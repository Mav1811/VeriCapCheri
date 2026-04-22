package cheri_encoder_pkg;

  localparam int MW = 14;

  // Base low fragment decode in mkCapChecker_Top:
  //   logical = {~stored[2], stored[1], stored[0]}
  function automatic logic [2:0] encode_base_low3_for_checker(
    input logic [2:0] logical_bits
  );
    begin
      encode_base_low3_for_checker = {~logical_bits[2], logical_bits[1:0]};
    end
  endfunction

  // Top low fragment decode in mkCapChecker_Top:
  //   logical = {~stored[2], ~stored[1], stored[0]}
  function automatic logic [2:0] encode_top_low3_for_checker(
    input logic [2:0] logical_bits
  );
    begin
      encode_top_low3_for_checker = {~logical_bits[2], ~logical_bits[1], logical_bits[0]};
    end
  endfunction

  // Return index of most-significant 1 in a 52-bit vector.
  // If x == 0, returns 0.
  function automatic logic [5:0] msbindex52(input logic [51:0] x);
    integer i;
    begin
      msbindex52 = 6'd0;
      for (i = 0; i < 52; i = i + 1) begin
        if (x[i])
          msbindex52 = logic'(i[5:0]);
      end
    end
  endfunction

  // Returns 1 when any of the low n bits of x are set.
  // If n == 0, returns 0.
  function automatic logic any_low_bits_set_65(
    input logic [64:0] x,
    input logic [5:0]  n
  );
    logic [64:0] mask;
    begin
      if (n == 6'd0) begin
        any_low_bits_set_65 = 1'b0;
      end
      else begin
        mask = (65'd1 << n) - 65'd1;
        any_low_bits_set_65 = |(x & mask);
      end
    end
  endfunction

  // Documented CHERI Concentrate payload:
  // { perms[15:0], 3'b000, otype[17:0], ~IE,
  //   T_hi[8:0], enc(TE[2:0]), B_hi[10:0], enc(BE[2:0]), addr[63:0] }
  //
  // The lower bound/exponent fragments are not stored verbatim in
  // mkCapChecker_Top: bit[2] of each 3-bit fragment is inverted in the
  // management-bus representation, and the stored IE bit is active-low.
  //
  function automatic logic [127:0] encode_cheri_cap(
    input logic [63:0] base,
    input logic [63:0] addr,
    input logic [64:0] length,
    input logic [15:0] perms,
    input logic [17:0] otype
  );
    logic [64:0] b_ext;
    logic [64:0] l_ext;
    logic [64:0] t_ext;
    logic [51:0] l_slice;

    logic [5:0] E;
    logic       IE;

    logic [64:0] b_shifted;
    logic [64:0] t_shifted;

    // Internal working fields.
    // B_work and T_work are kept in the "stored-shape" style:
    //   IE=0 : low bits are actual bound bits
    //   IE=1 : low 3 bits are zeroed for arithmetic; exponent is packed later into BE/TE
    logic [14:0] B_work;
    logic [12:0] T_work;
    logic [14:0] L_work;

    // Stored fields
    logic [10:0] B_hi;
    logic [2:0]  BE;
    logic [8:0]  T_hi;
    logic [2:0]  TE;
    logic [2:0]  BE_enc;
    logic [2:0]  TE_enc;
    logic        IE_enc;

    integer iter;

    begin
      b_ext   = {1'b0, base};
      l_ext   = length;
      t_ext   = b_ext + l_ext;
      l_slice = l_ext[64:13];

      // E = 52 - CLZ(l[64:13])
      // For a nonzero 52-bit slice, this is msbindex + 1.
      if (l_slice == 52'd0)
        E = 6'd0;
      else
        E = msbindex52(l_slice) + 6'd1;

      // IE = 0 iff E == 0 and l[12] == 0
      IE = ((E == 6'd0) && (l_ext[12] == 1'b0)) ? 1'b0 : 1'b1;

      B_work = 15'd0;
      T_work = 13'd0;
      L_work = 15'd0;

      // Conservative iterative refinement, following the documented flow:
      // derive B/T, round T up if truncated bits were lost, and increase E if L[13] is set.
      for (iter = 0; iter < 8; iter = iter + 1) begin
        if (IE == 1'b0) begin
          // IE = 0 case:
          // B = b[14:0]
          // T = t[12:0]
          B_work = b_ext[14:0];
          T_work = t_ext[12:0];
        end
        else begin
          // IE = 1 case:
          // B = b[E+14:E+3]
          // T = t[E+12:E+3]
          //
          // To avoid non-constant packed ranges, shift first and slice with constant indices.
          b_shifted = b_ext >> (E + 6'd3);
          t_shifted = t_ext >> (E + 6'd3);

          // Keep the extracted bits in the upper portion, zero low 3 bits for arithmetic.
          // This mirrors the "lose three bits to store exponent" behavior.
          B_work = {b_shifted[11:0], 3'b000};
          T_work = {t_shifted[9:0],  3'b000};

          // If any discarded low bits of t were nonzero, round T upward.
          if (any_low_bits_set_65(t_ext, E + 6'd3))
            T_work = T_work + 13'd1;
        end

        // L = T - B ; if L[13] is set, increase E and retry.
        L_work = {2'b00, T_work} - B_work;

        if (L_work[13]) begin
          E  = E + 6'd1;
          IE = 1'b1;
        end
      end

      // Final stored fields
      if (IE == 1'b0) begin
        B_hi = B_work[13:3];
        BE   = B_work[2:0];

        T_hi = T_work[11:3];
        TE   = T_work[2:0];
      end
      else begin
        B_hi = B_work[13:3];
        BE   = E[2:0];

        T_hi = T_work[11:3];
        TE   = E[5:3];
      end

      BE_enc = encode_base_low3_for_checker(BE);
      TE_enc = encode_top_low3_for_checker(TE);
      IE_enc = ~IE;

      encode_cheri_cap = {
        perms,
        3'b000,
        otype,
        IE_enc,
        T_hi,
        TE_enc,
        B_hi,
        BE_enc,
        addr
      };
    end
  endfunction
  function automatic logic [128:0] wrap128_toMem_fn(
      input logic [160:0] cap);
    logic [127:0] x;
    logic [25:0]  tmp26;
    begin
      tmp26 = cap[44]
            ? { cap[35:27],
                cap[43:41],
                cap[23:13],
                cap[40:38] }
            : cap[35:10];

      x = { cap[81:66],
            cap[64:63],
            cap[65],
            ~cap[62:44],
            tmp26[25:17],
            ~tmp26[16:15],
            tmp26[14:3],
            ~tmp26[2],
            tmp26[1:0],
            cap[159:96] };

      wrap128_toMem_fn = { cap[160], x };
    end
  endfunction

endpackage
