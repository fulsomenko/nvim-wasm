import { encode } from "./msgpack.js";

const statusEl = document.getElementById("status");
const modeEl = document.getElementById("mode");
const cursorEl = document.getElementById("cursor");
const bufferEl = document.getElementById("buffer");
const editorHost = document.getElementById("editor");

const WORKER_VERSION = "v1";
const cols = 140;
const rows = 60;
const themeName = "nvim-dark-visual";
const DEFAULT_VISUAL_BG = "#3e4451";
const DEFAULT_VISUAL_HL = "#3e445180";

let monaco = null;
let editor = null;
let worker = null;
let ring = null;
let reqId = 1;
let bufHandle = null; // numeric buffer id
let pending = new Map();
let primeSent = false;
let lastCursorStyle = null;
let lastCursorBlink = null;
let lastCursorWidth = null;
let initialCursorWidth = 0;
let typicalFullWidth = 2;
let cursorRefreshInFlight = false;
let cursorRefreshPending = false;
let cursorRefreshTimer = null;
let lastCursorPos = null;
let suppressCursorSync = false;
let lastMode = "";
let visualSelectionToken = 0;
let visualSelectionActive = false;

const monacoReady = loadMonaco();

const VISUAL_SELECTION_LUA = `
local api, fn = vim.api, vim.fn

local function virtcol2byte(winid, lnum, virtcol)
  local byte_idx = fn.virtcol2col(winid, lnum, virtcol) - 1
  if fn.has("nvim-0.10.0") == 0 then
    return byte_idx
  end
  local buf = api.nvim_win_get_buf(winid)
  local line = api.nvim_buf_get_lines(buf, lnum - 1, lnum, false)[1] or ""
  local char_idx = fn.charidx(line, byte_idx)
  local prefix = fn.strcharpart(line, 0, char_idx + 1)
  return #prefix
end

local function get_selections(win)
  win = win or api.nvim_get_current_win()
  local buf = api.nvim_win_get_buf(win)
  local mode = api.nvim_get_mode().mode or ""
  local is_visual = mode:match("[vV\\22sS\\19]")

  if not is_visual then
    local cur = api.nvim_win_get_cursor(win)
    local line0 = (cur[1] or 1) - 1
    local col0 = cur[2] or 0
    return { { start = { line = line0, col = col0 }, ["end"] = { line = line0, col = col0 }, inclusive = false } }
  end

  local sline = fn.line('v') - 1
  local scol = fn.col('v') - 1
  local eline = fn.line('.') - 1
  local ecol = fn.col('.') - 1

  if mode:lower() == "v" then
    local start_left = true
    if sline > eline or (sline == eline and scol > ecol) then
      start_left = false
      sline, eline = eline, sline
      scol, ecol = ecol, scol
    end
    if mode == "V" then
      scol = 0
      local line = api.nvim_buf_get_lines(buf, eline, eline + 1, false)[1] or ""
      ecol = #line
    end
    local range = {
      start = { line = sline, col = scol },
      ["end"] = { line = eline, col = ecol },
      inclusive = (vim.o.selection or "inclusive") == "inclusive",
    }
    if not start_left then
      range = { start = range["end"], ["end"] = range.start, inclusive = range.inclusive }
    end
    return { range }
  end

  local ranges = {}
  local start_vcol, end_vcol = fn.virtcol("v"), fn.virtcol(".")
  local top, bot = math.min(sline, eline), math.max(sline, eline)
  for lnum = top, bot do
    local line = api.nvim_buf_get_lines(buf, lnum, lnum + 1, false)[1] or ""
    local disp = fn.strdisplaywidth(line)
    if start_vcol > disp and end_vcol > disp then
      local chars = ({ vim.str_utfindex(line) })[2]
      table.insert(ranges, { start = { line = lnum, col = chars }, ["end"] = { line = lnum, col = chars }, inclusive = true })
    else
      local col_a = virtcol2byte(win, lnum + 1, math.min(start_vcol, end_vcol))
      local col_b = virtcol2byte(win, lnum + 1, math.max(start_vcol, end_vcol))
      table.insert(ranges, { start = { line = lnum, col = col_a }, ["end"] = { line = lnum, col = col_b }, inclusive = true })
    end
  end

  if #ranges == 0 then
    local cur = api.nvim_win_get_cursor(win)
    local line0 = (cur[1] or 1) - 1
    local col0 = cur[2] or 0
    return { { start = { line = line0, col = col0 }, ["end"] = { line = line0, col = col0 }, inclusive = false } }
  end

  return ranges
end

return get_selections(...)
`;



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

