# RESUME -- 2026-08-12 (b). Lint perf, v1.3.0-alpha released, YADF/DataCopy cycle pending

Supersedes `RESUME-2026-08-12-drag-home-ownership-and-rule-fortification.md` as the
entry point. That branch is MERGED; do not act on its "local only" state.

`main` = **e1b473f**, **in sync with origin**. Battery **254/255**.
Released **v1.3.0-alpha**: tag pushed + GitHub release with win32/win64 zips
(https://github.com/Alexl-git/Delphi-RAG-Lint/releases/tag/v1.3.0-alpha).

Working tree dirty ONLY with the known never-commit set (`FEATURES.txt`,
`docs/lint/PLAN-autodoc-*`, the four `dclDragLintWizard.{bpl,dcp}`) plus ~33
deliberately untracked INBOX/RESUME notes and `tools/lsp-diag/`.

## What shipped this session

1. **`lint-all` COMPLETES on a large project.** ORM3-Micronite2027: 8,705
   CPU-seconds unfinished -> **732 s**, findings byte-identical (19,024).
   `project-rules` 537.3 -> 30.4 s. Three rules each asked the store per
   OCCURRENCE what could be asked once per run:
   `unused-private-member` 447.8 -> 0.01 s, `unused-public-symbol` 59.0 -> 0.36 s
   (both ran TWO row-materialising queries per symbol to compare a length with
   zero, the second a FULL SCAN of `refs`), `unused-unit-in-uses` unbounded ->
   17.4 s (one query per REFERENCE). New store methods
   `GetReferencedSymbolIds` / `GetReferencedNamesLower` do one DISTINCT scan each.
2. **`DRAGLINT_PROFILE=1` now profiles the LINTER**, not just the indexer: per
   phase in `lint-all`, per rule inside `project-rules`, and per section inside
   the doc-facts rebuild. Phases stream (announced on open, costed on close) so a
   run that never terminates still names the phase it died in.
3. **`idx_refs_name_nocase` on `refs(name_text COLLATE NOCASE)`.** That column had
   no index, so `find-callers` -- the index's headline query -- was a full table
   scan on every call. NO SCHEMA_VERSION bump (still 21) and no reindex needed:
   `Migrate` creates it on every open. `find-callers Create` on ORM3 = 2.58 s.
4. **Source-line memo in the doc-facts builder** (single entry, keyed on
   last-write-time). `Build` read the whole file ~5x per DECLARATION.
5. Battery 250/255 -> **254/255**. Four fixed; see Gotchas for the one that
   matters most (`run_smoke` was DEAD, not passing).

## Resume point -- the ordered remainder of the user's request

The user asked for TODO 1/2/3, then a YADF cycle, then the same for DataCopy.
**TODO 2 is done. TODO 1 is partly done. TODO 3 is untouched.**

### 1. doc-drift's remaining ~7.6 s tail (partly done)

doc-drift is still the dominant `lint-all` phase. Measured on YADF (8 files, 188
decls) with `DRAGLINT_PROFILE=1`, doc-drift is 17.5 s of a 30.9 s run, and the
facts rebuild is 15.86 s of that:

```
harvest              0.77
resolved-callers     3.74
unresolved-name      1.81
return-cases         0.03
calls                1.80
raises               0.15
(unaccounted tail)  ~7.56   <- THE TARGET. Not yet instrumented.
```

The tail is everything after the Raises block in `TDocFactsBuilder.Build`
(`src/doc/DRagLint.Doc.Facts.pas`, ends ~line 2270): the ancestry block
(`GetTransitiveAncestors`, Overrides/Implements/Overridden-by) plus
`ComputeCoveredBy` and `ComputeWiring`. **Instrument those four before touching
them** -- the section counters are already in place (`GBHarvest`, `GBResolved`,
`GBUnresolved`, `GBReturns`, `GBCalls`, `GBRaises`, `GBTotal`, printed by
`DocFactsBuildProfile`); add one more accumulator per sub-step and the answer
falls out of a single YADF run (~30 s).

**Do not re-guess.** Two hypotheses were measured and each was a minority share:
`ExistingDocFor`'s per-decl whole-file read (7%) and the unindexed name lookups
(11%).

The deeper question worth asking: doc-drift regenerates the ENTIRE facts block
per decl purely to compare it against what is on disk. A cheaper staleness test
(a stored hash of the generated block, compared before regenerating) would beat
any micro-optimisation of `Build`.

### 2. TODO 3 -- a reindex never repopulates `call_edges` once dropped

The single battery failure: `tests/callresolve/run_migrate_v13_to_v14.ps1`.
The incremental resolve keys off files CHANGED ON DISK, so when only the DB was
mutated it refills nothing -- any pre-D5 or interrupted index stays silently
broken and `find-callers --resolved` returns nothing without erroring. Filed:
`docs/INBOX-reindex-does-not-repopulate-dropped-call-edges.md`.

### 3. YADF cycle, then DataCopy

Cycle = `index --all --only YADF --rebuild` -> `document --project ... --apply`
-> `index --all --only YADF --rebuild` -> `lint-all`. Last run gave
**235 findings, 0 errors, 0 warnings**, 8 own files:

```
79 local-var-casing        16 compiler-magic-comments   15 concat-in-loop
29 duplicate-code          16 deep-nesting              15 boolean-expression-complexity
12 too-many-exit-points     9 cyclomatic-complexity      7 cognitive-complexity
 7 out-param-not-set        4 bare-except                4 large-magic-number
 3 object-leak             ... 14 more rules at 1-2 each
```

By file: `YADF.Layout.pas` 168, `YADF.Options.pas` 25, `YadfMain.pas` 24,
`YADF.Guard.pas` 8, `YADF.Tokens.pas` 6, `YADF.Groups.pas` 4.

The user's instruction: **fix `local-var-casing`**, then for the rest decide
per rule whether it is a FALSE ALARM (tighten drag-lint) or REAL (fix YADF),
then re-run the cycle and report what is left. Then the same for DataCopy.

Note the standing lesson before acting on any count: **sample ~12 findings of a
category before believing it.** Of YADF's original 70 warnings, 28 were
drag-lint's own false positives and 24 were the autodoc defect -- only ~17 were
real debt. `local-var-casing` has form here: it once showed 212 "issues" of which
116 were the loop counter `i`.

YADF is UNCOMMITTED on branch `autodoc-phaseC` by design (its tree already
carried an earlier unstable autodoc run). A pre-autodoc snapshot of this
session's state is at
`C:\TEMP\claude\c--Projects-Delphi-RAG-lint\4023b50b-27b5-4a0a-8194-83f571a83c05\scratchpad\YADF-before-autodoc.patch`
(YADF HEAD was 14ab163d).

## Gotchas that will bite a cold start

* **Rebuilding the engine KILLS the VS Code LSP client, permanently.**
  `dragLint.serverPath` defaults to `third_party\dll-win64\drag-lint.exe`, which
  every `build_draglint_win64.bat` overwrites -- so five rebuilds in three
  minutes trips vscode-languageclient's give-up rule, and the extension
  contributes NO restart command. Recovery is *Developer: Reload Window*. The
  engine is fine (an initialize handshake returns exit 0). Filed:
  `docs/INBOX-vscode-client-dies-permanently-when-engine-is-redeployed.md`.
  **The user must reload the window after any session that rebuilds.**
* **A staleness guard can be DEAD rather than passing.** `run_smoke` scraped
  `VERSION = '<literal>'` from `DRagLint.CLI.pas`; `c92cb1d` made it an alias, so
  the scrape matched nothing and the runner exited 2 -- taking its exe-vs-source
  check and 19 other checks with it, while the battery just showed one red line.
  When a test fails, check whether it is failing or NOT RUNNING.
* **Verify a count before matching it.** The two rule-count expectations were
  stale for a real reason: `local-field-prefix` was genuinely added on main
  (3fdefd9), so 116 built-ins / 10 naming are correct.
* **Use the drag-lint index, not Grep**, for Delphi symbol lookups -- the user
  corrected this mid-session. `context --task "modify <QName>"`,
  `query find-callers`, `query --name ... --json`. Log every query to
  `stats/draglint-usage.log` and every gap to `stats/draglint-gaps.log`.
* **drag-lint lints its own edits via a PostToolUse hook** -- it flagged a
  `TDateTime` `=` in new code as float-equality. It was right about the tool; the
  fix was a bit-exact `PInt64` compare, since the question is "same stamp I
  stored", and a tolerance compare would call a just-rewritten file unchanged.
* Long-running work must be launched with PowerShell `Start-Process`; a
  subagent's/bash-job's background children die with the turn.
* `git add -A docs` sweeps in ~33 deliberately untracked INBOX notes. Stage
  explicitly.
* The Write tool emits LF; `.pas`/`.md` here are strict 7-bit ASCII + CRLF.
  Byte-check after writing (`bareLF`/`nonASCII` scan).
* The project-partition registries DISAGREE: `add-project.js --check .` reports
  NOT REGISTERED while `memory-dual-write.hotFileForCwd` (what the SessionStart
  hook actually reads) resolves
  `C:/Projects/claude-obsidian/Delphi-RAG-lint/hot.md`. Trust the latter.

## Method note worth keeping

Every perf win this session came from a profiler, and every hypothesis stated
before measuring was wrong or minor. The pattern in the code was identical three
times over: **a question asked per occurrence that could be asked once per run**,
and twice the query materialised every matching row only to compare a length
with zero. Worth looking for that shape directly next time.
