module fv_capChecker
import cheri_encoder_pkg::*;
import cap_pkg::*;
(
    input  logic CLK,
    input  logic RST_N,

    // ========================================================
    // s_axi : AXI SLAVE INTERFACE (requests IN, responses OUT)
    // ========================================================

    // Write Address Channel
    input  logic [99:0] s_axi_aw_put_val,
    input  logic                EN_s_axi_aw_put,
    input logic                RDY_s_axi_aw_put,
    input logic                s_axi_aw_canPut,

    // Write Data Channel (73-bit payload)
    input  logic [72:0]         s_axi_w_put_val,
    input  logic                EN_s_axi_w_put,
    input logic                RDY_s_axi_w_put,
    input logic                s_axi_w_canPut,

    // Read Address Channel
    input  logic [96:0]         s_axi_ar_put_val,
    input  logic                EN_s_axi_ar_put,
    input logic                RDY_s_axi_ar_put,
    input logic                s_axi_ar_canPut,

    // Write Response Channel
    input logic                s_axi_b_canPeek,
    input logic [5:0]          s_axi_b_peek,
    input  logic                EN_s_axi_b_drop,
    input logic                RDY_s_axi_b_drop,

    // Read Response Channel (71-bit payload)
    input logic                s_axi_r_canPeek,
    input logic [70:0]         s_axi_r_peek,
    input  logic                EN_s_axi_r_drop,
    input logic                RDY_s_axi_r_drop,

    // ========================================================
    // m_axi : AXI MASTER INTERFACE (requests OUT, responses IN)
    // ========================================================

    // Write Address Channel
    input logic                m_axi_aw_canPeek,
    input logic [96:0]         m_axi_aw_peek,
    input  logic                EN_m_axi_aw_drop,
    input logic                RDY_m_axi_aw_drop,

    // Write Data Channel
    input logic                m_axi_w_canPeek,
    input logic [72:0]         m_axi_w_peek,
    input  logic                EN_m_axi_w_drop,
    input logic                RDY_m_axi_w_drop,

    // Read Address Channel
    input logic                m_axi_ar_canPeek,
    input logic [96:0]         m_axi_ar_peek,
    input  logic                EN_m_axi_ar_drop,
    input logic                RDY_m_axi_ar_drop,

    // Write Response Channel
    input  logic [5:0]          m_axi_b_put_val,
    input  logic                EN_m_axi_b_put,
    input logic                RDY_m_axi_b_put,
    input logic                m_axi_b_canPut,

    // Read Response Channel
    input  logic [70:0]         m_axi_r_put_val,
    input  logic                EN_m_axi_r_put,
    input logic                RDY_m_axi_r_put,
    input logic                m_axi_r_canPut,

    // ========================================================
    // mgmt_axi : MANAGEMENT / CONTROL INTERFACE
    // ========================================================

    // Write Address Channel
    input  logic [39:0]         mgmt_axi_aw_put_val,
    input  logic                EN_mgmt_axi_aw_put,
    input logic                RDY_mgmt_axi_aw_put,
    input logic                mgmt_axi_aw_canPut,

    // Write Data Channel
    input  logic [145:0]        mgmt_axi_w_put_val,
    input  logic                EN_mgmt_axi_w_put,
    input logic                RDY_mgmt_axi_w_put,
    input logic                mgmt_axi_w_canPut,

    // Read Address Channel
    input  logic [38:0]         mgmt_axi_ar_put_val,
    input  logic                EN_mgmt_axi_ar_put,
    input logic                RDY_mgmt_axi_ar_put,
    input logic                mgmt_axi_ar_canPut,

    // Write Response Channel
    input logic                mgmt_axi_b_canPeek,
    input logic [3:0]          mgmt_axi_b_peek,
    input  logic                EN_mgmt_axi_b_drop,
    input logic                RDY_mgmt_axi_b_drop,

    // Read Response Channel
    input logic                mgmt_axi_r_canPeek,
    input logic [133:0]        mgmt_axi_r_peek,
    input  logic                EN_mgmt_axi_r_drop,
    input logic                RDY_mgmt_axi_r_drop
);
  logic  [160 : 0] allmighty_cap = 161'h100000000000000000003FFFC7FFFFD10000003F0 ;
  //logic  [128 : 0] wrapped_mem_cap;

    // ========================================================
    // No logic here ? properties go below
    // ========================================================


