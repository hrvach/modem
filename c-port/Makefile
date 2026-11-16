# Courier modem emulator — C glue (machine + link + line + profiles +
# wrappers + driver + config + WAV + main). See README.md.
#
#   make        build bin/courier-call (cores + glue)
#   make fw     decode SV25.XMD -> fw/SV25.flash.bin (see below)
#   make run    run the fake call with call.conf (decodes fw only if
#               fw/SV25.flash.bin is missing; the XMD is not touched otherwise)
#   make test   unit/smoke tests
#   make clean  remove build outputs (keeps fw/ and out/)
#
# FIRMWARE SOURCE: SV25.XMD is the firmware source of truth, not a
# pre-decoded flash bin. Canonical XMD:
#   ~/workspace/research_notes/courier-firmware/SV25.XMD
#   (524,416 bytes, SHA-256 43503d82caae5377d67c61f4f44d73e6a19e15c61b2cb706a70c6f1b88ef413f)
# Decode (rolling XOR, flash addr = file offset + 0x80) with the existing
# decode path handover-2-2026-11-15/handover/tools/sv25_decode.py; it
# produces fw/SV25.flash.bin (524,288 bytes, SHA-256
# f24633ab12c21c3cef93c0f6c0bb8150021b0056953cb5517a95932abc673c52).
# Override the XMD location with `make fw XMD=/path/to/SV25.XMD`.
# Never patch the firmware; never upload/publish the XMD, the decoded
# flash, or audio anywhere. Local files only.
CC      ?= gcc
CFLAGS  ?= -O2 -Wall -Wextra -std=gnu11
CPPFLAGS ?= -Isrc/glue -Isrc/dsp -Isrc/cpu
LDFLAGS ?=
LDLIBS  ?= -lm

XMD ?= $(HOME)/workspace/research_notes/courier-firmware/SV25.XMD
DECODE ?= $(HOME)/workspace/research_notes/courier-firmware/handover-2-2026-11-15/handover/tools/sv25_decode.py
FW = fw/SV25.flash.bin

GLUE_SRC = src/glue/machine.c src/glue/link.c src/glue/line.c \
           src/glue/resamp.c src/glue/config.c src/glue/wav.c src/glue/main.c
GLUE_OBJ = $(GLUE_SRC:.c=.o)

.PHONY: all fw run test clean

all: lib/libc5x.a lib/libi186.a bin/courier-call

# Core libraries. The cores (src/dsp/c5x_core.c, src/cpu/i186.c) are
# readable rewrites of the originals, behaviour-identical; the glue
# calls them only through src/dsp/c5x_core.h and src/cpu/i186.h.
lib/libc5x.a: src/dsp/c5x_core.o
	@mkdir -p lib
	$(AR) rcs $@ $<
lib/libi186.a: src/cpu/i186.o
	@mkdir -p lib
	$(AR) rcs $@ $<

src/dsp/c5x_core.o: src/dsp/c5x_core.c src/dsp/c5x_cyctab.h src/dsp/c5x_core.h
	$(CC) $(CFLAGS) $(CPPFLAGS) -c -o $@ $<
src/cpu/i186.o: src/cpu/i186.c src/cpu/i186.h
	$(CC) $(CFLAGS) $(CPPFLAGS) -c -o $@ $<

bin/courier-call: $(GLUE_OBJ) lib/libc5x.a lib/libi186.a
	@mkdir -p bin
	$(CC) $(CFLAGS) $(CPPFLAGS) -o $@ $(GLUE_OBJ) lib/libc5x.a lib/libi186.a $(LDLIBS)

src/glue/%.o: src/glue/%.c
	$(CC) $(CFLAGS) $(CPPFLAGS) -MMD -MP -c -o $@ $<

-include $(GLUE_OBJ:.o=.d)

fw: $(FW)

$(FW): $(XMD) $(DECODE)
	@mkdir -p fw
	python3 $(DECODE) $(XMD) $(FW)
	sha256sum $(FW)

run: all $(if $(wildcard $(FW)),,fw)
	./bin/courier-call --config call.conf

test: all
	@mkdir -p tests
	$(CC) $(CFLAGS) $(CPPFLAGS) -o tests/test_resamp tests/test_resamp.c src/glue/resamp.c $(LDLIBS)
	$(CC) $(CFLAGS) $(CPPFLAGS) -o tests/test_config tests/test_config.c src/glue/config.c
	$(CC) $(CFLAGS) $(CPPFLAGS) -o tests/test_line tests/test_line.c src/glue/line.c $(LDLIBS)
	./tests/test_resamp
	./tests/test_config
	./tests/test_line
	./bin/courier-call --help

clean:
	rm -f $(GLUE_OBJ) $(GLUE_OBJ:.o=.d) src/dsp/c5x_core.o src/cpu/i186.o
	rm -f lib/libc5x.a lib/libi186.a bin/courier-call
	rm -f tests/test_resamp tests/test_config tests/test_line
