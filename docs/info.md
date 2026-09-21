<!---

This file is used to generate your project datasheet. Please fill in the information below and delete any unused
sections.

You can also include images in this folder and reference them in the markdown. Each image must be less than
512 kb in size, and the combined size of all images must be less than 1 MB.
-->

## How it works

This is an **all-digital PLL (ADPLL)**. There is no charge pump, no VCO and no
analog cell anywhere in the design — it is ordinary synthesizable logic, so it
hardens through the standard Tiny Tapeout flow.

The core is a 24-bit **numerically-controlled oscillator (NCO)**. A phase
accumulator adds a frequency-control word (FCW) to itself on every control-clock
edge, and the accumulator's MSB is the output clock:

```
pll_clk frequency = clk * FCW / 2**24
```

On every rising edge of the external reference, the wrapped accumulator phase is
taken as the phase error and fed to a **PI loop filter**:

- proportional term: `error >> 3`
- integral term: accumulated `error >> 7`, saturated to ±2²²
- the sum is clamped to `FCW ∈ [4194304, 7864320]`, i.e. `0.25·clk … 0.469·clk`

Because the control word is a *ratio* of the control clock, the behaviour is
independent of the absolute clock rate. The loop settles on whichever reference
harmonic falls inside the FCW range nearest the nominal word, so with
`ref_clk = clk / 10` it locks on **4 × ref_clk = 0.4 × clk**.

A lock detector asserts `LOCKED` after 16 consecutive reference edges with
`|phase error| ≤ 16384`, and drops it if the error exceeds 65536. A separate
watchdog clears `LOCKED` if no reference edge arrives for 64 control cycles, so
a dead or disconnected reference is reported rather than silently free-running.
The reference is brought into the control-clock domain through a three-stage
synchronizer.

`uio` is an output-only debug bus. `DBG_SEL` (`ui[4:2]`) picks which byte of the
internal state appears on it:

| DBG_SEL | uio[7:0]                          |
| ------- | --------------------------------- |
| 0       | `phase_error[7:0]`                |
| 1       | `phase_error[15:8]`               |
| 2       | `phase_error[23:16]`              |
| 3       | `frequency_word[7:0]`             |
| 4       | `frequency_word[15:8]`            |
| 5       | `frequency_word[23:16]`           |
| 6       | `{5'b0, enable, locked, pll_clk}` |
| 7       | `0x00`                            |

### Caveat

`pll_clk` edges are quantized to the control clock, so this is a frequency
synthesizer with deterministic jitter of up to one control-clock period — not a
low-jitter analog/RF PLL. Use it as a clock-like digital output, not as a
reference for something jitter-sensitive.

## How to test

1. Drive `clk` at the project clock rate (50 MHz nominal) and release `rst_n`.
2. Drive `ui[1]` (`REF_CLK`) with a square wave at **clk / 10** (5 MHz at the
   nominal rate). The reference is asynchronous to `clk`; no phase relationship
   is required.
3. Set `ui[0]` (`ENABLE`) high.
4. Within a few thousand control cycles `uo[1]` (`LOCKED`) goes high and `uo[0]`
   (`PLL_CLK`) runs at 4 × `REF_CLK` (20 MHz at the nominal rate).
5. Read back the settled control word: set `ui[4:2] = 5`, then `4`, and read
   `uio[7:0]` each time — the top two bytes should read ≈ `0x66 0x66`
   (0.4 · 2²⁴).
6. Stop the reference (hold `ui[1]` static). `LOCKED` must fall within ~64
   control cycles.
7. `uo[2]` (`REF_ECHO`) is the reference re-registered on `clk`; scope it against
   `PLL_CLK` to see the 4:1 ratio directly.

The cocotb suite in `test/` automates all of the above:

```sh
cd test
make -B            # RTL
make -B GATES=yes  # gate level, after hardening
```

## External hardware

None required. A signal generator or any spare clock source for `REF_CLK`, and
an oscilloscope or logic analyser on `PLL_CLK` / `REF_ECHO`, are enough to
exercise the design.
