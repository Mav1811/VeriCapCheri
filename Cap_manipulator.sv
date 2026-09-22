// Cap_manipulator.sv
// SystemVerilog package with all get/set functions for the 161-bit CHERI
// internal capability representation (128-bit compressed CHERI format).
//
// Internal 161-bit layout [160:0]:
//   [160]     : tag (valid) bit
//   [159:96]  : address (cursor), 64 bits
//   [95:82]   : addrBits (low 14 bits of address >> E), 14 bits
//   [81:78]   : soft permissions, 4 bits
//   [77:66]   : hard permissions, 12 bits
//   [65]      : flags, 1 bit
//   [64:63]   : internal encoding bits
//   [62:45]   : otype / kind field, 18 bits
//   [44]      : internal exponent flag
//   [43:38]   : E (exponent / mantissa shift), 6 bits
//   [37:24]   : top mantissa bits, 14 bits
//   [23:10]   : base mantissa bits, 14 bits
//   [9:7]     : repBound (representability bound), 3 bits
//   [6:5]     : top/base lt repBound correction flags
//   [4]       : addr lt repBound correction flag
//   [3:0]     : fine correction bits
//
// SET functions that return 162 bits return {exact, tag, cap[159:0]}:
//   bit[161] = exact  (operation was representable)
//   bit[160] = tag    (original tag, preserved only when exact)
//   bits[159:0] = the new 160-bit capability body
//
// Usage:
//   import cap_pkg::*;
//   logic [160:0] my_cap;
//   logic [63:0]  addr;
//   addr   = getAddr(my_cap);
//   my_cap = setAddr(my_cap, addr)[160:0];  // [161] = exact flag

`ifndef CAP_MANIPULATOR_SV
`define CAP_MANIPULATOR_SV

