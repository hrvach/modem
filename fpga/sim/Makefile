# Makefile -- TMS320C5x FPGA port: lint, unit sims, co-sim, Cyclone V synth.
#
# Targets:
#   lint           verilator --lint-only -Wall on the top level
#   sim-unit       module testbenches (agents 1/2/4 deliver them in tb/)
#   cosim          build the C-vs-RTL harness and run it on the firmware
#   smoke          run the harness on the hand-written smoke program
#   dsp-smoke      DSP smoke gate: dsp_base.bin, 8 x 1M cycles, vector
#                  checkpoints + checksums + IO events
#   selftest       C-model-only determinism check
#   reset-check    compare post-reset state C vs RTL
#   synth-cyclonev Yosys synth_intel_alm area check for Cyclone V
#                  (stat must show MISTRAL_M10K cells for PMEM/DMEM
#                  and zero $mem_v2 cells remaining)
#   synth          alias for synth-cyclonev (generic `synth` is NOT used)
#   clean          remove build products
#
# Toolchain: Verilator 5.020, Yosys 0.33 (see goal GOAL.md).
# Verilator flow is --cc/--exe with our own main() -- never --binary
# with a C++ main (multiple definition of main). The module
# testbenches (sim-unit) use --binary because they have their own
# SystemVerilog top and no C++ main.

GOAL_DIR := $(CURDIR)/..
RTL_DIR  := $(GOAL_DIR)/rtl
TB_DIR   := $(GOAL_DIR)/tb
SIM_DIR  := $(CURDIR)
C_DIR    := /home/hatch/workspace/research_notes/courier-firmware/c-port/c
C_SRC    := $(C_DIR)/src/dsp
FW_IMG   := $(C_DIR)/fw/dsp_base.bin

# Real modules (agents 1-4). All five are complete; there is no
# placeholder fallback any more (the placeholder decode/ctrl were
# deleted from sim/ and are kept as references in tb/). If a sibling
# file is truncated mid-write the build fails loudly, which is the
# correct signal -- do not paper over it with a stub.
TOP := $(RTL_DIR)/c5x_core.sv
RTL_SRCS := $(TOP) \
    $(RTL_DIR)/c5x_alu.sv \
    $(RTL_DIR)/c5x_addr.sv \
    $(RTL_DIR)/c5x_mem.sv \
    $(RTL_DIR)/c5x_ctl_pkg.sv \
    $(RTL_DIR)/c5x_decode.sv \
    $(RTL_DIR)/c5x_ctrl.sv

VERILATOR ?= verilator
YOSYS     ?= yosys
CXX       ?= g++
CXXFLAGS  ?= -O2 -Wall

BUILD_DIR := $(SIM_DIR)/obj_dir
COSIM_BIN := $(SIM_DIR)/cosim

.PHONY: all lint sim-unit cosim smoke dsp-smoke selftest reset-check \
        synth-cyclonev synth clean help

all: lint cosim

help:
	@echo "targets: lint sim-unit cosim smoke dsp-smoke selftest reset-check synth-cyclonev synth clean"

lint:
	@echo "== lint: top level =="
	$(VERILATOR) --lint-only -Wall \
	    --top-module c5x_core $(RTL_SRCS)
	@echo "lint: clean"

# Module testbenches (agents 1/2/3/4 deliver them in tb/). Each
# testbench is built with --binary (it has its own SystemVerilog
# top, no C++ main) and run; a failure prints FAIL and ends
# $fatal(1). The decode testbench proves decode + cycle counts
# only (66,726 checks); the ctrl FSM has no module testbench --
# the SV25 co-sim in sim/ is its proof (agent 5).
TB_OBJ := $(SIM_DIR)/obj_tb
sim-unit: $(TB_DIR)/tb_c5x_alu.sv $(TB_DIR)/tb_c5x_addr.sv \
          $(TB_DIR)/tb_c5x_mem.sv $(TB_DIR)/tb_c5x_decode.sv
	@echo "== sim-unit: module testbenches =="
	@mkdir -p $(TB_OBJ)/alu $(TB_OBJ)/addr $(TB_OBJ)/mem \
	    $(TB_OBJ)/decode
	$(VERILATOR) --binary -j --top-module tb_c5x_alu \
	    -Mdir $(TB_OBJ)/alu $(TB_DIR)/tb_c5x_alu.sv $(RTL_DIR)/c5x_alu.sv
	$(TB_OBJ)/alu/Vtb_c5x_alu
	$(VERILATOR) --binary --top-module tb_c5x_addr \
	    -Mdir $(TB_OBJ)/addr $(TB_DIR)/tb_c5x_addr.sv $(RTL_DIR)/c5x_addr.sv
	$(TB_OBJ)/addr/Vtb_c5x_addr
	$(VERILATOR) --binary --timing --top-module tb_c5x_mem \
	    -Mdir $(TB_OBJ)/mem $(TB_DIR)/tb_c5x_mem.sv $(RTL_DIR)/c5x_mem.sv
	$(TB_OBJ)/mem/Vtb_c5x_mem
	$(VERILATOR) --binary -j --top-module tb_c5x_decode \
	    -Mdir $(TB_OBJ)/decode $(RTL_DIR)/c5x_ctl_pkg.sv \
	    $(TB_DIR)/tb_c5x_decode.sv $(RTL_DIR)/c5x_decode.sv
	$(TB_OBJ)/decode/Vtb_c5x_decode
	@echo "sim-unit: all module testbenches passed"

