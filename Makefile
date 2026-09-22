NGSPICE ?= ngspice
SPICE   := spice
PYTHON  ?= python3

# Point this at a checkout of https://github.com/IHP-GmbH/IHP-Open-PDK
IHP_PDK_ROOT ?= $(HOME)/IHP-Open-PDK

.PHONY: help generic ihp pdk logic vco pll all filter clean

help:
	@echo "Device model selection:"
	@echo "  make generic     use level-1 stand-ins (works on any ngspice)"
	@echo "  make ihp         use the IHP PSP103 models (needs ngspice with OSDI)"
	@echo "  make pdk         link spice/pdk to \$$IHP_PDK_ROOT"
	@echo ""
	@echo "Simulations:"
	@echo "  make logic       PFD, flip-flop clear and divider checks"
	@echo "  make vco         VCO tuning curve, prints Kvco table"
	@echo "  make pll         closed-loop lock test"
	@echo "  make all         all three"
	@echo ""
	@echo "  make filter      re-derive the loop filter from a measured Kvco"

# The testbenches include devices.spice; this selects which models it means.
generic:
	ln -sfn devices_generic.spice $(SPICE)/devices.spice
	@echo "devices.spice -> devices_generic.spice"

ihp: pdk
	ln -sfn devices_ihp.spice $(SPICE)/devices.spice
	@echo "devices.spice -> devices_ihp.spice"

pdk:
	@test -d "$(IHP_PDK_ROOT)/ihp-sg13g2/libs.tech/ngspice/models" || \
		{ echo "IHP_PDK_ROOT=$(IHP_PDK_ROOT) does not look like an IHP-Open-PDK checkout"; exit 1; }
	ln -sfn "$(IHP_PDK_ROOT)/ihp-sg13g2/libs.tech/ngspice/models" $(SPICE)/pdk

$(SPICE)/devices.spice:
	$(MAKE) generic

logic: $(SPICE)/devices.spice
	cd $(SPICE) && $(NGSPICE) -b tb/tb_logic.spice

vco: $(SPICE)/devices.spice
	cd $(SPICE) && $(NGSPICE) -b tb/tb_vco.spice

pll: $(SPICE)/devices.spice
	cd $(SPICE) && $(NGSPICE) -b tb/tb_pll.spice

all: logic vco pll

filter:
	$(PYTHON) scripts/loop_filter.py

clean:
	rm -f $(SPICE)/*.raw $(SPICE)/tb/*.raw
