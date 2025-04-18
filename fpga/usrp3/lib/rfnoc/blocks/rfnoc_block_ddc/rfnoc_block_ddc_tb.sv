//
// Copyright 2019 Ettus Research, a National Instruments Company
//
// SPDX-License-Identifier: LGPL-3.0-or-later
//
// Module: rfnoc_block_ddc_tb
//
// Description:  Testbench for rfnoc_block_ddc
//


module rfnoc_block_ddc_tb();

  // Include macros and time declarations for use with PkgTestExec
  `include "test_exec.svh"

  import PkgTestExec::*;
  import rfnoc_chdr_utils_pkg::*;
  import PkgChdrData::*;
  import PkgRfnocBlockCtrlBfm::*;
  import PkgRfnocItemUtils::*;
  import PkgMath::*;

  `include "rfnoc_block_ddc_regs.vh"


  //---------------------------------------------------------------------------
  // Local Parameters
  //---------------------------------------------------------------------------

  // Simulation parameters
  localparam real CHDR_CLK_PER   = 5.0;   // CHDR clock rate
  localparam real DDC_CLK_PER    = 4.0;   // DUC IP clock rate
  localparam int  EXTENDED_TEST  = 0;     // Perform a longer test
  localparam int  SPP            = 256;   // Samples per packet
  localparam int  PKT_SIZE_BYTES = SPP*4; // Bytes per packet
  localparam int  STALL_PROB     = 25;    // BFM stall probability

  // Block configuration
  localparam int CHDR_W        = 64;
  localparam int SAMP_W        = 32;
  localparam int THIS_PORTID   = 'h123;
  localparam int MTU           = 8;
  localparam int NUM_PORTS     = 1;
  localparam int NUM_HB        = 3;
  localparam int CIC_MAX_DECIM = 255;
  localparam int NOC_ID        = 32'hDDC00000;

  //---------------------------------------------------------------------------
  // Clocks
  //---------------------------------------------------------------------------

  bit rfnoc_chdr_clk;
  bit rfnoc_ctrl_clk;
  bit ce_clk;

  sim_clock_gen #(CHDR_CLK_PER) rfnoc_chdr_clk_gen (.clk(rfnoc_chdr_clk), .rst());
  sim_clock_gen #(CHDR_CLK_PER) rfnoc_ctrl_clk_gen (.clk(rfnoc_ctrl_clk), .rst());
  sim_clock_gen #(DDC_CLK_PER)  ddc_clk_gen        (.clk(ce_clk), .rst());


  //---------------------------------------------------------------------------
  // Bus Functional Models
  //---------------------------------------------------------------------------

  typedef ChdrData #(CHDR_W, SAMP_W)::chdr_word_t chdr_word_t;
  typedef ChdrData #(CHDR_W, SAMP_W)::item_t      item_t;


  RfnocBackendIf        backend            (rfnoc_chdr_clk, rfnoc_ctrl_clk);
  AxiStreamIf #(32)     m_ctrl             (rfnoc_ctrl_clk, 1'b0);
  AxiStreamIf #(32)     s_ctrl             (rfnoc_ctrl_clk, 1'b0);
  AxiStreamIf #(CHDR_W) m_chdr [NUM_PORTS] (rfnoc_chdr_clk, 1'b0);
  AxiStreamIf #(CHDR_W) s_chdr [NUM_PORTS] (rfnoc_chdr_clk, 1'b0);

  // Bus functional model for a software block controller
  RfnocBlockCtrlBfm #(CHDR_W, SAMP_W) blk_ctrl =
    new(backend, m_ctrl, s_ctrl);

  // Connect block controller to BFMs
  for (genvar i = 0; i < NUM_PORTS; i++) begin : gen_bfm_connections
    initial begin
      blk_ctrl.connect_master_data_port(i, m_chdr[i], PKT_SIZE_BYTES);
      blk_ctrl.connect_slave_data_port(i, s_chdr[i]);
      blk_ctrl.set_master_stall_prob(i, STALL_PROB);
      blk_ctrl.set_slave_stall_prob(i, STALL_PROB);
    end
  end


  //---------------------------------------------------------------------------
  // DUT
  //---------------------------------------------------------------------------

  logic [NUM_PORTS*CHDR_W-1:0] s_rfnoc_chdr_tdata;
  logic [       NUM_PORTS-1:0] s_rfnoc_chdr_tlast;
  logic [       NUM_PORTS-1:0] s_rfnoc_chdr_tvalid;
  logic [       NUM_PORTS-1:0] s_rfnoc_chdr_tready;

  logic [NUM_PORTS*CHDR_W-1:0] m_rfnoc_chdr_tdata;
  logic [       NUM_PORTS-1:0] m_rfnoc_chdr_tlast;
  logic [       NUM_PORTS-1:0] m_rfnoc_chdr_tvalid;
  logic [       NUM_PORTS-1:0] m_rfnoc_chdr_tready;

  // Map the array of BFMs to a flat vector for the DUT
  genvar i;
  for (i = 0; i < NUM_PORTS; i++) begin : gen_dut_connections
    // Connect BFM master to DUT slave port
    assign s_rfnoc_chdr_tdata[CHDR_W*i+:CHDR_W] = m_chdr[i].tdata;
    assign s_rfnoc_chdr_tlast[i]                = m_chdr[i].tlast;
    assign s_rfnoc_chdr_tvalid[i]               = m_chdr[i].tvalid;
    assign m_chdr[i].tready                     = s_rfnoc_chdr_tready[i];

    // Connect BFM slave to DUT master port
    assign s_chdr[i].tdata        = m_rfnoc_chdr_tdata[CHDR_W*i+:CHDR_W];
    assign s_chdr[i].tlast        = m_rfnoc_chdr_tlast[i];
    assign s_chdr[i].tvalid       = m_rfnoc_chdr_tvalid[i];
    assign m_rfnoc_chdr_tready[i] = s_chdr[i].tready;
  end

  rfnoc_block_ddc #(
    .THIS_PORTID    (THIS_PORTID),
    .CHDR_W         (CHDR_W),
    .NUM_PORTS      (NUM_PORTS),
    .MTU            (MTU),
    .NUM_HB         (NUM_HB),
    .CIC_MAX_DECIM  (CIC_MAX_DECIM)
  ) rfnoc_block_ddc_i (
    .rfnoc_chdr_clk          (backend.chdr_clk),
    .ce_clk                  (ce_clk),
    .s_rfnoc_chdr_tdata      (s_rfnoc_chdr_tdata),
    .s_rfnoc_chdr_tlast      (s_rfnoc_chdr_tlast),
    .s_rfnoc_chdr_tvalid     (s_rfnoc_chdr_tvalid),
    .s_rfnoc_chdr_tready     (s_rfnoc_chdr_tready),
    .m_rfnoc_chdr_tdata      (m_rfnoc_chdr_tdata),
    .m_rfnoc_chdr_tlast      (m_rfnoc_chdr_tlast),
    .m_rfnoc_chdr_tvalid     (m_rfnoc_chdr_tvalid),
    .m_rfnoc_chdr_tready     (m_rfnoc_chdr_tready),
    .rfnoc_core_config       (backend.cfg),
    .rfnoc_core_status       (backend.sts),
    .rfnoc_ctrl_clk          (backend.ctrl_clk),
    .s_rfnoc_ctrl_tdata      (m_ctrl.tdata),
    .s_rfnoc_ctrl_tlast      (m_ctrl.tlast),
    .s_rfnoc_ctrl_tvalid     (m_ctrl.tvalid),
    .s_rfnoc_ctrl_tready     (m_ctrl.tready),
    .m_rfnoc_ctrl_tdata      (s_ctrl.tdata),
    .m_rfnoc_ctrl_tlast      (s_ctrl.tlast),
    .m_rfnoc_ctrl_tvalid     (s_ctrl.tvalid),
    .m_rfnoc_ctrl_tready     (s_ctrl.tready)
  );


  //---------------------------------------------------------------------------
  // Helper Tasks
  //---------------------------------------------------------------------------

  // Translate the desired register access to a ctrlport write request.
  task automatic write_reg(int port, byte addr, bit [31:0] value);
    blk_ctrl.reg_write(256*8*port + addr*8, value);
  endtask : write_reg


  // Translate the desired register access to a ctrlport read request.
  task automatic read_user_reg(int port, byte addr, output logic [63:0] value);
    blk_ctrl.reg_read(256*8*port + addr*8 + 0, value[31: 0]);
    blk_ctrl.reg_read(256*8*port + addr*8 + 4, value[63:32]);
  endtask : read_user_reg


  task automatic set_decim_rate(int port, input int decim_rate);
    logic [7:0] cic_rate;
    logic [1:0] hb_enables;
    int _decim_rate;

    cic_rate = 8'd0;
    hb_enables = 2'b0;
    _decim_rate = decim_rate;

    // Calculate which half bands to enable and whatever is left over set the CIC
    while ((_decim_rate[0] == 0) && (hb_enables < NUM_HB)) begin
      hb_enables += 1'b1;
      _decim_rate = _decim_rate >> 1;
    end
    // CIC rate cannot be set to 0
    cic_rate = (_decim_rate[7:0] == 8'd0) ? 8'd1 : _decim_rate[7:0];
    `ASSERT_ERROR(
      hb_enables <= NUM_HB,
      "Enabled halfbands may not exceed total number of half bands."
    );
    `ASSERT_ERROR(
      cic_rate > 0 && cic_rate <= CIC_MAX_DECIM,
      {"CIC Decimation rate must be positive, not exceed the max cic ",
      "decimation rate, and cannot equal 0!"}
    );

    // Setup DDC
    $display("Set decimation to %0d", decim_rate);
    $display("- Number of enabled HBs: %0d", hb_enables);
    $display("- CIC Rate:              %0d", cic_rate);
    // Set decimation rate in AXI rate change
    write_reg(port, SR_N_ADDR, decim_rate);
    // Enable HBs, set CIC rate
    write_reg(port, SR_DECIM_ADDR, {hb_enables,cic_rate});
  endtask


  task automatic send_ramp (
    input int unsigned port,
    input int unsigned decim_rate,
    // (Optional) For testing passing through partial packets
    input logic drop_partial_packet = 1'b0,
    input int unsigned extra_samples = 0
  );
    set_decim_rate(port, decim_rate);

    // Setup DDC
    write_reg(port, SR_CONFIG_ADDR, 32'd1);       // Enable clear EOB
    write_reg(port, SR_FREQ_ADDR, 32'd0);         // Phase increment
    write_reg(port, SR_SCALE_IQ_ADDR, (1 << 14)); // Scaling, set to 1

    // Send a short ramp, should pass through unchanged
    fork
      begin
        chdr_word_t send_payload[$];
        packet_info_t pkt_info;

        pkt_info = 0;
        for (int i = 0; i < decim_rate*(PKT_SIZE_BYTES/8 + extra_samples); i++) begin
          send_payload.push_back(
            {16'(2*i/decim_rate), 16'(2*i/decim_rate),
            16'((2*i+1)/decim_rate), 16'((2*i+1)/decim_rate)});
        end
        $display("Send ramp (%0d words)", send_payload.size());
        pkt_info.eob = 1;
        blk_ctrl.send_packets(port, send_payload, /*data_bytes*/, /*metadata*/, pkt_info);
        blk_ctrl.wait_complete(port);
        $display("Send ramp complete");
      end
      begin
        string s;
        logic [63:0]  samples, samples_old;
        chdr_word_t   recv_payload[$], temp_payload[$];
        chdr_word_t   metadata[$];
        int           data_bytes;
        packet_info_t pkt_info;

        $display("Check ramp");
        if (~drop_partial_packet && (extra_samples > 0)) begin
          blk_ctrl.recv_adv(port, temp_payload, data_bytes, metadata, pkt_info);
          $sformat(s, "Invalid EOB state! Expected %b, Received: %b", 1'b0, pkt_info.eob);
          `ASSERT_ERROR(pkt_info.eob == 1'b0, s);
        end
        $display("Receiving packet");
        blk_ctrl.recv_adv(port, recv_payload, data_bytes, metadata, pkt_info);
        $display("Received!");
        $sformat(s, "Invalid EOB state! Expected %b, Received: %b", 1'b1, pkt_info.eob);
        `ASSERT_ERROR(pkt_info.eob == 1'b1, s);
        recv_payload = {temp_payload, recv_payload};
        if (drop_partial_packet) begin
          $sformat(s, "Incorrect packet size! Expected: %0d, Actual: %0d",
            PKT_SIZE_BYTES/8, recv_payload.size());
          `ASSERT_ERROR(recv_payload.size() == PKT_SIZE_BYTES/8, s);
        end else begin
          $sformat(s, "Incorrect packet size! Expected: %0d, Actual: %0d",
            PKT_SIZE_BYTES/8, recv_payload.size() + extra_samples);
          `ASSERT_ERROR(recv_payload.size() == PKT_SIZE_BYTES/8 + extra_samples, s);
        end
        samples = 64'd0;
        samples_old = 64'd0;
        for (int i = 0; i < PKT_SIZE_BYTES/8; i++) begin
          samples = recv_payload[i];
          for (int j = 0; j < 4; j++) begin
            // Need to check a range of values due to imperfect gain compensation
            $sformat(s,
              "Ramp word %0d invalid! Expected: %0d-%0d, Received: %0d", 2*i,
              samples_old[16*j +: 16], samples_old[16*j +: 16]+16'd4,
              samples[16*j +: 16]);
            `ASSERT_ERROR(
              (samples_old[16*j +: 16]+16'd4 >= samples[16*j +: 16]) &&
              (samples >= samples_old[16*j +: 16]), s);
          end
          samples_old = samples;
        end
        $display("Check complete");
      end
    join
  endtask

  //---------------------------------------------------------------------------
  // Send tone
  //---------------------------------------------------------------------------
  // Generates samples for a sine wave tone and sends them to the specified BFM
  // port.
  //
  // Parameters:
  //   port:              Port number
  //   decim_rate:        Decimation rate
  //   tone_ampl:         Amplitude of generated sine wave
  //   tone_freq_norm:    Normalized frequency of generated sine wave
  //   dsp_tune_norm:     Normalized digital frequency shift
  //   num_samps_to_send: Number of samples to send
  //   restrict_input:    Coerce input tone samples to 16-bit signed range
  //
  // Note: The tone_freq_norm and dsp_tune_norm parameters must be in the range
  // (-1/2, +1/2).
  //---------------------------------------------------------------------------
  task automatic send_tone (
    input int unsigned port              = 0,
    input int unsigned decim_rate        = 1,
    input real         tone_ampl         = 0.9,
    input real         tone_freq_norm    = 0.0,
    input real         dsp_tune_norm     = 0.0,
    input int          num_samps_to_send = 1000,
    input int          restrict_input    = 1
  );
    chdr_word_t     recv_metadata[$];
    item_t          recv_payload[$], send_payload[$];
    packet_info_t   recv_pkt_info, send_pkt_info;
    int unsigned    total_decim, cic_decim;
    real            cic_gain_float;
    logic [31:0]    cic_gain;
    logic [31:0]    dsp_tune_word;


    // Tuning word = F_shift/Fs * 2^32 (Shift freq must be [-Fs/2,Fs/2))
    dsp_tune_word = int'(dsp_tune_norm * 2.0**32);
    $display("send_tone(): dsp_tune_word = %d", dsp_tune_word);
    write_reg(port, rfnoc_block_ddc_i.SR_FREQ_ADDR, dsp_tune_word);

    // Calculate CIC gain
    total_decim = decim_rate;
    cic_decim   = 1;
    for (int i = 0; i < NUM_HB; i++) begin
      if (total_decim > 1) begin
        if (total_decim[0]) begin // Not divisible by 2
          cic_decim = total_decim;
          break;
        end else begin // Divisible by 2
          total_decim = total_decim/2;
          cic_decim   = total_decim;
        end
      end
    end
    // DDS Gain is 2.0
    cic_gain_float = 1/((2.0*(cic_decim**4))/(2.0**$clog2(cic_decim**4)));
    cic_gain       = int'((1 << 15)*cic_gain_float);
    $display("send_tone(): CIC Rate = %d", cic_decim);
    $display("send_tone(): CIC Gain = %f", cic_gain_float);

    set_decim_rate(port, decim_rate);
    write_reg(port, rfnoc_block_ddc_i.SR_SCALE_IQ_ADDR, cic_gain);

    @(posedge rfnoc_block_ddc_i.ce_clk);
    if (num_samps_to_send > 0) begin
      fork
      // Receive samples
      begin
        automatic item_t prev_item, curr_item;
        real prev, curr;
        do begin
          blk_ctrl.recv_items_adv(port, recv_payload, recv_metadata, recv_pkt_info);
        end while (recv_pkt_info.eob == 0);
        //check for jumps in of I/Q data
        prev_item = recv_payload.pop_front();
        foreach (recv_payload[recv_idx]) begin
          curr_item = recv_payload.pop_front();
          // Compare previous sample data to current sample data. If delta is
          // more than half of the 16-bit signed value range(e.g. SHORT_MAX),
          // we assume an arithmetic overflow has occurred.
          prev = real'(signed'(prev_item[SAMP_W/2+:SAMP_W/2]));
          curr = real'(signed'(curr_item[SAMP_W/2+:SAMP_W/2]));
          `ASSERT_ERROR((Math#(real)::abs(curr-prev) < SHORT_MAX/2),
            "Detected jump in I data.");
          prev = real'(signed'(prev_item[0+:SAMP_W/2]));
          curr = real'(signed'(curr_item[0+:SAMP_W/2]));
          `ASSERT_ERROR((Math#(real)::abs(curr-prev) < SHORT_MAX/2),
            "Detected jump in Q data.");
          prev_item = curr_item;
        end
      end
      // Send tone
      begin
        typedef logic [15:0] logic_t; //needed for typecasting to packed logic array
        automatic real         i_float, q_float;
        automatic logic [15:0] i, q;
        automatic longint      phase = 0;

        send_pkt_info = '{
          vc         : 0,
          eov        : 1'b0,
          eob        : 1'b0,
          has_time   : 1'b0,
          timestamp  : 64'd0
        };

        while (num_samps_to_send > 0) begin
          send_payload = {}; // Clear out previous iteration's samples
          for (int n = 0; n < SPP; n++) begin
            i_float = tone_ampl*(2.0**15)*$cos(2*PI*phase*tone_freq_norm);
            q_float = tone_ampl*(2.0**15)*$sin(2*PI*phase*tone_freq_norm);
            phase++;
            // if restrict_input is set, we need to coerce the float values to
            // 16-bit signed values instead of cutting off the additional MSBs,
            // ensuring a smooth transition in the tone.
            if (restrict_input) begin
              i = logic_t'(coerce_to_int16(i_float));
              q = logic_t'(coerce_to_int16(q_float));
            end else begin
              i = logic_t'(i_float);
              q = logic_t'(q_float);
            end
            send_payload.push_back({i,q});

            num_samps_to_send--;
            if (num_samps_to_send == 0) begin
              break;
            end
          end

          send_pkt_info.eob = (num_samps_to_send == 0);
          blk_ctrl.send_items(port, send_payload, {}, send_pkt_info);
          blk_ctrl.wait_complete(port);
        end
      end
      join
    end
  endtask


  //---------------------------------------------------------------------------
  // Test Process
  //---------------------------------------------------------------------------

  initial begin : tb_main
    const int port = 0;
    test.start_tb("rfnoc_block_ddc_tb");

    // Start the BFMs running
    blk_ctrl.run();


    //-------------------------------------------------------------------------
    // Reset
    //-------------------------------------------------------------------------

    test.start_test("Wait for Reset", 10us);
    fork
      blk_ctrl.reset_chdr();
      blk_ctrl.reset_ctrl();
    join;
    test.end_test();


    //-------------------------------------------------------------------------
    // Check NoC ID and Block Info
    //-------------------------------------------------------------------------

    test.start_test("Verify Block Info", 2us);
    `ASSERT_ERROR(blk_ctrl.get_noc_id() == NOC_ID, "Incorrect NOC_ID Value");
    `ASSERT_ERROR(blk_ctrl.get_num_data_i() == NUM_PORTS, "Incorrect NUM_DATA_I Value");
    `ASSERT_ERROR(blk_ctrl.get_num_data_o() == NUM_PORTS, "Incorrect NUM_DATA_O Value");
    `ASSERT_ERROR(blk_ctrl.get_mtu() == MTU, "Incorrect MTU Value");
    test.end_test();


    //-------------------------------------------------------------------------
    // Test read-back regs
    //-------------------------------------------------------------------------

    begin
      logic [63:0] val64;
      test.start_test("Test registers", 10us);
      read_user_reg(port, RB_NUM_HB, val64);
      `ASSERT_ERROR(val64 == NUM_HB, "Register NUM_HB didn't read back expected value");
      read_user_reg(port, RB_CIC_MAX_DECIM, val64);
      `ASSERT_ERROR(val64 == CIC_MAX_DECIM,
        "Register CIC_MAX_DECIM didn't read back expected value");
      test.end_test();
    end

    //-------------------------------------------------------------------------
    // Test overflow
    //-------------------------------------------------------------------------
    begin
      test.start_test("Test tone", 0.5ms);
      send_tone(.port             (0),
                .decim_rate       (2),
                .tone_ampl        (1.0),
                .tone_freq_norm   (1.0/1024.0),
                .dsp_tune_norm    (1.0/1024.0),
                .num_samps_to_send(10000),
                .restrict_input   (1));
      test.end_test();
    end


    //-------------------------------------------------------------------------
    // Test various decimation rates
    //-------------------------------------------------------------------------

    begin
      test.start_test("Decimate by 1, 2, 3, 4, 6, 8, 12, 13, 16, 24, 40, 255, 2040", 0.5ms);

      $display("Note: This test will take a long time!");

      // List of rates to catch most issues
      send_ramp(port, 1);                       // HBs enabled: 0, CIC rate: 1
      send_ramp(port, 2);                       // HBs enabled: 1, CIC rate: 1
      send_ramp(port, 3);                       // HBs enabled: 0, CIC rate: 3
      send_ramp(port, 4);                       // HBs enabled: 2, CIC rate: 1
      if (EXTENDED_TEST) send_ramp(port, 6);    // HBs enabled: 1, CIC rate: 3
      send_ramp(port, 8);                       // HBs enabled: 3, CIC rate: 1
      send_ramp(port, 12);                      // HBs enabled: 2, CIC rate: 3
      send_ramp(port, 13);                      // HBs enabled: 0, CIC rate: 13
      if (EXTENDED_TEST) send_ramp(port, 16);   // HBs enabled: 3, CIC rate: 2
      if (EXTENDED_TEST) send_ramp(port, 24);   // HBs enabled: 3, CIC rate: 3
      send_ramp(port, 40);                      // HBs enabled: 3, CIC rate: 5
      if (EXTENDED_TEST) send_ramp(port, 200);  // HBs enabled: 3, CIC rate: 25
      send_ramp(port, 255);                     // HBs enabled: 0, CIC rate: 255
      if (EXTENDED_TEST) send_ramp(port, 2040); // HBs enabled: 3, CIC rate: 255

      test.end_test();
    end


    //-------------------------------------------------------------------------
    // Test timed tune
    //-------------------------------------------------------------------------

    // This test has not been implemented because the RFNoC FFT has not been
    // ported yet.


    //-------------------------------------------------------------------------
    // Test passing through a partial packet
    //-------------------------------------------------------------------------

    test.start_test("Pass through partial packet");
    send_ramp(port, 2, 0, 4);
    send_ramp(port, 3, 0, 4);
    send_ramp(port, 4, 0, 4);
    if (EXTENDED_TEST) send_ramp(port, 8, 0, 4);
    send_ramp(port, 13, 0, 4);
    if (EXTENDED_TEST) send_ramp(port, 24, 0, 4);
    test.end_test();


    //-------------------------------------------------------------------------
    // Finish
    //-------------------------------------------------------------------------

    // End the TB, but don't $finish, since we don't want to kill other
    // instances of this testbench that may be running.
    test.end_tb(0);

    // Kill the clocks to end this instance of the testbench
    rfnoc_chdr_clk_gen.kill();
    rfnoc_ctrl_clk_gen.kill();
    ddc_clk_gen.kill();
  end
endmodule
