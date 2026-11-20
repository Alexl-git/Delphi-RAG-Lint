'use strict';
// v152 BK-VSHOVER (B32): the deferred ("fast, then complete") hover for VS Code.
// Pure helpers, no vscode import, so they are unit-testable with plain node.
//
// Protocol (engine 1.52, docs\superpowers\specs\2026-11-18-deferred-answers-design.md):
//   1. notification draglint/deferHover {textDocument, position}
//   2. textDocument/hover at that position -> FAST markdown; the slow fact lines are
//      replaced by one bullet carrying PLACEHOLDER.
//   3. textDocument/hover at the same position again -> the WHOLE markdown,
//      cancellable ($/cancelRequest -> RequestCancelled).
// An engine before 1.52 ignores the notification and answers step 2 whole (no
// placeholder), so isPartial() is false and no second request is sent.
//
// VS Code cannot edit a hover that is already shown, but it renders each hover
// PROVIDER's part as soon as that provider resolves. So the LSP provider shows the
// fast part at once and a companion provider adds the rest: remainder() = the lines
// of the whole markdown that the fast part does not already show.

// Must equal DRagLint.LSP.Deferred DEFER_HOVER_METHOD / DEFERRED_PLACEHOLDER
// (pinned by tests\autotest\run_v152_BK-VSHOVER.ps1 W1).
const DEFER_METHOD = 'draglint/deferHover';
const PLACEHOLDER = 'computing...';
// 1.52.2 PROXYMERGE: the placeholder `drag-lint lsp --proxy` puts after DelphiLSP's hover
// (behind a '---' rule) when drag-lint's part is past its budget; must equal
// DRagLint.LSP.Proxy.Merge HOVER_PLACEHOLDER without its _emphasis_.
const PROXY_PLACEHOLDER = 'drag-lint: analysing...';

// How long the companion waits for the fast step before giving up (ms).
const FIRST_STEP_WAIT_MS = 15000;

function key(uri, line, character) {
  return String(uri) + '#' + line + ':' + character;
}

function splitLines(text) {
  return String(text == null ? '' : text).replace(/\r\n?/g, '\n').split('\n');
}

function isPlaceholderLine(line) {
  const t = line.trim().replace(/^[-*]\s+/, '').replace(/^_(.*)_$/, '$1');
  return t === PLACEHOLDER || t === PROXY_PLACEHOLDER;
}

function isPartial(text) {
  return splitLines(text).some(isPlaceholderLine);
}

function isHeading(line) {
  const t = line.trim();
  return /^\*\*[^*]+:\*\*$/.test(t) || /^_[^_]+:_$/.test(t);
}

// The fast markdown as shown: the placeholder line removed, and a section heading
// left with nothing under it removed too (the companion's part brings it back with
// its rows). Text without a placeholder is returned unchanged (line ends normalised).
function fastPart(text) {
  const lines = splitLines(text);
  const out = [];
  for (let i = 0; i < lines.length; i++) {
    if (!isPlaceholderLine(lines[i])) { out.push(lines[i]); continue; }
    const next = i + 1 < lines.length ? lines[i + 1].trim() : '';
    let j = out.length - 1;
    while (j >= 0 && out[j].trim() === '') j--;
    if (next === '' && j >= 0 && isHeading(out[j])) out.splice(j);
    // the proxy's placeholder sits behind a '---' rule: drop the rule left dangling
    else if (next === '' && j >= 0 && out[j].trim() === '---') out.splice(j);
  }
  return out.join('\n');
}

function trimBlankEnds(lines) {
  let a = 0;
  let b = lines.length;
  while (a < b && lines[a].trim() === '') a++;
  while (b > a && lines[b - 1].trim() === '') b--;
  return lines.slice(a, b);
}

// The lines of `full` not in the longest common subsequence with `shown`, in order.
// '' when the whole answer adds nothing.
function remainder(shown, full) {
  const s = splitLines(shown);
  const f = splitLines(full);
  const n = s.length;
  const m = f.length;
  const lcs = Array.from({ length: n + 1 }, () => new Array(m + 1).fill(0));
  for (let i = n - 1; i >= 0; i--) {
    for (let j = m - 1; j >= 0; j--) {
      lcs[i][j] = s[i] === f[j] ? lcs[i + 1][j + 1] + 1 : Math.max(lcs[i + 1][j], lcs[i][j + 1]);
    }
  }
  const extra = [];
  let i = 0;
  let j = 0;
  while (j < m) {
    if (i < n && s[i] === f[j]) { i++; j++; } else if (i < n && lcs[i + 1][j] >= lcs[i][j + 1]) { i++; } else { extra.push(f[j]); j++; }
  }
  return trimBlankEnds(extra).join('\n');
}

// The markdown text of a vscode.Hover / LSP Hover (contents: MarkupContent,
// MarkdownString, string or an array of those).
function hoverText(hover) {
  if (!hover) return '';
  const c = hover.contents;
  const one = (x) => (x == null ? '' : typeof x === 'string' ? x : String(x.value == null ? '' : x.value));
  return Array.isArray(c) ? c.map(one).join('\n\n') : one(c);
}

// One slot, like the server's: the newest hovered position supersedes older ones.
// The LSP middleware settles the slot with the first step's outcome; the companion
// waits on it. A waiter of a superseded position gets null.
function createSlot() {
  let cur = null;
  function entry(k) {
    if (!cur || cur.key !== k) {
      if (cur) cur.resolve(null);
      let resolve;
      const promise = new Promise((r) => { resolve = r; });
      cur = { key: k, promise, resolve, settled: false };
    }
    return cur;
  }
  return {
    settle(k, value) {
      const e = entry(k);
      if (e.settled) return;
      e.settled = true;
      e.resolve(value);
    },
    wait(k, ms, isCancelled) {
      const e = entry(k);
      return new Promise((resolve) => {
        const timer = setTimeout(() => resolve(null), ms);
        e.promise.then((v) => { clearTimeout(timer); resolve(isCancelled && isCancelled() ? null : v); });
      });
    },
    // A new hover at the same position starts a fresh pair.
    reset(k) { if (cur && cur.key === k) { cur.resolve(null); cur = null; } entry(k); }
  };
}

module.exports = { DEFER_METHOD, PLACEHOLDER, PROXY_PLACEHOLDER, FIRST_STEP_WAIT_MS, key, isPartial, fastPart, remainder, hoverText, createSlot };
