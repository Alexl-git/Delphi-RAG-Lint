/*
  gen-theme.js -- regenerate themes/delphi-ide.color-theme.json from the RAD
  Studio editor scheme in the registry.

    node scripts/gen-theme.js [--version 37.0] [--out <path>]

  The committed theme is generated on a machine with RAD Studio installed and
  ships in the .vsix so the extension works out of the box. A user with a
  different scheme re-runs it through the palette command
  "drag-lint: Generate Theme From RAD Studio Colours", which calls the same
  buildTheme() -- there is one code path, so the shipped theme and a regenerated
  one cannot drift apart in shape.

  This is NOT wired into `npm run package`. Packaging must not depend on a
  registry that only exists on a developer's box: a build elsewhere would either
  fail or, worse, quietly emit a colourless theme.
*/

'use strict';

const fs = require('fs');
const path = require('path');
const { readScheme, buildTheme, serializeJson } = require('../lib/radcolors');

function arg(name, fallback) {
  const i = process.argv.indexOf(`--${name}`);
  return i >= 0 && process.argv[i + 1] ? process.argv[i + 1] : fallback;
}

const version = arg('version', 'auto');
const out = path.resolve(arg('out', path.join(__dirname, '..', 'themes', 'delphi-ide.color-theme.json')));

const scheme = readScheme(version);
const theme = buildTheme(scheme);

fs.mkdirSync(path.dirname(out), { recursive: true });
fs.writeFileSync(out, serializeJson(theme), 'utf8');

const coloured = Object.values(scheme.elements).filter((e) => e.fg || e.bg).length;
console.log(`Read ${Object.keys(scheme.elements).length} element(s) (${coloured} coloured) from ${scheme.key}`);
console.log(`Wrote ${out}`);
console.log(`  background ${theme.colors['editor.background']}  type ${theme.type}  tokenColors ${theme.tokenColors.length}`);
