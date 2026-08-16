# RESUME -- constructor docs, false-positive purge, and lint 2773 -> 2112

Date: 2026-08-10 (second session of the day). Supersedes
`RESUME-2026-08-10-schema-v20-v21-and-doc-drift.md` as the entry point.

## Where things are

| | start | now |
|---|---|---|
| `lint-all` | 2,773 | **2,112** |
| errors | 7 | **1** |
| `doc-drift` | 13 | **4** |
| lint fixtures | 157 | **158/158** |
| convergence gate | 0 pending | **0 pending** |

Branches:

* `main` -- **3 unpushed commits** (`176cfb9`, `65dc3b3`, `3fdefd9`)
* `fix/lint-noise-round1` -- **current branch**, 1 further commit `d18e862`
* `fix/naming-autofix` -- created, EMPTY, never used. Delete it or use it.

Nothing of mine is uncommitted. The dirty files in `git status` belong to the
OTHER workstream (`FEATURES.txt`, `PLAN-autodoc-*`, `dclDragLintWizard.bpl/.dcp`)
plus untracked INBOX notes -- **never commit those**.

## THE ONE JOB STILL RUNNING

**Library reindex win64 -> schema v21.** Started 11:40, ~2,000 of ~6,978 files
at 6 files/min, so roughly **12 more hours**, then win32 after it (the command
chains both). Output:
`C:\TEMP\claude\c--Projects-Delphi-RAG-lint\9e453cf0-...\tasks\bjzdnuk7o.output`

The resume doc it came from predicted "~45 min each" -- **that was wrong**. The
schema 20->21 bump forces a full re-parse of every file, not an incremental pass.

**It holds a Windows lock on `third_party\dll-win64\drag-lint.exe`**, so nothing
below could be deployed. Everything this session was built and tested from
`src\cli\Win64\Debug\drag-lint.exe`.

## Resume point -- do these first, in order

1. **When the reindex finishes: DEPLOY, then re-verify.**
   `cp src/cli/Win64/Debug/drag-lint.exe third_party/dll-win64/` and confirm it
   actually copied (see Gotchas -- a locked exe fails SILENTLY).
   Then re-run the **35 battery runners that take no `-Exe` flag** and therefore
   tested the OLD binary all session. One of them is
   `tests\heritage\run_virtctor_test.ps1` -- **virtual constructors**, the runner
   most likely to care about the constructor-marker change. `run_exe_freshness`
   is red until this happens and that is the only reason.

2. **Round 2 of the noise purge: SAMPLE, do not assume.**
   `field-by-name-in-loop` (340) + `duplicate-code` (269) = **29% of everything
   left**. Both were judged "genuine" in an earlier session, but that predates
   the sampling method, and `object-leak` also looked genuine until twelve of
   them were read (0 were real). Sample 12 of each before touching anything.

3. **Decide `try-except-swallowed`'s residual 104.** ~83% are the "assign a
   sentinel the caller checks" shape (`Result := False` on a probe). Whether
   that counts as swallowing is a SEMANTIC call, deliberately not made.

4. **Decide `unsafe-shellexecute` (the last error).** It fires on code that
   URL-encodes its argument and carries a comment saying so. Left strict on
   purpose: for a security rule a false negative costs more than a false
   positive. The honest fix is inline suppression -- **which does not exist**:
   the `// drag-lint:ignore try-except-swallowed (...)` comment at
   `src\lint\DRagLint.Lint.ProjectRules.pas:953` is DECORATIVE, nothing parses
   it. Implementing `// drag-lint:ignore <rule> (reason)` with a MANDATORY
   reason is probably the highest-value remaining feature.

5. **Naming autofix** -- 38 `local-var-casing` + 22 `local-field-prefix` survive
   the tightening. The fixer works (28 edits offered on one file) and its
   stale-index corruption guard landed in v0.82.

