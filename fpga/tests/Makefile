# Regression tests for the Courier modem core. Run from this directory:
#
#   make test          lint + every unit test, prints a PASS/FAIL summary
#   make lint          verilator --lint-only on every top
#   make t_<name>      one test (see TESTS below)
#   make cosim_dsp     C-vs-RTL DSP co-sim on the firmware (needs ../../courier)
#   make clean
#
# Adding a test: write tb/tb_<name>.sv (self-checking, $fatal or a nonzero
# $finish on failure, prints "PASS" on success), then add one line to TESTS
# and one "<name>_SRCS" variable. Nothing else.

ROOT    := $(abspath ..)
RTL     := $(ROOT)/rtl
TB      := $(ROOT)/tb
BUILD   := $(ROOT)/build/tests
COURIER ?= $(abspath $(ROOT)/../courier)
VERILATOR ?= verilator
VFLAGS  ?= --binary --timing -Wno-fatal -Wno-lint -Wno-style -j 0

DSPPKG := $(RTL)/dsp/c5x_ctl_pkg.sv

TESTS := line_ddr cdc smoke smoke_rx smoke_irx sdram_probe sdram_probe_15 sdram_probe_23 sdram_probe_40 xdom_req bus_trace dbg_status sdram16 sdram16_120 sdram_arb c5x_xmem c5x_pbram mem186 dsp_glue aic loader dte_uart c5x_alu c5x_addr c5x_mem c5x_decode c5x_idle c5x_io i186_core i186_intret i186_cli i186_ack i186_crcstep i186_sys

# <test>_TOP: testbench module if it differs from tb_<test>; <test>_FLAGS: extra verilator flags (e.g. -G parameters)
sdram16_120_TOP   := tb_sdram16
sdram16_120_FLAGS := -GCL=3 -GHALF=4.1336
sdram16_120_SRCS  := $(RTL)/ram/sdram.sv $(TB)/models/sdram_chip.sv $(TB)/models/altddio_out.v
sdram_arb_SRCS   := $(RTL)/ram/sdram_arb.sv $(RTL)/ram/sdram.sv $(TB)/models/sdram_chip.sv $(TB)/models/altddio_out.v
c5x_xmem_SRCS   := $(RTL)/ram/c5x_xmem.sv $(RTL)/ram/sdram_arb.sv $(RTL)/ram/sdram.sv $(TB)/models/sdram_chip.sv $(TB)/models/altddio_out.v
mem186_SRCS     := $(RTL)/ram/mem186.sv $(RTL)/ram/sdram_arb.sv $(RTL)/ram/sdram.sv $(TB)/models/sdram_chip.sv $(TB)/models/altddio_out.v
dsp_glue_SRCS   := $(RTL)/dsp_glue.sv
aic_SRCS        := $(RTL)/aic.sv
loader_SRCS     := $(RTL)/loader.sv
dte_uart_SRCS   := $(RTL)/dte_uart.sv
dbg_status_SRCS := $(RTL)/dbg_status.sv
bus_trace_SRCS := $(RTL)/bus_trace.sv
xdom_req_SRCS := $(RTL)/ram/xdom_req.sv
sdram_probe_15_TOP := tb_sdram_probe
sdram_probe_15_FLAGS := -GDLY=15 -GEXPECT_CAP=1
sdram_probe_15_SRCS := $(RTL)/ram/sdram_probe.sv $(RTL)/ram/sdram_arb.sv $(RTL)/ram/sdram.sv $(TB)/models/sdram_chip.sv $(TB)/models/altddio_out.v
sdram_probe_23_TOP := tb_sdram_probe
sdram_probe_23_FLAGS := -GDLY=23 -GEXPECT_CAP=2
sdram_probe_23_SRCS := $(RTL)/ram/sdram_probe.sv $(RTL)/ram/sdram_arb.sv $(RTL)/ram/sdram.sv $(TB)/models/sdram_chip.sv $(TB)/models/altddio_out.v
sdram_probe_40_TOP := tb_sdram_probe
sdram_probe_40_FLAGS := -GDLY=40 -GEXPECT_CAP=0 -GEXPECT_OK=0
sdram_probe_40_SRCS := $(RTL)/ram/sdram_probe.sv $(RTL)/ram/sdram_arb.sv $(RTL)/ram/sdram.sv $(TB)/models/sdram_chip.sv $(TB)/models/altddio_out.v
sdram_probe_SRCS := $(RTL)/ram/sdram_probe.sv $(RTL)/ram/sdram_arb.sv $(RTL)/ram/sdram.sv $(TB)/models/sdram_chip.sv $(TB)/models/altddio_out.v
sdram16_SRCS    := $(RTL)/ram/sdram.sv $(TB)/models/sdram_chip.sv $(TB)/models/altddio_out.v
c5x_alu_SRCS    := $(RTL)/dsp/c5x_alu.sv
c5x_addr_SRCS   := $(RTL)/dsp/c5x_addr.sv
c5x_mem_SRCS    := $(RTL)/dsp/c5x_mem.sv
c5x_decode_SRCS := $(DSPPKG) $(RTL)/dsp/c5x_decode.sv
c5x_pbram_SRCS := $(RTL)/ram/c5x_pbram.sv
cdc_SRCS := $(RTL)/cdc.sv
line_ddr_SRCS := $(RTL)/line_ddr.sv
c5x_idle_SRCS := $(DSPPKG) $(RTL)/dsp/c5x_alu.sv $(RTL)/dsp/c5x_addr.sv $(RTL)/dsp/c5x_mem.sv $(RTL)/dsp/c5x_decode.sv $(RTL)/dsp/c5x_ctrl.sv $(RTL)/dsp/c5x_core.sv
c5x_idle_FLAGS := --public-flat-rw
c5x_io_SRCS := $(DSPPKG) $(RTL)/dsp/c5x_alu.sv $(RTL)/dsp/c5x_addr.sv $(RTL)/dsp/c5x_mem.sv $(RTL)/dsp/c5x_decode.sv $(RTL)/dsp/c5x_ctrl.sv $(RTL)/dsp/c5x_core.sv
c5x_io_FLAGS := --public-flat-rw
i186_core_SRCS  := $(RTL)/i186/i186_core.sv
i186_intret_SRCS := $(RTL)/i186/i186_core.sv
i186_cli_SRCS := $(RTL)/i186/i186_core.sv
i186_ack_SRCS := $(RTL)/i186/i186_core.sv
i186_crcstep_SRCS := $(RTL)/i186/i186_core.sv
i186_sys_SRCS   := $(RTL)/i186/i186_sys.sv

