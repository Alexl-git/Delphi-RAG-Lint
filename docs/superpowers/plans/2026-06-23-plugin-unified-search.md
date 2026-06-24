# Unified Search Tab (IDE plugin) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a single human-oriented **Search** tab to the drag-lint dockable IDE panel: a Kind dropdown (Symbol/Text/Usages) + query field + one flat clickable results grid that jumps to source, with a clean empty state (never raw JSON or debug dumps).

**Architecture:** A new embed `CreateEmbeddedSearch` builds a toolbar (Kind combo + query edit + Search button + Advanced toggle), an optional advanced refinement row, and one `TListView`. It spawns existing `drag-lint` commands (`query --name` / `query --text` / `usages`) with `--json`, parses them with pure, ToolsAPI-free functions into a uniform `TSearchRow`, and fills the grid. Parsing lives in a separately-testable unit; process-spawning is extracted to one shared unit (today it is duplicated in two forms).

**Tech Stack:** Delphi 13 (Studio 37), VCL, ToolsAPI/OTAPI, `System.JSON`. Built as the design-time BPL `dclDragLintWizard`. Parser tests are a console program compiled with `dcc64`.

## Global Constraints

- Source files are strict 7-bit ASCII, CRLF. Never introduce Unicode or LF into `.pas`/`.dfm`/`.dpr`. After any Edit (which inserts LF), normalize the file to CRLF.
- DocInsight `///` spec-comments on every new public type/method; failing-test-first for the pure parsers (TDD); `try-finally` for resources.
- A NEW unit needs BOTH a `.dpk` `contains` entry (`Unit in 'Unit.pas',`) AND a `.dproj` `<DCCReference Include="Unit.pas"/>` (else F2613).
- Build the BPL via the **delphi-build** skill: `src\delphi-plugin\dclDragLintWizard.dproj`, Config=Debug, Platform=Win32 (the IDE plugin is Win32). Confirm `BUILD_EXITCODE=0` and no `[dcc] Error`. The BPL must NOT be loaded in a running RAD Studio instance or the link step locks the file.
- **Hard invariant (acceptance criterion):** the results grid and status line NEVER show raw JSON, command lines, or diagnostic dumps - only parsed rows and short status/error lines.
- Repo: `C:\Projects\Delphi-RAG-lint`, branch `feat/plugin-unified-search`. Plugin source: `src\delphi-plugin\`.
- Spec: `docs/superpowers/specs/2026-06-23-plugin-unified-search-design.md`.

---

### Task 1: Shared process-spawn unit (`ProcRun`)

Extract the byte-for-byte-duplicated stdout capture helper out of UsagesForm and SymbolSearchForm into one shared unit, so the new Search form (and the two existing forms) call one implementation.

**Files:**
- Create: `src\delphi-plugin\DragLint.Plugin.ProcRun.pas`
- Modify: `src\delphi-plugin\DragLint.Plugin.UsagesForm.pas` (delete its private `RunCaptureStdout`; use the shared one)
- Modify: `src\delphi-plugin\DragLint.Plugin.SymbolSearchForm.pas` (delete its private `RunCapture`; call the shared `RunCaptureStdout`)
- Modify: `src\delphi-plugin\dclDragLintWizard.dpk` and `dclDragLintWizard.dproj` (register the new unit)

**Interfaces:**
- Produces: `function RunCaptureStdout(const ACmdLine: string; out AOutput: string; ATimeoutMs: Integer): Integer;` - spawns `ACmdLine` with no window, captures stdout+stderr, returns the process exit code (or `< 0` on spawn failure).

- [ ] **Step 1: Create the unit** `src\delphi-plugin\DragLint.Plugin.ProcRun.pas` with the existing capture body verbatim (copy from `UsagesForm.RunCaptureStdout`, lines ~108-168):

```pascal
unit DragLint.Plugin.ProcRun;

{ Shared stdout/stderr capture for spawning drag-lint.exe with no console
  window. Extracted from UsagesForm/SymbolSearchForm (identical copies). }

interface

/// <summary>Spawns ACmdLine (CREATE_NO_WINDOW), captures stdout+stderr into
/// AOutput, waits up to ATimeoutMs (&lt;=0 = INFINITE), and returns the child
/// exit code, or a negative value if the process could not be started.</summary>
function RunCaptureStdout(const ACmdLine: string; out AOutput: string; ATimeoutMs: Integer): Integer;

implementation

uses
  System.SysUtils, Winapi.Windows;

function RunCaptureStdout(const ACmdLine: string; out AOutput: string; ATimeoutMs: Integer): Integer;
var
  SA       : TSecurityAttributes       ;
  ReadPipe : THandle                   ;
  WritePipe: THandle                   ;
  SI       : TStartupInfoW             ;
  PI       : TProcessInformation       ;
  Buf      : array[0..4095] of AnsiChar;
  BytesRead: DWORD                     ;
  ExitCode : DWORD                     ;
  WideCmd  : string                    ;
  SB       : TStringBuilder            ;
  TV       : DWORD                     ;
begin
  Result:= -1;
  AOutput:= '';
  SA.nLength:= SizeOf(SA);
  SA.bInheritHandle:= True;
  SA.lpSecurityDescriptor:= nil;
  if not CreatePipe(ReadPipe, WritePipe, @SA, 0) then Exit;
  try
    SetHandleInformation(ReadPipe, HANDLE_FLAG_INHERIT, 0);
    FillChar(SI, SizeOf(SI), 0);
    SI.cb:= SizeOf(SI);
    SI.dwFlags   := STARTF_USESTDHANDLES;
    SI.hStdOutput:= WritePipe;
    SI.hStdError := WritePipe;
    SI.hStdInput := GetStdHandle(STD_INPUT_HANDLE);
    FillChar(PI, SizeOf(PI), 0);
    WideCmd:= ACmdLine;
    UniqueString(WideCmd);
    if not CreateProcessW(nil, PWideChar(WideCmd), nil, nil, True, CREATE_NO_WINDOW, nil, nil, SI, PI) then
    begin
      CloseHandle(WritePipe);
      Exit;
    end;
    CloseHandle(WritePipe);
    SB:= TStringBuilder.Create;
    try
      repeat
        BytesRead:= 0;
        if not ReadFile(ReadPipe, Buf[0], SizeOf(Buf) - 1, BytesRead, nil) then Break;
        if BytesRead = 0 then Break;
        Buf[BytesRead]:= #0;
        SB.Append(string(AnsiString(Buf)));
      until False;
      AOutput:= SB.ToString;
    finally
      SB.Free;
    end;
    if ATimeoutMs <= 0 then TV:= INFINITE else TV:= DWORD(ATimeoutMs);
    WaitForSingleObject(PI.hProcess, TV);
    GetExitCodeProcess (PI.hProcess, ExitCode);
    Result:= Integer(ExitCode);
    CloseHandle(PI.hProcess);
    CloseHandle(PI.hThread );
  finally
    CloseHandle(ReadPipe);
  end;
