'use strict';
// v153 SETTINGS-VSCODE: the "drag-lint: Project Settings..." command's pure half (lib\projectsettings.js).
// Spec docs\superpowers\specs\2026-11-20-settings-store-design.md sections 6 and 8. The end-to-end half
// (this argv against the real engine) is tests\autotest\run_v153_SETTINGS_VSCODE.ps1.
const assert = require('assert');
const path = require('path');
const ps = require(path.join(__dirname, '..', 'lib', 'projectsettings.js'));

// `settings list --json` as the engine prints it (DRagLint.CLI.Settings DoList): rows are under "settings".
const listJson = JSON.stringify({
  anchor: 'C:\p\App.dproj', projectFile: 'C:\p\_D-RAG\drag-lint-project.json', projectFileExists: false,
  localFile: 'C:\p\_D-RAG\drag-lint-project.local.json', localFileExists: false,
  settings: [
    { key: 'lint.profile', type: 'string', value: 'fast', source: 'local', default: '', local: true, settable: true, flag: '--profile', description: 'Lint profile' },
    { key: 'taint.envSource', type: 'bool', value: false, source: 'default', default: false, local: true, settable: true, flag: '', description: 'Env is a taint source' },
    { key: 'lint.paths', type: 'path[]', value: ['a', 'b'], source: 'project', default: [], local: false, settable: true, flag: '', description: 'Paths' },
    { key: 'popupForms', type: 'object[]', value: [], source: 'default', default: [], local: false, settable: false, flag: '', description: 'Popup forms' },
    { key: 'ai.apiToken', type: 'string', value: 'abc123', source: 'local', default: '', local: true, settable: true, flag: '', description: 'Token' }
  ],
  unknown: [], error: ''
});
const p = ps.parseList(listJson);
assert.strictEqual(p.error, '');
assert.strictEqual(p.anchor, 'C:\p\App.dproj');
assert.strictEqual(p.rows.length, 5);
assert.strictEqual(p.rows[0].key, 'lint.profile');
// A failure (non-JSON text, or the {"ok":false,"error":..} object) gives no rows and the message.
assert.deepStrictEqual(ps.parseList('  boom text \n'), { anchor: '', rows: [], error: 'boom text' });
const f = ps.parseList('{"ok":false,"error":"no project"}');
assert.strictEqual(f.rows.length, 0);
assert.strictEqual(f.error, 'no project');

// Labels.
assert.strictEqual(ps.rowLabel(p.rows[0]), 'lint.profile = "fast"');
assert.strictEqual(ps.sourceText(p.rows[0]), 'local');
assert.strictEqual(ps.sourceText(p.rows[1]), '(default)');
assert.ok(ps.rowLabel(p.rows[3]).endsWith('  (read-only)'));
// Secrets are masked in labels and never pre-filled.
assert.strictEqual(ps.rowLabel(p.rows[4]), 'ai.apiToken = "********"');
assert.strictEqual(ps.currentText(p.rows[4]), '');

// Choices.
assert.deepStrictEqual(ps.choicesFor(p.rows[1]), ['true', 'false', 'reset to default']);
assert.strictEqual(ps.choicesFor(p.rows[0]), null);
assert.strictEqual(ps.choicesFor(p.rows[2]), null);
assert.deepStrictEqual(ps.choicesFor(p.rows[3]), []);

// Input box seed.
assert.strictEqual(ps.currentText(p.rows[0]), 'fast');
assert.strictEqual(ps.currentText(p.rows[2]), 'a,b');

// Scope question only for settable rows that may live in the local file.
assert.strictEqual(ps.needsScopeQuestion(p.rows[0]), true);
assert.strictEqual(ps.needsScopeQuestion(p.rows[2]), false);
assert.strictEqual(ps.needsScopeQuestion(p.rows[3]), false);

// argv.
assert.deepStrictEqual(ps.buildSetArgs({ key: 'lint.profile', value: 'strict', local: false, project: 'C:\p\App.dproj' }),
  ['settings', 'set', 'lint.profile', 'strict', '--project', 'C:\p\App.dproj', '--json']);
assert.deepStrictEqual(ps.buildSetArgs({ key: 'lint.profile', value: 'strict', local: true, project: 'C:\p\App.dproj' }),
  ['settings', 'set', 'lint.profile', 'strict', '--project', 'C:\p\App.dproj', '--local', '--json']);
assert.deepStrictEqual(ps.buildUnsetArgs({ key: 'lint.profile', local: true, project: 'C:\p\App.dproj' }),
  ['settings', 'unset', 'lint.profile', '--project', 'C:\p\App.dproj', '--local', '--json']);
assert.deepStrictEqual(ps.buildUnsetArgs({ key: 'lint.profile', local: false, project: 'P.dproj' }),
  ['settings', 'unset', 'lint.profile', '--project', 'P.dproj', '--json']);

// Result mapping: 0 and 1 are fine (1 = nothing to do), 2 = refused.
assert.deepStrictEqual(ps.describeResult('{"ok":true,"message":"set k in f"}', 0), { ok: true, message: 'set k in f' });
assert.deepStrictEqual(ps.describeResult('{"ok":false,"message":"unset: k is not set in f"}', 1), { ok: true, message: 'unset: k is not set in f' });
assert.deepStrictEqual(ps.describeResult('plain text\n', 0), { ok: true, message: 'plain text' });
assert.deepStrictEqual(ps.describeResult('{"ok":false,"error":"bad value"}', 2), { ok: false, message: 'bad value' });
assert.deepStrictEqual(ps.describeResult('stderr words', 2), { ok: false, message: 'stderr words' });

// Which keys need a re-lint.
assert.strictEqual(ps.affectsLint('lint.profile'), true);
assert.strictEqual(ps.affectsLint('taint.envSource'), true);
assert.strictEqual(ps.affectsLint('popupForms'), false);

// Project resolution: the first candidate that names a .dproj.
assert.strictEqual(ps.projectFrom('C:\p\App.DPROJ', 'X.dproj'), 'C:\p\App.DPROJ');
assert.strictEqual(ps.projectFrom('C:\p\App.dpr', 'X.dproj'), 'X.dproj');
assert.strictEqual(ps.projectFrom(undefined, ''), '');

console.log('projectsettings.test.js: ok');
