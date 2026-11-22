#!/bin/bash
# qbuild.sh [fast|full]: copy the project (Modem.*, files.qip, sys/, rtl/) to a new run directory on the Quartus build host and compile it there (detached).
#   BUILD_HOST=<ssh host>   default agent@builder.hrvoje.org
#   QUARTUS_BIN=<dir>       default /opt/fpga/17.1/quartus/bin
#   STAGE=map               only Analysis & Synthesis (quartus_map): M10K / DSP / ALM numbers and elaboration errors in a few minutes
#   NO_VIDEO=1              (default 1 for the first builds): no terminal / picture and no scaler: also defines the framework switches
#                           MISTER_DEBUG_NOHDMI (drops ascal and the HDMI path), MISTER_DISABLE_ALSA and MISTER_DISABLE_YC
#   dev:  fastest bring-up build: `fast` plus half placement / router effort and the optional timing / routing extras off (not for a bitstream to keep);
#   fast: balanced optimisation, no physical synthesis (iteration); full: the settings of Modem.qsf unchanged.
# NO firmware leaves this machine: the SV25 flash image, NVRAM and DSP ROM are loaded through the OSD at run time (../courier README: local files only).
# Prints the run id; written to ./.qbuild_runid. Only the newest 3 run directories are kept on the host.
set -e
P=${1:-fast}
BUILD_HOST=${BUILD_HOST:-agent@builder.hrvoje.org}
QB=${QUARTUS_BIN:-/opt/fpga/17.1/quartus/bin}
NV=${NO_VIDEO:-1}
cd "$(dirname "$0")/.."
CMD='quartus_sh --flow compile Modem'; [ "${STAGE:-}" = map ] && CMD='quartus_map --read_settings_files=on --write_settings_files=off Modem'
ID=run-$(date +%Y%m%d-%H%M%S)-$P; echo "$ID" > .qbuild_runid
FAST='true'
[ "$P" = fast ] && FAST='sed -i -e "s/^\(set_global_assignment -name OPTIMIZATION_MODE\).*/\1 BALANCED/" -e "s/^\(set_global_assignment -name OPTIMIZATION_TECHNIQUE\).*/\1 BALANCED/" -e "s/^\(set_global_assignment -name PHYSICAL_SYNTHESIS_[A-Z_]*\) ON/\1 OFF/" -e "s/^\(set_global_assignment -name FINAL_PLACEMENT_OPTIMIZATION\).*/\1 NEVER/" Modem.qsf'
[ "$P" = dev ] && FAST='sed -i -e "s/^\(set_global_assignment -name OPTIMIZATION_MODE\).*/\1 BALANCED/" -e "s/^\(set_global_assignment -name OPTIMIZATION_TECHNIQUE\).*/\1 BALANCED/" -e "s/^\(set_global_assignment -name PHYSICAL_SYNTHESIS_[A-Z_]*\) ON/\1 OFF/" -e "s/^\(set_global_assignment -name FINAL_PLACEMENT_OPTIMIZATION\).*/\1 NEVER/" Modem.qsf; sed -i -e "/^set_global_assignment -name \(ROUTER_LCELL_INSERTION_AND_LOGIC_DUPLICATION\|ECO_OPTIMIZE_TIMING\|ROUTER_CLOCKING_TOPOLOGY_ANALYSIS\|PERIPHERY_TO_CORE_PLACEMENT_AND_ROUTING_OPTIMIZATION\) /d" Modem.qsf; printf "\\nset_global_assignment -name PLACEMENT_EFFORT_MULTIPLIER 0.5\\nset_global_assignment -name ROUTER_EFFORT_MULTIPLIER 0.5\\nset_global_assignment -name FITTER_AGGRESSIVE_ROUTABILITY_OPTIMIZATION NEVER\\n" >> Modem.qsf'
[ "$NV" = 1 ] && FAST="$FAST; printf '\\nset_global_assignment -name VERILOG_MACRO \"NO_VIDEO=1\"\\nset_global_assignment -name VERILOG_MACRO \"MISTER_DEBUG_NOHDMI=1\"\\nset_global_assignment -name VERILOG_MACRO \"MISTER_DISABLE_ALSA=1\"\\nset_global_assignment -name VERILOG_MACRO \"MISTER_DISABLE_YC=1\"\\n' >> Modem.qsf"
ssh -o BatchMode=yes "$BUILD_HOST" 'bash -s' <<'REMOTE'
cd ~/modem-runs 2>/dev/null || { mkdir -p ~/modem-runs; cd ~/modem-runs; }
n=0
for d in $(ls -1dt run-[0-9]*-* 2>/dev/null); do
    n=$((n+1)); [ $n -le 2 ] && continue
    if [ -f "$d/build.pid" ] && kill -0 "$(cat "$d/build.pid")" 2>/dev/null; then echo "keep (running): $d"; continue; fi
    echo "pruning old run: $d"; rm -rf -- "$HOME/modem-runs/$d"
done
avail=$(df -BG --output=avail ~ | tail -1 | tr -dc 0-9)
[ "$avail" -ge 10 ] || { echo "only ${avail}G free, not starting"; exit 1; }
echo "free: ${avail}G"
REMOTE
tar --exclude=db --exclude=output_files --exclude='*.srf' -cf - Modem.qpf Modem.qsf Modem.sdc Modem.sv files.qip sys rtl | \
ssh -o BatchMode=yes "$BUILD_HOST" "set -e; mkdir -p ~/modem-runs/$ID && cd ~/modem-runs/$ID && tar xf - && printf '\`define BUILD_DATE \"%s\"\\n' \$(date +%y%m%d) > build_id.v && $FAST && echo profile=$P no_video=$NV && (nohup $QB/$CMD > build.log 2>&1 < /dev/null & echo \$! > build.pid); sleep 3; echo started $ID pid=\$(cat build.pid)"