function automatic logic [99:0] set_s_axi_aw_put_val(
  input logic [63:0] val,
  input logic [2:0]  cap
);
  logic[99:0] s_aw;   
  s_aw = {4'b0000, val, 8'h00, 3'b000, 18'd0, cap}; // {xxxx, val , burst len, transfer size, xx, cap index}
  return s_aw;
endfunction

// Read-address beat builder (97 bits). NOTE: unlike the AW beat, the AR beat
// carries NO cap-index field (that missing 3-bit field is exactly why AW is
// 100 bits and AR is 97). In this RTL the read path is hardwired to caps_0,
// so there is no index argument to pass.
//   layout: {xxxx, val, burst len, transfer size, xx}
//           [96:93] [92:29] [28:21]   [20:18]     [17:0]
function automatic logic [96:0] set_s_axi_ar_put_val(
  input logic [63:0] val
);
  logic [96:0] s_ar;
  s_ar = {4'b0000, val, 8'h00, 3'b000, 18'd0};
  return s_ar;
endfunction

//capability register select value
function automatic logic [39:0] Captable_select(
  input logic [2:0]  cap
);
    logic [39:0] aw;
    aw = {34'b1, cap, 3'b0};
    //aw[36:34] =  cap;
  return  aw;
endfunction
//capability register write value
function automatic logic [145:0] Captable_write(
  input logic [128:0]  cap_value
);
  logic [145:0] w;
  w = {cap_value[128:1], 17'b0, cap_value[0]};
  return  w;
endfunction

function automatic init_forwardWFF();
    return (mkCapChecker_Top.cap_checker_forwardWFF.empty_reg == 1'b0 &&
            mkCapChecker_Top.cap_checker_forwardWFF.full_reg  == 1'b1 &&
            mkCapChecker_Top.cap_checker_forwardWFF.data0_reg == 5'b0 &&
            mkCapChecker_Top.cap_checker_forwardWFF.data1_reg == 5'b0);
endfunction

function automatic init_forwardBFF();
    return (mkCapChecker_Top.cap_checker_forwardBFF.empty_reg == 1'b0 &&
            mkCapChecker_Top.cap_checker_forwardBFF.full_reg  == 1'b1 &&
            mkCapChecker_Top.cap_checker_forwardBFF.data0_reg == 1'b0 &&
            mkCapChecker_Top.cap_checker_forwardBFF.data1_reg == 1'b0);
endfunction

function automatic init_forwardRFF();
    return (mkCapChecker_Top.cap_checker_forwardRFF.empty_reg == 1'b0 &&
            mkCapChecker_Top.cap_checker_forwardRFF.full_reg  == 1'b1 &&
            mkCapChecker_Top.cap_checker_forwardRFF.data0_reg == 13'b0 &&
            mkCapChecker_Top.cap_checker_forwardRFF.data1_reg == 13'b0);
endfunction

//initial function

function automatic init_forward_fifos();
    return init_forwardWFF() &&
           init_forwardBFF() &&
           init_forwardRFF();
endfunction

// ============================================================
// Bounds decoding helpers
// Thin wrappers over the design-accurate cap_pkg (Cap_manipulator.sv) —
// the SystemVerilog conversion of cheri-cap-lib. cap_pkg::getBase /
// cap_pkg::getTop match mkCapChecker_Top.v bit-for-bit:
//   getBase  == base__h10981  (mkCapChecker_Top.v:1538)
//   getTop   == top__h10982   (mkCapChecker_Top.v:1632)
// getTop INCLUDES the CHERI Concentrate rollover/overflow correction
// (cap_hi_plus_sext / correction_bit / {~ret[64],ret[63:0]}) that a
// naive veriCHERI-style decode omits — omitting it makes `top` too
// large and lets an out-of-bounds address read as in-bounds.
// The whole 161-bit cap is passed in because the top correction needs
// the base mantissa/correction fields, so a per-field decode is unsafe.
// ============================================================

// 64-bit base bound of a 161-bit capability.
function automatic logic [63:0] get_base(input logic [160:0] cap);
  return cap_pkg::getBase(cap);
endfunction

// 65-bit top bound of a 161-bit capability (rollover-corrected).
function automatic logic [64:0] get_top(input logic [160:0] cap);
  return cap_pkg::getTop(cap);
endfunction

// Select the 161-bit capability entry addressed by the cap-index field,
// mirroring the DUT's caps[awuser] mux (case over cap_checker_caps_0..7).
// idx is the AXI write-address cap index s_aw[2:0].
function automatic logic [160:0] select_cap(input logic [2:0] idx);
  case (idx)
    3'd0:    return mkCapChecker_Top.cap_checker_caps_0;
    3'd1:    return mkCapChecker_Top.cap_checker_caps_1;
    3'd2:    return mkCapChecker_Top.cap_checker_caps_2;
    3'd3:    return mkCapChecker_Top.cap_checker_caps_3;
    3'd4:    return mkCapChecker_Top.cap_checker_caps_4;
    3'd5:    return mkCapChecker_Top.cap_checker_caps_5;
    3'd6:    return mkCapChecker_Top.cap_checker_caps_6;
    3'd7:    return mkCapChecker_Top.cap_checker_caps_7;
    default: return mkCapChecker_Top.cap_checker_caps_0;
  endcase
endfunction

// ============================================================
// is_address_protected
// Input: s_aw, the 100-bit AXI write-address beat (same layout that
//        set_s_axi_aw_put_val builds and that the DUT decodes):
//          s_aw[95:32] = access address
//          s_aw[31:24] = AxLEN  (burst length, beats-1)
//          s_aw[23:21] = AxSIZE (log2 bytes/beat)
// Returns 1 (PROTECTED) when the access has NO authority under cap0:
//   - cap0 is invalid (tag/valid bit cap0[160] clear), OR
//   - the access start is below base, OR
//   - the access END (addr + nBytes) exceeds top.
// Returns 0 only when cap0 is valid AND base <= addr AND addr+nBytes <= top.
// Pure function: reads cap0 only, no side effects. Size-aware, matching
// the DUT bounds check in mkCapChecker_Top.v.
// ============================================================
function automatic logic is_address_protected(input logic [99:0] s_aw);
  logic [160:0] cap0;        // selected internal 161-bit capability
  logic [2:0]   cap_idx;     // cap-index / pointer ID  (s_aw[2:0] = awuser)
  logic [63:0]  addr;        // access start address   (s_aw[95:32])
  logic [7:0]   axlen;       // AXI burst length       (s_aw[31:24])
  logic [2:0]   axsize;      // AXI transfer size      (s_aw[23:21])
  logic [15:0]  nbytes;      // access size in bytes = (AxLEN+1) << AxSIZE
  logic [63:0]  base_bound;  // decoded base   (cap0[159:110],[23:10],[1:0],[43:38])
  logic [64:0]  top_bound;   // decoded top    (cap0[37:24],[3:2] + rollover corr)
  logic [64:0]  access_top;  // exclusive end of access = addr + nbytes

  // Select the capability entry the request targets, exactly like the DUT
  // (caps[awuser]); the cap index is the low 3 bits of the AXI beat.
  cap_idx = s_aw[2:0];
  cap0    = select_cap(cap_idx);

  // Untagged/invalid capability conveys no authority -> always protected.
  // (Without this, garbage bounds of an invalid cap could read in-bounds.)
  if (!cap_pkg::isValidCap(cap0))   // cap0[160]
    return 1'b1;

  // Decode the AXI write-address beat.
  addr   = s_aw[95:32];
  axlen  = s_aw[31:24];
  axsize = s_aw[23:21];
  nbytes = ({8'd0, axlen} + 16'd1) << axsize;     // nBytes__h8730   (mkCapChecker_Top.v:1584)

  base_bound = get_base(cap0);
  top_bound  = get_top(cap0);
  access_top = {1'b0, addr} + {49'd0, nbytes};    // accessTopAddr__h8735 (mkCapChecker_Top.v:1505)

  // Protected when the access starts below base OR its end exceeds top.
  return (addr < base_bound) || (access_top > top_bound) && cap0[69];
endfunction

property write_pass;
//  non determinnent signals
    logic [2:0] cap_select;
    logic [63:0] cap_value;
    logic [63:0] cap_value_new;
    logic [63:0] access_value;
    logic [63:0] base_value;
    logic [64:0] length_value;
    logic [15:0] perms;
    logic [17:0] otype;
    logic [128:0] encoded_cap;
    //logic [63:0] cap_send;

    ##0 (1'b1, perms = '1)
    ##0 (1'b1, otype = '0)
    ##0 (1'b1, cap_value = 64'h0000_4000_0000_1040)
    ##0 (1'b1, base_value = 64'h0000_4000_0000_1000)
    ##0 (1'b1, length_value = 65'h0_0000_0000_0000_0200)
    ##0 (1'b1, encoded_cap = {encode_cheri_cap(base_value,cap_value,length_value,perms,otype), 1'b1})
    ##0 (1'b1, cap_select = 3'b000)
    // //##0 (1'b1, access_value = $anyconst)
    // ##0 (access_value >= base_value)
    // ##0 ({1'b1,access_value} <({1'b0,base_value} + length_value))

    // temporal behaviorwrite_capregs
    //##0  !EN_s_axi_aw_put
    //init_forward_fifos()
    ##1 mkCapChecker_Top.cap_checker_caps_0 ==  allmighty_cap  && //!EN_mgmt_axi_w_put && !EN_s_axi_aw_put && !EN_s_axi_w_put  //Captable_write(encoded_cap)
       EN_s_axi_aw_put && s_axi_aw_put_val == set_s_axi_aw_put_val(cap_value, cap_select) && !EN_s_axi_w_put  
    //##1  !EN_s_axi_aw_put 
    |->   
    mkCapChecker_Top.SEL_ARR_cap_checker_caps_0_40_BIT_160_90_cap_c_ETC___d490;
     //m_axi_aw_canPeek;
endproperty
// ============================================================
// ORIGINAL fv_capchecker.sv — preserved for reference
// (property and assert as first provided, before any edits)
// ============================================================
//
property mngmt_input;
//  non determinnent signals
    logic [2:0] cap_select;
    logic [63:0] cap_value;
    logic [63:0] access_value;
    logic [63:0] base_value;
    logic [64:0] length_value;
    logic [15:0] perms;
    logic [17:0] otype;
    logic [128:0] encoded_cap;
    //logic [63:0] cap_send;

    ##0 (1'b1, perms = '1)
    ##0 (1'b1, otype = '0)
    ##0 (1'b1, cap_value = 64'h0000_4000_0000_1040)
    ##0 (1'b1, base_value = 64'h0000_4000_0000_1000)
    ##0 (1'b1, length_value = 65'h0_0000_0000_0000_0200)
    ##0 (1'b1, encoded_cap = {encode_cheri_cap(base_value,cap_value,length_value,perms,otype), 1'b1})
    ##0 (1'b1, cap_select = 3'b000)
    // //##0 (1'b1, access_value = $anyconst)
    // ##0 (access_value >= base_value)
    // ##0 ({1'b1,access_value} <({1'b0,base_value} + length_value))

    // temporal behaviorwrite_capregs
    //##0  !EN_s_axi_aw_put
    ##0  RST_N
    ##0  EN_mgmt_axi_aw_put && !EN_mgmt_axi_w_put && mgmt_axi_aw_put_val == Captable_select(cap_select)
    ##1  !EN_mgmt_axi_aw_put && EN_mgmt_axi_w_put && mgmt_axi_w_put_val ==  Captable_write(encoded_cap) && !EN_s_axi_aw_put
    ##1  !EN_mgmt_axi_w_put && EN_s_axi_aw_put && s_axi_aw_put_val == set_s_axi_aw_put_val(cap_value, cap_select) && !EN_s_axi_w_put  
    //##1  !EN_s_axi_aw_put 
    |->   
    //$fell(m_axi_aw_canPeek);
    m_axi_aw_canPeek;
endproperty

dummy: assert property (@(posedge CLK) disable iff (!RST_N) integrity_check);

property mngmt_check;
    EN_mgmt_axi_aw_put &&  EN_mgmt_axi_w_put
|-> mkCapChecker_Top.WILL_FIRE_RL_cap_checker_writeCap;
endproperty
property integrity_check;
      EN_s_axi_aw_put && s_axi_aw_put_val == set_s_axi_aw_put_val(cap_value, cap_select) && is_address_protected(s_axi_aw_put_val)
      |->
      !mkCapChecker_Top.SEL_ARR_cap_checker_caps_0_40_BIT_160_90_cap_c_ETC___d490;
endproperty
     

write_pass_prop: assert property (@(posedge CLK)disable iff (!RST_N) write_pass);
endmodule

bind mkCapChecker_Top  fv_capChecker fv_capchecker_inst1(.*);