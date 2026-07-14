# Fresh Compiler Findings Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Keep `compiler_findings` fresh so drag-lint surfaces every DCC hint/warning/error for current source -- including clean/unchanged units whose hints the incremental compile skips.

**Architecture:** Add a per-file compile timestamp (`files.last_compiled_unix`). A new CLI verb `refresh-findings` compares it to the file's save mtime, recompiles stale units (>=2 stale -> full build; 1 stale -> incremental; `--full` forces full), and refreshes `compiler_findings` per file. The IDE plugin spawns the verb debounced on save/idle so the heavy work runs in the Win64 child, not the RAM-constrained 32-bit IDE.

**Tech Stack:** Delphi 13 (Object Pascal), SQLite (FireDAC), msbuild/dcc out-of-process, PowerShell autotest scripts.

## Global Constraints

- Delphi 13 Florence (RAD Studio 37); build via the `delphi-build` skill (rsvars + msbuild, PowerShell `Start-Process -Wait`, read log for `BUILD_EXITCODE=0` + no `[dcc] Error`).
- Strict 7-bit ASCII, CRLF, in all `.pas`. DocInsight `///` comments required on new public methods.
- CLI exe canonical path: `src/cli/Win64/Debug/drag-lint.exe`. Build project: `src/cli/drag-lint.dproj` (Debug, Win64).
- `SCHEMA_VERSION` lives in `src/storage/DRagLint.Storage.Schema.pas` (currently `15`).
- Additive columns are added via `TryExec('ALTER TABLE ... ADD COLUMN ...')` AFTER the main schema transaction in `TSQLiteSymbolStore.Migrate` (see the existing `impl_start_line`/`heritage`/`is_virtual` ALTERs) -- NOT in SCHEMA_DDL.
- Win32 Embarcadero sqlite3.dll is < 3.24: no `ON CONFLICT DO UPDATE`, no `ALTER ... ADD COLUMN IF NOT EXISTS`. Use plain `ALTER TABLE ADD COLUMN` wrapped in `TryExec` (swallows the duplicate-column error on re-migrate).
- Autotest scripts: `tests/autotest/run_*.ps1`, ASCII/CRLF, `Check(name, ok, detail)` helper, exit 0 = PASS. `.ps1` are CRLF in the working tree (`.gitattributes *.ps1 text eol=crlf`).
- TCompilerFinding fields (`DRagLint.Core.Model.pas`): `FileId: Int64; RawPath: string; Code: string; Severity: string; LineNo: Integer; ColNo: Integer; Message: string`.

---

### Task 1: Schema -- add `files.last_compiled_unix` + bump SCHEMA_VERSION

**Files:**
- Modify: `src/storage/DRagLint.Storage.Schema.pas:6` (SCHEMA_VERSION 15 -> 16)
- Modify: `src/storage/DRagLint.Storage.SQLite.pas` (add ALTER in `Migrate`, after the existing additive ALTERs near line 599)
- Test: `tests/autotest/run_fresh_findings.ps1` (created here, extended in later tasks)

**Interfaces:**
- Produces: a `files.last_compiled_unix INTEGER` column (NULL default) on every migrated DB.

- [ ] **Step 1: Write the failing test**

Create `tests/autotest/run_fresh_findings.ps1`:

```powershell
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\drag-lint-fresh-findings"
)
$ErrorActionPreference = 'Stop'
$script:Failed = $false
function Check($n, $ok, $d = '') {
  $s = if ($ok) { 'PASS' } else { 'FAIL' }
  $c = if ($ok) { 'Green' } else { 'Red' }
  Write-Host ("  [{0}] {1} {2}" -f $s, $n, $d) -ForegroundColor $c
  if (-not $ok) { $script:Failed = $true }
}
if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
$Exe = (Resolve-Path $Exe).Path
if (Test-Path $WorkDir) { Remove-Item -Recurse -Force $WorkDir }
New-Item -ItemType Directory $WorkDir | Out-Null
$db = Join-Path $WorkDir 'ff.sqlite'

# Task 1: the schema verb reports the new column exists after a migrate.
# Force a migrate by indexing an empty dir (creates + migrates the db).
$src = Join-Path $WorkDir 'src'; New-Item -ItemType Directory $src | Out-Null
[System.IO.File]::WriteAllText((Join-Path $src 'Empty.pas'),
  "unit Empty;`r`ninterface`r`nimplementation`r`nend.`r`n", [System.Text.Encoding]::ASCII)
& $Exe index $src --db $db | Out-Null
$schema = (& $Exe schema --json --db $db) -join "`n"
Check "files.last_compiled_unix column exists" ($schema -match 'last_compiled_unix') "schema had no such column"

