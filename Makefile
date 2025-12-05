# Wrapper Makefile (root) that drives wasm32-wasi build of the ./neovim submodule
# without modifying files inside the submodule.

NEOVIM_DIR ?= neovim
TOOLCHAIN_DIR := $(PWD)/.toolchains
PATCH_DIR := $(PWD)/patches

WASI_SDK_VER ?= 29.0
WASI_SDK_ARCH ?= $(shell uname -m | sed -e 's/x86_64/x86_64/' -e 's/aarch64/arm64/' -e 's/arm64/arm64/')
WASI_SDK_OS ?= linux
WASI_SDK_TAG := wasi-sdk-$(basename $(WASI_SDK_VER))
WASI_SDK_TAR := wasi-sdk-$(WASI_SDK_VER)-$(WASI_SDK_ARCH)-$(WASI_SDK_OS).tar.gz
WASI_SDK_URL ?= https://github.com/WebAssembly/wasi-sdk/releases/download/$(WASI_SDK_TAG)/$(WASI_SDK_TAR)
WASI_SDK_ROOT := $(TOOLCHAIN_DIR)/wasi-sdk-$(WASI_SDK_VER)-$(WASI_SDK_ARCH)-$(WASI_SDK_OS)

CMAKE_VERSION ?= 3.29.6
CMAKE_TAR := cmake-$(CMAKE_VERSION)-$(WASI_SDK_OS)-$(WASI_SDK_ARCH).tar.gz
CMAKE_URL ?= https://github.com/Kitware/CMake/releases/download/v$(CMAKE_VERSION)/$(CMAKE_TAR)
CMAKE_ROOT := $(TOOLCHAIN_DIR)/cmake-$(CMAKE_VERSION)-$(WASI_SDK_OS)-$(WASI_SDK_ARCH)
CMAKE := $(CMAKE_ROOT)/bin/cmake
CMAKE_GENERATOR ?= "Unix Makefiles"

WASM_DEPS_BUILD := $(PWD)/build-wasm-deps
WASM_DEPS_DOWNLOAD := $(TOOLCHAIN_DIR)/.deps-download-wasm
WASM_BUILD := $(PWD)/build-wasm
LIBUV_PATCHED_TAR := $(TOOLCHAIN_DIR)/libuv-wasi.tar.gz
LIBUV_ORIG_TAR := $(TOOLCHAIN_DIR)/libuv-1.51.0.tar.gz
LIBUV_ORIG_URL := https://github.com/libuv/libuv/archive/v1.51.0.tar.gz

.PHONY: wasm wasm-configure wasm-deps wasm-toolchain wasm-build-tools wasm-clean libuv-patched

HOST_LUA_CPATH ?= $(WASM_DEPS_BUILD)/build/src/lpeg/?.so;;
HOST_LUA_INIT ?= "table.unpack=table.unpack or unpack; unpack=table.unpack"
HOST_LUA_PATH ?= $(WASM_BUILD)/?.lua;;

wasm: wasm-configure
	LUA_CPATH="$(HOST_LUA_CPATH)" LUA_PATH="$(HOST_LUA_PATH)" LUA_INIT=$(HOST_LUA_INIT) $(CMAKE) --build $(WASM_BUILD) --target nvim_bin