end;

end.
```

- [ ] **Step 2: Register the unit.** In `dclDragLintWizard.dpk`, in the `contains` clause next to the other plugin units (after line ~57), add:

```pascal
  DragLint.Plugin.ProcRun in 'DragLint.Plugin.ProcRun.pas',
```

In `dclDragLintWizard.dproj`, next to the other `<DCCReference>` items (~line 99), add:

```xml
        <DCCReference Include="DragLint.Plugin.ProcRun.pas"/>
```

- [ ] **Step 3: Rewire UsagesForm.** In `DragLint.Plugin.UsagesForm.pas`: delete the private `function RunCaptureStdout(...)` (the whole `~108-168` block). Add `DragLint.Plugin.ProcRun` to the implementation `uses`. The single call site (`RunQuery`, `ExitCode:= RunCaptureStdout(CmdLine, Output, 30000);`) now resolves to the shared function unchanged.

- [ ] **Step 4: Rewire SymbolSearchForm.** In `DragLint.Plugin.SymbolSearchForm.pas`: delete the private `function RunCapture(...)` (`~73-133`). Add `DragLint.Plugin.ProcRun` to the implementation `uses`. Change the one call site in `RunSearch` from `RunCapture(CmdLine, Output, 15000)` to `RunCaptureStdout(CmdLine, Output, 15000)`.

- [ ] **Step 5: Normalize CRLF** on the three edited/created `.pas` files:

```powershell
foreach ($p in 'DragLint.Plugin.ProcRun.pas','DragLint.Plugin.UsagesForm.pas','DragLint.Plugin.SymbolSearchForm.pas') { $f="C:\Projects\Delphi-RAG-lint\src\delphi-plugin\$p"; $c=[IO.File]::ReadAllText($f); $c=$c -replace "`r`n","`n"; $c=$c -replace "`n","`r`n"; [IO.File]::WriteAllText($f,$c) }
```

- [ ] **Step 6: Build the BPL** (delphi-build skill, `dclDragLintWizard.dproj`, Debug/Win32). Expected: `BUILD_EXITCODE=0`, no `[dcc] Error`.

- [ ] **Step 7: Commit.**

```bash
git add src/delphi-plugin/DragLint.Plugin.ProcRun.pas src/delphi-plugin/DragLint.Plugin.UsagesForm.pas src/delphi-plugin/DragLint.Plugin.SymbolSearchForm.pas src/delphi-plugin/dclDragLintWizard.dpk src/delphi-plugin/dclDragLintWizard.dproj
git commit -m "refactor(plugin): extract shared RunCaptureStdout into DragLint.Plugin.ProcRun"
```

---

### Task 2: Pure result parsers (`SearchParse`) - TDD

The testable core: turn each command's `--json` into a uniform `TSearchRow` list, plus the Kind-filter mapping. ToolsAPI/VCL-free so a console test can exercise it.

**Files:**
- Create: `src\delphi-plugin\DragLint.Plugin.SearchParse.pas`
- Create (test): `tests\searchparse\SearchParseTests.dpr`
- Create (test runner): `tests\searchparse\run_searchparse_tests.ps1`
- Modify: `dclDragLintWizard.dpk` + `.dproj` (register `SearchParse`)

**Interfaces:**
- Produces:
  - `TSearchRow = record Category, ColA, ColB, FilePath: string; Line: Integer; end;`
  - `TSearchRows = TArray<TSearchRow>;`
  - `function ParseNameJson(const AJson: string): TSearchRows;` (from `query --name --json`)
  - `function ParseTextJson(const AJson: string): TSearchRows;` (from `query --text --json`)
  - `function ParseUsagesJson(const AJson: string): TSearchRows;` (from `usages --format json`)
  - `function KindMatchesFilter(const AKind, AFilter: string): Boolean;` (`AFilter` = '', 'Any', 'Method', 'Type/Class', 'Field/Var', 'Const', 'Property', 'Unit')

- [ ] **Step 1: Write the failing test** `tests\searchparse\SearchParseTests.dpr` (console; embeds the real JSON shapes captured from the CLI):

```pascal
program SearchParseTests;
{$APPTYPE CONSOLE}
uses
  System.SysUtils,
  DragLint.Plugin.SearchParse in '..\..\src\delphi-plugin\DragLint.Plugin.SearchParse.pas';
var
  GFail: Integer = 0;
procedure Check(const AName: string; ACond: Boolean);
begin
  if ACond then Writeln('PASS ', AName)
  else begin Writeln('FAIL ', AName); Inc(GFail); end;
end;
const
  NAME_JSON =
    '[{"id":577,"kind":"method","name":"SearchText","qualified_name":"DRagLint.Core.Interfaces.ISymbolStore.SearchText",' +
    '"file":"C:\\p\\Interfaces.pas","start_line":144},' +
    '{"id":2416,"kind":"method","name":"SearchText","qualified_name":"X.SearchText","file":"C:\\p\\SQLite.pas","start_line":78}]';
  TEXT_JSON =
    '[{"file_path":"C:\\p\\DockForm.pas","start_line":209,"source":"pas","kind":"literal","text":"Find Usages","enclosing":"X"}]';
  USAGES_JSON =
    '{"name":"SearchText","width":"narrow",' +
    '"declarations":[{"kind":"method","qname":"X.SearchText","file":"C:\\p\\I.pas","line":144}],' +
    '"reads":[],"writes":[],"calls":[{"file":"C:\\p\\CLI.pas","line":2023,"col":21}],' +
    '"types":[],"attributes":[],"events":[],"impact":[]}';