Write-Host ''
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
```

- [ ] **Step 2: Run test to verify it fails**

Run: `pwsh -File tests/autotest/run_fresh_findings.ps1`
Expected: FAIL -- `[FAIL] files.last_compiled_unix column exists` (column not added yet).

- [ ] **Step 3: Bump SCHEMA_VERSION**

In `src/storage/DRagLint.Storage.Schema.pas` line 6, change `SCHEMA_VERSION = 15;` to `SCHEMA_VERSION = 16;`.

- [ ] **Step 4: Add the ALTER in Migrate**

In `src/storage/DRagLint.Storage.SQLite.pas`, in `procedure TSQLiteSymbolStore.Migrate`, immediately after the existing `TryExec('ALTER TABLE refs ADD COLUMN enclosing_symbol_id INTEGER');` block (~line 599), add:

```pascal
  { v16: per-file last-successful-compile timestamp (Unix seconds). NULL = never
    compiled. Additive column; ALTER onto pre-v16 files tables for the same
    reason as the symbols/refs columns above. Read by the freshness engine to
    decide staleness (stale iff last_compiled_unix IS NULL OR < mtime_unix). }
  TryExec('ALTER TABLE files ADD COLUMN last_compiled_unix INTEGER');
```

- [ ] **Step 5: Build the CLI**

Use the `delphi-build` skill: build `src/cli/drag-lint.dproj` (Debug, Win64). Confirm `BUILD_EXITCODE=0`, no `[dcc64 Error]`. Deploy to `src/cli/Win64/Debug/drag-lint.exe` (build output is already there).

- [ ] **Step 6: Run test to verify it passes**

Run: `pwsh -File tests/autotest/run_fresh_findings.ps1`
Expected: PASS -- `[PASS] files.last_compiled_unix column exists`.

- [ ] **Step 7: Commit**

```bash
git add src/storage/DRagLint.Storage.Schema.pas src/storage/DRagLint.Storage.SQLite.pas tests/autotest/run_fresh_findings.ps1
git commit -m "feat(schema): add files.last_compiled_unix (v16) for compiler-finding freshness"
```

---

### Task 2: Store methods -- per-file finding clear + compile-timestamp get/set/stale-query

**Files:**
- Modify: `src/core/DRagLint.Core.Interfaces.pas` (ISymbolStore: add 4 method decls near the existing `ClearCompilerFindings` at line 187)
- Modify: `src/storage/DRagLint.Storage.SQLite.pas` (implement the 4 methods; declare in the class)
- Test: `tests/autotest/run_fresh_findings.ps1` (extend)

**Interfaces:**
- Consumes: `files.last_compiled_unix` (Task 1).
- Produces (ISymbolStore additions):
  - `procedure ClearCompilerFindingsForFile(AFileId: Int64);`
  - `procedure SetFileCompiledAt(AFileId: Int64; AUnix: Int64);`
  - `function GetFileCompiledAt(AFileId: Int64): Int64;` (0 when NULL/absent)
  - `function GetStaleFileIds: TArray<Int64>;` (file_ids where `last_compiled_unix IS NULL OR last_compiled_unix < mtime_unix`, language='pascal')

- [ ] **Step 1: Write the failing test**

Append to `tests/autotest/run_fresh_findings.ps1` (before the final `if ($script:Failed)` block). This drives a hidden test verb added in this task's step 3b:

```powershell
# Task 2: a hidden self-test verb exercises the new store methods on a temp db.
$storeTest = (& $Exe test-store-freshness --db $db) 2>&1 -join "`n"
Check "store-freshness self-test OK" ($LASTEXITCODE -eq 0) "out=$storeTest"
```

- [ ] **Step 2: Run test to verify it fails**

Run: `pwsh -File tests/autotest/run_fresh_findings.ps1`
Expected: FAIL -- `test-store-freshness` is an unknown verb (nonzero exit).

- [ ] **Step 3: Declare the interface methods**

In `src/core/DRagLint.Core.Interfaces.pas`, immediately after line 188 (`procedure InsertCompilerFinding(const AFinding: TCompilerFinding);`) add:

```pascal
    /// <summary>Deletes only the compiler_findings rows for one file, so a
    /// single-unit recompile can replace that file's findings without touching
    /// others. (Whole-DB ClearCompilerFindings is unchanged.)</summary>
    procedure ClearCompilerFindingsForFile(AFileId: Int64);
    /// <summary>Stamps files.last_compiled_unix for one file (Unix seconds).</summary>
    procedure SetFileCompiledAt(AFileId: Int64; AUnix: Int64);
    /// <summary>Returns files.last_compiled_unix for one file, or 0 when NULL.</summary>
    function GetFileCompiledAt(AFileId: Int64): Int64;
    /// <summary>Returns file_ids whose findings are STALE: last_compiled_unix is
    /// NULL or older than mtime_unix. Pascal source files only.</summary>
    function GetStaleFileIds: TArray<Int64>;