.PHONY: test lint clean $(addprefix t_,$(TESTS))
.NOTPARALLEL:

test:
	@fail=0; for t in $(TESTS); do \
	    if $(MAKE) -s t_$$t > $(BUILD)/$$t.log 2>&1 || ! mkdir -p $(BUILD); then \
	        echo "PASS  $$t"; \
	    else echo "FAIL  $$t   (see $(BUILD)/$$t.log)"; fail=1; fi; \
	done; \
	if [ $$fail = 0 ]; then echo "ALL PASS"; else echo "SOME FAILED"; exit 1; fi

$(BUILD):
	@mkdir -p $(BUILD)

define TEST_RULE
t_$(1): | $(BUILD)
	@mkdir -p $(BUILD)/$(1)
	@$(VERILATOR) $(VFLAGS) $$($(1)_FLAGS) --top-module $$(or $$($(1)_TOP),tb_$(1)) -Mdir $(BUILD)/$(1) \
	    $$($(1)_SRCS) $(TB)/$$(or $$($(1)_TOP),tb_$(1)).sv > $(BUILD)/$(1)/build.log 2>&1 \
	    || { grep -E '%Error' $(BUILD)/$(1)/build.log | head; exit 1; }
	@$(BUILD)/$(1)/V$$(or $$($(1)_TOP),tb_$(1)) | tee $(BUILD)/$(1)/run.log | tail -3
	@! grep -qE 'FAIL|[1-9][0-9]* (failed|errors)|%Error|MISMATCH|TIMEOUT' $(BUILD)/$(1)/run.log
	@grep -qE 'PASS|passed' $(BUILD)/$(1)/run.log
