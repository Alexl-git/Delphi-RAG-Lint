# Project `_D-RAG` Home and Declared Lint Ownership -- Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give every Delphi project's drag-lint index a home in a `_D-RAG` folder beside its project file, and stop `lint-all` reporting findings in third-party code that the project merely compiles.

**Architecture:** Two layers. (1) `ExpandSectionDb` in the manifest derives a project section's DB path as `<project folder>\_D-RAG\<project file base>.sqlite` when the section declares no `db`; a `migrate-dbs` verb moves the 27 existing DBs there. (2) A new `DRagLint.Project.OwnRoots` unit answers "is this file ours?" from `<project folder>\_D-RAG\drag-lint-project.json`, defaulting to the project's own folder, and `DoLintAll` filters both its per-file scan and its project-wide findings through it.

**Tech Stack:** Delphi 13 Florence (RAD Studio 37.0), Object Pascal, FireDAC + SQLite, PowerShell test battery (`tests\run_battery.ps1`, auto-discovers `run_*.ps1`).

**Spec:** `docs\superpowers\specs\2026-08-11-project-drag-lint-home-and-lint-ownership-design.md` (commit `06f9267`).

## Global Constraints

- **Encoding:** every `.pas` file is strict 7-bit ASCII, CRLF line endings, no BOM. The Write tool emits LF -- byte-check every Delphi file after writing (`python -c "d=open(p,'rb').read(); print(d.count(b'\n')-d.count(b'\r\n'))"` must print `0`).
- **Doc comments:** every new public type, function and method carries a DocInsight `///` comment with `<summary>`, `<param>`, `<returns>` and a `<remarks>` covering ownership/thread-safety where non-obvious. The doc-comment and the test must agree.
- **Build:** use the `delphi-build` skill's recipe (3-line wrapper `.bat` -> `Start-Process -Wait` -> read the log for `BUILD_EXITCODE=0` and no `[dcc] Error`). Never `cmd.exe /c build.bat` from the Bash tool; never the MCP build tool.
- **Exe under test:** `src\cli\Win64\Debug\drag-lint.exe`. Battery helper `tests\autotest\_manifest_common.ps1` pins it and copies the tree-sitter DLLs beside it.
- **The `_D-RAG` folder name** is the constant `DRAG_HOME_DIR` in `DRagLint.Core.Model` after Task 1. Never re-spell the literal.
- **Deriving a DB path never rebuilds an index.** `schema_meta` holds only `indexer_fingerprint` and `schema_version`; no table stores the database's own path. A move is a file move.
- **Don't commit:** `FEATURES.txt`, `docs\lint\PLAN-autodoc-*`, `third_party\dll-win32\dclDragLintWizard.{bpl,dcp}`, `third_party\dll-win64\dclDragLintWizard.{bpl,dcp}`.
- Branch is `fix/lint-noise-round1`. Commit after every task.

## File Structure

| file | responsibility |
|---|---|
| `src\core\DRagLint.Core.Model.pas` (modify) | holds `DRAG_HOME_DIR = '_D-RAG'` beside `DRAGLINT_VERSION` |
| `src\index\DRagLint.Index.Manifest.pas` (modify) | `SectionProjectFile` + derived DB path in `ExpandSectionDb` |
| `src\project\DRagLint.Project.OwnRoots.pas` (**new**) | reads `drag-lint-project.json`, applies the default, answers `IsOurs`; deliberately standalone so the LSP and IDE plugin can ask without dragging in the lint config |
| `src\cli\DRagLint.CLI.pas` (modify) | `migrate-dbs` verb, `--lint-third-party` flag, the `DoLintAll` filter + skip report, two selftests |
| `tests\autotest\run_manifest.ps1` (modify) | derived-DB-path assertions |
| `tests\autotest\run_lint_own_roots.ps1` (**new**) | end-to-end lint scoping |
| `tests\autotest\run_migrate_dbs.ps1` (**new**) | migration dry-run and apply |
| `tests\fixtures\own-roots\` (**new**) | project + shared + vendor fixture tree |

---

### Task 1: Derive a project section's DB path from its project file

**Files:**
- Modify: `src\core\DRagLint.Core.Model.pas` (add `DRAG_HOME_DIR` next to `DRAGLINT_VERSION` at line 17)
- Modify: `src\index\DRagLint.Index.Manifest.pas:1205-1219` (`ExpandSectionDb`)
- Modify: `src\cli\DRagLint.CLI.pas:10301`, `:10648` (replace the two `'_D-RAG'` literals), `:15806` and `:15820` (selftest dispatch + help), and add `DoSelfTestSectionDb`
- Test: `tests\autotest\run_manifest.ps1`

**Interfaces:**
- Consumes: nothing.
- Produces: `DRAG_HOME_DIR: string` in `DRagLint.Core.Model`; `function SectionProjectFile(const AManifest: TIndexManifest; const ASection: TIndexSection): string` exported from `DRagLint.Index.Manifest` (returns `''` for a folder-scan section); `ExpandSectionDb` behaviour change. Task 2 and Task 3 both call `SectionProjectFile` and `ExpandSectionDb`.

- [ ] **Step 1: Write the failing selftest**

Add to `src\cli\DRagLint.CLI.pas`, immediately before `DoSelfTest` (line ~15804). It mirrors `DoSelfTestManifestMerge`'s shape exactly -- print `SECTIONDB-OK` and return 0, or `SECTIONDB-FAIL: <detail>` and return 1.

```pascal
// selftest section-db: asserts ExpandSectionDb derives <projdir>\_D-RAG\<project
// base>.sqlite for a project section with no "db", that TWO projects in ONE folder
// get distinct files (YADF hosts three), that an explicit "db" still wins, and that
// a folder-scan section keeps <OutDir>\<Name>.sqlite.
// Prints SECTIONDB-OK on success or SECTIONDB-FAIL: <detail>.
function DoSelfTestSectionDb: Integer;
var
  M  : TIndexManifest;
  S  : TIndexSection ;
  Got: string        ;
begin
  M        := Default(TIndexManifest);
  M.RootDir:= 'C:\cfg';
  M.OutDir := 'C:\out';

  S        := Default(TIndexSection);
  S.Name   := 'YADF';
  S.Include:= ['C:\Projects\YADF\YADF.dproj'];
  Got      := ExpandSectionDb(M, S);
  if not SameText(Got, 'C:\Projects\YADF\_D-RAG\YADF.sqlite') then
    begin Writeln('SECTIONDB-FAIL: derived ', Got); Exit(1); end;

  S.Name   := 'YADFOT';
  S.Include:= ['C:\Projects\YADF\YADFOT.dproj'];
  Got      := ExpandSectionDb(M, S);
  if not SameText(Got, 'C:\Projects\YADF\_D-RAG\YADFOT.sqlite') then
    begin Writeln('SECTIONDB-FAIL: same-folder second project got ', Got); Exit(1); end;

  S.Db:= 'C:\elsewhere\pinned.sqlite';
  Got := ExpandSectionDb(M, S);
  if not SameText(Got, 'C:\elsewhere\pinned.sqlite') then
    begin Writeln('SECTIONDB-FAIL: explicit db did not win, got ', Got); Exit(1); end;

  S        := Default(TIndexSection);
  S.Name   := 'Library';
  S.Include:= ['C:\Projects\SomeFolder'];
  Got      := ExpandSectionDb(M, S);
  if not SameText(Got, 'C:\out\Library.sqlite') then
    begin Writeln('SECTIONDB-FAIL: folder section got ', Got); Exit(1); end;

  { A .dpr and a .dpk anchor a project just as a .dproj does -- DragLint-Tests
    and the Graph packages are configured that way. }
  S        := Default(TIndexSection);
  S.Name   := 'Tests';
  S.Include:= ['C:\Projects\X\tests\Edge.dpr'];
  Got      := ExpandSectionDb(M, S);
  if not SameText(Got, 'C:\Projects\X\tests\_D-RAG\Edge.sqlite') then
    begin Writeln('SECTIONDB-FAIL: .dpr anchor got ', Got); Exit(1); end;

  Writeln('SECTIONDB-OK');
  Result:= 0;
end; // function
```

Wire it into `DoSelfTest` (line 15806) and its help list (line 15820):

```pascal
  else if AArgs.SubCommand = 'section-db'    then Result:= DoSelfTestSectionDb
```
```pascal
    Writeln('Available: manifest-merge, glob, ignore, files, closure, dbselect, drift, coverage, recreate, unused-locals, harvest, section-db');
```

- [ ] **Step 2: Build and run it to verify it fails**

Build per the `delphi-build` recipe, then:

Run: `src\cli\Win64\Debug\drag-lint.exe selftest section-db`
Expected: FAIL -- `SECTIONDB-FAIL: derived C:\out\YADF.sqlite` (the current `<OutDir>\<Name>.sqlite` default), exit 1.

- [ ] **Step 3: Add the constant**

In `src\core\DRagLint.Core.Model.pas`, beside `DRAGLINT_VERSION` (line 17):

```pascal
  /// <summary>Hidden per-project folder holding everything drag-lint keeps for
  /// one Delphi project: its index, its drag-lint-project.json, its reports, and
  /// the ghost-compile journal that first created the folder.</summary>
  DRAG_HOME_DIR = '_D-RAG';
