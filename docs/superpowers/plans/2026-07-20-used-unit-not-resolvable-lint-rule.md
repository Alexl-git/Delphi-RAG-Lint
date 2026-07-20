# used-unit-not-resolvable Lint Rule Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Reframe the existing `unit-not-in-project` lint rule into `used-unit-not-resolvable`, which flags every `uses X` where X resolves to no known unit (project member / platform library / standard alias / RTL namespace), attaching the finding to the `uses` token line.

**Architecture:** A pure resolvability decision (`ResolveUsedUnit` + alias/RTL-namespace tables) lives in the dep-free `DRagLint.Lint.ProjectChecks.Parse` unit so it is unit-testable without a DB. The walker in `DRagLint.Lint.ProjectChecks` iterates `unit_uses`, supplies two predicates (is-project-member, is-in-library) to the pure decision, and emits a `TLintFinding` on the `uses` line when unresolvable. Wiring renames the rule id in the RuleCatalog and the two `lint-project`/`lint-all` call sites.

**Tech Stack:** Delphi 13 (Studio 37), Win64 console build (dcc64 via `build/build_draglint_win64.bat`), FireDAC/SQLite symbol store, DUnitX-free console test (`ProjectChecksTests.dpr`) + PowerShell autotest harness.

## Global Constraints

- All `.pas` source: strict 7-bit ASCII, CRLF line endings, no BOM. Verify after every Write/Edit.
- DocInsight `///` spec-comments required on every new public type/method.
- Severity strings are `error` | `warning` | `hint` | `info`. The rule uses `warning`.
- Rule must run without a `.dproj` (DB-only). Findings attach to the `uses` token, on the source unit's file.
- M2022.sqlite is NOT a resolution source (reference index only).
- Uses clauses with a non-empty `in '<path>'` locator are skipped (build-config, not resolvability).
- Namespace-blind matching: `unit_name_norm` = lowercased trailing dotted segment (existing engine behavior). Keep it.
- Build recipe: run `build/build_draglint_win64.bat` via PowerShell `Start-Process -Wait` + log; success = `BUILD_EXITCODE=0`, no `[dcc] Error`. Do NOT use the MCP build tool or `cmd.exe /c build.bat` from Bash.
- No sqlite3 on PATH -- use `python` (3.14, stdlib sqlite3, open `?mode=ro`) for DB assertions.
- Spec: `docs/superpowers/specs/2026-07-20-used-unit-not-resolvable-lint-rule-design.md`.

---

### Task 1: Pure resolvability decision + alias/RTL tables (TDD, dep-free)

**Files:**
- Modify: `src/lint/DRagLint.Lint.ProjectChecks.Parse.pas` (add pure functions + types)
- Test: `tests/projectchecks/ProjectChecksTests.dpr` (add test procedures; it already builds against `ProjectChecks.Parse`)

**Interfaces:**
- Produces (consumed by Task 2):
  - `type TUnitResolveVia = (urvNone, urvProjectMember, urvLibrary, urvAlias, urvRtlNamespace);`
  - `type TUnitResolution = record Resolvable: Boolean; Via: TUnitResolveVia; end;`
  - `function IsStandardUnitAlias(const AUnitName: string): Boolean;`
  - `function IsRtlNamespaceUnit(const AUnitName: string): Boolean;`
  - `function ResolveUsedUnit(const AUnitName: string; const AIsProjectMember, AIsInLibrary: TFunc<string, Boolean>): TUnitResolution;`
  - Resolution order inside `ResolveUsedUnit`: project member -> library -> alias -> RTL namespace -> none. `AIsProjectMember`/`AIsInLibrary` receive the NORMALIZED name (`NormUnit(AUnitName)`).

- [ ] **Step 1: Write the failing tests** — append to `ProjectChecksTests.dpr` a `TestUsedUnitResolvable` procedure and call it from the main block (add `TestUsedUnitResolvable;` after `TestStripComments;`).

