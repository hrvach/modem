#!/bin/sh
# wrap.sh -- slmodemd -e target that logs how d-modem is started and what it prints, then runs it (debugging aid)
D=$(dirname "$0")
echo "$(date +%T) start args=[$1] fd=[$2] uid=$(id -u)" >> "$D/wrap.log"
"$D/D-Modem/d-modem" "$@" >> "$D/wrap.log" 2>&1
echo "$(date +%T) d-modem exited rc=$?" >> "$D/wrap.log"