var
  R: TSearchRows;
begin
  R := ParseNameJson(NAME_JSON);
  Check('name: 2 rows', Length(R) = 2);
  Check('name: row0 category', (Length(R) > 0) and (R[0].Category = 'Symbol'));
  Check('name: row0 ColA', (Length(R) > 0) and (R[0].ColA = 'SearchText'));
  Check('name: row0 ColB kind', (Length(R) > 0) and (R[0].ColB = 'method'));
  Check('name: row0 line', (Length(R) > 0) and (R[0].Line = 144));
  Check('name: row0 file', (Length(R) > 0) and R[0].FilePath.EndsWith('Interfaces.pas'));

  R := ParseTextJson(TEXT_JSON);
  Check('text: 1 row', Length(R) = 1);
  Check('text: category', (Length(R) > 0) and (R[0].Category = 'Text'));
  Check('text: ColA text', (Length(R) > 0) and (R[0].ColA = 'Find Usages'));
  Check('text: ColB source', (Length(R) > 0) and (R[0].ColB = 'pas'));
  Check('text: line', (Length(R) > 0) and (R[0].Line = 209));

  R := ParseUsagesJson(USAGES_JSON);
  Check('usages: 2 rows (1 decl + 1 call)', Length(R) = 2);
  Check('usages: has Decl', (Length(R) > 0) and (R[0].Category = 'Decl'));
  Check('usages: has Call line 2023', (Length(R) > 1) and (R[1].Category = 'Call') and (R[1].Line = 2023));

  Check('kind: function is Method', KindMatchesFilter('function', 'Method'));
  Check('kind: class is NOT Method', not KindMatchesFilter('class', 'Method'));
  Check('kind: field is Field/Var', KindMatchesFilter('field', 'Field/Var'));
  Check('kind: Any matches anything', KindMatchesFilter('method', 'Any'));
  Check('kind: empty matches anything', KindMatchesFilter('const', ''));

  if GFail > 0 then begin Writeln(GFail, ' FAILED'); Halt(1); end
  else Writeln('searchparse: all pass');
end.
```

- [ ] **Step 2: Write the runner** `tests\searchparse\run_searchparse_tests.ps1`:

```powershell
$rs = 'C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\rsvars.bat'
$dir = $PSScriptRoot
$out = cmd /c "call `"$rs`" && dcc64 -B -E`"$dir`" `"$dir\SearchParseTests.dpr`"" 2>&1
$err = $out | Select-String -Pattern "\bError\b|E2\d{3}|F2\d{3}|Fatal"
if ($err) { Write-Host "BUILD FAILED:"; $err | Select-Object -First 10; exit 1 }
& "$dir\SearchParseTests.exe"
exit $LASTEXITCODE
```

- [ ] **Step 3: Run it - expect FAIL** (the unit does not exist -> compile error). Run: `pwsh -File tests\searchparse\run_searchparse_tests.ps1`. Expected: BUILD FAILED (cannot find `DragLint.Plugin.SearchParse`).

- [ ] **Step 4: Implement** `src\delphi-plugin\DragLint.Plugin.SearchParse.pas`:

```pascal
unit DragLint.Plugin.SearchParse;

{ Pure (ToolsAPI/VCL-free) parsers turning drag-lint --json output into a
  uniform row model for the Search tab grid. Unit-tested by
  tests\searchparse\SearchParseTests.dpr. }

interface

uses
  System.SysUtils;

type
  /// <summary>One grid row. FilePath/Line drive navigation; Line=0 = not
  /// navigable (e.g. an Impact summary).</summary>
  TSearchRow = record
    Category: string ;
    ColA    : string ;
    ColB    : string ;
    FilePath: string ;
    Line    : Integer;
  end;
  TSearchRows = TArray<TSearchRow>;

/// <summary>Rows from `query --name --json` (array of symbol objects).</summary>
function ParseNameJson(const AJson: string): TSearchRows;
/// <summary>Rows from `query --text --json` (array of literal-match objects).</summary>
function ParseTextJson(const AJson: string): TSearchRows;
/// <summary>Rows from `usages --format json` (grouped object), flattened.</summary>
function ParseUsagesJson(const AJson: string): TSearchRows;
/// <summary>True if a drag-lint symbol kind belongs to the UI kind filter
/// (''/'Any' match all).</summary>
function KindMatchesFilter(const AKind, AFilter: string): Boolean;

implementation

uses
  System.JSON, System.Generics.Collections;

function MakeRow(const ACat, AColA, AColB, AFile: string; ALine: Integer): TSearchRow;
begin
  Result.Category:= ACat; Result.ColA:= AColA; Result.ColB:= AColB;
  Result.FilePath:= AFile; Result.Line:= ALine;
end;

function ParseNameJson(const AJson: string): TSearchRows;
var
  Root: TJSONValue; Arr: TJSONArray; i: Integer; O: TJSONObject;
  Nm, Kd, F: string; Ln: Integer; List: TList<TSearchRow>;
begin
  SetLength(Result, 0);
  Root:= TJSONObject.ParseJSONValue(AJson);
  if not (Root is TJSONArray) then begin Root.Free; Exit; end;
  List:= TList<TSearchRow>.Create;
  try
    Arr:= TJSONArray(Root);
    for i:= 0 to Arr.Count - 1 do
    begin
      if not (Arr.Items[i] is TJSONObject) then Continue;
      O:= TJSONObject(Arr.Items[i]);
      Nm:= ''; Kd:= ''; F:= ''; Ln:= 0;
      O.TryGetValue<string>('name', Nm);
      O.TryGetValue<string>('kind', Kd);
      O.TryGetValue<string>('file', F);
      O.TryGetValue<Integer>('start_line', Ln);
      List.Add(MakeRow('Symbol', Nm, Kd, F, Ln));
    end;
    Result:= List.ToArray;
  finally
    List.Free; Root.Free;
  end;