function init() {
  setStatus("waiting", true);
  startSession().catch((err) => setStatus(`start failed: ${err?.message || err}`, true));
}

async function startSession() {
  if (!window.crossOriginIsolated) {
    setStatus("COOP/COEP required", true);
    return;
  }
  stopSession(true);
  await monacoReady;
  if (!editor) createEditor();

  ring = new SharedInputWriter();
  worker = new Worker(`./nvim-worker.js?${WORKER_VERSION}`, { type: "module" });
  worker.onmessage = handleWorkerMessage;
  worker.postMessage({ type: "start", inputBuffer: ring.buffer, cols, rows });
  setStatus("starting...");
  primeSent = false;
  setTimeout(() => { if (!primeSent) primeSession(); }, 400);
}

function stopSession(silent = false) {
  if (worker) {
    worker.terminate();
    worker = null;
  }
  ring = null;
  pending.clear();
  bufHandle = null;
  primeSent = false;
  if (!silent) setStatus("stopped", true);
}

async function primeSession() {
  if (!ring) return;
  primeSent = true;
  try {
    await waitForApi();
    sendRpc("nvim_command", ["set noswapfile signcolumn=no number norelativenumber"]);
    sendRpc("nvim_command", ["set nowrap laststatus=0 cmdheight=1"]);
    sendRpc("nvim_command", ["set shortmess+=F"]);
    sendRpc("nvim_command", ["set clipboard=unnamedplus"]);
    void syncVisualSelectionColor();

    const buf = await rpcCall("nvim_get_current_buf", []);
    const id = extractBufId(buf) ?? 1;
    bufHandle = id; // set early so initial buf_events are not dropped
    bufferEl.textContent = `buf: ${id}`;
    const attached = await rpcCall("nvim_buf_attach", [id, true, {}]);
    if (attached !== true) throw new Error("nvim_buf_attach failed");
    const lines = await rpcCall("nvim_buf_get_lines", [id, 0, -1, false]);
    applyBuffer(lines || [""]);
    setStatus("ready");
    const seeded = await seedBuffer(id);
    if (seeded && seeded.length) {
      applyBuffer(seeded);
    } else if (!lines || !lines.length) {
      applyBuffer(["-- Monaco + Neovim (WASM)", "-- Seed failed; using fallback text"]);
      updateCursor(1, 1);
    }
    bufHandle = id;
    await refreshCursorMode();
  } catch (err) {
    setStatus("failed to attach", true);
  }
}

function createEditor() {
  editor = monaco.editor.create(editorHost, {
    value: "",
    language: "lua",
    theme: "vs-dark",
    fontSize: 14,
    fontFamily: "Berkeley Mono, JetBrains Mono, ui-monospace, SFMono-Regular",
    readOnly: true,
    minimap: { enabled: false },
    lineNumbers: "on",
    automaticLayout: true,
    scrollBeyondLastLine: false,
    smoothScrolling: true,
    contextmenu: false,
    padding: { top: 12, bottom: 12 },
    cursorSmoothCaretAnimation: true,
    renderWhitespace: "none",
  });
  try {
    const EditorOption = monaco.editor.EditorOption;
    const fontInfo = editor.getOption(EditorOption.fontInfo);
    initialCursorWidth = editor.getOption(EditorOption.cursorWidth) || 0;
    typicalFullWidth = fontInfo?.typicalFullwidthCharacterWidth || 2;
  } catch (_) {
    initialCursorWidth = 0;
    typicalFullWidth = 2;
  }

  editor.onKeyDown(handleMonacoKey);

  editor.onMouseDown((ev) => {
    if (!bufHandle || !ev.target?.position) return;
    const { lineNumber, column } = ev.target.position;
    sendRpc("nvim_win_set_cursor", [0, [lineNumber, column]]);
  });

  editor.onDidChangeCursorPosition((ev) => {
    if (suppressCursorSync || !lastCursorPos) return;
    if (ev.source === "keyboard") {
      suppressCursorSync = true;
      editor.setPosition(lastCursorPos);
      suppressCursorSync = false;
    }
  });
}

