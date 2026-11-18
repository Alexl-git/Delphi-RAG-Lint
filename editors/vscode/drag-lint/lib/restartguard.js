'use strict';
// 1.52 VSTOAST. Pure helpers (no vscode dependency) for a planned restart of the language client:
//  * createRestartState: drops didOpen/didClose traffic while a planned stop or the new server's
//    start is in progress (the new client replays the open documents once initialised);
//  * graceMs / createGraceGate: the post-stop grace covers the stop timeout, and a second restart
//    inside the first one's grace cancels the first timer instead of being cut short by it;
//  * coalesce: one engine-copy publish = one restart.

const BASE_GRACE_MS = 3000;

function graceMs(stopTimeoutMs) { return stopTimeoutMs + BASE_GRACE_MS; }

function createRestartState(gate) {
  const state = {
    starting: false,
    shouldDrop() { return gate.planned || state.starting; },
    // Wraps a middleware (arg, next) so it is a no-op while traffic must not flow.
    wrap(fn) {
      return function (...args) {
        if (state.shouldDrop()) return undefined;
        return fn(...args);
      };
    }
  };
  return state;
}

function createGraceGate(gate, schedule, cancel) {
  let timer;
  return {
    open() {
      if (timer !== undefined) { cancel(timer); timer = undefined; }
      gate.begin();
    },
    closeLater(ms) {
      if (timer !== undefined) cancel(timer);
      timer = schedule(() => { timer = undefined; gate.end(); }, ms);
    }
  };
}

// A call while one runs shares it; a call within windowMs of the last start is skipped.
function coalesce(fn, windowMs, now) {
  const clock = now || Date.now;
  let running;
  let lastStart = -Infinity;
  return function (...args) {
    if (running) return running;
    if (clock() - lastStart < windowMs) return Promise.resolve();
    lastStart = clock();
    running = Promise.resolve(fn(...args)).finally(() => { running = undefined; });
    return running;
  };
}

module.exports = { createRestartState, createGraceGate, graceMs, coalesce };
