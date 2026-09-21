/*
 * Tiny Tapeout wrapper for the synthesizable all-digital PLL (ADPLL).
 *
 * Copyright (c) 2026 Hyphen133
 * SPDX-License-Identifier: Apache-2.0
 *
 * Pin map
 * -------
 *   ui_in[0]     enable         loop enable (low holds the NCO in reset)
 *   ui_in[1]     ref_clk        reference clock, nominally clk/10
 *   ui_in[4:2]   dbg_sel        selects which debug byte appears on uio_out
 *   ui_in[7:5]   -              unused
 *
 *   uo_out[0]    pll_clk        NCO output clock (~4x ref_clk when locked)
 *   uo_out[1]    locked         lock-detect flag
 *   uo_out[2]    ref_echo       ref_clk re-registered on clk (scope reference)
 *   uo_out[3]    err_sign       sign bit of phase_error
 *   uo_out[7:4]  -              tied low
 *
 *   uio_out[7:0] dbg_byte       debug byte selected by dbg_sel (always driven)
 *   uio_in       -              unused
 *
 * The loop locks pll_clk to the reference harmonic nearest NOMINAL_FCW.  The
 * frequency-control word is a ratio of the control clock, so the mapping is
 * clock-rate independent: pll_clk = clk * FCW / 2**PHASE_WIDTH, constrained to
 * 0.25*clk .. 0.469*clk.  With ref_clk = clk/10 the loop settles on 4*ref_clk.
 */

`default_nettype none

module tt_um_hyphen133_adpll (
    input  wire [7:0] ui_in,    // Dedicated inputs
    output wire [7:0] uo_out,   // Dedicated outputs
    input  wire [7:0] uio_in,   // IOs: Input path
    output wire [7:0] uio_out,  // IOs: Output path
    output wire [7:0] uio_oe,   // IOs: Enable path (active high: 0=input, 1=output)
    input  wire       ena,      // always 1 when the design is powered
    input  wire       clk,      // clock
    input  wire       rst_n     // reset_n - low to reset
);

  localparam integer PHASE_WIDTH = 24;

  // Debug byte selector encodings carried on ui_in[4:2].
  localparam [2:0] DBG_PHASE_ERROR_B0 = 3'd0;
  localparam [2:0] DBG_PHASE_ERROR_B1 = 3'd1;
  localparam [2:0] DBG_PHASE_ERROR_B2 = 3'd2;
  localparam [2:0] DBG_FREQ_WORD_B0   = 3'd3;
  localparam [2:0] DBG_FREQ_WORD_B1   = 3'd4;
  localparam [2:0] DBG_FREQ_WORD_B2   = 3'd5;
  localparam [2:0] DBG_STATUS         = 3'd6;

  wire enable  = ui_in[0];
  wire ref_clk = ui_in[1];
  wire [2:0] dbg_sel = ui_in[4:2];

  wire pll_clk;
  wire locked;
  wire signed [PHASE_WIDTH-1:0] phase_error;
  wire        [PHASE_WIDTH-1:0] frequency_word;

  adpll #(
      .PHASE_WIDTH(PHASE_WIDTH)
  ) u_adpll (
      .clk           (clk),
      .rst_n         (rst_n),
      .enable        (enable),
      .ref_clk       (ref_clk),
      .pll_clk       (pll_clk),
      .locked        (locked),
      .phase_error   (phase_error),
      .frequency_word(frequency_word)
  );

  // Re-register the reference so the echo pin is driven from a flop rather
  // than straight through from a pad.
  reg ref_echo;
  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) ref_echo <= 1'b0;
    else ref_echo <= ref_clk;
  end

  reg [7:0] dbg_byte;
  always @* begin
    case (dbg_sel)
      DBG_PHASE_ERROR_B0: dbg_byte = phase_error[7:0];
      DBG_PHASE_ERROR_B1: dbg_byte = phase_error[15:8];
      DBG_PHASE_ERROR_B2: dbg_byte = phase_error[23:16];
      DBG_FREQ_WORD_B0:   dbg_byte = frequency_word[7:0];
      DBG_FREQ_WORD_B1:   dbg_byte = frequency_word[15:8];
      DBG_FREQ_WORD_B2:   dbg_byte = frequency_word[23:16];
      DBG_STATUS:         dbg_byte = {5'b0, enable, locked, pll_clk};
      default:            dbg_byte = 8'h00;
    endcase
  end

  assign uo_out  = {4'b0, phase_error[PHASE_WIDTH-1], ref_echo, locked, pll_clk};
  assign uio_out = dbg_byte;
  assign uio_oe  = 8'hFF;  // uio bus is output-only

  // List all unused inputs to prevent warnings
  wire _unused = &{ena, uio_in, ui_in[7:5], 1'b0};

endmodule

`default_nettype wire
