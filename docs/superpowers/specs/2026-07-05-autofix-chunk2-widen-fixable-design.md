---
title: "AutoFix Chunk 2: Widen the fixable-rule set (+3) + batch-gating test/doc + 2 Minors"
date: 2026-07-05
status: approved
author: Claude
supersedes-scope-note: >
  Chunk 1 (v0.88.0-alpha, spec 2026-07-05-autofix-chunk1-fix-it-design.md) built the
  full "Fix it" vertical slice on the 3 existing fixable rules. Chunk 2 WIDENS that set
  and closes the small deferred items. No new CLI verbs, no IDE code, no schema change.
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

Chunk 2 makes **3 more rules fixable** (doubling the safe set to 6), locks and documents
the already-correct batch-gating behaviour (the user's original lead item), and closes 2
deferred final-review Minors. It ships as release **v0.89.0-alpha**.

An **exhaustive 163-rule fixability sweep** runs in parallel (its own workflow, results
land in the scratchpad); **Chunk 3** will widen to the full evidence-backed safe set. This
spec is intentionally scoped to the 3 highest-confidence, zero/low-risk rules so Chunk 2
stays small and shippable.

## Background: how a fix is built

`BuildAutofixEdits` (`src/cli/DRagLint.CLI.pas:4489`) consumes findings and emits
`TTextEdit`s. Only two edit kinds exist:

- `tekDeleteLines` -- delete whole source line(s) `StartLine..EndLine`.
- `tekReplaceInLine` -- on ONE line, replace `[StartCol, EndCol)` with a computed string.

A rule is **mechanically fixable** iff the correct fix is a single deterministic edit of
one of those kinds, computable from the finding's span + that line's text ALONE -- no type
resolution, no cross-line/flow reasoning, no rename, no multi-line restructure.

Finding spans come from two engines:

- **`.scm` (declarative) rules**: span = the `@warn`-captured node's full
  `StartPoint..EndPoint` (`src/lint/DRagLint.Lint.QueryRules.pas:306-309`). The
  `rules/<id>.scm` file decides what `@warn` covers. For the 3 rules here, `@warn` is on
  the whole offending expression node, so the span bounds exactly the text to rewrite.
- **Pascal-emitted rules**: span set at a `src/diagnostics/*.pas` emission site (often via
  an `EmitAt` helper: `EndCol := StartCol + Length(Trim(NodeStr(node)))`).

## Scope

### In scope

1. Make 3 rules fixable:
   - `redundant-not-not`  (`.scm`, dead-code)
   - `redundant-as-tobject` (`.scm`, dead-code)
   - `boolean-comparison-true` (`.scm`, dead-code)
2. Batch-gating regression test + documentation (already-correct behaviour, never tested).
3. Minor 1: `applied` accounting for no-edit findings.
4. Minor 2: `--fix --format sarif` stderr note.
5. Publish v0.89.0-alpha.

### Explicitly NOT in scope

- `nil-comparison` -- its `X <> nil -> Assigned(X)` swap has an **undetectable** behaviour
  edge for procedure-of-object / method-pointer references (per the rule's own `.scm`
  comment: `<> nil` checks only the code pointer; `Assigned` checks both). We cannot tell
  X's type from text alone, so the swap is not strictly side-effect-free. Returns to the
  Chunk 3 sweep for possible type-gating. **Dropped.**
- Any new CLI verb, IDE code, or index-schema change (all inherited from Chunk 1).
- `boolean-result-returned-directly`, `redundant-assigned-free`, `length-zero-compare`,
  `commented-out-code`, etc. -- deferred to Chunk 3 (multi-line / type-gated / judgment).

## Design

### 1. Registry

Extend `FIXABLE_RULE_IDS` (`src/cli/DRagLint.CLI.pas:4458`) from 3 to 6 entries, adding
`redundant-not-not`, `redundant-as-tobject`, `boolean-comparison-true`. The existing
lockstep guard test (`FIXABLE_RULE_IDS` <-> `BuildAutofixEdits` agree) must still pass.

### 2. Fix branches in `BuildAutofixEdits`

All three add an `else if SameText(F.RuleId, '<id>') and (F.StartLine = F.EndLine)` branch
emitting one `tekReplaceInLine` over `[F.StartCol, F.EndCol)`. Each branch is fully guarded:
a malformed / unexpected span produces NO edit (silently skipped, `AFixableCount` not
incremented) -- matching the existing conservative style.

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

Three new fixtures in `tests/autofix/fixtures/`, one per rule (mirrors `redundant_parens.pas`):

- `redundant_not_not.pas` -- `B := not not Flag;` on a known line -> apply -> `B := Flag;`.
- `redundant_as_tobject.pas` -- `Obj := Sender as TObject;` -> apply -> `Obj := Sender;`.
- `boolean_comparison.pas` -- 5 asserted lines, each with its expected result:
  - `if Flag = True then`      -> `if Flag then`
  - `if Flag <> False then`    -> `if Flag then`
  - `if Flag = False then`     -> `if not Flag then`
  - `if Flag <> True then`     -> `if not Flag then`
  - `if (A and B) = False then`-> `if not (A and B) then`   (compound guard fires)

All fixtures are strict 7-bit ASCII, CRLF, with a unit name matching the file (keeps
`unit-name-matches-file` quiet), per project encoding rules.

Test harnesses (extend the existing `tests/autofix/*.ps1` pattern -- copy fixture to a
scratch dir under C:\TEMP, preview then apply, assert exact resulting line + `.bak`):

- **`run_fix_newrules.ps1`** (new) -- per-rule preview+apply+`.bak` contract for each new
  fixture, asserting the exact resulting line for every case above.
- **`run_fixable_catalog.ps1`** (existing) -- auto-covers the new rules; update its expected
  set so the 3 new ids report `fixable=true` and the fixable total = 6.
- **Lockstep guard test** (existing) -- must pass with the 3 new registry entries.

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
  + `run_fix_respects_config` + `run_fixable_catalog` (6 fixable) + lockstep guard.
- No schema change (still v13). No IDE code change (menu/flag/checkbox auto-light for the 3
  new ids). Optional live smoke: confirm one new rule ("Fix it" on a `redundant-not-not` or
  `boolean-comparison-true` finding) in the real IDE.
- Final whole-branch opus review -> bump `VERSION` (`src/cli/DRagLint.CLI.pas:6`) to
  `0.89.0-alpha` -> CHANGELOG -> BACKLOG -> pack -> tag `v0.89.0-alpha` -> GitHub release.
  Release commit = CLI.pas + CHANGELOG + BACKLOG only; any rebuilt BPL/DCP goes in a
  SEPARATE `build(plugin):` commit; the release ZIP is CLI-only.

## Risks & mitigations

- **Compound-operand mis-classification** -> wrong `not X` fix. Mitigated by
  `IsSingleTokenAtom` erring toward wrapping + the `(A and B) = False` fixture case.
- **`.scm` span not covering the whole expression** -> mis-slice. Mitigated by each branch
  guarding its expected token shape and skipping (no edit) on mismatch, plus preview mode
  (`--fix` without `--apply`) never touching disk.
- **Multi-fix on one line** (two fixable findings same line) -- out of scope, unchanged from
  Chunk 1 (the applier orders by line; same-line column reconciliation is a known limitation
  noted in the `BuildAutofixEdits` remarks).

## Out-of-band context

- Parallel: `autofix-fixability-sweep` workflow classifies all 163 rules -> Chunk 3 widens
  to the full safe set. Report lands in the session scratchpad.
- Roadmap: `docs/lint/drag-lint TODO plan.md` (Track 1 AutoFix).
- Cadence (user): publish chunk -> plan next -> handoff -> clear -> implement -> publish.
