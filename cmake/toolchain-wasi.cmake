# Minimal WASI cross toolchain file.
# Used from the repo root: cmake -B build-wasm -G "Unix Makefiles" \
#   -DCMAKE_TOOLCHAIN_FILE=cmake/toolchain-wasi.cmake \
#   -DWASI_SDK_ROOT=/path/to/wasi-sdk-XX.X-<arch>-<os>

cmake_minimum_required(VERSION 3.18)

set(CMAKE_SYSTEM_NAME WASI)
set(CMAKE_SYSTEM_PROCESSOR wasm32)
set(CMAKE_SYSTEM_VERSION 1)
set(CMAKE_TRY_COMPILE_PLATFORM_VARIABLES WASI_SDK_ROOT)

if(NOT WASI_SDK_ROOT)
  if(DEFINED ENV{WASI_SDK_ROOT})
    set(WASI_SDK_ROOT "$ENV{WASI_SDK_ROOT}")
  endif()
endif()

if(NOT WASI_SDK_ROOT)
  message(FATAL_ERROR "WASI_SDK_ROOT is not set. Pass -DWASI_SDK_ROOT=<path>.")
endif()
set(WASI_SDK_ROOT "${WASI_SDK_ROOT}" CACHE PATH "Path to wasi-sdk root")

set(CMAKE_SYSROOT "${WASI_SDK_ROOT}/share/wasi-sysroot")

set(CMAKE_C_COMPILER "${WASI_SDK_ROOT}/bin/clang")
set(CMAKE_CXX_COMPILER "${WASI_SDK_ROOT}/bin/clang++")
set(CMAKE_AR "${WASI_SDK_ROOT}/bin/ar")
set(CMAKE_RANLIB "${WASI_SDK_ROOT}/bin/ranlib")
set(CMAKE_C_COMPILER_TARGET wasm32-wasi)
set(CMAKE_CXX_COMPILER_TARGET wasm32-wasi)

set(CMAKE_FIND_ROOT_PATH "${CMAKE_SYSROOT}")
set(CMAKE_FIND_ROOT_PATH_MODE_PROGRAM NEVER)
set(CMAKE_FIND_ROOT_PATH_MODE_LIBRARY ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_INCLUDE ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_PACKAGE ONLY)

# Avoid running built test executables at configure time.
set(CMAKE_TRY_COMPILE_TARGET_TYPE STATIC_LIBRARY)

# Allow unresolved symbols that will be supplied by the host JS runtime.
set(CMAKE_EXE_LINKER_FLAGS_INIT "--sysroot=${CMAKE_SYSROOT} -Wl,--allow-undefined")