```

- [ ] **Step 3b: Implement the methods + a hidden test verb**

In `src/storage/DRagLint.Storage.SQLite.pas`, declare the 4 methods in the class's public section (near `ClearCompilerFindings`), and implement (place after `procedure TSQLiteSymbolStore.ClearCompilerFindings` ~line 2430):

```pascal
procedure TSQLiteSymbolStore.ClearCompilerFindingsForFile(AFileId: Int64);
begin
  FConn.ExecSQL('DELETE FROM compiler_findings WHERE file_id = ?', [AFileId]);
end;

procedure TSQLiteSymbolStore.SetFileCompiledAt(AFileId: Int64; AUnix: Int64);
begin
  FConn.ExecSQL('UPDATE files SET last_compiled_unix = ? WHERE id = ?', [AUnix, AFileId]);
end;

function TSQLiteSymbolStore.GetFileCompiledAt(AFileId: Int64): Int64;
var Q: TFDQuery;
begin
  Result:= 0;
  Q:= TFDQuery.Create(nil);
  try
    Q.Connection:= FConn;
    Q.SQL.Text:= 'SELECT last_compiled_unix FROM files WHERE id = ?';
    Q.Params[0].AsLargeInt:= AFileId;
    Q.Open;
    if (not Q.Eof) and (not Q.Fields[0].IsNull) then Result:= Q.Fields[0].AsLargeInt;
    Q.Close;
  finally
    Q.Free;
  end;
end;

function TSQLiteSymbolStore.GetStaleFileIds: TArray<Int64>;
var Q: TFDQuery; L: TList<Int64>;
begin
  L:= TList<Int64>.Create;
  Q:= TFDQuery.Create(nil);
  try
    Q.Connection:= FConn;
    Q.SQL.Text:=
      'SELECT id FROM files ' +
      'WHERE language = ''pascal'' ' +
      '  AND (last_compiled_unix IS NULL OR last_compiled_unix < mtime_unix)';
    Q.Open;
    while not Q.Eof do begin L.Add(Q.Fields[0].AsLargeInt); Q.Next; end;
    Q.Close;
    Result:= L.ToArray;
  finally
    Q.Free; L.Free;
  end;
