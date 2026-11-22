#!/bin/bash
# qwait.sh: wait for the run in ./.qbuild_runid to finish on the build host, then print the errors (or the tail of the log)
cd "$(dirname "$0")/.."
H=${BUILD_HOST:-agent@builder.hrvoje.org}; ID=$(cat .qbuild_runid)
while ssh -o BatchMode=yes "$H" "kill -0 \$(cat ~/modem-runs/$ID/build.pid) 2>/dev/null"; do sleep 5; done
ssh -o BatchMode=yes "$H" "cd ~/modem-runs/$ID; grep -E '^Error' build.log | grep -v 'Peak virtual\|Processing ended\|Elapsed time\|Total CPU' | head -${N:-12}; tail -3 build.log"
