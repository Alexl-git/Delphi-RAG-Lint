# Test Helper CSV (form navigation map) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a drag-lint `forms-csv` CLI command (and a "Generate Test Helper CSV..." IDE menu item) that emits a per-form CSV describing each navigable form and the button/menu path a tester clicks to reach it from the main form.

**Architecture:** A self-contained engine unit `DRagLint.FormsMap.pas` builds a form->form navigation graph from the existing index (form symbols, `component` symbols, `event-binding` refs, and `.pas` construction refs), reads caption literals from `.dfm` line ranges, BFS-walks from the auto-detected root form, and writes the CSV. A thin `DoFormsCsv` in `DRagLint.CLI.pas` is the single tested entry; the IDE menu item shells out to `drag-lint.exe forms-csv` exactly like the other menu items.

**Tech Stack:** Delphi 13 (RAD Studio 37.0), FireDAC over SQLite (`TSQLiteSymbolStore`), tree-sitter-dfm (already used by the indexer), PowerShell smoke tests + fixtures.

---

## Background facts (verified against the codebase)

These are load-bearing; do not re-derive:

- **Form inventory is in the index.** Each `.dfm` root yields a symbol with
  `kind='form'`, `name=<DesignName>` (e.g. `frmMAIN`), `signature=<FormClass>`
  (e.g. `TfrmMAIN`), and `file_id` pointing at the `.dfm` file.
  (`src/parser/DRagLint.Parser.DFM.pas` `WalkObject`, AIsRoot -> `skForm`.)
- **Controls are in the index.** Every nested `.dfm` object yields `kind='component'`
  with `name=<ControlName>`, `signature=<ControlClass>`, parent linkage, and a line
  range (`start_line`..`end_line`).
- **Event handlers are in the index.** Each `On*` property whose value is a method
  yields a ref with `kind='event-binding'`, `name_text=<HandlerMethodName>`, located
  on the DFM line of that property. (`WalkProperty`.)
- **Captions are NOT in the index.** The DFM parser drops `Caption`/`Action`. The
  engine reads the caption literal directly from the control's `.dfm` line range.
- **Class ancestry is NOT in the index.** `kind='class'` rows have empty `signature`.
  The engine reads `= class(TAncestor)` from the `.pas` at the class symbol's
  `start_line` and walks ancestors to classify form vs data module vs frame.
- **Launch signal.** Micronite opens forms (incl. MDI children) via the constructor:
  `TfrmX.Create(...)`, named ctors `TfrmX.CreateForFolder(...)`
  (`CLIENT\uJobList.pas:1678`), or `Application.CreateForm(TfrmX, ...)`. The robust
  signal is the **form class name followed by `.Create`** (a prefix that also matches
  `.CreateForFolder`) or `CreateForm(<FormClass>`. Mere mentions
  (`MDIChildren[I] is TfrmBlueprint4`) lack that signal and are ignored.
- **Store API available (public):** `GetConnection: TFDConnection`,
  `FindContainingSymbol(AFileId: Int64; ALine: Integer): TSymbol`,
  `GetFilePath(AFileId: Int64): string`, `FindSymbolsByQualifiedName`,
  `Migrate`. (`src/storage/DRagLint.Storage.SQLite.pas`.)
- **CSV escape pattern** to copy: quote when the field contains `,` `"` or LF,
  doubling embedded quotes (`src/cli/DRagLint.CLI.pas:3850`).
- **Root detection:** parse the sibling `.dpr`; the root is the first
  `Application.CreateForm(T<Class>, ...)` whose class is a *form* node (this skips
  `Application.CreateForm(TdmStyles, dmStyles)` -> lands on `TfrmMAIN`).
- **Build (Win32 Debug):**
  `cmd.exe /c "call \"C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\rsvars.bat\" && msbuild /t:Build /p:Config=Debug /p:Platform=Win32 src\cli\drag-lint.dproj"`
  Output exe: `src\cli\Win32\Debug\drag-lint.exe`.

## File structure

- **Create** `src/forms/DRagLint.FormsMap.pas` - the engine (records, graph build,
  caption read, BFS, CSV emit). One cohesive responsibility: the form-navigation map.
- **Modify** `src/cli/DRagLint.CLI.pas` - add `RootForm` arg, `--root` parse, the
  `forms-csv` dispatch + `DoFormsCsv`, and a help line.
- **Modify** `src/cli/drag-lint.dpr` AND `src/cli/drag-lint.dproj` - register the new
  unit in BOTH (hard project rule: a unit missing from the `.dproj` still compiles via
  search path, so the omission is silent).
- **Modify** `src/delphi-plugin/DragLint.Plugin.Editor.pas` - add the menu item +
  handler (Save-All, run exe, open CSV). The BPL does NOT need the engine unit (it only
  shells out), so `dclDragLintWizard.dpk`/`.dproj` are unchanged.