end;

function ParseTextJson(const AJson: string): TSearchRows;
var
  Root: TJSONValue; Arr: TJSONArray; i: Integer; O: TJSONObject;
  Tx, Sr, F: string; Ln: Integer; List: TList<TSearchRow>;
begin
  SetLength(Result, 0);
  Root:= TJSONObject.ParseJSONValue(AJson);
  if not (Root is TJSONArray) then begin Root.Free; Exit; end;
  List:= TList<TSearchRow>.Create;
  try
    Arr:= TJSONArray(Root);
    for i:= 0 to Arr.Count - 1 do
    begin
      if not (Arr.Items[i] is TJSONObject) then Continue;
      O:= TJSONObject(Arr.Items[i]);
      Tx:= ''; Sr:= ''; F:= ''; Ln:= 0;
      O.TryGetValue<string>('text', Tx);
      O.TryGetValue<string>('source', Sr);
      O.TryGetValue<string>('file_path', F);
      O.TryGetValue<Integer>('start_line', Ln);
      List.Add(MakeRow('Text', Tx, Sr, F, Ln));
    end;
    Result:= List.ToArray;
  finally
    List.Free; Root.Free;
  end;
end;

function ParseUsagesJson(const AJson: string): TSearchRows;
var
  Root: TJSONValue; Obj: TJSONObject; List: TList<TSearchRow>;

  procedure AddGroup(const AKey, ACat: string);
  var Arr: TJSONArray; i: Integer; O: TJSONObject; F, QN: string; Ln: Integer;
  begin
    if not Obj.TryGetValue<TJSONArray>(AKey, Arr) then Exit;
    for i:= 0 to Arr.Count - 1 do
    begin
      if not (Arr.Items[i] is TJSONObject) then Continue;
      O:= TJSONObject(Arr.Items[i]);
      F:= ''; QN:= ''; Ln:= 0;
      O.TryGetValue<string>('file', F);
      O.TryGetValue<string>('qname', QN);
      O.TryGetValue<Integer>('line', Ln);
      if QN <> '' then List.Add(MakeRow(ACat, QN, ExtractFileName(F), F, Ln))
      else List.Add(MakeRow(ACat, ExtractFileName(F), '', F, Ln));
    end;
  end;

  procedure AddImpact;
  var Arr: TJSONArray; i: Integer; O: TJSONObject; Dp, Ca, Un: Integer;
  begin
    if not Obj.TryGetValue<TJSONArray>('impact', Arr) then Exit;
    for i:= 0 to Arr.Count - 1 do
    begin
      if not (Arr.Items[i] is TJSONObject) then Continue;
      O:= TJSONObject(Arr.Items[i]);
      Dp:= 0; Ca:= 0; Un:= 0;
      O.TryGetValue<Integer>('depth', Dp);
      O.TryGetValue<Integer>('callers', Ca);
      O.TryGetValue<Integer>('units', Un);
      List.Add(MakeRow('Impact', Format('depth %d: %d callers across %d units', [Dp, Ca, Un]), '', '', 0));
    end;
  end;

begin
  SetLength(Result, 0);
  Root:= TJSONObject.ParseJSONValue(AJson);
  if not (Root is TJSONObject) then begin Root.Free; Exit; end;
  List:= TList<TSearchRow>.Create;
  try
    Obj:= TJSONObject(Root);
    AddGroup('declarations', 'Decl' );
    AddGroup('reads'       , 'Read' );
    AddGroup('writes'      , 'Write');
    AddGroup('calls'       , 'Call' );
    AddGroup('types'       , 'Type' );
    AddGroup('attributes'  , 'Attr' );
    AddGroup('events'      , 'Event');
    AddImpact;
    Result:= List.ToArray;
  finally
    List.Free; Root.Free;
  end;
end;

function KindMatchesFilter(const AKind, AFilter: string): Boolean;
  function In_(const A: array of string): Boolean;
  var s: string;
  begin
    Result:= False;
    for s in A do if SameText(AKind, s) then Exit(True);
  end;
begin
  if (AFilter = '') or SameText(AFilter, 'Any') then Exit(True);
  if SameText(AFilter, 'Method')     then Exit(In_(['method','function','procedure','constructor','destructor']));
  if SameText(AFilter, 'Type/Class') then Exit(In_(['class','record','interface','enum','type']));
  if SameText(AFilter, 'Field/Var')  then Exit(In_(['field','var']));
  if SameText(AFilter, 'Const')      then Exit(In_(['const']));
  if SameText(AFilter, 'Property')   then Exit(In_(['property']));
  if SameText(AFilter, 'Unit')       then Exit(In_(['unit','program','package']));
  Result:= True;
end;

end.
```

- [ ] **Step 5: Normalize CRLF** on `DragLint.Plugin.SearchParse.pas` and `tests\searchparse\SearchParseTests.dpr` (same one-liner as Task 1 Step 5, per file).

- [ ] **Step 6: Run - expect PASS.** Run: `pwsh -File tests\searchparse\run_searchparse_tests.ps1`. Expected final line: `searchparse: all pass` (exit 0).

- [ ] **Step 7: Register the unit** in `dclDragLintWizard.dpk` (`DragLint.Plugin.SearchParse in 'DragLint.Plugin.SearchParse.pas',`) and `.dproj` (`<DCCReference Include="DragLint.Plugin.SearchParse.pas"/>`).

- [ ] **Step 8: Commit.**

```bash
git add src/delphi-plugin/DragLint.Plugin.SearchParse.pas tests/searchparse src/delphi-plugin/dclDragLintWizard.dpk src/delphi-plugin/dclDragLintWizard.dproj
git commit -m "feat(plugin): SearchParse pure JSON->row parsers + console tests"
```

---

### Task 3: Search form (`CreateEmbeddedSearch`)

The embedded tab UI: toolbar (Kind/query/Search/Advanced) + advanced row + grid, query dispatch, grid fill, navigation, clean empty state.

**Files:**
- Create: `src\delphi-plugin\DragLint.Plugin.SearchForm.pas`
- Modify: `dclDragLintWizard.dpk` + `.dproj`

**Interfaces:**
- Consumes: `RunCaptureStdout` (ProcRun); `ParseNameJson/ParseTextJson/ParseUsagesJson/KindMatchesFilter/TSearchRow/TSearchRows` (SearchParse); `OpenSourceAt(const AFile: string; ALine: Integer)` (DragLint.Plugin.HoverForm); `ResolveActiveIndexDbs(LoadSettings): TArray<string>` (DbResolver); `LoadSettings` (Settings).
- Produces: `procedure CreateEmbeddedSearch(AOwner: TComponent; AParent: TWinControl);`

- [ ] **Step 1: Implement the unit.** Mirror `CreateEmbeddedSymbolSearch` for control creation. A handler `TSearchHandler(TComponent)` owns the controls and holds `FKind, FQueryEdit: TEdit; FList: TListView; FStatus: TLabel; FBtn: TButton; FAdvChk: TCheckBox; FAdvPanel: TPanel; FKindFilter, FTextMode, FTextSource, FWidth: TComboBox; FRows: TSearchRows`.

```pascal
unit DragLint.Plugin.SearchForm;

