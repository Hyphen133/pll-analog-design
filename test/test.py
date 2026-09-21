# SPDX-FileCopyrightText: © 2026 Hyphen133
# SPDX-License-Identifier: Apache-2.0
"""Cocotb tests for the Tiny Tapeout ADPLL wrapper.

Only top-level pins are driven and sampled, so the same tests pass against the
RTL and against the gate-level netlist (``make -B GATES=yes``).
"""

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles, FallingEdge

# Simulation timing.  The control clock runs at 100 MHz here; the design itself
# is ratio-based, so the numbers below hold for any control-clock rate.
CLK_PERIOD_NS = 10
REF_HALF_PERIOD_CYCLES = 5  # ref_clk = clk / 10

# ui_in bit assignments.
ENABLE_BIT = 0
REF_CLK_BIT = 1
DBG_SEL_SHIFT = 2

# uo_out bit assignments.
PLL_CLK_BIT = 0
LOCKED_BIT = 1
REF_ECHO_BIT = 2
ERR_SIGN_BIT = 3

# Debug byte selectors on ui_in[4:2].
DBG_FREQ_WORD_B1 = 4
DBG_FREQ_WORD_B2 = 5
DBG_STATUS = 6

RESET_CYCLES = 10
LOCK_TIMEOUT_CYCLES = 4000
MEASURE_CYCLES = 500
REF_LOSS_CYCLES = 120

# When locked the NCO runs at 4 * ref_clk = 0.4 * clk, so 500 control cycles
# contain 200 output periods and the frequency-control word sits at
# 0.4 * 2**24.  One period of slack absorbs the phase-accumulator quantisation.
EXPECTED_OUTPUT_EDGES = 200
OUTPUT_EDGE_TOLERANCE = 1
PHASE_WIDTH = 24
EXPECTED_FCW = round(0.4 * (1 << PHASE_WIDTH))
FCW_TOLERANCE_PCT = 2.0


class PinDriver:
    """Owns ui_in so the reference generator and the tests can share the bus."""

    def __init__(self, dut):
        self._dut = dut
        self._enable = 0
        self._ref_clk = 0
        self._dbg_sel = 0
        self.ref_enabled = True
        self._drive()

    def _drive(self):
        self._dut.ui_in.value = (
            (self._enable << ENABLE_BIT)
            | (self._ref_clk << REF_CLK_BIT)
            | (self._dbg_sel << DBG_SEL_SHIFT)
        )

    def set_enable(self, value):
        self._enable = int(bool(value))
        self._drive()

    def set_ref_clk(self, value):
        self._ref_clk = int(bool(value))
        self._drive()

    def toggle_ref_clk(self):
        self.set_ref_clk(not self._ref_clk)

    def set_dbg_sel(self, value):
        self._dbg_sel = value & 0b111
        self._drive()


async def _drive_reference(dut, pins):
    """Reference clock at clk / 10 on ui_in[1]; returns once disabled."""
    while True:
        await ClockCycles(dut.clk, REF_HALF_PERIOD_CYCLES)
        if not pins.ref_enabled:
            return
        pins.toggle_ref_clk()


def _pin(handle, index):
    """Read one bit of a bus, treating unresolved values as 0."""
    try:
        return (int(handle.value) >> index) & 1
    except ValueError:
        return 0


async def _reset(dut, pins):
    dut.ena.value = 1
    dut.uio_in.value = 0
    dut.rst_n.value = 0
    pins.set_enable(0)
    pins.set_dbg_sel(0)
    await ClockCycles(dut.clk, RESET_CYCLES)
    dut.rst_n.value = 1
    await ClockCycles(dut.clk, 1)


async def _wait_for_lock(dut):
    """Return the number of control cycles taken to lock, or None on timeout."""
    for cycle in range(LOCK_TIMEOUT_CYCLES):
        await FallingEdge(dut.clk)
        if _pin(dut.uo_out, LOCKED_BIT):
            return cycle
    return None


