'use strict';
const assert = require('assert');
const path = require('path');
const pkg = require(path.join(__dirname, '..', 'package.json'));
const ctx = require(path.join(__dirname, '..', 'lib', 'context.js'));

const props = pkg.contributes.configuration.properties;
assert.strictEqual(props['dragLint.project'].type, 'string');
assert.strictEqual(props['dragLint.project'].default, '');
assert.deepStrictEqual(props['dragLint.platform'].enum, ctx.PLATFORMS);
assert.strictEqual(props['dragLint.config'].default, '');
const cmds = pkg.contributes.commands.map((c) => c.command);
assert.ok(cmds.includes('dragLint.selectPlatform'));
assert.ok(cmds.includes('dragLint.selectProject'));

assert.strictEqual(ctx.formatStatus(undefined).text, 'DL: context unknown');
const a = ctx.formatStatus({ project: 'C:/x/App.dproj', platform: 'Win64', config: 'Debug', source: 'client', notice: '' });
assert.strictEqual(a.text, 'DL: App | Win64 | Debug');
assert.strictEqual(a.warning, false);
const b = ctx.formatStatus({ project: '', platform: '', config: '', source: 'unknown', notice: 'no project' });
assert.strictEqual(b.text, 'DL: no project | default platform');
assert.strictEqual(b.warning, true);
assert.ok(b.tooltip.includes('unknown') && b.tooltip.includes('no project'));
assert.deepStrictEqual(ctx.initOptions(() => undefined), { project: '', platform: '', config: '' });
console.log('context.test.js: all assertions passed');