wasm-configure: wasm-deps
	$(CMAKE) -S $(NEOVIM_DIR) -B $(WASM_BUILD) -G $(CMAKE_GENERATOR) \
		-DCMAKE_PROJECT_INCLUDE=$(PWD)/cmake/wasm-overrides.cmake \
		-DCMAKE_TOOLCHAIN_FILE=$(PWD)/cmake/toolchain-wasi.cmake \
		-DWASI_SDK_ROOT=$(WASI_SDK_ROOT) \
		-DCMAKE_C_COMPILER_TARGET=wasm32-wasi \
		-DCMAKE_C_FLAGS="-mllvm -wasm-enable-sjlj -D_WASI_EMULATED_SIGNAL -I$(PATCH_DIR)/wasi-shim/include" \
		-DWASI_SHIM_DIR=$(PWD)/patches/wasi-shim/include \
		-DCMAKE_PREFIX_PATH=$(WASM_DEPS_BUILD)/usr \
		-DLUV_LIBRARY=$(WASM_DEPS_BUILD)/usr/lib/libluv.a \
		-DLUV_INCLUDE_DIR=$(WASM_DEPS_BUILD)/usr/include \
		-DLIBUV_LIBRARY=$(WASM_DEPS_BUILD)/usr/lib/libuv.a \
		-DLIBUV_INCLUDE_DIR=$(WASM_DEPS_BUILD)/usr/include \
		-DLPEG_LIBRARY=$(WASM_DEPS_BUILD)/usr/lib/liblpeg.a \
		-DLPEG_INCLUDE_DIR=$(WASM_DEPS_BUILD)/usr/include \
		-DUTF8PROC_LIBRARY=$(WASM_DEPS_BUILD)/usr/lib/libutf8proc.a \
		-DUTF8PROC_INCLUDE_DIR=$(WASM_DEPS_BUILD)/usr/include \
		-DTREESITTER_LIBRARY=$(WASM_DEPS_BUILD)/usr/lib/libtree-sitter.a \
		-DTREESITTER_INCLUDE_DIR=$(WASM_DEPS_BUILD)/usr/include \
		-DUNIBILIUM_LIBRARY=$(WASM_DEPS_BUILD)/usr/lib/libunibilium.a \
		-DUNIBILIUM_INCLUDE_DIR=$(WASM_DEPS_BUILD)/usr/include \
		-DLUA_LIBRARY=$(WASM_DEPS_BUILD)/usr/lib/liblua.a \
		-DLUA_INCLUDE_DIR=$(WASM_DEPS_BUILD)/usr/include \
		-DICONV_INCLUDE_DIR=$(PWD)/patches/wasi-shim/include \
		-DICONV_LIBRARY=$(PWD)/patches/wasi-shim/lib/libiconv.a \
		-DLIBINTL_INCLUDE_DIR=$(PWD)/patches/wasi-shim/include \
		-DLIBINTL_LIBRARY=$(PWD)/patches/wasi-shim/lib/libintl.a \
		-DCMAKE_SYSROOT=$(WASI_SDK_ROOT)/share/wasi-sysroot \
		-DCMAKE_BUILD_TYPE=RelWithDebInfo \
		-DUSE_BUNDLED=ON \
		-DUSE_BUNDLED_LUAJIT=OFF -DPREFER_LUA=ON \
		-DUSE_BUNDLED_LUA=ON -DUSE_BUNDLED_LUV=ON -DUSE_BUNDLED_LIBUV=ON \
		-DUSE_BUNDLED_MSGPACK=ON -DUSE_BUNDLED_LIBTERMKEY=ON \
		-DUSE_BUNDLED_LIBVTERM=ON -DUSE_BUNDLED_TS=ON \
		-DUSE_BUNDLED_TREESITTER=ON -DUSE_BUNDLED_UNIBILIUM=ON \
		-DENABLE_JEMALLOC=OFF -DENABLE_WASMTIME=OFF \
		-DENABLE_LTO=OFF \
		-DDEPS_BUILD_DIR=$(WASM_DEPS_BUILD) \
		-DCMAKE_EXE_LINKER_FLAGS="--target=wasm32-wasi --sysroot=$(WASI_SDK_ROOT)/share/wasi-sysroot -Wl,--allow-undefined -lwasi-emulated-signal"

