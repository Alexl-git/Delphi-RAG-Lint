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
  return { text: 'DL: ' + parts.join(' | '), tooltip: tip || 'drag-lint context', warning: notice !== '' };
}

function initOptions(get) {
  return { project: get('project') || '', platform: get('platform') || '', config: get('config') || '' };
}

module.exports = { PLATFORMS, baseName, formatStatus, initOptions };
