import { init as initGhostty, Terminal, FitAddon } from "https://cdn.jsdelivr.net/npm/ghostty-web@0.4.0/+esm";

const statusEl = document.getElementById("status");
const sizeEl = document.getElementById("size");
const terminalHost = document.getElementById("terminal");

let term = null;
let fit = null;
let worker = null;
let ring = null;

let ghosttyReady = null;
let terminalDesignHeightPx = 0;

class SharedInputWriter {
  constructor(capacity = 262144) {
    this.capacity = capacity;
    this.buffer = new SharedArrayBuffer(8 + capacity);
    this.ctrl = new Int32Array(this.buffer, 0, 2);
    this.data = new Uint8Array(this.buffer, 8);
    Atomics.store(this.ctrl, 0, 0);
    Atomics.store(this.ctrl, 1, 0);
  }
  push(bytes) {
    const src = bytes instanceof Uint8Array ? bytes : new Uint8Array(bytes);
    let head = Atomics.load(this.ctrl, 0);
    let tail = Atomics.load(this.ctrl, 1);
    for (let i = 0; i < src.length; i += 1) {
      const next = (tail + 1) % this.capacity;
      if (next === head) break;
      this.data[tail] = src[i];
      tail = next;
    }
    Atomics.store(this.ctrl, 1, tail);
    Atomics.notify(this.ctrl, 1);
  }
}

async function initTerminal() {
  if (!ghosttyReady) ghosttyReady = initGhostty();
  await ghosttyReady;
  term = new Terminal({
    fontSize: 14,
    fontFamily: "ui-monospace, SFMono-Regular, Menlo, Consolas, monospace",
    scrollback: 0,
    convertEol: false,
    cursorBlink: true,
  });
  fit = new FitAddon();
  term.loadAddon(fit);
  term.open(terminalHost);
  terminalDesignHeightPx = Math.max(1, Math.floor(terminalHost.getBoundingClientRect().height || 520));
  fitAndSnap();

  // Forward terminal input to nvim via SharedArrayBuffer
  term.onData(handleTermData);

  terminalHost.addEventListener("click", () => {
    term.focus();
  });
}

function updateSizeLabel(cols = term?.cols, rows = term?.rows) {
  if (!cols || !rows) {
    sizeEl.textContent = "size: -";
    return;
  }
  sizeEl.textContent = `size: ${cols}x${rows}`;
}

function setStatus(text, warn = false) {
  statusEl.textContent = text;
  statusEl.style.color = warn ? "#ff9ea2" : "#e8edf5";
}

async function startSession() {
  if (!window.crossOriginIsolated) {
    setStatus("Serve with COOP/COEP so SharedArrayBuffer works", true);
    return;
  }

  stopSession();
  try {
    if (!term) await initTerminal();
  } catch (err) {
    setStatus(`ghostty-web init failed: ${err?.message || err}`, true);
    return;
  }
  fitAndSnap();

  ring = new SharedInputWriter();

  worker = new Worker(`./nvim-worker.js`, { type: "module" });
  worker.onmessage = handleWorkerMessage;
  worker.postMessage({ type: "start", inputBuffer: ring.buffer, cols: term.cols, rows: term.rows });
  setStatus("Starting Neovim (TUI)...");
}

function stopSession() {
  if (worker) {
    worker.terminate();
    worker = null;
  }
  ring = null;
}

function handleWorkerMessage(event) {
  const { type } = event.data || {};
  if (type === "tui-output") {
    // TUI mode: write raw ANSI directly to xterm.js
    if (term && event.data.data) {
      term.write(new Uint8Array(event.data.data));
      setStatus("Ready");
    }
  } else if (type === "exit") {
    setStatus(`nvim exited (${event.data.code})`, event.data.code !== 0);
  }
}

function handleTermData(data) {
  // Forward raw terminal input bytes to nvim
  if (!ring || !data) return;
  const encoder = new TextEncoder();
  ring.push(encoder.encode(data));
}

function fitAndSnap() {
  if (!term || !fit) return;
  if (terminalDesignHeightPx > 0) terminalHost.style.height = `${terminalDesignHeightPx}px`;
  fit.fit();
  snapTerminalHeightToRows();
  updateSizeLabel();
}

function snapTerminalHeightToRows() {
  if (!term) return;
  const metrics = term.renderer?.getMetrics?.();
  if (!metrics?.height) return;
  const h = Math.max(1, Math.floor((term.rows || 1) * metrics.height));
  if (terminalDesignHeightPx > 0) {
    terminalHost.style.height = `${Math.min(terminalDesignHeightPx, h)}px`;
  } else {
    terminalHost.style.height = `${h}px`;
  }
}

function handleResize() {
  if (!term) return;
  fitAndSnap();
  // Note: In TUI mode, nvim won't receive SIGWINCH.
  // For fixed size operation, this is acceptable.
  // For dynamic resize, would need to send escape sequence or restart.
}

window.addEventListener("resize", () => handleResize());

startSession().catch((err) => setStatus(`start failed: ${err?.message || err}`, true));