```pascal
procedure TestUsedUnitResolvable;
var
  MemberSet: TArray<string>;
  LibSet   : TArray<string>;
  function InSet(const ASet: TArray<string>; const AN: string): Boolean;
  var S: string;
  begin
    Result := False;
    for S in ASet do if SameText(S, AN) then Exit(True);
  end;
  function IsMember(const AN: string): Boolean; begin Result := InSet(MemberSet, AN); end;
  function IsLib(const AN: string): Boolean;    begin Result := InSet(LibSet, AN);    end;
  function R(const AUnit: string): TUnitResolution;
  begin Result := ResolveUsedUnit(AUnit, IsMember, IsLib); end;
begin
  MemberSet := ['takejob'];             // a sibling project unit already indexed
  LibSet    := ['dbtables', 'sysutils'];// what the Win32 library fixture "knows"

  // Orpheus: not member, not lib, not alias, not RTL -> FLAG.
  Check('ovctcmmn is unresolvable', not R('ovctcmmn').Resolvable);
  Check('ovctcmmn via = none', R('ovctcmmn').Via = urvNone);

  // BDE on Win32: library knows dbtables -> resolvable.
  Check('Bde.DBTables resolvable via library (win32)', R('Bde.DBTables').Resolvable);
  Check('Bde.DBTables via = library', R('Bde.DBTables').Via = urvLibrary);

  // Standard alias: WinTypes -> resolvable via alias even if lib/member miss.
  Check('WinTypes resolvable via alias', R('WinTypes').Resolvable);
  Check('WinTypes via = alias', R('WinTypes').Via = urvAlias);

  // RTL namespace safety net: System.SysUtils, Vcl.Forms resolvable.
  Check('System.SysUtils resolvable via rtl-namespace or library',
    R('System.SysUtils').Resolvable);
  Check('Vcl.Forms resolvable via rtl-namespace', R('Vcl.Forms').Resolvable);
  Check('Vcl.Forms via = rtl-namespace', R('Vcl.Forms').Via = urvRtlNamespace);

  // Project member wins first.
  Check('TakeJob resolvable via project member', R('TakeJob').Resolvable);
  Check('TakeJob via = project-member', R('TakeJob').Via = urvProjectMember);

  // Alias table direct predicate.
  Check('IsStandardUnitAlias WinProcs', IsStandardUnitAlias('WinProcs'));
  Check('IsStandardUnitAlias DbiTypes', IsStandardUnitAlias('DbiTypes'));
  Check('IsStandardUnitAlias not-a-unit', not IsStandardUnitAlias('ovctcmmn'));

  // RTL namespace predicate (dotted + bare classics).
  Check('IsRtlNamespaceUnit System.Classes', IsRtlNamespaceUnit('System.Classes'));
  Check('IsRtlNamespaceUnit Winapi.Windows', IsRtlNamespaceUnit('Winapi.Windows'));
  Check('IsRtlNamespaceUnit bare Forms', IsRtlNamespaceUnit('Forms'));
  Check('IsRtlNamespaceUnit not ovctcmmn', not IsRtlNamespaceUnit('ovctcmmn'));
end;
```

- [ ] **Step 2: Build the test to verify it fails**

Run (PowerShell):
```powershell
& "C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\rsvars.bat"
# then build the console test:
& "$env:ProgramFiles(x86)\Embarcadero\Studio\37.0\bin\dcc64.exe" -B tests\projectchecks\ProjectChecksTests.dpr
```
Expected: FAIL to compile with `E2003 Undeclared identifier: 'ResolveUsedUnit'` (and the other new names). That is the failing state.

- [ ] **Step 3: Implement the minimal code** in `DRagLint.Lint.ProjectChecks.Parse.pas`. Add to the interface (after the existing function decls) and implementation. Use `System.SysUtils` (already used) for `TFunc`; add `System.StrUtils` to the uses if not present.