6. **Run `relint` on YADF and DataCopy** (the user's stated goal). BRANCH FIRST:
   `document --apply` rewrites source, YADF is git, DataCopy is hg AND shipped
   to a tester.

## What shipped

**Doc engine** (`176cfb9`, `65dc3b3`)
* A constructor is no longer asked for a `<returns>` it cannot have. The trigger
  was NOT the kind test -- the parser indexes a constructor as kind `method`, so
  that guard was dead code. `SignatureHasReturn` was firing on the declaration
  text. Fix is `SignatureIsConstructor`, ONE predicate read by both writer and
  checker.
* The engine now writes a `constructor` marker into the managed facts block, and
  `ddConstructorNotMarked` checks for it -- a claim the writer can satisfy.
* `<exception cref>` is no longer graded on a BODYLESS decl (interface methods).
* Constructors exempt from `ddReturnsButNoValue` too -- otherwise removing the
  demand would have started reporting every hand-documented constructor.

**Lint false positives** (`3fdefd9`, on main)
* New lint-config key `exclude_paths`; `drag-lint-lint.json` excludes
  `third_party` (134 findings of vendored upstream code). LINT scope, not INDEX
  scope -- those units are in the compile closure and symbol resolution needs them.
* `local-var-casing` SPLIT into `local-var-casing` + `local-field-prefix`
  (owner's suggestion). 116 complaints about `i` were burying 22 locals named
  `FName`/`FIdx` that genuinely read as fields.
* 1-character locals exempt from casing (135 findings).
* `hardcoded-credential` / `hardcoded-connection-string` / `sql-injection-concat`
  all tightened -- every one of their findings was false.

**Round 1** (`d18e862`, this branch)
* `object-leak` narrowed by DECLARED TYPE (106 -> 56): a record constructor
  (`TRegEx`) allocates nothing and an interface is refcounted, so those findings
  were UNFALSIFIABLE.
* Complexity thresholds retuned: cyclomatic 15->30, cognitive 25->65,
  method-too-long 120->250. The old cyclomatic threshold of 15 flagged a corpus
  whose MEDIAN flagged value was 22.
* `try-except-swallowed` accepts `Writeln`/`OutputDebugString`/`ShowMessage`.

**Shipped for agents**
* `docs/AI-CODING-CONVENTIONS.md` -- conventions stated AS the rule ids that
  enforce them; points at YADF for layout.
* `skills/relint/SKILL.md` -- the reindex->autodoc->reindex->lint-all loop.
* Both linked from `docs/AI-USAGE.md` section 4c.

## Gotchas -- what will bite a cold start

* **`index --all` resolves its manifest RELATIVE TO THE EXE'S OWN DIRECTORY.** A
  freshly built exe with no `drag-lint.json` beside it resolves **0 sections,
  indexes nothing, prints nothing, and EXITS 0**. This silently turned a full
  pipeline run into the stale-DB ordering it exists to prevent, and produced a
  completely convincing fake regression (lint 2936, doc-drift 169, 641 pending
  edits, a caller list growing 1 -> 97). Verify with
  `index --all --dry-run` -> `Sections to build:` MUST be > 0. Filed:
  `docs/INBOX-index-all-only-silently-does-nothing.md`.
  Workaround: copy `drag-lint.json`, `rules\`, `*.dll` next to the fresh exe.
* **A `cp` over a running exe fails SILENTLY on Windows.** `run_exe_freshness`
  failing means "your deploy did not happen".
* **The lint config `--config` takes a FILE PATH, not inline JSON.** Passing
  inline JSON silently disables the opt-in and makes the autofix look broken.
* **`doc-drift` inflating after an edit = a stale index, not a regression.**
  Any edit shifts line numbers; a doc block then grades against the wrong decl.
  Reindex before believing a doc-drift number.
* **NEVER run text-processing shortcuts over this repo's files.** Two self-
  inflicted wounds this session: a Python read/write round-trip converted two
  `.pas` files to LF, and an `[Text.Encoding]::ASCII` pass turned every em-dash
  in the tracked `docs/AI-USAGE.md` into `?`. `.md` is NOT covered by the
  encoding rule; `.pas`/`.dfm`/`.ps1` are (CRLF + 7-bit ASCII).
* **`run_encoding_guard` fails on 4 lone-LF `tools/lsp-diag/*.ps1`** from a
  CONCURRENT workstream. Not ours.
* **The battery driver does NOT forward `-Exe`.** 35 of 253 runners take no such
  flag, so a "green battery" against a fresh build silently tested the deployed
  (old) binary.
* **`query find-callers` is name-based and kind-blind** -- it takes the LEAF name.

## The pattern worth carrying forward

**A rule that is always wrong is worse than no rule** -- people learn to skip the
category, including the day it is right. Every category audited this session was
majority-false: 4/4 credentials, 1/1 shellexecute, 0/12 object leaks, 0/12
swallowed exceptions.

**Sample before believing a big number.** `local-var-casing` looked like 212 real
issues; 116 were the loop counter `i`, and its autofix wanted to rename `fi` to
`Fi` -- inventing an `F` field prefix and making the code worse.

**One rule, one complaint.** A message reading "should be X AND not Y" is two
rules wearing one id, and the noisy half buries the useful half.

**A threshold below the median of what it flags is describing the codebase, not
selecting outliers.**

Full false-positive analysis: `docs/BACKLOG-lint-false-positives.md` (pre-existing).
Open INBOX notes from this session: `INBOX-index-all-only-silently-does-nothing.md`,
`INBOX-exception-cref-transitive-raise.md`.