package cap_pkg;

  // ==========================================================================
  // GET functions — extract fields from a 161-bit capability
  // ==========================================================================

  function automatic logic isValidCap(input logic [160:0] cap);
    return cap[160];
  endfunction

  function automatic logic [63:0] getAddr(input logic [160:0] cap);
    return cap[159:96];
  endfunction

  function automatic logic getFlags(input logic [160:0] cap);
    return cap[65];
  endfunction

  function automatic logic [11:0] getHardPerms(input logic [160:0] cap);
    return cap[77:66];
  endfunction

  function automatic logic [15:0] getSoftPerms(input logic [160:0] cap);
    return {12'd0, cap[81:78]};
  endfunction

  // All permissions [30:0] = {12'd0, softperms[3:0], 3'd0, hardperms[11:0]}
  function automatic logic [30:0] getPerms(input logic [160:0] cap);
    return {12'd0, cap[81:78], 3'h0, cap[77:66]};
  endfunction

  // Kind [20:0] = {kind_type[2:0], otype_raw[17:0]}
  // kind_type: 0=SENTRY, 1=RES1, 2=RES0, 3=INDIRECT, 4=SEALED_WITH_TYPE
  function automatic logic [20:0] getKind(input logic [160:0] cap);
    logic [2:0] kind_type;
    case (cap[62:45])
      18'd262140: kind_type = 3'd3;
      18'd262141: kind_type = 3'd2;
      18'd262142: kind_type = 3'd1;
      18'd262143: kind_type = 3'd0;
      default:    kind_type = 3'd4;
    endcase
    return {kind_type, cap[62:45]};
  endfunction

  function automatic logic [63:0] getBase(input logic [160:0] cap);
    logic [15:0] x;
    logic [49:0] mask;
    logic [63:0] addBase;
    x       = {cap[1:0], cap[23:10]};
    mask    = 50'h3FFFFFFFFFFFF << cap[43:38];
    addBase = {{48{x[15]}}, x} << cap[43:38];
    return {cap[159:110] & mask, 14'd0} + addBase;
  endfunction

  function automatic logic [64:0] getTop(input logic [160:0] cap);
    logic [64:0] addTop, ret, result;
    logic [50:0] mask;
    logic [49:0] cap_hi_plus_sext;
    logic [15:0] x;
    logic [1:0]  cap_bits_1_0;
    logic        correction_bit;
    logic [1:0]  diff;

    cap_bits_1_0     = cap[1:0];
    x                = {cap[3:2], cap[37:24]};
    mask             = 51'h7FFFFFFFFFFFF << cap[43:38];
    addTop           = {{49{x[15]}}, x} << cap[43:38];
    ret              = {({1'b0, cap[159:110]} & mask), 14'd0} + addTop;

    cap_hi_plus_sext = cap[159:110] +
                       ({{48{cap_bits_1_0[1]}}, cap_bits_1_0} << cap[43:38]);

    correction_bit = (cap[43:38] == 6'd50) ? cap[23] : cap_hi_plus_sext[49];
    diff           = ret[64:63] - {1'b0, correction_bit};
    result         = (cap[43:38] < 6'd51 && diff > 2'd1) ?
                     {~ret[64], ret[63:0]} : ret;
    return result;
  endfunction

  function automatic logic [64:0] getLength(input logic [160:0] cap);
    logic [15:0] base_m, top_m, diff_m;
    logic [64:0] length;
    base_m  = {cap[1:0], cap[23:10]};
    top_m   = {cap[3:2], cap[37:24]};
    diff_m  = top_m - base_m;
    length  = {49'd0, diff_m} << cap[43:38];
    return (cap[43:38] < 6'd52) ? length : 65'h1FFFFFFFFFFFFFFFF;
  endfunction

  function automatic logic [63:0] getOffset(input logic [160:0] cap);
    logic [63:0] addrLSB, x72, x74, x193, y192;
    logic [15:0] base_m, offset_m;
    base_m  = {cap[1:0], cap[23:10]};
    offset_m = {2'b0, cap[95:82]} - base_m;
    x193    = 64'hFFFFFFFFFFFFFFFF << cap[43:38];
    y192    = ~x193;
    x74     = {{48{offset_m[15]}}, offset_m};
    x72     = x74 << cap[43:38];
    addrLSB = cap[159:96] & y192;
    return x72 | addrLSB;
  endfunction

  // isInBounds: checks whether the cursor is within [base, top)
  // isTopIncluded=1 checks [base, top] (inclusive top)
  function automatic logic isInBounds(input logic [160:0] cap,
                                      input logic isTopIncluded);
    logic cond_top, cond_base;
    if (cap[6] == cap[4])
      cond_top = isTopIncluded ? (cap[95:82] <= cap[37:24])
                               : (cap[95:82] <  cap[37:24]);
    else
      cond_top = cap[6];

    cond_base = (cap[5] == cap[4]) ? (cap[95:82] >= cap[23:10]) : cap[4];
    return cond_top && cond_base;
  endfunction

  // ==========================================================================
  // Constant capabilities
  // ==========================================================================

  function automatic logic [160:0] nullCap();
    return 161'h00000000000000000000000007FFFFD10000003F0;
  endfunction

  function automatic logic [160:0] almightyCap();
    return 161'h100000000000000000003FFFC7FFFFD10000003F0;
  endfunction

  // Null capability with a specific address embedded (tag=0)
  function automatic logic [160:0] nullWithAddr(input logic [63:0] addr);
    logic [13:0] res_addrBits;
    res_addrBits = {2'd0, addr[63:52]};
    return {1'b0, addr, res_addrBits, 82'h000007FFFFD10000003F0};
  endfunction

  // ==========================================================================
  // SET functions — return updated 161-bit capability
  // ==========================================================================

  function automatic logic [160:0] setValidCap(input logic [160:0] cap,
                                                input logic valid);
    return {valid, cap[159:0]};
  endfunction

  function automatic logic [160:0] setFlags(input logic [160:0] cap,
                                             input logic flags);
    return {cap[160:66], flags, cap[64:0]};
  endfunction

  function automatic logic [160:0] setHardPerms(input logic [160:0] cap,
                                                 input logic [11:0] hardperms);
    return {cap[160:78], hardperms, cap[65:0]};
  endfunction

  function automatic logic [160:0] setSoftPerms(input logic [160:0] cap,
                                                 input logic [15:0] softperms);
    return {cap[160:82], softperms[3:0], cap[77:0]};
  endfunction

  // perms[30:0] = {12'd0, softperms[3:0], 3'd0, hardperms[11:0]}
  function automatic logic [160:0] setPerms(input logic [160:0] cap,
                                             input logic [30:0] perms);
    return {cap[160:82], perms[18:15], perms[11:0], cap[65:0]};
  endfunction

  // kind[20:0] = {kind_type[2:0], otype_raw[17:0]}
  function automatic logic [160:0] setKind(input logic [160:0] cap,
                                            input logic [20:0] kind);
    logic [17:0] kind_bits;
    case (kind[20:18])
      3'd0:    kind_bits = 18'd262143;
      3'd1:    kind_bits = 18'd262142;
      3'd2:    kind_bits = 18'd262141;
      3'd3:    kind_bits = 18'd262140;
      default: kind_bits = kind[17:0];
    endcase
    return {cap[160:63], kind_bits, cap[44:0]};
  endfunction

  // ==========================================================================
  // SET functions — return {exact[161], tag[160], newCap[159:0]} = 162 bits
  //   bit[161]: exact  — the operation was representable without loss
  //   bit[160]: tag    — preserved from input, only valid when exact=1
  //   bits[159:0]: the new capability body
  // ==========================================================================

  // Set the cursor address. Tag is cleared if the new address is
  // not representable within the current bounds.
  function automatic logic [161:0] setAddr(input logic [160:0] cap,
                                            input logic [63:0]  addr);
    logic [63:0] x94;
    logic [49:0] deltaAddrHi, deltaAddrUpper, mask;
    logic [2:0]  repBound;
    logic [1:0]  x77;
    logic        exact;
    logic        addr_srl_lt_rep, cap_top_lt_rep, cap_bot_lt_rep;
    logic [3:0]  low4;

    repBound        = cap[23:21] - 3'b001;
    x94             = addr >> cap[43:38];
    mask            = 50'h3FFFFFFFFFFFF << cap[43:38];
    deltaAddrUpper  = (addr[63:14] & mask) - (cap[159:110] & mask);
    x77             = {1'b0, x94[13:11] < cap[9:7]} - {1'b0, cap[4]};
    deltaAddrHi     = {{48{x77[1]}}, x77} << cap[43:38];
    exact           = (deltaAddrHi == deltaAddrUpper);

    addr_srl_lt_rep = x94[13:11]  < repBound;
    cap_top_lt_rep  = cap[37:35]  < repBound;
    cap_bot_lt_rep  = cap[23:21]  < repBound;

    low4 = {
      (cap_top_lt_rep == addr_srl_lt_rep) ? 2'd0 :
        (cap_top_lt_rep ? 2'd1 : 2'd3),
      (cap_bot_lt_rep == addr_srl_lt_rep) ? 2'd0 :
        (cap_bot_lt_rep ? 2'd1 : 2'd3)
    };

    return {exact,
            exact && cap[160],
            addr,
            x94[13:0],
            cap[81:10],
            repBound,
            cap_top_lt_rep,
            cap_bot_lt_rep,
            addr_srl_lt_rep,
            low4};
  endfunction

  // Set offset absolutely (new_addr = base + offset).
  // Tag cleared if offset places cursor out of representable range.
  function automatic logic [161:0] setOffset(input logic [160:0] cap,
                                              input logic [63:0]  offset);
    logic [63:0] addBase, result_addr, x701, x855;
    logic [49:0] highOffsetBits, mask, signBits, x100;
    logic [13:0] newAddrBits, result_addrBits, toBoundsM1, toBounds;
    logic [3:0]  low4;
    logic [2:0]  repBound;
    logic [1:0]  mask773;
    logic        exact, in_range, res_lt_rep, top_lt_rep, bot_lt_rep;

    repBound       = cap[23:21] - 3'b001;
    mask           = 50'h3FFFFFFFFFFFF << cap[43:38];
    signBits       = {50{offset[63]}};
    x100           = offset[63:14] ^ signBits;
    highOffsetBits = x100 & mask;
    x701           = offset >> cap[43:38];
    toBoundsM1     = {3'b110, ~cap[20:10]};
    toBounds       = 14'd14336 - {3'b0, cap[20:10]};
    in_range       = offset[63] ? (x701[13:0] >= toBounds)
                                : (x701[13:0] <= toBoundsM1);
    exact          = (highOffsetBits == 50'd0 && in_range) ||
                     (cap[43:38] >= 6'd50);

    case (cap[43:38])
      6'd51:   mask773 = 2'b01;
      6'd52:   mask773 = 2'b00;
      default: mask773 = 2'b11;
    endcase

    newAddrBits     = cap[23:10] + x701[13:0];
    result_addrBits = {mask773, 12'd4095} & newAddrBits;
    x855            = {cap[1:0], cap[23:10]};
    addBase         = {{48{x855[15]}}, x855} << cap[43:38];
    result_addr     = {cap[159:110] & mask, 14'd0} + addBase + offset;

    res_lt_rep = result_addrBits[13:11] < repBound;
    top_lt_rep = cap[37:35] < repBound;
    bot_lt_rep = cap[23:21] < repBound;

    low4 = {
      (top_lt_rep == res_lt_rep) ? 2'd0 : (top_lt_rep ? 2'd1 : 2'd3),
      (bot_lt_rep == res_lt_rep) ? 2'd0 : (bot_lt_rep ? 2'd1 : 2'd3)
    };

    return {exact,
            exact && cap[160],
            result_addr,
            result_addrBits,
            cap[81:10],
            repBound,
            top_lt_rep,
            bot_lt_rep,
            res_lt_rep,
            low4};
  endfunction

  // Increment cursor by inc (new_addr = cursor + inc).
  function automatic logic [161:0] incOffset(input logic [160:0] cap,
                                              input logic [63:0]  inc);
    logic [63:0] result_addr, x701, x807;
    logic [49:0] highBitsFilter, highOffsetBits, signBits, x100;
    logic [13:0] repBoundBits, toBoundsM1, toBounds;
    logic [3:0]  low4;
    logic [2:0]  repBound;
    logic        exact, in_range, res_lt_rep, top_lt_rep, bot_lt_rep;

    repBound       = cap[23:21] - 3'b001;
    highBitsFilter = 50'h3FFFFFFFFFFFF << cap[43:38];
    signBits       = {50{inc[63]}};
    x100           = inc[63:14] ^ signBits;
    highOffsetBits = x100 & highBitsFilter;
    x701           = inc >> cap[43:38];
    repBoundBits   = {cap[9:7], 11'd0};
    toBoundsM1     = repBoundBits + ~cap[95:82];
    toBounds       = repBoundBits - cap[95:82];
    in_range       = inc[63] ?
                     (x701[13:0] >= toBounds && repBoundBits != cap[95:82]) :
                     (x701[13:0] < toBoundsM1);
    exact          = (highOffsetBits == 50'd0 && in_range) ||
                     (cap[43:38] >= 6'd50);

    result_addr = cap[159:96] + inc;
    x807        = result_addr >> cap[43:38];

    res_lt_rep = x807[13:11]  < repBound;
    top_lt_rep = cap[37:35]   < repBound;
    bot_lt_rep = cap[23:21]   < repBound;

    low4 = {
      (top_lt_rep == res_lt_rep) ? 2'd0 : (top_lt_rep ? 2'd1 : 2'd3),
      (bot_lt_rep == res_lt_rep) ? 2'd0 : (bot_lt_rep ? 2'd1 : 2'd3)
    };

    return {exact,
            exact && cap[160],
            result_addr,
            x807[13:0],
            cap[81:10],
            repBound,
            top_lt_rep,
            bot_lt_rep,
            res_lt_rep,
            low4};
  endfunction

  // Generalised offset modification.
  // doInc=1: increment (new_addr = cursor + offset)
  // doInc=0: set absolute (new_addr = base + offset)
  function automatic logic [161:0] modifyOffset(input logic [160:0] cap,
                                                 input logic [63:0]  offset,
                                                 input logic         doInc);
    logic [63:0] addBase, pointer, result_addr, ret_addr, x704, x891, x950;
    logic [49:0] highOffsetBits, mask, signBits, x101;
    logic [13:0] newAddrBits, repBoundBits, result_addrBits;
    logic [13:0] toBoundsM1_A, toBoundsM1_B, toBoundsM1;
    logic [13:0] toBounds_A,   toBounds_B,   toBounds;
    logic [3:0]  low4;
    logic [2:0]  repBound;
    logic [1:0]  mask798;
    logic        exact, in_range, res_lt_rep, top_lt_rep, bot_lt_rep;

    repBound       = cap[23:21] - 3'b001;
    mask           = 50'h3FFFFFFFFFFFF << cap[43:38];
    signBits       = {50{offset[63]}};
    x101           = offset[63:14] ^ signBits;
    highOffsetBits = x101 & mask;
    x704           = offset >> cap[43:38];
    repBoundBits   = {cap[9:7], 11'd0};
    toBoundsM1_A   = {3'b110, ~cap[20:10]};
    toBoundsM1_B   = repBoundBits + ~cap[95:82];
    toBoundsM1     = doInc ? toBoundsM1_B : toBoundsM1_A;
    toBounds_A     = 14'd14336 - {3'b0, cap[20:10]};
    toBounds_B     = repBoundBits - cap[95:82];
    toBounds       = doInc ? toBounds_B : toBounds_A;

    if (offset[63])
      in_range = (x704[13:0] >= toBounds) &&
                 (!doInc || (repBoundBits != cap[95:82]));
    else
      in_range = doInc ? (x704[13:0] <  toBoundsM1)
                       : (x704[13:0] <= toBoundsM1);

    exact = (highOffsetBits == 50'd0 && in_range) || (cap[43:38] >= 6'd50);

    pointer = cap[159:96] + offset;

    case (cap[43:38])
      6'd51:   mask798 = 2'b01;
      6'd52:   mask798 = 2'b00;
      default: mask798 = 2'b11;
    endcase

    newAddrBits     = cap[23:10] + x704[13:0];
    x891            = {cap[1:0], cap[23:10]};
    addBase         = {{48{x891[15]}}, x891} << cap[43:38];
    ret_addr        = {cap[159:110] & mask, 14'd0} + addBase + offset;
    result_addr     = doInc ? pointer : ret_addr;
    x950            = pointer >> cap[43:38];
    result_addrBits = doInc ? x950[13:0] : ({mask798, 12'd4095} & newAddrBits);

    res_lt_rep = result_addrBits[13:11] < repBound;
    top_lt_rep = cap[37:35] < repBound;
    bot_lt_rep = cap[23:21] < repBound;

    low4 = {
      (top_lt_rep == res_lt_rep) ? 2'd0 : (top_lt_rep ? 2'd1 : 2'd3),
      (bot_lt_rep == res_lt_rep) ? 2'd0 : (bot_lt_rep ? 2'd1 : 2'd3)
    };

    return {exact,
            exact && cap[160],
            result_addr,
            result_addrBits,
            cap[81:10],
            repBound,
            top_lt_rep,
            bot_lt_rep,
            res_lt_rep,
            low4};
  endfunction

  // Set bounds: new cap covers [cursor, cursor + length).
  // Bounds may be rounded outward to the nearest representable interval.
  // bit[161]=exact means no rounding occurred.
  function automatic logic [161:0] setBounds(input logic [160:0] cap,
                                              input logic [63:0]  length);
    // Fill highest set bit downward to build alignment masks
    logic [63:0] d4, d7, d10, d13, d16, d19;
    logic [65:0] lmaskLor, lmaskLo, mwLsbMask;
    logic [65:0] base66, len66, top66, x8717, x8832, x9013, y8718;
    logic [63:0] len_AND_inv;
    logic [27:0] packed_bounds;
    logic [14:0] x9052;
    logic [13:0] result_addrBits, baseBits, topBits8817, topBits9044, topBits8821;
    logic [13:0] x9088, x9091;
    logic [5:0]  E_raw, E_final;
    logic [3:0]  low4;
    logic [2:0]  repBound;
    logic        exact, t_lt_rep, b_lt_rep, a_lt_rep;
    logic        NOT_carry_d203, rnd_d323, rnd_d334, noRnd_d186;
    logic        addr_exact_d179;
    logic        need_inc_d204, need_inc_d210, need_inc_d211;
    logic        len_big; // |length[63:12]

    // Propagate highest bit of length rightward (fill below MSB)
    d4  = length       | {1'b0,  length[63:1]};
    d7  = d4           | {2'b0,  d4[63:2]};
    d10 = d7           | {4'b0,  d7[63:4]};
    d13 = d10          | {8'b0,  d10[63:8]};
    d16 = d13          | {16'b0, d13[63:16]};
    d19 = d16          | {32'b0, d16[63:32]};

    // Alignment masks (66-bit, matching the 66-bit base/top arithmetic)
    lmaskLor  = {12'd0, d19[63:10]};         // mask at bit granularity of 2^E
    lmaskLo   = {11'd0, d19[63:9]};          // one bit finer
    mwLsbMask = lmaskLor ^ lmaskLo;          // single-bit mask at 2^(E-1) boundary

    // Base and top in 66-bit extended arithmetic
    base66 = {2'b0, cap[159:96]};
    len66  = {2'b0, length};
    top66  = base66 + len66;

    // Carry check: does adding length to base produce a carry at the boundary?
    x8717          = mwLsbMask & base66;
    y8718          = mwLsbMask & len66;
    NOT_carry_d203 = (mwLsbMask & top66) != (x8717 ^ y8718);

    // len_big: any bit above bit 11 is set (bounds need exponent > 0)
    len_big = |length[63:12];

    // Conditions controlling upward rounding of top
    rnd_d323    = ((top66 & lmaskLor) != 66'd0) && len_big;
    rnd_d334    = ((top66 & lmaskLo)  != 66'd0) && len_big;
    noRnd_d186  = ((top66 & lmaskLor) == 66'd0) || !len_big;

    // Exactness of compressed representation relative to cursor
    addr_exact_d179 = ((cap[159:96] & {10'd0, d19[63:10]}) == 64'd0) || !len_big;

    // E_raw = MSB position of length above bit 12, computed as priority encode
    E_raw =
      length[63] ? 6'd51 : length[62] ? 6'd50 : length[61] ? 6'd49 :
      length[60] ? 6'd48 : length[59] ? 6'd47 : length[58] ? 6'd46 :
      length[57] ? 6'd45 : length[56] ? 6'd44 : length[55] ? 6'd43 :
      length[54] ? 6'd42 : length[53] ? 6'd41 : length[52] ? 6'd40 :
      length[51] ? 6'd39 : length[50] ? 6'd38 : length[49] ? 6'd37 :
      length[48] ? 6'd36 : length[47] ? 6'd35 : length[46] ? 6'd34 :
      length[45] ? 6'd33 : length[44] ? 6'd32 : length[43] ? 6'd31 :
      length[42] ? 6'd30 : length[41] ? 6'd29 : length[40] ? 6'd28 :
      length[39] ? 6'd27 : length[38] ? 6'd26 : length[37] ? 6'd25 :
      length[36] ? 6'd24 : length[35] ? 6'd23 : length[34] ? 6'd22 :
      length[33] ? 6'd21 : length[32] ? 6'd20 : length[31] ? 6'd19 :
      length[30] ? 6'd18 : length[29] ? 6'd17 : length[28] ? 6'd16 :
      length[27] ? 6'd15 : length[26] ? 6'd14 : length[25] ? 6'd13 :
      length[24] ? 6'd12 : length[23] ? 6'd11 : length[22] ? 6'd10 :
      length[21] ? 6'd9  : length[20] ? 6'd8  : length[19] ? 6'd7  :
      length[18] ? 6'd6  : length[17] ? 6'd5  : length[16] ? 6'd4  :
      length[15] ? 6'd3  : length[14] ? 6'd2  : length[13] ? 6'd1  : 6'd0;

    // Check whether rounding increments E by 1
    len_AND_inv   = length & {10'd1023, ~d19[63:10]};
    need_inc_d204 = (len_AND_inv == (d19 ^ {9'd0,  d19[63:9]}))  && NOT_carry_d203;
    need_inc_d210 = (len_AND_inv == (d19 ^ {10'd0, d19[63:10]})) &&
                    (NOT_carry_d203 || ((top66 & lmaskLor) != 66'd0));
    need_inc_d211 = (need_inc_d204 && ((top66 & lmaskLor) != 66'd0)) || need_inc_d210;
    E_final       = (need_inc_d211 && len_big) ? E_raw + 6'd1 : E_raw;

    // Shift base/top right by E to get mantissa bits
    x8832 = base66 >> E_raw;     // [65:0]
    x9013 = top66  >> E_raw;     // [65:0]
    x9052 = x9013[14:0] + 15'b000000000001000;  // top mantissa rounded up by 1 unit

    // Result address bits (base mantissa, possibly shifted by 1 more for rounding)
    result_addrBits = (need_inc_d211 && len_big) ? x8832[14:1] : x8832[13:0];

    // Base bits for packed format (aligned to 3-bit boundary)
    baseBits = {result_addrBits[13:3], 3'd0};

    // Top mantissa computations
    topBits9044  = rnd_d323 ? x9052[13:0]                         : x9013[13:0];
    topBits8821  = rnd_d334 ? (x9013[14:1] + 14'b00000000001000)  : x9013[14:1];
    topBits8817  = (need_inc_d211 && len_big) ? topBits8821 : topBits9044;

    // Select base/top mantissa for repBound computation
    x9088 = !len_big ? result_addrBits : baseBits;
    x9091 = !len_big ? topBits8817     : {topBits8817[13:3], 3'd0};
    repBound = x9088[13:11] - 3'b001;

    // Pack the 28-bit bounds field {topBits[13:0], baseBits[13:0]}
    packed_bounds = !len_big ?
      {topBits9044, x8832[13:0]} :
      {topBits8817[13:3], 3'd0, baseBits};

    // Correction flags
    t_lt_rep = x9091[13:11] < repBound;
    b_lt_rep = x9088[13:11] < repBound;
    a_lt_rep = result_addrBits[13:11] < repBound;

    low4 = {
      (t_lt_rep == a_lt_rep) ? 2'd0 : (t_lt_rep ? 2'd1 : 2'd3),
      (b_lt_rep == a_lt_rep) ? 2'd0 : (b_lt_rep ? 2'd1 : 2'd3)
    };

    exact = addr_exact_d179 && noRnd_d186;

    // Return 162-bit result:
    // {exact, cap[160:96], result_addrBits, cap[81:45], len_big,
    //  E_final, packed_bounds, repBound, t_lt_rep, b_lt_rep, a_lt_rep, low4}
    return {exact,
            cap[160:96],
            result_addrBits,
            cap[81:45],
            len_big,
            E_final,
            packed_bounds,
            repBound,
            t_lt_rep,
            b_lt_rep,
            a_lt_rep,
            low4};
  endfunction

  // ==========================================================================
  // Memory conversion functions
  // ==========================================================================

  // fromMem: convert 129-bit memory representation to 161-bit internal form.
  // mem_cap[128] = tag bit, mem_cap[127:0] = 128-bit compressed capability.
  function automatic logic [160:0] fromMem(input logic [128:0] mem_cap);
    logic [18:0] INV;
    logic [13:0] res_addrBits, x603, x583;
    logic [11:0] topBits512, b_top609;
    logic [13:0] b_base610;
    logic [5:0]  x423;
    logic [2:0]  tmp_expBotHalf, tmp_expTopHalf, repBound, tb661;
    logic [1:0]  carry_out514, impliedTopBits516, len_corr515, x600;
    logic [63:0] x385;
    logic [33:0] d40;
    logic        d47, d48, d50;
    logic [4:0]  d60;

    INV              = ~mem_cap[108:90];
    tmp_expBotHalf   = {~mem_cap[66], mem_cap[65:64]};
    tmp_expTopHalf   = {~mem_cap[80:79], mem_cap[78]};
    x423             = {tmp_expTopHalf, tmp_expBotHalf};   // E field (6 bits)

    b_base610        = {mem_cap[77:67], ~mem_cap[66], mem_cap[65:64]};
    b_top609         = {mem_cap[89:81], ~mem_cap[80:79], mem_cap[78]};

    topBits512       = INV[0] ? {mem_cap[89:81], 3'd0} : b_top609;
    x603             = INV[0] ? {mem_cap[77:67], 3'd0}  : b_base610;

    x385             = mem_cap[63:0] >> x423;
    res_addrBits     = INV[0] ? x385[13:0] : mem_cap[13:0];

    carry_out514     = (topBits512 < x603[11:0]) ? 2'b01 : 2'b00;
    x600             = x603[13:12] + carry_out514;
    len_corr515      = INV[0] ? 2'b01 : 2'b00;
    impliedTopBits516 = x600 + len_corr515;
    tb661            = {impliedTopBits516, topBits512[11]};
    repBound         = x603[13:11] - 3'b001;

    x583  = {impliedTopBits516, topBits512};   // [13:0]
    d40   = {INV[0] ? x423 : 6'd0, x583, x603}; // [33:0]

    d47  = tb661 < repBound;
    d48  = x603[13:11] < repBound;
    d50  = res_addrBits[13:11] < repBound;
    d60  = {d50,
            (d47 == d50) ? 2'd0 : (d47 ? 2'd1 : 2'd3),
            (d48 == d50) ? 2'd0 : (d48 ? 2'd1 : 2'd3)};

    return {mem_cap[128],        // [160]: tag
            mem_cap[63:0],       // [159:96]: address
            res_addrBits,        // [95:82]: addrBits
            mem_cap[127:112],    // [81:66]: softperms + hardperms
            mem_cap[109],        // [65]: flags
            mem_cap[111:110],    // [64:63]: encoding bits
            ~mem_cap[108:90],    // [62:44]: inverted internal bits
            d40,                 // [43:10]: E + top/base mantissa
            repBound,            // [9:7]
            d47,                 // [6]
            d48,                 // [5]
            d60};                // [4:0]
  endfunction

  // toMem: convert 161-bit internal capability to 129-bit memory form.
  // Returns mem_cap[128]=tag, mem_cap[127:0]=128-bit compressed capability.
  function automatic logic [128:0] toMem(input logic [160:0] cap);
    logic [25:0] d16;
    logic [127:0] x430;

    d16 = cap[44] ?
          {cap[35:27], cap[43:41], cap[23:13], cap[40:38]} :
          cap[35:10];

    x430 = {cap[81:66],          // [127:112]: softperms + hardperms
             cap[64:63],          // [111:110]
             cap[65],             // [109]: flags
             ~cap[62:44],         // [108:90]: inverted
             d16[25:17],          // [89:81]
             ~d16[16:15],         // [80:79]
             d16[14:3],           // [78:67]
             ~d16[2],             // [66]
             d16[1:0],            // [65:64]
             cap[159:96]};        // [63:0]: address

    return {cap[160], x430};
  endfunction

  // ==========================================================================
  // Validation helper
  // ==========================================================================

  // Returns 1 if checkType is a valid sealed object type (< 0x3FFFC = 262140)
  function automatic logic validAsType(input logic [160:0] dummy,
                                       input logic [63:0]  checkType);
    return checkType <= 64'd262139;
  endfunction

endpackage

`endif // CAP_MANIPULATOR_SV
