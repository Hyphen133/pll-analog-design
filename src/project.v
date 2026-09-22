/*
 * Analog charge-pump PLL - Tiny Tapeout black box.
 *
 * Copyright (c) 2026 Hyphen133
 * SPDX-License-Identifier: Apache-2.0
 *
 * This module is intentionally empty.  For an analog project Tiny Tapeout
 * takes the real circuit from gds/tt_um_hyphen133_pll.gds and the pin frame
 * from lef/tt_um_hyphen133_pll.lef; this file only declares the port list so
 * the harness can be elaborated and LVS has a reference interface.
 *
 * The circuit itself lives in spice/ as a SPICE hierarchy:
 *   spice/pll_top.spice  PFD -> charge pump -> loop filter -> VCO -> div8
 *
 * Pin map
 * -------
 *   clk        25 MHz reference
 *   ui_in[0]   RSTB, releases the divider reset
 *   uo_out[0]  DIV_OUT, VCO / 8 (25 MHz when locked)
 *   uo_out[1]  UP, PFD up pulse
 *   uo_out[2]  DN, PFD down pulse
 *   ua[0]      VCTRL, loop filter node (probe or force)
 *   ua[1]      IBIAS, charge-pump bias current (overrides the on-chip resistor)
 */

`default_nettype none

module tt_um_hyphen133_pll (
    input  wire       VGND,
    input  wire       VDPWR,    // 1.8v power supply
//    input  wire       VAPWR,    // 3.3v power supply
    input  wire [7:0] ui_in,    // Dedicated inputs
    output wire [7:0] uo_out,   // Dedicated outputs
    input  wire [7:0] uio_in,   // IOs: Input path
    output wire [7:0] uio_out,  // IOs: Output path
    output wire [7:0] uio_oe,   // IOs: Enable path (active high: 0=input, 1=output)
    inout  wire [7:0] ua,       // Analog pins, only ua[5:0] can be used
    input  wire       ena,      // always 1 when the design is powered, so you can ignore it
    input  wire       clk,      // clock
    input  wire       rst_n     // reset_n - low to reset
);

endmodule

`default_nettype wire
