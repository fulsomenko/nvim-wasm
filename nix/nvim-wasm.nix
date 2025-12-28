{ lib
, stdenvNoCC
, fetchurl
, fetchFromGitHub
, lua5_1
, gnumake
, git
, gnutar
, gzip
, cmake
, binaryen
, curl
, cacert
, llvmPackages
, gettext
, libiconv
}:

let
  # Platform detection for WASI SDK download
  wasiSdkVersion = "29.0";
  wasiSdkArch = if stdenvNoCC.hostPlatform.isx86_64 then "x86_64" else "arm64";
  wasiSdkOs = if stdenvNoCC.isDarwin then "macos" else "linux";

  # FOD output hashes per platform
  # Built with WASM_EH_FLAGS="-mno-exception-handling" for wasmi compatibility
  # Asyncify handles setjmp/longjmp via stack rewinding
  outputHashes = {
    "arm64-macos" = "sha256-3xZLnDN1dR72SGSuXBdWRNUOCrNrf0e7yrCbrbCI6m0=";  # TUI patches
    "x86_64-macos" = lib.fakeSha256;  # TODO: compute on x86_64-macos
    "arm64-linux" = lib.fakeSha256;   # TODO: compute on arm64-linux
    "x86_64-linux" = lib.fakeSha256;  # TODO: compute on x86_64-linux
  };

  # WASI SDK hashes per platform
  wasiSdkHashes = {
    "arm64-macos" = "sha256-4RVSkT4/meg01/59ob0IGrr3ZHWe12tgl6NMY/yDZl4=";
    "x86_64-macos" = "sha256-0N4v0+pcVwYO+ofkNWwWS+w2iZcvI4bwyaicWOEM7I0=";
    "arm64-linux" = "sha256-BSrXczl9yeWqmftM/vaUF15rHoG7KtHTyOez/IFEG3w=";
    "x86_64-linux" = "sha256-h9HRooedE5zcYkuWjvrT1Kl7gHjN/5XmOsiOyv0aAXE=";
  };

  # Toolchain sources (platform-specific)
  wasiSdk = fetchurl {
    url = "https://github.com/WebAssembly/wasi-sdk/releases/download/wasi-sdk-29/wasi-sdk-29.0-${wasiSdkArch}-${wasiSdkOs}.tar.gz";
    sha256 = wasiSdkHashes."${wasiSdkArch}-${wasiSdkOs}";
  };

  # Source dependencies for WASM build (platform-independent)
  luaSrc = fetchurl {
    url = "https://www.lua.org/ftp/lua-5.1.5.tar.gz";
    sha256 = "sha256-JkD8VqeV8p0o7xXhPDSkfiI5YLAkDoywqC2bBzhpUzM=";
  };

  libuvSrc = fetchurl {
    url = "https://github.com/libuv/libuv/archive/v1.51.0.tar.gz";
    sha256 = "sha256-J+Vc9wg5E7+2gmynjN6d52R83tZI018kFj8tMbufUc0=";
  };

  luvSrc = fetchurl {
    url = "https://github.com/luvit/luv/archive/1.51.0-1.tar.gz";
    sha256 = "sha256-1KEReK6OFrpYhnmeqRkF3ZsLR5x1rr1nhm03Nz5BUm8=";
  };

  luaCompat53Src = fetchurl {
    url = "https://github.com/lunarmodules/lua-compat-5.3/archive/v0.13.tar.gz";
    sha256 = "sha256-9dww57H9qFbuTTkr5FdkLB8MJZJkqbm/vLaAMCzoj8I=";
  };

  # Neovim source (same commit as submodule)
  neovimSrc = fetchFromGitHub {
    owner = "neovim";
    repo = "neovim";
    rev = "c40cb2a4cf324812d46479480f6065e2c28bcb80";
    sha256 = "sha256-3OO2iftEgrIxJXVpuJb1z/qvLTyWAYGoaq53aVUKuB4=";
    fetchSubmodules = false;
  };

  # Single Fixed-Output Derivation that builds everything
  # This allows network access for tree-sitter grammar downloads
  # and avoids cmake cross-compilation platform detection issues
  nvimWasmFull = stdenvNoCC.mkDerivation {
    pname = "nvim-wasm-full";
    version = "0.10.0";

    src = ./..;

    nativeBuildInputs = [ lua5_1 gnumake cmake curl cacert gnutar gzip git binaryen llvmPackages.clang gettext libiconv ];

    # Set CC for host builds
    CC = "${llvmPackages.clang}/bin/clang";

    # Fixed-output derivation settings
    outputHashAlgo = "sha256";
    outputHashMode = "recursive";
    outputHash = outputHashes."${wasiSdkArch}-${wasiSdkOs}";

    dontConfigure = true;
    dontFixup = true;

    # SSL certificate configuration for cmake downloads
    SSL_CERT_FILE = "${cacert}/etc/ssl/certs/ca-bundle.crt";
    GIT_SSL_CAINFO = "${cacert}/etc/ssl/certs/ca-bundle.crt";
    CURL_CA_BUNDLE = "${cacert}/etc/ssl/certs/ca-bundle.crt";
    NIX_SSL_CERT_FILE = "${cacert}/etc/ssl/certs/ca-bundle.crt";

    postPatch = ''
      # Create toolchains directory
      mkdir -p .toolchains

      # Extract WASI SDK
      tar -C .toolchains -xzf ${wasiSdk}
      touch .toolchains/wasi-sdk-${wasiSdkVersion}-${wasiSdkArch}-${wasiSdkOs}.tar.gz

      # Create cmake directory structure
      mkdir -p .toolchains/cmake-3.29.6-${wasiSdkOs}-${wasiSdkArch}/bin
      ln -sf ${cmake}/bin/cmake .toolchains/cmake-3.29.6-${wasiSdkOs}-${wasiSdkArch}/bin/cmake
      touch .toolchains/cmake-3.29.6-${wasiSdkOs}-${wasiSdkArch}.tar.gz

      # Copy source tarballs
      cp ${luaSrc} .toolchains/lua-5.1.5.tar.gz
      cp ${libuvSrc} .toolchains/libuv-1.51.0.tar.gz
      cp ${luvSrc} .toolchains/luv-1.51.0-1.tar.gz
      cp ${luaCompat53Src} .toolchains/lua-compat-5.3-v0.13.tar.gz

      # Replace neovim submodule
      rm -rf neovim
      cp -r ${neovimSrc} neovim
      chmod -R u+w neovim

      # Patch cmake.deps to disable macOS platform detection for WASM cross-compile
      # This prevents -arch arm64 flags from being added to WASI clang
      sed -i.bak 's/list(APPEND DEPS_CMAKE_ARGS -D CMAKE_BUILD_TYPE/list(APPEND DEPS_CMAKE_ARGS -D CMAKE_SYSTEM_NAME=Generic -D CMAKE_OSX_ARCHITECTURES= -D CMAKE_OSX_DEPLOYMENT_TARGET= -D CMAKE_BUILD_TYPE/' \
        neovim/cmake.deps/CMakeLists.txt
    '';

    buildPhase = ''
      export HOME=$TMPDIR
      export WASI_SDK_OS="${wasiSdkOs}"

      # Ensure SSL certs are available for cmake downloads
      export SSL_CERT_FILE="${cacert}/etc/ssl/certs/ca-bundle.crt"
      export GIT_SSL_CAINFO="${cacert}/etc/ssl/certs/ca-bundle.crt"
      export CURL_CA_BUNDLE="${cacert}/etc/ssl/certs/ca-bundle.crt"
      export NIX_SSL_CERT_FILE="${cacert}/etc/ssl/certs/ca-bundle.crt"
      export REQUESTS_CA_BUNDLE="${cacert}/etc/ssl/certs/ca-bundle.crt"

      echo "=== Building host dependencies (cmake.deps) ==="
      cmake -S neovim/cmake.deps -B .deps -G "Unix Makefiles" \
        -DCMAKE_BUILD_TYPE=Release \
        -DUSE_BUNDLED=ON \
        -DUSE_BUNDLED_LUA=ON -DUSE_BUNDLED_LUAJIT=OFF \
        -DUSE_BUNDLED_LUV=ON -DUSE_BUNDLED_LIBUV=ON \
        -DUSE_BUNDLED_MSGPACK=ON -DUSE_BUNDLED_LIBTERMKEY=ON \
        -DUSE_BUNDLED_LIBVTERM=ON -DUSE_BUNDLED_TS=ON \
        -DUSE_BUNDLED_UNIBILIUM=ON -DUSE_BUNDLED_LPEG=ON \
        -DUSE_BUNDLED_UTF8PROC=ON
      cmake --build .deps -- -j$NIX_BUILD_CORES

      echo "=== Building host Lua (nlua0) ==="
      cmake -S neovim -B build-host -G "Unix Makefiles" \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_PREFIX_PATH=$PWD/.deps/usr \
        -DUSE_BUNDLED=OFF \
        -DPREFER_LUA=ON \
        -DENABLE_WASMTIME=OFF -DENABLE_LTO=OFF
      cmake --build build-host --target nlua0 -- -j$NIX_BUILD_CORES

      # Copy nlua0 to expected location
      mkdir -p build-host/lua-src/src
      cp .deps/usr/bin/lua build-host/lua-src/src/lua
      cp .deps/usr/bin/luac build-host/lua-src/src/luac
      if [ -f build-host/lib/libnlua0.so ]; then
        cp build-host/lib/libnlua0.so build-host/libnlua0-host.so
      elif [ -f build-host/lib/libnlua0.dylib ]; then
        cp build-host/lib/libnlua0.dylib build-host/libnlua0-host.so
      fi

      echo "=== Compiling setjmp stub for wasmi compatibility ==="
      mkdir -p build-wasm-deps
      # Compile custom setjmp/longjmp that doesn't use WASM exceptions
      .toolchains/wasi-sdk-${wasiSdkVersion}-${wasiSdkArch}-${wasiSdkOs}/bin/clang \
        --target=wasm32-wasi \
        -mno-exception-handling \
        -c $PWD/patches/wasi-shim/setjmp_stub.c \
        -o build-wasm-deps/setjmp_stub.o

      echo "=== Building WASM dependencies ==="
      # Override WASM_EH_FLAGS to disable exception handling instructions for wasmi compatibility
      # Asyncify will handle setjmp/longjmp via stack rewinding instead
      make wasm-deps CMAKE=cmake CMAKE_BUILD_JOBS=$NIX_BUILD_CORES WASM_DEPS_JOBS=$NIX_BUILD_CORES \
        CMAKE_OSX_ARCHITECTURES="" CMAKE_OSX_DEPLOYMENT_TARGET="" CMAKE_OSX_SYSROOT="" \
        WASM_EH_FLAGS="-mno-exception-handling"

      echo "=== Building WASM Neovim ==="
      # Link with our setjmp stub
      make wasm CMAKE=cmake CMAKE_BUILD_JOBS=$NIX_BUILD_CORES \
        WASM_EH_FLAGS="-mno-exception-handling" \
        CMAKE_EXE_LINKER_FLAGS="$PWD/build-wasm-deps/setjmp_stub.o"

      echo "=== Building Asyncify variant ==="
      # Call wasm-opt directly to avoid Makefile's binaryen download
      ${binaryen}/bin/wasm-opt build-wasm/bin/nvim \
        --asyncify \
        --pass-arg=asyncify-imports@wasi_snapshot_preview1.poll_oneoff \
        -O2 --strip-debug --strip-producers \
        -o build-wasm/bin/nvim-asyncify.wasm
    '';

    installPhase = ''
      mkdir -p $out/bin $out/share/nvim

      # Install WASM binaries
      cp build-wasm/bin/nvim $out/bin/nvim.wasm
      cp build-wasm/bin/nvim-asyncify.wasm $out/bin/nvim-asyncify.wasm

      # Install runtime files
      cp -r ${neovimSrc}/runtime $out/share/nvim/
    '';
  };

in nvimWasmFull
