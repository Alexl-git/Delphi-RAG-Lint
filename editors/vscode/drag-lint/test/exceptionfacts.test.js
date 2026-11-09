'use strict';
// Wave 149 LX (spec P1): the exception lens click. The server answers
// workspace/executeCommand draglint.exceptionFacts [uri, line] with the routine's
// raise / handler sites; the extension shows them in a quick pick that jumps to one.
const assert = require('assert');
const path = require('path');
const ef = require(path.join(__dirname, '..', 'lib', 'exceptionfacts.js'));

// The command id the engine's lens carries (DRagLint.LSP.Feature.CodeLens EXC_COMMAND).
assert.strictEqual(ef.COMMAND, 'draglint.exceptionFacts');
assert.strictEqual(ef.isExceptionFactsCommand('draglint.exceptionFacts'), true);
assert.strictEqual(ef.isExceptionFactsCommand('draglint.showCallers'), false);

// Rows exactly as the engine answers them (run_lsp_hover_exceptions_guard X2).
const rows = [
  { uri: 'file:///C:/p/uExc.pas', line: 30, character: 10, action: 'handles', type: 'EFoo', via: 'bound', routine: 'uExc.TWorker.Safe' },
  { uri: 'file:///C:/p/uExc.pas', line: 30, character: 18, action: 'reraises', type: 'EFoo', via: 'handler', routine: 'uExc.TWorker.Safe' },
  { uri: 'file:///C:/p/uExc.pas', line: 31, character: 7, action: 'handles-all', type: '', via: '', routine: 'uExc.TWorker.Safe' }
];
const items = ef.toPickItems(rows);
assert.strictEqual(items.length, 3);
// label: action + type; the line is shown 1-based, as the editor numbers it
assert.strictEqual(items[0].label, 'handles EFoo');
assert.strictEqual(items[0].description, 'line 31 (bound)');
assert.strictEqual(items[1].label, 'reraises EFoo');
assert.strictEqual(items[1].description, 'line 31 (handler)');
// a bare except has no type: say so instead of an empty label
assert.strictEqual(items[2].label, 'handles-all (bare except)');
assert.strictEqual(items[2].description, 'line 32');
assert.strictEqual(items[0].detail, 'uExc.TWorker.Safe');
// the target position stays 0-based (vscode.Position)
assert.deepStrictEqual(ef.targetOf(items[1]), { uri: 'file:///C:/p/uExc.pas', line: 30, character: 18 });

// tolerant input: null / non-array / junk rows give no items, never a throw
assert.deepStrictEqual(ef.toPickItems(null), []);
assert.deepStrictEqual(ef.toPickItems({}), []);
assert.deepStrictEqual(ef.toPickItems([null, 5, { line: 1 }]), []);
assert.strictEqual(ef.emptyMessage(), 'drag-lint: no raise or handler sites for this routine.');

console.log('exceptionfacts.test.js: all assertions passed');
