---
title: "AutoFix Chunk 2: Widen the fixable-rule set (+6) + risky-fix tag + batch-gating test/doc + 2 Minors"
date: 2026-07-05
status: approved
author: Claude
supersedes-scope-note: >
  Chunk 1 (v0.88.0-alpha, spec 2026-07-05-autofix-chunk1-fix-it-design.md) built the
  full "Fix it" vertical slice on the 3 existing fixable rules. Chunk 2 WIDENS that set
  and closes the small deferred items. No new CLI verbs, no IDE code, no schema change.
revision-note: >
  Revised after the exhaustive 163-rule fixability sweep (2026-07-05) verified the full
  safe set. Scope grew from 3 to 6 new fixable rules (user decision): the original 3 plus
  reserved-word-casing, redundant-assigned-free, and off-by-one-count. off-by-one-count is
  the only BEHAVIOUR-CHANGING fix, so this revision adds a "risky" tag mechanism to contain
  it (confirmation-preview approach: tagged risky:true in the fix JSON/message; Fix-it and
  Fix-all both apply it, no batch exclusion). nil-comparison remains dropped.
---

# AutoFix Chunk 2 -- Widen the fixable-rule set

## Summary

Chunk 1 proved the AutoFix vertical slice (CLI fix verbs + IDE "Fix it"/"Fix all" menu +
per-rule auto-fix checkbox + `fixable` catalog flag) on 3 rules: `self-assignment`,
`redundant-parentheses`, `redundant-cast`. Everything downstream keys off a single
registry (`FIXABLE_RULE_IDS` in `src/cli/DRagLint.CLI.pas`), so widening the fixable set
is deliberately cheap: each new rule = one `FIXABLE_RULE_IDS` entry + one branch in
`BuildAutofixEdits` + one fixture. The catalog flag, "Fix it" menu item, and auto-fix
checkbox all light up automatically.