{ Unified Search dock tab: Kind (Symbol/Text/Usages) + query + one flat grid.
  Spawns drag-lint --json, parses via SearchParse, fills a TListView, jumps to
  source on activate. Never shows raw JSON / debug. }

interface

uses
  System.Classes, Vcl.Controls;

/// <summary>Build the Search UI into AParent (a dock tab). Controls are owned
/// by AOwner so they live/die with the dock frame.</summary>
procedure CreateEmbeddedSearch(AOwner: TComponent; AParent: TWinControl);

implementation

uses
  System.SysUtils, System.Generics.Collections,
  Vcl.StdCtrls, Vcl.ComCtrls, Vcl.ExtCtrls, Winapi.Windows,
  DragLint.Plugin.ProcRun, DragLint.Plugin.SearchParse,
  DragLint.Plugin.HoverForm, DragLint.Plugin.DbResolver, DragLint.Plugin.Settings;

type
  TSearchHandler = class(TComponent)
  public
    FKind      : TComboBox ;
    FQuery     : TEdit     ;
    FBtn       : TButton   ;
    FAdvChk    : TCheckBox ;
    FAdvPanel  : TPanel    ;
    FKindFilter: TComboBox ;
    FTextMode  : TComboBox ;
    FTextSource: TComboBox ;
    FWidth     : TComboBox ;
    FList      : TListView ;
    FStatus    : TLabel    ;
    FDebounce  : TTimer    ;
    FRows      : TSearchRows;
    function ResolveExe: string;
    function DbArgs: string;
    function CurrentKind: string;
    procedure Reconfigure;            // show the right advanced controls per Kind
    procedure RebuildColumns;
    procedure RunSearch;
    procedure Fill(const ARows: TSearchRows);
    procedure SetEmpty(const AMsg: string);
    procedure KindChange(Sender: TObject);
    procedure AdvChange(Sender: TObject);
    procedure QueryKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
    procedure QueryChange(Sender: TObject);
    procedure DebounceFired(Sender: TObject);
    procedure BtnClick(Sender: TObject);
    procedure ListActivate(Sender: TObject);
  end;

function TSearchHandler.ResolveExe: string;
begin
  Result:= LoadSettings.ExePath;
  if (Result = '') or not FileExists(Result) then Result:= ExtractFilePath(GetModuleName(HInstance)) + 'drag-lint.exe';
  if not FileExists(Result) then Result:= 'drag-lint.exe';
end;

function TSearchHandler.DbArgs: string;
var Dbs: TArray<string>; P: string;
begin
  Result:= '';
  try Dbs:= ResolveActiveIndexDbs(LoadSettings); except SetLength(Dbs, 0); end;
  for P in Dbs do if P <> '' then Result:= Result + Format(' --db "%s"', [P]);
end;

function TSearchHandler.CurrentKind: string;
begin
  case FKind.ItemIndex of
    1: Result:= 'Text';
    2: Result:= 'Usages';
    else Result:= 'Symbol';
  end;
end;

procedure TSearchHandler.Reconfigure;
var K: string;
begin
  K:= CurrentKind;
  FKindFilter.Visible:= (K = 'Symbol');
  FTextMode  .Visible:= (K = 'Text');
  FTextSource.Visible:= (K = 'Text');
  FWidth     .Visible:= (K = 'Usages');
end;

procedure TSearchHandler.RebuildColumns;
  procedure Cols(const A, B, C: string);
  var col: TListColumn;
  begin
    FList.Columns.Clear;
    col:= FList.Columns.Add; col.Caption:= A; col.Width:= 90;
    col:= FList.Columns.Add; col.Caption:= B; col.Width:= 280;
    col:= FList.Columns.Add; col.Caption:= C; col.Width:= 260;
  end;
begin
  if CurrentKind = 'Symbol' then Cols('Kind', 'Name', 'Location')
  else if CurrentKind = 'Text' then Cols('Source', 'Text', 'Location')
  else Cols('Category', 'Detail', 'Location');
end;

procedure TSearchHandler.SetEmpty(const AMsg: string);
begin
  FStatus.Caption:= AMsg;
end;

procedure TSearchHandler.Fill(const ARows: TSearchRows);
var i: Integer; it: TListItem;
begin
  FRows:= ARows;
  FList.Items.BeginUpdate;
  try
    FList.Items.Clear;
    for i:= 0 to High(ARows) do
    begin
      it:= FList.Items.Add;
      // Column order: ColCat/ColB-ish first per RebuildColumns. Map uniformly:
      if CurrentKind = 'Symbol' then begin it.Caption:= ARows[i].ColB; it.SubItems.Add(ARows[i].ColA); end
      else if CurrentKind = 'Text' then begin it.Caption:= ARows[i].ColB; it.SubItems.Add(ARows[i].ColA); end
      else begin it.Caption:= ARows[i].Category; it.SubItems.Add(ARows[i].ColA); end;
      if ARows[i].Line > 0 then it.SubItems.Add(Format('%s:%d', [ExtractFileName(ARows[i].FilePath), ARows[i].Line]))
      else it.SubItems.Add('');
      it.Data:= Pointer(i); // index into FRows for navigation
    end;
  finally
    FList.Items.EndUpdate;
  end;
