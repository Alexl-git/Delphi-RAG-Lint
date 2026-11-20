'use strict';
/**
 * DelphiLSP (the compiler language server behind `lsp --proxy`) learns its project
 * only from a `workspace/didChangeConfiguration` whose settings are the contents of
 * the IDE's `<Project>.delphilsp.json`. Without it DelphiLSP stays silent: no
 * diagnostics, hover answers null (measured headless 2026-11-20, lane VSCPROXY).
 * Free of the `vscode` module so plain node can test it.
 */
const fs = require('fs');

/**
 * @param {string} text  raw content of a .delphilsp.json file
 * @returns {object|null} the notification params ({settings: {...}}), or null when unusable
 */
function paramsFromText(text) {
  let j;
  try { j = JSON.parse(String(text).replace(/^\uFEFF/, '')); } catch (e) { return null; }
  if (!j || typeof j !== 'object' || !j.settings || typeof j.settings !== 'object') return null;
  return { settings: j.settings };
}

/**
 * @param {string} file  path of a .delphilsp.json
 * @returns {object|null} notification params, or null if unreadable / not a delphilsp file
 */
function loadParams(file) {
  try { return paramsFromText(fs.readFileSync(file, 'utf8')); } catch (e) { return null; }
}

const path = require('path');

const SKIP_SEGMENTS = ['.claude', 'node_modules', '.git', 'worktrees'];

/**
 * @param {string} p a file path
 * @returns {boolean} true when a segment is .claude, node_modules, .git or worktrees
 */
function isExcluded(p) {
  return String(p).split(/[\\/]+/).some((seg) => SKIP_SEGMENTS.includes(seg.toLowerCase()));
}

const isJson = (n) => /\.delphilsp\.json$/i.test(n);

/**
 * Nearest *.delphilsp.json walking up from the folder of activeFile, stopping at root.
 * @param {string} activeFile path of the active pascal file ('' = none)
 * @param {string} root       workspace root folder (the walk never leaves it)
 * @param {function(string):string[]} [listDir] directory lister (default fs.readdirSync)
 * @returns {string} json path or ''
 */
function nearest(activeFile, root, listDir) {
  if (!activeFile || !root) return '';
  const ls = listDir || ((d) => fs.readdirSync(d));
  const rel = path.relative(root, activeFile);
  if (rel.startsWith('..') || path.isAbsolute(rel)) return '';
  let dir = path.dirname(activeFile);
  for (;;) {
    let names = [];
    try { names = ls(dir); } catch (e) { names = []; }
    const hit = names.filter(isJson).sort()[0];
    if (hit) return path.join(dir, hit);
    if (path.resolve(dir).toLowerCase() === path.resolve(root).toLowerCase()) return '';
    const up = path.dirname(dir);
    if (up === dir) return '';
    dir = up;
  }
}

/**
 * Picks the config file: an explicit setting wins, then the json nearest the active
 * file, then the first non-excluded candidate.
 * @param {string} configured  dragLint.delphiLspConfig ('' = auto)
 * @param {string[]} found     .delphilsp.json paths found in the workspace
 * @param {string} [activeFile] active pascal file
 * @param {string} [root]       workspace root
 * @param {function(string):string[]} [listDir] directory lister (tests)
 * @returns {string} path or ''
 */
function pick(configured, found, activeFile, root, listDir) {
  if (typeof configured === 'string' && configured.trim() !== '') return configured.trim();
  const near = nearest(activeFile, root, listDir);
  if (near && !isExcluded(path.relative(root, near))) return near;
  const ok = (found || []).filter((f) => !isExcluded(root ? path.relative(root, f) : f));
  return ok.length ? ok[0] : '';
}

const MISSING_WARNING = 'drag-lint: dragLint.delphiLsp is on but no *.delphilsp.json was found in the workspace. ' +
  'DelphiLSP stays silent without it. Open the project once in RAD Studio (it writes <Project>.delphilsp.json) ' +
  'or set dragLint.delphiLspConfig to its path.';

module.exports = { paramsFromText, loadParams, pick, nearest, isExcluded, MISSING_WARNING };
