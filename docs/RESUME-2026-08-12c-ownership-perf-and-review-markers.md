# RESUME -- 2026-08-12 (c). Ownership + perf fixes shipped; dl:ok marker is the next build

Supersedes `RESUME-2026-08-12b-lint-perf-release-and-yadf-cycle.md` as the entry
point. Everything that doc listed as TODO 1 / TODO 3 is DONE.

`main` = **17b29de**, **6 commits UNPUSHED**. Battery **255/255** (first time
fully green -- the old `run_migrate_v13_to_v14` failure is fixed).
Working tree dirty ONLY with the known never-commit set (`FEATURES.txt`,
`docs/lint/PLAN-autodoc-*`, the four `dclDragLintWizard.{bpl,dcp}`) plus the
untracked INBOX/RESUME notes.

## RUNNING RIGHT NOW -- check this first

**Library Win32 + Win64 full rebuild**, launched from a COPIED exe at
`C:\TEMP\claude\c--Projects-Delphi-RAG-lint\b5bef1ca-...\scratchpad\idxexe\drag-lint.exe`
so it does NOT lock the deployed binary and engine rebuilds stay possible.

```
drag-lint index --all --only Library --rebuild --jobs 2
log: ...\scratchpad\libidx-both.log   (BLOCK-BUFFERED -- reads as empty while healthy)
```

Rebuilds into `library-Win{32,64}.rebuild.sqlite`, then swaps. **Progress cannot
be read from file size** (Windows does not update size metadata for an open
SQLite file) nor from the log (block-buffered). Use IO counters instead:

```powershell
Get-CimInstance Win32_Process -Filter "ProcessId=<pid>" |
  Select ReadOperationCount,WriteOperationCount,ReadTransferCount,WriteTransferCount
```

Healthy sample taken this session: **CPU +53.4 s / 60 s, +103.3 MB written,
+42,988 writeOps**. At that rate the ~4.2 GB combined target is well under an
hour -- the "12 h" figure in older notes was NOT verified and should not be
repeated.

**It uses ~0.89 of 9 cores even with two sections and `--jobs 2`.** That is the
evidence for the owner's multi-threaded-indexer idea. Measure where it serialises
before building it -- three perf hypotheses in this repo were each stated
confidently and each wrong; only the profiler found the real owner.

## What shipped this session

1. **`e64eee4` -- `ComputeCoveredBy` gated on the index having tests at all.**
   doc-drift's unaccounted ~7.6 s tail was NOT the ancestry block the previous
   handoff suspected (ancestry 0.48 s, wiring 0.19 s). `covered-by` was **8.76 s
   of a 15.55 s facts rebuild**, walking a reverse call graph up to 200 nodes per
   declaration to return '' every time, because YADF has no tests.
   New `ISymbolStore.HasTestRoutineMarkers`, cached ON THE STORE (not a global
   memo -- an instance field needs no identity check and holds no SQLite handle
   open). Deliberately a SUPERSET of `IsTestRoutine`: over-answering True costs
   one wasted walk, under-answering False silently drops a real fact.
   YADF lint-all 30.9 -> 22.6 s, findings byte-identical over three runs.
   `DocFactsBuildProfile` now prints all nine sections plus an explicit
   `unattributed` remainder, so a future gap is a number, not arithmetic.
2. **`c3d9a5b` -- a reindex repairs a dropped or emptied `call_edges`.**
   Every guard skipped the call pass when nothing changed ON DISK, and the skip
   message's premise ("every call edge already holds") is false when the edges
   were never there. New `ISymbolStore.CallEdgesNeedRebuild` (call_edges empty AND
   call-site refs present, erring towards True including on any probe error).
   **The INBOX note put the fix in the incremental SCOPING; that path is never
   reached** -- the skip is a level up in the CLI, at THREE sites (`DoIndex`,
   `BuildPlanItem` = the `index --all` path, `IndexDictionary`). Patching only
   `DoIndex` made the fixture test green while the real `index --all --only YADF`
   still skipped, which is what caught the other two.
   YADF's live index held **0** call edges; a plain reindex now rebuilds **2,900**.