end;

procedure TSearchHandler.RunSearch;
var
  Exe, Cmd, Outp, K, Q: string; ExitCode: Integer; Rows: TSearchRows;
begin
  Q:= Trim(FQuery.Text);
  if Q = '' then begin FList.Items.Clear; SetEmpty('Type to search.'); Exit; end;
  Exe:= ResolveExe;
  K:= CurrentKind;
  RebuildColumns;
  SetEmpty('Searching.');

  if K = 'Symbol' then
    Cmd:= Format('"%s" query --name "%s"%s --json', [Exe, Q, DbArgs])
  else if K = 'Text' then
  begin
    Cmd:= Format('"%s" query --text "%s"', [Exe, Q]);
    case FTextMode.ItemIndex of 1: Cmd:= Cmd + ' --substring'; 2: Cmd:= Cmd + ' --any-order'; end;
    if FTextSource.ItemIndex > 0 then Cmd:= Cmd + ' --source ' + LowerCase(FTextSource.Text);
    Cmd:= Cmd + DbArgs + ' --json';
  end
  else
  begin
    Cmd:= Format('"%s" usages --name "%s" --width %s%s --format json',
      [Exe, Q, LowerCase(StringReplace(FWidth.Text, ' ', '-', [rfReplaceAll])), DbArgs]);
  end;

  if K = 'Usages' then ExitCode:= RunCaptureStdout(Cmd, Outp, 30000)
  else ExitCode:= RunCaptureStdout(Cmd, Outp, 15000);
  Outp:= Trim(Outp);

  if ExitCode < 0 then begin FList.Items.Clear; SetEmpty('drag-lint not found or failed to start'); Exit; end;
  if (Outp = '') or (not (CharInSet(Outp[1], ['[', '{']))) then
  begin
    FList.Items.Clear;
    if Copy(Outp, 1, 5) = 'ERROR' then SetEmpty('drag-lint error: ' + Copy(Outp, 1, 200))
    else SetEmpty(Format('drag-lint error (exit %d)', [ExitCode]));
    Exit;
  end;

  if K = 'Symbol' then
  begin
    Rows:= ParseNameJson(Outp);
    if FKindFilter.ItemIndex > 0 then
    begin
      var Keep: TList<TSearchRow>:= TList<TSearchRow>.Create;
      try
        for var R in Rows do if KindMatchesFilter(R.ColB, FKindFilter.Text) then Keep.Add(R);
        Rows:= Keep.ToArray;
      finally Keep.Free; end;
    end;
  end
  else if K = 'Text' then Rows:= ParseTextJson(Outp)
  else Rows:= ParseUsagesJson(Outp);

  Fill(Rows);
  if Length(Rows) = 0 then
  begin
    if Trim(DbArgs) = '' then SetEmpty('No project index found - run Tools > drag-lint > Lint Buffer, or set the exe/DB in settings.')
    else if (K = 'Symbol') then SetEmpty(Format('No matches for "%s"  -  drag-lint indexes types/methods/fields/consts, not locals or parameters.', [Q]))
    else if (K = 'Text') and (FTextMode.ItemIndex = 1) and (Length(Q) < 3) then SetEmpty('--substring needs >= 3 characters; try Any-word.')
    else SetEmpty(Format('No matches for "%s"', [Q]));
  end
  else SetEmpty(Format('%d result(s)', [Length(Rows)]));
end;

procedure TSearchHandler.KindChange(Sender: TObject);
begin Reconfigure; RebuildColumns; if Trim(FQuery.Text) <> '' then RunSearch; end;

procedure TSearchHandler.AdvChange(Sender: TObject);
begin FAdvPanel.Visible:= FAdvChk.Checked; end;

procedure TSearchHandler.QueryKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
begin if Key = VK_RETURN then begin Key:= 0; RunSearch; end; end;

procedure TSearchHandler.QueryChange(Sender: TObject);
begin
  if CurrentKind = 'Symbol' then begin FDebounce.Enabled:= False; FDebounce.Enabled:= True; end;
end;

procedure TSearchHandler.DebounceFired(Sender: TObject);
begin FDebounce.Enabled:= False; if CurrentKind = 'Symbol' then RunSearch; end;

procedure TSearchHandler.BtnClick(Sender: TObject);
begin RunSearch; end;

procedure TSearchHandler.ListActivate(Sender: TObject);
var idx: Integer;
begin
  if FList.Selected = nil then Exit;
  idx:= Integer(FList.Selected.Data);
  if (idx < 0) or (idx > High(FRows)) then Exit;
  if (FRows[idx].FilePath <> '') and (FRows[idx].Line > 0) then OpenSourceAt(FRows[idx].FilePath, FRows[idx].Line);
end;