# NOTE: c_ref.c (not .cpp) -- it #includes the C core, which uses
# GNU C designated initializers that g++ rejects ("non-trivial
# designated initializers not supported"). Verilator's --exe --build
# compiles every source with C++, so c_ref.c is pre-compiled with
# the C compiler (gcc) into c_ref.o and linked in as an object.
C_REF_O := $(SIM_DIR)/c_ref.o
$(C_REF_O): c_ref.c c_ref.h
	$(CC) -O2 -Wall -I$(C_SRC) -I$(SIM_DIR) -c -o $@ $<

$(COSIM_BIN): cosim.cpp $(C_REF_O) c_ref.h $(RTL_SRCS)
	@echo "== build cosim =="
	$(VERILATOR) --cc --exe --build -j 4 \
	    --top-module c5x_core \
	    -I$(C_SRC) \
	    -CFLAGS "$(CXXFLAGS) -I$(C_SRC) -I$(SIM_DIR)" \
	    -o cosim \
	    $(RTL_SRCS) cosim.cpp $(C_REF_O)
	@test -x $(BUILD_DIR)/cosim && cp $(BUILD_DIR)/cosim $(COSIM_BIN)

# Firmware co-sim: defaults to 1000 instructions; override with
# STEPS=n. First mismatch stops with both states printed.
cosim: $(COSIM_BIN)
	$(COSIM_BIN) --firmware $(STEPS) --verbose

smoke: $(COSIM_BIN)
	$(COSIM_BIN) --smoke 4

# DSP smoke gate: dsp_base.bin, 8 x 1M cycles, vector checkpoints
# + checksums + IO events. Run before the full firmware co-sim.
dsp-smoke: $(COSIM_BIN)
	$(COSIM_BIN) --dsp-smoke

selftest: $(COSIM_BIN)
	$(COSIM_BIN) --selftest $(STEPS)

reset-check: $(COSIM_BIN)
	$(COSIM_BIN) --reset-check

# Cyclone V area check. Uses synth_intel_alm, NOT generic synth.
# Pass criteria (see docs/cosim.md):
#   * $__MISTRAL_M10K cells present -- one 64Kx16 memory is 1 Mbit,
#     expect roughly 100+ blocks per memory (PMEM + DMEM).
#   * zero $mem_v2 cells remaining -- every memory mapped to M10K.
# The PMEM/DMEM arrays must carry (* ramstyle = "M10K" *) with the
# simple-dual-port synchronous template (one write port, one read
# port, registered read data, no reset on the array, no async read).
# No Quartus primitives anywhere: no altsyncram, inference only.
# Single clock domain, no gated clocks.
SYNTH_LOG := $(SIM_DIR)/synth-cyclonev.log
synth-cyclonev:
	@echo "== synth-cyclonev: synth_intel_alm -top c5x_core -family cyclonev =="
	$(YOSYS) -Q -T -l $(SYNTH_LOG) -p \
	    "read_verilog -sv $(RTL_SRCS); \
	     synth_intel_alm -top c5x_core -family cyclonev; \
	     stat"
	@echo "== stat summary (final cell table) =="
	@grep -E '^[[:space:]]+MISTRAL_[A-Z0-9_]+[[:space:]]+[0-9]+' $(SYNTH_LOG) | tail -13
	@echo "== M10K / mem_v2 check (stat table lines only) =="
	@M10K=$$(grep -E '^[[:space:]]+MISTRAL_M10K[[:space:]]+[0-9]+' $(SYNTH_LOG) | tail -1 | awk '{print $$2+0}'); \
	MEMV2=$$(grep -E '^[[:space:]]+\$$mem_v2[[:space:]]+[0-9]+' $(SYNTH_LOG) | tail -1 | awk '{print $$2+0}'); \
	echo "MISTRAL_M10K cells: $$M10K   mem_v2 cells: $$MEMV2"; \
	if [ "$$MEMV2" != "0" ]; then \
	    echo "FAIL: mem_v2 cells remain -- a memory did not map to M10K"; \
	    exit 1; \
	fi; \
	if [ "$$M10K" = "0" ]; then \
	    echo "FAIL: no MISTRAL_M10K cells -- PMEM/DMEM not mapped to M10K"; \
	    exit 1; \
	fi; \
	echo "PASS: M10K present ($$M10K cells), zero mem_v2 remaining (see $(SYNTH_LOG))"

synth: synth-cyclonev

clean:
	rm -rf $(BUILD_DIR) $(COSIM_BIN) $(SYNTH_LOG) $(TB_OBJ)
