# RESUME -- 2026-08-11 (afternoon). Resolve passes, editors, and the YADF lint verdict

Supersedes `RESUME-2026-08-11-indexer-perf-and-lint-round2.md` as the entry point.
Branch **`fix/lint-noise-round1`**, HEAD **`4ae1526`**, 5 commits this session,
**no upstream** (local only). `main` still has 3 unpushed.

Working tree dirty ONLY with the known never-commit set (`FEATURES.txt`,
`docs/lint/PLAN-autodoc-*`, the four `dclDragLintWizard.{bpl,dcp}`) plus
untracked INBOX notes. Nothing of this session's work is uncommitted.

## >>> THE NEXT ACTION

**Stop lint-all counting third-party code.** The user's decision, this session:
*"don't count 3rd party linter messages. Deal only with our code."*

Measured on YADF: **1,072 findings, of which 768 (72%) are in
`C:\Projects\DelphiAST\`** -- a vendored parser YADF neither owns nor can fix.
YADF's own code has **304**. 182 of the 183 `inherited-bare` findings were
DelphiAST's.

This is a SCOPE defect, not a false positive. DelphiAST is in YADF's compile
closure, so the project index pulls it in -- correctly, because YADF needs it to
resolve calls -- and `lint-all` then inherits that scope and lints it. Indexing
scope and LINTING scope are not the same question, and lint is currently
answering with the indexer's answer.

Where to look: the `lint-all` file-set selection (`DRagLint.CLI.pas`, the
lint-all verb) and `DRagLint.Storage.FileMembership.pas`. The rule wants to be
"lint files under the project's own roots, not every file in the DB". Watch out
for the `--project` vs folder-scan distinction, and for `.dfm` siblings.

## YADF, our code only -- the real backlog (304)

0 errors. 231 info / 70 warning / 3 hint.

| n | file |
|---|---|
| **190** | YADF.Layout.pas |
| 42 | YADF.Options.pas |
| 37 | YadfMain.pas |
| 15 | YADF.LineScan.pas |
| 9 | YADF.Guard.pas |
| 7 | YADF.Tokens.pas |
| 4 | YADF.Groups.pas |

The 70 WARNINGS (the tier worth acting on):
`doc-drift` 24, `used-before-assignment` 23, `raise-bare-exception` 14,
`try-except-swallowed` 3, then 2 each of `unused-parameter`,
`ifthen-both-branches`, `create-inside-try`.

Top info rules: `local-var-casing` 79, `duplicate-code` 28, `deep-nesting` 16,
`compiler-magic-comments` 16, `concat-in-loop` 15,
`boolean-expression-complexity` 15.

**Read that honestly before acting:** of the 70 warnings, 24 (`doc-drift`) are
residue of the autodoc convergence defect below, and 23
(`used-before-assignment`) are a class that sampled **15/15 FALSE** on
drag-lint's own source (guard-flag idiom + short-circuit `and`/`or`). So genuine
warning debt is plausibly ~23. And `local-var-casing` inflated 2:1 on drag-lint
(116 of 212 were the loop counter `i`) -- **sample 12 before believing it.**

Findings captured at `C:\TEMP\claude\yadf_findings.txt` (all 1,072) and
`yadf_own.txt` (the 304).

## SHIPPED THIS SESSION (5 commits)

* **`043d402` -- resolve passes are incremental.** 2.09 GB library-Win32 index:
  indexing ONE file went **2,276.7 s -> 38.7 s**; a no-op re-index **-> 20.9 s**.
  `ResolveCallTargets` alone 2,252.8 s -> 17.0 s. Verified row-identical over
  3.32M refs + 541,354 call edges (`C:\TEMP\claude\cmpcalls_sql.py`), plus five
  mutation shapes on a fresh 168-file index.
* **`9898982` -- the call-target rebuild is atomic.** Its `DELETE` sat OUTSIDE
  the rebuild transaction, so an interruption emptied `call_edges` silently. I
  proved it by destroying all 541,352 edges in library-Win32 with a kill;
  repaired (2,623 s) and verified back to 541,354.
* **`050b10e` -- deep-nesting no longer counts an else-if chain as one level per
  branch.** `ParseArgs` read 141 deep, `Run` 84; both are flat dispatchers. New
  fixture pins both directions. Fixtures 161/161.
* **`c92cb1d` -- VS Code language client** (`editors/vscode/drag-lint/`),
  installed at `%USERPROFILE%\.vscode\extensions\drag-lint-1.2.2`. Also unified
  the version: the LSP handshake had said `0.40.5-alpha` while the CLI said
  `1.2.2-alpha`. Now `DRAGLINT_VERSION` in Core.Model; both agree.
* **`4ae1526` -- `docs/EDITORS.md`**, linked from README + INSTALL. Includes the
  full Zed Rust/WASM extension SPEC so a contributor with `rustup` can build it.

Battery **249/253** (4 known: 2 stale rule-count expectations from the naming
split, the lone-LF guard on untracked `tools/lsp-diag`, exe-freshness which now
passes). Lint fixtures 161/161, lint-store 16/16.

## OPEN DEFECTS FILED THIS SESSION (all untracked INBOX notes)

1. **`INBOX-autodoc-not-idempotent-on-yadf.md`** -- the `Covered by:` fact
   OSCILLATES across a reindex, so autodoc never reaches a fixed point: 54
   pending edits across 5 files, IDENTICAL across two full runs. Proven: apply
   -> dry-run with NO reindex converges ("nothing to document"); a rebuild flips
   it back. Overloads were REFUTED as the cause. `Covered by:` names test
   routines living in `YADFOT.dproj`, a separate DB since the per-project split.
   **A fact that cannot be computed from the configured index should be
   PRESERVED, not stripped** -- deleting it destroys information nothing else
   records.
2. **`INBOX-whole-db-resolve-degrades-a-stale-index.md`** -- a whole-corpus
   resolve re-derives `refs.receiver_text` from the file ON DISK at the ref's
   STORED line/col; on a stale index it overwrites good receivers with garbage
   (11,008 receivers + 464 edges destroyed, measured).
3. **`INBOX-deep-nesting-silent-on-trailing-else-call.md`** -- a chain ending in
   `else <procedure call>;` makes deep-nesting report NOTHING for that routine.
4. **drag-lint's own autofix broke the BPL build.** Commit `41134be` ("apply
   drag-lint's own safe autofixes to drag-lint") deleted three casts that were
   NOT redundant (`TJSONObject(Root).GetValue(...)` -> `Root.GetValue(...)`),
   leaving `dclDragLintWizard` unbuildable. Fixed in `c92cb1d`. **It shipped
   because the battery builds the CLI, not the package** -- consider adding a
   BPL build to the battery. NOT yet filed as its own note.

## STATE OF THINGS

* **Indexes: BOTH library platforms are now COMPLETE and VERIFIED.**

  | | files | symbols | refs | call_edges |
  |---|---|---|---|---|
  | Win32 | 7,412 | 2,240,573 | 3,321,103 | 541,354 |
  | Win64 | 6,978 | 2,233,622 | 3,358,430 | 548,438 |

  Both: `quick_check` ok, 0 foreign-key violations, `find-callers` smoke test
  returns real results. Win64 finished at **7,465 s (2.07 h)** for a full
  `--recompile` top-up from 2,123 already-indexed files -- and that run INCLUDED
  the whole-corpus resolve passes, which is the honest end-to-end number now that
  they are timed. Win32 was repaired after this session's call-edge incident.
  The old "Win64 index is INCOMPLETE" standing note is CLEARED.
* **Deployed:** CLI Win32 (Release) + Win64 (Debug) + both BPLs, all rebuilt and
  deployed 2026-08-11 ~11:46 and again after the version fix.
* **YADF** is left AUTODOCUMENTED on branch `autodoc-phaseC`, 11 files modified,
  uncommitted. Revert with `cd /c/Projects/YADF && git checkout -- .`. It is
  documented but **NOT at a fixed point** -- re-running churns those 5 files.

## GOTCHAS THAT COST TIME TODAY

* **stdout is block-buffered when redirected; stderr is not.** I read a stale
  stdout log, concluded an index run was still walking files, killed it -- and it
  was actually inside the 37-minute call pass. That is how the 541K edges died.
  `Win32_Process.WriteTransferCount` is the only reliable liveness signal.
* **Verify BEFORE asserting a destructive action is safe**, not after. The check
  that caught the damage was the right one; running it first would have avoided
  it entirely.
* **A fixture that does not reproduce a recorded defect is evidence about the
  FIXTURE first.** My deep-nesting fixture accidentally hit a *different* bug
  (trailing `else <call>` silences the rule) and nearly made me dismiss a real
  defect as already-fixed. Measuring the routine the note actually named
  (`ParseArgs`, 141) is what saved it.
* **The Write tool emits LF.** It wrote a `.pas` fixture with 48 lone LFs,
  violating the strict-CRLF rule. Always byte-check after writing Delphi source.
* **The IDE's LSP holds `third_party\dll-win64\drag-lint.exe` open**, so deploys
  fail while RAD Studio runs. Run index jobs from COPIES in scratch.
* `index --all` resolves its manifest **relative to the exe's own dir** -- a
  copied exe needs `drag-lint.json` and the tree-sitter DLLs beside it. Verify
  with `--dry-run` -> `Sections to build: > 0`.
* A `.bat` run via `Start-Process` does not search its own directory: use an
  ABSOLUTE exe path inside the bat, or you get exit 9009.

## HARNESSES

* `C:\TEMP\claude\yadf_pipeline.sh` -- reindex -> lint baseline -> autodoc apply
  -> reindex -> convergence probe -> lint-all + per-rule breakdown. Run-stamped;
  records YADF's branch/HEAD and prints the exact revert command.
* `C:\TEMP\claude\cmpcalls_sql.py` (ATTACH + EXCEPT, for 2 GB indexes) and
  `cmpcalls.py` (row sets, small DBs) -- compare two indexes on
  `refs.receiver_text`/`external_target` and every call edge, keyed on
  (file path, line, col, name) so re-issued symbol ids do not read as diffs.
* `DRAGLINT_PROFILE=1` -- per-phase indexer breakdown.
  `DRAGLINT_NO_SCOPED_RESOLVE=1` -- forces the old whole-corpus call pass.