3. **`17b29de` -- `document --project` writes only to code the project owns.**
   It documented the whole compile closure. A YADF run put its only two edits into
   `C:\Projects\DelphiAST` (4,287-line diff); that repo had silently accumulated 8
   modified files + 8 `.pas.bak` across earlier sessions. Now filtered through
   `TOwnRoots` -- the same declaration `lint-all` reads -- with skipped roots NAMED
   and their file counts printed. `--document-third-party` is the escape hatch.
4. **DelphiAST moved to the IDE Library path** (Win32 + Win64, `Source` and
   `Source\SimpleParser`; prior values backed up to
   `scratchpad\libpath-Win{32,64}.backup.txt`). The closure resolver ALREADY
   excluded library-path units and `DocumentProject` already fed it
   `ResolveLibraryPaths` -- the machinery was present and merely unconfigured.
   `document --project` on YADF: **945 decls -> 53, nothing to document**.
5. **Two specs committed** -- `397c1dd` naming autofix, `7755e9c` + `7e36983`
   the `dl:ok` reviewed marker. Both approved by the owner. See below.
6. **YADF 235 -> 156 findings**, `local-var-casing` **79 -> 0**.

## THE YADF AUTODOC CYCLE NOW CONVERGES

A second `document --project` pass is a **no-op**. The long-standing "autodoc
oscillates on YADF" was two real bugs, both fixed today: the empty `call_edges`
(`Covered by:` derives from it) and autodoc rewriting a dependency that fed back
into the index. This unblocks the owner's 1 -> 2 loop, which could not have
terminated before.

## Resume point -- the ordered remainder of the owner's request

### 1. NEXT BUILD: the `dl:ok` reviewed marker (spec'd, approved, not started)

Spec: `docs/superpowers/specs/2026-08-12-reviewed-marker-design.md`.
Goal: mark every remaining YADF finding that is legitimate code, so YADF reports
**0**. Then the same for DataCopy and for drag-lint itself.

Shape: `except // dl:ok bare-except@7f3a -- rethrown by the caller`.
The `@7f3a` is 4 hex of a hash over the line's CODE tokens (comments excluded,
whitespace dropped, identifiers lowercased) so YADF's reformatting and case
normalisation do not invalidate it but a real edit does. A stale hash RE-REPORTS
the finding plus a `review-marker-stale` hint -- never silently keeps the
suppression.
**Owner requirement:** the check is ONE central filter between rule output and
report output, not per-rule, so no future rule can forget it.
UX: LSP code action "mark reviewed" (VS Code diagnostics right-click), with the
Delphi IDE plugin panel reusing the same shared marker-text routine later.

### 2. Then: the naming autofix (spec'd, approved, not started)

Spec: `docs/superpowers/specs/2026-08-12-naming-autofix-design.md`. Phase 1 is
`DRagLint.Refactor.NamePlan` (pure) + scope wiring + `record_prefix` +
compile-verified application with binary-search rollback. Phase 2 is the two
shadow rules. **Its payoff is on DataCopy/ORM3, not YADF** -- YADF's naming
findings are already 0, so do not sequence YADF's cleanup behind it.

### 3. Rule hardening (evidenced, not started) -- ~13 YADF findings

`docs/INBOX-yadf-triage-2026-08-12-out-param-and-object-leak-false-alarms.md`:
* `out-param-not-set` 7/7 false -- the Try-pattern (`TryX(...; out Y): Boolean`
  exits False without assigning Y; Delphi initialises `out` params anyway).
* `object-leak` 3/3 false -- two distinct blind spots: a correct `finally X.Free`
  nested inside a `try..except` is not matched, and `TGroup` transfers ownership
  INSIDE ITS CONSTRUCTOR (`AParent.Children.Add(Self)` into an owning list), which
  the rule only looks for at the call site.
* 3 unsampled group-E singles (`overwrite-before-read`, `write-only-local`,
  `function-result-not-set`) -- same family, likely the same story.

