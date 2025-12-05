# Injected via -DCMAKE_PROJECT_INCLUDE for wasm builds.
# Removes Unix PTY sources that rely on unsupported APIs under WASI and
# replaces them with a small stub implementation that just reports ENOSYS.

if(NOT CMAKE_SOURCE_DIR MATCHES "/neovim$")
  return()
endif()

function(_nvim_wasm_disable_pty)
  get_filename_component(_wrap_root "${CMAKE_SOURCE_DIR}/.." ABSOLUTE)
  set(_deps_libdir "${_wrap_root}/build-wasm-deps/usr/lib")
  set(_stub_srcs
    "${_wrap_root}/patches/wasi-shim/pty_stub.c"
    "${_wrap_root}/patches/wasi-shim/signal_stub.c")
  foreach(_stub IN LISTS _stub_srcs)
    if(NOT EXISTS "${_stub}")
      message(FATAL_ERROR "wasm stub source not found: ${_stub}")
    endif()
  endforeach()

  set(_remove_srcs
    "${CMAKE_SOURCE_DIR}/src/nvim/os/pty_proc_unix.c"
    "${CMAKE_SOURCE_DIR}/src/nvim/os/signal.c")

  # Drop unsupported PTY sources and add our stub replacement.
  if(TARGET main_lib)
    get_target_property(_iface main_lib INTERFACE_SOURCES)
    if(_iface STREQUAL "_iface-NOTFOUND")
      set(_iface "")
    endif()
    list(REMOVE_ITEM _iface ${_remove_srcs})
    list(APPEND _iface ${_stub_srcs})
    set_property(TARGET main_lib PROPERTY INTERFACE_SOURCES "${_iface}")
    target_include_directories(main_lib INTERFACE "${_wrap_root}/patches/wasi-shim/include")
    # main_lib is only used locally, so drop any system libraries from its interface.
    set_property(TARGET main_lib PROPERTY INTERFACE_LINK_LIBRARIES "")
  endif()

  if(TARGET nvim_bin)
    get_target_property(_srcs nvim_bin SOURCES)
    if(_srcs STREQUAL "_srcs-NOTFOUND")
      set(_srcs "")
    endif()
    list(REMOVE_ITEM _srcs ${_remove_srcs})
    set_property(TARGET nvim_bin PROPERTY SOURCES "${_srcs}")
    target_sources(nvim_bin PRIVATE ${_stub_srcs})
    target_include_directories(nvim_bin BEFORE PRIVATE
      "${_wrap_root}/patches/wasi-shim/include")

    # Drop Unix-only linker flags/libs that fail on wasm-ld.
    get_target_property(_opts nvim_bin LINK_OPTIONS)
    if(NOT _opts STREQUAL "_opts-NOTFOUND")
      list(REMOVE_ITEM _opts "-Wl,--no-undefined")
      set_property(TARGET nvim_bin PROPERTY LINK_OPTIONS "${_opts}")
    endif()

    # Rebind to only the wasm-friendly static libs we built.
    set_property(TARGET nvim_bin PROPERTY LINK_LIBRARIES "")
    target_link_libraries(nvim_bin PRIVATE
      main_lib
      "${_deps_libdir}/libluv.a"
      "${_deps_libdir}/liblpeg.a"
      "${_deps_libdir}/libtree-sitter.a"
      "${_deps_libdir}/libutf8proc.a"
      "${_deps_libdir}/libunibilium.a"
      "${_deps_libdir}/liblua.a"
      "${_deps_libdir}/libuv.a")
  endif()

  # Skip helptags generation which would try to run the wasm binary.
  if(TARGET nvim_runtime)
    set_property(TARGET nvim_runtime PROPERTY EXCLUDE_FROM_ALL TRUE)
    set_property(TARGET nvim_runtime PROPERTY EXCLUDE_FROM_DEFAULT_BUILD TRUE)
  endif()

endfunction()

cmake_language(DEFER DIRECTORY "${CMAKE_SOURCE_DIR}" CALL _nvim_wasm_disable_pty)