- **Create** `tests/fixtures/formsmap/` - a mini indexed project exercising each case.
- **Create** `tests/autotest/run_formsmap.ps1` - fixture-driven CLI smoke checks
  (matches the repo's existing `run_smoke.ps1` test style; this repo has no DUnit).

## Conventions for every code step

- Files are **strict 7-bit ASCII, CRLF**. No em-dashes, no Unicode, no `//` trailing
  comments inside multi-line argument lists (YADF hazard).
- DocInsight `///` summaries on every public type/function in the new unit.
- Commit after each task with the message shown.

---

## Task 1: Scaffold the command + engine seam (header-only CSV)

Goal: `drag-lint forms-csv --db <x> --out <f.csv>` runs end to end and writes a
header-only CSV. Proves the CLI seam, build registration, and file output before any
graph logic.

**Files:**
- Create: `src/forms/DRagLint.FormsMap.pas`
- Modify: `src/cli/DRagLint.CLI.pas` (TArgs, PrintHelp, ParseArgs, dispatch, DoFormsCsv)
- Modify: `src/cli/drag-lint.dpr`, `src/cli/drag-lint.dproj`
- Create: `tests/fixtures/formsmap/` (built in Task 2; Task 1 uses any existing db)
- Create: `tests/autotest/run_formsmap.ps1`

- [ ] **Step 1: Create the engine unit with the public entry + record types**

Create `src/forms/DRagLint.FormsMap.pas`:

```pascal
unit DRagLint.FormsMap;

/// <summary>Builds a per-form navigation-map CSV for a project: how a tester
/// reaches each form from the application's root form, plus which forms launch
/// it. Reuses the drag-lint index (form/component symbols + event-binding refs +
/// construction refs) and reads caption literals from .dfm line ranges.</summary>
/// <remarks>Engine only. The CLI command forms-csv and the IDE menu item are thin
/// wrappers. Not thread-safe; single-shot per call.</remarks>

interface

uses
  System.SysUtils,
  System.Classes,
  System.Generics.Collections,
  DRagLint.Storage.SQLite;

type
  /// <summary>One navigable form (a .dfm root that descends from a form base).</summary>
  TFormNode = record
    FormClass:    string;   // e.g. TfrmMAIN (the form symbol's signature)
    FormName:     string;   // e.g. frmMAIN  (the design-time Name)
    UnitName:     string;   // e.g. uMain    (paired .pas basename, no extension)
    PasPath:      string;   // full path to the paired .pas
    DfmPath:      string;   // full path to the .dfm
    DfmFileId:    Int64;    // files.id of the .dfm in the index
    PasLineCount: Integer;  // line count of the .pas
  end;

  /// <summary>A launch edge: form FromClass opens form ToClass; Caption is the
  /// resolved control caption to press, or '(via Routine)' when no captioned
  /// control binds the launching routine.</summary>
  TFormEdge = record
    FromClass: string;
    ToClass:   string;
    Caption:   string;
  end;

  /// <summary>Generates the navigation-map CSV text.</summary>
  /// <param name="ADbPath">Path to the project's drag-lint index (sqlite).</param>
  /// <param name="AProjectFile">Path to the .dproj (used to find the .dpr for root
  /// detection). May be '' if ARootForm is supplied.</param>
  /// <param name="ARootForm">Root form class (e.g. TfrmMAIN). '' = auto-detect from
  /// the .dpr.</param>
  /// <returns>The full CSV text (RFC 4180 dialect, CRLF rows).</returns>
  /// <exception cref="Exception">If the index cannot be opened or no root can be
  /// resolved.</exception>
  function GenerateFormsCsv(const ADbPath, AProjectFile, ARootForm: string): string;

implementation

function GenerateFormsCsv(const ADbPath, AProjectFile, ARootForm: string): string;
var
  Sb: TStringBuilder;
begin
  Sb := TStringBuilder.Create;
  try
    Sb.Append('#,Unit,FormName,PAS lines,Navigation,Called From,Notes').Append(#13#10);
    Result := Sb.ToString;
  finally
    Sb.Free;
  end;
end;

end.
```

- [ ] **Step 2: Register the unit in the .dpr**

In `src/cli/drag-lint.dpr`, add after the `DRagLint.Project.Resolver` line (25):

```pascal
  DRagLint.FormsMap in '..\forms\DRagLint.FormsMap.pas',
```

- [ ] **Step 3: Register the unit in the .dproj**

In `src/cli/drag-lint.dproj`, find the `<DCCReference Include="..\project\DRagLint.Project.Resolver.pas"/>` line and add directly after it:

```xml
    <DCCReference Include="..\forms\DRagLint.FormsMap.pas"/>
```

- [ ] **Step 4: Add the `RootForm` arg field + `--root` parse + help line**

In `src/cli/DRagLint.CLI.pas`, in the `TArgs` record (after `WorkspaceConfig` at line 136) add:

```pascal
    RootForm:           string;  // forms-csv: --root <TfrmMAIN> (auto-detect if '')
```

In `PrintHelp`, after the `workspace add` line (189) add:

```pascal
  Writeln('  drag-lint forms-csv --project <X.dproj> --db <file.sqlite> [--out <f.csv>] [--root <TfrmMAIN>]   (test-helper navigation CSV, one row per form)');
```

In the argument-parsing loop (the long `else if` chain near lines 320-547), add a clause (place it next to the other single-value flags, e.g. after the `--config` clause around 547):

```pascal
    else if (A = '--root') and (i < ParamCount) then
    begin
      Inc(i);
      Result.RootForm := ParamStr(i);
    end
```

- [ ] **Step 5: Add the dispatch + DoFormsCsv**

In `src/cli/DRagLint.CLI.pas`, in the command dispatch chain (after the `uses-fix` branch at line 6279-6280) add:

```pascal
    else if Args.Command = 'forms-csv' then
      Result := DoFormsCsv(Args)
```

Add `DRagLint.FormsMap` to the CLI unit's `uses` clause (implementation `uses`).
Add the function (place it near `DoUsesReport`, before the dispatch `Run`):

```pascal
function DoFormsCsv(const AArgs: TArgs): Integer;
var
  DbPath, Csv: string;
begin
  if Length(AArgs.DbPaths) > 0 then
    DbPath := AArgs.DbPaths[0]
  else
    DbPath := AArgs.DbPath;
  if DbPath = '' then
  begin
    Writeln(ErrOutput, 'forms-csv: need --db <index.sqlite>');
    Exit(2);
  end;
  if not TFile.Exists(DbPath) then
  begin
    Writeln(ErrOutput, 'forms-csv: db not found: ', DbPath);
    Exit(2);
  end;
  try
    Csv := DRagLint.FormsMap.GenerateFormsCsv(DbPath, AArgs.ProjectPath, AArgs.RootForm);
  except
    on E: Exception do
    begin
      Writeln(ErrOutput, 'forms-csv: ', E.Message);
      Exit(1);
    end;
  end;
  if AArgs.Output <> '' then
  begin
    TFile.WriteAllText(AArgs.Output, Csv, TEncoding.ANSI);
    Writeln('forms-csv: wrote ', AArgs.Output);
  end
  else
    Write(Csv);
  Result := 0;
end;
```

Note: `DoFormsCsv` must be declared before `Run` uses it - add a forward declaration
in the `interface` or place the implementation above `Run`. Match the pattern of the
neighbouring `Do*` functions (they are defined above `Run` in the implementation
section; place `DoFormsCsv` there too, no forward needed).

- [ ] **Step 6: Build the exe**

Run:
```
cmd.exe /c "call \"C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\rsvars.bat\" && msbuild /t:Build /p:Config=Debug /p:Platform=Win32 src\cli\drag-lint.dproj"
```
Expected: `Build succeeded.` and `src\cli\Win32\Debug\drag-lint.exe` updated.

- [ ] **Step 7: Create the smoke test (header check)**

Create `tests/autotest/run_formsmap.ps1`:

```powershell
# drag-lint forms-csv smoke test. Builds a tiny fixture project, indexes it,
# runs forms-csv, and asserts the navigation CSV content.
#
# Usage: pwsh -File tests/autotest/run_formsmap.ps1 [-Exe <path>]
[CmdletBinding()]
param(
    [string] $Exe = "$PSScriptRoot\..\..\src\cli\Win32\Debug\drag-lint.exe",
    [string] $FixtureDir = "$PSScriptRoot\..\fixtures\formsmap",
    [string] $WorkDir = "$env:TEMP\drag-lint-formsmap"
)
$ErrorActionPreference = 'Stop'
$script:Failed = $false
function Check([string]$Name, [bool]$Ok, [string]$Detail='') {
    $status = if ($Ok) {'PASS'} else {'FAIL'}
    $color  = if ($Ok) {'Green'} else {'Red'}
    Write-Host ("  [{0}] {1} {2}" -f $status, $Name, $Detail) -ForegroundColor $color
    if (-not $Ok) { $script:Failed = $true }
}
if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
if (Test-Path $WorkDir) { Remove-Item -Recurse -Force $WorkDir }
New-Item -ItemType Directory $WorkDir | Out-Null
$db  = "$WorkDir\fixture.sqlite"
$out = "$WorkDir\forms.csv"
& $Exe index $FixtureDir --db $db 2>&1 | Out-Null
Check 'index fixture exits 0' ($LASTEXITCODE -eq 0)
& $Exe forms-csv --project "$FixtureDir\Demo.dproj" --db $db --out $out 2>&1 | Out-Null
Check 'forms-csv exits 0' ($LASTEXITCODE -eq 0)
Check 'csv exists' (Test-Path $out)
$csv = Get-Content $out -Raw
Check 'header present' ($csv -match '#,Unit,FormName,PAS lines,Navigation,Called From,Notes')
Write-Host ''
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
```

- [ ] **Step 8: Run smoke; expect the index/forms-csv steps to fail only on the missing fixture**

Run: `pwsh -File tests/autotest/run_formsmap.ps1`
Expected at this point: the script runs; `index fixture` FAILS (fixture dir not created
yet). That is the expected red - the fixture is built in Task 2. The header assertion
logic is in place. (Do not "fix" by faking the fixture.)

- [ ] **Step 9: Commit**

```bash
git add src/forms/DRagLint.FormsMap.pas src/cli/DRagLint.CLI.pas src/cli/drag-lint.dpr src/cli/drag-lint.dproj tests/autotest/run_formsmap.ps1
git commit -m "feat(forms-csv): scaffold command + engine seam (header-only CSV)

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 2: Fixture project + form inventory with data-module/frame exclusion

Goal: the CSV lists one row per *form/dialog*, with Unit, FormName, and PAS line count;
data modules and frames are excluded. Establishes inventory + ancestry classification.

**Fixture design** (`tests/fixtures/formsmap/`): a self-contained mini app.

- [ ] **Step 1: Write the fixture .dpr**

Create `tests/fixtures/formsmap/Demo.dpr`:

```pascal
program Demo;
uses
  Vcl.Forms,
  uDemoMain in 'uDemoMain.pas' {frmMain},
  uDemoList in 'uDemoList.pas' {frmList},
  uDemoEdit in 'uDemoEdit.pas' {frmEdit},
  uDemoData in 'uDemoData.pas' {dmDemo: TDataModule};
begin
  Application.Initialize;
  Application.CreateForm(TdmDemo, dmDemo);
  Application.CreateForm(TfrmMain, frmMain);
  Application.Run;
end.
```

- [ ] **Step 2: Write the fixture forms + data module (.pas/.dfm)**

Create `tests/fixtures/formsmap/uDemoMain.pas`:

```pascal
unit uDemoMain;
interface
uses Vcl.Forms, Vcl.StdCtrls, uDemoList;
type
  TfrmMain = class(TForm)
    btnLists: TButton;
    procedure btnListsClick(Sender: TObject);
  end;
var frmMain: TfrmMain;
implementation
{$R *.dfm}
procedure TfrmMain.btnListsClick(Sender: TObject);
begin
  TfrmList.Create(Self).ShowModal;
end;
end.
```

Create `tests/fixtures/formsmap/uDemoMain.dfm`:

```
object frmMain: TfrmMain
  Left = 0
  Top = 0
  Caption = 'Main'
  ClientHeight = 200
  ClientWidth = 300
  object btnLists: TButton
    Left = 8
    Top = 8
    Width = 75
    Height = 25
    Caption = 'Lists'
    OnClick = btnListsClick
  end
end
```

Create `tests/fixtures/formsmap/uDemoList.pas`:

```pascal
unit uDemoList;
interface
uses Vcl.Forms, Vcl.StdCtrls, uDemoEdit;
type
  TfrmList = class(TForm)
    btnEdit: TButton;
    procedure btnEditClick(Sender: TObject);
  end;
implementation
{$R *.dfm}
procedure TfrmList.btnEditClick(Sender: TObject);
begin
  TfrmEdit.Create(Self).ShowModal;
end;
end.
```

Create `tests/fixtures/formsmap/uDemoList.dfm`:

```
object frmList: TfrmList
  Left = 0
  Top = 0
  Caption = 'Lists'
  ClientHeight = 200
  ClientWidth = 300
  object btnEdit: TButton
    Left = 8
    Top = 8
    Width = 75
    Height = 25
    Caption = 'Edit Item'
    OnClick = btnEditClick
  end
end
```

Create `tests/fixtures/formsmap/uDemoEdit.pas`:

```pascal
unit uDemoEdit;
interface
uses Vcl.Forms;
type
  TfrmEdit = class(TForm)
  end;
implementation
{$R *.dfm}
end.
```

Create `tests/fixtures/formsmap/uDemoEdit.dfm`:

```
object frmEdit: TfrmEdit
  Left = 0
  Top = 0
  Caption = 'Edit'
  ClientHeight = 150
  ClientWidth = 250
end
```

Create `tests/fixtures/formsmap/uDemoData.pas`:

```pascal
unit uDemoData;
interface
uses System.Classes;
type
  TdmDemo = class(TDataModule)
  end;
var dmDemo: TdmDemo;
implementation
{$R *.dfm}
end.
```

Create `tests/fixtures/formsmap/uDemoData.dfm`:

```
object dmDemo: TdmDemo
  OldCreateOrder = False
end
```

- [ ] **Step 2b: Write a minimal Demo.dproj so --project resolves**

Create `tests/fixtures/formsmap/Demo.dproj` (only the bits the resolver/root reads):

```xml
<Project xmlns="http://schemas.microsoft.com/developer/msbuild/2003">
  <PropertyGroup>
    <MainSource>Demo.dpr</MainSource>
  </PropertyGroup>
  <ItemGroup>
    <DCCReference Include="uDemoMain.pas"><Form>frmMain</Form><FormType>dfm</FormType></DCCReference>
    <DCCReference Include="uDemoList.pas"><Form>frmList</Form><FormType>dfm</FormType></DCCReference>
    <DCCReference Include="uDemoEdit.pas"><Form>frmEdit</Form><FormType>dfm</FormType></DCCReference>
    <DCCReference Include="uDemoData.pas"><Form>dmDemo</Form><FormType>dfm</FormType></DCCReference>
  </ItemGroup>
</Project>
```

- [ ] **Step 3: Add the inventory + ancestry assertions to the smoke test**

In `tests/autotest/run_formsmap.ps1`, before the final summary, add:

```powershell
$rows = ($csv -split "`r`n") | Where-Object { $_ -ne '' }
Check 'frmMain row present'  ($csv -match 'uDemoMain,frmMain,')
Check 'frmList row present'  ($csv -match 'uDemoList,frmList,')
Check 'frmEdit row present'  ($csv -match 'uDemoEdit,frmEdit,')
Check 'data module excluded' (-not ($csv -match 'dmDemo'))
Check 'pas line count for frmEdit' ($csv -match 'uDemoEdit,frmEdit,9,')  # uDemoEdit.pas has 9 lines
Check 'row count is 3 forms + header' ($rows.Count -eq 4)
```

(If the exact line count of `uDemoEdit.pas` differs after you create it, set the
assertion to the real `(Get-Content uDemoEdit.pas).Count`.)

- [ ] **Step 4: Run smoke to verify inventory assertions FAIL**

Run: `pwsh -File tests/autotest/run_formsmap.ps1`
Expected: index now passes; `frmMain row present` etc. FAIL (engine still emits header
only).

- [ ] **Step 5: Implement inventory + classification in the engine**

In `DRagLint.FormsMap.pas`, add to the `uses`: `System.IOUtils,
System.Generics.Defaults, DRagLint.Core.Model, FireDAC.Comp.Client`
(`DRagLint.Core.Model` supplies `TSymbol`/`TReference` returned by the store;
`FireDAC.Comp.Client` supplies `TFDQuery`/`TFDConnection`).
Add these private helpers and rewrite `GenerateFormsCsv` to build + emit the inventory
(navigation columns are filled in later tasks; for now emit blank Navigation/CalledFrom):

```pascal
/// <summary>Reads the immediate ancestor class name from a .pas class
/// declaration at the given 1-based line (handles "T = class(TAncestor)").</summary>
function ReadAncestor(const APasPath: string; AStartLine: Integer): string;
var
  Lines: TArray<string>;
  Buf: string;
  I, P, Q: Integer;
begin
  Result := '';
  if not TFile.Exists(APasPath) then Exit;
  Lines := TFile.ReadAllLines(APasPath, TEncoding.ANSI);
  Buf := '';
  for I := AStartLine - 1 to Length(Lines) - 1 do
  begin
    Buf := Buf + ' ' + Lines[I];
    if Pos(')', Buf) > 0 then Break;
    if (Pos('class', LowerCase(Buf)) > 0) and (Pos('(', Buf) = 0) and
       (Pos(';', Buf) > 0) then Exit; // class with no ancestor list
    if I > AStartLine + 3 then Break;  // guard
  end;
  P := Pos('(', Buf);
  if P = 0 then Exit;
  Q := P + 1;
  while (Q <= Length(Buf)) and CharInSet(Buf[Q], [' ', #9]) do Inc(Q);
  P := Q;
  while (P <= Length(Buf)) and
        (CharInSet(Buf[P], ['A'..'Z','a'..'z','0'..'9','_'])) do Inc(P);
  Result := Copy(Buf, Q, P - Q);
end;

/// <summary>Classifies a form-root class as a navigable form (True) or a data
/// module / frame (False) by walking project-class ancestry; VCL bases terminate
/// the walk.</summary>
function IsNavigableForm(AStore: TSQLiteSymbolStore; const AFormClass: string): Boolean;
var
  Q: TFDQuery;
  Cls, Anc: string;
  Path: string;
  StartLine: Integer;
  Hops: Integer;
begin
  Cls := AFormClass;
  Hops := 0;
  while (Cls <> '') and (Hops < 16) do
  begin
    Inc(Hops);
    // Known VCL bases short-circuit the walk.
    if SameText(Cls, 'TDataModule') or SameText(Cls, 'TFrame') or
       SameText(Cls, 'TCustomFrame') then Exit(False);
    if SameText(Cls, 'TForm') or SameText(Cls, 'TCustomForm') or
       SameText(Cls, 'TfrmMicroniteBase') then Exit(True);  // project base form, if any
    // Look up the project class to get its .pas + decl line, then its ancestor.
    Q := TFDQuery.Create(nil);
    try
      Q.Connection := AStore.GetConnection;
      Q.SQL.Text :=
        'SELECT f.path AS p, s.start_line AS sl FROM symbols s ' +
        'JOIN files f ON f.id = s.file_id ' +
        'WHERE s.kind = ''class'' AND s.name = :n LIMIT 1';
      Q.ParamByName('n').AsString := Cls;
      Q.Open;
      if Q.IsEmpty then Break;  // not a project class; unknown ancestor
      Path := Q.FieldByName('p').AsString;
      StartLine := Q.FieldByName('sl').AsInteger;
    finally
      Q.Free;
    end;
    Anc := ReadAncestor(Path, StartLine);
    if Anc = '' then Break;
    Cls := Anc;
  end;
  // Unknown / unresolved ancestry: default to form (visual roots dominate).
  Result := True;
end;

/// <summary>Loads every navigable form from the index (kind='form'), pairing the
/// .dfm with its same-basename .pas and counting the .pas lines.</summary>
function LoadInventory(AStore: TSQLiteSymbolStore): TList<TFormNode>;
var
  Q: TFDQuery;
  Node: TFormNode;
begin
  Result := TList<TFormNode>.Create;
  Q := TFDQuery.Create(nil);
  try
    Q.Connection := AStore.GetConnection;
    Q.SQL.Text :=
      'SELECT s.name AS nm, s.signature AS cls, s.file_id AS fid, f.path AS p ' +
      'FROM symbols s JOIN files f ON f.id = s.file_id ' +
      'WHERE s.kind = ''form'' ORDER BY s.name';
    Q.Open;
    while not Q.Eof do
    begin
      Node := Default(TFormNode);
      Node.FormName  := Q.FieldByName('nm').AsString;
      Node.FormClass := Q.FieldByName('cls').AsString;
      Node.DfmFileId := Q.FieldByName('fid').AsLargeInt;
      Node.DfmPath   := Q.FieldByName('p').AsString;
      Node.PasPath   := TPath.ChangeExtension(Node.DfmPath, '.pas');
      Node.UnitName  := TPath.GetFileNameWithoutExtension(Node.PasPath);
      if TFile.Exists(Node.PasPath) then
        Node.PasLineCount := Length(TFile.ReadAllLines(Node.PasPath, TEncoding.ANSI))
      else
        Node.PasLineCount := 0;
      if IsNavigableForm(AStore, Node.FormClass) then
        Result.Add(Node);
      Q.Next;
    end;
  finally
    Q.Free;
  end;
end;

/// <summary>RFC 4180 field escaping (quote when needed, double embedded quotes).</summary>
function CsvField(const S: string): string;
begin
  if (Pos(',', S) > 0) or (Pos('"', S) > 0) or (Pos(#10, S) > 0) then
    Result := '"' + StringReplace(S, '"', '""', [rfReplaceAll]) + '"'
  else
    Result := S;
end;
```

Rewrite `GenerateFormsCsv` body:

```pascal
function GenerateFormsCsv(const ADbPath, AProjectFile, ARootForm: string): string;
var
  Store: TSQLiteSymbolStore;
  Nodes: TList<TFormNode>;
  Sb: TStringBuilder;
  N: TFormNode;
  Idx: Integer;
begin
  Store := TSQLiteSymbolStore.Create(ADbPath);
  Sb := TStringBuilder.Create;
  try
    Store.Migrate;
    Nodes := LoadInventory(Store);
    try
      Nodes.Sort(TComparer<TFormNode>.Construct(
        function(const L, R: TFormNode): Integer
        begin
          Result := CompareText(L.FormName, R.FormName);
        end));
      Sb.Append('#,Unit,FormName,PAS lines,Navigation,Called From,Notes').Append(#13#10);
      Idx := 0;
      for N in Nodes do
      begin
        Inc(Idx);
        Sb.Append(Idx).Append(',')
          .Append(CsvField(N.UnitName)).Append(',')
          .Append(CsvField(N.FormName)).Append(',')
          .Append(N.PasLineCount).Append(',')
          .Append(',')   // Navigation (Task 3-5)
          .Append(',')   // Called From (Task 5)
          .Append('')    // Notes
          .Append(#13#10);
      end;
      Result := Sb.ToString;
    finally
      Nodes.Free;
    end;
  finally
    Sb.Free;
    Store.Free;
  end;
end;
```

Add `System.Generics.Defaults` to the `uses`.

- [ ] **Step 6: Rebuild + run smoke**

Run the build command from Task 1 Step 6, then `pwsh -File tests/autotest/run_formsmap.ps1`.
Expected: inventory assertions PASS; navigation assertions (not added yet) absent.

- [ ] **Step 7: Commit**

```bash
git add src/forms/DRagLint.FormsMap.pas tests/fixtures/formsmap tests/autotest/run_formsmap.ps1
git commit -m "feat(forms-csv): form inventory + data-module/frame exclusion + fixtures

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 3: Launch-edge detection + direct ShowModal navigation

Goal: build the form->form graph from construction refs and render the BFS navigation
path for the direct-`ShowModal` fixture chain `frmMain -> 'Lists' -> 'Edit Item'`.

**Files:** Modify `src/forms/DRagLint.FormsMap.pas`, `tests/autotest/run_formsmap.ps1`.

- [ ] **Step 1: Add the navigation assertions to the smoke test**

In `run_formsmap.ps1` add:

```powershell
Check 'frmMain is root (blank nav)'   ($csv -match "uDemoMain,frmMain,\d+,,")
Check 'frmList nav via Lists'         ($csv -match "uDemoList,frmList,\d+,frmMain -> 'Lists',")
Check 'frmEdit nav via Lists>Edit'    ($csv -match "uDemoEdit,frmEdit,\d+,frmMain -> 'Lists' -> 'Edit Item',")
```

- [ ] **Step 2: Run smoke to verify nav assertions FAIL**

Run: `pwsh -File tests/autotest/run_formsmap.ps1`
Expected: the three nav assertions FAIL (Navigation column still blank).

- [ ] **Step 3: Implement edge detection + caption resolution + BFS**

In `DRagLint.FormsMap.pas` add the helpers below. (Caption resolution here covers the
direct case: a launching routine that is itself a control's `OnClick`. Action
indirection and within-form recursion come in Task 5.)

```pascal
/// <summary>True if the source line constructs the given form class:
/// "<FormClass>.Create" (also matches named ctors like .CreateForFolder) or
/// "CreateForm(<FormClass>".</summary>
function IsLaunchLine(const ALine, AFormClass: string): Boolean;
var
  Lc, Fc: string;
begin
  Lc := ALine;
  Fc := AFormClass;
  Result :=
    (Pos(Fc + '.Create', Lc) > 0) or
    (Pos('CreateForm(' + Fc, StringReplace(Lc, ' ', '', [rfReplaceAll])) > 0);
end;

/// <summary>Reads the Caption literal of a control from its .dfm line range
/// (the first "Caption = '...'" before any nested object). Strips '&'
/// accelerators and joins simple multi-line string continuations.</summary>
function ReadCaption(const ADfmPath: string; AStartLine, AEndLine: Integer): string;
var
  Lines: TArray<string>;
  I, P, Q: Integer;
  T: string;
begin
  Result := '';
  if not TFile.Exists(ADfmPath) then Exit;
  Lines := TFile.ReadAllLines(ADfmPath, TEncoding.ANSI);
  for I := AStartLine to AEndLine - 1 do  // skip the object header line itself
  begin
    if (I < 0) or (I >= Length(Lines)) then Continue;
    T := Trim(Lines[I]);
    if (LowerCase(Copy(T, 1, 7)) = 'object ') or
       (LowerCase(Copy(T, 1, 5)) = 'item') then Exit; // entered a child; no own caption
    if LowerCase(Copy(T, 1, 9)) = 'caption =' then
    begin
      P := Pos('''', T);
      Q := LastDelimiter('''', T);
      if (P > 0) and (Q > P) then
      begin
        Result := Copy(T, P + 1, Q - P - 1);
        Result := StringReplace(Result, '''''', '''', [rfReplaceAll]);
        Result := StringReplace(Result, '&', '', [rfReplaceAll]);
      end;
      Exit;
    end;
  end;
end;

/// <summary>Finds the control caption bound to event handler ARoutine in form
/// AFormClass; returns '' if no captioned control directly binds it (Task 5 adds
/// within-form recursion and Action indirection).</summary>
function CaptionForHandler(AStore: TSQLiteSymbolStore; const ANode: TFormNode;
  const ARoutine: string): string;
var
  Q: TFDQuery;
  Ctrl: TReference;  // not used directly; we re-query
  Line: Integer;
  Sym: TSymbol;
begin
  Result := '';
  Q := TFDQuery.Create(nil);
  try
    Q.Connection := AStore.GetConnection;
    Q.SQL.Text :=
      'SELECT start_line FROM refs ' +
      'WHERE kind = ''event-binding'' AND name_text = :h AND file_id = :fid ' +
      'ORDER BY start_line LIMIT 1';
    Q.ParamByName('h').AsString := ARoutine;
    Q.ParamByName('fid').AsLargeInt := ANode.DfmFileId;
    Q.Open;
    if Q.IsEmpty then Exit;
    Line := Q.FieldByName('start_line').AsInteger;
  finally
    Q.Free;
  end;
  Sym := AStore.FindContainingSymbol(ANode.DfmFileId, Line);
  if Sym.Name = '' then Exit;
  Result := ReadCaption(ANode.DfmPath, Sym.StartLine, Sym.EndLine);
end;
```

Add the graph builder and BFS. Insert into `GenerateFormsCsv` between inventory load
and CSV emit. First add a class-to-node lookup and an adjacency structure:

```pascal
/// <summary>Builds launch edges X -> Y across all forms. For each target form Y,
/// finds construction sites in any .pas, resolves the enclosing routine and its
/// owning form X, and resolves the caption of the control that triggers it.</summary>
function BuildEdges(AStore: TSQLiteSymbolStore; ANodes: TList<TFormNode>;
  AClassToNode: TDictionary<string, TFormNode>): TList<TFormEdge>;
var
  Y: TFormNode;
  Q: TFDQuery;
  PasFileId: Int64;
  LaunchLine: Integer;
  LineText: string;
  Routine, OwnerClass: string;
  RSym, ClsSym: TSymbol;
  XNode: TFormNode;
  Edge: TFormEdge;
  PasLines: TDictionary<Int64, TArray<string>>;
  function FileLines(AFileId: Int64; const APath: string): TArray<string>;
  begin
    if not PasLines.TryGetValue(AFileId, Result) then
    begin
      if TFile.Exists(APath) then
        Result := TFile.ReadAllLines(APath, TEncoding.ANSI)
      else
        Result := [];
      PasLines.Add(AFileId, Result);
    end;
  end;
begin
  Result := TList<TFormEdge>.Create;
  PasLines := TDictionary<Int64, TArray<string>>.Create;
  Q := TFDQuery.Create(nil);
  try
    Q.Connection := AStore.GetConnection;
    for Y in ANodes do
    begin
      Q.Close;
      Q.SQL.Text :=
        'SELECT r.file_id AS fid, r.start_line AS sl, f.path AS p ' +
        'FROM refs r JOIN files f ON f.id = r.file_id ' +
        'WHERE r.name_text = :cls AND f.language LIKE ''delphi%''';
      Q.ParamByName('cls').AsString := Y.FormClass;
      Q.Open;
      while not Q.Eof do
      begin
        PasFileId  := Q.FieldByName('fid').AsLargeInt;
        LaunchLine := Q.FieldByName('sl').AsInteger;
        var Arr := FileLines(PasFileId, Q.FieldByName('p').AsString);
        if (LaunchLine >= 1) and (LaunchLine <= Length(Arr)) then
          LineText := Arr[LaunchLine - 1]
        else
          LineText := '';
        if IsLaunchLine(LineText, Y.FormClass) then
        begin
          RSym := AStore.FindContainingSymbol(PasFileId, LaunchLine);
          if (RSym.Name <> '') and (RSym.ParentId > 0) then
          begin
            ClsSym := AStore.GetSymbolById(RSym.ParentId);
            OwnerClass := ClsSym.Name;
            Routine := RSym.Name;
            if AClassToNode.TryGetValue(OwnerClass, XNode) and
               (OwnerClass <> Y.FormClass) then
            begin
              Edge := Default(TFormEdge);
              Edge.FromClass := OwnerClass;
              Edge.ToClass   := Y.FormClass;
              Edge.Caption   := CaptionForHandler(AStore, XNode, Routine);
              if Edge.Caption = '' then
                Edge.Caption := '(via ' + Routine + ')';
              Result.Add(Edge);
            end;
          end;
        end;
        Q.Next;
      end;
    end;
  finally
    Q.Free;
    PasLines.Free;
  end;
end;
```

This uses `AStore.GetSymbolById`. Add that public method to the store (Task 3 Step 4).

Add the BFS path renderer:

```pascal
/// <summary>BFS shortest navigation path from the root form to AToClass.
/// Returns "RootName -> 'Cap1' -> 'Cap2'" or '' if unreachable.</summary>
function NavPath(AEdges: TList<TFormEdge>; AClassToNode: TDictionary<string, TFormNode>;
  const ARootClass, AToClass: string): string;
type
  TStep = record Cls: string; Path: string; end;
var
  Queue: TQueue<TStep>;
  Visited: TDictionary<string, Boolean>;
  Cur, Nxt: TStep;
  E: TFormEdge;
  RootNode: TFormNode;
begin
  Result := '';
  if SameText(ARootClass, AToClass) then Exit;  // root itself: blank nav
  Queue := TQueue<TStep>.Create;
  Visited := TDictionary<string, Boolean>.Create;
  try
    if AClassToNode.TryGetValue(ARootClass, RootNode) then
      Cur.Path := RootNode.FormName
    else
      Cur.Path := ARootClass;
    Cur.Cls := ARootClass;
    Queue.Enqueue(Cur);
    Visited.Add(ARootClass, True);
    while Queue.Count > 0 do
    begin
      Cur := Queue.Dequeue;
      for E in AEdges do
        if SameText(E.FromClass, Cur.Cls) and not Visited.ContainsKey(E.ToClass) then
        begin
          Nxt.Cls := E.ToClass;
          if Copy(E.Caption, 1, 1) = '(' then
            Nxt.Path := Cur.Path + ' -> ' + E.Caption
          else
            Nxt.Path := Cur.Path + ' -> ''' + E.Caption + '''';
          if SameText(E.ToClass, AToClass) then Exit(Nxt.Path);
          Visited.Add(E.ToClass, True);
          Queue.Enqueue(Nxt);
        end;
    end;
  finally
    Queue.Free;
    Visited.Free;
  end;
end;
```

Add root detection:

```pascal
/// <summary>Determines the root form class: --root if given, else the first
/// Application.CreateForm(T..., ...) in the sibling .dpr whose class is a form
/// node.</summary>
function DetectRoot(const AProjectFile, ARootForm: string;
  AClassToNode: TDictionary<string, TFormNode>): string;
var
  DprPath: string;
  Lines: TArray<string>;
  L, Frag: string;
  P, Q: Integer;
  Cls: string;
begin
  if ARootForm <> '' then Exit(ARootForm);
  Result := '';
  if AProjectFile = '' then Exit;
  DprPath := TPath.ChangeExtension(AProjectFile, '.dpr');
  if not TFile.Exists(DprPath) then Exit;
  Lines := TFile.ReadAllLines(DprPath, TEncoding.ANSI);
  for L in Lines do
  begin
    P := Pos('Application.CreateForm(', L);
    if P = 0 then Continue;
    Frag := Copy(L, P + Length('Application.CreateForm('), MaxInt);
    Q := 1;
    while (Q <= Length(Frag)) and CharInSet(Frag[Q], [' ', #9]) do Inc(Q);
    P := Q;
    while (P <= Length(Frag)) and CharInSet(Frag[P], ['A'..'Z','a'..'z','0'..'9','_']) do Inc(P);
    Cls := Copy(Frag, Q, P - Q);
    if AClassToNode.ContainsKey(Cls) then Exit(Cls);  // first form-node class wins
  end;
end;
```

Wire these into `GenerateFormsCsv`: after building/sorting `Nodes`, build the
class->node dictionary, the edges, detect the root, and fill the Navigation column:

```pascal
  // after Nodes.Sort(...)
  var ClassToNode := TDictionary<string, TFormNode>.Create;
  for N in Nodes do ClassToNode.AddOrSetValue(N.FormClass, N);
  var Edges := BuildEdges(Store, Nodes, ClassToNode);
  var RootClass := DetectRoot(AProjectFile, ARootForm, ClassToNode);
  try
    // ... in the row loop, replace the blank Navigation append:
    //   .Append(CsvField(NavOrUnreachable(...)))
  finally
    Edges.Free;
    ClassToNode.Free;
  end;
```

In the row loop, compute Navigation per node:

```pascal
        var Nav := '';
        if RootClass <> '' then
        begin
          Nav := NavPath(Edges, ClassToNode, RootClass, N.FormClass);
          if (Nav = '') and not SameText(N.FormClass, RootClass) then
            Nav := '(no path from MAIN)';
        end;
```

and `.Append(CsvField(Nav)).Append(',')` for the Navigation column.

Add `System.Generics.Collections` (already present) and ensure `TQueue` compiles.

- [ ] **Step 4: Add `GetSymbolById` to the store**

In `src/storage/DRagLint.Storage.SQLite.pas`, declare in the public section
(near `FindContainingSymbol` at line 118):

```pascal
    function GetSymbolById(AId: Int64): TSymbol;
```

Implement (place near `FindContainingSymbol`):

```pascal
function TSQLiteSymbolStore.GetSymbolById(AId: Int64): TSymbol;
var
  Q: TFDQuery;
begin
  Result := Default(TSymbol);
  Q := TFDQuery.Create(nil);
  try
    Q.Connection := FConn;
    Q.SQL.Text := 'SELECT * FROM symbols WHERE id = :id LIMIT 1';
    Q.ParamByName('id').AsLargeInt := AId;
    Q.Open;
    if not Q.IsEmpty then
      Result := ReadSymbolFromQuery(Q);
  finally
    Q.Free;
  end;
end;
```

(If `ReadSymbolFromQuery` is not visible, mirror the field reads used in
`FindContainingSymbol`.) Also add `GetSymbolById` to the `ISymbolStore` interface in
`src/core/DRagLint.Core.Interfaces.pas` if `FindContainingSymbol` is declared there;
otherwise leave it as a concrete method.

- [ ] **Step 5: Rebuild + run smoke**

Build (Task 1 Step 6) then `pwsh -File tests/autotest/run_formsmap.ps1`.
Expected: the three nav assertions PASS; inventory assertions still PASS.

- [ ] **Step 6: Commit**

```bash
git add src/forms/DRagLint.FormsMap.pas src/storage/DRagLint.Storage.SQLite.pas src/core/DRagLint.Core.Interfaces.pas tests/autotest/run_formsmap.ps1
git commit -m "feat(forms-csv): launch-edge graph + BFS navigation (direct ShowModal)

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 4: MDI named-constructor edges

Goal: confirm forms opened by a named constructor (the MDI pattern,
`TfrmX.CreateForFolder(...)`) are detected, since `IsLaunchLine` keys on
`<FormClass>.Create` which is a prefix of `.CreateForFolder`.

**Files:** add a fixture form + assertion; no engine change expected (this is a
guard test that locks the MDI behaviour in).

- [ ] **Step 1: Add an MDI-style child + a named-ctor launch**

Create `tests/fixtures/formsmap/uDemoChild.pas`:

```pascal
unit uDemoChild;
interface
uses Vcl.Forms;
type
  TfrmChild = class(TForm)
  public
    constructor CreateForFolder(AOwner: TComponent; AId: Integer);
  end;
implementation
{$R *.dfm}
constructor TfrmChild.CreateForFolder(AOwner: TComponent; AId: Integer);
begin
  inherited Create(AOwner);
end;
end.
```

Create `tests/fixtures/formsmap/uDemoChild.dfm`:

```
object frmChild: TfrmChild
  Left = 0
  Top = 0
  Caption = 'Child'
  ClientHeight = 150
  ClientWidth = 250
end
```

In `uDemoList.pas`, add a second button that opens the child via the named ctor.
Replace the `interface`/`implementation` of `uDemoList.pas` with:

```pascal
unit uDemoList;
interface
uses Vcl.Forms, Vcl.StdCtrls, uDemoEdit, uDemoChild;
type
  TfrmList = class(TForm)
    btnEdit: TButton;
    btnOpen: TButton;
    procedure btnEditClick(Sender: TObject);
    procedure btnOpenClick(Sender: TObject);
  end;
implementation
{$R *.dfm}
procedure TfrmList.btnEditClick(Sender: TObject);
begin
  TfrmEdit.Create(Self).ShowModal;
end;
procedure TfrmList.btnOpenClick(Sender: TObject);
begin
  TfrmChild.CreateForFolder(Self, 0);
end;
end.
```

In `uDemoList.dfm`, add the second button before `end`:

```
  object btnOpen: TButton
    Left = 8
    Top = 40
    Width = 75
    Height = 25
    Caption = 'Open Child'
    OnClick = btnOpenClick
  end
```

Add `uDemoChild.pas` to `Demo.dpr` uses (`uDemoChild in 'uDemoChild.pas' {frmChild},`)
and to `Demo.dproj` DCCReference list.

- [ ] **Step 2: Add the assertion (failing first)**

In `run_formsmap.ps1`:

```powershell
Check 'frmChild nav via named ctor' ($csv -match "uDemoChild,frmChild,\d+,frmMain -> 'Lists' -> 'Open Child',")
```

- [ ] **Step 3: Re-index + rebuild not needed (engine unchanged); run smoke**

Run: `pwsh -File tests/autotest/run_formsmap.ps1`
Expected: the new assertion PASSES with no engine change (the fixture re-indexes inside
the script). If it FAILS, the launch detector needs the named-ctor case - verify
`IsLaunchLine` matches `TfrmChild.CreateForFolder` (it should, via the `.Create`
prefix). Fix only if red.

- [ ] **Step 4: Commit**

```bash
git add tests/fixtures/formsmap tests/autotest/run_formsmap.ps1
git commit -m "test(forms-csv): MDI named-constructor edge guard

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 5: Within-form caption recursion, Action indirection, keep-the-gap

Goal: resolve captions when the launching routine is not directly a control handler
(called by one within the same form), when the trigger is a `TAction`, and emit
`(via Routine)` when nothing captioned is found.

**Files:** Modify `src/forms/DRagLint.FormsMap.pas`, fixtures, smoke test.

- [ ] **Step 1: Add fixtures for the three sub-cases**

(a) Indirect handler in `uDemoMain.pas`: add a plain method `OpenLists` called by the
button handler, and point the button at `OpenLists` indirectly. Replace
`btnListsClick` body:

```pascal
procedure TfrmMain.btnListsClick(Sender: TObject);
begin
  OpenLists;
end;

procedure TfrmMain.OpenLists;
begin
  TfrmList.Create(Self).ShowModal;
end;
```

and declare `procedure OpenLists;` in the class. (The button's `OnClick` stays
`btnListsClick`; the launch now sits in `OpenLists`, so caption resolution must walk
from `OpenLists` to its caller `btnListsClick` to find the `'Lists'` caption. The
existing Task 3 assertion `frmList nav via Lists` now exercises the recursion.)

(b) Action indirection: add to `uDemoMain.dfm` an action list + action, and a button
bound via `Action`:

```
  object ActionList1: TActionList
    object actReports: TAction
      Caption = 'Reports'
      OnExecute = actReportsExecute
    end
  end
  object btnReports: TButton
    Left = 90
    Top = 8
    Width = 75
    Height = 25
    Action = actReports
  end
```

In `uDemoMain.pas` add a form `frmReports` launch in `actReportsExecute`, declare the
method, add `uDemoReports` to uses. Create `uDemoReports.pas`/`.dfm` (a bare form like
`uDemoEdit`), add to `.dpr`/`.dproj`.

(c) Keep-the-gap: create `uDemoGap.pas`/`.dfm` (a bare form `frmGap`, class `TfrmGap`,
like `uDemoEdit`). The uncaptioned launch must live in a METHOD OF A REACHABLE FORM (so
an edge is actually produced) that has NO captioned binding. In `uDemoMain.pas`, add a
public method `OpenGap` whose body is `TfrmGap.Create(Self).ShowModal;`, declare it in
the `TfrmMain` class, add `uDemoGap` to uses -- but do NOT bind `OpenGap` to any control
(no `OnClick`) and do NOT call it from any other method. Add `uDemoGap` to `.dpr`/`.dproj`.

Why a form method, not a free procedure: `FindEnclosingImpl` only resolves a launch
site whose enclosing routine is a qualified `TClass.Method` belonging to a known form
node. A launch in a free-standing procedure yields NO edge (so the target would be
`(no path from MAIN)`, not `(via ...)`). Putting it in `TfrmMain.OpenGap` makes
`frmMain --(via OpenGap)--> frmGap` an edge: `CaptionForHandler(frmMain,'OpenGap')`
finds no event-binding, no Action, and no in-form caller, so it returns '' and the edge
caption becomes `(via OpenGap)` -- exactly the keep-the-gap behaviour.

- [ ] **Step 2: Add assertions (failing first)**

```powershell
Check 'action-bound caption (Reports)' ($csv -match "uDemoReports,frmReports,\d+,frmMain -> 'Reports',")
Check 'keep-the-gap via routine'        ($csv -match "uDemoGap,frmGap,\d+,frmMain -> \(via ")
```

- [ ] **Step 3: Run smoke to confirm RED for the new case**

Run: `pwsh -File tests/autotest/run_formsmap.ps1`
Expected: the existing `frmList nav via Lists` check now FAILS, because making
`btnListsClick` call `OpenLists` (which does the launch) means the launch's enclosing
routine is `OpenLists`, which has no captioned binding -- so without within-form caller
recursion the path renders `frmMain -> (via OpenLists)` instead of `frmMain -> 'Lists'`.
This is the RED that drives the recursion implementation. The `(Reports)` and
`keep-the-gap` checks may already pass (an action's `OnExecute` is itself an
event-binding whose owning `TAction` carries the caption; the gap edge already renders
`(via OpenGap)`), but keep them -- they guard those paths against regressions.

- [ ] **Step 4: Implement within-form recursion + Action resolution**

Replace `CaptionForHandler` with a recursive version that (1) checks direct
event-binding, (2) resolves `Action = X` on the bound control, (3) walks callers of the
routine *within the same form class*:

```pascal
/// <summary>Resolves the caption a tester presses in form ANode to invoke the
/// launching routine ARoutine: direct event-binding, Action-linked caption, or by
/// walking callers of ARoutine within the same form. '' if none found.</summary>
function CaptionForHandler(AStore: TSQLiteSymbolStore; const ANode: TFormNode;
  const ARoutine: string; AVisited: TDictionary<string, Boolean>): string;
var
  Q: TFDQuery;
  Line: Integer;
  Ctrl, ActSym: TSymbol;
  ActName, Cap: string;
begin
  Result := '';
  if AVisited.ContainsKey(ARoutine) then Exit;
  AVisited.Add(ARoutine, True);

  // (1) direct event-binding in this form's dfm
  Q := TFDQuery.Create(nil);
  try
    Q.Connection := AStore.GetConnection;
    Q.SQL.Text :=
      'SELECT start_line FROM refs ' +
      'WHERE kind = ''event-binding'' AND name_text = :h AND file_id = :fid ' +
      'ORDER BY start_line LIMIT 1';
    Q.ParamByName('h').AsString := ARoutine;
    Q.ParamByName('fid').AsLargeInt := ANode.DfmFileId;
    Q.Open;
    if not Q.IsEmpty then
    begin
      Line := Q.FieldByName('start_line').AsInteger;
      Ctrl := AStore.FindContainingSymbol(ANode.DfmFileId, Line);
      if Ctrl.Name <> '' then
      begin
        Cap := ReadCaption(ANode.DfmPath, Ctrl.StartLine, Ctrl.EndLine);
        if Cap <> '' then Exit(Cap);
        // (2) control bound via Action: read "Action = X", resolve X's caption.
        ActName := ReadActionRef(ANode.DfmPath, Ctrl.StartLine, Ctrl.EndLine);
        if ActName <> '' then
        begin
          ActSym := FindComponent(AStore, ANode.DfmFileId, ActName);
          if ActSym.Name <> '' then
          begin
            Cap := ReadCaption(ANode.DfmPath, ActSym.StartLine, ActSym.EndLine);
            if Cap <> '' then Exit(Cap);
          end;
        end;
      end;
    end;
  finally
    Q.Free;
  end;

  // Also: an action whose OnExecute is ARoutine (action not reached via a button's
  // own handler but bound directly). Find event-binding to ARoutine already covers
  // OnExecute (it is an On* property), so (1) handles it.

  // (3) walk callers of ARoutine WITHIN this form's own .pas.
  // IMPORTANT (verified in Task 3): implementation method BODIES are NOT indexed
  // as symbols (only their interface declaration line is, with start_line ==
  // end_line). So FindContainingSymbol over a .pas body line does NOT resolve the
  // enclosing routine. Reuse the FindEnclosingImpl text-scan helper (added to this
  // unit in Task 3) instead. A caller of ARoutine within the same form lives in the
  // form's own unit, so scan ANode.PasPath directly: for each line that mentions
  // ARoutine, resolve its enclosing routine; if it belongs to this form class,
  // recurse on that caller.
  var Lines: TArray<string> := [];
  if TFile.Exists(ANode.PasPath) then
    Lines := TFile.ReadAllLines(ANode.PasPath, TEncoding.ANSI);
  for var LineIdx := 0 to Length(Lines) - 1 do
  begin
    if Pos(ARoutine, Lines[LineIdx]) = 0 then Continue;
    var OwnerClass: string := '';
    var CallerRoutine: string := '';
    if FindEnclosingImpl(Lines, LineIdx + 1, OwnerClass, CallerRoutine) and
       SameText(OwnerClass, ANode.FormClass) and
       not SameText(CallerRoutine, ARoutine) then
    begin
      Cap := CaptionForHandler(AStore, ANode, CallerRoutine, AVisited);
      if Cap <> '' then Exit(Cap);
    end;
  end;
end;
```

Note: `FindEnclosingImpl` has signature
`function FindEnclosingImpl(const ALines: TArray<string>; ALaunchLine: Integer; out AOwnerClass, ARoutine: string): Boolean;`
(added in Task 3). It is in the same unit's implementation section, so it is callable
directly here. The `(2)` Action-indirection path is unchanged because DFM component
bodies ARE indexed with full ranges (so `FindContainingSymbol`/`FindComponent` over the
`.dfm` are correct); only the `.pas` body case needed the text-scan adaptation.

Add the two helpers:

```pascal
/// <summary>Reads "Action = X" within a control's .dfm line range; '' if none.</summary>
function ReadActionRef(const ADfmPath: string; AStartLine, AEndLine: Integer): string;
var
  Lines: TArray<string>;
  I, P: Integer;
  T: string;
begin
  Result := '';
  if not TFile.Exists(ADfmPath) then Exit;
  Lines := TFile.ReadAllLines(ADfmPath, TEncoding.ANSI);
  for I := AStartLine to AEndLine - 1 do
  begin
    if (I < 0) or (I >= Length(Lines)) then Continue;
    T := Trim(Lines[I]);
    if LowerCase(Copy(T, 1, 7)) = 'object ' then Exit;
    if LowerCase(Copy(T, 1, 8)) = 'action =' then
    begin
      P := Pos('=', T);
      Result := Trim(Copy(T, P + 1, MaxInt));
      Exit;
    end;
  end;
end;

/// <summary>Finds a component symbol by name within a .dfm file.</summary>
function FindComponent(AStore: TSQLiteSymbolStore; ADfmFileId: Int64;
  const AName: string): TSymbol;
var
  Q: TFDQuery;
begin
  Result := Default(TSymbol);
  Q := TFDQuery.Create(nil);
  try
    Q.Connection := AStore.GetConnection;
    Q.SQL.Text :=
      'SELECT * FROM symbols WHERE kind = ''component'' AND name = :n ' +
      'AND file_id = :fid LIMIT 1';
    Q.ParamByName('n').AsString := AName;
    Q.ParamByName('fid').AsLargeInt := ADfmFileId;
    Q.Open;
    if not Q.IsEmpty then
      Result := AStore.GetSymbolById(Q.FieldByName('id').AsLargeInt);
  finally
    Q.Free;
  end;
end;
```

Update the call in `BuildEdges` to pass a fresh visited set:

```pascal
              var Vis := TDictionary<string, Boolean>.Create;
              try
                Edge.Caption := CaptionForHandler(AStore, XNode, Routine, Vis);
              finally
                Vis.Free;
              end;
              if Edge.Caption = '' then
                Edge.Caption := '(via ' + Routine + ')';
```

- [ ] **Step 5: Rebuild + run smoke**

Build then `pwsh -File tests/autotest/run_formsmap.ps1`.
Expected: all caption assertions PASS (direct, indirect-recursion, Action, keep-the-gap).

- [ ] **Step 6: Commit**

```bash
git add src/forms/DRagLint.FormsMap.pas tests/fixtures/formsmap tests/autotest/run_formsmap.ps1
git commit -m "feat(forms-csv): caption recursion + Action indirection + keep-the-gap

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 6: Called From column, unreachable forms, cycle safety

Goal: fill the `Called From` column (all direct parent forms), confirm unreachable
forms render `(no path from MAIN)`, and confirm a cycle does not hang.

**Files:** Modify `src/forms/DRagLint.FormsMap.pas`, fixtures, smoke test.

- [ ] **Step 1: Add fixtures - an orphan form and a cycle**

Create `tests/fixtures/formsmap/uDemoUnreached.pas`/`.dfm` (form `frmLonely`, never
constructed anywhere). Add to `.dpr`/`.dproj`.

Add a cycle: in `uDemoEdit.pas` add a button that opens `frmList` (so List<->Edit form
a cycle). Add the button + `OnClick` in `uDemoEdit.dfm` and the launch in the handler
(`TfrmList.Create(Self).ShowModal;`), add `uDemoList` to `uDemoEdit.pas` uses.

- [ ] **Step 2: Add assertions (failing first)**

```powershell
Check 'unreachable form'      ($csv -match 'uDemoUnreached,frmLonely,\d+,\(no path from MAIN\),')
Check 'called-from for frmEdit' ($csv -match "uDemoEdit,frmEdit,\d+,[^,]*,frmList")
Check 'no hang (script completed)' ($true)
```

- [ ] **Step 3: Run smoke; expect called-from FAIL (column still blank)**

Run: `pwsh -File tests/autotest/run_formsmap.ps1`
Expected: `called-from` FAILS; `unreachable` already PASSES (Task 3 logic); the script
must still terminate (BFS visited-set prevents the cycle from hanging).

- [ ] **Step 4: Implement Called From**

Add to `DRagLint.FormsMap.pas`:

```pascal
/// <summary>Lists distinct parent forms that directly launch AToClass, each as its
/// form Name with the resolved caption in parentheses; ';'-separated.</summary>
function CalledFrom(AEdges: TList<TFormEdge>;
  AClassToNode: TDictionary<string, TFormNode>; const AToClass: string): string;
var
  E: TFormEdge;
  Seen: TStringList;
  ParentNode: TFormNode;
  Item: string;
begin
  Result := '';
  Seen := TStringList.Create;
  try
    Seen.Sorted := True;
    Seen.Duplicates := dupIgnore;
    for E in AEdges do
      if SameText(E.ToClass, AToClass) then
      begin
        if AClassToNode.TryGetValue(E.FromClass, ParentNode) then
          Item := ParentNode.FormName
        else
          Item := E.FromClass;
        if Copy(E.Caption, 1, 1) <> '(' then
          Item := Item + ' (' + E.Caption + ')';
        if Seen.IndexOf(Item) < 0 then
        begin
          Seen.Add(Item);
          if Result <> '' then Result := Result + '; ';
          Result := Result + Item;
        end;
      end;
  finally
    Seen.Free;
  end;
end;
```

In the row loop, set the Called From column:

```pascal
        var CF := CalledFrom(Edges, ClassToNode, N.FormClass);
```

and `.Append(CsvField(CF)).Append(',')` for that column.

- [ ] **Step 5: Rebuild + run smoke**

Expected: all assertions PASS; the script terminates (no cycle hang).

- [ ] **Step 6: Commit**

```bash
git add src/forms/DRagLint.FormsMap.pas tests/fixtures/formsmap tests/autotest/run_formsmap.ps1
git commit -m "feat(forms-csv): Called From column + unreachable + cycle-safe BFS

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 7: Real ORM3 smoke (end-to-end on the live index)

Goal: prove the command works on the real project, not just fixtures.

**Files:** none (manual/verification task; optionally append an opt-in check).

- [ ] **Step 1: Run against the real ORM3 index + project**

Run:
```
src\cli\Win32\Debug\drag-lint.exe forms-csv --project C:\Projects\DB\ORM3\CLIENT\Micronite2027.dproj --db C:\Projects\DB\ORM3\drag-lint.sqlite --out %TEMP%\orm3-forms.csv
```
Expected: exit 0; `%TEMP%\orm3-forms.csv` written.

- [ ] **Step 2: Spot-check the output**

Open the CSV and verify:
- `frmMAIN` row exists with blank Navigation (it is the root).
- `frmBlueprint4` (MDI) has a non-empty Navigation ending in a captioned step, and its
  Called From includes the Job List form.
- `dlgOperatorList` appears (a dialog) and `dmStyles` / data modules do NOT.
- Row count is in the expected ballpark (tens-to-hundreds of forms, no data modules).

Record findings (counts, any `(via ...)` hotspots, any surprising `(no path from MAIN)`)
in `docs/test-findings-2026-06-14-forms-csv.md`.

- [ ] **Step 3: Commit the findings doc**

```bash
git add docs/test-findings-2026-06-14-forms-csv.md
git commit -m "docs(forms-csv): ORM3 end-to-end smoke findings

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 8: IDE menu item

Goal: add **drag-lint -> Generate Test Helper CSV...** that saves all, runs the exe on
the active project, and opens the CSV. (Verified manually; the IDE cannot be smoke-tested
here.)

**Files:** Modify `src/delphi-plugin/DragLint.Plugin.Editor.pas`.

- [ ] **Step 1: Add the menu handler**

In `DragLint.Plugin.Editor.pas`, add a handler modelled on the existing exe-shelling
items (use `GetActiveProjectFile` at line 1034, `GetActiveProjectDb` at line 1052, the
`ExePath` resolution at lines 726-729, and the `CreateProcessW` capture helper at line
960). Add:

```pascal
procedure TDragLintMenu.GenerateFormsCsvClick(Sender: TObject);
var
  ProjFile, ProjDb, ExePath, OutPath, Cmd: string;
  Dlg: TSaveDialog;
begin
  // Save all so on-disk DFMs match the editor (the engine reads saved files).
  (BorlandIDEServices as IOTAModuleServices).SaveAll;
  ProjFile := GetActiveProjectFile;
  ProjDb   := GetActiveProjectDb;
  if (ProjFile = '') or (ProjDb = '') then
  begin
    ShowMessage('drag-lint: no active project or index found.');
    Exit;
  end;
  ExePath := LoadSettings.ExePath;
  if (ExePath = '') or not FileExists(ExePath) then
    ExePath := ExtractFilePath(GetModuleName(HInstance)) + 'drag-lint.exe';
  if not FileExists(ExePath) then ExePath := 'drag-lint.exe';

  Dlg := TSaveDialog.Create(nil);
  try
    Dlg.Filter := 'CSV files (*.csv)|*.csv';
    Dlg.DefaultExt := 'csv';
    Dlg.FileName := ChangeFileExt(ExtractFileName(ProjFile), '') + '-forms.csv';
    Dlg.InitialDir := ExtractFilePath(ProjFile);
    if not Dlg.Execute then Exit;
    OutPath := Dlg.FileName;
  finally
    Dlg.Free;
  end;

  Cmd := Format('"%s" forms-csv --project "%s" --db "%s" --out "%s"',
    [ExePath, ProjFile, ProjDb, OutPath]);
  if RunCaptured(Cmd) <> 0 then  // RunCaptured = the CreateProcessW helper near line 960
  begin
    ShowMessage('drag-lint: forms-csv failed. See plugin log.');
    Exit;
  end;
  // Open the CSV in the IDE editor.
  (BorlandIDEServices as IOTAActionServices).OpenFile(OutPath);
end;
```

(Match the actual class/owner of the existing menu handlers - they may be plain
procedures rather than methods; mirror whichever pattern the neighbouring items use,
e.g. `RenameSymbolClick` near line 1067. Use the existing `RunCaptured`/capture helper
name from line 960; if it differs, use the real name.)

- [ ] **Step 2: Register the menu item**

In the menu-construction block (root menu built near line 2011), add an item after an
existing entry (mirror how the other ~17 items are added):

```pascal
  AddMenuItem(RootMenu, 'Generate Test Helper CSV...', GenerateFormsCsvClick);
```

(Use the exact helper the file uses to add items - find the `AddMenuItem`-style helper
near line 1648; mirror its signature.)

- [ ] **Step 3: Rebuild the BPL**

Run:
```
cmd.exe /c "call \"C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\rsvars.bat\" && msbuild /t:Build /p:Config=Debug /p:Platform=Win32 src\delphi-plugin\dclDragLintWizard.dproj"
```
Expected: `Build succeeded.`

- [ ] **Step 4: Manual IDE verification**

In RAD Studio: uninstall the old BPL, install the rebuilt one, open ORM3, then
**Tools/menu -> drag-lint -> Generate Test Helper CSV...**, pick a path, confirm the CSV
opens and matches the CLI output from Task 7. Record the result in the findings doc.

- [ ] **Step 5: Commit**

```bash
git add src/delphi-plugin/DragLint.Plugin.Editor.pas docs/test-findings-2026-06-14-forms-csv.md
git commit -m "feat(forms-csv): IDE menu item (Save-All, run exe, open CSV)

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 9: Docs + changelog

**Files:** `README.md`, `CHANGELOG.md`, the smoke runner wiring.

- [ ] **Step 1: Document the command**

Add to `README.md` (command list) and `CHANGELOG.md` (a new entry) a short description
of `forms-csv` and the menu item, including the column meanings and the saved-DFM caveat.

- [ ] **Step 2: Wire run_formsmap.ps1 into the smoke suite**

If `tests/autotest/run_smoke.ps1` has a top-level runner or the repo has a test entry
point, add a call to `run_formsmap.ps1` so it runs with the suite. Otherwise leave it as
a standalone script and note it in `README.md` under testing.

- [ ] **Step 3: Final full smoke**

Run: `pwsh -File tests/autotest/run_formsmap.ps1`
Expected: all checks PASS, exit 0.

- [ ] **Step 4: Commit**

```bash
git add README.md CHANGELOG.md tests/autotest
git commit -m "docs(forms-csv): README + CHANGELOG; wire smoke runner

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Self-review notes (for the executor)

- The engine reads **saved** `.dfm`/`.pas` files; the IDE menu Save-Alls first.
- `IsLaunchLine` keys on `<FormClass>.Create` (covers named ctors) and
  `CreateForm(<FormClass>`; it deliberately ignores `is`/`as`/cast mentions because
  those lack that signal. If a future project opens forms by string/enum key, those
  rows will show `(no path from MAIN)` - expected, documented.
- Caption recursion and BFS both use visited sets - no infinite loops on cyclic graphs.
- Method/property names are consistent across tasks: `GenerateFormsCsv`, `LoadInventory`,
  `IsNavigableForm`, `ReadAncestor`, `BuildEdges`, `IsLaunchLine`, `CaptionForHandler`
  (recursive, takes `AVisited`), `ReadCaption`, `ReadActionRef`, `FindComponent`,
  `NavPath`, `DetectRoot`, `CalledFrom`, `CsvField`; store gains `GetSymbolById`.
- If `ReadSymbolFromQuery` / `ISymbolStore` shapes differ from what is referenced,
  mirror the nearest existing method rather than inventing new signatures.
