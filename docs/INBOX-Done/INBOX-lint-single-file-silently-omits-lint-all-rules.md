> **RETIRED to INBOX-Done/ on 2026-08-16 (session 21).** FIXED 2026-08-16 (8d911f9): `lint <file>` now prints a stderr note that it runs per-file rules only and that whole-run rules (project-wide checks, review-marker-unused/stale) are NOT reported, so a 0 cannot be read as clean. Human path only -- JSON and the plugin stream are untouched.

# INBOX -- `lint <file>` reports 0 findings on a file `lint-all` warns about

**Found:** 2026-08-14, while building `tests\autotest\run_doc_cap_parity.ps1`.
**Severity:** medium -- it does not produce a wrong finding, it produces a
CONFIDENT ZERO, which is worse to act on.

## Symptom

Same file, same DB, same manifest, same CWD, two commands:

```
> drag-lint lint C:\TEMP\...\fx\uCapPar.pas --db fx.sqlite
0 finding(s)

> drag-lint lint-all --db fx.sqlite
uCapPar.pas:3:1   [warning] doc-drift: managed facts block is out of date
uCapPar.pas:14:1  [info]    unused-public-symbol: Caller01 has no references
lint-all: 2 finding(s)
```

`lint <file>` does not say "doc-drift skipped in single-file mode". It says
**`0 finding(s)`**, which reads as "this file is clean".

## Why (presumed, not yet confirmed in code)

Both rules that appear only under `lint-all` need a STORE-WIDE walk rather than
one file's AST: `doc-drift` iterates documented public declarations and
rebuilds their facts; `unused-public-symbol` needs whole-index reference counts.
So the omission is probably deliberate and correct AS BEHAVIOUR. The defect is
that it is silent.

## Why it matters

* It cost real time on this session: the first version of the cap-parity guard
  used `lint <file>` for both its positive and its negative phase. The positive
  phase went GREEN -- for the wrong reason -- and only the negative control
  caught it. A guard built on `lint <file>` and no negative control would have
  been the THIRD vacuous attempt at that test.
* `docs\INBOX-index-only-nonmatching-section-is-a-silent-noop.md` is the same
  shape (a command doing less than asked and reporting success). This is a
  recurring class in this CLI, not a one-off.
* Any workflow that lints one changed file as a fast pre-commit check is blind
  to every whole-index rule while believing itself covered.

## Fix

Make the omission LOUD, not different. `lint <file>` should report which rules
it did not run and why:

```
lint: 2 whole-index rule(s) not run in single-file mode (doc-drift,
      unused-public-symbol) -- use lint-all for these.
```

The list must be DERIVED from the rule registry's own scope flag, not
hand-maintained, or it becomes a third place that drifts (cf.
`INBOX-OWED-guard-for-checker-writer-cap-parity.md`, where two config sites
diverging was the whole bug).

Do NOT "fix" this by running the whole-index rules under `lint <file>` -- that
would make a single-file lint pay for a full store walk.

## Reproduce

`tests\autotest\run_doc_cap_parity.ps1` builds the fixture; swap its
`Get-StaleCount` from `lint-all` to `lint $file` and the negative control stops
firing while everything else stays green.
