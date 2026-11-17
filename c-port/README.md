# Backup: courier sources (C build + web build)

Restore into a checkout, then:

C build (native, needs fw/SV25.flash.bin, already here):
    make && make test
    ./bin/courier-call --config call.conf

Web build (needs the Emscripten SDK, ~/emsdk, activated with
`source ~/emsdk/emsdk_env.sh`):
    emcc -O3 -std=gnu11 -Isrc/glue -Isrc/dsp -Isrc/cpu web/modem/modem.c \
      src/dsp/c5x_core.c src/cpu/i186.c src/glue/machine.c src/glue/config.c \
      -o web/modem/web/modem.js -lm -sMODULARIZE=1 -sEXPORT_NAME=ModemModule \
      -sENVIRONMENT=worker -sFORCE_FILESYSTEM=1 -sALLOW_MEMORY_GROWTH=1 \
      -sINITIAL_MEMORY=268435456 -sSTACK_SIZE=1048576 \
      -sEXPORTED_FUNCTIONS=_modem_create,_modem_send,_modem_run,_modem_cycles,_modem_cpu_hz,_modem_rate,_modem_push_rx,_modem_pull_tx,_modem_dte,_modem_set_ring,_modem_rx_level,_modem_port,_malloc,_free \
      -sEXPORTED_RUNTIME_METHODS=HEAP32,HEAPU8,ccall \
      --preload-file call.conf --preload-file fw/SV25.flash.bin@fw/SV25.flash.bin \
      --preload-file fw/nvram.bin@fw/nvram.bin --preload-file fw/dsp_base.bin@fw/dsp_base.bin

Serve web/modem/web over http (python3 -m http.server) and open the page.

Not included: build outputs, out/, the uncommitted WAT experiment, and the
faster idle/diagnostics-free DSP variant (scratch only, not yet in the repo).
