module fv_capChecker 
import cheri_encoder_pkg::*;
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
  s_aw = {4'b0000, val, 8'h00, 3'b000, 18'd0, cap};
  return s_aw;
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

  
sequence slave_address_req;
    EN_s_axi_aw_put  ##1 !EN_s_axi_aw_put ;
endsequence

sequence write_capregs;
     EN_mgmt_axi_aw_put && EN_mgmt_axi_w_put 
     ##1 !EN_mgmt_axi_aw_put && !EN_mgmt_axi_w_put && !EN_s_axi_aw_put  ;
endsequence


property write_pass;
//  non determinnent signals
    logic [2:0] cap_select;
    logic [63:0] cap_value;
    //logic [63:0] access_value;
    logic [63:0] base_value;
    logic [64:0] length_value;
    logic [14:0] perms;
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
    //##0 (1'b1, access_value = $anyconst)
    //##0 (access_value >= base_value)
    //##0 ({1'b1,access_value} <({1'b0,base_value} + length_value))
    // temporal behaviorwrite_capregs
    //##0  !EN_s_axi_aw_put
    ##0  EN_mgmt_axi_aw_put && !EN_mgmt_axi_w_put && mgmt_axi_aw_put_val == Captable_select(cap_select)
    ##0  !EN_mgmt_axi_aw_put && EN_mgmt_axi_w_put && mgmt_axi_w_put_val ==  Captable_write(encoded_cap)
    //##0  write_capregs
    ##1 !EN_mgmt_axi_w_put 
    ##1  EN_s_axi_aw_put && s_axi_aw_put_val == set_s_axi_aw_put_val(cap_value, cap_select) 
    ##1  !EN_s_axi_aw_put 
    |->   
    ##0 m_axi_aw_canPeek;
endproperty

property mngmt_check;
    EN_mgmt_axi_aw_put &&  EN_mgmt_axi_w_put
|-> mkCapChecker_Top.WILL_FIRE_RL_cap_checker_writeCap;
endproperty

write_pass_prop: assert property (@(posedge CLK) disable iff (!RST_N) write_pass);
endmodule

bind mkCapChecker_Top  fv_capChecker fv_capchecker_inst1(.*);