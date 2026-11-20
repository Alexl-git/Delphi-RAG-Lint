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

/**
 * Picks the config file: an explicit setting wins, else the first candidate.
 * @param {string} configured  dragLint.delphiLspConfig ('' = auto)
 * @param {string[]} found     .delphilsp.json paths found in the workspace
 * @returns {string} path or ''
 */
function pick(configured, found) {
  if (typeof configured === 'string' && configured.trim() !== '') return configured.trim();
  return (found && found.length) ? found[0] : '';
}

const MISSING_WARNING = 'drag-lint: dragLint.delphiLsp is on but no *.delphilsp.json was found in the workspace. ' +
  'DelphiLSP stays silent without it. Open the project once in RAD Studio (it writes <Project>.delphilsp.json) ' +
  'or set dragLint.delphiLspConfig to its path.';

module.exports = { paramsFromText, loadParams, pick, MISSING_WARNING };
