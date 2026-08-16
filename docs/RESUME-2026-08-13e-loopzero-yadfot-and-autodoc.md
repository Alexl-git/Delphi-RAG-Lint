# RESUME -- 2026-08-13 (session 17)

Supersedes `RESUME-2026-08-13d-shared-unit-docs-and-menu.md`.

## Status

`main` = **`4a28a10`**, **22 unpushed**. Battery **269/269 GREEN** (14.8 min).
`C:\Projects\YADF` on `autodoc-phaseC` at **`eb433b3`**, clean apart from
`.res` build artifacts and untracked reports.

Pushing needs `git config http.postBuffer 524288000` + `http.version HTTP/1.1`.

## The result

| Project | start | end |
|---|---|---|
| YADF | 12 | 12 |
| YADFOT | **35** | **9** |
| YADFSetup | 24 | 13 |
| family | 71 | **34** |

**YADFOT has 0 errors and 0 warnings.** All 9 remaining are `info`.

## What shipped

* YADF `91d1f21` -- `local-var-casing` x7 fixed BY HAND in YADF.OptionsFrame.pas
  (case-only, 86 occurrences, byte-identical file size). Cleared 7 in YADFOT AND
  7 in YADFSetup: one shared unit, seen twice.
* YADF `eb433b3` -- 10 `try-except-swallowed` allowed, `FE` -> `FormEd`,
  2 doc-drift autofixed.
* `830efec` -- spec: shared-unit per-project attributed fact segments.
* `4a28a10` -- **the engine fix**: `try-except-swallowed` now keys on the
  EXCEPTION, not the sink's name.

## NEXT SESSION STARTS HERE

1. **`object-leak` rule fix -- the best remaining value.** Rule-hardening plan
   item 2, cost S, ~15 findings corpus-wide, and 2 of YADFOT's 9. Both YADFOT
   cases are PROVEN false positives (evidence in
   `INBOX-yadfot-loopzero-remainder-2026-08-13.md`):
   - `YADF.Tokens.pas:282` -- `Lex` IS freed, `finally Lex.Free` at `:322`. The
     guard is the NEXT statement and the rule looks in the wrong place.
   - `YADF.Groups.pas:200` -- ownership TRANSFERS: `TGroup.Create` ends with
     `AParent.Children.Add(Self)` (`:124`) and `Destroy` frees `Children`
     (`:130`). Plan item 6, but the transfer is a CONSTRUCTOR ARGUMENT, so a
     VCL-`Owner`-shaped check will not catch it.
2. **Implement the shared-unit spec** (`830efec`). The required test is the
   feature: run `document` in all 6 project orders, assert byte-identical.
3. `used-before-assignment` x2 and `length-zero-compare` x1 -- both M-sized
   (CFG lattice / declared-type propagation). Filed, not attempted.

## Autodoc backlog -- re-measured, and the picture CHANGED

* **`INBOX-autodoc-caller-list-fabricates-callers...` is largely FIXED.**
  Re-ran the exact reproducer: `TQueryRule.Create` went from **107 fabricated
  callers to 1**, the correct `TQueryRuleLoader.LoadAll`, plus one spurious
  entry that CARRIES the ` ?` marker. No `(+N more)` fan-out anywhere in that
  unit. Only `Create` was re-measured -- **re-verify on `Execute`/`Add`/`Free`
  before closing it.**
* **Fix 2 (mark uniformly-uncertain lists) is now a COST decision, not a safety
  one, and still needs the owner ruling.** It would add ` ?` to 70-85% of
  entries (65/99 lines on YADF, 832/1126 on drag-lint, measured in
  `run_doc_p3_callerline.ps1`) and reverse a decision that file pins with
  mutation cases M2/M3. **Do not flip it silently.**
* Still open and untouched: `document --qname --apply` nesting on a stale
  anchor; `document --project` ignoring `ownRoots`; `Returns:` incomplete;
  autodoc-not-idempotent (54 pending edits, 2026-08-11, predates this session's
  convergence work -- probably improved, unmeasured).
* **UNEXPLAINED, and it corrupts source.** A stray autodoc run this session
  produced DUPLICATE `<remarks>` blocks (two for `ResolveProfileIniPath`) and
  orphan blocks with no declaration attached in `YADF.Groups.pas` /
  `YADF.Tokens.pas`. Reverted; patch saved at
  `C:\TEMP\claude\c--Projects-Delphi-RAG-lint\02688424-cda2-4f74-8cbf-83f5a14b5a8b\scratchpad\rogue-autodoc-2026-08-13.patch`.
  Same family as the stale-anchor note. **Understand this before any wide
  `--apply`.**

## Beliefs CORRECTED this session

* **`local-var-casing` is NOT autofixable.** It advertises `fixable: true` and
  answers `no fixable findings (of 7 finding(s))` -- the identical refusal as
  `field-name-prefix`. `INBOX-field-name-prefix-fixable-flag-lies.md` asserted
  it "does work"; that was never tested and is false. **2 of 2 naming rules
  checked are lying**, out of 21 claiming the flag.
* **`--rule` is the REPORT filter; `--fix-rule` is the FIX filter.** They are
  different flags. `--rule X --fix` offers fixes for everything fixable, not X.
  (Also: `--rule` filters the printed lines but the SUMMARY still reports the
  unfiltered total, which reads as a contradiction.)
* **The `(+N more)` churn is not only about N.** The NAMED entries differ per
  project too -- `declaration (YADF.Debug.pas)` is in YADF's list and not
  YADFOT's. Any fix that stabilises only the tail marker still churns.

## Gotchas paid for this session

* **A rogue `episodic-memory` `sync-cli.js` orphan committed over my staged work**
  with a fabricated message ("Applied via drag-lint autofix" -- the autofix
  refuses to run) and ran an autodoc pass nobody asked for. Kill the orphan
  (`sync-cli.js`, parent already dead) at the first sign of unexplained tree
  changes.
* **`allow` MERGES into an existing marker** -- `// dl:ok empty-except@1500,
  try-except-swallowed@1500` -- rather than adding a second comment. Good.
* **`allow` REFUSES a file-level anchor**: `unit-too-large` reports at `:1:1`,
  which is inside a block comment, so the marker "would not parse back". The
  refusal is correct; the gap is that file-level rules cannot be acknowledged
  at all. Owner has said LEAVE unit-too-large ALONE.
* **`empty-except` and `try-except-swallowed` both fire on one construct**, and
  a `dl:ok` for one does NOT silence the other -- deliberate, because markers
  are excluded from counting as documentation (else suppression is
  self-fulfilling). Each rule needs its own acknowledgement.
* **The lint fixture's expectations are LINE-ANCHORED** -- new cases go LAST or
  every prior expectation silently renumbers.
* **A `Select-String 'try-except-swallowed'` on that fixture matches EVERY
  finding**, because the FILENAME contains the rule name. Filter on
  `'] <rule>:'`.
* `run_exe_freshness.ps1` fails by design if you edit engine source after
  building -- it exists to stop the battery testing a stale binary.
* Battery ~15 min; background it. Concurrent `document` calls slow it (
  `run_lint_tests` went 133s -> 148s).
