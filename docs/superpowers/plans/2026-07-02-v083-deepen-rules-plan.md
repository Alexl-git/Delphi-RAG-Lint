# v0.83 Plan -- deepen existing rules + last two refactoring-detection signals (AUTONOMOUS FORK)

> **For the autonomous worker:** You are running UNSUPERVISED on branch `feat/v083-deepen-rules` (forked from `main`,
> which is at v0.82.0-alpha). A human reviews your branch tomorrow. Work through the items IN ORDER. Do each YOURSELF --
> **DO NOT spawn subagents / use the Agent tool / delegate** (a prior session's nested-agent delegation caused an orphan
> that raced the tree; single-agent sequential is required here). After EACH committed item, **push the branch**
> (`git push -u origin feat/v083-deepen-rules`) so progress is durable regardless of what happens to the launching
> session. Follow TDD + build-verify. **STOP before any release** (no version bump, no tag, no `gh release`) -- the human
> reviews + releases. Maintain a running progress log at `.superpowers/sdd/v083-progress.md` (append after each item).

**Goal:** ship the last two refactoring-DETECTION signals (`split-variable`, `separate-query-from-modifier`, both new
OFF-by-default) and DEEPEN the existing `object-leak` ON rule (strengthen its ownership oracle for RTL owned bases).
After this, drag-lint's lint-detection coverage is effectively complete.

**Order (autonomous-safety ordering -- SAFE items first):**
1. `split-variable` (NEW, OFF -- cannot regress anything).
2. `separate-query-from-modifier` (NEW, OFF -- cannot regress anything).
3. `object-leak` OwnsOracle enhancement (touches an ON rule -- STRICT guardrail, defer-if-regress).

Doing 1+2 first guarantees safe, reviewable progress even if 3 must be deferred.

## Global Constraints (obey for every item)
- **Encoding:** `.pas`/fixtures strict 7-bit ASCII, CRLF, no BOM. DocInsight `///` on new public surface. No `}` inside a
  `{ }` comment.
- **Build Win64:** `Stop-Process -Name drag-lint -Force -ErrorAction SilentlyContinue` (edit hook locks the exe), then
  `build\build_draglint_win64.bat` via PowerShell `Start-Process -Wait` -> log; success = ExitCode 0 + `OK: staged` + no
  `[dcc] Error`/`Fatal`. NEVER the MCP build tool; NEVER the .bat via the Bash tool (hangs). (This .bat does NOT print
  `BUILD_EXITCODE=`; verify via captured ExitCode 0 + `OK: staged` + no `Error` lines.)
- **Test exe** = `third_party\dll-win64\drag-lint.exe`. Harness baselines (all green at start of this fork):
  file `tests\lint\run_lint_tests.ps1` = **151**; store `tests\lint-store\run_store_tests.ps1` = **16**; catalog
  `tests\rules-catalog\run_rulecatalog_tests.ps1` = **29**; flowengine `tests\flowengine\run_flowengine_tests.ps1` = **33**;
  exit-code `tests\ergonomics\run_exitcode_tests.ps1` = **11 unit + 4 CLI**. New fixtures grow the relevant harness by 1
  each -- report the new counts. NO regression to any baseline.
- **OFF-by-default requires BOTH** catalog `False` in `RuleCatalog.pas` AND the rule id in the DefDisabled list in EVERY
  emitting CLI path in `CLI.pas` -- verify OFF-suppression at RUNTIME (bare run emits 0; `--config {enabled:[...]}` or
  `--rule` makes it fire). For a `lint-all`/store rule the DefDisabled site is `DoLintAll`'s array; for a file-level flow/
  AST rule mirror an existing OFF file-level rule (`default-encoding-io` in DeadCodeChecks, or `interface-object-mixing`/
  `unsafe-typecast-without-is` for CheckTypeAware) across ALL its CLI sites. Confirm which path emits your rule first.
- **Reuse EXISTING categories.** `refactoring`, `data-flow`, `resource-lifetime`, `bug-patterns`, `metrics` etc. already
  exist (see `tests/rules-catalog/RuleCatalogTests.dpr` CanonicalBuckets). A genuinely new category must be added there or
  the catalog test breaks.
