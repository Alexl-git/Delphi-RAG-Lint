# RESUME — proptree ancestor scope + converter/editor fixes

Cold-start pointer. Last updated **2026-08-02** (Phase G complete). Read this first, then
the SDD ledger named below.

## Status

**`main` = `659e665`, 80 commits ahead of `origin/main`, NOT pushed** (user holds push).

All three workstreams are now merged into `main`:

| Work | Branch | State |
|---|---|---|
| proptree ancestor-scope repair (15 commits) | `feat/proptree-ancestor-scope` @ `34a96e2` | **MERGED** (ff) into main |
| 4 ported engine fixes (6 commits) | `fix/engine-uses-target-and-build` @ `3e47f7a` | **MERGED** (ff) into main |
| 4 editor fixes (2 commits) | `fix/editor-defects` @ `659e665` | **MERGED** (ff) 2026-07-30 after review |

### 2026-07-30 -- editor fixes reviewed, merged, and DEPLOYED

Reviewed and approved; `main` fast-forwarded (strict-ff verified first). Suite rebuilt and
run: **325 pass / 0 fail / 0 skip** -- the **0 skip** is the load-bearing number, because the
new acceptance tests skip themselves when the exe/library DB is absent, and a skip would have
looked like success. `acceptance.tcxbutton.pool.{Name,Tag,Left,Top}` and the matching
`.assignable.*` all pass.

Verified end-to-end through the **deployed** binaries, not just the branch:
`proptree --qname cxButtons.TcxButton --min-visibility published --refs-as-leaves` returns
**696 leaves in 6.8 s** (branch measured 696 / 6.96 s). `Tag` is `writable=True`,
`declared_in=System.Classes.TComponent`; `Left`/`Top` `declared_in=Vcl.Controls.TControl` --
i.e. the inherited-ancestor climb is what supplies them. `Action.*` nested paths = 0 with a
bare `Action` leaf present, while `Colors.*` still yields 104 -- references bounded, owned
sub-objects intact.

Residual, accepted with the merge (none blocking):
1. **Baseline still unreconciled.** `STATUS.md` claims 340; this build measures 325 post-change
   (296 pre-change). Bookkeeping in STATUS.md, not a defect in the branch.
2. **The DoCopy guard has no automated check** -- it sits behind a modal dialog. Code inspected
   and correct (canonical-path compare, refuses); needs the manual GUI step in PHASE2-REPORT.
3. **`Scaffold` at 346 s would exceed the new 180 s bound.** Harmless only while it has zero
   callers, which the DocInsight states as an explicit condition. Give it a caller and revisit.
4. Item 1 (`cpBoth` -> `cpWin64`) remains a **refuted-but-applied** change. The code comments and
   the test name say so honestly ("pins the default rather than a truncation claim"), and it was
   re-checked here: the Win32 fragment answers `class not found` for `TcxButton`, so it never
   shadowed anything -- the change is defensive hygiene against first-DB-wins, not a repair.

### What works now, verified read-only with NO re-index

`Vcl.StdCtrls.TEdit` and `cxButtons.TcxButton` return `Name`, `Tag`, `Left`, `Top`, `Width`,
`Height`, `Visible`, `Hint`. FMX-declared leaves went **9179 -> 0** across six sampled roots.
`Vcl.Controls.TControl.Parent` resolves to `Vcl.Controls.TWinControl`, not the FireMonkey homonym.
Index side, measured on a COPY of the library: `unit_uses.target_file_id` fill 41.8% -> 91.0%,
GAINED 41,893 / LOST 0 / CHANGED exactly the 122 known-wrong rows.

**The editor acceptance goal is MET** on `fix/editor-defects`: `Name`, `Tag`, `Left`, `Top` are
emitted by `GetProptree(..., 'published')`, are `IsWritable`, and are accepted by
`ConvRules.Casts.IsCastable` against `Vcl.StdCtrls.TButton` — RefreshPool's exact conditions,
through the real adapter. 16 checks.

## RESUME POINT — the exact next action

### Phase G is COMPLETE (2026-08-02). Two things are waiting on a human.

All 10 tasks of `docs/superpowers/plans/2026-07-30-converter-editor-phase-g.md` are done
and reviewed, on branch `merge/converter-into-main` in
`C:\TEMP\claude\c--Projects-Delphi-RAG-lint\wt-merge-converter`.
**Suite: 543 pass / 0 fail / 0 skip** (baseline entering Phase G was 376).

