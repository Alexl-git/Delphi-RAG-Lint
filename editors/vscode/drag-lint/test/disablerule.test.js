'use strict';
// v152 BK-VSHOVER (B43): the disable-rule code action's pure half (lib\disablerule.js).
// The end-to-end half (this argv against the real engine) is run_v152_BK-VSHOVER E1.
const assert = require('assert');
const path = require('path');
const dr = require(path.join(__dirname, '..', 'lib', 'disablerule.js'));

// The command id the engine's code action carries (DRagLint.LSP.Completion).
assert.strictEqual(dr.COMMAND, 'drag-lint.disableRule');

// Arguments exactly as the engine sends them: [rule, scope, file, line].
assert.deepStrictEqual(dr.fromCommandArgs(['empty-except', 'unit', 'C:\\src\\u.pas', 18]),
  { rule: 'empty-except', scope: 'unit', file: 'C:\\src\\u.pas', line: 18 });
assert.strictEqual(dr.fromCommandArgs(['empty-except', 'machine', 'C:\\src\\u.pas', 18]), null);
assert.strictEqual(dr.fromCommandArgs([]), null);
assert.strictEqual(dr.fromCommandArgs(undefined), null);

// Reason rules.
assert.notStrictEqual(dr.reasonProblem('  ', 'unit'), '');
assert.strictEqual(dr.reasonProblem('legacy unit', 'unit'), '');
assert.strictEqual(dr.reasonProblem('caf\u00e9', 'project'), '');
assert.notStrictEqual(dr.reasonProblem('caf\u00e9', 'line'), '');

// The argv.
assert.deepStrictEqual(dr.buildArgs({ rule: 'empty-except', scope: 'unit', file: 'u.pas', line: 5, reason: ' why ' }),
  ['rules', 'disable', '--rule', 'empty-except', '--scope', 'unit', '--in', 'u.pas', '--reason', 'why', '--json']);
assert.deepStrictEqual(dr.buildArgs({ rule: 'r', scope: 'project', file: 'u.pas', line: 5, reason: 'x', project: 'C:\\p\\App.dproj' }),
  ['rules', 'disable', '--rule', 'r', '--scope', 'project', '--in', 'u.pas', '--project', 'C:\\p\\App.dproj', '--reason', 'x', '--json']);
assert.deepStrictEqual(dr.buildArgs({ rule: 'r', scope: 'line', file: 'u.pas', line: 5, reason: 'x' }),
  ['rules', 'disable', '--rule', 'r', '--scope', 'line', '--in', 'u.pas', '--line', '5', '--reason', 'x', '--json']);

// The engine's answer.
const done = '{"action":"disable","rule":"r","scope":"unit","config":"C:\\\\p\\\\drag-lint-lint.json","changed":true,"exit":0,"message":"r disabled for unit u"}';
assert.deepStrictEqual(dr.describeResult(done, 0), { ok: true, message: 'r disabled for unit u' });
assert.strictEqual(dr.describeResult('{"exit":1,"message":"already disabled"}', 1).ok, true);
assert.deepStrictEqual(dr.describeResult('error: --reason is required', 2), { ok: false, message: 'error: --reason is required' });
assert.strictEqual(dr.describeResult('', 2).ok, false);

console.log('disablerule.test.js: all assertions passed');
