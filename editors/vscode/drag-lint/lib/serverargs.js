'use strict';
/**
 * Builds the argv of the language server (after the exe). Kept free of the
 * `vscode` module so a plain node process can test it
 * (tests\autotest\run_vscode_extension_contract.ps1 does).
 *
 * dragLint.fullRules (owner ruling 2026-11-05) is ON unless the user saved
 * `false`: undefined / null / any non-false value means ON, so a profile that
 * never mentioned the setting gets the full rule set, and only an explicit
 * false gives the plain `lsp` of releases before 1.43.
 *
 * @param {string[]} dbs  non-empty --db paths (already filtered by the caller)
 * @param {*} fullRules   the raw dragLint.fullRules value
 * @returns {string[]}    e.g. ['lsp', '--db', 'X.sqlite', '--full-rules']
 */
function buildArgs(dbs, fullRules) {
  const args = ['lsp'];
  for (const db of dbs) args.push('--db', db);
  if (fullRules !== false) args.push('--full-rules');
  return args;
}

module.exports = { buildArgs };