end;
```

Add a hidden CLI verb `test-store-freshness` in `src/cli/DRagLint.CLI.pas` (NOT in help text) that: opens the db, migrates, picks any file_id via `GetAllFileIds` (or inserts a temp file row if none), calls `SetFileCompiledAt(fid, 1000)`, asserts `GetFileCompiledAt(fid) = 1000`, inserts a finding then `ClearCompilerFindingsForFile(fid)` and asserts `FindCompilerFindingsForFile(fid)` is empty, and asserts `GetStaleFileIds` returns an array (no crash). Exit 0 on all-pass, 1 otherwise. Wire it into the command dispatch in `Run`.

- [ ] **Step 4: Build the CLI** (delphi-build skill; `BUILD_EXITCODE=0`).

- [ ] **Step 5: Run test to verify it passes**

Run: `pwsh -File tests/autotest/run_fresh_findings.ps1`
Expected: PASS -- both `files.last_compiled_unix` and `store-freshness self-test OK`.

- [ ] **Step 6: Commit**

```bash
git add src/core/DRagLint.Core.Interfaces.pas src/storage/DRagLint.Storage.SQLite.pas src/cli/DRagLint.CLI.pas tests/autotest/run_fresh_findings.ps1
git commit -m "feat(store): per-file finding clear + compile-timestamp get/set/stale-query"
```

---

### Task 3: Full-build mode in CompileCheck

**Files:**
- Modify: `src/diagnostics/DRagLint.Diagnostics.CompileCheck.pas` (add a full-build parameter to `Run`)
- Test: covered indirectly by Task 4's end-to-end test.

**Interfaces:**
- Consumes: nothing new.
- Produces: `TCompileChecker.Run(const ATarget: string; const AFullBuild: Boolean = False; const AMsbuildPath: string = ''; const ARsvarsPath: string = ''): TCompileCheckResult;` -- when `AFullBuild` is True, uses `msbuild /t:Build` (or `dcc -B`) instead of the incremental `/t:Make`.

- [ ] **Step 1: Inspect current Run**

Read `src/diagnostics/DRagLint.Diagnostics.CompileCheck.pas` around lines 203-250. The incremental command is built at ~line 225 (`/t:Make`; `dcc` without `-B`). Confirm the exact command-format lines before editing.

- [ ] **Step 2: Add the AFullBuild parameter**

Change the `Run` declaration (interface ~line 44 and implementation ~line 203) to insert `const AFullBuild: Boolean = False` as the 2nd parameter (keep the existing optional params after it so existing callers -- `DoCompileCheck`, `DoCheckUnit`, ghost-check -- still compile unchanged, since they pass by position only the first arg). In the command-building block, when `AFullBuild` is True use `/t:Build` for the msbuild branch and add `-B` for the dcc branch; otherwise keep `/t:Make` / no `-B`.

```pascal
    if AFullBuild then
    begin
      if AMsbuildPath <> '' then Cmd:= Format('cmd.exe /c "call "%s" && "%s" "%s" /v:normal /t:Build /nologo"', [RsVars, AMsbuildPath, ATarget])
      else Cmd:= Format('cmd.exe /c "call "%s" && msbuild "%s" /v:normal /t:Build /nologo"', [RsVars, ATarget]);
    end
    else
    begin
      // existing incremental /t:Make command (unchanged)
    end;
