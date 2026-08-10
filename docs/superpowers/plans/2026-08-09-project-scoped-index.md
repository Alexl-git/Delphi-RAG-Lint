# Project-Scoped Indexing Implementation Plan

---

## >>> RESUME POINT -- 2026-08-09 (end of the implementation session)

`main` = **`5429e4a`, 32 commits UNPUSHED** (no consent to push given). Last FULL battery **241/241**
(taken at `982c08c`). **Ledger with every decision, correction and deferred finding:**
`.superpowers/sdd/2026-08-09-project-scoped-index/progress.md` -- gitignored, so read it from disk;
it is the real record, this section is the summary.

### SHIPPED and verified

Tasks 1, 3, 5, 6, 7 complete, each reviewed clean. A project's index is now exactly its compile
closure; `--rebuild`/`--recompile` exist; the manifest carries 29 sections across BOTH platforms;
the IDE menu rebuilds the ACTIVE project into the right DB.

| measured | before | after |
|---|---|---|
| YADF | 228 files (5 `.private` + 57 DelphiAST) | **27** |
| DragLint | 670 files | **147** |
| Loader `.dfm` | **0** | **76** |
| ORM3-Micronite2027 `call_edges` | 0 (crashed) | **25,370** |

### THE NEXT ACTIONS, in order

1. **PHASE 3 / Task 8 -- documentation.** Bigger than originally scoped: four DB names changed and
   the four old DBs have been DELETED, so `C:\Projects\CLAUDE.md`, the auto-memory and ~25 docs name
   files that no longer exist. Start with the CLI usage banner (the only docs inside the binary).
2. **PHASE 4 / Task 9 -- the live runs.** BRANCH FIRST (YADF = git, DataCopy = **hg**); `document
   --apply` REWRITES SOURCE and DataCopy shipped to a tester on 2026-08-07. Rebuild+time -> verify
   scope -> `lint-all` BEFORE -> autodocument -> rebuild+time -> `lint-all` after.
3. **Per-file isolation (USER-APPROVED, and it is the primary fix, not a nicety).** `CLI.pas:1646`
   (the `--project` loop) has NO per-file `try/except`; the folder walk (`Indexer.pas:693`) does.
   That disagreement is what turned a survivable SKIP into a fatal `0xC0000005`.
4. **Split `Walk`'s ~25 branch bodies** (`Parser.Delphi13.pas:1566`) so their locals stop sharing one
   1,776-byte frame. The durable fix, and **the only one that helps the IDE plugin** -- a BPL inherits
   `bds.exe`'s stack, so `{$MAXSTACKSIZE}` cannot reach it. Measure TIME as well as depth:
   `PDFlibStampAnnot.pas` takes 16.75 s for 19 symbols, suggesting super-linear cost.
5. Phase 2: out-of-scope eviction (unlocks a trustworthy `--recompile`), then the
   used-but-not-a-`.dproj`-member warning.

### OPEN QUESTIONS FOR THE USER

