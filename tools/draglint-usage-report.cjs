#!/usr/bin/env node
'use strict';
// draglint-usage-report.js -- the ONLY source for published drag-lint token numbers
// (owner 2026-11-14, docs\INBOX-claude-mcp-integration-152.md section 2).
//
// Reads stats\draglint-usage.log (TSV) and prints, per tool and per month:
//   conservative avoided  (HEADLINE)  -- the counterfactual a careful reader would accept
//   used                              -- tokens drag-lint actually returned
//   as logged (inflated)              -- the raw claim, shown only for comparison
//
// Row shape (newest rule, global CLAUDE.md "Logs"):
//   ISO8601  what  units_needed  tokens_avoided  tool  tokens_used  est_method
// Older rows have 4 or 6 columns and no est_method.
//
// CONSERVATIVE METHOD (printed with every report):
//   * a row whose est_method starts with "cons-" was estimated conservatively when it was
//     written (grep = matched lines x 25 + one 200-line slice per unit needed; read = the
//     slice that would have been read) -- taken as logged, capped at 6000;
//   * every other (legacy) row is CAPPED: tool=read at 3000 tokens, anything else at 1500.
//
// Usage: node tools\draglint-usage-report.cjs [--log <path>] [--json]
// .cjs on purpose: a .js under the repo makes node read the nearest package.json for
// "type", and an empty one at the repo root aborts with ERR_INVALID_PACKAGE_CONFIG.

const fs = require('fs');
const path = require('path');

const CAP = { read: 3000, other: 1500, cons: 6000 };
const METHOD_LINE = 'method: conservative = rows marked est_method=cons-* as logged (<= ' + CAP.cons +
  '), every other row capped ' +
  '(read <= ' + CAP.read + ', grep/other <= ' + CAP.other + ' tokens per query); the raw log total is NOT a claim.';

function parseArgs(argv) {
  const a = { log: path.join(__dirname, '..', 'stats', 'draglint-usage.log'), json: false };
  for (let i = 0; i < argv.length; i++) {
    if (argv[i] === '--log') a.log = argv[++i];
    else if (argv[i] === '--json') a.json = true;
  }
  return a;
}

function num(s) { const n = Number(String(s || '').replace(/[,_]/g, '')); return Number.isFinite(n) ? n : null; }

function conservative(row) {
  if (/^cons-/.test(row.method)) return Math.min(row.claimed, CAP.cons);
  const cap = row.tool === 'read' ? CAP.read : CAP.other;
  return Math.min(row.claimed, cap);
}

// Class of a row the parser cannot use (U1). Order matters: most specific first.
function classify(line, c) {
  if (/^usage\s/i.test(line)) return 'prefixed';
  if (line.slice(1).search(/\d{4}-\d{2}-\d{2}T\d{2}:/) >= 0 && /^\d{4}-/.test(line)) return 'concatenated';
  if (!/^\d{4}-\d{2}/.test(line)) return 'split';
  if (c.length === 4 || c.length === 3) return '4-field';
  if (c.length > 7 || c.length < 3) return 'column-count';
  return 'non-numeric';
}

// A row written by hand as 'ts report <what> <units> <avoided> report <used>' has 'report' in
// BOTH col 2 and col 6, which shifts every column (the 2026-09-29 rows). Repair in memory only.
function unshift(c) {
  if (c.length === 7 && c[1] === 'report' && c[5] === 'report') return [c[0], c[2], c[3], c[4], c[5], c[6]];
  return null;
}

function blank() { return { rows: 0, claimed: 0, cons: 0, used: 0, pairedRows: 0, pairedCons: 0, pairedClaimed: 0 }; }

function add(b, r) {
  b.rows++; b.claimed += r.claimed; b.cons += r.cons;
  if (r.used !== null) { b.used += r.used; b.pairedRows++; b.pairedCons += r.cons; b.pairedClaimed += r.claimed; }
}

function main() {
  const args = parseArgs(process.argv.slice(2));
  const text = fs.readFileSync(args.log, 'utf8');
  const rows = [];
  let skipped = 0;
  let repaired = 0;
  const byClass = {};
  for (const line of text.split(/\r?\n/)) {
    if (!line.trim() || line.startsWith('#')) continue;
    let c = line.split('\t');
    const fixed = unshift(c);
    if (fixed) { c = fixed; repaired++; }
    const claimed = c.length >= 4 && c.length <= 7 ? num(c[3]) : null;
    if (claimed === null || !/^\d{4}-\d{2}/.test(c[0])) {
      skipped++;
      const k = classify(line, c);
      byClass[k] = (byClass[k] || 0) + 1;
      continue;
    }
    const tool = (c[4] || '').trim().toLowerCase() || 'unspecified';
    const used = c.length >= 6 ? num(c[5]) : null;
    const method = (c[6] || '').trim() || 'legacy';
    const r = { month: c[0].slice(0, 7), tool, claimed, used, method };
    r.cons = conservative(r);
    rows.push(r);
  }
  const total = blank();
  const byTool = {};
  const byMonth = {};
  for (const r of rows) {
    add(total, r);
    add(byTool[r.tool] = byTool[r.tool] || blank(), r);
    add(byMonth[r.month] = byMonth[r.month] || blank(), r);
  }
  if (args.json) {
    process.stdout.write(JSON.stringify({ method: METHOD_LINE, caps: CAP, skipped, skippedByClass: byClass, repaired, total, byTool, byMonth }, null, 2) + '\n');
    return;
  }
  const k = (n) => (n / 1000).toFixed(1).padStart(9) + 'k';
  const out = [];
  out.push('drag-lint usage -- CONSERVATIVE figures (' + args.log + ')');
  out.push(METHOD_LINE);
  out.push('');
  out.push('HEADLINE (rows that logged both sides, n=' + total.pairedRows + '): conservative avoided ' +
    k(total.pairedCons).trim() + ' vs used ' + k(total.used).trim() + ' -> net ' + k(total.pairedCons - total.used).trim());
  out.push('all rows (n=' + total.rows + '): conservative avoided ' + k(total.cons).trim() +
    '; as logged (inflated) ' + k(total.claimed).trim() + '; malformed rows skipped: ' + skipped +
    (skipped ? ' (' + Object.keys(byClass).sort().map((k) => k + '=' + byClass[k]).join(', ') + ')' : '') +
    '; shifted rows repaired: ' + repaired);
  const table = (title, obj) => {
    out.push('');
    out.push(title.padEnd(12) + '     rows   paired  cons.avoided          used     net(paired)  as-logged(inflated)');
    for (const key of Object.keys(obj).sort()) {
      const b = obj[key];
      out.push(key.padEnd(12) + String(b.rows).padStart(9) + String(b.pairedRows).padStart(9) +
        k(b.cons).padStart(14) + k(b.used).padStart(14) + k(b.pairedCons - b.used).padStart(16) + k(b.claimed).padStart(21));
    }
  };
  table('tool', byTool);
  table('month', byMonth);
  process.stdout.write(out.join('\n') + '\n');
}

main();
