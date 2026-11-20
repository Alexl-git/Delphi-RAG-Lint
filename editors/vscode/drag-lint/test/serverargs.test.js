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

// 1.6.9 config pick: skip tool/worktree dirs, prefer the json nearest the active file
{
  const R = path.join(os.tmpdir(), 'dlroot');
  const j = (...p) => path.join(R, ...p);
  assert.strictEqual(dl.isExcluded('.claude\\worktrees\\a\\x.delphilsp.json'), true);
  assert.strictEqual(dl.isExcluded('a\\node_modules\\x.json'), true);
  assert.strictEqual(dl.isExcluded('src/worktrees/x.json'), true);
  assert.strictEqual(dl.isExcluded('src\\delphi-plugin\\x.json'), false);
  const fake = { [j('src', 'cli')]: ['a.pas'], [j('src')]: ['b.delphilsp.json'], [j('src', 'plug')]: ['dcl.delphilsp.json'] };
  const ls = (d) => { if (!(d in fake)) throw new Error('nodir'); return fake[d]; };
  assert.strictEqual(dl.nearest(j('src', 'cli', 'a.pas'), R, ls), j('src', 'b.delphilsp.json'));
  assert.strictEqual(dl.nearest(j('src', 'plug', 'u.pas'), R, ls), j('src', 'plug', 'dcl.delphilsp.json'));
  assert.strictEqual(dl.nearest(j('other', 'u.pas'), R, ls), '');
  assert.strictEqual(dl.nearest(path.join(os.tmpdir(), 'elsewhere', 'u.pas'), R, ls), '');
  const found = [j('.claude', 'worktrees', 'agent-1', 'w.delphilsp.json'), j('src', 'plug', 'dcl.delphilsp.json')];
  assert.strictEqual(dl.pick('', found, '', R, ls), j('src', 'plug', 'dcl.delphilsp.json'), 'excluded skipped');
  assert.strictEqual(dl.pick('', found, j('src', 'cli', 'a.pas'), R, ls), j('src', 'b.delphilsp.json'), 'nearest wins');
  assert.strictEqual(dl.pick('C:\\x\\mine.json', found, j('src', 'cli', 'a.pas'), R, ls), 'C:\\x\\mine.json', 'explicit wins');
  assert.strictEqual(dl.pick('', [], '', R, ls), '');
  console.log('delphilsp config pick tests ok');
}
