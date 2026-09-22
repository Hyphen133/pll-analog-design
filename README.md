![](../../workflows/gds/badge.svg) ![](../../workflows/docs/badge.svg)

# Analog Charge-Pump PLL — Tiny Tapeout (IHP SG13G2)

A transistor-level analog PLL: phase-frequency detector, current-steering
charge pump, on-chip RC loop filter, current-starved ring VCO and a ÷8
feedback divider. 25 MHz reference in, 200 MHz out.

No accumulator, no digital loop filter — the control voltage is a real voltage
on a real MIM capacitor. See [docs/info.md](docs/info.md) for the datasheet.

> An earlier standard-cell **digital** ADPLL version of this project is kept at
> the tag [`digital-adpll`](../../tree/digital-adpll). It was replaced because
> it was not an analog design.

## Status

| Item | State |
| ---- | ----- |
| Architecture + transistor-level netlists | **done** — `spice/` |
| PFD / flip-flop / divider logic verified | **done** — see below |
| Closed-loop lock verified | **done, generic devices** |
| Loop filter sized from measured Kvco | **done** — `scripts/loop_filter.py` |
| Device-accurate sim with IHP PSP103 | **blocked** — see [Simulation](#device-accurate-simulation) |
| Layout: `gds/` + `lef/` | **not started** — required before submission |

**This cannot be submitted to Tiny Tapeout yet.** An analog project is
hardened by `TinyTapeout/tt-gds-action/custom_gds`, which does not synthesise
anything: it packages a GDS and a LEF that you draw yourself in Magic or
KLayout. Until `gds/tt_um_hyphen133_pll.gds` and
`lef/tt_um_hyphen133_pll.lef` exist, the `gds` workflow will fail — that is
expected at this stage, not a regression.

## Simulation results

All numbers below are from generic level-1 devices (see
[Device-accurate simulation](#device-accurate-simulation)), so they validate
topology, polarity and loop dynamics, **not** silicon-accurate frequencies.

```
$ make logic
flip-flop clear -> Q          3.5 uV at 2 ns, 1.800 V at 100 ns
PFD, ref leads fb by 4 ns     UP 4.115 ns, DN 0.113 ns
divide ratio                  7.9996

$ make pll
vctrl at 1 / 3 / 5 us         0.9191 / 0.9193 / 0.9210 V
f_vco                         200.014 MHz   (target 8 x 25 MHz)
divide ratio                  8.0035
```

The narrow DN pulse when locked is the deliberate anti-dead-zone overlap, not
an error.

## Layout of the repository

```
spice/cells.spice        inverter, NAND2/3, transmission gate, D and T flops
spice/vco.spice          bias generator, starved inverter, 5-stage ring
spice/blocks.spice       PFD, charge pump, bias, loop filter, divide-by-8
spice/pll_top.spice      the closed loop
spice/devices_generic.spice  level-1 stand-ins for the IHP primitives
spice/devices_ihp.spice      the real PSP103 corner libs
spice/tb/                testbenches
scripts/loop_filter.py   loop filter sizing from Icp, Kvco, N, fn, zeta
src/project.v            empty black box; TT needs the port list only
info.yaml                TT metadata, pinout, analog pin count
gds/, lef/               hand-drawn layout goes here (not yet present)
```

## Running the simulations

```bash
make generic     # select the level-1 stand-in devices
make logic       # PFD, flip-flop clear, divider
make vco         # VCO tuning curve
make pll         # closed-loop lock
make filter      # re-derive R, C1, C2 from a measured Kvco
```

Needs only a stock `ngspice`.

### Device-accurate simulation

`make ihp IHP_PDK_ROOT=/path/to/IHP-Open-PDK` switches the same testbenches to
the real models, but it will not run on a stock ngspice:

- The IHP SG13G2 models are **PSP103 Verilog-A**. They need an ngspice built
  with OSDI support plus compiled `psp103.osdi` / `r3_cmc.osdi` binaries
  (`.spiceinit` in the PDK expects them under `libs.tech/ngspice/osdi/`).
- Those `.osdi` files are **not** shipped in the PDK repo or its releases. They
  are built from `libs.tech/verilog-a/psp103/` with OpenVAF, and `.osdi` is a
  compiled shared object, so it must match your architecture.
- A stock ngspice reports `Unknown model type psp103va` and stops.

The easiest route is a prebuilt environment such as IIC-OSIC-TOOLS, which
ships ngspice, OpenVAF and the IHP PDK already wired together. Once it runs,
re-extract Kvco with `make vco`, feed it to `make filter`, and update the
`loop_filter` defaults in `spice/blocks.spice`.

## License

Apache-2.0. See [LICENSE](LICENSE).
