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
EXPORTS="_modem_create,_modem_send,_modem_run,_modem_cycles,_modem_cpu_hz,_modem_rate,_modem_push_rx,_modem_pull_tx,_modem_dte,_modem_set_ring,_modem_rx_level,_modem_port,_modem_scope_set,_modem_scope_pull,_modem_dm,_modem_send_bytes,_malloc,_free"
FLAGS="-O2 -std=gnu11 -Wall -Wextra $INC -sMODULARIZE=1 -sEXPORT_NAME=ModemModule -sALLOW_MEMORY_GROWTH=1 -sSTACK_SIZE=4194304 -sEXPORTED_FUNCTIONS=$EXPORTS -sEXPORTED_RUNTIME_METHODS=ccall,HEAP32,HEAPU8,FS -sFORCE_FILESYSTEM=1"
# The browser build carries no firmware: the page decodes the user's own SV25.XMD and writes /fw/SV25.flash.bin before modem_create.
PRELOAD_WEB="--preload-file call.conf@/call.conf --preload-file fw/nvram.bin@/fw/nvram.bin"
PRELOAD="$PRELOAD_WEB --preload-file fw/SV25.flash.bin@/fw/SV25.flash.bin --preload-file fw/dsp_base.bin@/fw/dsp_base.bin"

# LOCAL USE ONLY: EMBED_FW=fw/SV20.flash.bin bakes that decoded flash image into the browser build (modem.data), so the page needs no firmware file. The result contains
# the firmware: never publish or upload web/modem/web/modem.data (it is git-ignored). The profile (CPU clock) comes from the file name prefix (SV20 -> sv20, SV25 -> sv25),
# and web/modem/web/embedded.txt (also git-ignored) tells the page to use the built-in image.
rm -f web/modem/web/embedded.txt
if [ -n "${EMBED_FW:-}" ]; then
    case "$(basename "$EMBED_FW")" in
        SV20*) EMBED_PROFILE=sv20 ;;
        SV25*) EMBED_PROFILE=sv25 ;;
        *) echo "EMBED_FW: cannot tell the firmware from the file name (SV20* or SV25*)" >&2; exit 1 ;;
    esac
    PRELOAD_WEB="$PRELOAD_WEB --preload-file $EMBED_FW@/fw/SV25.flash.bin"
    echo "$EMBED_PROFILE" > web/modem/web/embedded.txt
    PRELOAD="$PRELOAD_WEB --preload-file fw/dsp_base.bin@/fw/dsp_base.bin"   # the Node build carries the same image, not the SV25 one
    echo "NOTE: $EMBED_FW is embedded in web/modem/web/modem.data. Local use only; do not publish it." >&2
fi

mkdir -p web/modem/build
emcc $SRC $FLAGS -sENVIRONMENT=web,worker $PRELOAD_WEB -o web/modem/web/modem.js
emcc $SRC $FLAGS -sENVIRONMENT=node $PRELOAD -o web/modem/build/modem.js
echo "built web/modem/web/modem.{js,wasm,data} and web/modem/build/modem.js"