procedure CreateEmbeddedSearch(AOwner: TComponent; AParent: TWinControl);
var H: TSearchHandler; Pnl: TPanel;
begin
  H:= TSearchHandler.Create(AOwner);

  // toolbar row
  Pnl:= TPanel.Create(AOwner); Pnl.Parent:= AParent; Pnl.Align:= alTop; Pnl.Height:= 28; Pnl.BevelOuter:= bvNone;
  H.FKind:= TComboBox.Create(AOwner); H.FKind.Parent:= Pnl; H.FKind.Align:= alLeft; H.FKind.Width:= 90; H.FKind.Style:= csDropDownList;
  H.FKind.Items.Add('Symbol'); H.FKind.Items.Add('Text'); H.FKind.Items.Add('Usages'); H.FKind.ItemIndex:= 0;
  H.FKind.OnChange:= H.KindChange;
  H.FAdvChk:= TCheckBox.Create(AOwner); H.FAdvChk.Parent:= Pnl; H.FAdvChk.Align:= alRight; H.FAdvChk.Width:= 90; H.FAdvChk.Caption:= 'Advanced'; H.FAdvChk.OnClick:= H.AdvChange;
  H.FBtn:= TButton.Create(AOwner); H.FBtn.Parent:= Pnl; H.FBtn.Align:= alRight; H.FBtn.Width:= 70; H.FBtn.Caption:= 'Search'; H.FBtn.OnClick:= H.BtnClick;
  H.FQuery:= TEdit.Create(AOwner); H.FQuery.Parent:= Pnl; H.FQuery.Align:= alClient; H.FQuery.TextHint:= 'type, then Enter';
  H.FQuery.OnKeyDown:= H.QueryKeyDown; H.FQuery.OnChange:= H.QueryChange;

  // advanced row (hidden by default)
  H.FAdvPanel:= TPanel.Create(AOwner); H.FAdvPanel.Parent:= AParent; H.FAdvPanel.Align:= alTop; H.FAdvPanel.Height:= 28; H.FAdvPanel.BevelOuter:= bvNone; H.FAdvPanel.Visible:= False;
  H.FKindFilter:= TComboBox.Create(AOwner); H.FKindFilter.Parent:= H.FAdvPanel; H.FKindFilter.Align:= alLeft; H.FKindFilter.Width:= 110; H.FKindFilter.Style:= csDropDownList;
  for var s in ['Any','Method','Type/Class','Field/Var','Const','Property','Unit'] do H.FKindFilter.Items.Add(s);
  H.FKindFilter.ItemIndex:= 0; H.FKindFilter.OnChange:= H.AdvChange;
  H.FTextMode:= TComboBox.Create(AOwner); H.FTextMode.Parent:= H.FAdvPanel; H.FTextMode.Align:= alLeft; H.FTextMode.Width:= 100; H.FTextMode.Style:= csDropDownList;
  for var s in ['Phrase','Substring','Any-word'] do H.FTextMode.Items.Add(s); H.FTextMode.ItemIndex:= 0;
  H.FTextSource:= TComboBox.Create(AOwner); H.FTextSource.Parent:= H.FAdvPanel; H.FTextSource.Align:= alLeft; H.FTextSource.Width:= 90; H.FTextSource.Style:= csDropDownList;
  for var s in ['All','pas','dfm','sql'] do H.FTextSource.Items.Add(s); H.FTextSource.ItemIndex:= 0;
  H.FWidth:= TComboBox.Create(AOwner); H.FWidth.Parent:= H.FAdvPanel; H.FWidth.Align:= alLeft; H.FWidth.Width:= 100; H.FWidth.Style:= csDropDownList;
  for var s in ['Narrow','Wide','Very wide'] do H.FWidth.Items.Add(s); H.FWidth.ItemIndex:= 0;

  // status + grid
  H.FStatus:= TLabel.Create(AOwner); H.FStatus.Parent:= AParent; H.FStatus.Align:= alBottom; H.FStatus.Layout:= tlCenter; H.FStatus.Height:= 18; H.FStatus.Caption:= 'Type to search.';
  H.FList:= TListView.Create(AOwner); H.FList.Parent:= AParent; H.FList.Align:= alClient; H.FList.ViewStyle:= vsReport; H.FList.ReadOnly:= True; H.FList.RowSelect:= True; H.FList.HideSelection:= False;
  H.FList.OnDblClick:= H.ListActivate;

  H.FDebounce:= TTimer.Create(H); H.FDebounce.Interval:= 300; H.FDebounce.Enabled:= False; H.FDebounce.OnTimer:= H.DebounceFired;

  H.Reconfigure; H.RebuildColumns;
end;

end.
```

- [ ] **Step 2: Normalize CRLF** on `DragLint.Plugin.SearchForm.pas`.

- [ ] **Step 3: Register the unit** in `dclDragLintWizard.dpk` (`DragLint.Plugin.SearchForm in 'DragLint.Plugin.SearchForm.pas',`) and `.dproj` (`<DCCReference Include="DragLint.Plugin.SearchForm.pas"/>`).

- [ ] **Step 4: Build the BPL** (delphi-build skill, Debug/Win32). Expected: `BUILD_EXITCODE=0`, no `[dcc] Error`. (Fix any compile errors against the real signatures of `OpenSourceAt`, `ResolveActiveIndexDbs`, `LoadSettings` - verify them in HoverForm/DbResolver/Settings if the compiler complains; do NOT guess.)

- [ ] **Step 5: Commit.**

```bash
git add src/delphi-plugin/DragLint.Plugin.SearchForm.pas src/delphi-plugin/dclDragLintWizard.dpk src/delphi-plugin/dclDragLintWizard.dproj
git commit -m "feat(plugin): unified Search embed (Kind dropdown + grid + jump)"
```

---

### Task 4: Wire the Search tab into the dock panel

**Files:**
- Modify: `src\delphi-plugin\DragLint.Plugin.DockForm.pas`

**Interfaces:**
- Consumes: `CreateEmbeddedSearch` (SearchForm).

- [ ] **Step 1: Add the field + tab + embed.** In `TDragLintDockFrame` private fields (near `FTabSearch: TTabSheet;`, ~line 70) add `FTabUnifiedSearch: TTabSheet;`. In the constructor where tabs are created (~line 208-210, after `FTabStruct:= AddTab('Structure');`) insert as the second tab:

```pascal
  FTabUnifiedSearch:= AddTab('Search (no grep)');
```

In `HandleInitTimer` (after the `CreateEmbeddedStructure` try-block, before the existing `CreateEmbeddedUsages` block) add:

```pascal
  try
    CreateEmbeddedSearch(Self, FTabUnifiedSearch);
  except
    on E: Exception do AddPlaceholder(FTabUnifiedSearch, 'Search failed to load: ' + E.Message);
  end;
