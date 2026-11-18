'use strict';
// 1.52 VSRESTART: a PLANNED stop (Restart Language Server / Update Engine Copy Now) must produce
// zero error-flood lines in the Output channel and must not spend the crash-restart budget.
const assert = require('assert');
const path = require('path');
const ps = require(path.join(__dirname, '..', 'lib', 'plannedstop.js'));

// The exact lines the owner pasted (2026-11-17 15:35:52) from the old server's stream teardown.
const FLOOD = [
  'Connection to server is erroring. write EOF',
  'Request textDocument/didOpen failed. Error: write EOF',
  'Cannot call write after a stream was destroyed',
  'Request textDocument/documentSymbol failed. Message: Cannot call write after a stream was destroyed (code -32099)',
  'Request workspace/didChangeConfiguration failed.',
  'Shutting down server.',
  'Server process exited with code 1.',
  'Server process exited with code 0.'
];
function mk() {
  const out = [];
  const real = { appendLine: (l) => out.push(l), append: (t) => out.push(t), dispose: () => out.push('REAL-DISPOSED') };
  const gate = ps.createGate();
  return { out, gate, ch: ps.wrapChannel(real, gate) };
}

// unplanned: every line passes through untouched (a real crash must stay visible)
{
  const m = mk();
  FLOOD.forEach((l) => m.ch.appendLine(l));
  assert.deepStrictEqual(m.out, FLOOD, 'unplanned lines pass through');
}
// planned: the flood is dropped, ONE summary line, exit-code line becomes "stopped for restart"
{
  const m = mk();
  m.gate.begin();
  FLOOD.forEach((l) => m.ch.appendLine(l));
  m.gate.end();
  m.ch.flush();
  const errish = m.out.filter((l) => /erroring|EOF|stream was destroyed|failed|exited with code/i.test(l));
  assert.strictEqual(errish.length, 0, 'planned restart: 0 error lines, got ' + JSON.stringify(errish));
  assert.ok(m.out.some((l) => /stopped for restart/i.test(l)), 'planned stop is logged as stopped for restart');
  assert.strictEqual(m.out.filter((l) => /stopped for restart/i.test(l)).length, 1, 'exactly one such line');
}
// an unrelated line during a planned stop still passes (the filter is not a black hole)
{
  const m = mk();
  m.gate.begin();
  m.ch.appendLine('some other diagnostic');
  m.gate.end();
  assert.ok(m.out.includes('some other diagnostic'));
}
// the channel must not be disposed by the client (it is shared across restarts)
{
  const m = mk();
  m.ch.dispose();
  assert.ok(!m.out.includes('REAL-DISPOSED'), 'wrapper dispose is a no-op');
}
// error handler: planned -> Continue on error, DoNotRestart on close, and the budget is untouched
{
  const calls = { closed: 0 };
  const inner = { error: () => ({ action: 'inner-error' }), closed: () => { calls.closed++; return { action: 'inner-closed' }; } };
  const gate = ps.createGate();
  const h = ps.wrapErrorHandler(inner, gate, { Continue: 1, DoNotRestart: 2 });
  assert.strictEqual(h.error(new Error('x'), undefined, 1).action, 'inner-error');
  assert.strictEqual(h.closed().action, 'inner-closed');
  gate.begin();
  assert.strictEqual(h.error(new Error('write EOF'), undefined, 9).action, 1);
  assert.strictEqual(h.closed().action, 2);
  assert.strictEqual(calls.closed, 1, 'planned close never reaches the crash budget');
}
console.log('plannedstop.test.js: all assertions passed');
