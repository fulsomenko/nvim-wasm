# Neovim WASM Demo (SAB-free, Asyncify)

Minimal linegrid demo that runs Neovim in a Web Worker (WASI) and renders the UI in the browser (no `SharedArrayBuffer`).

## How it works
- Neovim runs in a Worker; the main thread attaches with `nvim_ui_attach` (linegrid).
- Input is sent over `postMessage`; the Worker feeds it into stdin.
- The bundled `nvim-asyncify.wasm` is produced from `build-wasm/bin/nvim` using Binaryen Asyncify so `poll_oneoff` can suspend (no COOP/COEP, no JSPI).

## Run
- Serve with any static server (no COOP/COEP required): `python3 serve.py` on localhost:8765.
- Open the page, click the grid, and type.

## Regenerate assets
- Rebuild + copy `nvim-asyncify.wasm` into this directory: `make demo-asyncify`
- Rebuild runtime tarball: `tar -czf examples/demo-asyncify/nvim-runtime.tar.gz -C neovim/.. runtime -C build-wasm usr nvim_version.lua`