```pascal
// interface section
type
  /// <summary>How a used unit was resolved (or urvNone when unresolvable).</summary>
  TUnitResolveVia = (urvNone, urvProjectMember, urvLibrary, urvAlias, urvRtlNamespace);
  /// <summary>Result of ResolveUsedUnit: whether the unit resolves, and via which source.</summary>
  TUnitResolution = record
    Resolvable: Boolean;
    Via       : TUnitResolveVia;
  end;

/// <summary>True if AUnitName is a classic Delphi unit alias (WinTypes, WinProcs,
/// DbiTypes, DbiProcs, DbiErrs) -- the compiler maps these to a real unit, so a
/// `uses` of one is always resolvable.</summary>
function IsStandardUnitAlias(const AUnitName: string): Boolean;

/// <summary>True if AUnitName is an RTL/framework unit by namespace (System.*,
/// Vcl.*, Fmx.*, Winapi.*, Data.*, Datasnap.*, Soap.*, Web.*, FireDAC.*) or a
/// classic bare RTL name (Forms, SysUtils, Classes, Windows, ...). Belt-and-
/// suspenders so incomplete library-index coverage never false-flags core RTL.</summary>
function IsRtlNamespaceUnit(const AUnitName: string): Boolean;

/// <summary>Decide whether a used unit resolves to something known. Order:
/// project member -> platform library -> standard alias -> RTL namespace.
/// The two predicates receive the NORMALIZED name (NormUnit).</summary>
/// <param name="AUnitName">Verbatim used unit name, e.g. 'Bde.DBTables'.</param>
/// <param name="AIsProjectMember">Given a normalized stem, is it an indexed project unit?</param>
/// <param name="AIsInLibrary">Given a normalized stem, is it in the platform library DB?</param>
function ResolveUsedUnit(const AUnitName: string;
  const AIsProjectMember, AIsInLibrary: TFunc<string, Boolean>): TUnitResolution;

// implementation section
function IsStandardUnitAlias(const AUnitName: string): Boolean;
const
  ALIASES: array[0..4] of string = ('wintypes', 'winprocs', 'dbitypes', 'dbiprocs', 'dbierrs');
var
  I  : Integer;
  Low: string;
begin
  Low := LowerCase(Trim(AUnitName));
  Result := False;
  for I := Low(ALIASES) to High(ALIASES) do
    if Low = ALIASES[I] then Exit(True);
end;

function IsRtlNamespaceUnit(const AUnitName: string): Boolean;
const
  NS: array[0..8] of string = ('system.', 'vcl.', 'fmx.', 'winapi.', 'data.', 'datasnap.', 'soap.', 'web.', 'firedac.');
  BARE: array[0..14] of string = ('system', 'sysinit', 'forms', 'sysutils', 'classes',
    'windows', 'messages', 'variants', 'graphics', 'controls', 'dialogs', 'menus',
    'stdctrls', 'math', 'types');
var
  Low: string;
  I  : Integer;
begin
  Low := LowerCase(Trim(AUnitName));
  Result := False;
  for I := System.Low(NS) to System.High(NS) do
    if StartsText(NS[I], Low) then Exit(True);
  for I := System.Low(BARE) to System.High(BARE) do
    if Low = BARE[I] then Exit(True);
end;

function ResolveUsedUnit(const AUnitName: string;
  const AIsProjectMember, AIsInLibrary: TFunc<string, Boolean>): TUnitResolution;
var
  Norm: string;
begin
  Result.Resolvable := False;
  Result.Via        := urvNone;
  Norm := NormUnit(AUnitName);
  if Norm = '' then Exit;
  if Assigned(AIsProjectMember) and AIsProjectMember(Norm) then
    begin Result.Resolvable := True; Result.Via := urvProjectMember; Exit; end;
  if Assigned(AIsInLibrary) and AIsInLibrary(Norm) then
    begin Result.Resolvable := True; Result.Via := urvLibrary; Exit; end;
  if IsStandardUnitAlias(AUnitName) then
    begin Result.Resolvable := True; Result.Via := urvAlias; Exit; end;
  if IsRtlNamespaceUnit(AUnitName) then
    begin Result.Resolvable := True; Result.Via := urvRtlNamespace; Exit; end;
end;
```

