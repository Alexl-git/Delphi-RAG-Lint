# Two-DB Model Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Auto-select Project DB + platform-specific Library DB when no `--db` flag is given, deriving platform from `.dproj` on the CLI and from `IOTAProject.CurrentPlatform` in the plugin.

**Architecture:** Two independent changes — (A) CLI `ResolveConsumerDbs` gains `.dproj` platform detection so the right `library-{platform}.sqlite` is included automatically; (B) plugin `GetLibraryDbPath` is replaced with a platform-aware variant that reads `outDir` from the manifest and uses the live OTAPI platform. `index` gains manifest-based project-DB auto-selection. No manifest schema changes.

**Tech Stack:** Delphi 13 / Object Pascal; XMLDoc or string-search for .dproj parsing; existing `TManifestIO`, `TDbSelect`, `TIndexManifest` types; OTAPI `IOTAProject.CurrentPlatform`.

## Global Constraints

- All `.pas` files: strict 7-bit ASCII, CRLF line endings. Never introduce Unicode or LF-only.
- DocInsight `///` triple-slash on every new public declaration.
- `try-finally` for all resource allocations.
- Build: `build\pack-lint-release.ps1 -Version X` or plain msbuild with rsvars.bat. See CLAUDE.md for canonical build command.
- Delphi 13 syntax: `if` ternary, `is not`, inline `var`.
- Spec: `docs/superpowers/specs/2026-06-26-two-db-model-design.md`

---

## File Map

| File | Change |
|---|---|
| `src\cli\DRagLint.CLI.pas` | Add `DetectPlatformFromDproj`; wire into `ResolveConsumerDbs`; fix `DoIndex` auto-DB |
| `src\delphi-plugin\DragLint.Plugin.DbResolver.pas` | Add `GetPlatformAwareLibraryDbPath`; call it from `ResolveActiveIndexDbs` |

No other files change.

---

## Background — what already works (read before touching code)

