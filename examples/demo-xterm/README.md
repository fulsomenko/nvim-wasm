# Neovim WASM + xterm.js Demo (ghostty-web backend)

Neovim in a Web Worker (WASI), rendered via an xterm.js-compatible terminal API (powered by `ghostty-web`) by converting Neovim's `ext_linegrid` UI updates into ANSI.

## Demo
Try it: https://nvim-wasm-xterm.pages.dev/



https://github.com/user-attachments/assets/3500597a-f552-4e87-895c-d11fa0715060



## Run
- Serve with COOP/COEP so `SharedArrayBuffer` works (e.g. `python serve.py` on localhost:8765).
- Open the page, click the terminal, and type.