Delivered: G1 theme (follow the IDE), G2 toolbar, G3 go-to-definition **verified against a
live RAD Studio**, G4 the reusable `#mapping`/`#apply` conditional enum->property DSL
**in the editor only**, G5 Examine harvesting `uses` clauses, G7 the ReFind BDE->FireDAC
corpus **imported as product files** in the new top-level `convrules\` directory.
G6 is deferred by design. **G8 (the DSL design message + human manual) is NOT started and
is the natural next piece of work.**

**HELD FOR A HUMAN -- (1) the deploy.** Task 10 Step 3 (copy `ConvRulesEditor.exe` AND
`drag-lint.exe` + `drag-lint.json` + the three `tree-sitter*.dll` into
`C:\Projects\Delphi-RAG-lint-converter\third_party\dll-win64\`) was deliberately NOT done:
it writes into another checkout and overwrites binaries a human uses. It needs explicit
confirmation. **When it happens, they must go as a PAIR** -- see the gotcha below.

**HELD FOR A HUMAN -- (2) the merge.** `merge/converter-into-main` has not been merged
into `main`.

**Do not push.** `main` is 99 ahead of `origin/main` on purpose: nothing is published until
the converter engine and the editor match and are both tested on several real project forms.
Note this now also covers the imported Embarcadero ReFind files, which ship as product
files in `convrules\` rather than as test data -- revisit licensing before any public release.

### Verified behaviours worth not re-discovering

- **A `TFont` conversion marks nothing when you Examine a real form, and that is CORRECT.**
  Examine scans for DFM blocks whose CLASS is the From class, and `TFont` is never a DFM
  component -- only an inline sub-object of one. Use a From class that really is a
  component (e.g. `Vcl.StdCtrls.TEdit`, or `Abcbtn.TabcToggleBtn` in `VARINSP.dfm`).
- **`drag-lint query --name` is a SUBSTRING match.** A wrong qualified name returns
  **zero** hits rather than an error. `TEditCharCase` is `System.UITypes.TEditCharCase`,
  not `Vcl.StdCtrls.TEditCharCase`.
- **The context bundle does not return implementation bodies** even though
  `impl_start_line`/`impl_end_line` ARE indexed -- logged twice now in
  `C:\Projects\Delphi-RAG-lint\stats\draglint-gaps.log`.

### Still the top ENGINE blocker (unchanged, not part of Phase G)

Multi-`--db` ancestor resolution: `DoPropTree` hands `BuildPropTree` only the first store the
root resolved in, so a real ORM3 form's ancestors — which live in the library index — are
unreachable even with `--db project --db library`. `TcxButton` converges only because it IS in
the library index. Details in item 3 below.

## Then, in order

1. **Phase 3 — records.** Update `docs/converter/STATUS.md` (its NEXT ACTION is **stale**: it still
   says implement the proptree fix on main, which is done and merged). Correct the delivered
   `docs/INBOX-REPLY-proptree-ancestor-scope-2026-07-29.md` in BOTH sibling checkouts: its ACTION 2
   tells the converter team to raise a 30 s watchdog, but `--depth 1 --min-visibility published`
   is the better lever, and Phase 2 measured `TcxButton` at 20.11 s (not the 74-79 s that note
   quotes — a different invocation). Reply to the autodoc group on what we ported.
2. **Reply to the autodoc group with the severity reframing.** Their collision note called our
   `ResolveUnitUseTargets` gap a Critical because "your branch populates the column and makes it
   load-bearing for ancestry". **That premise is false for this codebase and was verified false
   twice**: our `ResolveAncestry` scopes purely textually (`Storage.SQLite.pas:4359`/`:4370`) and
   never reads `target_file_id`. The real consumers are `ResolveHelpers:4516`,
   `GetUnitScopeEdges:1392-1409` -> `CallResolver.pas:308`, and `Report.Deps.pas:334/351/353`. The
   fix was still worth shipping; the severity was not. They also asked us to take their uncommitted
   `build_draglint_win64.bat` patch — **we did** (`f685050`).
3. **Spec the multi-`--db` ancestor resolution.** `DoPropTree` hands `BuildPropTree` only the first
   store the root resolved in, so an ORM3 form's ancestors — which live in the library index — are
   unreachable even with `--db project --db library`. Neither branch fixed it; it needs a
   multi-store id space through `BuildPropTree`/`ClassChain`/`BodyOf`. **This is the remaining
   blocker for converting real project forms** and is why the original reporter's defect 3 is still
   open. Deserves its own spec.

## Gotchas that will bite a cold start

- **`ConvRulesEditor.exe` and `drag-lint.exe` must be deployed AS A PAIR.** Since `849077f` the
  editor passes `--refs-as-leaves` on **every** proptree call, and an engine that does not parse
  that flag treats it as FATAL. The copy sitting in
  `Delphi-RAG-lint-converter\third_party\dll-win64` on 2026-07-30 was from 07-21 and did **not**
  have the flag, so shipping the new editor alone would have been *worse* than the bug it fixes —
  every lookup would die instead of timing out. Check before staging:
  `drag-lint.exe --help | findstr refs-as-leaves`. Stage `ConvRulesEditor.exe`, `drag-lint.exe`,
  `drag-lint.json` and the three `tree-sitter*.dll` together. (Deployed 2026-07-30; the previous
  set is backed up in `_backup-pre-editorfixes-20260730-014808` beside it.)
- **A stale editor binary is the first thing to suspect, not the last.** The 07-28 build predated
  every 07-29 fix, and the checkout it came from (`feat/converter-editor`) contains neither the
  merged proptree repair nor the editor fixes. Symptoms look exactly like an engine bug. Check the
  exe's timestamp against the fix commit dates before debugging anything else.
- **`call <script>.bat` by bare name does not resolve here**, even after `cd /D` into its folder
  (`'x.bat' is not recognized`), and the same applies to running a built `.exe` by bare name
  (exit **9009**). Always use absolute paths in wrapper batches.
- **Something kills `drag-lint.exe` BY IMAGE NAME.** `Stop-Process -Name drag-lint`, `taskkill /F
  /IM` and friends appear in **28 `.md` files (41 occurrences)** here. A by-name kill ignores
  process trees, shows a negative exit with **empty stderr** and no Windows event, and destroyed a
  1.9 GB index rebuild twice. This is the real cause of the long-standing "index --all aborts"
  mystery — it is NOT the agent tool's timeout, and running detached or under Task Scheduler does
  not protect you. The hazard is concurrency: do not run a long index/proptree job while another
  session builds.
- **`C:\Projects\.drag-lint\library-Win32.sqlite` is a ~9.5 MB fragment of a ~1.9 GB index.** It
  answers queries and silently misses almost everything — authoritative for **nothing**. Use
  `library-Win64.sqlite` (1.87 GB, schema 18) and treat it as read-only (`--no-write-back`).
- **Never write into `C:\Projects\Delphi-RAG-lint`** (autodoc group, `feat/autodoc-phase3`, dozens
  of dirty files) **or `C:\Projects\Delphi-RAG-lint-converter`** (`feat/converter-editor`, carries a
  third workstream's uncommitted edits to `ConvRules.Engine.pas` — the same file Phase 2 touches,
  so that workstream will need to reconcile). Reading both is fine and often necessary.
- **`main` is not checked out in any worktree.** It was advanced with `git branch -f` after
  verifying a strict fast-forward, because the standard `git checkout main` would have to happen in
  the autodoc group's dirty checkout.
- **Never swap an older source file into a live worktree** to get an "old build" — an agent did
  that, died mid-run, and left the tree holding pre-branch code. Use an out-of-tree `git worktree`.
- **Suite `-Exe` defaults now work.** `main` stages the tree-sitter companions beside the linked
  exe, so `src\cli\Win64\Debug\drag-lint.exe` starts. Do NOT repoint suites at the staged copy —
  that was tried, reviewed, and rejected.
- `run_string_equality_fp` is **red on `main`** (4/1, its no-store `.scm` check). Pre-existing,
  proved by reproducing it at `f685050`; needs an owner. Three suites (`run_formsmap`, `run_smoke`,
  `run_wiring`) are Win32-only and were never run.

## Where the evidence lives

- SDD ledger for the 15-commit branch, with every task, review verdict, controller ruling and
  parked minor: `C:\TEMP\claude\c--Projects-Delphi-RAG-lint\wt-proptree-ancestor\.superpowers\sdd\2026-07-29-proptree-ancestor-scope\progress.md`
- Pre-change baseline and all measurement captures: `baseline.md` in that same directory.
- Phase 1: `C:\TEMP\claude\c--Projects-Delphi-RAG-lint\wt-engine-fixes\PHASE1-REPORT.md` (72-suite
  table, 1161 pass / 1 pre-existing fail).
- Phase 2: `C:\TEMP\claude\c--Projects-Delphi-RAG-lint\wt-editor-fixes\PHASE2-REPORT.md`.
- Open converter/editor defect list: `C:\TEMP\claude\c--Projects-Delphi-RAG-Lint-Graph\3f1be57a-59d8-4ca3-a470-85ed86beb1a1\scratchpad\converter-open-defects.md`
- ~3.5 GB of reclaimable measurement evidence in `C:\TEMP\claude\draglint-fix\`.

**These paths are under `C:\TEMP` and are scratch.** Everything load-bearing is also in git
(`main` @ `3e47f7a`) and in this file; if TEMP has been cleaned, the branch history plus the two
delivered INBOX notes in the sibling checkouts are the record.