```

(Mirror the same `-B` toggle for the `dcc64`/`.pas` target branch.)

- [ ] **Step 3: Build the CLI** (delphi-build; `BUILD_EXITCODE=0`). No behavior change for existing callers (they pass `AFullBuild=False` by default).

- [ ] **Step 4: Commit**

```bash
git add src/diagnostics/DRagLint.Diagnostics.CompileCheck.pas
git commit -m "feat(compilecheck): optional full-build (/t:Build, -B) mode"
```

---

### Task 4: `refresh-findings` CLI verb (the freshness engine)

**Files:**
- Modify: `src/cli/DRagLint.CLI.pas` (new `DoRefreshFindings`; wire into `Run`; add to help)
- Test: `tests/autotest/run_fresh_findings.ps1` (extend with a real fixture project)

**Interfaces:**
- Consumes: `GetStaleFileIds`, `ClearCompilerFindingsForFile`, `SetFileCompiledAt`, `GetFilePath`, `GetAllFileIds`, `FindFileIdByPath` (store); `TCompileChecker.Run(..., AFullBuild)`, `InsertFindings` (Task 3).
- Produces: `function DoRefreshFindings(const AArgs: TArgs): Integer;` and the verb
  `drag-lint refresh-findings --project <X.dproj> --db <db> [--platform win32|win64] [--full] [--json]`.

Algorithm (implement exactly):
1. Require `--project` and a readable `--db`; else Usage + Exit(2).
2. Open store, `Migrate`.
3. `Stale := Store.GetStaleFileIds`. If `Length(Stale) = 0` and not `--full`: print "0 stale, up to date" (or `{"mode":"noop","compiled":0}`), Exit(0).
4. `FullBuild := AArgs.Full or (Length(Stale) >= 2)`.
5. `Res := TCompileChecker.Run(AArgs.ProjectPath, FullBuild)`; `Res.Findings := NormalizeFindings(Res.Findings, ExtractFilePath(AArgs.ProjectPath))`.
6. Determine the covered set of file_ids:
   - FullBuild -> every file_id from `Store.GetAllFileIds` whose `GetFilePath` is a `.pas`/`.dpr`/`.dpk` (the whole compile closure is authoritative).
   - Incremental -> `{ the one stale file_id } union { FindFileIdByPath(F.RawPath) for each finding F }`.
7. If the compile FAILED (`Res.ExitCode <> 0` AND there is a Fatal/Error finding): still store findings (so errors show), but do NOT stamp `last_compiled_unix` for files in the covered set (leave them stale to retry). If compile succeeded (ExitCode 0): proceed to stamp.
8. Transactionally, for each covered file_id: `ClearCompilerFindingsForFile(fid)`, insert that file's findings (filter `Res.Findings` by `FindFileIdByPath(F.RawPath) = fid`), and (on success) `SetFileCompiledAt(fid, DateTimeToUnix(Now, False))`.
9. Output text or `--json` summary: mode (`full`|`incremental`|`noop`), stale count, files stamped, findings added. Exit 0 (or 1 if any Error-severity finding survived).

- [ ] **Step 1: Write the failing test**

Append to `tests/autotest/run_fresh_findings.ps1`. Build a tiny fixture project with a deliberate H2219 (a private method declared but never called), index it, then run refresh-findings and assert the hint is stored:

```powershell
# Task 4: end-to-end -- a unit with an unused private method must surface H2219.
$proj = Join-Path $WorkDir 'ffproj'; New-Item -ItemType Directory $proj | Out-Null
$pas = @'
unit UHint;
interface
type
  TThing = class
  private
    procedure NeverCalled;
  public
    procedure DoIt;
  end;
implementation
procedure TThing.NeverCalled; begin end;
procedure TThing.DoIt; begin end;
end.
'@
[System.IO.File]::WriteAllText((Join-Path $proj 'UHint.pas'), ($pas -replace "`r?`n","`r`n"), [System.Text.Encoding]::ASCII)
$dpr = @'
program FFProj;
uses UHint in 'UHint.pas';
begin
end.
'@
[System.IO.File]::WriteAllText((Join-Path $proj 'FFProj.dpr'), ($dpr -replace "`r?`n","`r`n"), [System.Text.Encoding]::ASCII)
# minimal dproj (rtl+vcl only) -- reuse the repro dproj pattern; here dcc on the .dpr suffices:
$db2 = Join-Path $WorkDir 'ff2.sqlite'
& $Exe index $proj --db $db2 | Out-Null
$out = (& $Exe refresh-findings --project (Join-Path $proj 'FFProj.dpr') --db $db2 --json) 2>&1 -join "`n"
Check "refresh-findings exits 0/1 (ran)" ($LASTEXITCODE -le 1) "exit=$LASTEXITCODE out=$out"
# query the stored findings via the schema/compiler_findings (use a hidden dump verb or check-unit)
$dump = (& $Exe query --text "declared but never used" --substring --db $db2) 2>&1 -join "`n"
Check "H2219 stored for the unused private method" ($out -match 'H2219' -or $out -match 'never used' -or $dump -match 'NeverCalled') "out=$out dump=$dump"
```

(If `dcc64` on a bare `.dpr` needs a `.dproj`, generate a minimal one mirroring `docs/examples/devexpress-printer-crash-repro/PrinterCrashRepro.dproj` with only `rtl;vcl` packages. Note in the test which path was taken.)

- [ ] **Step 2: Run test to verify it fails**

Run: `pwsh -File tests/autotest/run_fresh_findings.ps1`
Expected: FAIL -- `refresh-findings` unknown verb.

- [ ] **Step 3: Implement DoRefreshFindings**

Add `function DoRefreshFindings(const AArgs: TArgs): Integer;` to `src/cli/DRagLint.CLI.pas` implementing the algorithm above. Reuse `NormalizeFindings`, `TCompileChecker.Run`, `TCompileChecker.InsertFindings` patterns from `DoCompileCheck` (line 7419). Add a `Full: Boolean` field to `TArgs` and parse `--full` in the arg loop. Add `ProjectPath`/`--project` parsing if not already present (check-unit already parses `--project`). Wire `refresh-findings` into the command dispatch in `Run` and add a help line:

```pascal
  Writeln('  drag-lint refresh-findings --project <X.dproj> --db <db> [--platform win32|win64] [--full] [--json]   (recompile stale units + refresh compiler_findings; >=2 stale -> full build)');