NOTE: the local `InSet` in the test shadows nothing; the `Low`/`System.Low` qualification above avoids the `Low()` intrinsic clash with the local `Low` string -- keep the `System.Low`/`System.High` qualifiers.

- [ ] **Step 4: Build + run the test to verify it passes**

Run:
```powershell
& "$env:ProgramFiles(x86)\Embarcadero\Studio\37.0\bin\dcc64.exe" -B tests\projectchecks\ProjectChecksTests.dpr
.\tests\projectchecks\ProjectChecksTests.exe
```
Expected: `projectchecks-tests: N pass / 0 fail / N total`, exit 0. All new `TestUsedUnitResolvable` lines PASS.

- [ ] **Step 5: Verify encoding + commit**

```powershell
# ASCII/CRLF check (0 = clean):
$b=[IO.File]::ReadAllBytes("src\lint\DRagLint.Lint.ProjectChecks.Parse.pas"); ($b | Where-Object {$_ -gt 127}).Count
git add src/lint/DRagLint.Lint.ProjectChecks.Parse.pas tests/projectchecks/ProjectChecksTests.dpr
git commit -m "feat(lint): pure ResolveUsedUnit + alias/RTL-namespace tables (used-unit-not-resolvable)"
```
Expected: non-ASCII count `0`; commit succeeds.

---

### Task 2: Reframe the walker (attach to uses line, drop .dproj requirement)

**Files:**
- Modify: `src/lint/DRagLint.Lint.ProjectChecks.pas` (rename `CheckUnitMembership` -> `CheckUsedUnitResolvable`; rewrite body; update interface decl `:40`)

**Interfaces:**
- Consumes (from Task 1): `ResolveUsedUnit`, `TUnitResolution`, `NormUnit`.
- Produces (consumed by Task 3):
  - `class function CheckUsedUnitResolvable(const AStore: ISymbolStore; const ALibDbPath: string): TArray<TLintFinding>;`
  - Emits one `warning` finding per unresolvable `uses`, with `RuleId='used-unit-not-resolvable'`, `FilePath` = the using file, `StartLine`/`StartCol` = the use's token position.

- [ ] **Step 1: Write the failing integration test** — create `tests/autotest/run_used_unit_not_resolvable.ps1` (models `run_proptree_ancestry_bridge.ps1`).

