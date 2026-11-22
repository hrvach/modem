#!/bin/bash
# build.sh: Verilate rtl/dsp (c5x_core) and build the ctypes shim library build/dsp_regress/librtl.so used by dsp_regress.py
set -e
HERE=$(cd "$(dirname "$0")" && pwd); ROOT=$(cd "$HERE/../.." && pwd); F=$ROOT/rtl/dsp; O=$ROOT/build/dsp_regress
mkdir -p "$O"; cd "$O"
verilator --cc --build -j 4 --public-flat-rw -CFLAGS -fPIC -Wno-fatal -Wno-lint -Wno-style -O2 --top-module c5x_core -Mdir vobj \
  $F/c5x_ctl_pkg.sv $F/c5x_alu.sv $F/c5x_addr.sv $F/c5x_mem.sv $F/c5x_decode.sv $F/c5x_ctrl.sv $F/c5x_core.sv > vbuild.log 2>&1 || { tail -8 vbuild.log; exit 1; }
VI=$(verilator --getenv VERILATOR_ROOT)/include; [ -d "$VI" ] || VI=/usr/share/verilator/include
g++ -O2 -w -fPIC -I vobj -I $VI -I $VI/vltstd -c $HERE/rtlshim.cpp -o rtlshim.o
g++ -O2 -w -fPIC -I vobj -I $VI -I $VI/vltstd -c $VI/verilated.cpp -o verilated.o
g++ -O2 -w -fPIC -I vobj -I $VI -I $VI/vltstd -c $VI/verilated_threads.cpp -o verilated_threads.o
g++ -shared -o librtl.so rtlshim.o verilated.o verilated_threads.o vobj/Vc5x_core__ALL.a -lpthread
echo "built $O/librtl.so"
