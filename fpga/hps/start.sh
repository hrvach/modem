#!/bin/sh
# start.sh [twilio|peer] -- on the MiSTer: baresip (with the modemline module, SIP trace on) and the line controller.
#   twilio (default): the SIP trunk, config in /media/fat/modem/baresip-cfg (config, accounts: yours, never overwritten by scripts)
#   peer:             the test peer on the builder (D-Modem), config in /media/fat/modem/baresip-peer, plain UDP / RTP, numbers are dialled as sip:<digits>@79.137.67.20
#   RXGAIN=2.0 start.sh peer   scales the audio the modem hears (default 1.0, test aid)
# Stop with: killall baresip python3
cd /media/fat/modem
MODE=${1:-twilio}
case "$MODE" in
    twilio) CFG=/media/fat/modem/baresip-cfg;  DOMAIN=${DOMAIN:-hrvoje.pstn.twilio.com}; PREFIX=${PREFIX:-+} ;;
    peer)   CFG=/media/fat/modem/baresip-peer; DOMAIN=${DOMAIN:-79.137.67.20};          PREFIX=${PREFIX:-} ;;
    *) echo "usage: start.sh [twilio|peer]"; exit 1 ;;
esac
[ -f "$CFG/accounts" ] || { echo "no $CFG/accounts"; exit 1; }
killall baresip python3 2>/dev/null; sleep 1
MODEMLINE_RXGAIN=${RXGAIN:-1.0} nohup ./baresip -s -f "$CFG" > /tmp/baresip.log 2>&1 &
sleep 3
nohup python3 -u lined.py --domain "$DOMAIN" --prefix "$PREFIX" --dwell "${DWELL:-2.5}" > /tmp/lined.log 2>&1 &
echo "started: $MODE ($CFG, $DOMAIN)"