endef
$(foreach t,$(TESTS),$(eval $(call TEST_RULE,$(t))))

lint:
	$(VERILATOR) --lint-only -Wall -Wno-fatal --top-module c5x_core \
	    $(DSPPKG) $(RTL)/dsp/c5x_alu.sv $(RTL)/dsp/c5x_addr.sv $(RTL)/dsp/c5x_mem.sv \
	    $(RTL)/dsp/c5x_decode.sv $(RTL)/dsp/c5x_ctrl.sv $(RTL)/dsp/c5x_core.sv

clean:
	rm -rf $(BUILD)

# Whole-system boot of the real firmware (slow, needs ../../courier/fw/SV25.flash.bin and nvram.bin; not part of `make test`):
#   make system CLOCKS=30000000
ALLRTL := $(RTL)/cdc.sv $(RTL)/modem_core.sv $(RTL)/ram/sdram.sv $(RTL)/ram/sdram_arb.sv $(RTL)/ram/sdram_probe.sv $(RTL)/ram/xdom_req.sv $(RTL)/ram/mem186.sv $(RTL)/ram/c5x_pbram.sv $(RTL)/loader.sv $(RTL)/dte_uart.sv \
          $(RTL)/aic.sv $(RTL)/bus_trace.sv $(RTL)/dsp_glue.sv $(RTL)/i186/i186_top.sv $(RTL)/i186/i186_core.sv $(RTL)/i186/i186_sys.sv $(DSPPKG) $(RTL)/dsp/c5x_alu.sv \
          $(RTL)/dsp/c5x_addr.sv $(RTL)/dsp/c5x_mem.sv $(RTL)/dsp/c5x_decode.sv $(RTL)/dsp/c5x_ctrl.sv $(RTL)/dsp/c5x_core.sv
CLOCKS ?= 20000000
.PHONY: system system_build
system_build:
	@mkdir -p $(BUILD)/system
	$(VERILATOR) --binary --timing -O3 --x-assign fast --x-initial fast -Wno-fatal -Wno-lint -Wno-style -j 0 --top-module tb_modem_core -Mdir $(BUILD)/system \
	    $(ALLRTL) $(TB)/models/sdram_chip.sv $(TB)/models/altddio_out.v $(TB)/tb_modem_core.sv > $(BUILD)/system/build.log 2>&1 || { grep -E '%Error' $(BUILD)/system/build.log | head; exit 1; }
system: system_build
	cd $(COURIER) && $(BUILD)/system/Vtb_modem_core +clocks=$(CLOCKS) $(SYSARGS) 2>&1 | tee $(BUILD)/system/run.log | tail -40

# end-to-end smoke (a few seconds): tiny 186 + DSP programs from tb/smoke/make_smoke.py through the real loader, SDRAM model, both cores and the glue
.PHONY: t_smoke
t_smoke: system_build
	@python3 $(TB)/smoke/make_smoke.py $(BUILD)/smoke > /dev/null
	@mkdir -p $(BUILD)/smoke
	@cd $(BUILD)/smoke && $(BUILD)/system/Vtb_modem_core +clocks=2000000 +smoke +start=7C000 +flash=$(BUILD)/smoke/flash_smoke.bin +nvram=$(BUILD)/smoke/nvram_smoke.bin +rom=$(BUILD)/smoke/rom_smoke.bin +sendat=1 > run.log 2>&1; grep -E 'dte byte|PASS|FAIL' run.log | tail -6
	@grep -q 'PASS tb_modem_core' $(BUILD)/smoke/run.log
	@grep -q 'ROM image in the DSP block RAM: PASS' $(BUILD)/smoke/run.log

