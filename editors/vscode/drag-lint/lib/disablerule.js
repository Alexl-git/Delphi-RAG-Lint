'use strict';
// v152 BK-VSHOVER (B43, DISRULE H1): the "drag-lint: disable <rule> in this unit /
// project..." code action. The engine's codeAction carries
//   command drag-lint.disableRule, arguments [rule, scope, file, line(1-based)]
// (DRagLint.LSP.Completion); the extension asks for the reason and runs
//   drag-lint rules disable --rule R --scope S --in FILE [--project P] --reason "..." --json
// (docs\wiki\v152-disable-rule.md). Pure helpers, no vscode import.

const COMMAND = 'drag-lint.disableRule';
const SCOPES = ['line', 'unit', 'project'];

// The command's arguments as the engine sends them -> a request object, or null
// when they are not that shape.
function fromCommandArgs(args) {
  const a = Array.isArray(args) ? args : [];
  const [rule, scope, file, line] = a;
  if (typeof rule !== 'string' || rule === '' || !SCOPES.includes(scope) || typeof file !== 'string' || file === '') return null;
  return { rule, scope, file, line: Number.isInteger(line) ? line : parseInt(line, 10) || 0 };
}

// '' when the reason is acceptable, else the message to show. The engine requires
// one; for line scope it goes into the source file, which stays 7-bit ASCII.
function reasonProblem(reason, scope) {
  const r = String(reason == null ? '' : reason).trim();
  if (r === '') return 'A reason is required: say why the rule does not apply here.';
  if (scope === 'line' && /[^\x20-\x7e]/.test(r)) return 'Line scope writes the reason into the source file: use plain ASCII characters only.';
  return '';
}

// The engine argv. `project` (the .dproj the server reports as context) names the
// config for project scope; without it the engine uses the nearest
// drag-lint-lint.json above the file, as `lint` does.
function buildArgs(req) {
  const args = ['rules', 'disable', '--rule', req.rule, '--scope', req.scope, '--in', req.file];
  if (req.scope === 'line') args.push('--line', String(req.line));
  if (req.scope === 'project' && req.project) args.push('--project', req.project);
  args.push('--reason', String(req.reason).trim(), '--json');
  return args;
}

// The engine's answer -> {ok, message}. exit 0 = done, 1 = nothing to do (already
// disabled), 2 = refused / usage error. The --json object's `message` is shown when
// present; otherwise the raw output.
function describeResult(stdout, exitCode) {
  const text = String(stdout == null ? '' : stdout);
  let obj = null;
  const start = text.indexOf('{');
  const end = text.lastIndexOf('}');
  if (start >= 0 && end > start) {
    try { obj = JSON.parse(text.slice(start, end + 1)); } catch (e) { obj = null; }
  }
  const msg = obj && obj.message ? String(obj.message) : text.trim();
  if (exitCode === 0) return { ok: true, message: msg || 'Rule disabled.' };
  if (exitCode === 1) return { ok: true, message: msg || 'Nothing to do: the rule is already disabled there.' };
  return { ok: false, message: msg || ('drag-lint rules disable failed (exit ' + exitCode + ').') };
}

module.exports = { COMMAND, SCOPES, fromCommandArgs, reasonProblem, buildArgs, describeResult };