```powershell
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\drag-lint-uunr"
)
$ErrorActionPreference = 'Continue'
$script:Failed = $false
function Check($n,$ok,$d=''){ $s= if($ok){'PASS'}else{'FAIL'}; $c= if($ok){'Green'}else{'Red'};
  Write-Host ("  [{0}] {1} {2}" -f $s,$n,$d) -ForegroundColor $c; if(-not $ok){$script:Failed=$true} }
function Write-Ascii([string]$Path,[string]$Body){
  $norm = $Body -replace "`r`n","`n" -replace "`n","`r`n"
  [IO.File]::WriteAllText($Path,$norm,[Text.Encoding]::ASCII) }

if(-not(Test-Path $Exe)){Write-Host "FATAL: no exe $Exe" -ForegroundColor Red; exit 2}
$Exe=(Resolve-Path $Exe).Path
if(Test-Path $WorkDir){Remove-Item -Recurse -Force $WorkDir}
New-Item -ItemType Directory $WorkDir | Out-Null
$work=Join-Path $WorkDir 'fixture'; New-Item -ItemType Directory $work | Out-Null

# A sibling project unit that IS indexed (so it resolves as a project member).
Write-Ascii (Join-Path $work 'TakeJob.pas') @'
unit TakeJob;
interface
type TJob = class end;
implementation
end.
'@

# The unit under test: uses a resolvable sibling + an unresolvable Orpheus unit.
Write-Ascii (Join-Path $work 'VarInsp.pas') @'
unit VarInsp;
interface
uses
  TakeJob,
  ovctcmmn,
  System.SysUtils;
type TDlg = class end;
implementation
end.
'@

$db=Join-Path $WorkDir 'uunr.sqlite'
$idx = & $Exe index $work --db $db 2>&1
Check 'index exits 0' ($LASTEXITCODE -eq 0) "exit=$LASTEXITCODE"

# Run the rule (no library DB passed -> ovctcmmn cannot resolve; SysUtils via RTL net).
$out = (& $Exe lint-project --db $db --rule used-unit-not-resolvable 2>&1) -join "`n"
Check 'flags ovctcmmn' ($out -match 'ovctcmmn')  "out=$out"
Check 'does NOT flag TakeJob (project member)'   (-not ($out -match '\bTakeJob\b.*used-unit-not-resolvable')) "out=$out"
Check 'does NOT flag System.SysUtils (RTL net)'  (-not ($out -match 'SysUtils')) "out=$out"
Check 'finding is on VarInsp.pas (uses file)'    ($out -match 'VarInsp\.pas:\d+:\d+') "out=$out"
# The ovctcmmn uses token is on line 5 of VarInsp.pas.
Check 'ovctcmmn finding line is 5'               ($out -match 'VarInsp\.pas:5:') "out=$out"

if($script:Failed){Write-Host 'FAIL' -ForegroundColor Red; exit 1}else{Write-Host 'PASS' -ForegroundColor Green; exit 0}
```

- [ ] **Step 2: Run to verify it fails** (rule id does not exist yet, and the walker still emits on the .dproj)

Run:
```powershell
$env:ErrorActionPreference='Continue'; & .\tests\autotest\run_used_unit_not_resolvable.ps1 -Exe .\src\cli\Win64\Debug\drag-lint.exe
```
Expected: FAIL — `used-unit-not-resolvable` is not yet a rule id, so `lint-project --rule used-unit-not-resolvable` yields no findings; `flags ovctcmmn` FAILS. (Rebuild happens in Task 3/4; for now confirm the harness itself runs and the assertions fail as expected.)

- [ ] **Step 3: Rewrite the walker** in `DRagLint.Lint.ProjectChecks.pas`. Replace `CheckUnitMembership` (interface `:40` + implementation `:141-271`) with `CheckUsedUnitResolvable`. Keep the library-DB open logic and `IsInLibDb`. Build the project-member set from the store; iterate `unit_uses`; skip `in '<path>'`; emit on the use line.

```pascal
// interface (replace the CheckUnitMembership decl)
      /// <summary>Flags every `uses X` whose unit X resolves to no known unit
      /// (project member / platform library / standard alias / RTL namespace).
      /// Findings attach to the `uses` token line on the using file. No .dproj
      /// required. Uses with an explicit `in '<path>'` locator are skipped.</summary>
      /// <param name="AStore">Open project symbol store (the project scope).</param>
      /// <param name="ALibDbPath">Platform library SQLite DB; '' skips the library source.</param>
      /// <returns>One warning per unresolvable used unit.</returns>
      class function CheckUsedUnitResolvable(const AStore: ISymbolStore;
        const ALibDbPath: string): TArray<TLintFinding>;

// implementation (new body; delete the old CheckUnitMembership body)
class function TProjectChecks.CheckUsedUnitResolvable(const AStore: ISymbolStore;
  const ALibDbPath: string): TArray<TLintFinding>;
