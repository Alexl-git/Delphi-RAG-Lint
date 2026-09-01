'use strict';

// Package the drag-lint VS Code extension into a .vsix.
//
// This exists because nothing did. The repo carried extension v1.4.0 while the
// machine had v1.2.2 installed, so the private-engine-copy fix -- the whole
// point of 1.4.0 -- never reached the editor. Two versions of drift with no
// build step is exactly how that happens silently.
//
//   npm install && npm run package
//
// Output: <repo root>\dist\drag-lint-<version>.vsix

const fs = require('fs');
const path = require('path');
const { spawnSync } = require('child_process');

const extDir = path.resolve(__dirname, '..');
const repoRoot = path.resolve(extDir, '..', '..', '..');
const distDir = path.join(repoRoot, 'dist');

function fail(msg) {
  console.error('package.js: ' + msg);
  process.exit(1);
}

// The manifest says "SEE LICENSE IN LICENSE", so vsce requires the file to be
// present here. Refresh it from the repo root every time rather than letting a
// tracked copy drift.
const rootLicense = path.join(repoRoot, 'LICENSE');
if (!fs.existsSync(rootLicense)) fail('no LICENSE at the repo root: ' + rootLicense);
fs.copyFileSync(rootLicense, path.join(extDir, 'LICENSE'));

const manifest = JSON.parse(fs.readFileSync(path.join(extDir, 'package.json'), 'utf8'));
const version = manifest.version;
if (!version) fail('package.json has no version');

fs.mkdirSync(distDir, { recursive: true });
const out = path.join(distDir, 'drag-lint-' + version + '.vsix');

// Run vsce's JS entry point under this node, not the .bin\vsce.cmd shim:
// spawning a .cmd needs shell:true, and shell:true with args is DEP0190.
const vsce = path.join(extDir, 'node_modules', '@vscode', 'vsce', 'vsce');
if (!fs.existsSync(vsce)) fail('vsce not found -- run "npm install" first (it is a devDependency)');

console.log('packaging drag-lint ' + version + ' -> ' + out);

const r = spawnSync(process.execPath, [vsce, 'package', '--out', out], {
  cwd: extDir,
  stdio: 'inherit',
});

if (r.status !== 0) fail('vsce exited with ' + r.status);

const size = fs.statSync(out).size;
console.log('');
console.log('OK  ' + out + '  (' + size + ' bytes)');
console.log('install with:  code --install-extension "' + out + '"');