```

Replace the two existing literals in `src\cli\DRagLint.CLI.pas` (`:10301` and `:10648`) with `DRAG_HOME_DIR` so there is one spelling in the codebase.

- [ ] **Step 4: Implement the derivation**

In `src\index\DRagLint.Index.Manifest.pas`, add above `ExpandSectionDb` (uses `DRagLint.Core.Model` -- add to the implementation `uses` if absent):

```pascal
/// <summary>The project file a section is anchored to, expanded to an absolute
/// path, or '' when the section scans a folder tree instead.</summary>
/// <param name="AManifest">Parsed manifest; RootDir anchors a relative include.</param>
/// <param name="ASection">Section to inspect.</param>
/// <returns>Absolute .dproj/.dpr/.dpk path, or '' for a folder-scan section.</returns>
/// <remarks>Only the FIRST include is considered. A section whose target is a
/// project indexes that project's compile closure, so a second project target
/// would be a second section -- which is how the manifest already models it.</remarks>
function SectionProjectFile(const AManifest: TIndexManifest; const ASection: TIndexSection): string;
var
  Ext: string;
begin
  Result:= '';
  if Length(ASection.Include) = 0 then Exit;
  Result:= ASection.Include[0];
  if Result = '' then Exit;
  if TPath.IsRelativePath(Result) and (AManifest.RootDir <> '') then
    Result:= TPath.Combine(AManifest.RootDir, Result);
  Result:= ExpandFileName(Result);
  Ext   := LowerCase(ExtractFileExt(Result));
  if (Ext <> '.dproj') and (Ext <> '.dpr') and (Ext <> '.dpk') then Result:= '';
end;
```

Declare it in the interface section beside `ExpandSectionDb` (line ~411). Then change `ExpandSectionDb`:

```pascal
function ExpandSectionDb(const AManifest: TIndexManifest; const ASection: TIndexSection): string;
var
  OutBase : string;
  ProjFile: string;
begin
  Result:= ASection.Db;
  { An omitted Db on a PROJECT section resolves to that project's own _D-RAG
    home, named after the PROJECT FILE. Not the folder and not the section name:
    five folders here host two or three projects (YADF, YADFOT and YADFSetup all
    live in C:\Projects\YADF), so a folder-derived name would collide.
    An explicit Db still wins -- the escape hatch for a read-only or network
    source tree that cannot host a database. }
  if Result = '' then
  begin
    ProjFile:= SectionProjectFile(AManifest, ASection);
    if ProjFile <> '' then
      Exit(TPath.Combine(TPath.Combine(ExtractFilePath(ProjFile), DRAG_HOME_DIR),
                         TPath.GetFileNameWithoutExtension(ProjFile) + '.sqlite'));
    Result:= ASection.Name + '.sqlite';
  end;
  if not TPath.IsRelativePath(Result) then Exit(ExpandFileName(Result));
  OutBase:= AManifest.OutDir;
  if OutBase = '' then OutBase:= AManifest.RootDir
  else if TPath.IsRelativePath(OutBase) then OutBase:= TPath.Combine(AManifest.RootDir, OutBase);
  Result:= ExpandFileName(TPath.Combine(OutBase, Result));
