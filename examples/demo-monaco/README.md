# Neovim WASM + Monaco Demo

Headless Neovim in a Worker (WASI) with Monaco rendering the buffer and cursor.

## How it works
- Neovim runs headless and speaks msgpack-RPC over a SharedArrayBuffer ring.
- Buffer and cursor state are mirrored into Monaco from Neovim buffer events (vscode-neovim style).
- All key input is forwarded to Neovim; Monaco stays read-only and reflects Neovim state.

## Run
- Serve with COOP/COEP so `SharedArrayBuffer` works (e.g. `python serve.py` on localhost:3000).
- Open the page; Monaco shows the Neovim buffer and tracks its cursor/mode.