# serial receive through the real pin: the tiny 186 echoes a byte (+1) clocked in at 115200 8N1 on UART_RXD
.PHONY: t_smoke_rx
t_smoke_rx: system_build
	@python3 $(TB)/smoke/make_smoke.py $(BUILD)/smoke > /dev/null
	@mkdir -p $(BUILD)/smoke
	@cd $(BUILD)/smoke && $(BUILD)/system/Vtb_modem_core +clocks=4000000 +smokerx +start=7C000 +flash=$(BUILD)/smoke/flash_smoke_rx.bin +nvram=$(BUILD)/smoke/nvram_smoke.bin +sendat=1 > run_rx.log 2>&1; grep -E 'dte byte|PASS|FAIL' run_rx.log | tail -5
	@grep -q 'PASS tb_modem_core' $(BUILD)/smoke/run_rx.log

# interrupt-driven serial receive like the firmware: two bytes back to back, the handler reads RBUF only
.PHONY: t_smoke_irx
t_smoke_irx: system_build
	@python3 $(TB)/smoke/make_smoke.py $(BUILD)/smoke > /dev/null
	@mkdir -p $(BUILD)/smoke
	@cd $(BUILD)/smoke && $(BUILD)/system/Vtb_modem_core +clocks=5000000 +smokeirx +start=7C000 +flash=$(BUILD)/smoke/flash_smoke_irx.bin +nvram=$(BUILD)/smoke/nvram_smoke.bin +sendat=1 > run_irx.log 2>&1; grep -E 'dte byte|PASS|FAIL' run_irx.log | tail -5
	@grep -q 'PASS tb_modem_core' $(BUILD)/smoke/run_irx.log

# DSP core benchmark (clocks per model cycle) and golden trace: make bench [BENCHARGS="+trace=1 +clocks=2000000"]
BENCHSRCS := $(DSPPKG) $(RTL)/dsp/c5x_alu.sv $(RTL)/dsp/c5x_addr.sv $(RTL)/dsp/c5x_mem.sv $(RTL)/dsp/c5x_decode.sv $(RTL)/dsp/c5x_ctrl.sv $(RTL)/dsp/c5x_core.sv
.PHONY: bench
bench:
	@mkdir -p $(BUILD)/bench
	@$(VERILATOR) $(VFLAGS) --public-flat-rw --top-module tb_c5x_bench -Mdir $(BUILD)/bench $(BENCHSRCS) $(TB)/tb_c5x_bench.sv > $(BUILD)/bench/build.log 2>&1 || { grep -E '%Error' $(BUILD)/bench/build.log | head; exit 1; }
	@$(BUILD)/bench/Vtb_c5x_bench $(BENCHARGS)

# Directed checks of the defects listed in cosim.md (not part of `make test` until they pass): make bugs
.PHONY: bugs
bugs:
	@mkdir -p $(BUILD)/bugs
	@$(VERILATOR) $(VFLAGS) --public-flat-rw --top-module tb_c5x_bugs -Mdir $(BUILD)/bugs $(BENCHSRCS) $(TB)/tb_c5x_bugs.sv > $(BUILD)/bugs/build.log 2>&1 || { grep -E '%Error' $(BUILD)/bugs/build.log | head; exit 1; }
	@$(BUILD)/bugs/Vtb_c5x_bugs

# lock-step trace of the DSP core (ROM + dsp_base.bin) for diffing with the C core
.PHONY: lock
lock:
	@mkdir -p $(BUILD)/lock
	@$(VERILATOR) $(VFLAGS) --public-flat-rw --top-module tb_c5x_lock -Mdir $(BUILD)/lock $(BENCHSRCS) $(TB)/tb_c5x_lock.sv > $(BUILD)/lock/build.log 2>&1 || { grep -E '%Error' $(BUILD)/lock/build.log | head; exit 1; }
	@$(BUILD)/lock/Vtb_c5x_lock $(BENCHARGS)

.PHONY: pipedxr
pipedxr:
	@mkdir -p $(BUILD)/pipedxr
	@$(VERILATOR) $(VFLAGS) --public-flat-rw --top-module tb_pipe_dxr -Mdir $(BUILD)/pipedxr $(BENCHSRCS) $(RTL)/aic.sv $(TB)/tb_pipe_dxr.sv > $(BUILD)/pipedxr/build.log 2>&1 || { grep -E '%Error' $(BUILD)/pipedxr/build.log | head; exit 1; }
	@$(BUILD)/pipedxr/Vtb_pipe_dxr $(BENCHARGS)
