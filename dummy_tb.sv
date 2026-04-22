`timescale 1ns/1ps

module tb_capchecker;
  import cheri_encoder_pkg::*;

  function automatic logic [128:0] build_capchecker_cap_word(
    input logic [63:0] base,
    input logic [63:0] addr,
    input logic [64:0] length,
    input logic [15:0] perms,
    input logic [17:0] otype
  );
    logic [127:0] encoded_cap;
    begin
      encoded_cap = encode_cheri_cap(base, addr, length, perms, otype);
      // mkCapChecker_Top expects:
      //   [128:1] = compressed 128-bit CHERI payload
      //   [0]     = capability valid/tag bit
      build_capchecker_cap_word = {encoded_cap, 1'b1};
    end
  endfunction

  function automatic logic [145:0] pack_mgmt_w_payload(
    input logic [128:0] cap_word
  );
    begin
      pack_mgmt_w_payload = {cap_word[128:1], 17'd0, cap_word[0]};
    end
  endfunction

  function automatic logic [128:0] wrap128_to_capchecker_word(
    input logic [128:0] wrap_word
  );
    begin
      // module_wrap128_toMem returns {tag, payload[127:0]}
      // mkCapChecker_Top mgmt_w_put expects {payload[127:0], tag}
      wrap128_to_capchecker_word = {wrap_word[127:0], wrap_word[128]};
    end
  endfunction

  task automatic dump_encoder_debug(
    input logic [63:0]  base_in,
    input logic [63:0]  addr_in,
    input logic [64:0]  length_in,
    input logic [15:0]  perms_in,
    input logic [17:0]  otype_in,
    input logic [127:0] enc_in,
    input logic [128:0] cap_word_in,
    input logic [145:0] mgmt_payload_in
  );
    begin
      $display("<%0t> TB: encoder inputs", $time);
      $display("  base        = %h", base_in);
      $display("  addr        = %h", addr_in);
      $display("  length      = %h", length_in);
      $display("  perms       = %h", perms_in);
      $display("  otype       = %h", otype_in);

      $display("<%0t> TB: encoded_cap_dbg         = %h", $time, enc_in);
      $display("  perms[127:112]            = %h", enc_in[127:112]);
      $display("  reserved[111:109]         = %b", enc_in[111:109]);
      $display("  otype[108:91]             = %h", enc_in[108:91]);
      $display("  stored_ie(~IE) [90]       = %b", enc_in[90]);
      $display("  top_hi[89:81]             = %h", enc_in[89:81]);
      $display("  top_low_enc[80:78]        = %b", enc_in[80:78]);
      $display("  base_hi[77:67]            = %h", enc_in[77:67]);
      $display("  base_low_enc[66:64]       = %b", enc_in[66:64]);
      $display("  addr[63:0]                = %h", enc_in[63:0]);

      $display("<%0t> TB: cap_word                = %h", $time, cap_word_in);
      $display("<%0t> TB: mgmt_payload_dbg       = %h", $time, mgmt_payload_in);
      $display("<%0t> TB: reference almighty raw = %h", $time, almighty_cap_raw);
      $display("<%0t> TB: reference almighty mem = %h", $time, almighty_cap_word);
      $display("<%0t> TB: reference reordered    = %h", $time,
        wrap128_to_capchecker_word(almighty_cap_word));
    end
  endtask

  function automatic logic [99:0] pack_s_axi_aw(
    input logic [63:0] addr,
    input logic [7:0]  len,
    input logic [2:0]  size,
    input logic [2:0]  cap_idx
  );
    begin
      pack_s_axi_aw = {4'b0000, addr, len, size, 18'd0, cap_idx};
    end
  endfunction

  function automatic logic [96:0] pack_s_axi_ar(
    input logic [63:0] addr,
    input logic [7:0]  len,
    input logic [2:0]  size
  );
    begin
      pack_s_axi_ar = {4'b0000, addr, len, size, 18'd0};
    end
  endfunction

  logic CLK;
  logic RST_N;

  initial begin
    CLK = 0;
    forever #5 CLK = ~CLK;
  end

  initial begin
    RST_N = 1'b0;
    repeat (5) @(posedge CLK);
    RST_N = 1'b1;
  end

  logic        s_axi_aw_canPut;
  logic [99:0] s_axi_aw_put_val;
  logic        EN_s_axi_aw_put;
  logic        RDY_s_axi_aw_put;

  logic        s_axi_w_canPut;
  logic [72:0] s_axi_w_put_val;
  logic        EN_s_axi_w_put;
  logic        RDY_s_axi_w_put;

  logic        s_axi_b_canPeek;
  logic [5:0]  s_axi_b_peek;
  logic        RDY_s_axi_b_peek;
  logic        EN_s_axi_b_drop;
  logic        RDY_s_axi_b_drop;

  logic        s_axi_ar_canPut;
  logic [96:0] s_axi_ar_put_val;
  logic        EN_s_axi_ar_put;
  logic        RDY_s_axi_ar_put;

  logic        s_axi_r_canPeek;
  logic [70:0] s_axi_r_peek;
  logic        RDY_s_axi_r_peek;
  logic        EN_s_axi_r_drop;
  logic        RDY_s_axi_r_drop;

  // m_axi (master side)
  logic        m_axi_aw_canPeek;
  logic [96:0] m_axi_aw_peek;
  logic        RDY_m_axi_aw_peek;
  logic        EN_m_axi_aw_drop;
  logic        RDY_m_axi_aw_drop;

  logic        m_axi_w_canPeek;
  logic [72:0] m_axi_w_peek;
  logic        RDY_m_axi_w_peek;
  logic        EN_m_axi_w_drop;
  logic        RDY_m_axi_w_drop;

  logic        m_axi_b_canPut;
  logic [5:0]  m_axi_b_put_val;
  logic        EN_m_axi_b_put;
  logic        RDY_m_axi_b_put;

  logic        m_axi_ar_canPeek;
  logic [96:0] m_axi_ar_peek;
  logic        RDY_m_axi_ar_peek;
  logic        EN_m_axi_ar_drop;
  logic        RDY_m_axi_ar_drop;

  logic        m_axi_r_canPut;
  logic [70:0] m_axi_r_put_val;
  logic        EN_m_axi_r_put;
  logic        RDY_m_axi_r_put;

  logic        mgmt_axi_aw_canPut;
  logic [39:0] mgmt_axi_aw_put_val;
  logic        EN_mgmt_axi_aw_put;
  logic        RDY_mgmt_axi_aw_put;

  logic        mgmt_axi_w_canPut;
  logic [145:0] mgmt_axi_w_put_val;
  logic        EN_mgmt_axi_w_put;
  logic        RDY_mgmt_axi_w_put;

  logic        mgmt_axi_b_canPeek;
  logic [3:0]  mgmt_axi_b_peek;
  logic        RDY_mgmt_axi_b_peek;
  logic        EN_mgmt_axi_b_drop;
  logic        RDY_mgmt_axi_b_drop;

  logic        mgmt_axi_ar_canPut;
  logic [38:0] mgmt_axi_ar_put_val;
  logic        EN_mgmt_axi_ar_put;
  logic        RDY_mgmt_axi_ar_put;

  logic        mgmt_axi_r_canPeek;
  logic [133:0] mgmt_axi_r_peek;
  logic        RDY_mgmt_axi_r_peek;
  logic        EN_mgmt_axi_r_drop;
  logic        RDY_mgmt_axi_r_drop;

  logic [63:0] base;
  logic [63:0] addr;
  logic [64:0] length;
  logic [15:0] perms;
  logic [17:0] otype;
  logic [128:0] cap_word;
  logic [72:0] test_w_payload;
  logic [127:0] encoded_cap_dbg;
  logic [145:0] mgmt_payload_dbg;
  logic [160:0] almighty_cap_raw;
  logic [128:0] almighty_cap_word;

  localparam logic [2:0]  CAP_IDX     = 3'd0;
  localparam logic [63:0] CAP_BASE    = 64'h0000_4000_0000_1000;
  localparam logic [64:0] CAP_LENGTH  = 65'h0_0000_0000_0000_0200;
  localparam logic [63:0] ACCESS_ADDR = 64'h0000_4000_0000_1040;

  mkCapChecker_Top dut (
    .CLK(CLK),
    .RST_N(RST_N),

    .s_axi_aw_canPut(s_axi_aw_canPut),
    .s_axi_aw_put_val(s_axi_aw_put_val),
    .EN_s_axi_aw_put(EN_s_axi_aw_put),
    .RDY_s_axi_aw_put(RDY_s_axi_aw_put),

    .s_axi_w_canPut(s_axi_w_canPut),
    .s_axi_w_put_val(s_axi_w_put_val),
    .EN_s_axi_w_put(EN_s_axi_w_put),
    .RDY_s_axi_w_put(RDY_s_axi_w_put),

    .s_axi_b_canPeek(s_axi_b_canPeek),
    .s_axi_b_peek(s_axi_b_peek),
    .RDY_s_axi_b_peek(RDY_s_axi_b_peek),
    .EN_s_axi_b_drop(EN_s_axi_b_drop),
    .RDY_s_axi_b_drop(RDY_s_axi_b_drop),

    .s_axi_ar_canPut(s_axi_ar_canPut),
    .s_axi_ar_put_val(s_axi_ar_put_val),
    .EN_s_axi_ar_put(EN_s_axi_ar_put),
    .RDY_s_axi_ar_put(RDY_s_axi_ar_put),

    .s_axi_r_canPeek(s_axi_r_canPeek),
    .s_axi_r_peek(s_axi_r_peek),
    .RDY_s_axi_r_peek(RDY_s_axi_r_peek),
    .EN_s_axi_r_drop(EN_s_axi_r_drop),
    .RDY_s_axi_r_drop(RDY_s_axi_r_drop),

    .m_axi_aw_canPeek(m_axi_aw_canPeek),
    .m_axi_aw_peek(m_axi_aw_peek),
    .RDY_m_axi_aw_peek(RDY_m_axi_aw_peek),
    .EN_m_axi_aw_drop(EN_m_axi_aw_drop),
    .RDY_m_axi_aw_drop(RDY_m_axi_aw_drop),

    .m_axi_w_canPeek(m_axi_w_canPeek),
    .m_axi_w_peek(m_axi_w_peek),
    .RDY_m_axi_w_peek(RDY_m_axi_w_peek),
    .EN_m_axi_w_drop(EN_m_axi_w_drop),
    .RDY_m_axi_w_drop(RDY_m_axi_w_drop),

    .m_axi_b_canPut(m_axi_b_canPut),
    .m_axi_b_put_val(m_axi_b_put_val),
    .EN_m_axi_b_put(EN_m_axi_b_put),
    .RDY_m_axi_b_put(RDY_m_axi_b_put),

    .m_axi_ar_canPeek(m_axi_ar_canPeek),
    .m_axi_ar_peek(m_axi_ar_peek),
    .RDY_m_axi_ar_peek(RDY_m_axi_ar_peek),
    .EN_m_axi_ar_drop(EN_m_axi_ar_drop),
    .RDY_m_axi_ar_drop(RDY_m_axi_ar_drop),

    .m_axi_r_canPut(m_axi_r_canPut),
    .m_axi_r_put_val(m_axi_r_put_val),
    .EN_m_axi_r_put(EN_m_axi_r_put),
    .RDY_m_axi_r_put(RDY_m_axi_r_put),

    .mgmt_axi_aw_canPut(mgmt_axi_aw_canPut),
    .mgmt_axi_aw_put_val(mgmt_axi_aw_put_val),
    .EN_mgmt_axi_aw_put(EN_mgmt_axi_aw_put),
    .RDY_mgmt_axi_aw_put(RDY_mgmt_axi_aw_put),

    .mgmt_axi_w_canPut(mgmt_axi_w_canPut),
    .mgmt_axi_w_put_val(mgmt_axi_w_put_val),
    .EN_mgmt_axi_w_put(EN_mgmt_axi_w_put),
    .RDY_mgmt_axi_w_put(RDY_mgmt_axi_w_put),

    .mgmt_axi_b_canPeek(mgmt_axi_b_canPeek),
    .mgmt_axi_b_peek(mgmt_axi_b_peek),
    .RDY_mgmt_axi_b_peek(RDY_mgmt_axi_b_peek),
    .EN_mgmt_axi_b_drop(EN_mgmt_axi_b_drop),
    .RDY_mgmt_axi_b_drop(RDY_mgmt_axi_b_drop),

    .mgmt_axi_ar_canPut(mgmt_axi_ar_canPut),
    .mgmt_axi_ar_put_val(mgmt_axi_ar_put_val),
    .EN_mgmt_axi_ar_put(EN_mgmt_axi_ar_put),
    .RDY_mgmt_axi_ar_put(RDY_mgmt_axi_ar_put),

    .mgmt_axi_r_canPeek(mgmt_axi_r_canPeek),
    .mgmt_axi_r_peek(mgmt_axi_r_peek),
    .RDY_mgmt_axi_r_peek(RDY_mgmt_axi_r_peek),
    .EN_mgmt_axi_r_drop(EN_mgmt_axi_r_drop),
    .RDY_mgmt_axi_r_drop(RDY_mgmt_axi_r_drop)
  );

  module_wrap128_almightyCap cap_ref (
    .wrap128_almightyCap(almighty_cap_raw)
  );

  module_wrap128_toMem cap_ref_mem (
    .wrap128_toMem_cap(almighty_cap_raw),
    .wrap128_toMem(almighty_cap_word)
  );

  task automatic drive_defaults;
    begin
      EN_s_axi_aw_put    = 0;
      EN_s_axi_w_put     = 0;
      EN_s_axi_ar_put    = 0;
      EN_s_axi_b_drop    = 0;
      EN_s_axi_r_drop    = 0;

      EN_m_axi_aw_drop   = 0;
      EN_m_axi_w_drop    = 0;
      EN_m_axi_ar_drop   = 0;

      EN_m_axi_b_put     = 0;
      EN_m_axi_r_put     = 0;

      EN_mgmt_axi_aw_put = 0;
      EN_mgmt_axi_w_put  = 0;
      EN_mgmt_axi_ar_put = 0;
      EN_mgmt_axi_b_drop = 0;
      EN_mgmt_axi_r_drop = 0;

      s_axi_aw_put_val    = '0;
      s_axi_w_put_val     = '0;
      s_axi_ar_put_val    = '0;
      m_axi_b_put_val     = '0;
      m_axi_r_put_val     = '0;
      mgmt_axi_aw_put_val = '0;
      mgmt_axi_w_put_val  = '0;
      mgmt_axi_ar_put_val = '0;
    end
  endtask

  initial begin
    drive_defaults();
  end

  task automatic s_aw_put(input logic [99:0] v);
    begin
      do @(posedge CLK); while (!s_axi_aw_canPut);
      s_axi_aw_put_val <= v;
      EN_s_axi_aw_put  <= 1'b1;
      @(posedge CLK);
      EN_s_axi_aw_put  <= 1'b0;
    end
  endtask

  task automatic s_w_put(input logic [72:0] v);
    begin
      do @(posedge CLK); while (!s_axi_w_canPut);
      s_axi_w_put_val <= v;
      EN_s_axi_w_put  <= 1'b1;
      @(posedge CLK);
      EN_s_axi_w_put  <= 1'b0;
    end
  endtask

  task automatic s_ar_put(input logic [96:0] v);
    begin
      do @(posedge CLK); while (!s_axi_ar_canPut);
      s_axi_ar_put_val <= v;
      EN_s_axi_ar_put  <= 1'b1;
      @(posedge CLK);
      EN_s_axi_ar_put  <= 1'b0;
    end
  endtask

  task automatic mgmt_aw_put(input logic [39:0] v);
    begin
      do @(posedge CLK); while (!mgmt_axi_aw_canPut);
      mgmt_axi_aw_put_val <= v;
      EN_mgmt_axi_aw_put  <= 1'b1;
      @(posedge CLK);
      EN_mgmt_axi_aw_put  <= 1'b0;
    end
  endtask

  task automatic mgmt_w_put(input logic [128:0] v);
    begin
      do @(posedge CLK); while (!mgmt_axi_w_canPut);

      mgmt_axi_w_put_val <= pack_mgmt_w_payload(v);
      EN_mgmt_axi_w_put  <= 1'b1;
      @(posedge CLK);
      EN_mgmt_axi_w_put  <= 1'b0;
    end
  endtask

  task automatic expect_m_axi_w(input logic [72:0] expected);
    int cycles;
    begin
      cycles = 0;
      while (!m_axi_w_canPeek && cycles < 40) begin
        @(posedge CLK);
        cycles++;
      end

      if (!m_axi_w_canPeek)
        $fatal(1, "Timed out waiting for m_axi_w");

      if (m_axi_w_peek !== expected)
        $fatal(1, "m_axi_w mismatch. expected=%h got=%h", expected, m_axi_w_peek);
    end
  endtask

  task automatic expect_no_m_axi_w(input int max_cycles);
    int cycles;
    begin
      cycles = 0;
      while (cycles < max_cycles) begin
        @(posedge CLK);
        if (m_axi_w_canPeek)
          $fatal(1, "Unexpected m_axi_w observed: %h", m_axi_w_peek);
        cycles++;
      end
    end
  endtask

  task automatic program_cap0(input logic [128:0] programmed_cap_word);
    begin
      $display("<%0t> TB: program_cap0 cap_word=%h", $time, programmed_cap_word);
      $display("<%0t> TB: program_cap0 mgmt_payload=%h", $time, pack_mgmt_w_payload(programmed_cap_word));
      mgmt_aw_put(40'h0000_00000);
      mgmt_w_put(programmed_cap_word);
      repeat (2) @(posedge CLK);
    end
  endtask

  task automatic run_write_read_case(
    input logic [63:0] access_addr,
    input logic [72:0] write_data,
    input bit expect_write_pass,
    input bit expect_read_pass
  );
    begin
      s_aw_put(pack_s_axi_aw(access_addr, 8'h00, 3'b000, CAP_IDX));
      s_w_put(write_data);

      if (expect_write_pass)
        expect_m_axi_w(write_data);
      else
        expect_no_m_axi_w(20);

      s_ar_put(pack_s_axi_ar(access_addr, 8'h00, 3'b000));

      if (!expect_read_pass)
        repeat (10) @(posedge CLK);

      repeat (8) @(posedge CLK);
    end
  endtask

  always_ff @(posedge CLK) begin
    if (!RST_N) begin
      EN_m_axi_aw_drop   <= 0;
      EN_m_axi_w_drop    <= 0;
      EN_m_axi_ar_drop   <= 0;
      EN_s_axi_b_drop    <= 0;
      EN_s_axi_r_drop    <= 0;
      EN_mgmt_axi_b_drop <= 0;
      EN_mgmt_axi_r_drop <= 0;
    end else begin
      EN_m_axi_aw_drop   <= 0;
      EN_m_axi_w_drop    <= 0;
      EN_m_axi_ar_drop   <= 0;
      EN_s_axi_b_drop    <= 0;
      EN_s_axi_r_drop    <= 0;
      EN_mgmt_axi_b_drop <= 0;
      EN_mgmt_axi_r_drop <= 0;

      if (m_axi_aw_canPeek && RDY_m_axi_aw_drop)
        EN_m_axi_aw_drop <= 1'b1;
      if (m_axi_w_canPeek && RDY_m_axi_w_drop)
        EN_m_axi_w_drop <= 1'b1;
      if (m_axi_ar_canPeek && RDY_m_axi_ar_drop)
        EN_m_axi_ar_drop <= 1'b1;

      if (s_axi_b_canPeek && RDY_s_axi_b_drop)
        EN_s_axi_b_drop <= 1'b1;
      if (s_axi_r_canPeek && RDY_s_axi_r_drop)
        EN_s_axi_r_drop <= 1'b1;

      if (mgmt_axi_b_canPeek && RDY_mgmt_axi_b_drop)
        EN_mgmt_axi_b_drop <= 1'b1;
      if (mgmt_axi_r_canPeek && RDY_mgmt_axi_r_drop)
        EN_mgmt_axi_r_drop <= 1'b1;
    end
  end

  int pending_writes;
  int pending_reads;

  always_ff @(posedge CLK) begin
    if (!RST_N) begin
      pending_writes <= 0;
      pending_reads  <= 0;
      EN_m_axi_b_put <= 0;
      EN_m_axi_r_put <= 0;
      m_axi_b_put_val <= '0;
      m_axi_r_put_val <= '0;
    end else begin
      EN_m_axi_b_put <= 0;
      EN_m_axi_r_put <= 0;

      if (m_axi_aw_canPeek && RDY_m_axi_aw_drop)
        pending_writes <= pending_writes + 1;
      if (m_axi_ar_canPeek && RDY_m_axi_ar_drop)
        pending_reads <= pending_reads + 1;

      if (pending_writes > 0 && m_axi_b_canPut) begin
        m_axi_b_put_val <= 6'b000000;
        EN_m_axi_b_put  <= 1'b1;
        pending_writes  <= pending_writes - 1;
      end

      if (pending_reads > 0 && m_axi_r_canPut) begin
        m_axi_r_put_val    <= '0;
        m_axi_r_put_val[0] <= 1'b1;
        EN_m_axi_r_put  <= 1'b1;
        pending_reads   <= pending_reads - 1;
      end
    end
  end

  initial begin
    $dumpfile("capchecker.vcd");
    $dumpvars(0, tb_capchecker);
  end

  initial begin
    @(posedge RST_N);
    repeat (2) @(posedge CLK);

    perms = '1;
    base = CAP_BASE;
    addr = ACCESS_ADDR;
    length = CAP_LENGTH;
    otype = 18'h0;
    encoded_cap_dbg = encode_cheri_cap(base, addr, length, perms, otype);
    cap_word = build_capchecker_cap_word(base, addr, length, perms, otype);
    mgmt_payload_dbg = pack_mgmt_w_payload(cap_word);
    test_w_payload = {64'h0123_4567_89AB_CDEF, 8'hFF, 1'b1};

    dump_encoder_debug(
      base,
      addr,
      length,
      perms,
      otype,
      encoded_cap_dbg,
      cap_word,
      mgmt_payload_dbg
    );

    program_cap0(cap_word);
    run_write_read_case(ACCESS_ADDR, test_w_payload, 1'b1, 1'b1);

    repeat (50) @(posedge CLK);
    $finish;
  end

endmodule
