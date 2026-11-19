'use strict';
// v152 BK-VSHOVER (B32): the deferred hover's pure half (lib\deferredhover.js).
const assert = require('assert');
const path = require('path');
const dh = require(path.join(__dirname, '..', 'lib', 'deferredhover.js'));

// Same text as the engine (the runner pins it against DRagLint.LSP.Deferred.pas).
assert.strictEqual(dh.DEFER_METHOD, 'draglint/deferHover');
assert.strictEqual(dh.PLACEHOLDER, 'computing...');

// Shapes exactly as the engine answers them (run_v152_BK-VSHOVER V1 / V2):
// CRLF inside the body, LF in the context footer.
const footer = '\n\n---\n\ncontext: none -- Win64 [default]';
const fast = '**Target** `method`\r\n\r\n- `u.TWorker.Target` - line 8\r\n    procedure Target\r\n\r\n**Analysis facts:**\r\n- computing...\r\n' + footer;
const whole = '**Target** `method`\r\n\r\n- `u.TWorker.Target` - line 8\r\n    procedure Target\r\n\r\n**Analysis facts:**\r\n- Called from: u.TWorker.CallerA, u.TWorker.CallerB\r\n- Effect-free: yes\r\n' + footer;

assert.strictEqual(dh.isPartial(fast), true);
assert.strictEqual(dh.isPartial(whole), false);
assert.strictEqual(dh.isPartial(''), false);
// The placeholder must be a line of its own; a word inside a sentence is not one.
assert.strictEqual(dh.isPartial('still computing... the answer'), false);

// The fast part drops the placeholder AND its now-empty heading; keeps the footer.
const shown = dh.fastPart(fast);
assert.ok(!shown.includes('computing...'));
assert.ok(!shown.includes('Analysis facts'));
assert.ok(shown.includes('procedure Target'));
assert.ok(shown.includes('context: none'));
// A heading that still has rows under it stays.
const mixed = '**Analysis facts:**\n- Complexity: 3\n- computing...\n';
assert.strictEqual(dh.fastPart(mixed), '**Analysis facts:**\n- Complexity: 3\n');
// No placeholder: unchanged apart from line ends.
assert.strictEqual(dh.fastPart('a\r\nb'), 'a\nb');

// The companion part: what the whole answer adds, heading included, footer not repeated.
assert.strictEqual(dh.remainder(shown, whole),
  '**Analysis facts:**\n- Called from: u.TWorker.CallerA, u.TWorker.CallerB\n- Effect-free: yes');
assert.strictEqual(dh.remainder(dh.fastPart(mixed), '**Analysis facts:**\n- Complexity: 3\n- Set by: W1 (u.pas:5, assign)\n'),
  '- Set by: W1 (u.pas:5, assign)');
// Nothing new -> '' (the companion then shows nothing).
assert.strictEqual(dh.remainder(whole, whole), '');

// hoverText over the shapes a provider can return.
assert.strictEqual(dh.hoverText({ contents: { kind: 'markdown', value: 'x' } }), 'x');
assert.strictEqual(dh.hoverText({ contents: [{ value: 'a' }, 'b'] }), 'a\n\nb');
assert.strictEqual(dh.hoverText(null), '');

assert.strictEqual(dh.key('file:///a.pas', 3, 7), 'file:///a.pas#3:7');

// The slot: the companion waits for the middleware's first step; a newer position
// releases an older waiter with null; nothing settles -> null after the timeout.
(async () => {
  const slot = dh.createSlot();
  slot.reset('k1');
  const w1 = slot.wait('k1', 1000);
  slot.settle('k1', { partial: true, shown: 'S' });
  assert.deepStrictEqual(await w1, { partial: true, shown: 'S' });

  slot.reset('k2');
  const w2 = slot.wait('k2', 1000);
  slot.reset('k3');
  assert.strictEqual(await w2, null);

  const w3 = slot.wait('k3', 30);
  assert.strictEqual(await w3, null);

  // A cancelled hover gets null even when the first step arrives.
  slot.reset('k4');
  const w4 = slot.wait('k4', 1000, () => true);
  slot.settle('k4', { partial: true, shown: 'S' });
  assert.strictEqual(await w4, null);

  // A re-hover at the SAME position starts a fresh pair (no stale settled value).
  slot.reset('k4');
  const w5 = slot.wait('k4', 30);
  assert.strictEqual(await w5, null);

  console.log('deferredhover.test.js: all assertions passed');
})().catch((e) => { console.error(e); process.exit(1); });