```

Add `DragLint.Plugin.SearchForm` to the implementation `uses` (next to `DragLint.Plugin.SymbolSearchForm`).

- [ ] **Step 2: Normalize CRLF** on `DragLint.Plugin.DockForm.pas`.

- [ ] **Step 3: Build the BPL** (Debug/Win32). Expected: `BUILD_EXITCODE=0`, no `[dcc] Error`.

- [ ] **Step 4: Commit.**

```bash
git add src/delphi-plugin/DragLint.Plugin.DockForm.pas
git commit -m "feat(plugin): add Search tab to the dockable panel"
```

---

### Task 5: Remove the Find Usages debug dump (clean empty state)

**Files:**
- Modify: `src\delphi-plugin\DragLint.Plugin.UsagesForm.pas` (`RunQuery`, ~654-705)

**Interfaces:** none new.

- [ ] **Step 1: Replace the debug block.** In `TDragLintUsagesForm.RunQuery`, the `if FTree.Items.Count = 0 then begin ... end;` block currently builds `== DEBUG (v0.40.5) ==` and `== DEBUG: resolver state ==` nodes (the `var DbgRoot ... DiagRoot ...` section). Delete everything from `var DbgRoot:= AddNodeData(...)` through the end of the `DiagRoot.Expand(False); DbgRoot.Expand(False);` lines, keeping ONLY the honest scope hint that follows (the `var Hint: string; ... AddNodeData(nil, Hint, '', 0);` block). The kept code becomes the entire body of the `if FTree.Items.Count = 0` branch:

```pascal
    if FTree.Items.Count = 0 then
    begin
      var Hint: string;
      Hint:= '(no usages found)';
      if (Length(FSymbolName) > 1) and CharInSet(FSymbolName[1], ['A', 'a']) and CharInSet(FSymbolName[2], ['A'..'Z']) then
        Hint:= Hint + '  -  "' + FSymbolName + '" looks like a parameter (A-prefix); drag-lint does not index parameters or local variables.'
      else if (Length(FSymbolName) > 1) and CharInSet(FSymbolName[1], ['F', 'f']) and CharInSet(FSymbolName[2], ['A'..'Z']) then
        Hint:= Hint + '  -  "' + FSymbolName + '" looks like a private field; make sure the project DB is current (Tools > drag-lint > Lint Buffer).'
      else
        Hint:= Hint + '  -  if "' + FSymbolName + '" is a parameter or local variable, that is expected - drag-lint indexes types, methods, fields and constants only.';
      AddNodeData(nil, Hint, '', 0);
    end;
```

This removes the command line / stdout / FDbPaths / resolver-state dumps; the `ResolverDiagnostic`/`DragLint.Plugin.Settings` import may now be unused - if the compiler warns, drop the now-unused unit from `uses`.

- [ ] **Step 2: Normalize CRLF** on `DragLint.Plugin.UsagesForm.pas`.

- [ ] **Step 3: Build the BPL** (Debug/Win32). Expected: `BUILD_EXITCODE=0`, no `[dcc] Error`.

- [ ] **Step 4: Commit.**

```bash
git add src/delphi-plugin/DragLint.Plugin.UsagesForm.pas
git commit -m "fix(plugin): replace Find Usages debug dump with a clean no-results hint"
```

---

### Task 6: Manual test checklist + changelog

**Files:**
- Modify: `docs\TEST-CHECKLIST.md`
- Modify: `CHANGELOG.md`

- [ ] **Step 1: Append an IDE checklist** to `docs\TEST-CHECKLIST.md` under the docking section:

```
[ ] S1. Tools > drag-lint dockable panel -> a "Search (no grep)" tab appears (2nd, after Structure).
[ ] S2. Kind=Symbol, type a known type/method name -> grid lists Kind|Name|Location; double-click jumps to the .pas at the right line.
[ ] S3. Kind=Text, type a known message/caption phrase -> grid lists Source|Text|Location; double-click jumps. Toggle Advanced -> Substring/Any-word + Source filter appear and change results.
[ ] S4. Kind=Usages, type a known symbol -> grid lists Category|Detail|Location (Decl/Read/Write/Call...); double-click jumps. Advanced -> Width changes the snippet width.
[ ] S5. Search something not indexed (a local variable) -> a single clean "No matches ... drag-lint indexes ..." status line. NO JSON, NO == DEBUG == anywhere.
[ ] S6. Find Usages tab on a not-found symbol -> a single "(no usages found)" hint line, NO == DEBUG == block.
```

- [ ] **Step 2: Add a CHANGELOG note** under the current top (unreleased/next alpha):

```
- IDE plugin: new unified **Search (no grep)** dock tab - one Kind dropdown (Symbol/Text/Usages) + query field + a clickable results grid that jumps to source; Advanced toggle exposes per-kind refinements (kind filter / text mode+source / usages width). Find Usages no longer shows a debug dump on no-results.
```

- [ ] **Step 3: Commit.**

```bash
git add docs/TEST-CHECKLIST.md CHANGELOG.md
git commit -m "docs(plugin): Search-tab manual checklist + changelog"
```

---

## Self-Review

- **Spec coverage:** Layout (Task 3 control creation). Kind->command mapping (Task 3 RunSearch). Flat grid + Category (Task 3 Fill/RebuildColumns). Pure parsers + kind filter (Task 2). Navigation/OpenSourceAt (Task 3 ListActivate). Empty-state hints + no-JSON invariant (Task 3 SetEmpty branches; manual S5). Find Usages debug removal (Task 5). Shared ProcRun (Task 1). Testable SearchParse (Task 2 console test). dpk/dproj wiring (Tasks 1-3). Manual checklist (Task 6). All covered.
- **Placeholder scan:** no TBD/TODO; every code step shows real code. The two open choices from brainstorming are resolved in the plan (Search tab = 2nd position; debounce = Symbol only).
- **Type consistency:** `RunCaptureStdout` signature identical across ProcRun/UsagesForm/SymbolSearchForm/SearchForm. `TSearchRow` fields (Category/ColA/ColB/FilePath/Line) used identically in SearchParse, its test, and SearchForm.Fill. `KindMatchesFilter(AKind, AFilter)` argument order matches between SearchParse and SearchForm.
- **Risk:** `OpenSourceAt`, `ResolveActiveIndexDbs`, `LoadSettings`, `AddPlaceholder` signatures are assumed from existing call sites; Task 3/4 builds will surface any mismatch (the note says verify, don't guess). Building a design-time BPL headlessly must have no IDE holding the BPL.
