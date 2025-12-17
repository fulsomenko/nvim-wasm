# Neovim WASM Demo (SAB-free, Asyncify)

Minimal linegrid demo that runs Neovim in a Web Worker (WASI) and renders the UI in the browser (no `SharedArrayBuffer`).

## Demo
Try it: [https://nvim-wasm-monaco.pages.dev/](https://nvim-wasm-asyncify.pages.dev/)

## How it works
- Neovim runs in a Worker; the main thread attaches with `nvim_ui_attach` (linegrid).
- Input is sent over `postMessage`; the Worker feeds it into stdin.
- The bundled `nvim-asyncify.wasm` is produced from `build-wasm/bin/nvim` using Binaryen Asyncify so `poll_oneoff` can suspend (no COOP/COEP, no JSPI).

## Run
- Serve with any static server (no COOP/COEP required): `python3 serve.py` on localhost:8765.
- Open the page, click the grid, and type.
