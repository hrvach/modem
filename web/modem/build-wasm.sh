#!/usr/bin/env bash
# Builds the wasm modem: web/modem/web/ (browser page, worker) and
# web/modem/build/ (Node). Needs emsdk; EMSDK defaults to ~/emsdk.
# Run from anywhere:  web/modem/build-wasm.sh
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
source "${EMSDK:-$HOME/emsdk}/emsdk_env.sh" >/dev/null
cd "$ROOT"

SRC="web/modem/modem.c src/glue/machine.c src/glue/config.c src/dsp/c5x_core.c src/cpu/i186.c"
INC="-Isrc/glue -Isrc/dsp -Isrc/cpu"
EXPORTS="_modem_create,_modem_send,_modem_run,_modem_cycles,_modem_cpu_hz,_modem_rate,_modem_push_rx,_modem_pull_tx,_modem_dte,_modem_set_ring,_modem_rx_level,_modem_port,_modem_scope_set,_modem_scope_pull,_malloc,_free"
FLAGS="-O2 -std=gnu11 -Wall -Wextra $INC -sMODULARIZE=1 -sEXPORT_NAME=ModemModule -sALLOW_MEMORY_GROWTH=1 -sSTACK_SIZE=4194304 -sEXPORTED_FUNCTIONS=$EXPORTS -sEXPORTED_RUNTIME_METHODS=ccall,HEAP32,HEAPU8"
PRELOAD="--preload-file call.conf@/call.conf --preload-file fw/SV25.flash.bin@/fw/SV25.flash.bin --preload-file fw/dsp_base.bin@/fw/dsp_base.bin --preload-file fw/nvram.bin@/fw/nvram.bin"

mkdir -p web/modem/build
emcc $SRC $FLAGS -sENVIRONMENT=web,worker $PRELOAD -o web/modem/web/modem.js
emcc $SRC $FLAGS -sENVIRONMENT=node $PRELOAD -o web/modem/build/modem.js
echo "built web/modem/web/modem.{js,wasm,data} and web/modem/build/modem.js"
