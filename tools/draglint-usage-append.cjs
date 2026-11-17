#!/usr/bin/env node
'use strict';
// draglint-usage-append.cjs -- the ONE validating writer for stats\draglint-usage.log (U1).
// Writes exactly: ISO8601 <TAB> what <TAB> units <TAB> avoided <TAB> tool <TAB> used <TAB> est_method <CRLF>
// Usage: node tools\draglint-usage-append.cjs --what "<text>" --units N --avoided N --tool grep|read|mcp --used N
//          [--method cons-v1] [--log <path>]
// Refuses (exit 2, nothing written): a non-numeric units/avoided/used, a tool outside grep|read|mcp
// (a numeric tool is the 2026-09-29 shifted-row bug). Tabs and newlines inside --what become spaces.
const fs = require('fs');
const path = require('path');

const TOOLS = ['grep', 'read', 'mcp'];

function arg(argv, name) {
  const i = argv.indexOf(name);
  return i >= 0 ? argv[i + 1] : undefined;
}

function main() {
  const argv = process.argv.slice(2);
  const log = arg(argv, '--log') || path.join(__dirname, '..', 'stats', 'draglint-usage.log');
  const what = String(arg(argv, '--what') || '').replace(/[\t\r\n]+/g, ' ').trim();
  const tool = String(arg(argv, '--tool') || '').trim().toLowerCase();
  const method = String(arg(argv, '--method') || 'cons-v1').replace(/[\t\r\n\s]+/g, '');
  const nums = {};
  const bad = [];
  for (const k of ['units', 'avoided', 'used']) {
    const v = arg(argv, '--' + k);
    if (v === undefined || !/^\d+$/.test(v)) bad.push('--' + k + ' must be a plain integer (got ' + JSON.stringify(v) + ')');
    else nums[k] = v;
  }
  if (!what) bad.push('--what is required');
  if (!TOOLS.includes(tool)) bad.push('--tool must be one of ' + TOOLS.join('|') + ' (got ' + JSON.stringify(tool) + ')');
  if (!method) bad.push('--method must not be empty');
  if (bad.length) {
    process.stderr.write('draglint-usage-append: refused, nothing written:\n  ' + bad.join('\n  ') + '\n');
    process.exit(2);
  }
  const ts = new Date().toISOString().replace(/\.\d+Z$/, 'Z');
  fs.appendFileSync(log, [ts, what, nums.units, nums.avoided, tool, nums.used, method].join('\t') + '\r\n');
}

main();
