'use strict';
// 1.52 VSTOAST: restart race (queue/drop traffic), stop timeout, double restart, exit code 0.
const assert = require('assert');
const path = require('path');
const fs = require('fs');
const rg = require(path.join(__dirname, '..', 'lib', 'restartguard.js'));
const ps = require(path.join(__dirname, '..', 'lib', 'plannedstop.js'));

(async () => {
  // 1. traffic is dropped while a planned stop or a start is in progress, passed otherwise
  {
    const gate = ps.createGate();
    const st = rg.createRestartState(gate);
    const sent = [];
    const next = (d) => { sent.push(d); return 'ok'; };
    assert.strictEqual(st.wrap((d, n) => n(d))('a', next), 'ok');
    gate.begin();
    assert.strictEqual(st.wrap((d, n) => n(d))('b', next), undefined, 'dropped during planned stop');
    gate.end();
    st.starting = true;
    assert.strictEqual(st.wrap((d, n) => n(d))('c', next), undefined, 'dropped while the new server initialises');
    st.starting = false;
    st.wrap((d, n) => n(d))('d', next);
    assert.deepStrictEqual(sent, ['a', 'd']);
  }
  // 1b. grace covers the stop timeout, and a new begin cancels the earlier grace timer
  {
    assert.ok(rg.graceMs(2000) >= 2000 + 3000, 'grace covers stop timeout + 3 s');
    const gate = ps.createGate();
    const timers = [];
    const sched = (f, ms) => { const t = { f, ms, cancelled: false }; timers.push(t); return t; };
    const cancel = (t) => { t.cancelled = true; };
    const sg = rg.createGraceGate(gate, sched, cancel);
    sg.open(); sg.closeLater(5000);
    sg.open(); // second restart inside the first grace
    assert.ok(timers[0].cancelled, 'first grace timer cancelled by the second open');
    assert.ok(gate.planned);
    sg.closeLater(5000);
    timers[1].f();
    assert.ok(!gate.planned);
  }
  // 2. stop timeout line is teardown noise (silent end of the old server), exit code 0 is info, not error
  {
    assert.ok(ps.isTeardownNoise('Stopping server timed out'));
    const out = [];
    const real = { appendLine: (l) => out.push(l) };
    const gate = ps.createGate();
    const ch = ps.wrapChannel(real, gate);
    ch.appendLine('Server process exited with code 0.');
    assert.ok(out.length === 1 && /^\[info\]/.test(out[0]) && !/error/i.test(out[0]), 'unplanned exit 0 logged at info: ' + out[0]);
    ch.appendLine('Server process exited with code 1.');
    assert.strictEqual(out[1], 'Server process exited with code 1.', 'non-zero stays visible');
  }
  // 3. coalesce: one publish = one restart
  {
    let n = 0; let t = 0;
    const f = rg.coalesce(async () => { n++; await new Promise((r) => setImmediate(r)); }, 10000, () => t);
    const a = f(); const b = f();
    await Promise.all([a, b]);
    assert.strictEqual(n, 1, 'concurrent calls share one run');
    t = 5000; await f();
    assert.strictEqual(n, 1, 'call inside the window is skipped');
    t = 20000; await f();
    assert.strictEqual(n, 2, 'call after the window runs');
  }
  // 4/5 static: extension.js wiring
  {
    const ext = fs.readFileSync(path.join(__dirname, '..', 'extension.js'), 'utf8');
    assert.ok(/old\.dispose\(\)/.test(ext), 'old client disposed after stop (showCallers duplicate)');
    assert.ok(/restartguard\.coalesce\(/.test(ext), 'updateEngineNow coalesced');
    assert.ok(/didOpen:\s*restartState\.wrap/.test(ext) && /didClose:\s*restartState\.wrap/.test(ext), 'didOpen/didClose guarded');
    assert.ok(/restartState\.starting = true/.test(ext), 'starting flag set');
    assert.ok(/RevealOutputChannelOn\.Never/.test(ext), 'no popups from the output channel');
    assert.ok(/stop\(STOP_TIMEOUT_MS\)/.test(ext), 'explicit stop timeout');
  }
  console.log('all assertions passed');
})().catch((e) => { console.error(e); process.exit(1); });