Chunk 2 makes **6 more rules fixable** (taking the total from 3 to 9), adds a **risky-fix
tag** to contain the one behaviour-changing rule, locks and documents the already-correct
batch-gating behaviour (the user's original lead item), and closes 2 deferred final-review
Minors. It ships as release **v0.89.0-alpha**.

The **exhaustive 163-rule fixability sweep** (2026-07-05) confirmed the mechanically-safe
frontier is small (**9 total fixable of 163**; the other 153 are report-only detectors that
need type/flow/rename/restructure). Chunk 2 now includes ALL of the sweep's verified finds,
so there is no separate widening left for a Chunk 3 (Chunk 3 becomes the next Track-1 item,
e.g. the FAutoFix save-time auto-apply control, not more rule-widening).

## Background: how a fix is built

`BuildAutofixEdits` (`src/cli/DRagLint.CLI.pas:4489`) consumes findings and emits
`TTextEdit`s. Only two edit kinds exist:

- `tekDeleteLines` -- delete whole source line(s) `StartLine..EndLine`.
- `tekReplaceInLine` -- on ONE line, replace `[StartCol, EndCol)` with a computed string.

A rule is **mechanically fixable** iff the correct fix is a single deterministic edit of
one of those kinds, computable from the finding's span + that line's text ALONE -- no type
resolution, no cross-line/flow reasoning, no rename, no multi-line restructure. A fix may be
**behaviour-preserving** (rewrites redundant code to an equivalent) or, in ONE case
(`off-by-one-count`), **behaviour-changing** (assumes the flagged code is a bug and alters
runtime semantics) -- the latter is tagged `risky` (see the Design section).

Finding spans come from two engines:

- **`.scm` (declarative) rules**: span = the `@warn`-captured node's full
  `StartPoint..EndPoint` (`src/lint/DRagLint.Lint.QueryRules.pas:306-309`). The
  `rules/<id>.scm` file decides what `@warn` covers. For the redundant-* rules here, `@warn`
  is on the whole offending expression node, so the span bounds exactly the text to rewrite;
  for `off-by-one-count` it is on the loop end-bound only, and for `redundant-assigned-free`
  on the whole single-line `if` statement including its trailing `;`.
- **Pascal-emitted rules**: span set at a `src/diagnostics/*.pas` emission site (often via
  an `EmitAt` helper: `EndCol := StartCol + Length(Trim(NodeStr(node)))`). `reserved-word-casing`
  (NamingChecks.pas:463) uses `EmitAt` on the keyword token -> span = the keyword text.

## Scope

### In scope

1. Make 6 rules fixable (behaviour-PRESERVING unless noted):
   - `redundant-not-not`  (`.scm`, dead-code) -- `not not X` -> `X`.
   - `redundant-as-tobject` (`.scm`, dead-code) -- `X as TObject` -> `X`.
   - `boolean-comparison-true` (`.scm`, dead-code) -- `=True`/`<>False` -> `X`;
     `=False`/`<>True` -> `not X` (compound-operand paren guard).
   - `reserved-word-casing` (Pascal, naming) -- LowerCase the keyword token.
   - `redundant-assigned-free` (`.scm`, resource-lifetime) -- `if Assigned(X) then X.Free;`
     -> `X.Free;` (single-line + delimited-`then` guards).
   - `off-by-one-count` (`.scm`, bug-patterns) -- append ` - 1` to the loop end-bound.
     **BEHAVIOUR-CHANGING** -> tagged `risky` (see 2).
2. **Risky-fix tag:** a registry of behaviour-changing rule-ids (`RISKY_FIX_RULE_IDS`,
   currently just `off-by-one-count`) + a `risky` boolean in the `--fix --json` output and a
   note in the text/dry-run output. Containment = **confirmation-preview**: `Fix it` and
   `Fix all` BOTH apply it (no batch exclusion), but the JSON/message flags `risky:true` so a
   human or AI orchestrator sees the warning before/when applying. `IsFixableRule` still
   returns true for it (Fix-it works); `IsRiskyFixRule(id)` is the new predicate.
3. Batch-gating regression test + documentation (already-correct behaviour, never tested).
4. Minor 1: `applied` accounting for no-edit findings.
5. Minor 2: `--fix --format sarif` stderr note.
6. Publish v0.89.0-alpha.

### Explicitly NOT in scope

- `nil-comparison` -- its `X <> nil -> Assigned(X)` swap has an **undetectable** behaviour
  edge for procedure-of-object / method-pointer references (per the rule's own `.scm`
  comment: `<> nil` checks only the code pointer; `Assigned` checks both). We cannot tell
  X's type from text alone, so the swap is not strictly side-effect-free. Not in the sweep's
  verified set. **Dropped.**
- Any new CLI verb, IDE code, or index-schema change (all inherited from Chunk 1).
- `boolean-result-returned-directly`, `length-zero-compare`, `commented-out-code`, etc. --
  the sweep confirmed these are NOT mechanically fixable (multi-line / type-gated / judgment);
  they stay report-only. `nil-comparison` likewise (see above).

## Design

### 1. Registries

Extend `FIXABLE_RULE_IDS` (`src/cli/DRagLint.CLI.pas:4458`) from 3 to 9 entries, adding
`redundant-not-not`, `redundant-as-tobject`, `boolean-comparison-true`,
`reserved-word-casing`, `redundant-assigned-free`, `off-by-one-count`. The existing
lockstep guard test (`FIXABLE_RULE_IDS` <-> `BuildAutofixEdits` agree) must still pass.

Add a second small registry for behaviour-changing fixes:

```pascal
const
  RISKY_FIX_RULE_IDS: array[0..0] of string = ('off-by-one-count');

function IsRiskyFixRule(const ARuleId: string): Boolean;  { SameText scan, mirrors IsFixableRule }
```

### 2. Fix branches in `BuildAutofixEdits`

Each new rule adds an `else if SameText(F.RuleId, '<id>') and (F.StartLine = F.EndLine)`
branch emitting one `tekReplaceInLine` over `[F.StartCol, F.EndCol)`. Each branch is fully
guarded: a malformed / unexpected span produces NO edit (silently skipped, `AFixableCount`
not incremented) -- matching the existing conservative style.

**`redundant-not-not`** -- span covers `not not X`.
- `Span := Copy(Ln, StartCol, EndCol-StartCol)`.
- Guard: `Span` (case-insensitive) begins with the keyword `not`, then whitespace, then
  the keyword `not` again (whole-word `not`, not a `notxxx` identifier prefix).
- Strip both `not` keywords and the whitespace up to the inner operand; `Repl :=` the
  remaining operand text, verbatim (no re-trim beyond the leading strip).
- Replace the span with `Repl`. (No paren risk: X stays in the same expression position.)

**`redundant-as-tobject`** -- span covers `X as TObject`.
- Guard: scan `Span` at paren/bracket depth 0 for the whole-word `as` operator token that
  is followed (after whitespace) by the whole-word identifier `TObject` extending to the
  end of the span (case-insensitive). If no such depth-0 ` as TObject` tail, no edit.
- `AsPos` := the 1-based index in `Span` of that depth-0 `as` keyword.
  `Repl := TrimRight(Copy(Span, 1, AsPos - 1))` -- the lhs text with trailing space removed.
- Replace the span with `Repl`. (No paren risk: `as` is the captured node's outermost
  operator, so the lhs is already a complete operand.)

**`boolean-comparison-true`** -- span covers `X <op> <bool>`, op in {`=`,`<>`},
bool in {`True`,`False`}.
- Scan `Span` at paren/bracket depth 0 for the LAST `=` or `<>` operator token; split into
  `LhsText`, `Op`, `RhsBoolText`. Guard: a valid split with a recognised op and bool token.
- Polarity: `(= True)` or `(<> False)` -> **positive**; `(= False)` or `(<> True)` ->
  **negative**.
- Positive: `Repl := TrimRight(LhsText)` (was already a boolean expression; the comparison
  was the redundant part).
- Negative: `Operand := Trim(LhsText)`; if `not IsSingleTokenAtom(Operand)` then
  `Operand := '(' + Operand + ')'`; `Repl := 'not ' + Operand`.
- Replace the span with `Repl`.

**`reserved-word-casing`** -- span covers the keyword token (Pascal `EmitAt`, single-line).
- `Span := Copy(Ln, StartCol, EndCol-StartCol)`.
- Guard: `Span` is non-empty and `Span <> LowerCase(Span)` (there is something to fix).
- `Repl := LowerCase(Span)`. Replace the span with `Repl`. (Behaviour-preserving: Pascal
  keywords are case-insensitive and have no reference sites -- this is a local text edit, not
  a rename.)

**`redundant-assigned-free`** -- span covers the whole single-line `if Assigned(X) then
<stmt>;` (`.scm` `@warn` on the `if` node, incl. trailing `;`).
- Guard: `F.StartLine = F.EndLine` (single-line only; multi-line `if`/`then` splits are
  skipped).
- Scan `Span` for the delimited `then` keyword: whole-word `then` (preceded and followed by
  whitespace / non-identifier), NOT a substring of an identifier (a var named e.g.
  `Authenticated` must not match). Take the text AFTER `then` (trimmed-left) to end of span
  as `Repl` (this is `X.Free;` or `FreeAndNil(X);`, semicolon preserved).
- Guard: `Repl` non-empty. Replace the span with `Repl`. (Behaviour-preserving: `TObject.Free`
  is nil-safe and `FreeAndNil` tolerates nil, so the `Assigned` guard is redundant; the
  else-clause form does not fire -- the rule only matches the guard-less `if`.)

**`off-by-one-count`** -- span covers the loop END-BOUND only (`.scm` `@warn` on the
`exprDot X.Count` / `exprCall Length(X)` node, single-line). **BEHAVIOUR-CHANGING.**
- Guard: `F.StartLine = F.EndLine` and `Span` non-empty.
- `Repl := Span + ' - 1'` (the bound is isolated by `to .. do`, no precedence hazard).
- Replace the span with `Repl`. This fix is registered in `RISKY_FIX_RULE_IDS`; it is still
  applied by both Fix-it and Fix-all, but every emission path tags it `risky` (see 3a).

### 3a. Risky-fix tag (containment for `off-by-one-count`)

`off-by-one-count` assumes `for I := 0 to List.Count do` is a bug (iterates one too far) and
rewrites the bound. This is *usually* right, but a deliberately-inclusive loop would be
broken. Containment = **confirmation-preview** (no batch exclusion):

- `--fix --json`: each finding object gains a `risky` boolean (`IsRiskyFixRule(F.RuleId)`).
  For non-risky rules it is `false`.
- `--fix` text / dry-run: when any emitted edit is for a risky rule, `RenderDryRun` (or the
  fix summary) prints a `[risky: behaviour-changing]` note next to that edit / in the summary.
- `Fix it` and `Fix all` both still apply it (fixable=true). Documented in AI-USAGE +
  CHANGELOG so a human/AI orchestrator is warned.
- The IDE menu / catalog `fixable` flag are unchanged (off-by-one-count shows as fixable);
  no new IDE code -- the `risky` signal is a CLI-JSON/message concern this chunk.

### 3. `IsSingleTokenAtom(const S: string): Boolean` -- correctness-critical helper

Answers: *can `not <S>` be written WITHOUT parentheses?* Factored out for direct testability.

Returns **True** (simple, no parens) when `Trim(S)` is a lone primary term: a leading
identifier / dotted chain, optionally followed only by balanced call `(...)` / index `[...]`
suffixes and `.ident` segments, with NO top-level operator and NO top-level whitespace
between tokens. Examples -> True: `Foo`, `Foo.Bar.Baz`, `Fn(a, b)`, `Arr[i]`,
`Obj.Method(x)[j]`.

Returns **False** (compound -> wrap) for everything else: any top-level operator
(`a and b`, `a + b`, `a = c`, `-x`, `@p`, `a shl 2`), any top-level whitespace outside
`()`/`[]`, empty string, or a string not starting with an identifier character.

Implementation: single left-to-right pass tracking `()`/`[]` nesting depth. At depth 0, an
operator character or a whitespace-separated token boundary -> return False. **Err toward
False** (wrap) on anything ambiguous: over-wrapping is harmless (`not (Foo)` is still
correct); under-wrapping is a correctness bug.

Direct unit assertions (exercised via the boolean fixture and, if a Pascal unit test host
exists, directly): `Foo`->T, `Foo.Bar`->T, `Fn(a,b)`->T, `Arr[i]`->T, `a and b`->F,
`a or b`->F, `x + 1`->F, `A.B and C`->F.

### 4. Fixtures & tests

Six new fixtures in `tests/autofix/fixtures/`, one per rule (mirrors `redundant_parens.pas`):

- `redundant_not_not.pas` -- `B := not not Flag;` -> apply -> `B := Flag;`.
- `redundant_as_tobject.pas` -- `Obj := Sender as TObject;` -> apply -> `Obj := Sender;`.
- `boolean_comparison.pas` -- 5 asserted lines:
  - `if Flag = True then`      -> `if Flag then`
  - `if Flag <> False then`    -> `if Flag then`
  - `if Flag = False then`     -> `if not Flag then`
  - `if Flag <> True then`     -> `if not Flag then`
  - `if (A and B) = False then`-> `if not (A and B) then`   (compound guard fires)
- `reserved_word_casing.pas` -- a keyword in wrong case, e.g. `BEGIN` / `IF` -> apply ->
  lowercased (`begin` / `if`). Fixture must contain the mis-cased keyword on a known line.
- `redundant_assigned_free.pas` -- `if Assigned(Obj) then Obj.Free;` -> apply -> `Obj.Free;`;
  include a second line with a var whose name contains `then` (e.g. `Authenticated`) that must
  NOT be mangled by the delimited-`then` scan (assert that line unchanged / correctly split).
- `off_by_one.pas` -- `for I := 0 to List.Count do` -> apply -> `for I := 0 to List.Count - 1 do`.

All fixtures are strict 7-bit ASCII, CRLF, with a unit name matching the file (keeps
`unit-name-matches-file` quiet), per project encoding rules.

Test harnesses (extend the existing `tests/autofix/*.ps1` pattern -- copy fixture to a
scratch dir under C:\TEMP, preview then apply, assert exact resulting line + `.bak`):

- **`run_fix_newrules.ps1`** (new) -- per-rule preview+apply+`.bak` contract for each new
  fixture, asserting the exact resulting line for every case above (all 6 rules).
- **`run_fix_risky_tag.ps1`** (new) -- `off-by-one-count` fix `--json` reports `risky:true`;
  a behaviour-preserving rule (e.g. `redundant-not-not`) reports `risky:false`; the text
  dry-run output for the off-by-one fix contains the `[risky` note.
- **`run_fixable_catalog.ps1`** (existing) -- auto-covers the new rules; update its expected
  set so all 6 new ids report `fixable=true` and the fixable total = **9**.
- **Lockstep guard test** (existing) -- must pass with the 6 new registry entries.

### 5. Batch-gating regression test + doc (the user's lead item)

**Behaviour is ALREADY correct** (diagnosis in BACKLOG LATEST-10): findings pass through
`Cfg.ShouldKeep` (the enable/disable filter) into `Survivors` in `FinalizeAndOutput`
BEFORE the `--fix` block runs, and `--fix` operates only on `Survivors`/`Targeted`.
`lint-all` routes through the same `FinalizeAndOutput`, so it is gated identically. Chunk 2
LOCKS and DOCUMENTS it:

- **`run_fix_respects_config.ps1`** (new) -- write a `drag-lint-lint.json` disabling ONE
  fixable rule, run `lint --fix --json --apply` on a fixture containing that rule + another
  fixable rule; assert the disabled rule's finding is NOT applied while the enabled one is.
  Repeat via `lint-all --fix` on the `proj/` fixture.
- **Docs**: add "batch fix respects the active rule set (disabled rules are not fixed)" to
  `docs/lint/AI-USAGE.md` and CHANGELOG.

### 6. Minor 1 -- `applied` accounting for no-edit findings

Untargeted `lint --fix --json --apply` currently reports `applied:true` for a finding whose
rule is fixable but whose span produced NO edit (a branch guard failed). Fix: derive
`applied` from whether an edit was actually produced/applied for THAT finding, not from
"rule is fixable". Fold into the same JSON/edit accounting the gating test exercises; add an
assertion (a guarded-out finding reports `applied:false`).

### 7. Minor 2 -- `--fix --format sarif`

When `--fix` is combined with `--format sarif` (fix mode cannot emit SARIF), print a clear
stderr note (`--fix does not support SARIF output; using text output`) and proceed in text
mode. Non-breaking; least surprising for scripts. Add a small assertion (stderr contains the
note, stdout is text not SARIF).

## Verification & publish

- Build the CLI via the delphi-build skill (staged win64 exe in `third_party/dll-win64/`).
- Full battery green: lint 154/154, store 16/16, all autofix suites + `run_fix_newrules`
  (6 rules) + `run_fix_risky_tag` + `run_fix_respects_config` + `run_fixable_catalog`
  (9 fixable) + lockstep guard.
- No schema change (still v13). No IDE code change (menu/flag/checkbox auto-light for the 6
  new ids). Optional live smoke: confirm one new rule ("Fix it" on a `redundant-not-not` or
  `boolean-comparison-true` finding) in the real IDE.
- Final whole-branch opus review -> bump `VERSION` (`src/cli/DRagLint.CLI.pas:6`) to
  `0.89.0-alpha` -> CHANGELOG -> BACKLOG -> pack -> tag `v0.89.0-alpha` -> GitHub release.
  Release commit = CLI.pas + CHANGELOG + BACKLOG only; any rebuilt BPL/DCP goes in a
  SEPARATE `build(plugin):` commit; the release ZIP is CLI-only.

## Risks & mitigations

- **Compound-operand mis-classification** -> wrong `not X` fix. Mitigated by
  `IsSingleTokenAtom` erring toward wrapping + the `(A and B) = False` fixture case.
- **`off-by-one-count` breaks an intentionally-inclusive loop** -- the fix is
  behaviour-changing. Mitigated by the `risky` tag (JSON `risky:true` + text `[risky` note)
  so a human/AI orchestrator is warned. NOT batch-excluded (user decision: confirmation-
  preview, not exclusion). Documented in AI-USAGE + CHANGELOG.
- **`redundant-assigned-free` delimited-`then` mis-match** (a var named `...then...`) ->
  wrong split. Mitigated by whole-word `then` matching + the fixture's `Authenticated` case.
- **`.scm` span not covering the whole expression** -> mis-slice. Mitigated by each branch
  guarding its expected token shape and skipping (no edit) on mismatch, plus preview mode
  (`--fix` without `--apply`) never touching disk.
- **Multi-fix on one line** (two fixable findings same line) -- out of scope, unchanged from
  Chunk 1 (the applier orders by line; same-line column reconciliation is a known limitation
  noted in the `BuildAutofixEdits` remarks).

## Out-of-band context

- The `autofix-fixability-sweep` workflow (2026-07-05) classified all 163 rules; its verified
  finds are ALL included here (9 total fixable). Report saved in the session scratchpad
  (`sweep-result.json`). No rule-widening remains for a Chunk 3.
- Roadmap: `docs/lint/drag-lint TODO plan.md` (Track 1 AutoFix). Next Track-1 item after this
  = the FAutoFix save-time auto-apply control (was "Chunk 3").
- Cadence (user): publish chunk -> plan next -> handoff -> clear -> implement -> publish.
