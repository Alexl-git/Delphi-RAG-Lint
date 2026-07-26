# Project coherence -- self-healing reconcile -- Implementation Plan (Phase 1)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax.

> **DESIGN REVISION (2026-07-19, user):** do NOT add a new `reconcile` verb. Fold the
> index/findings-coherence capability into the EXISTING `reconcile-project` verb
> (`DoReconcileProject` / `TProjectReconciler`, which already reconciles the `.dpr`
> member list vs the compile closure). Rationale: both jobs start from the same
> project-member enumeration; a single verb that makes *everything* about the project
> coherent is what was intended, avoids a confusing second `reconcile*` verb, and reuses
> the closure `reconcile-project` already computes. The two phases stay independently
> opt-in so nothing surprising happens:
>
> ```
> reconcile-project <proj>                      -> report only         (today, unchanged)
> reconcile-project <proj> --apply              -> edit the .dpr/.dproj (today, unchanged)
> reconcile-project <proj> --db <db> [--full]   -> heal the DB index+findings  (NEW; never edits the .dpr)
> ```

**Goal:** Guarantee every project member is indexed + compiled + fresh in the drag-lint DB, delivered as a new opt-in **`--db [--full]` phase of the existing `reconcile-project` verb**, so the plugin can heal the LSP's index/findings at project-open and when a not-yet-indexed unit is opened -- fixing the "edited/new unit missing from the LSP's DB -> no diagnostics" bug (VARINSPCODE.pas).