- `DoQuery`, `DoLint`, `DoFormsMap`, `DoLintProject` all call `ResolveConsumerDbs(AArgs)` which calls `TDbSelect.Resolve`. `TDbSelect.Resolve` already includes the library section DB at the end of the result when it matches the requested platform. **These commands already get two DBs** — the only bug is that the platform defaults to `Manifest.Settings.DefaultPlatform` (`"Win32"`) even when the project is Win64.
- `AArgs.CheckPlatform` is a field on `TArgs` populated from `--platform`; it is already parsed globally in `ParseArgs` so all subcommands already accept `--platform`.
- Plugin `ResolveActiveIndexDbs` already calls `GetLibraryDbPath` and `IncludeLibraryDb` already defaults to `True`. The bug is that `GetLibraryDbPath` searches the BPL directory first (not `C:\Projects\.drag-lint\`) and picks Win32 regardless of the active project.
- `DoIndex` uses `AArgs.DbPath` which defaults to `drag-lint.sqlite` in the CWD — currently no manifest lookup.

---

## Task 1 — CLI: `.dproj` platform detection in `ResolveConsumerDbs`

**Files:**
- Modify: `src\cli\DRagLint.CLI.pas` (around line 7507 — `ResolveConsumerDbs`; add helper above it)

**What to add:** A private helper `DetectPlatformFromDproj` that, given the manifest and CWD, finds the manifest section whose `include` path is an ancestor of CWD (longest-prefix match), finds the first `*.dproj` file in that section's include directory, and parses the `<Platform Condition="'$(Platform)'==''">Win64</Platform>` element.

- [ ] **Step 1: Write the failing test**

Add to `tests\cli\` (or run manually — drag-lint has no formal CLI unit test harness; use a manual integration test described in Step 5). For now, locate the test fixture area and note the manual test command:

```
drag-lint resolve-dbs --json
```
Run from `C:\Projects\DB\ORM3\CLIENT`. Expected current (wrong) output: includes `library-Win32.sqlite`. Expected after fix: includes `library-Win64.sqlite`.

Record the current (broken) output so you can verify the fix.

- [ ] **Step 2: Add `DetectPlatformFromDproj` helper in `DRagLint.CLI.pas`**

Add this function immediately before `ResolveConsumerDbs` (around line 7505). Use a simple string search — no XMLDoc dependency needed for this single well-known element:

```pascal
/// <summary>Reads the default platform from the first .dproj found under the
/// manifest section that covers ACwd. Returns '' if not found.</summary>
function DetectPlatformFromDproj(const AManifest: TIndexManifest;
  const ACwd: string): string;
var
  Sections : TArray<TIndexSection> ;
  Sec      : TIndexSection         ;
  BestLen  : Integer               ;
  BestInc  : string                ;
  IncPath  : string                ;
  CwdNorm  : string                ;
  IncNorm  : string                ;
  DprojFile: string                ;
  DprojFiles: TArray<string>       ;
  Xml      : string                ;
  P1, P2   : Integer               ;
begin
  Result:= '';
  CwdNorm:= IncludeTrailingPathDelimiter(
              TPath.GetFullPath(ACwd)).ToLower;
  BestLen:= -1;
  BestInc:= '';

  // Find manifest section whose include is the longest ancestor of ACwd.
  Sections:= AManifest.Indexes.Sections;
  for Sec in Sections do
  begin
    for IncPath in Sec.Include do
    begin
      IncNorm:= IncludeTrailingPathDelimiter(
                  TPath.GetFullPath(IncPath)).ToLower;
      if CwdNorm.StartsWith(IncNorm) and (Length(IncNorm) > BestLen) then
      begin
        BestLen:= Length(IncNorm);
        BestInc:= IncPath;
      end;
    end;
  end;

  if BestInc = '' then Exit;

  // Find first .dproj under that include path.
  try
    DprojFiles:= TDirectory.GetFiles(BestInc, '*.dproj',
                   TSearchOption.soTopDirectoryOnly);
    if Length(DprojFiles) = 0 then
      DprojFiles:= TDirectory.GetFiles(BestInc, '*.dproj',
                     TSearchOption.soAllDirectories);
    if Length(DprojFiles) = 0 then Exit;
    DprojFile:= DprojFiles[0];
  except
    Exit;
  end;

  // Parse <Platform Condition="'$(Platform)'==''">Win64</Platform>
  try
    Xml:= TFile.ReadAllText(DprojFile);
  except
    Exit;
  end;
  // Locate the conditional default Platform element (not the per-config ones).
  P1:= Pos('Condition=''', Xml);
  while P1 > 0 do
  begin
    // Check it's a <Platform ...> element (scan back ~50 chars for '<Platform')
    var TagStart: Integer:= P1;
    while (TagStart > 1) and (Xml[TagStart] <> '<') do Dec(TagStart);
    if Xml.Substring(TagStart - 1, 9).ToLower = '<platform' then
    begin
      // Find closing '>' then extract text until '<'
      P1:= Pos('>', Xml, P1);
      if P1 = 0 then Break;
      P2:= Pos('<', Xml, P1 + 1);
      if P2 = 0 then Break;
      Result:= Xml.Substring(P1, P2 - P1 - 1).Trim;
      if (Result = 'Win32') or (Result = 'Win64') then Exit;
      Result:= '';
    end;
    P1:= Pos('Condition=''', Xml, P1 + 1);
  end;
end;
```

- [ ] **Step 3: Wire into `ResolveConsumerDbs`**

In `ResolveConsumerDbs` (around line 7520), change the platform resolution block from:

```pascal
if AArgs.CheckPlatform <> '' then Platform:= AArgs.CheckPlatform
else Platform:= Manifest.Settings.DefaultPlatform;
```

to:

```pascal
if AArgs.CheckPlatform <> '' then
  Platform:= AArgs.CheckPlatform
else
begin
  Platform:= DetectPlatformFromDproj(Manifest, GetCurrentDir);
  if Platform = '' then Platform:= Manifest.Settings.DefaultPlatform;
end;
```

- [ ] **Step 4: Run integration test**

```
cd C:\Projects\DB\ORM3\CLIENT
C:\Projects\Delphi-RAG-lint\third_party\dll-win64\drag-lint.exe resolve-dbs --json
```

Expected: JSON array containing `C:\Projects\DB\ORM3\drag-lint.sqlite` and `C:\Projects\.drag-lint\library-Win64.sqlite`. Verify `Win64` appears, not `Win32`.

Also run from a non-ORM3 dir to verify fallback:
```
cd C:\Projects\Delphi-RAG-lint
C:\Projects\Delphi-RAG-lint\third_party\dll-win64\drag-lint.exe resolve-dbs --json
```
Expected: DragLint project DB + library for its default platform (check manifest default).

- [ ] **Step 5: Normalize CRLF on the modified file section**

After editing, run:
```powershell
$f = "C:\Projects\Delphi-RAG-lint\src\cli\DRagLint.CLI.pas"
$t = [System.IO.File]::ReadAllText($f) -replace "\r\n","`n" -replace "`n","`r`n"
[System.IO.File]::WriteAllText($f, $t, [System.Text.Encoding]::Default)
```

- [ ] **Step 6: Build (Win64)**

```powershell
& "C:\Projects\Delphi-RAG-lint\build\pack-lint-release.ps1" -Version "0.60.0-alpha"
```
Expected: exits 0, `third_party\dll-win64\drag-lint.exe` updated.

- [ ] **Step 7: Commit**

```
git -C C:\Projects\Delphi-RAG-lint add src\cli\DRagLint.CLI.pas
git -C C:\Projects\Delphi-RAG-lint commit -m "feat(cli): detect platform from .dproj in ResolveConsumerDbs"
```

---

## Task 2 — Plugin: platform-aware library DB

**Files:**
- Modify: `src\delphi-plugin\DragLint.Plugin.DbResolver.pas`

**What to add:** A new function `GetPlatformAwareLibraryDbPath(const ASettings: TDragLintSettings): string` that reads `outDir` from the manifest (same logic already in `ManifestDbForFile` lines 113–115) and uses `GetActiveProjectPlatform()` to build `library-{platform}.sqlite`. Called from `ResolveActiveIndexDbs` instead of the current `GetLibraryDbPath` call.

**Key existing functions:**
- `GetActiveProjectPlatform(): string` — already in `DragLint.Plugin.Editor.pas`; calls `IOTAProject.CurrentPlatform`; returns `'Win64'` for ORM3
- `GetLibraryDbPath(): string` — current function; tries exe-relative paths; returns Win32 first
- `ResolveActiveIndexDbs` (line 409) — calls `GetLibraryDbPath` at lines ~446–448; keep as fallback

- [ ] **Step 1: Verify test baseline**

Open the plugin in the IDE, use a `.pas` file from ORM3 as the active editor file, then invoke drag-lint "Find Usages" or check the resolver diagnostic. Note which library DB path appears in `DLT('dbresolve', ...)` output or in the query results. It should currently show `library-Win32.sqlite` or `drag-lint-library.sqlite` (wrong for Win64 projects).

- [ ] **Step 2: Add `GetManifestOutDir` private helper**

Add before `GetLibraryDbPath` in `DragLint.Plugin.DbResolver.pas`:

```pascal
/// <summary>Returns the indexes.outDir from the drag-lint manifest beside the
/// engine exe, or empty string if the manifest cannot be read.</summary>
function GetManifestOutDir(const ASettings: TDragLintSettings): string;
var
  EngineDir: string;
  ManPath  : string;
  Json     : TJSONObject;
  Indexes  : TJSONValue;
  OutDirVal: TJSONValue;
  Content  : string;
begin
  Result:= '';
  try
    EngineDir:= ExtractFilePath(ASettings.EnginePath);
    if EngineDir = '' then Exit;
    ManPath:= TPath.Combine(EngineDir, 'drag-lint.json');
    if not TFile.Exists(ManPath) then Exit;
    Content:= TFile.ReadAllText(ManPath);
    Json:= TJSONObject.ParseJSONValue(Content) as TJSONObject;
    if Json = nil then Exit;
    try
      Indexes:= Json.GetValue('indexes');
      if not (Indexes is TJSONObject) then Exit;
      OutDirVal:= TJSONObject(Indexes).GetValue('outDir');
      if OutDirVal is TJSONString then
        Result:= TJSONString(OutDirVal).Value;
    finally
      Json.Free;
    end;
  except
    Result:= '';
  end;
end;
```

- [ ] **Step 3: Add `GetPlatformAwareLibraryDbPath`**

Add immediately after `GetManifestOutDir`:

```pascal
/// <summary>Returns the platform-specific library DB path using the manifest
/// outDir and the currently active project's platform from OTAPI.
/// Falls back to GetLibraryDbPath if the manifest or file is unavailable.</summary>
function GetPlatformAwareLibraryDbPath(
  const ASettings: TDragLintSettings): string;
var
  OutDir  : string;
  Platform: string;
  Db      : string;
begin
  OutDir:= GetManifestOutDir(ASettings);
  if OutDir <> '' then
  begin
    Platform:= GetActiveProjectPlatform; // IOTAProject.CurrentPlatform
    if Platform = '' then Platform:= 'Win64';
    Db:= TPath.Combine(OutDir, 'library-' + Platform + '.sqlite');
    if TFile.Exists(Db) then Exit(Db);
    // Platform DB missing — fall through to legacy search.
  end;
  Result:= GetLibraryDbPath; // existing fallback: exe-relative Win32/Win64/legacy
end;
```

- [ ] **Step 4: Wire into `ResolveActiveIndexDbs`**

In `ResolveActiveIndexDbs` (line 409), there are two call sites for `GetLibraryDbPath` (lines ~446 and ~414 in the two branches). Replace **both** with `GetPlatformAwareLibraryDbPath(ASettings)`:

Find:
```pascal
    LibPath:= GetLibraryDbPath;
```
Replace both occurrences with:
```pascal
    LibPath:= GetPlatformAwareLibraryDbPath(ASettings);
```

- [ ] **Step 5: Normalize CRLF**

```powershell
$f = "C:\Projects\Delphi-RAG-lint\src\delphi-plugin\DragLint.Plugin.DbResolver.pas"
$t = [System.IO.File]::ReadAllText($f) -replace "\r\n","`n" -replace "`n","`r`n"
[System.IO.File]::WriteAllText($f, $t, [System.Text.Encoding]::Default)
```

- [ ] **Step 6: Build the plugin package**

```powershell
# Use rsvars + msbuild on the plugin .dpk
$bat = @"
call "C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\rsvars.bat"
cd C:\Projects\Delphi-RAG-lint\src\delphi-plugin
msbuild /t:Build /p:Config=Debug /p:Platform=Win32 /v:normal dclDragLintWizard.dproj > C:\TEMP\plugin-build.log 2>&1
"@
$bat | Out-File C:\TEMP\build-plugin.bat -Encoding ASCII
Start-Process cmd.exe -ArgumentList '/c C:\TEMP\build-plugin.bat' -Wait -NoNewWindow
Get-Content C:\TEMP\plugin-build.log | Select-String -Pattern "error|warning|BUILD" | Select-Object -Last 20
```

Expected: `Build succeeded`, no `[dcc] Error` lines.

- [ ] **Step 7: Verify in IDE**

Restart the IDE (to reload the BPL). Open a `.pas` file from `C:\Projects\DB\ORM3\CLIENT`. Invoke any drag-lint plugin action. Check the resolver diagnostic — library DB should now show `library-Win64.sqlite`, not `library-Win32.sqlite` or `drag-lint-library.sqlite`.

- [ ] **Step 8: Commit**

```
git -C C:\Projects\Delphi-RAG-lint add src\delphi-plugin\DragLint.Plugin.DbResolver.pas
git -C C:\Projects\Delphi-RAG-lint commit -m "feat(plugin): platform-aware library DB via manifest outDir + OTAPI platform"
```

---

## Task 3 — CLI: `index` auto-selects Project DB from manifest

**Files:**
- Modify: `src\cli\DRagLint.CLI.pas` (`DoIndex`, around line 1315)

**Goal:** When `index` is called with a path but no `--db`, look up the manifest section that covers that path and use its `db` value instead of defaulting to `drag-lint.sqlite` in CWD.

- [ ] **Step 1: Add `ResolveIndexDb` helper before `DoIndex`**

```pascal
/// <summary>Resolves the DB path for an index operation. If --db was given
/// explicitly, returns it unchanged. Otherwise finds the manifest section
/// whose include path covers AIndexPath and returns that section's db.
/// Falls back to AArgs.DbPath (default: drag-lint.sqlite in CWD).</summary>
function ResolveIndexDb(const AArgs: TArgs; const AIndexPath: string): string;
var
  Manifest : TIndexManifest;
  Sections : TArray<TIndexSection>;
  Sec      : TIndexSection;
  IncPath  : string;
  CwdNorm  : string;
  IncNorm  : string;
  BestLen  : Integer;
  BestDb   : string;
  EngineDir: string;
begin
  // Explicit --db always wins.
  if Length(AArgs.DbPaths) > 0 then Exit(AArgs.DbPath);

  BestLen:= -1;
  BestDb := '';
  try
    EngineDir:= ExtractFilePath(ParamStr(0));
    Manifest:= TManifestIO.Load(EngineDir, AIndexPath);
    CwdNorm:= IncludeTrailingPathDelimiter(
                TPath.GetFullPath(AIndexPath)).ToLower;
    Sections:= Manifest.Indexes.Sections;
    for Sec in Sections do
    begin
      // Skip library sections — never auto-select them for index.
      if SameText(Sec.Source, 'registry-libraries') then Continue;
      for IncPath in Sec.Include do
      begin
        IncNorm:= IncludeTrailingPathDelimiter(
                    TPath.GetFullPath(IncPath)).ToLower;
        if CwdNorm.StartsWith(IncNorm) and (Length(IncNorm) > BestLen) then
        begin
          BestLen:= Length(IncNorm);
          BestDb := Sec.Db;
        end;
      end;
    end;
  except
    // Manifest unavailable — fall through to default.
  end;

  if BestDb <> '' then Result:= BestDb
  else Result:= AArgs.DbPath; // default: drag-lint.sqlite in CWD
end;
```

- [ ] **Step 2: Wire into `DoIndex`**

In `DoIndex` (around line 1370), find the line:
```pascal
  Writeln('Database: ', AArgs.DbPath);
  Store:= TSQLiteSymbolStore.Create(AArgs.DbPath);
```

Replace with:
```pascal
  var ResolvedDb: string:= ResolveIndexDb(AArgs,
    IfThen(AArgs.Path <> '', AArgs.Path, GetCurrentDir));
  Writeln('Database: ', ResolvedDb);
  Store:= TSQLiteSymbolStore.Create(ResolvedDb);
```

(`IfThen` is in `SysUtils`; already in scope.)

- [ ] **Step 3: Integration test**

```
cd C:\Projects\DB\ORM3
C:\Projects\Delphi-RAG-lint\third_party\dll-win64\drag-lint.exe index CLIENT --dry-run
```

Expected output line: `Database: C:\Projects\DB\ORM3\drag-lint.sqlite` (manifest-resolved, not `C:\Projects\DB\ORM3\drag-lint.sqlite` from CWD coincidence — confirm it's from manifest by running from a different directory):

```
cd C:\TEMP
C:\Projects\Delphi-RAG-lint\third_party\dll-win64\drag-lint.exe index C:\Projects\DB\ORM3\CLIENT
```

Expected: `Database: C:\Projects\DB\ORM3\drag-lint.sqlite` (from manifest, not `C:\TEMP\drag-lint.sqlite`).

- [ ] **Step 4: Normalize CRLF + build**

```powershell
$f = "C:\Projects\Delphi-RAG-lint\src\cli\DRagLint.CLI.pas"
$t = [System.IO.File]::ReadAllText($f) -replace "\r\n","`n" -replace "`n","`r`n"
[System.IO.File]::WriteAllText($f, $t, [System.Text.Encoding]::Default)
```

```powershell
& "C:\Projects\Delphi-RAG-lint\build\pack-lint-release.ps1" -Version "0.60.0-alpha"
```

- [ ] **Step 5: Commit**

```
git -C C:\Projects\Delphi-RAG-lint add src\cli\DRagLint.CLI.pas
git -C C:\Projects\Delphi-RAG-lint commit -m "feat(cli): index auto-selects project DB from manifest when no --db given"
```

---

## Task 4 — Release

- [ ] **Step 1: Bump VERSION in `src\cli\DRagLint.CLI.pas` line 6**

Change to `'0.60.0-alpha'` (or next version per CHANGELOG).

- [ ] **Step 2: Add CHANGELOG entry**

At the top of `CHANGELOG.md`:
```
## v0.60.0-alpha
- feat: Two-DB model — auto-select Project DB + platform library DB with no --db flags
- feat: Platform detected from .dproj <Platform> element (CLI) / IOTAProject.CurrentPlatform (plugin)
- feat: index auto-resolves project DB from manifest when no --db given
- fix(plugin): library DB now uses manifest outDir + active platform (library-Win64.sqlite for Win64 projects)
```

- [ ] **Step 3: Final build + deploy**

```powershell
& "C:\Projects\Delphi-RAG-lint\build\pack-lint-release.ps1" -Version "0.60.0-alpha"
```

- [ ] **Step 4: Tag + release**

```
git -C C:\Projects\Delphi-RAG-lint tag v0.60.0-alpha
gh release create v0.60.0-alpha --repo Alexl-git/Delphi-RAG-Lint --latest --title "v0.60.0-alpha" --notes "Two-DB model: auto-select project + platform library DB"
```

---

## Self-Review

**Spec coverage:**
- ✓ Section 1 (CLI auto-resolution): Task 1 implements `.dproj` detection + wires into `ResolveConsumerDbs`
- ✓ Section 2 (Plugin): Task 2 implements `GetPlatformAwareLibraryDbPath` with OTAPI platform + manifest outDir
- ✓ Section 3 (`index` special case): Task 3 implements `ResolveIndexDb` — project only, no library
- ✓ Section 4 (`--platform` flag): Already parsed globally by `ParseArgs`; no code change needed
- ✓ Most-specific match: Both `DetectPlatformFromDproj` and `ResolveIndexDb` use longest-prefix matching

**No placeholders found.**

**Type consistency:**
- `TIndexManifest`, `TIndexSection`, `TManifestIO.Load`, `TDbSelect.Resolve` — types used consistently from existing codebase
- `GetActiveProjectPlatform` — existing function in `DragLint.Plugin.Editor.pas`; returns `string`
- `ASettings.EnginePath` — verify this field name in `TDragLintSettings` before Task 2 Step 2; if different, adjust `GetManifestOutDir` accordingly
