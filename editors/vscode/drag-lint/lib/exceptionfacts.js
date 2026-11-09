'use strict';

// Wave 149 LX (spec P1, docs\superpowers\specs\2026-11-07-editor-programme.md):
// the exception code lens click. The engine's lens 'raises N types, handles M types'
// carries the command draglint.exceptionFacts with [uri, line]; vscode-languageclient
// sends it as workspace/executeCommand and the server answers the routine's raise /
// handler sites:
//   [{uri, line, character, action, type, via, routine}]   (0-based positions)
// This module is the pure part (row -> quick pick item -> target); extension.js owns
// the middleware hook, the quick pick and the jump.

const COMMAND = 'draglint.exceptionFacts';

/**
 * @param {string} command an executeCommand id
 * @returns {boolean} true for the exception lens command
 */
function isExceptionFactsCommand(command) {
  return command === COMMAND;
}

/**
 * @param {unknown} rows the server's reply
 * @returns {{label: string, description: string, detail: string, row: object}[]} one item per
 *   well-formed row (a row needs a string uri and a numeric line), in the server's order
 */
function toPickItems(rows) {
  if (!Array.isArray(rows)) return [];
  const items = [];
  for (const r of rows) {
    if (!r || typeof r !== 'object' || typeof r.uri !== 'string' || typeof r.line !== 'number') continue;
    const action = typeof r.action === 'string' && r.action ? r.action : 'site';
    const label = r.type ? `${action} ${r.type}` : `${action} (bare except)`;
    const description = `line ${r.line + 1}` + (r.via ? ` (${r.via})` : '');
    items.push({ label, description, detail: typeof r.routine === 'string' ? r.routine : '', row: r });
  }
  return items;
}

/**
 * @param {{row: {uri: string, line: number, character?: number}}} item a toPickItems item
 * @returns {{uri: string, line: number, character: number}} the 0-based jump target
 */
function targetOf(item) {
  const r = item.row;
  return { uri: r.uri, line: r.line, character: typeof r.character === 'number' ? r.character : 0 };
}

/** @returns {string} the message shown when the server answers no sites */
function emptyMessage() {
  return 'drag-lint: no raise or handler sites for this routine.';
}

module.exports = { COMMAND, isExceptionFactsCommand, toPickItems, targetOf, emptyMessage };
