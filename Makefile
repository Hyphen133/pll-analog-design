TOP := tt_um_hyphen133_adpll
CORE := adpll
RTL := src/adpll.v
WRAPPER := src/tt_um_hyphen133_adpll.v
TB := tb/tb_adpll.sv
BUILD := build
YOSYS ?= yosys
IVERILOG ?= iverilog
VVP ?= vvp
LIBRELANE ?= librelane

.PHONY: all model lint sim tt-test tt-test-gl synth layout layout-docker clean

all: model synth

$(BUILD):
	mkdir -p $(BUILD)

model:
	python3 scripts/model_adpll.py

lint: | $(BUILD)
	$(YOSYS) -p 'read_verilog -sv $(RTL) $(WRAPPER); hierarchy -check -top $(TOP); proc; check'

# Core-level self-checking testbench (Icarus, no cocotb required).
sim: | $(BUILD)
	$(IVERILOG) -g2012 -Wall -s tb_adpll -o $(BUILD)/tb_adpll $(TB) $(RTL)
	$(VVP) $(BUILD)/tb_adpll

# Tiny Tapeout cocotb suite, driven only through the tt_um_* pins.
tt-test:
	$(MAKE) -C test -B

# Same suite against the hardened netlist.  Copy the GDS action's
# results/final/verilog/gl/$(TOP).v to test/gate_level_netlist.v first.
tt-test-gl:
	$(MAKE) -C test -B GATES=yes

synth: | $(BUILD)
	$(YOSYS) -l $(BUILD)/synthesis.log synth/synth.ys

# Requires LibreLane/OpenLane and a sky130A PDK.  The final GDS, DEF, metrics,
# and signoff reports appear under openlane/runs/RUN_*/final.  Note this
# hardens the bare ADPLL core on Sky130; the Tiny Tapeout submission itself is
# hardened on IHP SG13G2 by .github/workflows/gds.yaml.
layout:
	cd openlane && $(LIBRELANE) --pdk sky130A --run-tag RUN_PLL --overwrite config.json

# Use when LibreLane's EDA tools are supplied by its Docker image.
layout-docker:
	cd openlane && $(LIBRELANE) --docker-no-tty --dockerized --pdk sky130A --run-tag RUN_PLL --overwrite config.json

clean:
	rm -rf $(BUILD) openlane/runs/RUN_PLL
	$(MAKE) -C test clean 2>/dev/null || true
