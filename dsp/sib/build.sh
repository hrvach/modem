#!/bin/sh
# Build libc5x_sib.so (courier-emu C5x core + shim). Single job, low priority.
cd "$(dirname "$0")" && nice -n 19 clang++ -std=c++17 -O2 -fPIC -shared -Wno-unused-result c5x_core.cpp c5x_sib_shim.cpp -o ../libc5x_sib.so
