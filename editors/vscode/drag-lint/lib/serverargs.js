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
 * dragLint.delphiLsp (1.6.8, lane VSCPROXY) is OFF unless the user saved
 * `true`: then the argv starts `lsp --proxy` plus the merge flags of
 * dragLint.delphiLspMerge, so DelphiLSP's compiler diagnostics and hover appear
 * next to drag-lint's. --full-rules is still appended (the engine ignores it
 * with --proxy) so the argv stays one shape.
 *
 * @param {string[]} dbs  non-empty --db paths (already filtered by the caller)
 * @param {*} fullRules   the raw dragLint.fullRules value
 * @param {*} [delphiLsp] the raw dragLint.delphiLsp value (true = proxy mode)
 * @param {*} [merge]     the raw dragLint.delphiLspMerge value (array of flag names)
 * @returns {string[]}    e.g. ['lsp', '--db', 'X.sqlite', '--full-rules']
 */
const MERGE_FLAGS = [
  '--merge-diagnostics', '--merge-hover', '--merge-completion',
  '--merge-definition', '--merge-navigation'
];

function mergeFlags(merge) {
  if (!Array.isArray(merge)) return MERGE_FLAGS.slice();
  return merge.filter((f) => MERGE_FLAGS.indexOf(f) >= 0);
}

function buildArgs(dbs, fullRules, delphiLsp, merge) {
  const proxy = delphiLsp === true;
  const args = ['lsp'];
  if (proxy) args.push('--proxy', ...mergeFlags(merge));
  for (const db of dbs) args.push('--db', db);
  if (fullRules !== false) args.push('--full-rules');
  return args;
}

module.exports = { buildArgs, MERGE_FLAGS };