**Architecture:** `reconcile-project` gains a DB-coherence phase. After the existing closure Analyze (Missing/Extra/Stale report; `--apply` edits the `.dpr`), when `--db <db>` is passed it: (1) takes the project-owned compile closure `Analyze` already computed as the member set (+ each unit's sibling `.dfm`); (2) computes per-member coherence vs `<db>` (indexed / index-fresh via mtime TIMESTAMP not sha / compiled-fresh via last_compiled_unix); (3) incrementally scans the missing/stale members (+ `.dfm`) into `<db>`; (4) if any member is incoherent (or `--full`), runs a FULL recompile via the existing refresh-findings compile+capture engine into `<db>`. The `--apply` (edit `.dpr`) phase stays independent and unchanged. Later (Tasks 4-6, deferred) the plugin calls `reconcile-project --project <proj> --db <manifestDb> --full` (NO `--apply`) at project-open + module-added/file-open-not-indexed.

**Tech Stack:** Delphi 13 / RAD Studio 37, Win64 CLI + Win32 design-time BPL. Spec: `docs/superpowers/specs/2026-07-19-project-coherence-reconcile-design.md` (READ IT FIRST -- the invariant + membership + coherence checks; note the spec's "new `reconcile` verb" is superseded by the revision above -- same behavior, folded into `reconcile-project`).

## Global Constraints

- Read the spec first for the invariant, membership definition, and coherence checks. The verb is `reconcile-project` (extended), not a new `reconcile` verb.
- **CLI build:** `build/build_draglint_win64.bat` via PowerShell `Start-Process -Wait` + log; require `EXIT:0`, no `[dcc] Error`. Test target = `src/cli/Win64/Debug/drag-lint.exe` (staged to `third_party/dll-win64/`).
- **Encoding:** all `.pas` strict 7-bit ASCII, CRLF, no BOM. After each Write/Edit re-normalize to CRLF + verify 0 lone-LF / 0 non-ASCII. DocInsight `///` on new public surface.
- **Reuse over rebuild:** the `.dpr` member parse (`TProjectReconciler.CollectDprMembers`) and the compile closure (`TClosureResolver` via `Analyze`) already exist -- surface/reuse them, do NOT write a second `.dpr` parser. The refresh-findings compile+capture core is currently INLINE in `DoRefreshFindings` (CLI ~7605); factor it into a callable helper reused by BOTH `DoRefreshFindings` and the reconcile-project DB phase -- do NOT duplicate the compile logic.
- **DB target rule (binds Tasks 5-6, deferred):** the plugin MUST resolve the `--db` via `ManifestDbForFile` / `ResolveActiveIndexDbs[0]` (the DB the LSP reads) -- never a raw per-project `<proj>.sqlite`. The Phase-1 CLI is `--db`-arg driven (disk/DB based).
- **Autotests:** EXTEND `tests/autotest/run_reconcile.ps1` (it already covers `reconcile-project`) with DB-phase cases -- do NOT create a second file or clobber the existing cases/fixture. Use its Check convention; skip-not-fail when exe/project/DB absent. Known harness quirk: the exe prints `(loaded defaults...)` + `FTS5 probe` to stderr; a runner using `$ErrorActionPreference='Stop'` + `2>&1` aborts on it -- redirect exe stderr to `$null`.
- Commit per task. Do NOT push (user holds push). Do NOT deploy over a running IDE's BPL.

---

### Task 1: Members + closure exposure (pure)

**Files:** Modify `src/index/DRagLint.Index.Reconcile.pas` (surface the closure). Create `src/core/DRagLint.Project.Members.pas` (the member record + `.dfm` pairing). Test: a tiny console harness OR fold into the Task 3 autotest -- but a standalone red->green is preferred (see below).

**Produces:**
- Extend `TReconcileResult` with `ClosureFiles: TArray<string>;` (the project-owned compile closure `Analyze` already computes in `CR.Files` -- just copy it into the result; already library-excluded). Update its DocInsight.
- New unit `DRagLint.Project.Members.pas`:
  - `type TProjectMember = record UnitPath: string; DfmPath: string; HasDfm: Boolean; end;`
  - `function PairDfmSiblings(const AUnitPaths: TArray<string>): TArray<TProjectMember>;` -- for each `.pas` path, set `DfmPath` to the sibling `.dfm` (same base name) when it exists on disk, `HasDfm` accordingly; non-`.pas` entries pass through with `HasDfm=False`. Pure (disk-existence check only). DocInsight on the type + function.

Logic: reuse the EXISTING closure -- do NOT parse the `.dpr` again. `PairDfmSiblings` is the only new parsing-free helper; it just does `.pas`->`.dfm` sibling resolution.

- [ ] Step 1: Write the failing test -- fixture dir with 2 `.pas` (one with a sibling `.dfm`); assert `PairDfmSiblings` returns 2 members, correct abs paths, `HasDfm` true for the one, false for the other. (Console harness under `tests/autotest/fixtures/` mirroring an existing `*Harness.dpr`, built + run; OR fold into Task 3's autotest if a standalone harness is disproportionate -- implementer's call, but TDD red->green must be demonstrated.)
- [ ] Step 2: Run -> fails (unit/function missing).
- [ ] Step 3: Implement `ClosureFiles` exposure + `PairDfmSiblings`.
- [ ] Step 4: Run -> passes.
- [ ] Step 5: Commit.

### Task 2: Coherence delta (members vs DB)

**Files:** Create `src/core/DRagLint.Project.Coherence.pas`; consumes `ISymbolStore` + `TProjectMember`. Add one `ISymbolStore` accessor (mtime by file_id) -- it is MISSING today (`FindFileIdByPath` and `GetFileCompiledAt`/last_compiled_unix already exist; there is no public `mtime_unix` getter).

**Produces:**
- `type TMemberCoherence = record Member: TProjectMember; Indexed, IndexFresh, CompiledFresh: Boolean; end;`
- `function ComputeCoherence(const AStore: ISymbolStore; const AMembers: TArray<TProjectMember>): TArray<TMemberCoherence>;`
- `function IsIncoherent(const AC: TMemberCoherence): Boolean;` (not Indexed OR not IndexFresh OR not CompiledFresh)
- New accessor on `ISymbolStore` + `TSQLiteSymbolStore`: `function GetFileMTime(AFileId: Int64): Int64;` (files.mtime_unix, 0 when NULL/absent) with DocInsight.

Logic per member: `FileId := AStore.FindFileIdByPath(UnitPath)`; `Indexed := FileId > 0`; `IndexFresh := Indexed AND (GetFileMTime(FileId) = diskMTimeUnix(UnitPath))` (timestamp; sha is a fallback tiebreaker only -- not needed here); `CompiledFresh := Indexed AND (GetFileCompiledAt(FileId) >= GetFileMTime(FileId))`. A member with `HasDfm` also treats the `.dfm` as a member for Indexed/IndexFresh (the `.dfm` gets its own coherence via a second `TProjectMember`, OR check both -- keep it simple: the reconcile phase enumerates `.pas` and `.dfm` as separate members to scan; coherence checks a single path per record). Use disk mtime as Unix seconds (match how the indexer stores `mtime_unix`).

- [ ] Step 1: Failing test -- seed a tiny DB (TSQLiteSymbolStore.Create + Migrate + index one fixture file so it has a fresh `files` row) with one member indexed+fresh and one member whose path is absent; assert the absent one `IsIncoherent`, the fresh one not. (Fold into the Task 3 autotest harness, or a small console harness.)
- [ ] Step 2: Run -> fails.
- [ ] Step 3: Implement `GetFileMTime` (interface + SQLite impl, DocInsight) + the Coherence unit.
- [ ] Step 4: Run -> passes.
- [ ] Step 5: Commit.

### Task 3: DB-coherence phase in `reconcile-project`

**Files:** Modify `src/cli/DRagLint.CLI.pas` (`DoReconcileProject` ~12854, usage text ~456, and factor the refresh-findings core out of `DoRefreshFindings` ~7605). `TArgs.DbPath` and `TArgs.Full` already exist (refresh-findings uses them) -- confirm they parse for the `reconcile-project` command; add parsing only if missing.

**Verb (extended):** `drag-lint reconcile-project <proj|--project X> [--apply] [--db <db>] [--full] [--json] [--config <c>]`

Flow (added AFTER the existing Analyze/report/`--apply`): if `AArgs.DbPath <> ''`:
1. Members = `PairDfmSiblings(RR.ClosureFiles)` (project-owned closure + sibling `.dfm`).
2. Open the store on `AArgs.DbPath` (`TSQLiteSymbolStore.Create(db); Migrate`); build a `TIndexer` (same parser set as CLI index sites: DParser + `TDFMParser` + `TFirebirdSqlParser`).
3. `ComputeCoherence(store, members)`; incoherent set = members failing `IsIncoherent`.
4. For each incoherent member: `Indexer.IndexFile(UnitPath)`; if `HasDfm`, `Indexer.IndexFile(DfmPath)`.
5. If any member was incoherent (or `--full`): call the factored refresh-findings core `RefreshProjectFindings(ProjectFile, AArgs.DbPath, AArgs.Full{or True})` -> full recompile + finding capture into `<db>`. Skip-not-fail cleanly when msbuild/project unavailable (mirror `DoRefreshFindings`' existing guard).
6. Extend the summary: text line `coherence: members=N incoherent=M scanned=K recompiled=<bool>`; JSON adds a `"coherence": { "members":N, "incoherent":M, "scanned":K, "recompiled":bool }` object alongside missing/extra/stale.

Refactor: extract the compile+capture body of `DoRefreshFindings` into `function RefreshProjectFindings(const AProjectPath, ADbPath: string; AFull: Boolean): <result/int>;` (a new small helper unit under `src/diagnostics/` or a local function reused by both). `DoRefreshFindings` then calls it. Do NOT duplicate the `TCompileChecker.Run` + `NormalizeFindings` + stamp loop.

- [ ] Step 1: EXTEND `tests/autotest/run_reconcile.ps1` -- add a DB-phase case: fixture `.dpr` + 2 units (one w/ `.dfm`), pre-seed a DB missing one unit; run `reconcile-project --project <fx> --db <db>` (no `--apply`); assert the missing unit (+ its `.dfm`) now has a `files` row (query via Python sqlite3, per convention -- no sqlite3 on PATH), and the summary reports `incoherent>=1`. Assert `--apply` behavior is unchanged (existing cases still pass) and that WITHOUT `--db` the `.dpr` is the only thing that could change. Compile step skip-not-fail when msbuild/project unavailable. Redirect exe stderr to `$null`.
- [ ] Step 2: Run -> fails (DB phase not implemented).
- [ ] Step 3: Implement the factored `RefreshProjectFindings` + the DB phase in `DoReconcileProject` + usage text + DocInsight.
- [ ] Step 4: Build (CLI), run -> passes.
- [ ] Step 5: Commit.

### Task 4 (DEFERRED -- plugin): per-file buffer-change timestamp

**Files:** Modify `src/delphi-plugin/DragLint.Plugin.EditViewNotifier.pas` (`Modified` hook ~170) + a small owner (`GBufferChangeTick: TDictionary<string,Cardinal>` in a shared plugin unit).

**Produces:** `procedure StampBufferChange(const AFile: string);` + `function BufferChangeTick(const AFile: string): Cardinal;`. Call `StampBufferChange(activeFile)` from `EditViewNotifier.Modified`.

- [ ] Deferred to a later session (plugin work; IDE-closed BPL build).

### Task 5 (DEFERRED -- plugin): `RequestProjectReconcile` (coalesced, async)

**Files:** Modify `src/delphi-plugin/DragLint.Plugin.Editor.pas` (near `InvokeReindexProject` ~4292; reuse the R2 job queue). Resolve DB via `ManifestDbForFile`/`ResolveActiveIndexDbs[0]`.

**Produces:** `procedure RequestProjectReconcile(const AProjectPath: string);` -- builds `"<exe>" reconcile-project --project "<proj>" --db "<manifestDb>" --full` (NO `--apply`), enqueues via R2 with `CoalesceKey='reconcile:'+lower(db)`, async, one at a time. Mirror `InvokeReindexProject`'s spawn+capture+marshal-back.

- [ ] Deferred to a later session.

### Task 6 (DEFERRED -- plugin): wire the triggers

**Files:** Modify `src/delphi-plugin/DragLint.Plugin.ProjectNotifier.pas` (`FileNotification`).

- Project open (`.dproj`, ~239): replace `SpawnIndexer(...)` with `RequestProjectReconcile(FileName)`.
- `ofnFileOpened` for a `.pas` (~197): if the file's path is NOT in the manifest DB, call `RequestProjectReconcile(activeProject)`. Debounce so opening many files coalesces.

- [ ] Deferred to a later session.

---

## Self-review notes
- Spec coverage: membership+closure (T1), coherence/timestamp+mtime accessor (T2), DB-phase scan + always-full recompile folded into `reconcile-project` (T3). Buffer-change stamp (T4) + coalesced plugin entry (T5) + triggers/DB-target (T6) = DEFERRED plugin phase. Project-wide multi-buffer ghost-overlay = Phase 2 (out of scope).
- Reuse over rebuild: `.dpr` parse + compile closure (`TProjectReconciler`/`TClosureResolver`), `IndexFile`, refresh-findings engine (factor, don't duplicate), `FindFileIdByPath`/`GetFileCompiledAt`. Only genuinely-new code: `ClosureFiles` exposure, `PairDfmSiblings`, `GetFileMTime`, the Coherence unit, the DB phase.
- The motivating bug is fixed by T3 + the deferred T6 (a not-indexed opened unit -> `reconcile-project --db` -> scanned into the LSP's DB -> findings attach). T1-T3 (CLI) are this session; T4-T6 (plugin) next.

## Execution
Recommended: subagent-driven-development, one task per subagent, review between. This session = Tasks 1-3 (CLI); T3 is the load-bearing fix. Tasks 4-6 (plugin) deferred.