function sendInput(keys) {
  sendRpc("nvim_input", [keys]);
  scheduleCursorRefresh();
}

function handleMonacoKey(ev) {
  const key = translateKey(ev.browserEvent);
  if (!key) return;
  ev.preventDefault();
  sendInput(key);
}

function sendRpc(method, params = []) {
  if (!ring) return;
  const msg = encode([0, reqId++, method, params]);
  ring.push(msg);
}

function sendRpcResponse(msgid, error, result) {
  if (!ring) return;
  const msg = encode([1, msgid, error, result]);
  ring.push(msg);
}

function rpcCall(method, params = []) {
  return new Promise((resolve, reject) => {
    if (!ring) { reject(new Error("session not started")); return; }
    const id = reqId++;
    pending.set(id, { resolve, reject, ts: Date.now() });
    ring.push(encode([0, id, method, params]));
    setTimeout(() => {
      if (pending.has(id)) {
        pending.delete(id);
        reject(new Error(`rpc timeout: ${method}`));
      }
    }, 8000);
  });
}

function handleWorkerMessage(event) {
  const { type } = event.data || {};
  if (type === "rpc-response") {
    const { msgid, error, result } = event.data;
    const entry = pending.get(msgid);
    if (!entry) return;
    pending.delete(msgid);
    if (error) entry.reject(new Error(String(error)));
    else entry.resolve(result);
  } else if (type === "rpc-notify") {
    void handleNotify(event.data.method, event.data.params || []);
  } else if (type === "rpc-request") {
    handleRequest(event.data.msgid, event.data.method, event.data.params || []);
  } else if (type === "clipboard-copy") {
    const text = (event.data.lines || []).join("\n");
    if (navigator.clipboard?.writeText) navigator.clipboard.writeText(text).catch(() => {});
  } else if (type === "clipboard-paste") {
    doClipboardPaste(event.data.msgid);
  } else if (type === "start-error") {
    setStatus(`start failed: ${event.data?.message || "unknown"}`, true);
  } else if (type === "exit") {
    setStatus(`nvim exited (${event.data.code})`, event.data.code !== 0);
  }
}

function handleRequest(msgid, method, params) {
  if (method === "wasm-clipboard-paste") {
    doClipboardPaste(msgid);
  } else {
    // Unknown request: respond with nil to keep nvim moving.
    sendRpcResponse(msgid, null, null);
  }
}

async function handleNotify(method, params) {
  if (method === "nvim_buf_lines_event") {
    const [buf] = params;
    const id = extractBufId(buf);
    if (bufHandle != null && id === bufHandle) {
      try {
        const allLines = await rpcCall("nvim_buf_get_lines", [id, 0, -1, false]);
        applyBuffer(allLines || [""]);
      } catch (_) {
        // ignore
      }
      void refreshCursorMode();
    }
  } else if (method === "nvim_buf_detach_event") {
    bufHandle = null;
    bufferEl.textContent = "buf: -";
  }
}

function applyBuffer(lines = [""]) {
  if (!editor) return;
  const current = editor.getModel().getValue();
  const joined = (lines && lines.length ? lines : [""]).join("\n");
  editor.getModel().setValue(joined);
}

function translateKey(ev) {
  const key = ev.key;
  const isCtrl = ev.ctrlKey || ev.metaKey;
  const isAlt = ev.altKey;
  switch (key) {
    case "Backspace": return "<BS>";
    case "Enter": return "<CR>";
    case "Escape": return "<Esc>";
    case "Tab": return "<Tab>";
    case "ArrowUp": return "<Up>";
    case "ArrowDown": return "<Down>";
    case "ArrowLeft": return "<Left>";
    case "ArrowRight": return "<Right>";
    case "Delete": return "<Del>";
    case "Home": return "<Home>";
    case "End": return "<End>";
    case "PageUp": return "<PageUp>";
    case "PageDown": return "<PageDown>";
    case "Insert": return "<Insert>";
    default: break;
  }
  if (key.length === 1) {
    const char = ev.shiftKey ? key : key.toLowerCase();
    if (!isCtrl && !isAlt) return char;
    let mod = "";
    if (isCtrl) mod += "C-";
    if (isAlt) mod += "A-";
    return `<${mod}${char}>`;
  }
  return null;
}

