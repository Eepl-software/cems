# Cross-compile JSNOW for 64-bit ARM (NEON path), e.g. to test under qemu:
#   cmake -S . -B build-arm -DCMAKE_TOOLCHAIN_FILE=cmake/aarch64-linux-gnu.cmake
#   cmake --build build-arm -j
#   qemu-aarch64 -L /usr/aarch64-linux-gnu build-arm/jsnow --frames 3
set(CMAKE_SYSTEM_NAME Linux)
set(CMAKE_SYSTEM_PROCESSOR aarch64)
set(CMAKE_C_COMPILER aarch64-linux-gnu-gcc)
set(CMAKE_CXX_COMPILER aarch64-linux-gnu-g++)
set(CMAKE_FIND_ROOT_PATH /usr/aarch64-linux-gnu)
set(CMAKE_FIND_ROOT_PATH_MODE_PROGRAM NEVER)
set(CMAKE_FIND_ROOT_PATH_MODE_LIBRARY ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_INCLUDE ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_PACKAGE ONLY)
