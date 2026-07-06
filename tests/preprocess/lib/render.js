#!/usr/bin/env node
// Byte-exact oracle for PP-Task-4: runs the REAL tree-sitter-delphi13
// preprocess() function on a fixture and writes its resolved bytes to stdout
// VERBATIM (process.stdout.write of a UTF-8 Buffer -- no newline translation).
//
// Why not oracle.ps1 / cli.js? cli.js reads only the `defines` array from its
// --defines JSON and never forwards numericDefines to preprocess(), so the
// {$IF CompilerVersion >= 37} fixture cannot be evaluated numerically through
// it. This helper calls preprocess() directly with an explicit numericDefines
// map, exercising the exact code being ported (the evaluator's numeric path),
// which is the faithful comparison for the Pascal Preprocess().
//
// Usage: node render.js <fixture.pas> [--define SYM]... [--numeric K=V]...
// Node is a TEST-ONLY dependency; the shipped drag-lint exe never calls it.
'use strict';

const fs = require('fs');
const { preprocess } = require('C:/Projects/tree-sitter-delphi13/preprocessor/preprocess');

function main() {
  const args = process.argv.slice(2);
  let file = null;
  const defines = [];
  const numericDefines = {};
  for (let i = 0; i < args.length; i++) {
    const a = args[i];
    if (a === '--define') defines.push(String(args[++i]).toLowerCase());
    else if (a === '--numeric') {
      const kv = String(args[++i]);
      const eq = kv.indexOf('=');
      if (eq > 0) numericDefines[kv.slice(0, eq)] = parseInt(kv.slice(eq + 1), 10);
    } else if (!a.startsWith('--') && !file) file = a;
    else if (a.startsWith('--')) { process.stderr.write('unknown option: ' + a + '\n'); process.exit(2); }
  }
  if (!file) { process.stderr.write('no input file\n'); process.exit(2); }

  const source = fs.readFileSync(file, 'utf8');
  const result = preprocess(source, {
    defines,
    numericDefines,
    includeMode: 'defines-only',
    baseDir: require('path').dirname(file),
  });
  process.stdout.write(Buffer.from(result.text, 'utf8'));
}

main();