function doClipboardPaste(msgid) {
  const fallback = (text) => {
    const lines = (text || "").split(/\r?\n/);
    sendRpcResponse(msgid, null, [lines, "v"]);
  };
  if (!navigator.clipboard?.readText) {
    const manual = window.prompt("Paste text");
    fallback(manual || "");
    return;
  }
  navigator.clipboard.readText()
    .then((text) => fallback(text || ""))
    .catch(() => fallback(""));
}

function updateCursor(line, col) {
  if (!editor) return;
  const pos = clampCursor(line, col - 1); // clamp expects 0-based col
  const ln = pos.line;
  const cl = pos.col;
  cursorEl.textContent = `cursor: ${ln}:${cl}`;
  const monacoPos = { lineNumber: ln, column: cl };
  lastCursorPos = monacoPos;
  if (!visualSelectionActive) {
    const current = editor.getPosition();
    const same = current && current.lineNumber === ln && current.column === cl;
    if (!same) {
      suppressCursorSync = true;
      editor.setPosition(monacoPos);
      editor.revealPositionInCenterIfOutsideViewport(monacoPos);
      suppressCursorSync = false;
    }
  }
}

function setStatus(text, warn = false) {
  statusEl.textContent = text;
  statusEl.className = warn ? "status warn" : "status ok";
}

async function seedBuffer(bufHandle) {
  const buf = extractBufId(bufHandle);
  if (!buf || buf <= 0) return false;
  const seedLines = [
    "-- Monaco + Neovim (WASM)",
    "-- Click here, press i, and start typing.",
    "",
    "local function greet(name)",
    "  return 'hello ' .. name",
    "end",
    "",
    "print(greet('monaco'))",
  ];
  try {
    await rpcCall("nvim_buf_set_lines", [buf, 0, -1, false, seedLines]);
    await rpcCall("nvim_buf_set_option", [buf, "modifiable", true]);
    await rpcCall("nvim_buf_set_option", [buf, "modified", true]);
    await rpcCall("nvim_buf_set_option", [buf, "buftype", ""]);
    await rpcCall("nvim_buf_set_option", [buf, "filetype", "lua"]);
    await rpcCall("nvim_buf_set_name", [buf, "monaco-demo.lua"]);
    return seedLines;
  } catch (_) {
    return null;
  }
}

function loadMonaco() {
  return new Promise((resolve, reject) => {
    if (!window.require) {
      reject(new Error("monaco loader missing"));
      return;
    }
    window.require.config({ paths: { vs: "https://cdn.jsdelivr.net/npm/monaco-editor@0.44.0/min/vs" } });
    window.require(["vs/editor/editor.main"], () => {
      monaco = window.monaco;
      resolve(monaco);
    }, reject);
  });
}

async function waitForApi(retries = 5, delay = 300) {
  for (let i = 0; i < retries; i += 1) {
    try {
      await rpcCall("nvim_get_api_info", []);
      return;
    } catch (_) {
      await new Promise((r) => setTimeout(r, delay));
    }
  }
  throw new Error("nvim_get_api_info timed out");
}

function decodeHandleId(data) {
  if (!data || data.length === 0) return null;
  const t = data[0];
  if (data.length === 1) {
    return t <= 0x7f ? t : (t - 0x100);
  }
  const view = new DataView(data.buffer, data.byteOffset, data.byteLength);
  switch (t) {
    case 0xcc: return view.getUint8(1);
    case 0xcd: return view.getUint16(1);
    case 0xce: return view.getUint32(1);
    case 0xcf: return Number(view.getBigUint64(1));
    case 0xd0: return view.getInt8(1);
    case 0xd1: return view.getInt16(1);
    case 0xd2: return view.getInt32(1);
    case 0xd3: return Number(view.getBigInt64(1));
    default: return t;
  }
}

function toUint8(data) {
  if (data instanceof Uint8Array) return data;
  if (data instanceof ArrayBuffer) return new Uint8Array(data);
  if (Array.isArray(data)) return new Uint8Array(data);
  if (Number.isInteger(data)) return new Uint8Array([data & 0xff]);
  if (data && data.type === "Buffer" && Array.isArray(data.data)) return new Uint8Array(data.data);
  return null;
}

