'use strict';
// 1.6.8 VSCPROXY: argv of the server in plain and DelphiLSP-proxy mode; delphilsp.json loader.
const assert = require('assert');
const path = require('path');
const fs = require('fs');
const os = require('os');
const sa = require(path.join(__dirname, '..', 'lib', 'serverargs.js'));
const dl = require(path.join(__dirname, '..', 'lib', 'delphilsp.js'));

// plain mode (unchanged)
assert.deepStrictEqual(sa.buildArgs(['A.sqlite'], undefined), ['lsp', '--db', 'A.sqlite', '--full-rules']);
assert.deepStrictEqual(sa.buildArgs([], false), ['lsp']);
assert.deepStrictEqual(sa.buildArgs([], true, false), ['lsp', '--full-rules']);
assert.deepStrictEqual(sa.buildArgs([], true, 'true'), ['lsp', '--full-rules'], 'only boolean true enables proxy');
// proxy mode, default merge = all five
const all = ['--merge-diagnostics', '--merge-hover', '--merge-completion', '--merge-definition', '--merge-navigation'];
assert.deepStrictEqual(sa.buildArgs(['A.sqlite'], true, true), ['lsp', '--proxy', ...all, '--db', 'A.sqlite', '--full-rules']);
assert.deepStrictEqual(sa.buildArgs([], false, true, undefined), ['lsp', '--proxy', ...all]);
// explicit subset, unknown flags dropped (never reach the engine argv)
assert.deepStrictEqual(sa.buildArgs([], false, true, ['--merge-hover', '--bogus', '--merge-diagnostics']), ['lsp', '--proxy', '--merge-hover', '--merge-diagnostics']);
assert.deepStrictEqual(sa.buildArgs([], false, true, []), ['lsp', '--proxy'], 'empty array = plain relay');

// delphilsp.json
assert.strictEqual(dl.paramsFromText('not json'), null);
assert.strictEqual(dl.paramsFromText('{"x":1}'), null);
assert.deepStrictEqual(dl.paramsFromText('\uFEFF{"settings":{"project":"p"}}'), { settings: { project: 'p' } });
assert.strictEqual(dl.pick('', []), '');
assert.strictEqual(dl.pick('', ['a', 'b']), 'a');
assert.strictEqual(dl.pick(' c ', ['a']), 'c');
const f = path.join(os.tmpdir(), 'vscproxy-test.delphilsp.json');
fs.writeFileSync(f, '{"settings":{"project":"file:///x.dpr"}}');
assert.strictEqual(dl.loadParams(f).settings.project, 'file:///x.dpr');
fs.unlinkSync(f);
assert.strictEqual(dl.loadParams(f), null);
console.log('serverargs.test.js: ok');
