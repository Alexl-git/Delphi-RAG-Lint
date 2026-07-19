# Project coherence -- self-healing reconcile -- Implementation Plan (Phase 1)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax.

**Goal:** Guarantee every project member is indexed + compiled + fresh by a new `drag-lint reconcile` CLI verb, triggered by the plugin at project-open and when a not-yet-indexed unit is opened/added -- fixing the "edited/new unit missing from the LSP's index -> no diagnostics" bug (VARINSPCODE.pas).

**Architecture:** A headless `reconcile` verb enumerates `.dpr` members (+ `.dfm` siblings), computes the incoherent set vs the DB (timestamp-based), incrementally scans the missing/stale members, and -- if any member is incoherent -- runs a full recompile via the existing refresh-findings engine, all into the manifest DB the LSP reads. The plugin exposes one coalesced `RequestProjectReconcile` and wires it at project-open + module-added/file-open-not-indexed, plus records a per-file buffer-change timestamp.

**Tech Stack:** Delphi 13 / RAD Studio 37, Win64 CLI + Win32 design-time BPL. Spec: `docs/superpowers/specs/2026-07-19-project-coherence-reconcile-design.md` (READ IT FIRST -- it is the source of requirements).

## Global Constraints

- Read the spec first; it holds the exact invariant, membership definition, coherence checks, and Phase-1/2 boundary.
- **CLI build:** `build/build_draglint_win64.bat` via PowerShell `Start-Process -Wait` + log; require `EXIT:0`, no `[dcc] Error`. Test target = `src/cli/Win64/Debug/drag-lint.exe` (staged to `third_party/dll-win64/`).
- **Plugin BPL build:** `src/delphi-plugin/dclDragLintWizard.dproj` Win32, RAD Studio CLOSED (`Get-Process bds` empty), via the plugin `_bpl_build.bat`; BPL/DCP committed separately.
- **Encoding:** all `.pas` strict 7-bit ASCII, CRLF, no BOM. After each Write/Edit re-normalize to CRLF + verify 0 lone-LF / 0 non-ASCII. DocInsight `///` on new public surface.
- **DB target rule:** the plugin MUST resolve the reconcile DB via `ManifestDbForFile` / `ResolveActiveIndexDbs[0]` (the DB the LSP reads) -- never a raw per-project `<proj>.sqlite`.
- **Autotests:** `tests/autotest/run_*.ps1` (Check / GSkip convention; skip-not-fail when exe/project/DB absent). NOTE the known harness quirk: the exe prints `(loaded defaults...)` + `FTS5 probe` to stderr; a runner using `$ErrorActionPreference='Stop'` + `2>&1` aborts on it -- redirect stderr to `$null` or set `Continue` in new runners.
- Commit per task. Do NOT push (user holds push). Do NOT deploy over a running IDE's BPL.

---

### Task 1: Member enumeration from the `.dpr` (pure)

**Files:** Create `src/core/DRagLint.Project.Members.pas`; Test in a new `tests/autotest/run_reconcile.ps1` (or a DUnitX case) driving the CLI diagnostic added in Task 3 -- for Task 1 unit-test via a tiny console harness or fold the assertion into Task 3's autotest.

**Produces:**
- `type TProjectMember = record UnitPath: string; DfmPath: string; HasDfm: Boolean; end;`
- `function EnumerateProjectMembers(const ADprojOrDpr: string): TArray<TProjectMember>;`

Logic: locate the `.dpr` (if given a `.dproj`, use the sibling `.dpr`); parse its uses/`contains` list for `unitname in '<relpath>'` entries; resolve each `<relpath>` to an absolute path against the `.dpr` dir; for each `.pas`, set `DfmPath` to the sibling `.dfm` if it exists on disk. Ignore entries with no `in '<path>'` (RTL/VCL). Robust to `{...}` comments and line breaks in the uses list.

- [ ] Step 1: Write the failing membership test (fixture `.dpr` naming 2 units, one with a `.dfm`; assert 2 members, correct abs paths, `HasDfm` true for the one).
- [ ] Step 2: Run -> fails (unit/function missing).
- [ ] Step 3: Implement `EnumerateProjectMembers` (reuse existing `.dpr`/uses parsing if any exists under `src/core` or `src/index`; grep `uses` / dpr parse first -- prefer reuse over a new parser).
- [ ] Step 4: Run -> passes.
- [ ] Step 5: Commit.

### Task 2: Coherence delta (members vs DB)

**Files:** Create `src/core/DRagLint.Project.Coherence.pas`; consumes `ISymbolStore` + `TProjectMember`.

**Produces:**
- `type TMemberCoherence = record Member: TProjectMember; Indexed, IndexFresh, CompiledFresh: Boolean; end;`
- `function ComputeCoherence(const AStore: ISymbolStore; const AMembers: TArray<TProjectMember>): TArray<TMemberCoherence>;`
- `function IsIncoherent(const AC: TMemberCoherence): Boolean;` (not Indexed OR not IndexFresh OR not CompiledFresh)

Logic per member: `Indexed` = `AStore.FindFileIdByPath(UnitPath) > 0`; `IndexFresh` = stored `mtime_unix` == disk mtime (timestamp); `CompiledFresh` = `last_compiled_unix >= mtime_unix`. Add a store accessor if needed to read `mtime_unix` / `last_compiled_unix` by path (check `ISymbolStore` first -- extend minimally if absent).

