'use strict';
// Pure helpers for the project/platform context feature (no vscode import,
// so they are unit-testable with plain node).

const PLATFORMS = ['', 'Win32', 'Win64', 'Win64x', 'Linux64', 'OSX64', 'OSXARM64', 'Android', 'Android64', 'iOSDevice64', 'iOSSimARM64'];

// File base name without extension, for either path separator.
function baseName(p) {
  const s = String(p || '').split(/[\/]/).pop() || '';
  const i = s.indexOf('.');
  return i > 0 ? s.slice(0, i) : s;
}

// ctx = {project, platform, config, source, notice} from 'draglint/context',
// or undefined if the server never sent one.
function formatStatus(ctx) {
  if (!ctx || typeof ctx !== 'object') {
    return { text: 'DL: context unknown', tooltip: 'drag-lint: no context reported by the server', warning: false };
  }
  const parts = [ctx.project ? baseName(ctx.project) : 'no project'];
  parts.push(ctx.platform || 'default platform');
  if (ctx.config) parts.push(ctx.config);
  const notice = ctx.notice ? String(ctx.notice) : '';
  const tip = [ctx.source ? 'source: ' + ctx.source : '', notice].filter(Boolean).join('\n');
  return { text: 'DL: ' + parts.join(' | '), tooltip: tip || 'drag-lint context', warning: notice !== '' && ctx.level !== 'info' };
}

function initOptions(get) {
  return { project: get('project') || '', platform: get('platform') || '', config: get('config') || '' };
}

// Language ids of files that can belong to a Delphi project. The status item is
// shown only for these; on a .md / .json the server finds no owning project and
// the item would read 'no project | default platform' for no reason.
const DELPHI_LANGUAGES = ['pascal', 'objectpascal', 'delphi', 'dfm', 'delphi-project'];

function isDelphiLanguage(id) {
  return DELPHI_LANGUAGES.includes(String(id || '').toLowerCase());
}

module.exports = { PLATFORMS, baseName, formatStatus, initOptions, isDelphiLanguage };
