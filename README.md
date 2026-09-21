![](../../workflows/gds/badge.svg) ![](../../workflows/docs/badge.svg) ![](../../workflows/test/badge.svg) ![](../../workflows/fpga/badge.svg)

# All-Digital PLL (ADPLL) — Tiny Tapeout project

A fully synthesizable all-digital phase-locked loop in Verilog, packaged as a
[Tiny Tapeout](https://tinytapeout.com) project on top of the
[ttihp-verilog-template](https://github.com/TinyTapeout/ttihp-verilog-template)
(IHP SG13G2).

The core is a 24-bit NCO steered by a PI loop filter. Because the
frequency-control word is a ratio of the control clock, the design is
clock-rate independent: with `ref_clk = clk / 10` it locks `pll_clk` to
`4 × ref_clk = 0.4 × clk`.

> This is a **digital/NCO PLL**, not a transistor-level charge-pump PLL.
> `pll_clk` is a usable clock-like output, but its edges are quantized to the
> control clock. A low-jitter analog/RF PLL needs custom analog cells and
> cannot be synthesized by Yosys.

See [docs/info.md](docs/info.md) for the datasheet: theory of operation, the
full pin map, the debug-bus encoding and the bring-up procedure.

## Pin map

| Pin        | Name      | Direction | Function                              |
| ---------- | --------- | --------- | ------------------------------------- |
| `ui[0]`    | ENABLE    | in        | Loop enable; low holds the NCO reset  |
| `ui[1]`    | REF_CLK   | in        | Reference clock, nominally `clk / 10` |
| `ui[4:2]`  | DBG_SEL   | in        | Selects the debug byte on `uio`       |
| `uo[0]`    | PLL_CLK   | out       | NCO output, `4 × REF_CLK` when locked |
| `uo[1]`    | LOCKED    | out       | Lock detect                           |
| `uo[2]`    | REF_ECHO  | out       | `REF_CLK` re-registered on `clk`      |
| `uo[3]`    | ERR_SIGN  | out       | Sign bit of the phase error           |
| `uio[7:0]` | DBG[7:0]  | out       | Debug byte (bus is output-only)       |

## Layout

```
info.yaml                       Tiny Tapeout project metadata and pinout
docs/info.md                    datasheet source
src/tt_um_hyphen133_adpll.v     Tiny Tapeout top level (pin mapping, debug mux)
src/adpll.v                     the ADPLL core
src/config.json                 LibreLane config used by the GDS action
test/                           cocotb suite driven through the tt_um_* pins
tb/tb_adpll.sv                  core-level self-checking Icarus testbench
scripts/model_adpll.py          dependency-free cycle model and smoke test
synth/synth.ys                  generic Yosys synthesis of the TT top level
openlane/                       standalone Sky130 hardening of the bare core
.github/workflows/              TT GDS, docs, test and FPGA actions
```

`src/` is the single source of truth for the RTL — Tiny Tapeout requires it
there, and the local Yosys/OpenLane flows read from the same files.

## Run

```bash
make model        # cycle model, pure Python
make tt-test      # Tiny Tapeout cocotb suite  (needs iverilog + cocotb)
make sim          # core-level SV testbench    (needs iverilog)
make lint         # Yosys elaboration check    (needs yosys)
make synth        # generic gate mapping       (needs yosys)
```

Install the cocotb dependencies once with `pip install -r test/requirements.txt`.

Gate-level simulation, after the GDS action has hardened the design: copy
`results/final/verilog/gl/tt_um_hyphen133_adpll.v` to
`test/gate_level_netlist.v`, then `make tt-test-gl`.

The Tiny Tapeout GDS is built by `.github/workflows/gds.yaml` on every push —
no local PDK needed. The `openlane/` directory is a separate, optional Sky130
hardening of the bare `adpll` core:

```bash
make layout                                      # needs LibreLane + sky130A
make layout-docker LIBRELANE=/path/to/librelane  # containerized toolchain
```

## Tiny Tapeout

To publish the results page, enable GitHub Pages for this repository
(Settings → Pages → Source: GitHub Actions). Submission instructions live at
[tinytapeout.com](https://tinytapeout.com) and the HDL docs at
[tinytapeout.com/hdl](https://tinytapeout.com/hdl/).

## License

Apache-2.0. See [LICENSE](LICENSE).