end;
```

- [ ] **Step 5: Rebuild and run the selftest to verify it passes**

Run: `src\cli\Win64\Debug\drag-lint.exe selftest section-db`
Expected: PASS -- prints `SECTIONDB-OK`, exit 0.

- [ ] **Step 6: Add the battery assertion**

Append to `tests\autotest\run_manifest.ps1`, after the existing `selftest manifest-merge` block:

```powershell
Write-Host ''
$sdb = & $Exe selftest section-db 2>&1 | Out-String
Check 'section-db selftest (derived _D-RAG path)' ($sdb -match 'SECTIONDB-OK')
```

Run: `pwsh -File tests\autotest\run_manifest.ps1`
Expected: every Check PASS, including the new one.

- [ ] **Step 7: Commit**

```bash
git add src/core/DRagLint.Core.Model.pas src/index/DRagLint.Index.Manifest.pas src/cli/DRagLint.CLI.pas tests/autotest/run_manifest.ps1
git commit -m "feat(index): a project section with no db resolves to its _D-RAG home"
```

---

### Task 2: The `migrate-dbs` verb

**Files:**
- Modify: `src\cli\DRagLint.CLI.pas` (new `DoMigrateDbs`, verb dispatch at `:16270`, help text at `:486`)
- Create: `tests\autotest\run_migrate_dbs.ps1`

**Interfaces:**
- Consumes: `SectionProjectFile`, `ExpandSectionDb`, `DRAG_HOME_DIR` from Task 1.
- Produces: the verb `drag-lint migrate-dbs [--config <manifest>] [--apply]`. Exit 0 = nothing to do or success, 1 = at least one move failed, 2 = usage/lock error. Task 3 runs it for real.

**A deliberate refinement of spec section 3.3 step 1.** The spec says "refuse to run if RAD Studio is running". Implement it as an **exclusive-open probe on each database file** instead. That tests the thing that actually matters -- is this file locked -- and also catches a running index job or an LSP launched from a copied exe, which a process-name check would miss. The error message names the locked file and cites RAD Studio as the likely holder.

- [ ] **Step 1: Write the failing test**

Create `tests\autotest\run_migrate_dbs.ps1`:

```powershell
$Exe = . "$PSScriptRoot\_manifest_common.ps1"
$work = Join-Path $env:TEMP ('draglint_migrate_' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory $work | Out-Null
try {
    # A project tree + an out-of-tree DB dir, mirroring today's layout.
    $proj = Join-Path $work 'proj';  New-Item -ItemType Directory $proj | Out-Null
    $out  = Join-Path $work 'out' ;  New-Item -ItemType Directory $out  | Out-Null
    Set-Content -LiteralPath (Join-Path $proj 'App.dproj') -Value '<Project/>' -NoNewline
    Set-Content -LiteralPath (Join-Path $proj 'App.pas')   -Value "unit App;`r`ninterface`r`nimplementation`r`nend."

    # Build a real index at the OLD location so there is something to move.
    $olddb = Join-Path $out 'Old-App.sqlite'
    & $Exe index $proj --db $olddb | Out-Null
    Check 'fixture index built' (Test-Path $olddb)
    $before = & $Exe query --db $olddb --name App --json 2>$null | Out-String

    $cfg = Join-Path $work 'drag-lint.json'
    $j = @{ indexes = @{ outDir = $out; sections = @(
              @{ name = 'Old-App'; db = 'Old-App.sqlite'; include = @((Join-Path $proj 'App.dproj')) } ) } }
    Set-Content -LiteralPath $cfg -Value ($j | ConvertTo-Json -Depth 8)

    $newdb = Join-Path $proj '_D-RAG\App.sqlite'

    # 1. Dry run must NOT touch disk.
    $dry = & $Exe migrate-dbs --config $cfg 2>&1 | Out-String
    Check 'dry-run exits 0'          ($LASTEXITCODE -eq 0)
    Check 'dry-run names the target' ($dry -match [regex]::Escape($newdb))
    Check 'dry-run moved nothing'    ((Test-Path $olddb) -and -not (Test-Path $newdb))

    # 2. Apply moves the DB and its WAL siblings.
    $app = & $Exe migrate-dbs --config $cfg --apply 2>&1 | Out-String
    Check 'apply exits 0'        ($LASTEXITCODE -eq 0)
    Check 'db moved'             ((Test-Path $newdb) -and -not (Test-Path $olddb))
    Check 'no -wal left behind'  (-not (Test-Path "$olddb-wal"))
    Check 'gitignore written'    (Test-Path (Join-Path $proj '_D-RAG\.gitignore'))
    Check 'gitignore ignores all' ((Get-Content (Join-Path $proj '_D-RAG\.gitignore') -Raw).Trim() -eq '*')

    # 3. The moved index still answers, and the manifest now derives the path.
    $after = & $Exe query --db $newdb --name App --json 2>$null | Out-String
    Check 'moved index still answers' ($after.Trim() -eq $before.Trim())
    $plan = & $Exe index --all --dry-run --json --config $cfg 2>$null | Out-String
    Check 'manifest points at _D-RAG' ($plan -match '_D-RAG')

    # 4. Re-running is a no-op, not an error.
    & $Exe migrate-dbs --config $cfg --apply 2>&1 | Out-Null
    Check 'second apply is a no-op' ($LASTEXITCODE -eq 0)

    # 5. A locked DB aborts with exit 2 and names the file.
    $newdb2 = Join-Path $proj '_D-RAG\App.sqlite'
    $fs = [IO.File]::Open($newdb2, 'Open', 'ReadWrite', 'None')
    try {
        $j2 = @{ indexes = @{ outDir = $out; sections = @(
                  @{ name = 'Old-App'; db = $newdb2; include = @((Join-Path $proj 'App.dproj')) } ) } }
        $cfg2 = Join-Path $work 'locked.json'
        Set-Content -LiteralPath $cfg2 -Value ($j2 | ConvertTo-Json -Depth 8)
        $lock = & $Exe migrate-dbs --config $cfg2 --apply 2>&1 | Out-String
        Check 'locked db aborts with 2' ($LASTEXITCODE -eq 2)
        Check 'lock error names the file' ($lock -match 'App.sqlite')
    } finally { $fs.Close() }
} finally {
    Remove-Item -Recurse -Force $work -ErrorAction SilentlyContinue
}
if ($script:Failed) { exit 1 } else { exit 0 }
```

- [ ] **Step 2: Run it to verify it fails**

Run: `pwsh -File tests\autotest\run_migrate_dbs.ps1`
Expected: FAIL -- `dry-run exits 0` fails because `migrate-dbs` is an unknown command (exit 2).

- [ ] **Step 3: Implement the verb**

Add to `src\cli\DRagLint.CLI.pas` near the other index verbs:

```pascal
{ Exclusive-open probe. A DB that another process holds -- RAD Studio's LSP is
  the usual one, but a stray index job or an LSP started from a copied exe does
  it too -- must abort the migration BEFORE the first move, not half way through.
  Testing the file beats testing for a process name: it is the lock that would
  actually break the move. }
function DbIsLocked(const APath: string): Boolean;
var
  FS: TFileStream;
begin
  Result:= False;
  if not TFile.Exists(APath) then Exit;
  try
    FS:= TFileStream.Create(APath, fmOpenReadWrite or fmShareExclusive);
    FS.Free;
  except
    on E: EFOpenError do Result:= True;
  end;
end;

{ Move a database and the two WAL sidecars that belong to it. All 27 configured
  indexes have both today. Checkpointing first collapses the WAL into the main
  file, so a sidecar that fails to move costs nothing. }
procedure MoveDbSet(const ASrc, ADst: string);
var
  Suffix: string;
begin
  TFile.Move(ASrc, ADst);
  for Suffix in ['-wal', '-shm'] do
    if TFile.Exists(ASrc + Suffix) then
    begin
      if TFile.Exists(ADst + Suffix) then TFile.Delete(ADst + Suffix);
      TFile.Move(ASrc + Suffix, ADst + Suffix);
    end;
end;

/// <summary>Moves every project section's index into that project's _D-RAG home
/// and drops the now-derivable "db" from the manifest.</summary>
/// <param name="AArgs">Parsed args; ConfigPath and the --apply switch are read.</param>
/// <returns>0 = success or nothing to do, 1 = a move failed, 2 = a DB is locked
/// or the manifest could not be read.</returns>
/// <remarks>Dry-run by default: prints every planned move and touches nothing.
/// No reindex is needed -- no table stores the database's own path.</remarks>
function DoMigrateDbs(const AArgs: TArgs): Integer;
var
  Manifest : TIndexManifest;
  CfgPath  : string        ;
  I        : Integer       ;
  Src, Dst : string        ;
  ProjFile : string        ;
  Moved    : Integer       ;
  Planned  : Integer       ;
  Conn     : TFDConnection ;
  RowsBefore, RowsAfter: Int64;
  HgRoots  : TStringList   ;
begin
  Result := 0;
  Moved  := 0;
  Planned:= 0;
  { Deliberately NOT TManifestIO.Load: that MERGES a global and a local manifest
    and does not report which file it read, so saving the merged result back
    would inline one manifest into the other. Resolve exactly one file and
    rewrite exactly that file. --config wins; else the drag-lint.json beside the
    exe, which is where the real one lives (third_party\dll-win64). }
  CfgPath:= AArgs.WorkspaceConfig;
  if CfgPath = '' then CfgPath:= TPath.Combine(ExtractFilePath(ParamStr(0)), 'drag-lint.json');
  if not TFile.Exists(CfgPath) then
  begin
    Writeln('ERROR: manifest not found: ', CfgPath);
    Writeln('       Pass --config <drag-lint.json> naming the file to rewrite.');
    Exit(2);
  end;
  Manifest:= TManifestIO.ParseText(TFile.ReadAllText(CfgPath), ExtractFilePath(TPath.GetFullPath(CfgPath)));

  { Probe EVERY lock before moving ANY file. A half-done migration is the one
    outcome worth engineering against. }
  for I:= 0 to High(Manifest.Sections) do
  begin
    if SectionProjectFile(Manifest, Manifest.Sections[I]) = '' then Continue;
    Src:= ExpandSectionDb(Manifest, Manifest.Sections[I]);
    if DbIsLocked(Src) then
    begin
      Writeln('ERROR: in use, cannot migrate: ', Src);
      Writeln('       Close RAD Studio (its LSP holds project indexes open) and retry.');
      Exit(2);
    end;
  end;

  HgRoots:= TStringList.Create;
  HgRoots.Sorted:= True; HgRoots.Duplicates:= dupIgnore;
  try
    for I:= 0 to High(Manifest.Sections) do
    begin
      ProjFile:= SectionProjectFile(Manifest, Manifest.Sections[I]);
      if ProjFile = '' then Continue;                    { folder scan: stays put }
      Src:= ExpandSectionDb(Manifest, Manifest.Sections[I]);
      Dst:= TPath.Combine(TPath.Combine(ExtractFilePath(ProjFile), DRAG_HOME_DIR),
                          TPath.GetFileNameWithoutExtension(ProjFile) + '.sqlite');
      if SameText(Src, Dst) then Continue;               { already home }
      Inc(Planned);
      Writeln(Format('%s  %s -> %s', [Manifest.Sections[I].Name, Src, Dst]));
      if not AArgs.Apply then Continue;
      if not TFile.Exists(Src) then
      begin
        Writeln('  SKIP: source does not exist (never built)');
        Continue;
      end;

      try
        { Checkpoint so the moved file is self-contained, and count rows so the
          move can be verified rather than assumed. }
        Conn:= TFDConnection.Create(nil);
        try
          Conn.DriverName:= 'SQLite';
          Conn.Params.Values['Database']:= Src;
          Conn.LoginPrompt:= False;
          Conn.Open;
          Conn.ExecSQL('PRAGMA wal_checkpoint(TRUNCATE)');
          RowsBefore:= Conn.ExecSQLScalar('SELECT COUNT(*) FROM files');
        finally
          Conn.Close; Conn.Free;
        end;

        TDirectory.CreateDirectory(ExtractFileDir(Dst));
        MoveDbSet(Src, Dst);

        Conn:= TFDConnection.Create(nil);
        try
          Conn.DriverName:= 'SQLite';
          Conn.Params.Values['Database']:= Dst;
          Conn.LoginPrompt:= False;
          Conn.Open;
          RowsAfter:= Conn.ExecSQLScalar('SELECT COUNT(*) FROM files');
        finally
          Conn.Close; Conn.Free;
        end;
        if RowsAfter <> RowsBefore then
        begin
          Writeln(Format('  ERROR: %d files before, %d after -- STOPPING', [RowsBefore, RowsAfter]));
          Exit(1);
        end;

        { Self-ignoring for git. Mercurial cannot self-ignore, so collect the
          repo roots and print instructions at the end instead of editing a
          repository's ignore file behind its owner's back. }
        TFile.WriteAllText(TPath.Combine(ExtractFileDir(Dst), '.gitignore'), '*'#13#10);
        var HgRoot: string:= FindHgRoot(ExtractFilePath(ProjFile));
        if HgRoot <> '' then HgRoots.Add(HgRoot);

        Manifest.Sections[I].Db:= '';   { now derivable }
        Inc(Moved);
        Writeln(Format('  OK (%d files)', [RowsAfter]));
      except
        on E: Exception do
        begin
          Writeln('  ERROR: ', E.ClassName, ': ', E.Message);
          Exit(1);
        end;
      end;
    end;

    if AArgs.Apply and (Moved > 0) then
    begin
      TManifestIO.Save(Manifest, CfgPath);
      Writeln(Format('migrate-dbs: %d database(s) moved; manifest updated (%s)', [Moved, CfgPath]));
      if HgRoots.Count > 0 then
      begin
        Writeln('');
        Writeln('Mercurial cannot self-ignore. Add this line to each .hgignore:');
        Writeln('    ' + DRAG_HOME_DIR);
        for var R: string in HgRoots do Writeln('  ' + TPath.Combine(R, '.hgignore'));
      end;
    end
    else if not AArgs.Apply then
      Writeln(Format('migrate-dbs: %d database(s) would move. Re-run with --apply.', [Planned]));
  finally
    HgRoots.Free;
  end;
end; // function
```

Add the `FindHgRoot` helper next to it:

```pascal
{ Nearest ancestor holding a .hg directory, or '' -- used only to tell the user
  which .hgignore to edit. }
function FindHgRoot(const AStartDir: string): string;
var
  Dir, Parent: string;
begin
  Result:= '';
  Dir   := ExcludeTrailingPathDelimiter(ExpandFileName(AStartDir));
  while Dir <> '' do
  begin
    if TDirectory.Exists(TPath.Combine(Dir, '.hg')) then Exit(Dir);
    Parent:= ExtractFileDir(Dir);
    if SameText(Parent, Dir) then Break;
    Dir:= Parent;
  end;
end;
```

Add `Apply: Boolean` to `TArgs`, parse it beside the other switches (`src\cli\DRagLint.CLI.pas:~823`):

```pascal
    else if A = '--apply'   then Result.Apply := True
```

Dispatch it at `:16270`:

```pascal
    else if Args.Command = 'migrate-dbs'       then Result:= DoMigrateDbs      (Args)
```

And add to the usage block (`:486`):

```pascal
  Writeln('  drag-lint migrate-dbs        [--config <drag-lint.json>] [--apply]   move project indexes into each project''s _D-RAG folder');
```

- [ ] **Step 4: Rebuild and run the test to verify it passes**

Run: `pwsh -File tests\autotest\run_migrate_dbs.ps1`
Expected: every Check PASS, exit 0.

- [ ] **Step 5: Commit**

```bash
git add src/cli/DRagLint.CLI.pas tests/autotest/run_migrate_dbs.ps1
git commit -m "feat(index): migrate-dbs moves project indexes into their _D-RAG home"
```

---

### Task 3: Run the real migration on all 27 databases

**Files:**
- Modify: `C:\Projects\Delphi-RAG-lint\third_party\dll-win64\drag-lint.json` (rewritten by the tool)
- Modify: `.hgignore` in `C:\Projects\DB\ORM3\{CLIENT,SERVER,COMMON,OBJECTS,PACKAGE}`, `C:\Projects\TableTools`, `C:\Projects\Loader2019`, `C:\Projects\DataCopy` (by hand, from the tool's printed instructions)

**Interfaces:**
- Consumes: the `migrate-dbs` verb from Task 2.
- Produces: 27 databases at their derived paths. Task 5's `AnchorDirForDb` depends on this layout being real.

This is an operational task, not a code change. It moves 292 MB of real indexes. **RAD Studio must be closed.**

- [ ] **Step 1: Deploy the freshly built engine, then snapshot the current state**

`migrate-dbs` exists only in the exe Task 2 built. The deployed
`third_party\dll-win64\drag-lint.exe` is stale, and running the verb from
`src\cli\Win64\Debug` instead is a trap: `index --all` resolves its manifest
relative to **the exe's own directory**, so a copied exe with no
`drag-lint.json` beside it indexes nothing and exits 0 -- a fake pass. Deploy
first, with RAD Studio closed (it holds the exe open):

```bash
cp src/cli/Win64/Debug/drag-lint.exe third_party/dll-win64/drag-lint.exe
third_party/dll-win64/drag-lint.exe --version    # must report 1.2.2-alpha or later
third_party/dll-win64/drag-lint.exe migrate-dbs --help 2>&1 | head -3   # verb exists
```

Then snapshot:

```bash
python - <<'EOF'
import json, os, sqlite3
d=json.load(open(r'C:\Projects\Delphi-RAG-lint\third_party\dll-win64\drag-lint.json'))
out=d['indexes']['outDir']; rows={}
for s in d['indexes']['sections']:
    db=s['db']; db=db if os.path.isabs(db) else os.path.join(out,db)
    if os.path.exists(db):
        c=sqlite3.connect('file:'+db+'?mode=ro',uri=True)
        rows[s['name']]=c.execute('select count(*) from files').fetchone()[0]; c.close()
json.dump(rows, open(r'C:\TEMP\claude\pre_migration_counts.json','w'), indent=1)
print(len(rows),'databases;', sum(rows.values()),'file rows total')
EOF
```
Expected: 29 databases listed (27 project + SQL + library-Win32).

- [ ] **Step 2: Dry run**

Run: `third_party\dll-win64\drag-lint.exe migrate-dbs --apply` -- NO, run WITHOUT `--apply` first:

Run: `cd third_party\dll-win64 && .\drag-lint.exe migrate-dbs`
Expected: 27 planned moves listed, `migrate-dbs: 27 database(s) would move.`, and **nothing on disk changed** (`ls C:\Projects\.drag-lint\*.sqlite | wc -l` is unchanged).

- [ ] **Step 3: Close RAD Studio, then apply**

Run: `cd third_party\dll-win64 && .\drag-lint.exe migrate-dbs --apply`
Expected: 27 `OK (N files)` lines, `manifest updated`, then the `.hgignore` instruction block. If it exits 2 naming a locked file, the IDE is still running -- close it and re-run; the migration is resumable because it skips anything already home.

- [ ] **Step 4: Verify every database survived and still answers**

```bash
python - <<'EOF'
import json, os, sqlite3
pre=json.load(open(r'C:\TEMP\claude\pre_migration_counts.json'))
d=json.load(open(r'C:\Projects\Delphi-RAG-lint\third_party\dll-win64\drag-lint.json'))
out=d['indexes']['outDir']; bad=[]
for s in d['indexes']['sections']:
    n=s['name']
    if n not in pre: continue
    db=s.get('db','')
    if not db:
        inc=s['include'][0]
        db=os.path.join(os.path.dirname(inc),'_D-RAG',os.path.splitext(os.path.basename(inc))[0]+'.sqlite')
    elif not os.path.isabs(db): db=os.path.join(out,db)
    if not os.path.exists(db): bad.append((n,'MISSING',db)); continue
    c=sqlite3.connect('file:'+db+'?mode=ro',uri=True)
    got=c.execute('select count(*) from files').fetchone()[0]
    ok=c.execute('pragma quick_check').fetchone()[0]
    fk=len(c.execute('pragma foreign_key_check').fetchall()); c.close()
    if got!=pre[n] or ok!='ok' or fk: bad.append((n,f'rows {pre[n]}->{got} check={ok} fk={fk}',db))
print('MISMATCHES:',bad if bad else 'none')
EOF
```
Expected: `MISMATCHES: none`.

- [ ] **Step 5: Verify the consumers still resolve**

```bash
cd third_party/dll-win64
./drag-lint.exe resolve-dbs --platform Win32 | head -20
./drag-lint.exe resolve-dbs --in C:/Projects/YADF/YADF.dpr
./drag-lint.exe index --all --dry-run | grep -i 'Sections to build'
./drag-lint.exe query --name TLinter --db C:/Projects/Delphi-RAG-lint/src/cli/_D-RAG/drag-lint.sqlite | head -5
```
Expected: paths point into `_D-RAG`; `Sections to build:` is greater than 0; the query returns real rows.

- [ ] **Step 6: Add the Mercurial ignore lines by hand**

For each `.hgignore` path the tool printed, add a line `_D-RAG` under the `syntax: glob` section. Verify with `hg status` in each repo: no `_D-RAG` entry appears.

- [ ] **Step 7: Commit the manifest**

```bash
git add third_party/dll-win64/drag-lint.json
git commit -m "chore(index): move all 27 project indexes into their project _D-RAG homes"
```

---

### Task 4: `DRagLint.Project.OwnRoots` -- declared ownership

**Files:**
- Create: `src\project\DRagLint.Project.OwnRoots.pas`
- Modify: `src\cli\drag-lint.dproj` (add the `<DCCReference>`), `src\cli\drag-lint.dpr` (uses clause)
- Modify: `src\cli\DRagLint.CLI.pas` (add `DoSelfTestOwnRoots` + dispatch + help)
- Create: `tests\fixtures\own-roots\` fixture tree
- Test: via `selftest own-roots --dir <fixture>`, asserted in Task 5's runner

**Interfaces:**
- Consumes: `DRAG_HOME_DIR` from Task 1.
- Produces:
  - `TOwnRoots` record with `class function Load(const AAnchorDir: string): TOwnRoots; static`, `function IsOurs(const AFilePath: string): Boolean`, and read-only properties `Roots: TArray<string>`, `Anchor: string`, `Declared: Boolean`, `Error: string`.
  - `function AnchorDirForDb(const ADbPath: string): string` -- the project folder for a DB in a `_D-RAG` home, else `''`.
  - Task 5 calls all of these.

**Refinement of spec section 4.1:** `ownRoots` entries may be **relative to the anchor directory** as well as absolute. This is a superset of the spec and makes declarations portable -- ORM3's eight sections each declare `[".."]` rather than a hardcoded `C:\Projects\DB\ORM3`, and the test fixture can declare roots at all. Absolute entries keep working unchanged.

- [ ] **Step 1: Create the fixture tree**

```
tests\fixtures\own-roots\
  proj\App.dproj                       (content: <Project/>)
  proj\App.pas                         (a unit with a duplicate-code twin in vendor\)
  proj\_D-RAG\drag-lint-project.json   { "ownRoots": [".", "..\\shared"] }
  shared\Shared.pas
  vendor\Vendor.pas
```

`proj\App.pas`, `shared\Shared.pas` and `vendor\Vendor.pas` must each be strict-ASCII CRLF. Give `App.pas` and `Vendor.pas` an identical 30-line routine so Task 5 can assert that `duplicate-code` does not pair our code with vendored code:

```pascal
unit App;

interface

procedure RunReport(const APath: string);

implementation

uses System.SysUtils, System.Classes;

procedure RunReport(const APath: string);
var
  SL : TStringList;
  I  : Integer    ;
  Acc: Integer    ;
begin
  SL:= TStringList.Create;
  try
    SL.LoadFromFile(APath);
    Acc:= 0;
    for I:= 0 to SL.Count - 1 do
    begin
      if Trim(SL[I]) = '' then Continue;
      if StartsText('#', Trim(SL[I])) then Continue;
      if Length(SL[I]) > 80 then Inc(Acc, 2) else Inc(Acc);
    end;
    if Acc > 100 then Writeln('large: ', Acc)
    else if Acc > 10 then Writeln('medium: ', Acc)
    else Writeln('small: ', Acc);
  finally
    SL.Free;
  end;
end;

end.
```

`vendor\Vendor.pas` is the same file with `unit Vendor;` and `procedure RunReport` renamed nothing else -- an exact clone is the point. `shared\Shared.pas` is a trivial unit (`unit Shared; interface implementation end.`).

- [ ] **Step 2: Write the failing selftest**

Add to `src\cli\DRagLint.CLI.pas` before `DoSelfTest`:

```pascal
// selftest own-roots --dir <fixtures\own-roots>: asserts a declared root list is
// read (including a RELATIVE entry), that a file under a declared root is ours,
// that a sibling folder outside them is not, that an UNDECLARED project defaults
// to its own folder, and that a DB inside a _D-RAG resolves back to its project.
// Prints OWNROOTS-OK or OWNROOTS-FAIL: <detail>.
function DoSelfTestOwnRoots(const AArgs: TArgs): Integer;
var
  Fx  : string   ;
  Own : TOwnRoots;
begin
  { --dir lands in TArgs.Path, not a field called Dir (see the parser at :980) --
    the same field `selftest ignore --dir` reads. }
  Fx:= AArgs.Path;
  if Fx = '' then begin Writeln('OWNROOTS-FAIL: pass --dir <fixtures\own-roots>'); Exit(1); end;

  Own:= TOwnRoots.Load(TPath.Combine(Fx, 'proj'));
  if not Own.Declared then begin Writeln('OWNROOTS-FAIL: declaration not read'); Exit(1); end;
  if Own.Error <> '' then begin Writeln('OWNROOTS-FAIL: ', Own.Error); Exit(1); end;
  if not Own.IsOurs(TPath.Combine(Fx, 'proj\App.pas')) then
    begin Writeln('OWNROOTS-FAIL: own file not ours'); Exit(1); end;
  if not Own.IsOurs(TPath.Combine(Fx, 'shared\Shared.pas')) then
    begin Writeln('OWNROOTS-FAIL: relative root "..\shared" not honoured'); Exit(1); end;
  if Own.IsOurs(TPath.Combine(Fx, 'vendor\Vendor.pas')) then
    begin Writeln('OWNROOTS-FAIL: vendor file counted as ours'); Exit(1); end;

  { An undeclared project owns exactly its own folder. }
  Own:= TOwnRoots.Load(TPath.Combine(Fx, 'vendor'));
  if Own.Declared then begin Writeln('OWNROOTS-FAIL: vendor has no declaration'); Exit(1); end;
  if not Own.IsOurs(TPath.Combine(Fx, 'vendor\Vendor.pas')) then
    begin Writeln('OWNROOTS-FAIL: default root must be the project folder'); Exit(1); end;
  if Own.IsOurs(TPath.Combine(Fx, 'proj\App.pas')) then
    begin Writeln('OWNROOTS-FAIL: default root leaked to a sibling'); Exit(1); end;

  { No anchor at all: filtering must be OFF, not empty. }
  Own:= TOwnRoots.Load('');
  if not Own.IsOurs(TPath.Combine(Fx, 'vendor\Vendor.pas')) then
    begin Writeln('OWNROOTS-FAIL: an anchorless run must not filter'); Exit(1); end;

  if not SameText(AnchorDirForDb(TPath.Combine(Fx, 'proj\_D-RAG\App.sqlite')),
                  ExcludeTrailingPathDelimiter(TPath.Combine(Fx, 'proj'))) then
    begin Writeln('OWNROOTS-FAIL: AnchorDirForDb did not resolve the _D-RAG parent'); Exit(1); end;
  if AnchorDirForDb(TPath.Combine(Fx, 'proj\App.sqlite')) <> '' then
    begin Writeln('OWNROOTS-FAIL: a DB outside a _D-RAG has no anchor'); Exit(1); end;

  Writeln('OWNROOTS-OK');
  Result:= 0;
end; // function
```

Wire into `DoSelfTest` and the `Available:` list as in Task 1.

- [ ] **Step 3: Run it to verify it fails**

Run: `src\cli\Win64\Debug\drag-lint.exe selftest own-roots --dir tests\fixtures\own-roots`
Expected: FAIL -- the build breaks first (`DRagLint.Project.OwnRoots` not found). That is the failing state.

- [ ] **Step 4: Implement the unit**

Create `src\project\DRagLint.Project.OwnRoots.pas`:

```pascal
unit DRagLint.Project.OwnRoots;

/// <summary>One question, asked of a project rather than of an index: is this
/// source file part of the code this project OWNS?</summary>
/// <remarks>Exists because INDEXING scope and LINTING scope are different
/// questions. A project index is the compile closure, which correctly contains
/// vendored third-party source -- 768 of YADF's 1,072 findings were in
/// C:\Projects\DelphiAST, a parser YADF neither owns nor can fix. Lint was
/// inheriting the indexer's answer.
///
/// Ownership CANNOT be inferred here and must be declared. Measured against
/// every configured index: "under the project folder" and "under the VCS root"
/// both drop 295 of ORM3-Micronite2027's own business objects, because
/// Mercurial repositories on this machine are per-folder (CLIENT, SERVER,
/// COMMON and OBJECTS are four repositories of one codebase); and "a different
/// repository means third-party" additionally counts PDFlibPas, which has no
/// repository at all, as ours.
///
/// Deliberately standalone, for the reason DRagLint.Storage.FileMembership
/// gives: the LSP and the IDE plugin need this one answer and must not drag in
/// the lint configuration machinery to get it.
///
/// All .pas source: strict 7-bit ASCII, CRLF line endings, no BOM.</remarks>

interface

type
  /// <summary>The directory roots whose files a lint run treats as the project's
  /// own code, plus the answer to "is this file one of them?".</summary>
  /// <remarks>Value type; copy freely. Immutable after Load. Thread-safe to
  /// share for reading.</remarks>
  TOwnRoots = record
  strict private
    FRoots   : TArray<string>;
    FAnchor  : string        ;
    FDeclared: Boolean       ;
    FError   : string        ;
    FActive  : Boolean       ;
  public
    /// <summary>Reads &lt;AAnchorDir&gt;\_D-RAG\drag-lint-project.json and resolves
    /// its "ownRoots", or falls back to the anchor directory itself.</summary>
    /// <param name="AAnchorDir">The project file's folder. Pass '' when no anchor
    /// could be determined; the result then treats EVERY file as ours, so an
    /// unanchored run behaves exactly as it did before this unit existed.</param>
    /// <returns>A populated record. Check Error before use: a non-empty Error
    /// means the declaration was present but unusable and the caller must refuse
    /// to lint rather than silently scope to something unintended.</returns>
    /// <remarks>An entry may be absolute or relative to AAnchorDir; a relative
    /// entry keeps a declaration portable ("[..]" from ORM3\CLIENT). A missing,
    /// unreadable or malformed file is NOT an error -- it defaults. An explicit
    /// empty "ownRoots": [] IS an error, because scoping to nothing would report
    /// a clean project, the same reasoning as the empty --project refusal.</remarks>
    class function Load(const AAnchorDir: string): TOwnRoots; static;
    /// <summary>True when AFilePath sits under one of the roots.</summary>
    /// <param name="AFilePath">Absolute or relative source path.</param>
    /// <returns>True for our code; always True when the record is inactive
    /// (no anchor).</returns>
    /// <remarks>Path comparison mirrors
    /// DRagLint.Storage.FileMembership.NormalizeForLookup: forward slashes
    /// folded to backslashes, compared case-insensitively.</remarks>
    function IsOurs(const AFilePath: string): Boolean;
    /// <summary>Resolved roots, each with a trailing path delimiter.</summary>
    property Roots: TArray<string> read FRoots;
    /// <summary>The project folder this was loaded for.</summary>
    property Anchor: string read FAnchor;
    /// <summary>True when a drag-lint-project.json supplied the roots; False
    /// when they were defaulted to the anchor.</summary>
    property Declared: Boolean read FDeclared;
    /// <summary>Non-empty when the declaration was present but unusable.</summary>
    property Error: string read FError;
    /// <summary>False when there is no anchor and IsOurs always answers True.</summary>
    property Active: Boolean read FActive;
  end;

/// <summary>The project folder for an index that lives in a _D-RAG home.</summary>
/// <param name="ADbPath">Path to a .sqlite index.</param>
/// <returns>The parent of the _D-RAG folder, without a trailing delimiter, or
/// '' when the DB is not inside one.</returns>
/// <remarks>This is why the index moved next to its project: the anchor is a
/// property of the path, so no manifest lookup and no CWD-sensitive config
/// discovery is needed to find a project's declaration.</remarks>
function AnchorDirForDb(const ADbPath: string): string;

implementation

uses
  System.SysUtils
  , System.IOUtils
  , System.JSON
  , DRagLint.Core.Model
  ;

function NormalizeDir(const APath: string): string;
begin
  Result:= '';
  if APath = '' then Exit;
  Result:= IncludeTrailingPathDelimiter(
             ExpandFileName(StringReplace(APath, '/', '\', [rfReplaceAll])));
end;

function AnchorDirForDb(const ADbPath: string): string;
var
  Dir: string;
begin
  Result:= '';
  if ADbPath = '' then Exit;
  Dir:= ExtractFileDir(ExpandFileName(StringReplace(ADbPath, '/', '\', [rfReplaceAll])));
  if not SameText(ExtractFileName(Dir), DRAG_HOME_DIR) then Exit;
  Result:= ExtractFileDir(Dir);
end;

class function TOwnRoots.Load(const AAnchorDir: string): TOwnRoots;
var
  CfgPath: string     ;
  Root   : TJSONObject;
  Arr    : TJSONArray ;
  V      : TJSONValue ;
  Entry  : string     ;
begin
  Result         := Default(TOwnRoots);
  Result.FActive := AAnchorDir <> '';
  if not Result.FActive then Exit;

  Result.FAnchor:= ExcludeTrailingPathDelimiter(ExpandFileName(AAnchorDir));
  CfgPath       := TPath.Combine(TPath.Combine(Result.FAnchor, DRAG_HOME_DIR), 'drag-lint-project.json');

  if TFile.Exists(CfgPath) then
  try
    Root:= TJSONObject.ParseJSONValue(TFile.ReadAllText(CfgPath)) as TJSONObject;
    if Root <> nil then
    try
      if Root.GetValue('ownRoots') is TJSONArray then
      begin
        Arr:= Root.GetValue('ownRoots') as TJSONArray;
        if Arr.Count = 0 then
        begin
          Result.FError:= Format('%s declares an empty "ownRoots". Remove the key to ' +
            'default to the project folder, or list the roots -- scoping to nothing ' +
            'would report a clean project.', [CfgPath]);
          Exit;
        end;
        for V in Arr do
        begin
          Entry:= Trim(V.Value);
          if Entry = '' then Continue;
          if TPath.IsRelativePath(Entry) then Entry:= TPath.Combine(Result.FAnchor, Entry);
          Result.FRoots:= Result.FRoots + [NormalizeDir(Entry)];
        end;
        Result.FDeclared:= Length(Result.FRoots) > 0;
      end;
    finally
      Root.Free;
    end;
  except
    { A malformed declaration defaults rather than throws: the fallback is the
      project's own folder, which is never WRONG, only narrow -- and the skip
      report names what it dropped, so a bad file is visible within one run. }
    on E: Exception do Result.FDeclared:= False;
  end;

  if not Result.FDeclared then Result.FRoots:= [NormalizeDir(Result.FAnchor)];
end;

function TOwnRoots.IsOurs(const AFilePath: string): Boolean;
var
  P: string;
  R: string;
begin
  Result:= True;
  if not FActive then Exit;
  if AFilePath = '' then Exit;
  P:= ExpandFileName(StringReplace(AFilePath, '/', '\', [rfReplaceAll]));
  for R in FRoots do
    if (R <> '') and StartsText(R, P) then Exit(True);
  Result:= False;
end;

end.
```

Add `DRagLint.Project.OwnRoots` to `src\cli\drag-lint.dpr`'s uses clause and a `<DCCReference Include="..\project\DRagLint.Project.OwnRoots.pas"/>` to `src\cli\drag-lint.dproj` beside the existing `DRagLint.Project.Resolver` entry.

- [ ] **Step 5: Rebuild and run the selftest to verify it passes**

Run: `src\cli\Win64\Debug\drag-lint.exe selftest own-roots --dir tests\fixtures\own-roots`
Expected: PASS -- prints `OWNROOTS-OK`, exit 0.

- [ ] **Step 6: Byte-check encoding**

```bash
for f in src/project/DRagLint.Project.OwnRoots.pas tests/fixtures/own-roots/proj/App.pas tests/fixtures/own-roots/vendor/Vendor.pas tests/fixtures/own-roots/shared/Shared.pas; do
  python -c "
d=open('$f','rb').read()
print('$f', 'loneLF:', d.count(b'\n')-d.count(b'\r\n'), 'nonascii:', sum(1 for b in d if b>127))"
done
```
Expected: `loneLF: 0 nonascii: 0` for every file. Fix any file that fails before committing.

- [ ] **Step 7: Commit**

```bash
git add src/project/DRagLint.Project.OwnRoots.pas src/cli/drag-lint.dpr src/cli/drag-lint.dproj src/cli/DRagLint.CLI.pas tests/fixtures/own-roots
git commit -m "feat(lint): declare a project's own roots in _D-RAG/drag-lint-project.json"
```

---

### Task 5: Scope `lint-all` to our code

**Files:**
- Modify: `src\cli\DRagLint.CLI.pas` -- `DoLintAll` at `:9366`, the enumeration loop at `:9440-9448`, the project-wide block at `:9563-9577`, arg parsing at `:~823`, usage at `:486`
- Create: `tests\autotest\run_lint_own_roots.ps1`

**Interfaces:**
- Consumes: `TOwnRoots`, `AnchorDirForDb` from Task 4.
- Produces: `--lint-third-party` on `lint-all`; the `lint-all: N file(s) outside the project's own roots skipped` report block.

- [ ] **Step 1: Write the failing test**

Create `tests\autotest\run_lint_own_roots.ps1`:

```powershell
$Exe = . "$PSScriptRoot\_manifest_common.ps1"
$fx  = "$PSScriptRoot\..\fixtures\own-roots"

$ur = & $Exe selftest own-roots --dir $fx 2>&1 | Out-String
Check 'own-roots selftest' ($ur -match 'OWNROOTS-OK')

# Index the fixture project INTO its _D-RAG home, the way the real layout works.
$db = Join-Path $fx 'proj\_D-RAG\App.sqlite'
if (Test-Path $db) { Remove-Item -Force $db }
& $Exe index $fx --db $db | Out-Null
Check 'fixture indexed' (Test-Path $db)

$rep = Join-Path $env:TEMP 'draglint_ownroots_report.txt'

# 1. Bare run: vendor\ is outside the declared roots, so it is skipped and named.
$bare = & $Exe lint-all --db $db --output $rep --quiet 2>&1 | Out-String
Check 'scan excludes vendor'   ($bare -notmatch 'Vendor\.pas')
Check 'skip line present'      ($bare -match "outside the project's own roots skipped")
Check 'skip NAMES the root'    ($bare -match 'vendor')
Check 'declared root included' ((Get-Content $rep -Raw) -match 'Shared\.pas|App\.pas')

# 2. A project-wide rule must not pair our code with vendored code.
#    App.pas and Vendor.pas are exact clones; duplicate-code must stay silent.
Check 'no clone across the boundary' ((Get-Content $rep -Raw) -notmatch 'duplicate-code')

# 3. --lint-third-party restores the old behaviour.
$all = & $Exe lint-all --db $db --output $rep --quiet --lint-third-party 2>&1 | Out-String
Check 'third-party flag re-includes' ((Get-Content $rep -Raw) -match 'Vendor\.pas')
Check 'clone found when included'    ((Get-Content $rep -Raw) -match 'duplicate-code')

# 4. An empty ownRoots is a usage error, not "own nothing".
$decl = Join-Path $fx 'proj\_D-RAG\drag-lint-project.json'
$keep = Get-Content $decl -Raw
try {
    Set-Content -LiteralPath $decl -Value '{ "ownRoots": [] }' -NoNewline
    $bad = & $Exe lint-all --db $db --output $rep --quiet 2>&1 | Out-String
    Check 'empty ownRoots exits 2'   ($LASTEXITCODE -eq 2)
    Check 'empty ownRoots explains'  ($bad -match 'ownRoots')
} finally { Set-Content -LiteralPath $decl -Value $keep -NoNewline }

if ($script:Failed) { exit 1 } else { exit 0 }
```

- [ ] **Step 2: Run it to verify it fails**

Run: `pwsh -File tests\autotest\run_lint_own_roots.ps1`
Expected: FAIL -- `scan excludes vendor` fails (Vendor.pas is linted today), `skip line present` fails (no such line).

- [ ] **Step 3: Add the flag and the anchor resolver**

In `src\cli\DRagLint.CLI.pas`, add `LintThirdParty: Boolean` to `TArgs`, parse it beside the other switches (`:~823`):

```pascal
    else if A = '--lint-third-party' then Result.LintThirdParty:= True
```

Add above `DoLintAll` (uses `DRagLint.Project.OwnRoots` -- add to the implementation `uses`):

```pascal
{ The project folder a lint run is anchored to: --project when given, else the
  index's own _D-RAG parent, else the manifest section that claims this DB.
  The manifest step is not dead weight after the migration -- a section may pin
  an explicit "db" outside any _D-RAG (the read-only/network-share escape
  hatch), and such a project would otherwise silently lose its declaration.
  '' means no anchor could be determined, which TOwnRoots.Load turns into
  "filtering off" rather than "own nothing": an ad-hoc --db must keep working
  exactly as it did before this feature existed. }
function LintAnchorDir(const AArgs: TArgs; const ADbPath: string): string;
var
  Manifest: TIndexManifest;
  I       : Integer       ;
  ProjFile: string        ;
begin
  if AArgs.ProjectPath <> '' then
    Exit(ExcludeTrailingPathDelimiter(ExtractFilePath(TPath.GetFullPath(AArgs.ProjectPath))));

  Result:= AnchorDirForDb(ADbPath);
  if Result <> '' then Exit;

  try
    Manifest:= TManifestIO.Load(ExtractFilePath(ParamStr(0)), GetCurrentDir);
    for I:= 0 to High(Manifest.Sections) do
    begin
      ProjFile:= SectionProjectFile(Manifest, Manifest.Sections[I]);
      if ProjFile = '' then Continue;
      if SameText(ExpandSectionDb(Manifest, Manifest.Sections[I]), ExpandFileName(ADbPath)) then
        Exit(ExcludeTrailingPathDelimiter(ExtractFilePath(ProjFile)));
    end;
  except
    { No manifest, or an unreadable one, is not a lint failure. }
    on E: Exception do Result:= '';
  end;
end;

{ Collapse skipped files into the fewest honest lines. Grouping by directory
  would print DelphiAST twice (Source, and Source\SimpleParser) instead of
  naming the dependency once, so each file's group is the HIGHEST ancestor
  directory that is not itself an ancestor of one of our own roots: walking up
  from DelphiAST\Source\SimpleParser stops at C:\Projects\DelphiAST, because the
  next step reaches C:\Projects, which contains our own root C:\Projects\YADF. }
function GroupKeyFor(const AFilePath: string; const AOwn: TOwnRoots): string;
var
  Dir, Parent, R: string;
  Blocked       : Boolean;
begin
  Result:= ExtractFileDir(ExpandFileName(AFilePath));
  while True do
  begin
    Dir   := Result;
    Parent:= ExtractFileDir(Dir);
    if (Parent = '') or SameText(Parent, Dir) then Break;   { drive root }
    Blocked:= False;
    for R in AOwn.Roots do
      if StartsText(IncludeTrailingPathDelimiter(Parent), R) then begin Blocked:= True; Break; end;
    if Blocked then Break;
    Result:= Parent;
  end;
end;
```

- [ ] **Step 4: Filter the per-file scan**

In `DoLintAll`, replace the enumeration loop (`:9438-9448`) with:

```pascal
  var Cfg: TLintConfig:= LoadLintConfig(AArgs);
  { Ownership is a SCOPE decision, exactly like exclude_paths, so it belongs
    here -- before the scan, so an out-of-scope file never reaches the scanner
    and the banner counts what was actually scanned. }
  var Own: TOwnRoots:= TOwnRoots.Load(LintAnchorDir(AArgs, ProjectDb));
  if Own.Error <> '' then begin EmitStatusLine(AArgs, 'ERROR: ' + Own.Error); Exit(2); end;
  FilePaths:= nil;
  var ExcludedCount: Integer:= 0;
  var SkippedThird : TArray<string>:= nil;
  for Fid in Store.GetAllFileIds do
  begin
    PasPath:= Store.GetFilePath(Fid);
    if SameText(ExtractFileExt(PasPath), '.pas') and TFile.Exists(PasPath) then
    begin
      if Cfg.IsPathExcluded(PasPath) then begin Inc(ExcludedCount); Continue; end;
      if (not AArgs.LintThirdParty) and (not Own.IsOurs(PasPath)) then
        begin SkippedThird:= SkippedThird + [PasPath]; Continue; end;
      if (ScopeSet = nil) or ScopeSet.ContainsKey(ScopeKey(PasPath)) then FilePaths:= FilePaths + [PasPath];
    end;
  end;
```

Then after the existing `exclude_paths` status line (`:9456`), add the skip report:

```pascal
  { A scope filter that reports nothing is indistinguishable from a clean
    codebase. Name what was dropped, grouped, and say how to include it. }
  if Length(SkippedThird) > 0 then
  begin
    EmitStatusLine(AArgs, Format('lint-all: %d file(s) outside the project''s own roots skipped', [Length(SkippedThird)]));
    var Groups: TDictionary<string, Integer>:= TDictionary<string, Integer>.Create;
    try
      for var SkPath: string in SkippedThird do
      begin
        var K: string:= GroupKeyFor(SkPath, Own);
        var N: Integer:= 0;
        Groups.TryGetValue(K, N);
        Groups.AddOrSetValue(K, N + 1);
      end;
      var Keys: TArray<string>:= Groups.Keys.ToArray;
      TArray.Sort<string>(Keys, TComparer<string>.Construct(
        function(const L, R: string): Integer
        begin Result:= Groups[R] - Groups[L]; end));
      for var Idx: Integer:= 0 to Min(9, High(Keys)) do
        EmitStatusLine(AArgs, Format('          %6d  %s', [Groups[Keys[Idx]], Keys[Idx]]));
      if Length(Keys) > 10 then
        EmitStatusLine(AArgs, Format('          + %d more root(s)', [Length(Keys) - 10]));
      if Own.Anchor <> '' then
        EmitStatusLine(AArgs, Format('          declare in %s to include; --lint-third-party to lint everything',
          [TPath.Combine(TPath.Combine(Own.Anchor, DRAG_HOME_DIR), 'drag-lint-project.json')]));
    finally
      Groups.Free;
    end;
  end;
```

- [ ] **Step 5: Filter the project-wide findings**

Immediately before the existing `if ScopeSet <> nil then` block (`:9568`):

```pascal
  { The per-file filter above only narrowed the SCAN. Every rule between the
    scan and here reads the whole store -- god-class, clone detection, layering,
    the doc rules, used-unit-not-resolvable -- so without this the third-party
    findings walk straight back in through the project-wide pass. Exactly the
    failure the --project ScopeSet filter below already documents.
    A finding with no file path belongs to the run, not to a file: keep it. }
  if (not AArgs.LintThirdParty) and Own.Active then
  begin
    var Ours: TArray<TLintFinding>:= nil;
    for F in Findings do
      if (F.FilePath = '') or Own.IsOurs(F.FilePath) then Ours:= Ours + [F];
    Findings:= Ours;
  end;
```

Add the flag to the `lint-all` usage line (`:486`):

```pascal
  Writeln('  drag-lint lint-all           [--db <file.sqlite>] [--project <.dproj>] [--disable id,...] [--output <report.txt>] [--json] [--quiet] [--lint-third-party]');
```

- [ ] **Step 6: Rebuild and run the test to verify it passes**

Run: `pwsh -File tests\autotest\run_lint_own_roots.ps1`
Expected: every Check PASS, exit 0.

- [ ] **Step 7: Commit**

```bash
git add src/cli/DRagLint.CLI.pas tests/autotest/run_lint_own_roots.ps1
git commit -m "fix(lint): lint-all counts only the project's own code

768 of YADF's 1,072 findings were in vendored DelphiAST."
```

---

### Task 6: Declare the two real projects and measure the effect

**Files:**
- Create: `C:\Projects\DB\ORM3\{CLIENT,SERVER,PACKAGE}\_D-RAG\drag-lint-project.json` and the four `TESTER\*\_D-RAG\` equivalents (8 sections total)
- Create: `C:\Projects\TableTools\_D-RAG\drag-lint-project.json`

**Interfaces:**
- Consumes: everything from Tasks 1-5.
- Produces: measured before/after numbers for the resume doc in Task 7.

- [ ] **Step 1: Re-deploy, then record the baseline**

Task 5 changed `DoLintAll`, so the deployed engine is stale again. Re-deploy
before measuring or the numbers describe the old binary:

```bash
cp src/cli/Win64/Debug/drag-lint.exe third_party/dll-win64/drag-lint.exe
```

```bash
cd third_party/dll-win64
./drag-lint.exe lint-all --db C:/Projects/YADF/_D-RAG/YADF.sqlite --quiet --lint-third-party --output C:/TEMP/claude/yadf_before.txt 2>&1 | tail -3
./drag-lint.exe lint-all --db C:/Projects/DB/ORM3/CLIENT/_D-RAG/Micronite2027.sqlite --quiet --lint-third-party --output C:/TEMP/claude/orm3_before.txt 2>&1 | tail -3
```
Expected: YADF reports 1,072 findings (the recorded number).

- [ ] **Step 2: Write the declarations**

Each of the 8 ORM3 project folders gets `_D-RAG\drag-lint-project.json`. From `CLIENT`, `SERVER` and `PACKAGE` the root is one level up; from the four `TESTER\<name>` folders it is two:

```json
{
  "_comment": [
    "ORM3 is ONE codebase spread over sibling folders, each of which Mercurial",
    "makes its own repository -- CLIENT, SERVER, COMMON and OBJECTS are four hg",
    "roots of one program. Declaring the shared parent keeps COMMON\\OBJECTS",
    "(268 units of business objects) in the lint scope while leaving PDFlibPas,",
    "which the projects merely compile, out of it.",
    "Relative to this file's project folder, so the declaration survives a move."
  ],
  "ownRoots": [".."]
}
```

For `TESTER\Tests`, `TESTER\CachedUpdates`, `TESTER\PdfOcrImport`, `TESTER\TEST_uSetupDefaultsFrm`, use `"ownRoots": ["..\\.."]`.

`C:\Projects\TableTools\_D-RAG\drag-lint-project.json` -- TableTools legitimately compiles ORM3 shared units, so it declares both:

```json
{
  "_comment": [
    "TableTools compiles 8 units from the ORM3 shared tree (COMMON, SERVER);",
    "those are ours. C:\\Projects\\tzdb is vendored and is not."
  ],
  "ownRoots": [".", "C:\\Projects\\DB\\ORM3"]
}
```

- [ ] **Step 3: Measure the effect**

```bash
cd third_party/dll-win64
./drag-lint.exe lint-all --db C:/Projects/YADF/_D-RAG/YADF.sqlite --quiet --output C:/TEMP/claude/yadf_after.txt 2>&1 | tail -6
./drag-lint.exe lint-all --db C:/Projects/DB/ORM3/CLIENT/_D-RAG/Micronite2027.sqlite --quiet --output C:/TEMP/claude/orm3_after.txt 2>&1 | tail -6
```

Expected, and these are the acceptance numbers for the whole plan:
- YADF: **1,072 -> 304** findings; the skip block names `C:\Projects\DelphiAST` with 8 files.
- ORM3-Micronite2027: scans **565** files, not 641; the skip block names `C:\Projects\PDFlibPas` with 76 files; the 295 `COMMON\OBJECTS` files are still scanned.

If YADF's count is not 304, do NOT adjust the number to match -- find out why. The 304 was measured directly on 2026-08-11 and is recorded in the spec.

- [ ] **Step 4: Verify the ORM3 shared tree really is still in scope**

```bash
grep -c 'ORM3\\COMMON\\OBJECTS' C:/TEMP/claude/orm3_after.txt   # must be > 0
grep -c 'PDFlibPas'             C:/TEMP/claude/orm3_after.txt   # must be 0
```

- [ ] **Step 5: Commit**

The declarations live outside this repository (in ORM3 and TableTools), so there is nothing to `git add` here. Record the numbers in the commit for Task 7 instead. Confirm `git status` in this repo shows no unexpected changes.

---

### Task 7: Consumers, docs, and the full battery

**Files:**
- Modify: `src\delphi-plugin\DragLint.Plugin.Settings.pas:58` (DB path template), `DragLint.Plugin.DbResolver.pas`, `DragLint.Plugin.Editor.pas:4944-4946`
- Modify: `README.md`, `docs\INDEXING-AND-DB-ARCHITECTURE.md`, `docs\SCAN-DATABASES.md`, `docs\INSTALL.md`, `docs\editors\vscode-and-zed-mcp.md`, `CHANGELOG.md`, `skills\relint\SKILL.md`
- Modify: `C:\Projects\CLAUDE.md` (the shared Delphi context all sessions read)
- Modify: `tests\autotest\run_exe_freshness.ps1`, `run_wiring.ps1`, `run_qname_row_order.ps1`, `run_hover_qname_row_order.ps1`, `tests\run_battery.ps1`, `tools\measure\phase1_verify.py`, `tools\measure\uses_target_replay.py` -- only where a hardcoded `C:\Projects\.drag-lint\<Name>.sqlite` path now points at a moved DB

**Interfaces:**
- Consumes: the finished layout from Task 3 and the flag from Task 5.
- Produces: a green battery and documentation that matches reality.

- [ ] **Step 1: Update the IDE plugin's DB path template**

`src\delphi-plugin\DragLint.Plugin.Settings.pas:58` currently defaults to `'<projdir>\drag-lint.sqlite'`. Change it to the project's home:

```pascal
  Result.DbPathTemplate       := '<projdir>\' + DRAG_HOME_DIR + '\<projname>.sqlite';
```

Extend `ResolveDbPath` (`:198`) to substitute `<projname>` with the project file's base name alongside the existing `<projdir>`. Keep `<projdir>\drag-lint.sqlite` working as a fallback probe in `ResolveActiveIndexDbs` so an IDE whose registry still holds the old template keeps finding an index. Update the stale comment at `Editor.pas:4944-4946`, which claims the index is "NOT next to the .dproj" -- it now is.

- [ ] **Step 2: Rebuild both packages**

The battery builds the CLI, not the package -- that is exactly how commit `41134be` shipped a broken BPL. Build `src\delphi-plugin\dclDragLintWizard.dproj` for Win32 and Win64 per the `delphi-build` recipe, with the IDE closed.
Expected: `BUILD_EXITCODE=0`, no `[dcc] Error` in either log.

- [ ] **Step 3: Update the current-state docs**

Rewrite the DB-location sections of `README.md`, `docs\INDEXING-AND-DB-ARCHITECTURE.md`, `docs\SCAN-DATABASES.md`, `docs\INSTALL.md`, `docs\editors\vscode-and-zed-mcp.md` and `skills\relint\SKILL.md` to describe `<project folder>\_D-RAG\<project>.sqlite`, with `C:\Projects\.drag-lint` retained only for `library-{platform}.sqlite`. Add a `CHANGELOG.md` entry covering both the relocation and the lint scoping.

Update `C:\Projects\CLAUDE.md`'s "Delphi code search" section: DB paths, the `resolve-dbs` advice (unchanged, still the right answer), and a new line stating that `lint-all` reports only the project's own code and that `_D-RAG\drag-lint-project.json` declares the roots.

Leave `.superpowers\sdd\*`, `docs\superpowers\plans\*` and old `RESUME-*` / `INBOX-*` documents alone -- they are dated records (spec section 2).

- [ ] **Step 4: Fix the battery scripts' hardcoded paths**

```bash
grep -rn 'Projects\\\.drag-lint\|Projects/\.drag-lint' tests/ tools/measure/ --include='*.ps1' --include='*.py'
```
For each hit, decide: a `library-*.sqlite` reference stays; a project DB reference moves to the `_D-RAG` path.

- [ ] **Step 5: Run the full battery**

Run: `pwsh -File tests\run_battery.ps1`
Expected: **at least 251/253** -- the previous baseline was 249/253 with 4 known failures (2 stale rule-count expectations from the naming split, the lone-LF guard on untracked `tools\lsp-diag`, exe-freshness). The two new runners add 2 passes. Any NEW failure must be fixed, not accepted. Lint fixtures must stay 161/161 and lint-store 16/16.

- [ ] **Step 6: Reindex one project and confirm the derived path is used end to end**

```bash
cd third_party/dll-win64
./drag-lint.exe index --all --only YADF --dry-run     # must name the _D-RAG path
./drag-lint.exe index --all --only YADF
./drag-lint.exe query --name TYadfLayout --db C:/Projects/YADF/_D-RAG/YADF.sqlite | head -5
```
Expected: the dry-run names `C:\Projects\YADF\_D-RAG\YADF.sqlite`; the index run writes there (no new file appears in `C:\Projects\.drag-lint`); the query returns rows.

- [ ] **Step 7: Commit**

```bash
git add -A src/delphi-plugin README.md CHANGELOG.md docs skills tests tools
git commit -m "docs+plugin: the project _D-RAG home is the documented index location

lint-all now reports only the project's own code: YADF 1,072 -> 304 findings,
ORM3-Micronite2027 scans 565 files instead of 641 while keeping all 295 of its
COMMON\\OBJECTS units."
```

---

## Acceptance

- `drag-lint lint-all --db C:\Projects\YADF\_D-RAG\YADF.sqlite` reports **304** findings, names `C:\Projects\DelphiAST` as skipped, and `--lint-third-party` restores 1,072.
- ORM3-Micronite2027 scans 565 files, keeps `COMMON\OBJECTS`, drops `PDFlibPas`.
- All 27 project indexes live in a `_D-RAG` folder, open cleanly, and report the same `files` row counts as before the move.
- `pwsh -File tests\run_battery.ps1` is at or above 251/253 with no new failure.
- Both BPLs build.