### 4. Owner rulings still to apply

* `commented-out-code` -- **disable** (config only).
* `bare-except` -- build the per-project exception-class unit. ALREADY DESIGNED in
  `docs/INBOX-exception-class-unit-and-generated-exception-types.md`. YADF has 4;
  ORM3 has 220 exception findings, so YADF is the cheap place to prove it.
* Complexity family + `duplicate-code` (~107 of YADF's 156) -- **the owner left
  the call to Claude**, with "if we cannot split complex routines, let it stay".
  NOT yet sampled at 12 each. 98 of 156 are in `YADF.Layout.pas`. Prior: a
  tokeniser/formatter has inherent long `case` dispatch, so "reviewed, accepted"
  via `dl:ok` probably beats refactoring -- but SAMPLE BEFORE RULING.
  YADF has a `Test\` directory; check whether it is golden/round-trip coverage
  before any AI-driven refactor, since compile-verify proves it builds, not that
  it still formats identically.

### 5. Then DataCopy, then drag-lint itself, same loop.

### 6. Follow-on owed from this session

* `index --all --only YADF --rebuild` so DelphiAST drops out of YADF's PROJECT
  index too (it is still in there from before the library-path change).
* File the `--only` silent-no-op fix
  (`docs/INBOX-index-only-nonmatching-section-is-a-silent-noop.md`).

## Gotchas that will bite a cold start

* **The episodic-memory plugin RESUMES old coding sessions and edits source.**
  Its sync spawns `claude.exe --model haiku --resume <session-id>
  --permission-mode default`. `--resume` CONTINUES the conversation; the previous
  session had ended mid-request, so a Haiku agent inherited the pending
  instruction and wrote real edits into `src/doc/DRagLint.Doc.Facts.pas` during
  this session. Killing the children is whack-a-mole -- they respawn as the sync
  walks its queue. **Kill the `sync-cli.js` node PARENTS**, and do not kill the
  `mcp-server.js` node whose parent is the live session pid. Filed:
  `docs/INBOX-episodic-memory-sync-resumes-sessions-and-edits-source.md`.
  **It recurs on every session start** until the plugin is fixed or sync disabled.
* **Run the battery with `pwsh`, NEVER `powershell.exe`.** Under Windows
  PowerShell 5.1 every single runner fails (220/220 observed) because native
  stderr surfaces as a terminating error. It looks exactly like a catastrophic
  regression and is purely the invocation.
* **A redirected battery/index log is BLOCK-BUFFERED.** Polling it mid-run shows a
  stale prefix; a run that has actually finished can read as "still going". Check
  for the process, not the log tail.
* **Rebuilding the engine kills the VS Code LSP client permanently** --
  `dragLint.serverPath` is the deployed exe the build overwrites. Recovery:
  *Developer: Reload Window*. This session rebuilt ~6 times.
* **A long library index locks the deployed exe** and blocks all engine rebuilds.
  Run it from a COPIED exe (with `drag-lint.json` and the tree-sitter companions
  beside it -- `index --all` resolves its manifest relative to the EXE'S OWN DIR).
* `--only <name>` that matches nothing indexes nothing and **exits 0**.
  `--only "Library[Win32]"` -- the name as PRINTED -- matches zero sections;
  `--only Library` matches both.
* `git add -A docs` sweeps ~35 deliberately untracked INBOX notes. Stage
  explicitly.
* The Write tool emits LF; `.pas`/`.md` here are strict 7-bit ASCII + CRLF.
  Byte-check after every write.
* The two project-partition registries DISAGREE. Trust
  `memory-dual-write.hotFileForCwd`, not `add-project.js --check`.

## Method note worth keeping

The handoff named three suspects for the doc-drift tail. Instrumenting only those
three would have "confirmed" a 0.67 s answer and missed the 8.76 s one. What
worked was instrumenting EVERY remaining sub-step and printing an explicit
`unattributed` remainder, so the profiler could not agree with the hypothesis by
omission.
