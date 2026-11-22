#!/bin/bash
# build-arm.sh: cross-build a static armv7 baresip with the modemline module on the build host (needs cmake, gcc-arm-linux-gnueabihf, libssl-dev:armhf).
# usage: hps/build-arm.sh [HOST]   (default agent@builder.hrvoje.org); sources of libre / baresip (v4.1.0) are taken from $SRC (default: ./hpsbuild next to this script's scratch dir)
set -e
H=${1:-agent@builder.hrvoje.org}
HERE=$(cd "$(dirname "$0")" && pwd)
SRC=${SRC:-$HERE/../../hpsbuild}
[ -d "$SRC/re" ] && [ -d "$SRC/baresip" ] || { echo "need $SRC/re and $SRC/baresip (git clone --branch v4.1.0 https://github.com/baresip/re and /baresip)"; exit 1; }
ssh "$H" 'mkdir -p ~/hps/src'
rsync -a --delete --exclude build --exclude .git "$SRC/re" "$SRC/baresip" "$H:hps/src/"
rsync -a --delete "$HERE/" "$H:hps/modemline-src/"
ssh "$H" 'bash -s' <<'EOS'
set -e
cd ~/hps; mkdir -p build out
TC=$PWD/modemline-src/arm-toolchain.cmake
cmake -S src/re -B build/re -DCMAKE_TOOLCHAIN_FILE=$TC -DCMAKE_BUILD_TYPE=Release -DUSE_OPENSSL=ON -DCMAKE_DISABLE_FIND_PACKAGE_ZLIB=ON -DOPENSSL_INCLUDE_DIR=/usr/include -DOPENSSL_SSL_LIBRARY=/usr/lib/arm-linux-gnueabihf/libssl.a -DOPENSSL_CRYPTO_LIBRARY=/usr/lib/arm-linux-gnueabihf/libcrypto.a -DLIBRE_BUILD_SHARED=OFF -DCMAKE_INSTALL_PREFIX=$PWD/out > build/re.log 2>&1 || { tail -20 build/re.log; exit 1; }
cmake --build build/re -j8 > build/re.make.log 2>&1 || { grep -E "error|Error" build/re.make.log | head; exit 1; }
cmake --install build/re > /dev/null
cmake -S src/baresip -B build/baresip -DCMAKE_TOOLCHAIN_FILE=$TC -DCMAKE_BUILD_TYPE=Release -DSTATIC=ON -DCMAKE_DISABLE_FIND_PACKAGE_ZLIB=ON -DOPENSSL_INCLUDE_DIR=/usr/include -DOPENSSL_SSL_LIBRARY=/usr/lib/arm-linux-gnueabihf/libssl.a -DOPENSSL_CRYPTO_LIBRARY=/usr/lib/arm-linux-gnueabihf/libcrypto.a -DCMAKE_PREFIX_PATH=$PWD/out \
  -DMODULES="g711;ctrl_tcp;menu;account;srtp;auresamp" -DAPP_MODULES=modemline -DAPP_MODULES_DIR=$PWD/modemline-src > build/baresip.log 2>&1 || { tail -20 build/baresip.log; exit 1; }
cmake --build build/baresip --target baresip_exe -j8 > build/baresip.make.log 2>&1 || { grep -E "error|Error|undefined" build/baresip.make.log | head -20; exit 1; }
file build/baresip/baresip 2>/dev/null | cut -c1-120 || true
ls -la build/baresip/baresip
EOS