- [ ] Step 1: Failing test -- seed a tiny DB with one member indexed+fresh and one absent; assert the absent one is incoherent, the fresh one coherent.
- [ ] Step 2: Run -> fails.
- [ ] Step 3: Implement (+ any minimal `ISymbolStore` accessor with DocInsight).
- [ ] Step 4: Run -> passes.
- [ ] Step 5: Commit.

### Task 3: `reconcile` CLI verb

**Files:** Modify `src/cli/DRagLint.CLI.pas` (TArgs + parse + `DoReconcile` + usage/help + dispatch). Reuse `Indexer.IndexFile` and the refresh-findings compile+capture engine (grep `DoRefreshFindings` -- factor its core into a callable the reconcile verb reuses; do NOT duplicate the compile logic).

**Verb:** `drag-lint reconcile --project <X.dproj> --db <db> [--full] [--json]`

Flow: `EnumerateProjectMembers` -> open the store -> `ComputeCoherence` -> for each incoherent member: `Indexer.IndexFile(UnitPath)` and, if `HasDfm`, `Indexer.IndexFile(DfmPath)` -> if any member incoherent (or `--full`), invoke the refresh-findings-full engine for the project into `<db>` -> print a summary (`members=N incoherent=M scanned=K recompiled=<bool>`), `--json` variant.

- [ ] Step 1: Failing autotest `tests/autotest/run_reconcile.ps1` -- fixture `.dpr` + 2 units (one w/ `.dfm`), pre-seed a DB missing one unit; run `reconcile`; assert the missing unit (+ its `.dfm`) now has a `files` row, and the summary reports `incoherent>=1`. Compile step: skip-not-fail when msbuild/project unavailable (mirror refresh-findings' guard). Redirect exe stderr to `$null` (harness quirk).
- [ ] Step 2: Run -> fails (verb missing).
- [ ] Step 3: Implement `DoReconcile` + args + dispatch + usage/help + DocInsight; factor refresh-findings core if needed.
- [ ] Step 4: Build (CLI), run -> passes.
- [ ] Step 5: Commit.

### Task 4: Plugin -- per-file buffer-change timestamp

**Files:** Modify `src/delphi-plugin/DragLint.Plugin.EditViewNotifier.pas` (`Modified` hook ~line 170) + a small owner (a `GBufferChangeTick: TDictionary<string,Cardinal>` in a shared plugin unit, e.g. Editor or a new `DragLint.Plugin.BufferState.pas`).

**Produces:** `procedure StampBufferChange(const AFile: string);` (sets `GBufferChangeTick[lower(file)] := GetTickCount`) and `function BufferChangeTick(const AFile: string): Cardinal;`. Call `StampBufferChange(activeFile)` from `EditViewNotifier.Modified`.

- [ ] Step 1: (headless-unverifiable UI) -- add the map + functions with DocInsight; a tiny console/DUnitX test of stamp/read round-trip.
- [ ] Step 2-4: Implement; build the BPL (IDE closed); confirm compile EXIT:0.
- [ ] Step 5: Commit (source; BPL in a separate build commit).

### Task 5: Plugin -- `RequestProjectReconcile` (coalesced, async)

**Files:** Modify `src/delphi-plugin/DragLint.Plugin.Editor.pas` (near `InvokeReindexProject` ~4292, reuse the R2 job queue + `jkReindex`-style job; add `jkReconcile` or reuse). Resolve DB via `ManifestDbForFile`/`ResolveActiveIndexDbs[0]`.

**Produces:** `procedure RequestProjectReconcile(const AProjectPath: string);` -- builds `"<exe>" reconcile --project "<proj>" --db "<manifestDb>" --full`, enqueues via R2 with `CoalesceKey='reconcile:'+lower(db)`, async, one at a time (never blocks IDE). Mirror `InvokeReindexProject`'s spawn+capture+marshal-back.

- [ ] Steps 1-5: Implement (reuse existing spawn/queue pattern); build BPL; commit. (Live behavior noted for IDE smoke.)

### Task 6: Plugin -- wire the triggers

**Files:** Modify `src/delphi-plugin/DragLint.Plugin.ProjectNotifier.pas` (`FileNotification`).

- Project open (`.dproj`, ~line 239): replace `SpawnIndexer(...)` with `RequestProjectReconcile(FileName)`.
- `ofnFileOpened` for a `.pas` (~line 197): after registering the save-notifier, if the file's path is NOT in the manifest DB (a cheap `FindFileIdByPath` via a short-lived read-only store, or a lightweight existence check), call `RequestProjectReconcile(activeProject)`. Debounce so opening many files coalesces to one reconcile.

- [ ] Steps 1-5: Implement; build BPL (IDE closed); commit source + a separate BPL build commit. Live-IDE smoke noted (open a new unit -> reconcile fires -> diagnostics appear).

---

## Self-review notes
- Spec coverage: membership (T1), coherence/timestamp (T2), reconcile verb + scan + full recompile (T3), buffer-change stamp (T4), coalesced entry (T5), triggers/DB-target (T6). Buffer-fresh project-wide overlay + extra self-healing callers = Phase 2 (out of scope).
- Reuse over rebuild: `.dpr` parsing, `IndexFile`, refresh-findings engine, R2 queue, `ManifestDbForFile` -- grep first, factor, don't duplicate.
- The motivating bug is fixed by T3+T6 (a not-indexed opened unit -> reconcile -> scanned into the LSP's DB -> findings attach).

## Execution
Recommended: subagent-driven-development, one task per subagent, review between. Tasks 1-3 (CLI) are independent of 4-6 (plugin) and can proceed first; 3 is the load-bearing fix.