function extractBufId(val) {
  if (val && typeof val === "object" && typeof val.type === "number") {
    const data = toUint8(val.data);
    if (data) {
      const id = decodeHandleId(data);
      if (id != null && id > 0) return id;
    }
  }
  const num = Number(val);
  if (Number.isInteger(num) && num > 0) return num;
  return null;
}

function clamp(value, min, max) {
  return Math.min(Math.max(value, min), max);
}

function scheduleCursorRefresh() {
  if (cursorRefreshTimer) return;
  cursorRefreshTimer = setTimeout(() => {
    cursorRefreshTimer = null;
    void refreshCursorMode();
  }, 30);
}

function clampCursor(ln, col0) {
  const fallbackLine = Math.max(1, Number(ln) || 1);
  const fallbackCol = Math.max(1, (Number(col0) || 0) + 1);
  const model = editor?.getModel();
  if (!model) {
    return { line: fallbackLine, col: fallbackCol };
  }
  const lineCount = model.getLineCount();
  const line = clamp(fallbackLine, 1, lineCount);
  const text = model.getLineContent(line) ?? "";
  const maxColumn = model.getLineMaxColumn(line);
  const byteCol = Math.max(0, Number(col0) || 0);
  const charIndex = byteIndexToCharIndex(text, byteCol);
  const col = clamp(charIndex + 1, 1, maxColumn);
  return { line, col };
}

async function refreshCursorMode() {
  if (cursorRefreshInFlight) {
    cursorRefreshPending = true;
    return;
  }
  cursorRefreshInFlight = true;
  try {
    const [cursor, mode] = await Promise.all([
      rpcCall("nvim_win_get_cursor", [0]),
      rpcCall("nvim_get_mode", []),
    ]);
    if (Array.isArray(cursor) && cursor.length >= 2) {
      // nvim_win_get_cursor returns 1-based line, 0-based col (bytes)
      const ln = cursor[0];
      const col0 = cursor[1];
      const clamped = clampCursor(ln, col0);
      updateCursor(clamped.line, clamped.col);
    }
    if (mode && typeof mode.mode === "string") {
      modeEl.textContent = `mode: ${mode.mode}`;
      lastMode = mode.mode;
      applyCursorStyle(mode.mode);
    }
    void updateVisualSelection(lastMode);
  } catch (err) {
    // swallow errors during rapid input
  } finally {
    cursorRefreshInFlight = false;
    if (cursorRefreshPending) {
      cursorRefreshPending = false;
      void refreshCursorMode();
    }
  }
}

function applyCursorStyle(mode) {
  if (!editor) return;
  const m = typeof mode === "string" ? mode : "";
  const isInsert = m.startsWith("i") || m.startsWith("R");
  const style = isInsert ? "line" : "block";
  const blink = isInsert ? "blink" : "solid";
  const width = isInsert ? (initialCursorWidth || 1) : typicalFullWidth;
  if (style === lastCursorStyle && blink === lastCursorBlink && width === lastCursorWidth) return;
  editor.updateOptions({ cursorStyle: style, cursorBlinking: blink, cursorWidth: width });
  lastCursorStyle = style;
  lastCursorBlink = blink;
  lastCursorWidth = width;
}

async function updateVisualSelection(mode) {
  const visual = isVisualMode(mode);
  const token = ++visualSelectionToken;
  if (!editor || !monaco) return;
  if (!visual) {
    if (visualSelectionActive) {
      const pos = editor.getPosition() || lastCursorPos || { lineNumber: 1, column: 1 };
      editor.setSelection(new monaco.Selection(pos.lineNumber, pos.column, pos.lineNumber, pos.column));
      visualSelectionActive = false;
    }
    return;
  }

  try {
    const selections = await fetchVisualRanges();
    if (token !== visualSelectionToken) return;
    if (!selections.length) return;
    if (selections.length === 1) editor.setSelection(selections[0]);
    else editor.setSelections(selections);
    visualSelectionActive = true;
  } catch (_) {
    // ignore selection fetch failures
  }
}

async function fetchVisualRanges() {
  const res = await rpcCall("nvim_exec_lua", [VISUAL_SELECTION_LUA, []]);
  return Array.isArray(res) ? res.map(byteRangeToSelection).filter(Boolean) : [];
}

