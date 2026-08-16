> **RETIRED to INBOX-Done/ on 2026-08-16 (session 21).** FIXED 2026-08-16 (73c441c): --rule now validates from BuildCatalog (173 rules, both registries) and filters the query-rule pass. Guarded by run_rule_filter_scope.ps1 (9/9).

# `lint --rule <id>` also returns findings from OTHER rules

Found 2026-08-12 while writing `tests\autotest\run_case_dataflow.ps1` (Task 3 of
`PLAN-2026-08-12-case-dataflow-fix-and-datacopy-cycle.md`).

## Reproducer

    drag-lint lint <file.pas> --rule write-only-local --json

on a file containing `case AInput of 0: ...` returns, alongside the
`write-only-local` findings, several of:

    "Case label is a literal -- consider naming the constant"

which is `magic-literal`, not the requested rule. Same shape with
`--rule function-result-not-set`.

## Why it matters

`--rule` reads as a filter, and every caller treats it as one. Two consequences:

1. **Tests that count findings are silently wrong.** The first draft of
   `run_case_dataflow.ps1` asserted `count -eq 0` for "this rule must not
   fire" -- which failed for a reason that had nothing to do with the rule under
   test. It now filters on message text instead, and says why. Any other test
   that trusts `--rule` to isolate a rule has the same latent defect.
2. **`--fix --fix-rule` pairs with it.** `lint --fix` scopes edits by rule; if
   the rule filter is advisory on the read side, that pairing deserves checking
   before it is trusted to scope a WRITE. Not yet investigated -- flagged, not
   diagnosed.

## What is NOT yet known

Whether this is (a) the filter being applied to only some of the rule families
(the built-in AST checks are invoked as a block in `DoLint`, while `.scm` rules
come through `TLinter.LintFile`), or (b) the filter being applied at output time
but after some rules bypass it. `magic-literal` is a built-in, so (a) is the
first place to look.

Related and possibly the same root: `docs/INBOX-lint-all-json-stdout-banner.md`
records a similar "a writer that was not gated" class of defect.

## Suggested guard when fixed

A test that asks for one rule on a fixture that trips three, and asserts the
returned set contains exactly the one. Assert on the returned `rule_id` values,
not on the count -- a count check passes for the wrong reason as soon as the
fixture changes.