- Commit each item separately, message per item below; push the branch after each. Stage only that item's files (never
  `.claude/`/`.vscode/`).

---

## Item 1 -- `split-variable` (Split Variable) -- NEW, category `refactoring`, `info`, OFF-by-default
**What:** flag a local variable that is reused for two UNRELATED purposes -- i.e. it has >=2 DISJOINT def-use lifetimes
where a later whole-variable definition overwrites the variable with NO read of the prior value in between (the variable
serves two roles and should be split into two locals). This is an M2 flow signal.

**Where:** `src/diagnostics/DRagLint.Diagnostics.FlowChecks.pas` -- the M2 CFG/def-use engine. It already hosts
`overwrite-before-read`, `write-only-local`, `loop-var-after-loop` as passes over the per-routine CFG (`Cfg`, `Vars`,
`Blocks`, def-use). Add a new pass in the same structure. The signal is close to `overwrite-before-read` (a whole-var def
with no intervening read) BUT split-variable specifically wants: the variable has an EARLIER complete def-use lifetime
(def, then >=1 read) AND THEN a later whole-var def that starts a SECOND lifetime -- two disjoint live ranges. If it fires
identically to `overwrite-before-read`, it is redundant -> in that case DEFER it and document (do not ship a duplicate).
Investigate the overlap FIRST (read `overwrite-before-read`'s logic in this file); ship only if split-variable's signal is
distinct (two genuine live ranges, both used) and low-FP.

**Steps (TDD):**
1. Fixture `tests/lint/split-variable.pas` (+ `.pas.expected` + `.config.json` enabling it -- file-harness, like
   `default-encoding-io.*`): a routine where `X` is assigned+used for purpose A, then reassigned+used for purpose B (two
   disjoint lifetimes) -> FIRES; a routine where `X` is a normal single-purpose accumulator (reassigned but the running
   value is read) -> must NOT fire; a routine matching `overwrite-before-read` (clobbered before any read) -> must NOT
   fire as split-variable (that's a different rule). Confirm the fire line.
2. Implement the pass; category `refactoring`, `info`; catalog `False`; DefDisabled wiring in the file-level path(s).
3. src/ FP-sanity: count findings; keep OFF regardless; report the count + a sample judgement.
4. Build; all harnesses green (lint -> 152); OFF-suppression verified at runtime.
5. Commit `feat(lint): split-variable rule (refactoring, OFF-by-default, M2 two-live-range detection)`; push.
**If the M2 def-use plumbing proves too involved to do safely unsupervised, DEFER with a written analysis and move to
Item 2** (do not ship a half-working ON-path change).

## Item 2 -- `separate-query-from-modifier` (Separate Query from Modifier) -- NEW, category `refactoring`, `info`, OFF
**What:** flag a FUNCTION (has a `Result` / is not a bare procedure) that ALSO mutates observable state -- i.e. a
command-query-separation violation: a value-returning function that assigns to a field/unit-global, writes a `var`/`out`
parameter, or calls a known state-mutating routine. This is inherently noisy -> ships OFF, so tune for a LOW src/ FP.

**Where:** AST-level. Likely `src/diagnostics/DRagLint.Diagnostics.AstChecks.pas` (walk each `defProc` that is a function;
detect a state-mutation in its body). Keep the mutation definition CONSERVATIVE to control FP: start with assignment to a
FIELD (`FFoo := ...` / `Self.Foo := ...`) or a unit-level global inside a function body. Exclude constructors, setters,
property accessors, and obvious builder patterns if they dominate the FP set.

**Steps (TDD):**
1. Fixture `tests/lint/separate-query-from-modifier.pas` (+ `.expected` + `.config.json`): a function that returns a value
   AND assigns a field -> FIRES; a pure function (no mutation) -> absent; a procedure (no Result) that mutates -> absent
   (only functions are the target).
2. Implement; category `refactoring`, `info`; catalog `False`; DefDisabled wiring across the file-level path(s).
3. src/ FP-sanity -- this WILL be noisy; report the count and the dominant FP shapes. Tighten the mutation predicate until
   the FP set is defensible for an OFF rule (or, if it stays wildly noisy, DEFER with the FP analysis rather than ship).
4. Build; harnesses green (lint -> 153 if Item 1 shipped, else 152); OFF-suppression verified.
5. Commit `feat(lint): separate-query-from-modifier rule (refactoring, OFF-by-default, CQS)`; push.

## Item 3 -- `object-leak` OwnsOracle enhancement -- DEEPEN an EXISTING ON rule (STRICT GUARDRAIL)
**What:** `object-leak` (`FlowChecks.pas`, the `object-leak` block ~:672-698; a conservative escape/data-flow leak
detector) uses an ownership oracle (`OwnsOracle`/`OwnCache`, created ~:709; a `TEscape` analysis consumes it). Recon
(v0.82) found it stays SILENT on an obvious `TFileStream`/`TMemoryStream`/`TBitmap` created-and-never-freed because the
oracle can't confirm those RTL types are owned `TObject`s. GOAL: strengthen the oracle to recognize known RTL OWNED bases
so real stream/file/bitmap leaks are caught -- WITHOUT introducing false positives.

**FIRST: locate + understand the ownership decision.** Grep `OwnsOracle`, `OwnCache`, `TEscape`, and the predicate that
decides whether a constructor's type is an owned object (it likely resolves the type via the store to a `TObject`
descendant and EXCLUDES component-with-Owner / interface / ref-counted types). Read it fully before touching it. The
enhancement is: treat a constructed type as owned when its declared/resolved base is a known owned RTL family --
`TStream` (and `TFileStream`/`TMemoryStream`/`TStringStream`/`TBytesStream`...), `TStrings`/`TStringList`, `TGraphic`/
`TBitmap`/`TPicture`, `TCollection`, etc. -- UNLESS ownership visibly transfers (returned, assigned to a field/out-param,
added to an owning container, or the ctor takes an `AOwner`). Keep the transfer/escape exclusions intact (that is what
keeps FP low).

**GUARDRAIL (mandatory -- this is an ON-by-default rule):**
- Existing `object-leak` fixtures/tests MUST stay green.
- Run a src/ FP-sanity BEFORE (current exe) and AFTER: capture all `object-leak` findings over `src/` (index a throwaway
  src/ DB, `lint`/`check-ast` the files, or `lint-all` if that path emits it -- confirm which path emits object-leak
  first). The AFTER set must be a SUPERSET whose ADDITIONS are all genuine leaks (spot-check every new finding). If ANY
  new finding is a false positive, tighten the exclusion; if you cannot get the additions clean, **REVERT the oracle
  change entirely and DEFER** (document the finding) -- do NOT ship new FPs on an ON rule.
- If unsure, prefer conservatism: it is fine to catch only SOME additional real leaks, as long as zero new FPs.

**Steps (TDD):**
1. Fixture(s): a routine leaking a `TFileStream`/`TMemoryStream`/`TBitmap` (created, not freed, not transferred) ->
   object-leak now FIRES; a routine that properly `try..finally`-frees it -> absent; a routine that TRANSFERS ownership
   (returns it, assigns to a field, or passes an AOwner) -> absent (no false positive). Add to the existing object-leak
   test surface (find where object-leak is currently tested).
2. Implement the oracle enhancement.
3. Build; run the BEFORE/AFTER src/ guardrail diff; all harnesses green.
4. If clean: commit `feat(flow): object-leak recognizes RTL owned bases (TStream/TStrings/TGraphic...) -- deeper leak coverage`; push.
   If it regresses: revert, and commit `docs: defer object-leak OwnsOracle enhancement -- <reason + FP evidence>`; push.

## After all items (still on the branch, NO release)
Append a final summary to `.superpowers/sdd/v083-progress.md`: what shipped / deferred, harness counts, src/ FP numbers,
the object-leak guardrail result, and anything the human should decide. Leave `VERSION` at `0.82.0-alpha` (the human bumps
+ releases after review). Ensure the branch is pushed. Then STOP.

## Fallback / safety
- Any item that is too risky to do safely unsupervised -> DEFER it with a written analysis; move on. Partial, correct,
  reviewable progress beats a broken push. Never ship a regression on an ON rule (Item 3).
- If a build breaks and you cannot fix it within reason, revert to the last good commit on the branch (which is pushed)
  and document the blocker in the progress log.
