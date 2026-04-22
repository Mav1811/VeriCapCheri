package cheri_cc_pkg;

  // Count index of most-significant 1 bit (0..63). If x==0, returns 0.
  function automatic int unsigned msb_index64(input logic [63:0] x);
    int unsigned i;
    begin
      msb_index64 = 0;
      for (i = 0; i < 64; i++) begin
        if (x[i]) msb_index64 = i;
      end
    end
  endfunction

  // Ceiling divide by 2^E: ceil(x / 2^E) = (x + (2^E - 1)) >> E for E>0
  function automatic logic [63:0] ceil_shr_pow2(input logic [63:0] x,
                                                input int unsigned E);
    logic [63:0] add;
    begin
      if (E == 0) begin
        ceil_shr_pow2 = x;
      end else begin
        add = (64'h1 << E) - 1;
        ceil_shr_pow2 = (x + add) >> E;
      end
    end
  endfunction

  // Floor divide by 2^E: floor(x / 2^E) = x >> E
  function automatic logic [63:0] floor_shr_pow2(input logic [63:0] x,
                                                 input int unsigned E);
    begin
      floor_shr_pow2 = (E == 0) ? x : (x >> E);
    end
  endfunction

  // Main encoder: returns 128-bit CHERI-128 CC capability value
  // Inputs:
  //   base:   desired base (64-bit)
  //   addr:   current cursor/address (64-bit). Commonly == base.
  //   length: requested length (64-bit). top = base + length
  //   perms:  15-bit permission field
  //
  // Output:
  //   128-bit packed capability (tag handled separately in real CHERI).
  function automatic logic [127:0] cc_cheri128_encode(
      input logic [63:0] base,
      input logic [63:0] addr,
      input logic [63:0] length,
      input logic [14:0] perms
  );
    logic [63:0] top;
    int unsigned E;          // exponent
    logic        IE;         // internal exponent flag
    logic        s_or_Lmsb;  // we set sealed=0; use this bit as Lmsb/exp-msb
    logic [63:0] Bfull, Tfull;  // full (unbounded) shifted values before slicing
    logic [20:0] B21;        // B mantissa (21 bits)
    logic [18:0] T19;        // T mantissa (19 bits)
    logic [17:0] B_hi;       // B[20:3]
    logic [15:0] T_hi;       // T[18:3]
    logic [2:0]  BE, TE;     // low bits (or exponent bits when IE=1)

    logic [127:0] cap;

    begin
      // Basic sanity: length==0 is legal but boring; still encode something.
      top = base + length;

      // --- Step 1: derive exponent E from length magnitude (CC "normal form") ---
      // Paper derives E from msb of length (for CHERI-64 shown as msb(l[31:8])).
      // Here we generalize to 64-bit length:
      //   choose E so that shifting by E gives you mantissas that fit.
      // We need B in 21 bits and T in 19 bits. The "fit" constraint is:
      //   Bfull < 2^21 and Tfull < 2^19 after shifting.
      //
      // Start with an E based on length msb, then bump until it fits.
      E = 0;
      if (length != 0) begin
        // heuristic starting point: msb_index64(length) - 18
        // because T has 19 bits (approx. needs length/2^E to fit in 19 bits)
        int unsigned msb;
        msb = msb_index64(length);
        if (msb > 18) E = msb - 18;
        else          E = 0;
      end

      // Increase E until mantissas fit in their bitwidths.
      // Use rounded top (ceil) to be safe, as per CC encoding discussion. :contentReference[oaicite:7]{index=7}
      while (1) begin
        Bfull = floor_shr_pow2(base, E);
        Tfull = ceil_shr_pow2(top,  E);

        if ((Bfull < (64'h1 << 21)) && (Tfull < (64'h1 << 19))) begin
          break;
        end
        E = E + 1;
        if (E > 63) begin
          // give up: saturate, still return something deterministic
          E = 63;
          Bfull = 0;
          Tfull = 0;
          break;
        end
      end

      // --- Step 2: decide IE ---
      // CC uses IE to embed exponent bits when E>0; otherwise E=0 and keep precision. :contentReference[oaicite:8]{index=8}
      IE = (E != 0);

      // --- Step 3: form mantissas ---
      // Truncate to required widths.
      B21 = Bfull[20:0];
      T19 = Tfull[18:0];

      // Split into hi/lo pieces for packing.
      B_hi = B21[20:3];
      T_hi = T19[18:3];

      if (!IE) begin
        // E==0: keep low bits of mantissas in BE/TE
        BE = B21[2:0];
        TE = T19[2:0];

        // Use s_or_Lmsb as "Lmsb" bit (like L[7] in CHERI-64 case). :contentReference[oaicite:9]{index=9}
        // We set it to msb(length) for compatibility with the idea; simplest is 0/1:
        s_or_Lmsb = (length[63:0] != 0) ? length[msb_index64(length)] : 1'b0;

      end else begin
        // IE==1: embed exponent into {s_or_Lmsb, TE, BE}.
        // We use 7 bits: E[6] in s_or_Lmsb, E[5:3] in TE, E[2:0] in BE.
        // This mirrors CHERI-64 concept where E = {L7, TE, BE}. 
        s_or_Lmsb = E[6];
        TE        = E[5:3];
        BE        = E[2:0];

        // Since we "spent" low bits of mantissas on exponent, we effectively lose some precision.
        // In a strict implementation you'd ensure B21[2:0]==0 and T19[2:0]==0 when IE=1,
        // via extra rounding. If you want that, enforce it here:
        // (Uncomment if you want stricter alignment.)
        // B_hi = (B21 & ~21'h7) [20:3];
        // T_hi = (T19 & ~19'h7) [18:3];
      end

      // --- Step 4: pack the 128-bit value ---
      cap = '0;
      cap[127:113] = perms;
      cap[112]     = IE;
      cap[111]     = s_or_Lmsb;
      cap[110:95]  = T_hi;
      cap[94:92]   = TE;
      cap[91:74]   = B_hi;
      cap[73:71]   = BE;
      cap[64:1]    = addr;     // cursor/address stored explicitly in CHERI-128. :contentReference[oaicite:11]{index=11}
      cap[0]    = 1'b1;
      cc_cheri128_encode = cap;
    end
  endfunction

endpackage