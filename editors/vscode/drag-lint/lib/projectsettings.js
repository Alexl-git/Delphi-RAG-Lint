'use strict';
// v153 SETTINGS-VSCODE: the "drag-lint: Project Settings..." command. It is a thin UI over the
// engine's `settings list|set|unset --json` verb (docs\superpowers\specs\2026-11-20-settings-store-design.md
// sections 6 and 8; DRagLint.CLI.Settings): the extension never reads or writes the settings files itself.
// Pure helpers, no vscode import.

const MASK = '********';
const SECRET_KEY = /(secret|token|password|passwd|apikey|api-key)/i;
const RESET = 'reset to default';

function isSecret(row) { return SECRET_KEY.test(String(row && row.key)); }

// `settings list --json` stdout -> {anchor, rows, error}. The rows are the engine's "settings" array.
// Anything that is not that object (a usage text, {"ok":false,"error":..}) gives rows [] and the message.
function parseList(stdout) {
  const text = String(stdout == null ? '' : stdout).trim();
  let o = null;
  try { o = JSON.parse(text); } catch (e) { o = null; }
  if (o && typeof o === 'object' && Array.isArray(o.settings)) {
    return { anchor: String(o.anchor || ''), rows: o.settings, error: String(o.error || '') };
  }
  if (o && typeof o === 'object' && (o.error || o.message)) return { anchor: '', rows: [], error: String(o.error || o.message) };
  return { anchor: '', rows: [], error: text || 'no output from the engine' };
}

function sourceText(row) { return row.source === 'default' ? '(default)' : String(row.source); }

// 'key = value' for the picker; a secret value is masked, a non-settable row says so.
function rowLabel(row) {
  const shown = isSecret(row) ? JSON.stringify(MASK) : JSON.stringify(row.value);
  return row.key + ' = ' + shown + (row.settable ? '' : '  (read-only)');
}

// The pick list for a value, or null when the user types it (input box); [] = not editable here.
function choicesFor(row) {
  if (!row.settable) return [];
  if (row.type === 'bool') return ['true', 'false', RESET];
  if (row.type === 'string' || row.type === 'path' || row.type === 'path[]') return null;
  return [];
}

// The input box seed: unquoted string, comma-joined list; never a secret.
function currentText(row) {
  if (isSecret(row)) return '';
  const v = row.value;
  if (Array.isArray(v)) return v.join(',');
  if (v === null || v === undefined) return '';
  return String(v);
}

function needsScopeQuestion(row) { return row.local === true && row.settable === true; }

function buildSetArgs(o) {
  const a = ['settings', 'set', o.key, o.value, '--project', o.project];
  if (o.local) a.push('--local');
  a.push('--json');
  return a;
}

function buildUnsetArgs(o) {
  const a = ['settings', 'unset', o.key, '--project', o.project];
  if (o.local) a.push('--local');
  a.push('--json');
  return a;
}

// Exit 0 done, 1 nothing to do (both fine), 2 refused.
function describeResult(stdout, code) {
  const text = String(stdout == null ? '' : stdout).trim();
  let o = null;
  try { o = JSON.parse(text); } catch (e) { o = null; }
  const msg = (o && typeof o === 'object' && (o.error || o.message)) ? String(o.error || o.message) : text;
  return { ok: code === 0 || code === 1, message: msg };
}

function affectsLint(key) { return /^(lint|taint)\./.test(String(key)); }

function projectFrom(ctxProject, configured) {
  for (const c of [ctxProject, configured]) {
    if (typeof c === 'string' && /\.dproj$/i.test(c)) return c;
  }
  return '';
}

module.exports = { RESET, parseList, sourceText, rowLabel, choicesFor, currentText, needsScopeQuestion,
  buildSetArgs, buildUnsetArgs, describeResult, affectsLint, projectFrom };
