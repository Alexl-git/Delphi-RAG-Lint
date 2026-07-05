# Win64-by-default + IDE Structure/Encoding Fixes Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Every plugin spawn uses the Win64 drag-lint by default (BPL stays the only 32-bit artifact); the Structure tab shows sorted diagnostics + real code elements; ANSI files with high-bytes index instead of skipping; read verbs never mutate a database. Ships as v0.86.0-alpha.

**Architecture:** One new shared resolver unit consumed by all five plugin spawn sites; parse-tolerant outline capture; a single `EnsureUtf8Bytes` ingest helper used by indexer + parse cache; a read-only mode on `TSQLiteSymbolStore` that skips Migrate and is passed by all query verbs.

**Tech Stack:** Delphi 13 / RAD Studio 37, existing build bats (`build\build_draglint_win32|64.bat`, plugin dproj), PowerShell harnesses under `tests\`.

**Spec:** `docs/superpowers/specs/2026-07-05-win64-default-and-ide-fixes-design.md` -- read it first; it carries the root-cause evidence and the user's policy ruling.

## Global Constraints

- `.pas` strict 7-bit ASCII + CRLF. DocInsight `///` on every new public declaration.
- Build ONLY via wrapper .bat run from PowerShell `Start-Process -Wait` with logs (never Bash-cmd, never MCP build). Plugin BPL builds FAIL with F2039 if RAD Studio is open -- report DONE_WITH_CONCERNS with the lock evidence, never fight it.
- Engine prime directive: refuse/error clearly rather than guess; no silent behavior changes to write verbs.
- The Win32 CLI exe stays built, staged (`third_party\dll-win32\`), and packaged in release zips.
- SDD checkpoint discipline: one implementer at a time; reviewer per task; final whole-branch review BEFORE tag/push/gh-release.

---

### Task 1: Shared exe resolver -- Win64 default (plugin)

**Files:**
- Create: `src/delphi-plugin/DragLint.Plugin.ExeResolver.pas`
- Modify: `src/delphi-plugin/DragLint.Plugin.Editor.pas` (DLExe/DLExe64 bodies -> delegate), `DragLint.Plugin.StructureForm.pas` (ResolveExePath), `DragLint.Plugin.LiveDiagnostics.pas` (~line 664 inline resolution), `DragLint.Plugin.ProjectNotifier.pas` (ResolveExePath), `DragLint.Plugin.Keyboard.pas` (DLExtractMethodExe -> delegate, delete the KEEP-IN-SYNC copy)
- Also add the new unit to `dclDragLintWizard.dpk` contains-list + `.dproj` DCCReference.

**Interfaces:**
- Produces: `function DragLintExe: string;` in the new unit. Resolution order (from the spec, verbatim): settings ExePath override (non-empty + FileExists) -> `<bpl-dir>\..\dll-win64\drag-lint.exe` -> `<bpl-dir>\drag-lint.exe` -> bare `'drag-lint.exe'`.
- The new unit may use `DragLint.Plugin.Settings` (LoadSettings). It must NOT use Editor.pas (avoid cycles).

- [ ] **Step 1: Write the new unit** (complete code):

```pascal
unit DragLint.Plugin.ExeResolver;

{ v0.86 policy (user ruling 2026-07-05): the IDE BPL is the only 32-bit
  artifact; every process the plugin spawns defaults to the Win64 CLI.
  The Win32 sibling next to the BPL is the "just in case" fallback only. }

interface

/// <summary>Resolves the drag-lint CLI exe for ALL plugin spawn sites.</summary>
/// <returns>Full path when a candidate exists; else the bare name
/// 'drag-lint.exe' (resolved via PATH by CreateProcess).</returns>
/// <remarks>Order: 1) Settings ExePath override (set + exists);
/// 2) &lt;bpl-dir&gt;\..\dll-win64\drag-lint.exe (DEFAULT);
/// 3) &lt;bpl-dir&gt;\drag-lint.exe (Win32 fallback); 4) bare name.
/// Thread-safe: pure function over the settings snapshot + file system.</remarks>
function DragLintExe: string;

implementation

uses
  System.SysUtils
  , DragLint.Plugin.Settings
  ;

function DragLintExe: string;
var
  BplDir: string;
begin
  Result:= LoadSettings.ExePath;
  if (Result <> '') and FileExists(Result) then Exit;
  BplDir:= ExtractFilePath(GetModuleName(HInstance));
  Result:= ExtractFilePath(ExcludeTrailingPathDelimiter(BplDir)) + 'dll-win64\drag-lint.exe';
  if FileExists(Result) then Exit;
  Result:= BplDir + 'drag-lint.exe';
  if FileExists(Result) then Exit;
  Result:= 'drag-lint.exe';
end;

end.
```

(Confirm `GetModuleName`/`HInstance` uses match the existing resolvers' uses clauses; mirror them.)

- [ ] **Step 2: Delegate all five call sites.** Replace each resolver BODY with `Result:= DragLintExe;` (keep public names/signatures so call sites don't churn). ProjectNotifier keeps its `ACfgExePath` parameter but ignores it in favor of the shared resolver (its cfg value came from the same Settings). Delete Keyboard's duplicated logic + its KEEP-IN-SYNC comment.
- [ ] **Step 3: Build the plugin package.** `dclDragLintWizard.dproj` Win32 Debug via wrapper bat (Start-Process). Expected `BUILD_EXITCODE=0`.
- [ ] **Step 4: Verification (no IDE available):** grep-sweep proves no remaining `<bpl-dir>\drag-lint.exe`-first resolution: `rg -n "GetModuleName\(HInstance\)" src/delphi-plugin` must show hits only inside `DragLint.Plugin.ExeResolver.pas` (and unrelated non-exe uses, listed in the report).
- [ ] **Step 5: Commit** `feat(ide): shared DragLintExe resolver -- Win64 default for every spawn (policy 2026-07-05)`.

---

### Task 2: Structure tab -- tolerant JSON capture + diagnostics sorted by line

**Files:**
- Modify: `src/delphi-plugin/DragLint.Plugin.StructureCache.pas` (ParseOutlineJson + RunAndCaptureSurface), `src/delphi-plugin/DragLint.Plugin.StructureForm.pas` (BuildTree diag sort)

**Interfaces:** unchanged public surface.

- [ ] **Step 1: Slice before parse.** In `ParseOutlineJson`, before `ParseJSONValue`: take `Copy(AOutput, Pos('[', AOutput), LastDelimiter(']', AOutput) - Pos('[', AOutput) + 1)` guarded by `Pos('[',...) > 0` and `LastDelimiter > Pos`; parse the slice. Add a unit comment citing the win32 preamble/DROP-TRIGGER evidence (spec Finding 1).
- [ ] **Step 2: Separate stderr pipe.** In `RunAndCaptureSurface`, create a second pipe for `SI.hStdError`; drain both (stderr into a small side buffer); on nonzero exit code, `DLT('structure', 'outline stderr: ' + <tail 300 chars>)`. Mirror the two-pipe drain pattern if one exists elsewhere in the plugin (check LspClient); otherwise sequential drain after process exit is acceptable given outline's small stderr.
- [ ] **Step 3: Sort diagnostics by line.** In `BuildTree` before the FDiags loop: stable sort ascending by `D.Line` (e.g. copy FDiags to a local array + `TArray.Sort` with a comparer on Line; ties keep original order -- use an index-decorated sort). Code Elements remain in CLI order.
- [ ] **Step 4: Build plugin (as T1 Step 3), expect exit 0.**
- [ ] **Step 5: CLI-side proof:** run the exact structure command against the WIN32 exe (whose preamble noise reproduces the bug) and pipe through a tiny PowerShell reimplementation of the slice to show the JSON parses; include in report. (Live-IDE check happens in the user smoke at ship.)
- [ ] **Step 6: Commit** `fix(ide): structure outline survives CLI preamble (slice + stderr pipe); diagnostics sorted by line`.

---

### Task 3: EnsureUtf8Bytes ingest transcoding (engine, TDD)

**Files:**
- Create: `src/core/DRagLint.Core.Encoding.pas`
- Modify: `src/core/DRagLint.Core.Indexer.pas` (IndexFile ingest, ~line 240 region), `src/diagnostics/DRagLint.Diagnostics.ParseCache.pas` (its byte ingest, ~line 60 region)
- Test: new fixture dir `tests/lint-store/encoding-ansi-highbytes/` is NOT right (that harness is rule-oriented) -- instead extend `tests/autotest/` with `run_encoding_ingest.ps1` (below).

**Interfaces:**
- Produces: `function EnsureUtf8Bytes(const ABytes: TBytes): TBytes;` in the new unit, per the spec's D3 contract (UTF-8 BOM strip / UTF-16 BOM transcode / valid-UTF-8 passthrough / else CP1252->UTF-8). Sha256 stays over RAW bytes.

- [ ] **Step 1: Write the failing test** `tests/autotest/run_encoding_ingest.ps1`: creates a temp dir with `HighByte.pas` containing (written as BYTES, not text) a unit with `resourcestring C = 'Micronite <0xAE> Copyright<0xA9>';`, runs `drag-lint index <dir> --db <tmp>`, asserts exit 0, output contains `HighByte.pas ->` (indexed, NOT `SKIP`), and `drag-lint query --text "Micronite" --substring --db <tmp>` finds the literal. Also a `Utf16.pas` variant with a UTF-16LE BOM asserting indexed. Run -> expect FAIL (SKIP + EEncodingError today).
- [ ] **Step 2: Implement `EnsureUtf8Bytes`.** Strict UTF-8 validation scan (table-driven continuation-byte walk, NO exception-driven control flow); BOM handling per spec; CP1252 path via `TEncoding.GetEncoding(1252).GetString` -> `TEncoding.UTF8.GetBytes`. DocInsight per spec. Wire into `TIndexer.IndexFile` right after the raw read (raw bytes kept for sha/mtime) and into the ParseCache ingest so lint/check-ast/refactor parses agree. GROUNDING: read both ingest sites first; do not touch the refactor TextEdit applier (it works on original files by design).
- [ ] **Step 3: Run the new test -> PASS; run `run_lint_tests.ps1`, `run_store_tests.ps1`, `run_flowengine_tests.ps1`, `run_extractmethod_unit_tests.ps1` -> all green (byte-identical behavior for pure-ASCII sources).**
- [ ] **Step 4: Real-world proof:** reindex `C:\Projects\DB\ORM3\CLIENT` into a SCRATCH COPY of the per-project DB (do not touch the live one) and assert SOFTWID.PAS shows `-> N symbols` not `SKIP`.
- [ ] **Step 5: Commit** `feat(core): EnsureUtf8Bytes ingest -- ANSI/UTF-16 sources transcode instead of skipping (SOFTWID class)`.

---

### Task 4: Read-only opens for query verbs (engine, TDD)

**Files:**
- Modify: `src/storage/DRagLint.Storage.SQLite.pas` (constructor + Migrate gate + FireDAC OpenMode), `src/cli/DRagLint.CLI.pas` (query-verb store constructions)
- Test: `tests/autotest/run_readonly_verbs.ps1` (new)

**Interfaces:**
- `constructor TSQLiteSymbolStore.Create(const ADbPath: string; AReadOnly: Boolean = False);` -- read-only skips `Migrate` and sets FireDAC `OpenMode=omReadOnly`; adds `function IsSchemaCurrent(out AFound, AExpected: Integer): Boolean` used to emit the actionable stale-schema error (spec D4 wording) from read verbs.
- CLI: outline, query (all forms), find-unit, surface, context, dump-refs open read-only. index/import-log/forms-csv/lint-all unchanged. GROUNDING: enumerate every `TSQLiteSymbolStore.Create` in CLI.pas first and classify read vs write in the report; when unsure, leave as write-mode (safe).

- [ ] **Step 1: Failing test** `run_readonly_verbs.ps1`: build a tiny fixture DB (index 1 file), snapshot the DB file's md5 AND `SELECT COUNT(*) FROM sqlite_master WHERE type='trigger'`; run `outline`, `query --name`, `query --text`, `surface`, `context` against it; assert md5 UNCHANGED after each (today Migrate's stamp/DDL may dirty it -- capture the RED evidence); assert a pre-v13-shaped DB (reuse the make_v12 python from run_migrate_v12.ps1) gets the actionable `index schema v12` message + nonzero exit from `outline`, NOT a field error.
- [ ] **Step 2: Implement.** Read-only constructor path; verb wiring; stale-schema guard message exactly: `index schema v%d < v%d: run "drag-lint index <dir> --db <db>" to migrate`.
- [ ] **Step 3: New test PASS + full battery green** (lint/store/flowengine/extractmethod-unit/e2e/migrate-v12/formsmap -- migrate-v12 MUST stay green: write verbs still migrate).
- [ ] **Step 4: Commit** `feat(storage): read-only store opens for query verbs -- no DDL-on-read (kills win32 trigger drops)`.

---

### Task 5: Ship v0.86.0-alpha

**Files:** `src/cli/DRagLint.CLI.pas:6` (VERSION), `CHANGELOG.md`, tracker note in `docs/lint/BACKLOG.md`.

- [ ] **Step 1:** VERSION `0.85.0-alpha -> 0.86.0-alpha`; CHANGELOG section (summarize D1-D4 from the spec incl. the Structure-tab + SOFTWID fixes and the win32 trigger-drop kill).
- [ ] **Step 2:** Build Win64 + Win32 CLI (both bats -> both staged, so the win32 "just in case" exe is CURRENT); rebuild plugin BPL; run the FULL battery (lint 153 / store 16 / catalog 29 / flowengine / extractmethod unit+e2e / migrate-v12 / formsmap / encoding-ingest / readonly-verbs).
- [ ] **Step 3:** `build\pack-lint-release.ps1 -Version 0.86.0-alpha`; verify zips + `--version` prints.
- [ ] **Step 4:** COMMIT ONLY -- controller runs the final whole-branch review, THEN tag `v0.86.0-alpha` on the reviewed head, push, `gh release create ... --latest` (mirror v0.85 mechanics + notes file).
- [ ] **Step 5:** USER SMOKE (handoff): restart IDE -> Structure tab on BASICSF.pas shows sorted Diagnostics + ~240 Code Elements; run reindex from the IDE -> SOFTWID.PAS indexed (not SKIP); text-search still works after a Structure refresh (triggers intact).

---

## After this milestone

Recommended next refactoring: **Change Signature** (REFACTOR-LIST.md "recommended next") -- new brainstorm -> spec -> plan; reuses rename's cross-unit apply + Extract Method's liveness pass.