function byteRangeToSelection(range) {
  if (!range || !range.start || !range.end) return null;
  const start = toMonacoBytePos(range.start, false);
  const end = toMonacoBytePos(range.end, !!range.inclusive);
  if (!start || !end) return null;
  return new monaco.Selection(start.lineNumber, start.column, end.lineNumber, end.column);
}

function toMonacoBytePos(pos, inclusiveEnd) {
  if (!pos || typeof pos.line !== "number" || typeof pos.col !== "number") return null;
  const model = editor?.getModel();
  const lineNumber = clamp(pos.line + 1, 1, model?.getLineCount() || Infinity);
  if (!model) {
    const baseCol = Math.max(1, pos.col + 1);
    return { lineNumber, column: baseCol + (inclusiveEnd ? 1 : 0) };
  }
  const text = model.getLineContent(lineNumber) ?? "";
  const byte = Math.max(0, Number(pos.col) || 0);
  let endByte = byte;
  if (inclusiveEnd) {
    const charIndex = byteIndexToCharIndex(text, byte);
    const cp = text.codePointAt(charIndex);
    endByte = byte + utf8ByteLength(cp || 0);
  }
  const column = byteIndexToCharIndex(text, endByte) + 1;
  const maxColumn = model.getLineMaxColumn(lineNumber);
  return { lineNumber, column: clamp(column, 1, maxColumn) };
}

function isVisualMode(mode) {
  const m = typeof mode === "string" ? mode : lastMode;
  return m.startsWith("v") || m.startsWith("V") || m === "\u0016" || m.startsWith("s") || m.startsWith("S") || m === "\u0013";
}

async function syncVisualSelectionColor() {
  if (!monaco || !editor) return;
  try {
    const hex = await fetchVisualBg();
    const base = hex || "#3e4451";
    const main = withAlpha(base, 0.45);
    const highlight = withAlpha(base, 0.3);
    monaco.editor.defineTheme(themeName, {
      base: "vs-dark",
      inherit: true,
      rules: [],
      colors: {
        "editor.selectionBackground": main,
        "editor.selectionHighlightBackground": highlight,
      },
    });
    editor.updateOptions({ theme: themeName });
  } catch (_) {
    // ignore theme sync errors
  }
}

async function fetchVisualBg() {
  try {
    const hl = await rpcCall("nvim_get_hl", [0, { name: "Visual", link: false }]);
    const bg = normalizeHlBg(hl);
    if (bg) return bg;
  } catch (_) {
    // ignore
  }
  try {
    const hl = await rpcCall("nvim_get_hl_by_name", ["Visual", true]);
    const bg = normalizeHlBg(hl);
    if (bg) return bg;
  } catch (_) {
    // ignore
  }
  return null;
}

function normalizeHlBg(hl) {
  if (!hl || typeof hl !== "object") return null;
  const num = hl.background ?? hl.bg;
  if (typeof num === "number" && num >= 0) {
    return toHex(num);
  }
  if (typeof num === "string" && num.startsWith("#")) return num;
  return null;
}

function toHex(n) {
  const v = Number(n >>> 0);
  return `#${v.toString(16).padStart(6, "0").slice(-6)}`;
}

function withAlpha(hex, alpha) {
  const clean = (hex || "").replace("#", "");
  if (clean.length !== 6) return hex;
  const a = Math.round(clamp(alpha, 0, 1) * 255);
  return `#${clean}${a.toString(16).padStart(2, "0")}`;
}

function byteIndexToCharIndex(text, byteIndex) {
  let totalBytes = 0;
  let charIndex = 0;
  const target = Math.max(0, Number(byteIndex) || 0);
  while (totalBytes < target) {
    if (charIndex >= text.length) {
      return charIndex + (target - totalBytes);
    }
    const code = text.codePointAt(charIndex);
    const bytes = utf8ByteLength(code);
    totalBytes += bytes;
    charIndex += bytes === 4 ? 2 : 1;
  }
  return charIndex;
}

function utf8ByteLength(point) {
  if (point == null) return 0;
  if (point <= 0x7f) return 1;
  if (point <= 0x7ff) return 2;
  if (point >= 0xd800 && point <= 0xdfff) return 4; // surrogate pair uses two UTF-16 code units
  if (point < 0xffff) return 3;
  return 4;
}

init();