```

- [ ] **Step 4: Build the CLI** (delphi-build; `BUILD_EXITCODE=0`).

- [ ] **Step 5: Run test to verify it passes**

Run: `pwsh -File tests/autotest/run_fresh_findings.ps1`
Expected: PASS -- H2219 (unused private method) is stored.

- [ ] **Step 6: Commit**

```bash
git add src/cli/DRagLint.CLI.pas tests/autotest/run_fresh_findings.ps1
git commit -m "feat(cli): refresh-findings verb -- recompile stale units, refresh compiler_findings"
```

---

### Task 5: Staleness-transition test (incremental vs full)

**Files:**
- Test: `tests/autotest/run_fresh_findings.ps1` (extend)

**Interfaces:**
- Consumes: the `refresh-findings` verb (Task 4).

- [ ] **Step 1: Write the failing/again test**

Append cases that assert the mode decision. After the first refresh (all stale -> full), touch ONE unit and re-run, asserting incremental; touch TWO and assert full. Use the `--json` `mode` field:

```powershell
# Task 5: mode decision. First run above was full (all stale).
# Touch one unit -> exactly 1 stale -> incremental.
Start-Sleep -Milliseconds 1100
(Get-Item (Join-Path $proj 'UHint.pas')).LastWriteTime = Get-Date
& $Exe index $proj --db $db2 | Out-Null   # refresh files.mtime_unix
$m1 = (& $Exe refresh-findings --project (Join-Path $proj 'FFProj.dpr') --db $db2 --json) 2>&1 -join "`n"
Check "1 stale -> incremental mode" ($m1 -match '"mode"\s*:\s*"incremental"') "out=$m1"
# No changes -> noop.
$m2 = (& $Exe refresh-findings --project (Join-Path $proj 'FFProj.dpr') --db $db2 --json) 2>&1 -join "`n"
Check "0 stale -> noop mode" ($m2 -match '"mode"\s*:\s*"noop"') "out=$m2"
```

- [ ] **Step 2: Run test**

Run: `pwsh -File tests/autotest/run_fresh_findings.ps1`
Expected: PASS if Task 4's `--json` emits a `mode` field with `full`/`incremental`/`noop`. If it does not, add the `mode` field to `DoRefreshFindings` JSON output (Task 4 step 3), rebuild, re-run.

- [ ] **Step 3: Commit**

```bash
git add tests/autotest/run_fresh_findings.ps1
git commit -m "test(fresh-findings): incremental vs full vs noop mode decision"
```

---

### Task 6: IDE plugin -- spawn refresh-findings on save/idle + Full Sweep menu

**Files:**
- Modify: `src/delphi-plugin/DragLint.Plugin.Editor.pas` (spawn `refresh-findings` from the existing save/idle hooks; add Full Sweep menu item)
- Modify: `src/delphi-plugin/DragLint.Plugin.LiveDiagnostics.pas` if the spawn helper lives there
- Build: `src/delphi-plugin/dclDragLintWizard.dproj` (Win32 BPL)

**Interfaces:**
- Consumes: the `refresh-findings` verb (Task 4); the existing `DragLintExe` resolver (prefers Win64) and the `CreateProcessW` spawn helper (`Editor.pas:59`).

NOTE: OTA UI is NOT headless-testable. The only automated gate is the BPL compiling. Verification is the live-IDE smoke checklist below.

- [ ] **Step 1: Wire the spawn on save/idle**

In the existing `TriggerCompileOnSave` (`Editor.pas:1706`) and the idle ghost-check path, ADD (or replace, if it supersedes the ad-hoc compile) a spawn of:
`"<DragLintExe>" refresh-findings --project "<activeProjectDproj>" --db "<projectDb>"`
via the existing `CreateProcessW` helper, `CREATE_NO_WINDOW`, non-blocking. Reuse the existing single-in-flight busy guard and the `GHOST_IDLE_MS` debounce -- do NOT add a new timer. Resolve the active project's `.dproj` and its db the same way the current live-diagnostics path does.

- [ ] **Step 2: Add the Full Sweep menu item**

Register a menu item "drag-lint: Full Compile Sweep" alongside the existing drag-lint menu items. Its handler spawns `"<DragLintExe>" refresh-findings --project "<activeProjectDproj>" --db "<projectDb>" --full` (non-blocking, CREATE_NO_WINDOW). Mirror an existing menu-item registration in the plugin for the exact OTA calls.

- [ ] **Step 3: Build the BPL**

Use the `delphi-build` skill on `src/delphi-plugin/dclDragLintWizard.dproj` (Win32). RAD Studio must be CLOSED if the BPL is locked -- if a subagent hits a lock, report BLOCKED (do NOT close the user's IDE). Confirm 0 errors; deploy to `third_party/dll-win32/`.

- [ ] **Step 4: Commit**

```bash
git add src/delphi-plugin/DragLint.Plugin.Editor.pas src/delphi-plugin/DragLint.Plugin.LiveDiagnostics.pas third_party/dll-win32/dclDragLintWizard.bpl
git commit -m "feat(plugin): spawn refresh-findings on save/idle + Full Compile Sweep menu"
```

- [ ] **Step 5: LIVE-IDE SMOKE (user, not headless)**

1. Open a project; edit + save a unit that has an unused private method -> after the idle debounce, the H2219 hint appears in drag-lint's diagnostics (not only Embarcadero's LSP).
2. drag-lint menu -> "Full Compile Sweep" -> runs a full build; hints for ALL units appear.
3. Confirm the 32-bit IDE RAM does not spike (the compile runs in the spawned Win64 child).

---

### Task 7: Docs + battery + final review

**Files:**
- Modify: `docs/AI-USAGE.md` (add the `refresh-findings` row), `README`/`CHANGELOG` as the repo convention.
- Modify: `docs/INDEX-SCHEMA.md` (document `files.last_compiled_unix` + schema_version 16).

- [ ] **Step 1: Docs**

Add to `docs/AI-USAGE.md` verb table:
`| refresh-findings --project X --db D | recompile stale units (mtime > last_compiled) + refresh compiler_findings; >=2 stale -> full build, 1 stale -> incremental, --full forces full; feeds the IDE compiler overlay |`
Update `docs/INDEX-SCHEMA.md`: bump the documented schema_version to 16 and add the `files.last_compiled_unix` column description.

- [ ] **Step 2: Run the convert/compiler test battery for no regression**

Run `tests/autotest/run_fresh_findings.ps1`, plus `run_proptree.ps1`, `run_convert_scaffold.ps1`, `run_convert_rules.ps1` (confirm the schema bump + store changes broke nothing). All exit 0.

- [ ] **Step 3: Commit**

```bash
git add docs/AI-USAGE.md docs/INDEX-SCHEMA.md CHANGELOG.md README.md
git commit -m "docs(fresh-findings): refresh-findings verb + schema v16 (files.last_compiled_unix)"
```

- [ ] **Step 4: Final whole-branch review**

Request a code review of the whole branch (superpowers:requesting-code-review). Focus points: the staleness SQL, the covered-set logic (never stamp a file we did not compile), compile-failure path (errors stored, timestamp NOT stamped), transaction safety of the per-file refresh, ASCII/CRLF, DocInsight on new public methods.