wasm-deps: wasm-toolchain wasm-build-tools libuv-patched
	@libuv_sha=$$(sha256sum $(LIBUV_PATCHED_TAR) | awk '{print $$1}'); \
	$(CMAKE) -S $(NEOVIM_DIR)/cmake.deps -B $(WASM_DEPS_BUILD) -G $(CMAKE_GENERATOR) \
		-DCMAKE_PROJECT_INCLUDE=$(PWD)/cmake/wasm-overrides.cmake \
		-DCMAKE_TOOLCHAIN_FILE=$(PWD)/cmake/toolchain-wasi.cmake \
		-DWASI_SDK_ROOT=$(WASI_SDK_ROOT) \
		-DCMAKE_C_COMPILER_TARGET=wasm32-wasi \
		-DCMAKE_C_FLAGS="-mllvm -wasm-enable-sjlj -D_WASI_EMULATED_SIGNAL -I$(PATCH_DIR)/wasi-shim/include" \
		-DWASI_SHIM_DIR=$(PWD)/patches/wasi-shim/include \
		-DCMAKE_SYSROOT=$(WASI_SDK_ROOT)/share/wasi-sysroot \
		-DCMAKE_BUILD_TYPE=Release \
		-DUSE_BUNDLED_LUAJIT=OFF -DPREFER_LUA=ON -DUSE_BUNDLED_LUA=ON \
		-DDEPS_DOWNLOAD_DIR=$(WASM_DEPS_DOWNLOAD) \
		-DLIBUV_URL=file://$(LIBUV_PATCHED_TAR) \
		-DLIBUV_SHA256=$$libuv_sha \
		-DCMAKE_EXE_LINKER_FLAGS="--target=wasm32-wasi --sysroot=$(WASI_SDK_ROOT)/share/wasi-sysroot -Wl,--allow-undefined -lwasi-emulated-signal"
	$(CMAKE) --build $(WASM_DEPS_BUILD)

wasm-toolchain:
	@mkdir -p $(TOOLCHAIN_DIR)
	@if [ ! -d "$(WASI_SDK_ROOT)" ]; then \
	  echo "Downloading wasi-sdk $(WASI_SDK_VER) ..."; \
	  curl -L "$(WASI_SDK_URL)" -o "$(TOOLCHAIN_DIR)/$(WASI_SDK_TAR)"; \
	  tar -C "$(TOOLCHAIN_DIR)" -xf "$(TOOLCHAIN_DIR)/$(WASI_SDK_TAR)"; \
	fi

wasm-build-tools:
	@mkdir -p $(TOOLCHAIN_DIR)
	@if [ ! -x "$(CMAKE)" ]; then \
	  echo "Downloading CMake $(CMAKE_VERSION) ..."; \
	  curl -L "$(CMAKE_URL)" -o "$(TOOLCHAIN_DIR)/$(CMAKE_TAR)"; \
	  tar -C "$(TOOLCHAIN_DIR)" -xf "$(TOOLCHAIN_DIR)/$(CMAKE_TAR)"; \
	fi

wasm-clean:
	$(RM) -r $(WASM_BUILD) $(WASM_DEPS_BUILD)

libuv-patched: $(LIBUV_PATCHED_TAR)

$(LIBUV_PATCHED_TAR):
	@mkdir -p $(TOOLCHAIN_DIR) $(PATCH_DIR)
	@if [ ! -f "$(LIBUV_ORIG_TAR)" ]; then \
	  echo "Downloading libuv orig ..."; \
	  curl -L "$(LIBUV_ORIG_URL)" -o "$(LIBUV_ORIG_TAR)"; \
	fi
	@tmpdir=$$(mktemp -d); \
	  tar -C $$tmpdir -xf "$(LIBUV_ORIG_TAR)" || exit $$?; \
	  cd $$tmpdir/libuv-1.51.0 && patch -p1 < "$(PATCH_DIR)/libuv-wasi.patch"; \
	  tar -C $$tmpdir -czf "$(LIBUV_PATCHED_TAR)" libuv-1.51.0; \
	  rm -rf $$tmpdir
