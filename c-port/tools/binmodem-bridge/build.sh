#!/bin/sh
# Build the BinModem bridge without touching the BinModem checkout.
#   tools/binmodem-bridge/build.sh [BINMODEM_DIR]   (default ~/Programming/BinModem)
# Prints the path of the bridge binary. Work dir: ${WORK:-/tmp/binmodem-bridge-build}.
set -e
HERE=$(cd "$(dirname "$0")" && pwd)
BM=${1:-$HOME/Programming/BinModem}
WORK=${WORK:-/tmp/binmodem-bridge-build}
rm -rf "$WORK/bm" "$WORK/bridge"; mkdir -p "$WORK/bm" "$WORK/bridge" "$WORK/alsa/lib" "$WORK/alsa/pc"
(cd "$BM" && tar --exclude=.git --exclude=target --exclude=captures -cf - .) | tar -xf - -C "$WORK/bm"
# rustc < 1.96 lacks uN::isolate_lowest_one; x & x.wrapping_neg() is the same value.
sed -i 's/let ja = allowed.isolate_lowest_one();/let ja = allowed \& allowed.wrapping_neg();/' \
    "$WORK/bm/crates/datapump/src/v92/digital.rs"
# Phase 3/4 tracing (PHASE4_TRACE=1): stage changes, failure reasons, J and MP events.
(cd "$WORK/bm" && git apply -p1 "$HERE/trace.patch")
# cpal wants alsa.pc even though the bridge never opens a sound device; point it at the
# runtime library when the -devel package is not installed.
if ! pkg-config --exists alsa 2>/dev/null; then
    ln -sf /usr/lib64/libasound.so.2 "$WORK/alsa/lib/libasound.so"
    printf 'prefix=%s/alsa\nlibdir=${prefix}/lib\nName: alsa\nDescription: shim\nVersion: 1.2.0\nLibs: -L${libdir} -lasound\n' \
        "$WORK" > "$WORK/alsa/pc/alsa.pc"
    export PKG_CONFIG_PATH="$WORK/alsa/pc"
fi
cp -r "$HERE/src" "$WORK/bridge/src"
sed "s|../../../BinModem/crates/modem|$WORK/bm/crates/modem|" "$HERE/Cargo.toml" > "$WORK/bridge/Cargo.toml"
cargo build --release --manifest-path "$WORK/bridge/Cargo.toml" --target-dir "$WORK/target" >&2
echo "$WORK/target/release/bridge"