- **18 further orphan DBs, ~4.9 GB**, still in `C:\Projects\.drag-lint\` and still reachable by
  auto-select: `projects.sqlite` (1.2 GB), `library.sqlite` (1.0 GB), `active-projects.sqlite`,
  `M2022.sqlite`, `samples.sqlite`, `convrules-worktree.sqlite`, `Delphi-RAG-Lint-Graph.sqlite`
  (newly orphaned BY this conversion), and `library-<non-Win32/64 platforms>` which may be
  legitimate `--scan-libraries-all` output. Four were deleted on the user's instruction; these await
  a decision.
- **`ConvRulesEditor.dpr:77` and `ConvRulesModelTests.dpr:449/752/1145` hardcode the retired ORM3
  union DB path.** The file still exists but is no longer rebuilt, so it will go stale silently.
- **TableTools/OCRPDF project files were chosen by an agent, not supplied** --
  `TableTools370P.dproj`, `MemTableFieldWizard.dproj`, `delphi\OCRPDF.dpr`,
  `TESTER1\TEST_PDFFragments.dproj`. They exist; whether they are the right set is the user's call.

### GOTCHAS THAT WILL BITE A COLD START

- **`run_encoding_guard.ps1` currently FAILS**, on 4 lone-LF `tools/lsp-diag/*.ps1` created 19:33 by
  a CONCURRENT WORKSTREAM. Not this work's; deliberately untouched. The next battery shows a red
  that is not yours.
- **`third_party/dll-win32/dclDragLintWizard.{bpl,dcp}` are MODIFIED and unstaged** -- the Task 5
  build. **The IDE fix is not live until that BPL is installed.** The `dll-win64` pair plus
  `FEATURES.txt` and `PLAN-autodoc-and-backlog-2026-08-06.md` belong to another workstream: never
  commit them.
- Writing `{$MAXSTACKSIZE}` in prose inside a `{ }` comment terminates the comment and breaks the
  build.
- `index --all` RECREATES each section DB every run (`RecreateSectionDb`), so it has never been
  incremental; `--recompile` there warns and is ignored. Replacing it with `ClearAllFiles` is a
  Phase 2 prerequisite and carries the IDE file-handle question with it.
- Do not rebuild the `Library` sections casually: 4.1 GB, unchanged by this work.

---

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A project's index contains exactly that project's compile closure -- nothing loose, nothing archived, nothing from a library -- and can be refreshed incrementally (`--recompile`) or from scratch (`--rebuild`).

**Architecture:** Two independent axes. SCAN TYPE (Project = `.dproj` closure, Library = whole folder tree) is DECLARED by what the target is. MODE (Rebuild / Recompile) is CHOSEN per run. Most of Project scan already exists -- `DRagLint.Index.Closure.TClosureResolver` is already wired into manifest `smClosure` sections. The genuinely new behaviour is **out-of-scope eviction**; the rest is unification, flags, and configuration.

**Tech Stack:** Delphi 13 (Studio 37), Win64 Debug, SQLite/FireDAC store, PowerShell test runners under `tests\`, python for sqlite read-back.

**Spec:** `docs/superpowers/specs/2026-08-09-project-scoped-index-rebuild-recompile-design.md`

## Phasing -- rebuild first, eviction second

Decided 2026-08-09 on the user's observation: **"When we rebuild there is no eviction since we do a
fresh build."** That is correct, and it means a correct index does not have to wait on the hardest
task.

- **Phase 1 (Tasks 1, 3, 5, 6, 7):** rebuild only. Correct by construction -- wipe, then index the
  closure. The IDE's "Reindex project" is a rebuild.
- **Phase 2 (Tasks 2, 4):** eviction, which is what makes `--recompile` trustworthy, and the
  non-member warning. Only after eviction lands does the IDE gain a "Refresh index" item.

**Do not ship "Refresh" before eviction.** A refresh that cannot drop a unit removed from the
`.dproj` is today's defect with a friendlier name.

Rebuild cost, measured 2026-08-09, because "a few seconds" is optimistic for the large ones:
YADF fresh = 10.3s (124 files); Delphi-RAG-lint self-index = **115s** (670 files). ORM3's union DB
is 88 MB against Delphi-RAG-lint's 31 MB -- but split per project, each one is far smaller, which
is what makes rebuild-on-demand viable in the IDE.

**Execute Tasks 1, 3, 6 first. Task 2 and Task 4 are Phase 2 and must not block them.**

## Global Constraints

- **Encoding:** every `.pas` / `.ps1` file is strict 7-bit ASCII with CRLF. Agent tools emit lone LF -- normalise before committing or `tests\autotest\run_encoding_guard.ps1` fails.
- **Build:** 3-line wrapper `.bat` (`rsvars` -> `cd src\cli` -> `msbuild /t:Build /p:Config=Debug /p:Platform=Win64 drag-lint.dproj`), run via PowerShell `Start-Process -Wait`, check `BUILD_EXITCODE=0`, then copy `src\cli\Win64\Debug\drag-lint.exe` over `third_party\dll-win64\drag-lint.exe`. Never `cmd.exe /c build.bat` from the Bash tool -- it hangs. `build.bat` in the repo root is STALE.
- **Rebuild AFTER the last source edit.** `tests\autotest\run_exe_freshness.ps1` fails if the exe is older than any source file -- including a comment-only edit.
- **Battery:** `pwsh -File tests\run_battery.ps1`, ~13 min, currently 237/237. Never rebuild the exe or edit `src\*.pas` mid-battery (several suites compile from source); `.ps1` and docs are fine.
- **FK cascade:** every file-owned table declares `REFERENCES files(id) ON DELETE CASCADE` and `Migrate` sets `PRAGMA foreign_keys = ON`. **`string_literals` must still be DELETEd explicitly first** -- its FTS5 shadow tables sync via `AFTER DELETE` triggers, and SQLite fires triggers for FK-cascaded rows only when `recursive_triggers` is on. Left to the cascade, `query --text` keeps matching deleted source.
- **Narrow, never widen.** A wrong edge/row is worse than a missing one; decline rather than guess.

---

### Task 1: `index --project` uses the compile closure

Today the two project paths disagree. `DRagLint.CLI.pas:1939` resolves the project's SEARCH-PATH FOLDERS (`TProjectResolver.ResolveProjectOnly`) and walks them -- which is why it drags in Spring4D and every loose `.pas` beside the project. The manifest `smClosure` arm (`DRagLint.CLI.pas:1423`) already does the right thing. Unify on the closure.

**Files:**
- Modify: `src/cli/DRagLint.CLI.pas:1924-1945` (the `AArgs.ProjectPath <> ''` index arm)
- Test: `tests/autotest/run_index_project_closure.ps1` (create)

**Interfaces:**
- Consumes: `DRagLint.Index.Closure.TClosureResolver.Create(ALibraryRoots: TArray<string>)`, `.SetPreprocess(AEnabled: Boolean; const AProfile: TDefineProfile)`, `.Resolve(const AProjectFile: string; const AExclude: TArray<string>): TClosureResult`; `TClosureResult.Files: TArray<string>`, `.Warnings: TArray<string>`, `.UsedBy: TArray<string>`; `DRagLint.Project.Resolver.TProjectResolver.ResolveLibraryPaths`.
- Produces: nothing new. Task 2 relies on this arm computing an in-scope file set.

- [ ] **Step 1: Write the failing test**

Create `tests/autotest/run_index_project_closure.ps1`. Fixture layout under `C:\TEMP\draglint_projclosure\`:

```
proj\App.dpr          program App; uses Member1 in 'Member1.pas', Member2 in 'Member2.pas'; begin end.
proj\App.dproj        <DCCReference Include="Member1.pas"/> <DCCReference Include="Member2.pas"/>
proj\Member1.pas      unit Member1; interface uses Member2; implementation end.
proj\Member2.pas      unit Member2; interface implementation end.
proj\Member1.dfm      (a form resource beside Member1.pas)
proj\Loose.pas        unit Loose; interface implementation end.     <- referenced by NOTHING
```

**CORRECTION added 2026-08-09 after the first implementation round.** This task's original fixture had no `.dfm`, and that omission was a plan defect, not an implementer one. `TClosureResolver` returns `.pas`/`.inc` only, so a literal switch to the closure DROPS EVERY FORM. Verified on the only closure-built DB in existence: `Loader.sqlite` = 84 files, **dfm 0, dpr 0**, against folder-built `DataCopy.sqlite` and `TableTools.sqlite` carrying 2 `.dfm` each. Task 6 converts ORM3, DataCopy and YADF -- VCL apps full of forms -- so this would have silently zeroed the wizard structure view, DFM event wiring and forms-csv for all of them.

Required in BOTH arms (standalone `--project` and the manifest `smClosure` arm), or the two paths re-split, which is what this task exists to prevent:
- each closure `.pas`'s **sibling `.dfm`**, when it exists;
- the **project file itself** (`.dpr` / `.dproj`) -- every `unit-not-in-dpr` finding anchors to it, never to the offending unit.

Note the gap was PRE-EXISTING in the manifest arm; `index --project` did not introduce it, it would have spread it.

Index with `index --project <proj\App.dproj> --db <db>` and assert via python over `files`:

```
Member1.pas present ; Member2.pas present ; App.dpr present
Loose.pas ABSENT      <- the assertion that fails today
```

- [ ] **Step 2: Run it and watch it fail**

`pwsh -NoProfile -File tests\autotest\run_index_project_closure.ps1`
Expected: FAIL on "Loose.pas ABSENT" -- the folder walk picks it up.

- [ ] **Step 3: Replace the folder walk with the closure**

In the `AArgs.ProjectPath <> ''` arm, drop `Resolver.ResolveProjectOnly` + folder walk and mirror the `smClosure` arm: build `TProjectResolver`, `TClosureResolver.Create(Resolver.ResolveLibraryPaths)`, `Cl.SetPreprocess(APreprocess, ResolveIndexProfile(AArgs.ProjectPath, ...))`, `CR := Cl.Resolve(AArgs.ProjectPath, ExcludePatterns)`, print `CR.Warnings`, then `Indexer.IndexFile(F)` for each `CR.Files` entry.

- [ ] **Step 4: Add the fail-loudly guard**

A missing or malformed `.dproj` must NOT fall back to a folder walk -- that is the whole defect returning. `TFile.Exists` already exits 2 at line 1845; additionally, when `Cl.Resolve` returns zero `Files`, write an error naming the project and `Exit(2)` rather than producing an empty index. A linter or doc run over an empty index reports a clean bill of health, which is the most dangerous failure available to it.

- [ ] **Step 5: Add the guard's test**

Append to the runner: point `--project` at a `.dproj` containing no `DCCReference` and no resolvable `.dpr`; assert exit code 2 and that the DB has no `files` rows.

- [ ] **Step 6: Build, deploy, run**

Build per Global Constraints, copy the exe, re-run the runner. Expected: all PASS.

- [ ] **Step 7: Commit**

```bash
git add src/cli/DRagLint.CLI.pas tests/autotest/run_index_project_closure.ps1
git commit -m "fix(index): index --project resolves the COMPILE CLOSURE, not search-path folders"
```

---

### Task 2: out-of-scope eviction

The load-bearing new behaviour. Prune-by-default deletes files that vanished from DISK; nothing deletes a file that still exists and is no longer in scope. This is why YADF's 5 `.private\` copies and 104 `C:\Projects\DelphiAST\` files survive every reindex.

**Files:**
- Modify: `src/core/DRagLint.Core.Interfaces.pas` (near `PruneMissingFiles`, line ~122)
- Modify: `src/storage/DRagLint.Storage.SQLite.pas` (beside `PruneMissingFiles`, line ~220 decl / ~868-941 impl -- reuse its cascade + `string_literals` handling verbatim)
- Modify: `src/cli/DRagLint.CLI.pas` (both project arms: standalone ~1924, manifest `smClosure` ~1423)
- Test: `tests/autotest/run_index_scope_eviction.ps1` (create)

**Interfaces:**
- Produces: `ISymbolStore.EvictOutOfScopeFiles(const ARoots, AInScopeAbsPaths: TArray<string>): TArray<string>` -- deletes every indexed file under `ARoots` whose absolute path is not in `AInScopeAbsPaths`; returns the removed paths. Task 3 calls it too.

- [ ] **Step 1: Write the failing test**

`tests/autotest/run_index_scope_eviction.ps1`. Reuse Task 1's fixture shape. Sequence:

```
1. index --project App.dproj --db db          -> Member1, Member2 present
2. rewrite App.dproj/App.dpr dropping Member2 (LEAVE Member2.pas ON DISK)
3. index --project App.dproj --db db          (recompile)
4. assert: Member2.pas has NO files row, and NO symbols rows
5. assert: Member1.pas untouched
```

Step 4 is the point: prune cannot catch this, because the file still exists.

Second half -- eviction is SCOPED. Two projects, `ProjA.dproj` and `ProjB.dproj`, into **separate DBs**; recompile A; assert B's DB is byte-for-byte unaffected (compare `SELECT COUNT(*) FROM files` and the sorted path list before/after).

- [ ] **Step 2: Run it and watch it fail**

Expected: FAIL at step 4 -- `Member2.pas` still has rows.

- [ ] **Step 3: Add `EvictOutOfScopeFiles` to the store**

Model it on `PruneMissingFiles`: absolutize roots; folder roots get a trailing separator so `App` cannot swallow `AppTools`; a root naming a single FILE matches whole, not as a prefix. Compare paths case-insensitively (`files.path` casing was B6). Delete `string_literals` for the doomed ids FIRST, then `DELETE FROM files WHERE id IN (...)` and let the cascade take symbols/refs/uses/docs.

- [ ] **Step 4: Call it from both project arms**

After the walk and **BEFORE the resolve passes** -- the same ordering `PruneMissingFiles` uses, so uses/ancestry/call edges are recomputed against the survivors. In-scope set = `CR.Files`. Roots = the project file's directory tree, i.e. the directories of the closure files.

- [ ] **Step 5: Report what was evicted**

Print a count plus paths, the way prune reports vanished files. A corpus that has been quietly wrong for months must announce itself once.

- [ ] **Step 6: Wire eviction into LIBRARY scan too**

Same store method, different in-scope set. For a library scan the in-scope set is the walked tree minus the section's `exclude` globs, so **adding an `exclude` removes what it now covers** instead of leaving it indexed forever. The `Library` section already excludes `SourceD3`, `Delphi5`, `Delphi7`, `BuildD3`... -- everything indexed before those excludes existed is still in there. Same defect as `.private`, other scan type.

Add to the runner: index a folder of 3 units, add an `exclude` glob covering one, recompile, assert its rows are gone and the other two survive.

- [ ] **Step 7: Build, deploy, run**

Expected: all PASS -- project eviction, the scoping half, and library eviction.

- [ ] **Step 8: Commit**

```bash
git add src/core/DRagLint.Core.Interfaces.pas src/storage/DRagLint.Storage.SQLite.pas src/cli/DRagLint.CLI.pas tests/autotest/run_index_scope_eviction.ps1
git commit -m "feat(index): evict indexed files that are no longer in scope"
```

---

### Task 3: `--rebuild` / `--recompile`

**Files:**
- Modify: `src/cli/DRagLint.CLI.pas` (arg parsing ~line 715; index execution)
- Modify: `src/storage/DRagLint.Storage.SQLite.pas` (add `ClearAllFiles`)
- Test: `tests/autotest/run_index_rebuild_recompile.ps1` (create)

**Interfaces:**
- Consumes: `EvictOutOfScopeFiles` (Task 2).
- Produces: `ISymbolStore.ClearAllFiles: Integer` -- deletes every `files` row (and cascade) in the DB, returns the count. CLI args `--rebuild` and `--recompile`.

- [ ] **Step 1: Write the failing test**

`tests/autotest/run_index_rebuild_recompile.ps1`. The claim the design rests on is **convergence**, asserted for BOTH scan types because the axes are independent and a bug could hit only one pairing:

```
Project scan: index --project P --rebuild   -> snapshot A (sorted files+symbol counts)
              index --project P --recompile -> snapshot B      assert A == B
Library scan: index <folder> --rebuild      -> snapshot C
              index <folder> --recompile    -> snapshot D      assert C == D
Also: --rebuild on a DB polluted with an out-of-scope file removes it.
```

- [ ] **Step 2: Run it and watch it fail**

Expected: FAIL -- `Unknown argument: --rebuild`.

- [ ] **Step 3: Parse the flags**

Beside the existing `--force-reparse` handling (~line 715). `--recompile` is the default and may be passed explicitly. `--rebuild` implies force-reparse (the DB is empty afterwards, so every file is new anyway -- setting it keeps the fingerprint gate honest).

- [ ] **Step 4: Implement `ClearAllFiles`**

Delete rows, **not the file** -- the schema, its migrations and settings survive, and no file handle is dropped, which matters because the IDE plugin may hold the DB open. Same `string_literals`-first ordering as Task 2.

- [ ] **Step 5: Wire `--rebuild` into every index form**

Call `ClearAllFiles` after the store opens and before the walk, for project AND library scans.

- [ ] **Step 6: Build, deploy, run**

- [ ] **Step 7: Commit**

```bash
git add src/cli/DRagLint.CLI.pas src/storage/DRagLint.Storage.SQLite.pas tests/autotest/run_index_rebuild_recompile.ps1
git commit -m "feat(index): --rebuild / --recompile as an explicit mode axis"
```

---

### Task 4: "used but not a project member" diagnostic

A unit reached via `uses`, resolving project-local, that is NOT in the `.dproj` member list, is still compiled by Delphi -- so it is INDEXED -- and reported, because "forgotten from the .dproj" is what it usually means.

**Files:**
- Modify: `src/index/DRagLint.Index.Closure.pas` (`TClosureResult`, `Resolve`)
- Modify: `src/cli/DRagLint.CLI.pas` (both project arms)
- Test: `tests/autotest/run_index_nonmember_warning.ps1` (create)

**Interfaces:**
- Produces: `TClosureResult.NonMembers: TArray<string>` -- closure files reached only transitively, absent from the `.dproj` `DCCReference` list and from the `.dpr` uses clause.

- [ ] **Step 1: Check for an existing rule FIRST**

`lint --project` already offers `unit-not-in-dpr` (`DRagLint.Lint.ProjectChecks.TProjectChecks.CheckUnitsInDpr`, called at `DRagLint.CLI.pas:5944`). Read it. **If it already reports this exact condition, wire it in and do NOT add a second rule** -- two rules disagreeing about membership is worse than none.

- [ ] **Step 2: Write the failing test**

Fixture: `App.dproj` lists `Member1.pas` only; `Member1` does `uses Forgotten;` and `Forgotten.pas` sits on the search path. Assert: `Forgotten.pas` IS indexed (it compiles), AND the index run's stderr/stdout names it as a non-member warning.

- [ ] **Step 3: Run it and watch it fail**

Expected: FAIL -- the file is indexed silently, no warning.

- [ ] **Step 4: Populate `NonMembers`**

`Resolve` already seeds from the member list (`UsedBy[i] = '<project>'` for direct members) and records the using-unit for everything else. `NonMembers` = files whose `UsedBy` is not `'<project>'`. No new traversal.

- [ ] **Step 5: Report at index time**

Count plus unit names, severity **warning** -- the code compiles, and the fix is a project-file edit, not a code change.

- [ ] **Step 6: Build, deploy, run. Step 7: Commit**

```bash
git commit -m "feat(index): warn when a compiled unit is not a .dproj member"
```

---

### Task 5: IDE menu -- "Reindex project" is a REBUILD

**DROPPED from this plan: the `group` field and `resolve-dbs --group`.** `resolve-dbs --platform
Win64` already prints every configured DB one per line, and every consumer already accepts repeated
`--db`, so discovery exists. Naming ORM3's sections `ORM3-<Project>` (Task 6) carries the grouping
in the filenames instead. See the spec's "Cross-project search" section.

**Files:**
- Modify: `src/delphi-plugin/` -- the menu action that currently triggers a reindex
- Manual verification only (a design-time BPL cannot be exercised headlessly)

**Interfaces:**
- Consumes: `--rebuild` (Task 3).

- [ ] **Step 1: Find the existing reindex menu action.** `DragLint.Plugin.DbResolver` already resolves the DB from `ProjGroup.ActiveProject` (`GetActiveProjectFilePath`, line ~198/214), so "it must work on whichever ORM3 project is active" is ALREADY satisfied -- activating a different project already selects a different DB. Do not rebuild that; only change what the action passes.
- [ ] **Step 2: Pass `--rebuild`** on the "Reindex project" action, and pass the ACTIVE project's `.dproj` as `--project`.
- [ ] **Step 3: Do NOT add a "Refresh index" item yet.** It is a recompile, and recompile without eviction (Phase 2) cannot drop a unit removed from the `.dproj` -- i.e. it would ship today's defect under a friendlier name.
- [ ] **Step 4: BUILD REQUIRES THE IDE CLOSED.** The design-time BPL is loaded by the running IDE; building it with the IDE open fails on a locked output. Confirm with the user before starting, and follow `C:\Projects\Delphi_IDE_OptionsPage_HOWTO.md`.
- [ ] **Step 5: Commit.**

```bash
git commit -m "feat(plugin): Reindex project performs a full rebuild of the active project"
```

---

### Task 6: convert the manifest sections to Project scan

Configuration, not code -- Task 1-4 made it correct; this makes it apply.

**Files:**
- Modify: `third_party/dll-win64/drag-lint.json`

- [ ] **Step 1: Snapshot the current state.** For each affected DB record `SELECT COUNT(*) FROM files` and the sorted path list into `C:\TEMP\` so the conversion's effect is measurable, not asserted.
**Why this is a conversion and not a re-listing of folders:** ORM3's code spans CLIENT, SERVER, COMMON, OBJECTS and "maybe some more added in the future". A project scan never enumerates folders -- `TClosureResolver` follows `uses` across the project's search paths, so COMMON/OBJECTS arrive because CLIENT's units use them, and a shared folder added later is picked up with **no manifest change**. The current folder root has to be told where to look, which is why it also swallowed everything else living under the tree.

- [ ] **Step 2: Convert ORM3 into 8 project sections**, each named **`ORM3-<Project>`** so the DB filename carries the grouping (`ORM3-Micronite2027.sqlite`, ...). Without the prefix, `Interfaces.sqlite` sits in a flat folder shared with every other project and the name-based lookup this design relies on becomes ambiguous. `include` names one `.dproj` each: `CLIENT\Micronite2027.dproj`, `SERVER\MicroniteMW1Service.dproj`, `PACKAGE\Interfaces.dproj`, `PACKAGE\TestMicroniteObjects.dproj`, `TESTER\Tests\MicroniteTests.dproj`, `TESTER\CachedUpdates\TestCachedUpdates.dproj`, `TESTER\PdfOcrImport\PdfOcrImportTests.dproj`, `TESTER\TEST_uSetupDefaultsFrm\TEST_uSetupDefaultsFrm.dproj`. **Keep the existing union `drag-lint.sqlite` section for now** -- it is retired in Task 7, after verification.
- [ ] **Step 3: Convert DragLint, DataCopy, TableTools, OCRPDF** to `.dproj` includes, same `<Repo>-<Project>` naming where a repo has several. `DragLint` -> `src\cli\drag-lint.dproj`, plus separate sections for the wizard `.dpk`, `tests\StorageHelperEdgesTests.dpr` and `tools\corpusscan\CorpusScanDelphi.dpr`.
- [ ] **Step 4: Leave `Library` and `SQL` as Library-scan sections.** They already are; no edit.
- [ ] **Step 5: `index --all --dry-run --json`** and diff against Step 1's snapshot. Confirm every section reports `"mode":"closure"` except `Library`/`SQL`.
- [ ] **Step 6: Commit** the manifest with the before/after file counts in the message.

---

### Task 7: reindex, verify, and update the references

- [ ] **Step 1: Full battery.** `pwsh -File tests\run_battery.ps1`. Must be green (237 + the 5 new runners = 242) before anything is reindexed.
- [ ] **Step 2: Ask the user to close the IDE.** The design-time BPL holds the DBs open; a reindex will fail with "used by another process". Kill orphaned `drag-lint.exe` / `drag_lint_graph.exe` if it still errors.
- [ ] **Step 3: Reindex `--rebuild`** -- Delphi-RAG-lint, YADF, DataCopy, then the ORM3 group.
- [ ] **Step 4: Verify each.** Assert `.private`, `Backup-*` and cross-repo paths are gone; spot-check a known symbol resolves in each new DB; run `lint-all` on one and compare the finding count to Step 1's snapshot.
- [ ] **Step 5: Update the references BEFORE retiring the union DB.** `C:\Projects\CLAUDE.md` names `C:\Projects\DB\ORM3\drag-lint.sqlite` as the canonical ORM3 index, and the auto-memory references it. Update both to the group form. A half-migrated state where the docs name a DB that no longer exists is worse than either end state.
- [ ] **Step 6: Retire the ORM3 union section** and commit.
- [ ] **Step 7: Tell the user the IDE is safe to start.**

---

### Task 8 (PHASE 3): update every place the old flags and DB paths are documented

Added 2026-08-09 on the user's instruction: *"we changed the parameters flags and meanings, so we need to update AI instructions and user instructions and make all the necessary documentation updates."*

**This is not tidying.** `C:\Projects\CLAUDE.md` names `C:\Projects\DB\ORM3\drag-lint.sqlite` as the canonical ORM3 index; after Task 7 that file is gone. Documentation that names a DB which no longer exists actively misleads every future session -- which is exactly the failure Task 7 Step 5 is ordered to prevent.

**Files:**
- Modify: `src/cli/DRagLint.CLI.pas` -- the `index` usage banner (in-product documentation; it currently documents `--force-reparse` and prune-by-default and says nothing about scan types or modes)
- Modify: `C:\Projects\CLAUDE.md` -- the drag-lint section: index verbs, the ORM3 DB set, project-vs-library scan, `resolve-dbs`
- Modify: `README.md`, `INSTALL.md`, `AGENT_USAGE_NOTES.md`, `CHANGELOG.md`
- Modify: `docs/AI-INDEX-FIRST.md`, `docs/AI-USAGE.md`
- Review: `docs/FIX-2026-08-03-index-project-scope.md` -- may be superseded; if so say so in it rather than deleting it
- Modify: `C:\Users\alexanderl\.claude\projects\c--Projects-Delphi-RAG-lint\memory\MEMORY.md` and `project_lint_rules_v062.md` / `project_draglint_formscsv.md` where they name the ORM3 union DB

- [ ] **Step 1: Find every mention, do not guess at the list.** `grep -rln "drag-lint index\|--force-reparse\|resolve-dbs\|ORM3\\\\drag-lint.sqlite\|DB\\\\ORM3\\\\drag-lint" --include=*.md .` plus the CLI usage banner. Record the hit list in the ledger so the review can check coverage against it.
- [ ] **Step 2: Update the CLI usage banner FIRST.** It is what a user sees with no docs at all, and it is the only one that ships inside the binary. Document: scan type is declared by the target (`.dproj` -> project, folder -> library), mode is `--rebuild` / `--recompile` (default), and that a project scan indexes the compile closure and NOTHING else.
- [ ] **Step 3: Update the AI instructions** (`C:\Projects\CLAUDE.md`, `docs/AI-INDEX-FIRST.md`, `docs/AI-USAGE.md`, `AGENT_USAGE_NOTES.md`). The ORM3 entry must list the eight `ORM3-*` DBs and say that a cross-project question needs several `--db` flags, discoverable via `resolve-dbs --platform <p>`.
- [ ] **Step 4: Update the user instructions** (`README.md`, `INSTALL.md`) and add a `CHANGELOG.md` entry.
- [ ] **Step 5: Update the auto-memory** so a future session does not resume against a retired DB path.
- [ ] **Step 6: Re-run the Step 1 greps** and confirm zero stale hits remain. Commit.

---

### Task 9 (PHASE 4): the live runs -- rebuild, autodocument, rebuild, lint

Ordered by the user 2026-08-09. **See the standing-order note below before starting.**

- [ ] **Step 1: BRANCH FIRST, both repos.** YADF is git (`git checkout -b index-scope-autodoc`); DataCopy is **Mercurial** (`hg branch` or a bookmark). `document --apply` REWRITES SOURCE FILES. DataCopy was shipped to a tester on 2026-08-07 -- an unbranched run there is not recoverable by "undo".
- [ ] **Step 2: Rebuild each index, WITH TIMING** -- YADF, DataCopy, Delphi-RAG-lint. Record wall-clock, file count, symbol count per project into the ledger. Baselines already measured 2026-08-09: YADF fresh 10.3s / 124 files; Delphi-RAG-lint 115s / 670 files (as a folder root -- the project-scan number will differ and that difference is the point).
- [ ] **Step 3: Verify scope before trusting anything downstream.** Assert `.private\`, `Backup-*` and cross-repo paths (`C:\Projects\DelphiAST\`) are ABSENT. YADF's accumulated DB held 228 files against 124 real ones; if that is not fixed here, every number after it is measured on the wrong corpus.
- [ ] **Step 4: `lint-all` BEFORE autodoc** on YADF and DataCopy, and record the finding counts. Without a before, the after means nothing.
- [ ] **Step 5: Autodocument** YADF and DataCopy (`document --project <dproj> --apply`), committing on the branch.
- [ ] **Step 6: Rebuild each index again, WITH TIMING**, and compare against Step 2. Autodoc adds `///` comments, so files grow -- this measures what that costs.
- [ ] **Step 7: `lint-all` again** and diff against Step 4. Report false positives, missing findings, and whether the generated docs are worth keeping.

---

## Not in scope

Option 4 (bare cross-unit calls, 167 resolvable), intrinsics classification, the five approved doc features and the final remeasure remain queued in `docs/lint/PLAN-autodoc-phaseC-2026-08-09.md`.

**STANDING-ORDER CONFLICT, recorded rather than silently resolved.** The user instructed TWICE that the YADF/DataCopy live runs wait until all autodoc work is finished -- *"YADF and DataCopy will wait until all features are polished and working to the best of our knowledge."* None of the four queued items above is done. Task 9 nevertheless runs those projects, on the user's later and explicit instruction. The consequence to expect: the autodoc output will NOT include the five approved doc features (`<exception cref>`, `<value>`, ownership notes, recursion notes, `<seealso>` by default), so a doc-quality review of the result is judging an engine that is knowingly incomplete. Branching (Step 1) is what keeps that reversible.
