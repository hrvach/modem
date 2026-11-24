# SIP gateway for the wasm modem page (SIP tab)

`cargo build --release`, then on the machine that serves the page:

    GW_BINMODEM_PORT=5160 target/release/gateway --host <address the page is served from> --jitter-ms 80

The page connects to `ws://<host>:8777`. Destinations: BinModem (`127.0.0.1:$GW_BINMODEM_PORT`) and D-Modem. Origins other than localhost and `--host` are refused.
Page: SIP tab, Power on, choose the destination (it resets to D-Modem on reload), dial from the terminal (`ATDT100`); digits are decoded from the modem's DTMF, hang up with `ATH`. Tx 1, Rx 2.
BinModem answerer: courier_fpga `tools/cline/sipanswer.py --port 5160 --rtp-listen 5162 --calls 300 --outscale 5000 --log /tmp/sipans5160`.
Result 2026-11-24: CONNECT 33600/ARQ/V34/LAPM/V42BIS with BinModem. The 80 ms cushions matter: V.42 detection needs a round trip well under its 750 ms timer.
Recordings of each call (8 kHz both ways, modem samples, codec rates): `~/.cache/courier-sip/rec`; log: `~/.cache/courier-sip/gateway.log`.