var
  Findings   : TList<TLintFinding>;
  Members    : TDictionary<string, Boolean>; { normalized stems of indexed units }
  AllFileIds : TArray<Int64>;
  FileId     : Int64;
  UsesArr    : TArray<TUnitUse>;
  U          : TUnitUse;
  F          : TLintFinding;
  LibConn    : TFDConnection;
  LibQ       : TFDQuery;
  SrcPath    : string;
  UnitStem   : string;

  function UnitStemOfPath(const APath: string): string;
  var Slash: Integer; S: string;
  begin
    S := StringReplace(APath, '/', '\', [rfReplaceAll]);
    Slash := S.LastDelimiter('\');
    if Slash >= 0 then S := Copy(S, Slash + 2, MaxInt);
    Result := LowerCase(ChangeFileExt(S, ''));
  end;

  function IsMember(const ANorm: string): Boolean;
  begin Result := Members.ContainsKey(ANorm); end;

  function IsLib(const ANorm: string): Boolean;
  begin
    Result := False;
    if not Assigned(LibQ) then Exit;
    LibQ.Close;
    LibQ.Params[0].Value := ANorm;
    LibQ.Open;
    Result := not LibQ.IsEmpty;
  end;

begin
  Result   := nil;
  Findings := TList<TLintFinding>.Create;
  Members  := TDictionary<string, Boolean>.Create;
  LibConn  := nil;
  LibQ     := nil;
  try
    if (ALibDbPath <> '') and TFile.Exists(ALibDbPath) then
    begin
      LibConn := TFDConnection.Create(nil);
      LibConn.DriverName := 'SQLite';
      LibConn.Params.Values['Database'] := ALibDbPath;
      LibConn.Params.Values['OpenMode'] := 'ReadOnly';
      LibConn.Connected := True;
      LibQ := TFDQuery.Create(nil);
      LibQ.Connection := LibConn;
      LibQ.SQL.Text := 'SELECT 1 FROM symbols WHERE unit_name_norm = :N LIMIT 1';
      LibQ.Prepare;
    end;

    AllFileIds := AStore.GetAllFileIds;
    for FileId in AllFileIds do
    begin
      UnitStem := UnitStemOfPath(AStore.GetFilePath(FileId));
      if UnitStem <> '' then Members.AddOrSetValue(UnitStem, True);
    end;

    for FileId in AllFileIds do
    begin
      SrcPath := AStore.GetFilePath(FileId);
      UsesArr := AStore.GetUnitUsesForFile(FileId);
      for U in UsesArr do
      begin
        if U.InPath <> '' then Continue; { self-locating uses -- not a resolvability question }
        if ResolveUsedUnit(U.UnitName, IsMember, IsLib).Resolvable then Continue;
        F := Default(TLintFinding);
        F.RuleId   := 'used-unit-not-resolvable';
        F.Severity := 'warning';
        F.Message  := Format(
          'Unit ''%s'' is used but resolves to no known unit (not a project ' +
          'member, not in the library, not a known alias). Convert it: comment ' +
          'it out, replace it (e.g. Orpheus->DevExpress, BDE->FireDAC), or add ' +
          'it to the project.', [U.UnitName]);
        F.FilePath  := SrcPath;
        F.StartLine := U.StartLine;
        F.StartCol  := U.StartCol;
        F.EndLine   := U.EndLine;
        F.EndCol    := U.EndCol;
        Findings.Add(F);
      end;
    end;
    Result := Findings.ToArray;
  finally
    LibQ.Free;
    LibConn.Free;
    Members.Free;
    Findings.Free;
  end;
end;
```

Add `DRagLint.Lint.ProjectChecks.Parse` to the implementation uses if `ResolveUsedUnit` is not visible (it is already in the interface uses, `:24`). Ensure `System.Generics.Collections` (TDictionary) and `FireDAC.Comp.Client` (already in impl uses `:47`) are present.

- [ ] **Step 4: (defer run to Task 4)** — this task's code cannot be exercised until the CLI wiring (Task 3) renames the call sites; a whole-exe rebuild happens in Task 4. Confirm the unit COMPILES in isolation:

```powershell
& "$env:ProgramFiles(x86)\Embarcadero\Studio\37.0\bin\dcc64.exe" -B --no-config `
  -U src\lint;src\core;src\storage src\lint\DRagLint.Lint.ProjectChecks.pas 2>&1 | Select-String 'Error'
```
Expected: no `Error` lines (a bare unit compile may warn on unit-path resolution; the authoritative check is the full build in Task 4). If unit-path issues block a standalone compile, SKIP this step and rely on Task 4's full build.

- [ ] **Step 5: Verify encoding + commit**

```powershell
$b=[IO.File]::ReadAllBytes("src\lint\DRagLint.Lint.ProjectChecks.pas"); ($b | Where-Object {$_ -gt 127}).Count
git add src/lint/DRagLint.Lint.ProjectChecks.pas tests/autotest/run_used_unit_not_resolvable.ps1
git commit -m "feat(lint): reframe walker to used-unit-not-resolvable (finding on uses line, no .dproj)"
```
Expected: non-ASCII `0`; commit succeeds.

---

### Task 3: RuleCatalog rename + CLI wiring + robust library-DB pick

**Files:**
- Modify: `src/lint/DRagLint.Lint.RuleCatalog.pas:205`
- Modify: `src/cli/DRagLint.CLI.pas:7250` (lint-all call site) and `:7331-7335` (lint-project call site)

**Interfaces:**
- Consumes (from Task 2): `TProjectChecks.CheckUsedUnitResolvable(AStore, ALibDbPath)`.

- [ ] **Step 1: Rename the catalog entry** — `DRagLint.Lint.RuleCatalog.pas:205`:

```pascal
    B('used-unit-not-resolvable', 'project-wide', 'warning', 'Used unit resolves to no known unit (project/library/alias)');
```

- [ ] **Step 2: Rewire lint-project** — `DRagLint.CLI.pas:7331-7336`. Replace the block with a rule-id rename and a robust library-DB pick (find the `library-*` DB among `--db`s rather than assuming index `[1]`):

```pascal
  { used-unit-not-resolvable -- flags used units resolving to no known unit }
  if (AArgs.Rule = '') or (AArgs.Rule = 'used-unit-not-resolvable') then
  begin
    var LibDbPath2: string := '';
    for var DbI := 0 to High(AArgs.DbPaths) do
      if ContainsText(ExtractFileName(AArgs.DbPaths[DbI]), 'library-') then
      begin LibDbPath2 := AArgs.DbPaths[DbI]; Break; end;
    if (LibDbPath2 = '') and (Length(AArgs.DbPaths) > 1) then LibDbPath2 := AArgs.DbPaths[High(AArgs.DbPaths)];
    Findings := Findings + DRagLint.Lint.ProjectChecks.TProjectChecks.CheckUsedUnitResolvable(Store, LibDbPath2);
  end;
```

- [ ] **Step 3: Rewire lint-all** — `DRagLint.CLI.pas:7249-7250`. Replace with:

```pascal
  { Used-unit resolvability (used-unit-not-resolvable) }
  Findings := Findings + DRagLint.Lint.ProjectChecks.TProjectChecks.CheckUsedUnitResolvable(Store, LibDb);
```
(`LibDb` is the existing library-DB local in lint-all; keep it.)

- [ ] **Step 4: Confirm no other references to the old name remain**

```powershell
Select-String -Path src\**\*.pas -Pattern 'CheckUnitMembership|unit-not-in-project' | Select-Object Path,LineNumber,Line
```
Expected: zero hits in `src/` (docs/tests referencing the old rule id are fine to leave; update the RuleCatalog doc/README opportunistically if trivial). If any `src/*.pas` hit remains, fix it.

- [ ] **Step 5: Commit**

```powershell
git add src/lint/DRagLint.Lint.RuleCatalog.pas src/cli/DRagLint.CLI.pas
git commit -m "feat(lint): wire used-unit-not-resolvable in RuleCatalog + lint-project/lint-all"
```

---

### Task 4: Full build + verification + deploy

**Files:** none (build + run)

- [ ] **Step 1: Build the Win64 exe**

Run via PowerShell `Start-Process -Wait` + log:
```powershell
$log = "$env:TEMP\build_uunr.log"
Start-Process -FilePath "cmd.exe" -ArgumentList '/c','build\build_draglint_win64.bat' -Wait -NoNewWindow -RedirectStandardOutput $log
Select-String -Path $log -Pattern 'BUILD_EXITCODE|\[dcc\] Error' | Select-Object -First 20
```
Expected: `BUILD_EXITCODE=0`, no `[dcc] Error`.

- [ ] **Step 2: Run the new integration test**

```powershell
& .\tests\autotest\run_used_unit_not_resolvable.ps1 -Exe .\src\cli\Win64\Debug\drag-lint.exe
```
Expected: all `[PASS]`, exit 0 (`PASS`).

- [ ] **Step 3: Run the pure test + a regression**

```powershell
.\tests\projectchecks\ProjectChecksTests.exe            # rebuild first if Task 1 exe is stale
& .\tests\autotest\run_reconcile.ps1 -Exe .\src\cli\Win64\Debug\drag-lint.exe
```
Expected: projectchecks-tests `0 fail`; run_reconcile all pass (no regression from the rule rename).

- [ ] **Step 4: Deploy the exe** (the plugin/LSP spawn the deployed copy)

```powershell
Copy-Item .\src\cli\Win64\Debug\drag-lint.exe .\third_party\dll-win64\drag-lint.exe -Force
(Get-FileHash .\src\cli\Win64\Debug\drag-lint.exe).Hash -eq (Get-FileHash .\third_party\dll-win64\drag-lint.exe).Hash
```
Expected: `True` (hashes match -- deploy not blocked by a lock).

- [ ] **Step 5: Commit any build artifacts if tracked** (only if `git status` shows the deployed exe is tracked+changed)

```powershell
git status --porcelain third_party/dll-win64/drag-lint.exe
# if shown as modified AND tracked, commit; otherwise skip:
git add third_party/dll-win64/drag-lint.exe; git commit -m "build: deploy drag-lint.exe with used-unit-not-resolvable rule"
```

---

## Self-Review

**Spec coverage:**
- Section 1 (identity/message/severity/uses-line/no-dproj) -> Task 2 (walker) + Task 3 (catalog/wiring). ✓
- Section 2 (4-source resolution + platform library + M2022 excluded) -> Task 1 (pure resolver: member/library/alias/RTL) + Task 3 (library-DB pick). ✓ M2022 excluded by construction (never passed as a source). ✓
- Section 3 (namespace-blind matching) -> Task 1/2 use `NormUnit` (trailing segment). ✓
- Section 4 (runs in lint-project, uses line, MVP boundaries) -> Task 3 wiring + Task 2 finding location. ✓ No LSP/autofix (out of scope). ✓
- `in '<path>'` skip -> Task 2 `if U.InPath <> '' then Continue`. ✓
- Platform default -> library-DB is selected by the caller among `--db`s (Task 3); platform selection reuses existing plumbing. ✓

**Placeholder scan:** No TBD/TODO; every code step shows full code; every run step shows the command + expected output. ✓

**Type consistency:** `ResolveUsedUnit(AUnitName, AIsProjectMember, AIsInLibrary)` signature identical in Task 1 (def) and Task 2 (call). `TUnitResolution.Resolvable`/`.Via` used consistently. `CheckUsedUnitResolvable(AStore, ALibDbPath)` identical in Task 2 (def) and Task 3 (calls). ✓
