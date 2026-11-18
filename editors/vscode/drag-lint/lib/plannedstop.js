'use strict';
// 1.52 VSRESTART. A PLANNED stop of the language client ("Restart Language Server", "Update Engine
// Copy Now", a fullRules change) closes the old server's stdin on purpose. vscode-languageclient
// still has requests in flight (didOpen, documentSymbol, codeAction, inlayHint, semanticTokens ...)
// and logs each one as an error ("write EOF", "Cannot call write after a stream was destroyed"),
// then logs "Server process exited with code N" as an error. None of that is a fault: it is the
// stop we asked for. This module (pure, no vscode dependency, unit-tested in
// test/plannedstop.test.js) provides
//   * a gate that says "a planned stop is in progress";
//   * an Output-channel wrapper that, while the gate is open, drops the teardown lines and writes
//     ONE "Server stopped for restart" line when the gate closes;
//   * an error-handler wrapper that, while the gate is open, neither escalates nor counts the close
//     against the crash-restart budget (the caller restarts explicitly).
// Outside a planned stop everything passes through untouched, so a real crash stays visible.

const NOISE = [
  /connection to server is erroring/i,
  /\bwrite EOF\b/i,
  /cannot call write after a stream was destroyed/i,
  /^request \S+ failed/i,
  /^sending (request|notification) \S+ failed/i,
  /^shutting down server/i,
  /server process exited with code \d+/i,
  /stopping server timed out/i,
  /\(code -32099\)/
];

function isTeardownNoise(line) {
  const s = String(line).trim();
  return NOISE.some((re) => re.test(s));
}

function createGate() {
  const listeners = [];
  return {
    planned: false,
    begin() { this.planned = true; },
    end() {
      this.planned = false;
      listeners.forEach((f) => f());
    },
    onEnd(f) { listeners.push(f); }
  };
}

function wrapChannel(real, gate) {
  let suppressed = 0;
  let sawPlanned = false;
  const flush = () => {
    if (!sawPlanned) return;
    real.appendLine('Server stopped for restart (planned); ' + suppressed + ' teardown message(s) from the old connection suppressed.');
    suppressed = 0;
    sawPlanned = false;
  };
  gate.onEnd(flush);
  const emit = (line) => {
    if (gate.planned) sawPlanned = true;
    if (gate.planned && isTeardownNoise(line)) { suppressed++; return; }
    // A clean exit (code 0) is information, never an error, planned or not.
    if (/server process exited with code 0\b/i.test(String(line))) { real.appendLine('[info] ' + String(line).trim()); return; }
    real.appendLine(line);
  };
  const ch = {
    name: real.name,
    appendLine: emit,
    append: (t) => emit(t),
    replace: (t) => real.replace && real.replace(t),
    clear: () => real.clear && real.clear(),
    show: (...a) => real.show && real.show(...a),
    hide: () => real.hide && real.hide(),
    // LogOutputChannel level methods, in case the client calls them.
    trace: emit, debug: emit, info: emit, warn: emit, error: emit,
    // Shared across restarts: the client must not dispose it; the extension does, once.
    dispose() { /* no-op by design */ },
    flush
  };
  return ch;
}

function wrapErrorHandler(inner, gate, actions) {
  return {
    error(error, message, count) {
      if (gate.planned) return { action: actions.Continue };
      return inner.error(error, message, count);
    },
    closed() {
      if (gate.planned) return { action: actions.DoNotRestart };
      return inner.closed();
    }
  };
}

module.exports = { createGate, wrapChannel, wrapErrorHandler, isTeardownNoise };
