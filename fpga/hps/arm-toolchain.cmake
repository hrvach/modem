# cmake toolchain file: armv7 hard-float Linux (the MiSTer's HPS), cross compiler from Debian's gcc-arm-linux-gnueabihf
set(CMAKE_SYSTEM_NAME Linux)
set(CMAKE_SYSTEM_PROCESSOR arm)
set(CMAKE_C_COMPILER arm-linux-gnueabihf-gcc)
set(CMAKE_C_FLAGS_INIT "-march=armv7-a -mfpu=neon -mfloat-abi=hard -O2")
set(CMAKE_EXE_LINKER_FLAGS_INIT "-static")
set(CMAKE_LIBRARY_ARCHITECTURE arm-linux-gnueabihf)
set(CMAKE_FIND_ROOT_PATH /usr/arm-linux-gnueabihf /usr)
set(CMAKE_FIND_ROOT_PATH_MODE_PROGRAM NEVER)
set(CMAKE_FIND_ROOT_PATH_MODE_LIBRARY BOTH)
set(CMAKE_FIND_ROOT_PATH_MODE_INCLUDE BOTH)
set(CMAKE_C_STANDARD_LIBRARIES_INIT "-lz -lzstd -ldl -lpthread")   # the Debian static libcrypto.a was built with zlib / zstd support