async def _count_output_edges(dut, cycles):
    """Count pll_clk rising edges over `cycles` control-clock periods."""
    edges = 0
    previous = _pin(dut.uo_out, PLL_CLK_BIT)
    for _ in range(cycles):
        await FallingEdge(dut.clk)
        current = _pin(dut.uo_out, PLL_CLK_BIT)
        if current and not previous:
            edges += 1
        previous = current
    return edges


async def _read_debug_byte(dut, pins, selector):
    pins.set_dbg_sel(selector)
    await FallingEdge(dut.clk)
    return int(dut.uio_out.value) & 0xFF


async def _start_locked_pll(dut):
    """Bring the DUT out of reset with a live reference and wait for lock.

    Cocotb tears down the tasks a test started when that test ends, so every
    test starts its own clock and reference generator.
    """
    pins = PinDriver(dut)
    cocotb.start_soon(Clock(dut.clk, CLK_PERIOD_NS, unit="ns").start())
    cocotb.start_soon(_drive_reference(dut, pins))

    await _reset(dut, pins)
    pins.set_enable(1)

    lock_cycles = await _wait_for_lock(dut)
    assert lock_cycles is not None, (
        f"PLL did not lock within {LOCK_TIMEOUT_CYCLES} control cycles"
    )
    dut._log.info(f"Locked after {lock_cycles} control cycles")
    return pins


@cocotb.test()
async def test_locks_and_tracks_reference(dut):
    """The NCO locks to 4x the reference and holds that ratio."""
    await _start_locked_pll(dut)

    edges = await _count_output_edges(dut, MEASURE_CYCLES)

    assert abs(edges - EXPECTED_OUTPUT_EDGES) <= OUTPUT_EDGE_TOLERANCE, (
        f"expected {EXPECTED_OUTPUT_EDGES} +/- {OUTPUT_EDGE_TOLERANCE} output "
        f"cycles in {MEASURE_CYCLES} control cycles, got {edges}"
    )


@cocotb.test()
async def test_bidir_bus_reports_control_word(dut):
    """uio is an output-only bus carrying the settled frequency-control word."""
    pins = await _start_locked_pll(dut)

    assert int(dut.uio_oe.value) == 0xFF, "uio_oe must drive the whole bus"

    byte2 = await _read_debug_byte(dut, pins, DBG_FREQ_WORD_B2)
    byte1 = await _read_debug_byte(dut, pins, DBG_FREQ_WORD_B1)

    # The two most significant bytes are enough to confirm the ratio and are
    # insensitive to the dither in the low bits of the control word.
    measured_fcw_hi = (byte2 << 8) | byte1
    expected_fcw_hi = EXPECTED_FCW >> 8
    tolerance = expected_fcw_hi * FCW_TOLERANCE_PCT / 100.0
    assert abs(measured_fcw_hi - expected_fcw_hi) <= tolerance, (
        f"frequency word {measured_fcw_hi} (x256) is more than "
        f"{FCW_TOLERANCE_PCT}% away from the expected {expected_fcw_hi}"
    )


@cocotb.test()
async def test_status_byte_mirrors_lock(dut):
    """Debug selector 6 exposes the enable and lock flags."""
    pins = await _start_locked_pll(dut)

    status = await _read_debug_byte(dut, pins, DBG_STATUS)

    assert (status >> 1) & 1 == 1, "status byte must report locked"
    assert (status >> 2) & 1 == 1, "status byte must report enable"


@cocotb.test()
async def test_reference_loss_clears_lock(dut):
    """Freezing the reference must drop the lock flag."""
    pins = await _start_locked_pll(dut)

    pins.ref_enabled = False
    pins.set_ref_clk(0)
    await ClockCycles(dut.clk, REF_LOSS_CYCLES)

    assert _pin(dut.uo_out, LOCKED_BIT) == 0, (
        "reference-loss watchdog did not clear lock"
    )
