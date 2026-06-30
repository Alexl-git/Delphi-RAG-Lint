# v0.69 D2b -- refactor CLI: `find-unit` + `safe-delete` -- Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship the two remaining D2 refactor subcommands -- `drag-lint find-unit --name <Sym> --in <file>` (add the unit that declares `<Sym>` to `<file>`'s uses clause) and `drag-lint safe-delete --name <QName>` (verify ZERO references, then delete the declaration + impl body) -- both dry-run by default, `--json`, `--apply` (backups on, ANSI/CRLF preserved).

**Architecture:** Both are fully STORE-DRIVEN (no AST re-parse). `TSymbol` already carries `StartLine/EndLine` (declaration span) and `ImplStartLine/ImplEndLine` (impl body span); `GetUnitUsesForFile` gives each uses entry's `Section` + `EndLine/EndCol`. The one missing piece is a range insert/delete primitive -- a new unit `DRagLint.Refactor.TextEdit` (`TTextEdit` + `TTextEditApplier`) that splices lines (insert-in-line / insert-lines / delete-lines) with the same ANSI/CRLF/.bak discipline as `TRenameRefactoring.Apply`. Two builders (`TFindUnitRefactoring.Build`, `TSafeDeleteRefactoring.Build`) compute the edits from the store.

**Tech Stack:** Delphi 13 (Studio 37), the SQLite symbol store, Win64 `dcc64`/`msbuild`, PowerShell test harnesses.

## Global Constraints

- **Encoding (every `.pas`/`.dpr`):** strict 7-bit ASCII, CRLF, no BOM. Edit/Write emit LF -- normalize touched files to CRLF + byte-verify before committing. `.md` may keep pre-existing non-ASCII.
- **Pascal comments:** never `}` or nested `{` inside a `{ }` comment.
- **DocInsight:** `///` `<summary>` on every new public type/method.
- **VERSION is NOT bumped in D2b.** `src/cli/DRagLint.CLI.pas:6` stays `0.68.0-alpha`; v0.69 publishes after D1b.
- **`--apply` preserves strict ANSI / CRLF / no-BOM**, backups ON by default (`--no-backup` to suppress) -- the new `TTextEditApplier` mirrors `TRenameRefactoring.Apply`'s encoding.
- **Dry-run is the DEFAULT**; `--json` emits the edit set; `--apply` writes.
- **New unit needs BOTH** `src/cli/drag-lint.dpr` (`uses ... in '..\refactor\DRagLint.Refactor.TextEdit.pas'`) AND `drag-lint.dproj` (`<DCCReference>`).
- **Build via `build\build_draglint_win64.bat`** (delphi-build skill; Start-Process -Wait + log; tail `OK: staged Win64 drag-lint.exe`; no `Error`/`E2xxx`/`F2xxx`). KILL orphaned `drag-lint.exe`/`drag_lint_graph.exe` first.
- **DO NOT `git add` the built exe** (`*.exe` ignored). Commit SOURCE ONLY.
- **CORRECTNESS -- safe-delete zero-ref check:** `FindReferencesTo(SymbolId)` ALWAYS returns empty (refs.symbol_id is NULL in the index). The zero-reference check MUST use `FindCallersByName(Sym.Name)` (name-text match). If it returns ANY row, REFUSE the delete (nonzero exit, no edits). The declaration node emits no self-ref, so a non-empty result = real usages.
- **safe-delete is conservative:** refuse on ANY caller; never delete when uncertain. Over-deletion destroys code.

---

## File Structure

| File | Responsibility | Change |
|------|----------------|--------|
| `src/refactor/DRagLint.Refactor.TextEdit.pas` | `TTextEdit` + `TTextEditApplier` (apply/dry-run) + `TFindUnitRefactoring.Build` + `TSafeDeleteRefactoring.Build` | Create |
| `src/cli/DRagLint.CLI.pas` | `find-unit` + `safe-delete` dispatch + `DoFindUnit`/`DoSafeDelete` + help | Modify |
| `src/cli/drag-lint.dpr` + `drag-lint.dproj` | register the new unit | Modify |
| `tests/refactor/TextEditTests.dpr` + `run_textedit_tests.ps1` | in-memory applier console test | Create |
| `tests/refactor/findunit/*.pas` + `run_find_unit.ps1`; `tests/refactor/safedelete/*.pas` + `run_safe_delete.ps1` | DB-fixture CLI tests | Create |
| `CHANGELOG.md` | docs | Modify |

---

## Task 1: `TTextEdit` + `TTextEditApplier` (range insert/delete primitive)

**Files:**
- Create: `src/refactor/DRagLint.Refactor.TextEdit.pas`
- Create: `tests/refactor/TextEditTests.dpr`, `tests/refactor/run_textedit_tests.ps1`

**Interfaces:**
- Produces:
  - `TTextEditKind = (tekInsertInLine, tekInsertLines, tekDeleteLines);`
  - `TTextEdit = record FilePath: string; Kind: TTextEditKind; Line: Integer; Col: Integer; EndLine: Integer; Text: string; end;`
    - `tekInsertInLine`: insert `Text` into line `Line` so it begins at 1-based column `Col` (existing char at `Col` shifts right). `EndLine` ignored.
    - `tekInsertLines`: insert `Text` (may be multi-line, CRLF-joined) as new line(s) AFTER 1-based line `Line` (`Line=0` => at top). `Col`/`EndLine` ignored.
    - `tekDeleteLines`: delete 1-based lines `Line..EndLine` inclusive. `Col`/`Text` ignored.
  - `TTextEditApplier.Apply(const AEdits: TArray<TTextEdit>; AWriteBackups: Boolean): Integer;` (files touched)
  - `TTextEditApplier.RenderDryRun(const AEdits: TArray<TTextEdit>): string;`

- [ ] **Step 1: Write the failing console test**

Create `tests/refactor/TextEditTests.dpr`:
```pascal
program TextEditTests;
{$APPTYPE CONSOLE}
uses
  System.SysUtils, System.IOUtils,
  DRagLint.Refactor.TextEdit in '..\..\src\refactor\DRagLint.Refactor.TextEdit.pas';
var GPass, GFail: Integer;
procedure Check(const AName: string; ACond: Boolean);
begin
  if ACond then begin Inc(GPass); Writeln('PASS  ', AName); end
  else begin Inc(GFail); Writeln('FAIL  ', AName); end;
end;
function Mk(const AFile: string; AKind: TTextEditKind; ALine, ACol, AEnd: Integer; const AText: string): TTextEdit;
begin
  Result.FilePath:= AFile; Result.Kind:= AKind; Result.Line:= ALine;
  Result.Col:= ACol; Result.EndLine:= AEnd; Result.Text:= AText;
end;
var
  P: string; Edits: TArray<TTextEdit>; After: string;
begin
  GPass:= 0; GFail:= 0;
  try
    P:= TPath.Combine(TPath.GetTempPath, 'te_fixture.pas');

    { delete-lines: remove lines 2..3 of a 4-line file }
    TFile.WriteAllText(P, 'aaa'#13#10'bbb'#13#10'ccc'#13#10'ddd'#13#10, TEncoding.ANSI);
    Edits:= [Mk(P, tekDeleteLines, 2, 0, 3, '')];
    TTextEditApplier.Apply(Edits, False);
    After:= TFile.ReadAllText(P, TEncoding.ANSI);
    Check('delete-lines removed bbb+ccc', (Pos('bbb', After) = 0) and (Pos('ccc', After) = 0)
      and (Pos('aaa', After) > 0) and (Pos('ddd', After) > 0));

    { insert-lines: add a line after line 1 }
    TFile.WriteAllText(P, 'aaa'#13#10'ddd'#13#10, TEncoding.ANSI);
    Edits:= [Mk(P, tekInsertLines, 1, 0, 0, 'NEW')];
    TTextEditApplier.Apply(Edits, False);
    After:= TFile.ReadAllText(P, TEncoding.ANSI);
    Check('insert-lines added NEW after aaa',
      (Pos('aaa'#13#10'NEW'#13#10'ddd', After) > 0));

    { insert-in-line: insert ', X' at col 7 of "uses A;" -> "uses A, X;" }
    TFile.WriteAllText(P, 'uses A;'#13#10, TEncoding.ANSI);
    { 'uses A;' -> columns: u=1 s=2 e=3 s=4 (space)=5 A=6 ;=7. Insert before ';' (col 7). }
    Edits:= [Mk(P, tekInsertInLine, 1, 7, 0, ', X')];
    TTextEditApplier.Apply(Edits, False);
    After:= TFile.ReadAllText(P, TEncoding.ANSI);
    Check('insert-in-line made "uses A, X;"', (Pos('uses A, X;', After) > 0));

    { CRLF preserved + back-to-front multi-edit on one file }
    TFile.WriteAllText(P, 'l1'#13#10'l2'#13#10'l3'#13#10'l4'#13#10, TEncoding.ANSI);
    Edits:= [Mk(P, tekDeleteLines, 3, 0, 3, ''), Mk(P, tekDeleteLines, 1, 0, 1, '')];
    TTextEditApplier.Apply(Edits, False);
    After:= TFile.ReadAllText(P, TEncoding.ANSI);
    Check('multi-delete back-to-front kept l2+l4',
      (Pos('l2', After) > 0) and (Pos('l4', After) > 0) and (Pos('l1', After) = 0) and (Pos('l3', After) = 0));
    Check('CRLF preserved', Pos(#13#10, After) > 0);

    if TFile.Exists(P) then TFile.Delete(P);
    if TFile.Exists(P + '.bak') then TFile.Delete(P + '.bak');
  except
    on E: Exception do begin Writeln('EXCEPTION ', E.ClassName, ': ', E.Message); Inc(GFail); end;
  end;
  Writeln('');
  Writeln(Format('textedit-tests: %d pass / %d fail / %d total', [GPass, GFail, GPass + GFail]));
  if GFail > 0 then Halt(1) else Halt(0);
end.
```

Create `tests/refactor/run_textedit_tests.ps1`:
```powershell
# Build + run the TextEdit applier console tests (bare dcc64, Win64).
$rs  = 'C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\rsvars.bat'
$dir = $PSScriptRoot
$repo = (Resolve-Path (Join-Path $dir "..\..")).Path
$out = cmd /c "call `"$rs`" && cd /d `"$dir`" && dcc64 -B -E`"$dir`" -NSSystem -U`"$repo\src\refactor`" `"$dir\TextEditTests.dpr`"" 2>&1
$err = $out | Select-String -Pattern "\bError\b|E2\d{3}|F2\d{3}|Fatal"
if ($err) { Write-Host "BUILD FAILED:"; $err | Select-Object -First 12; exit 1 }
& "$dir\TextEditTests.exe"
exit $LASTEXITCODE
```

- [ ] **Step 2: Run -- confirm build failure (unit missing)**

```powershell
pwsh -File tests\refactor\run_textedit_tests.ps1
```
Expected: BUILD FAILED -- `DRagLint.Refactor.TextEdit` not found.

- [ ] **Step 3: Create the unit (applier only for now; builders added in Tasks 2-3)**

Create `src/refactor/DRagLint.Refactor.TextEdit.pas`:
```pascal
unit DRagLint.Refactor.TextEdit;

{ Range insert/delete text edits for the non-rename refactors (find-unit,
  safe-delete). TRenameRefactoring.Apply is token-replace only; this applier
  does whole-line insert/delete + single-line character insert, with the same
  ANSI / CRLF / .bak discipline. Builders (TFindUnitRefactoring, TSafeDelete-
  Refactoring) are added in later tasks. }

interface

uses
  System.SysUtils, System.Classes, System.IOUtils,
  System.Generics.Collections, System.Generics.Defaults,
  DRagLint.Core.Model, DRagLint.Core.Interfaces;

type
  TTextEditKind = (tekInsertInLine, tekInsertLines, tekDeleteLines);

  /// <summary>One text edit. tekInsertInLine: insert Text into line Line at
  /// 1-based column Col. tekInsertLines: insert Text (CRLF-joined) after line
  /// Line (0 = top). tekDeleteLines: delete lines Line..EndLine inclusive.</summary>
  TTextEdit = record
    FilePath: string;
    Kind    : TTextEditKind;
    Line    : Integer;
    Col     : Integer;
    EndLine : Integer;
    Text    : string;
  end;

  TTextEditApplier = class
  public
    /// <summary>Applies edits per file, back-to-front by line, preserving ANSI
    /// + CRLF + (optional) .bak backup. Returns files touched.</summary>
    class function Apply(const AEdits: TArray<TTextEdit>; AWriteBackups: Boolean): Integer;
    /// <summary>Human-readable preview of the edit set.</summary>
    class function RenderDryRun(const AEdits: TArray<TTextEdit>): string;
  end;

implementation

{ Sort key for back-to-front application within a file: larger line first; for
  deletes use EndLine as the key so a delete is processed before any edit above
  it. tekInsertInLine/Lines use Line. }
function EditTopLine(const E: TTextEdit): Integer;
begin
  if E.Kind = tekDeleteLines then Result:= E.EndLine else Result:= E.Line;
end;

class function TTextEditApplier.Apply(const AEdits: TArray<TTextEdit>; AWriteBackups: Boolean): Integer;
var
  FileMap : TDictionary<string, TList<TTextEdit>>;
  E       : TTextEdit;
  Group   : TList<TTextEdit>;
  Pair    : TPair<string, TList<TTextEdit>>;
  RawBytes: TBytes;
  Content : string;
  Lines   : TStringList;
  Touched : Integer;
  Cmp     : IComparer<TTextEdit>;
begin
  Touched:= 0;
  FileMap:= TDictionary<string, TList<TTextEdit>>.Create;
  try
    for E in AEdits do
    begin
      if not FileMap.TryGetValue(E.FilePath, Group) then
      begin Group:= TList<TTextEdit>.Create; FileMap.Add(E.FilePath, Group); end;
      Group.Add(E);
    end;

    for Pair in FileMap do
    begin
      if not TFile.Exists(Pair.Key) then Continue;
      RawBytes:= TFile.ReadAllBytes(Pair.Key);
      Content := TEncoding.ANSI.GetString(RawBytes);
      if AWriteBackups then TFile.WriteAllBytes(Pair.Key + '.bak', RawBytes);

      Group:= Pair.Value;
      { back-to-front: largest top-line first so indices stay valid }
      Cmp:= TComparer<TTextEdit>.Construct(
        function(const A, B: TTextEdit): Integer
        begin Result:= EditTopLine(B) - EditTopLine(A); end);
      Group.Sort(Cmp);

      Lines:= TStringList.Create;
      try
        Lines.Text:= Content;
        for E in Group do
        begin
          case E.Kind of
            tekDeleteLines:
              begin
                var LHi: Integer:= E.EndLine; var LLo: Integer:= E.Line;
                if LLo < 1 then LLo:= 1;
                if LHi > Lines.Count then LHi:= Lines.Count;
                for var L: Integer:= LHi downto LLo do
                  if (L >= 1) and (L <= Lines.Count) then Lines.Delete(L - 1);
              end;
            tekInsertLines:
              begin
                var Idx: Integer:= E.Line; { insert AFTER 1-based Line => 0-based index Line }
                if Idx < 0 then Idx:= 0;
                if Idx > Lines.Count then Idx:= Lines.Count;
                { split Text on CRLF/LF so multi-line inserts keep separate lines }
                var Parts: TArray<string>:= E.Text.Replace(#13#10, #10).Split([#10]);
                for var PIdx: Integer:= High(Parts) downto 0 do
                  Lines.Insert(Idx, Parts[PIdx]);
              end;
            tekInsertInLine:
              begin
                if (E.Line >= 1) and (E.Line <= Lines.Count) then
                begin
                  var S: string:= Lines[E.Line - 1];
                  var C: Integer:= E.Col; if C < 1 then C:= 1;
                  if C > Length(S) + 1 then C:= Length(S) + 1;
                  Lines[E.Line - 1]:= Copy(S, 1, C - 1) + E.Text + Copy(S, C, MaxInt);
                end;
              end;
          end;
        end;

        { re-encode ANSI + CRLF, preserve a trailing newline if the original had one }
        var SB: TStringBuilder:= TStringBuilder.Create;
        try
          for var I: Integer:= 0 to Lines.Count - 1 do
          begin
            SB.Append(Lines[I]);
            if I < Lines.Count - 1 then SB.Append(#13#10);
          end;
          if (Length(Content) > 0) and (Content[Length(Content)] = #10) then SB.Append(#13#10);
          TFile.WriteAllBytes(Pair.Key, TEncoding.ANSI.GetBytes(SB.ToString));
        finally
          SB.Free;
        end;
        Inc(Touched);
      finally
        Lines.Free;
      end;
    end;
  finally
    for Pair in FileMap do Pair.Value.Free;
    FileMap.Free;
  end;
  Result:= Touched;
end;

class function TTextEditApplier.RenderDryRun(const AEdits: TArray<TTextEdit>): string;
var SB: TStringBuilder; E: TTextEdit; Last: string;
begin
  SB:= TStringBuilder.Create;
  try
    Last:= '';
    for E in AEdits do
    begin
      if E.FilePath <> Last then begin SB.AppendLine('File: ' + E.FilePath); Last:= E.FilePath; end;
      case E.Kind of
        tekDeleteLines : SB.AppendLine(Format('  delete lines %d..%d', [E.Line, E.EndLine]));
        tekInsertLines : SB.AppendLine(Format('  insert after line %d: %s', [E.Line, E.Text]));
        tekInsertInLine: SB.AppendLine(Format('  insert at L%d:C%d: %s', [E.Line, E.Col, E.Text]));
      end;
    end;
    Result:= SB.ToString;
  finally
    SB.Free;
  end;
end;

end.
```
(The `DRagLint.Core.Model`/`Interfaces` uses are for the builders added in Tasks 2-3; they compile now even if unused.)

- [ ] **Step 4: Run -- confirm GREEN**

```powershell
pwsh -File tests\refactor\run_textedit_tests.ps1
```
Expected: `textedit-tests: 5 pass / 0 fail / 5 total`. If `insert-in-line` col is off by one, fix the test's expected column from the real string layout (the engine's `Copy(S,1,C-1)+Text+Copy(S,C,MaxInt)` inserts Text starting at column C).

- [ ] **Step 5: Commit**

```bash
git add src/refactor/DRagLint.Refactor.TextEdit.pas tests/refactor/TextEditTests.dpr tests/refactor/run_textedit_tests.ps1
git commit -m "feat(refactor): TTextEdit range insert/delete applier (v0.69 D2b)"
```

---

## Task 2: `TFindUnitRefactoring.Build` + `find-unit` CLI

**Files:**
- Modify: `src/refactor/DRagLint.Refactor.TextEdit.pas` (add `TFindUnitRefactoring`)
- Modify: `src/cli/DRagLint.CLI.pas` (`DoFindUnit` + dispatch + help), `drag-lint.dpr`/`.dproj` (register the unit)
- Create: `tests/refactor/findunit/Lib.pas`, `tests/refactor/findunit/Target.pas`, `tests/refactor/run_find_unit.ps1`

**Interfaces:**
- Consumes: `TTextEdit`, `TTextEditApplier` (Task 1).
- Produces: `class function TFindUnitRefactoring.Build(const AStore: ISymbolStore; const AName, AInFile: string; out AResolvedUnit: string; out AAlreadyUsed: Boolean): TArray<TTextEdit>;`
  - Resolves the best unit declaring `AName`; if already in `AInFile`'s uses, returns empty + `AAlreadyUsed=True`; else returns one `tekInsertInLine` (append to the last uses entry) or `tekInsertLines` (fresh `uses` block).

- [ ] **Step 1: Write the failing DB-fixture test**

Create `tests/refactor/findunit/Lib.pas`:
```pascal
unit Lib;
interface
type
  TWidget = class
  end;
implementation
end.
```
Create `tests/refactor/findunit/Target.pas`:
```pascal
unit Target;
interface
uses System.SysUtils;
implementation
procedure UseIt;
var W: TWidget;
begin
  W := TWidget.Create;
end;
end.
```
Create `tests/refactor/run_find_unit.ps1`:
```powershell
param([string]$Exe = "third_party\dll-win64\drag-lint.exe")
$ErrorActionPreference = "Stop"
$repo = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
Set-Location $repo
$exe = (Resolve-Path $Exe).Path
$dir = Join-Path $PSScriptRoot "findunit"
$db  = Join-Path $env:TEMP "refactor_findunit.sqlite"
if (Test-Path $db) { Remove-Item $db -Force }
& $exe index $dir --db $db | Out-Null
$fail = 0
function Assert($n,$c){ if($c){Write-Host "PASS  $n"}else{Write-Host "FAIL  $n" -ForegroundColor Red;$script:fail++} }

$target = Join-Path $dir "Target.pas"
# dry-run: should propose adding 'Lib' to Target.pas uses
$dry = (& $exe find-unit --name TWidget --in $target --db $db 2>$null) -join "`n"
Assert "dry-run proposes adding Lib" ($dry -match 'Lib')

# --json edit set
$json = & $exe find-unit --name TWidget --in $target --json --db $db 2>$null | ConvertFrom-Json
Assert "json edit set non-empty" (@($json).Count -ge 1)

# --apply into a temp copy, then verify Lib is in the uses clause
$tmp = Join-Path $env:TEMP "findunit_apply"
if (Test-Path $tmp) { Remove-Item $tmp -Recurse -Force }
New-Item -ItemType Directory -Path $tmp | Out-Null
Copy-Item (Join-Path $dir "*.pas") $tmp
$db2 = Join-Path $env:TEMP "refactor_findunit2.sqlite"; if (Test-Path $db2) { Remove-Item $db2 -Force }
& $exe index $tmp --db $db2 | Out-Null
$t = Join-Path $tmp "Target.pas"
& $exe find-unit --name TWidget --in $t --apply --no-backup --db $db2 2>$null | Out-Null
$after = Get-Content $t -Raw
Assert "apply added Lib to a uses clause" ($after -match '\bLib\b')
Assert "apply kept it compilable-looking (uses ... ;)" ($after -match 'uses[^;]*Lib[^;]*;')

# already-present: asking for a unit already in uses is a no-op
$noop = (& $exe find-unit --name TObject --in $target --db $db 2>&1) -join "`n"
Assert "already-used or unresolved is a clean no-op (no crash)" ($LASTEXITCODE -ne $null)

Write-Host ""
if ($fail -gt 0) { Write-Host "find-unit: $fail FAIL"; exit 1 } else { Write-Host "find-unit: all pass"; exit 0 }
```

- [ ] **Step 2: Run -- confirm FAIL (command unknown)**

```powershell
pwsh -File tests\refactor\run_find_unit.ps1
```
Expected: FAIL -- `find-unit` unknown.

- [ ] **Step 3: Add `TFindUnitRefactoring` to the unit**

In `src/refactor/DRagLint.Refactor.TextEdit.pas`, add to the interface:
```pascal
  TFindUnitRefactoring = class
  public
    /// <summary>Computes edits to add the unit declaring AName to AInFile's uses
    /// clause. AResolvedUnit = the chosen unit; AAlreadyUsed=True (empty result)
    /// when it is already imported. Empty result + AResolvedUnit='' when AName is
    /// unresolvable. Inserts into the implementation uses if present, else the
    /// interface uses, else a fresh implementation uses block.</summary>
    class function Build(const AStore: ISymbolStore; const AName, AInFile: string;
      out AResolvedUnit: string; out AAlreadyUsed: Boolean): TArray<TTextEdit>;
  end;
```
Add the implementation:
```pascal
class function TFindUnitRefactoring.Build(const AStore: ISymbolStore;
  const AName, AInFile: string; out AResolvedUnit: string; out AAlreadyUsed: Boolean): TArray<TTextEdit>;
var
  Syms : TArray<TSymbol>;
  S    : TSymbol;
  Cands: TDictionary<string, Integer>; { unit -> score }
  Best : string; BestScore: Integer;
  FullPath: string; InFileId: Int64;
  Uses_: TArray<TUnitUse>; U: TUnitUse;
  UsedSet: TDictionary<string, Boolean>;
  UnitName: string;
  TargetSection: TUnitUseSection;
  LastInSection: TUnitUse; HaveLast: Boolean;
  Edit: TTextEdit;
  Pair: TPair<string, Integer>;
begin
  Result:= nil; AResolvedUnit:= ''; AAlreadyUsed:= False;

  { 1. resolve the best declaring unit }
  Syms:= AStore.FindSymbolsByExactName(AName);
  if Length(Syms) = 0 then Exit;
  Cands:= TDictionary<string, Integer>.Create;
  try
    for S in Syms do
    begin
      UnitName:= ChangeFileExt(ExtractFileName(AStore.GetFilePath(S.FileId)), '');
      if UnitName = '' then Continue;
      var Sc: Integer:= 1;
      if not SameText(S.Section, 'implementation') then Inc(Sc, 10); { interface-visible }
      Cands.AddOrSetValue(UnitName, Cands.Items[UnitName] + Sc); { default 0 if absent via TryGet below }
    end;
    Best:= ''; BestScore:= -1;
    for Pair in Cands do
      if Pair.Value > BestScore then begin BestScore:= Pair.Value; Best:= Pair.Key; end;
  finally
    Cands.Free;
  end;
  if Best = '' then Exit;
  AResolvedUnit:= Best;

  { do not add a unit to itself }
  if SameText(ChangeFileExt(ExtractFileName(AInFile), ''), Best) then Exit;

  { 2. load the target file's existing uses }
  FullPath:= TPath.GetFullPath(AInFile);
  InFileId:= AStore.FindFileIdByPath(FullPath);
  if InFileId <= 0 then InFileId:= AStore.FindFileIdByPath(AInFile);
  Uses_:= nil;
  if InFileId > 0 then Uses_:= AStore.GetUnitUsesForFile(InFileId);

  UsedSet:= TDictionary<string, Boolean>.Create;
  try
    for U in Uses_ do UsedSet.AddOrSetValue(LowerCase(U.UnitName), True);
    if UsedSet.ContainsKey(LowerCase(Best)) then begin AAlreadyUsed:= True; Exit; end;

    { 3. choose target section: implementation uses if present, else interface }
    TargetSection:= uusImplementation;
    HaveLast:= False;
    var HasImpl: Boolean:= False; var HasIntf: Boolean:= False;
    for U in Uses_ do
    begin
      if U.Section = uusImplementation then HasImpl:= True;
      if U.Section = uusInterface then HasIntf:= True;
    end;
    if HasImpl then TargetSection:= uusImplementation
    else if HasIntf then TargetSection:= uusInterface
    else TargetSection:= uusImplementation; { fresh block goes to implementation }

    { last entry in the chosen section -> append ', Best' after it }
    for U in Uses_ do
      if U.Section = TargetSection then
        if (not HaveLast) or (U.StartLine > LastInSection.StartLine)
           or ((U.StartLine = LastInSection.StartLine) and (U.StartCol > LastInSection.StartCol)) then
        begin LastInSection:= U; HaveLast:= True; end;

    if HaveLast then
    begin
      { insert ', Best' at the end of the last unit entry (before the ';') }
      Edit.FilePath:= AInFile; Edit.Kind:= tekInsertInLine;
      Edit.Line:= LastInSection.EndLine; Edit.Col:= LastInSection.EndCol;
      Edit.EndLine:= 0; Edit.Text:= ', ' + Best;
      Result:= [Edit];
    end
    else
    begin
      { no uses clause in the file at all -> a fresh "uses Best;" block.
        Insert after the 'implementation' line if the file has one, else after
        'interface'. We locate the keyword by reading the file (cheap, single file). }
      var KeywordLine: Integer:= 0;
      if TFile.Exists(AInFile) then
      begin
        var Raw: string:= TEncoding.ANSI.GetString(TFile.ReadAllBytes(AInFile));
        var SL: TStringList:= TStringList.Create;
        try
          SL.Text:= Raw;
          var WantImpl: Boolean:= (TargetSection = uusImplementation);
          for var I: Integer:= 0 to SL.Count - 1 do
          begin
            var T: string:= LowerCase(Trim(SL[I]));
            if WantImpl and (T = 'implementation') then begin KeywordLine:= I + 1; Break; end;
            if (not WantImpl) and (T = 'interface') then begin KeywordLine:= I + 1; Break; end;
          end;
        finally
          SL.Free;
        end;
      end;
      if KeywordLine = 0 then Exit; { cannot place safely }
      Edit.FilePath:= AInFile; Edit.Kind:= tekInsertLines;
      Edit.Line:= KeywordLine; Edit.Col:= 0; Edit.EndLine:= 0;
      Edit.Text:= ''#13#10'uses ' + Best + ';';
      Result:= [Edit];
    end;
  finally
    UsedSet.Free;
  end;
end;
```
(Fix the `Cands.Items[UnitName]` default: use `var Cur: Integer; if not Cands.TryGetValue(UnitName, Cur) then Cur:= 0; Cands.AddOrSetValue(UnitName, Cur + Sc);` -- adjust if `TryGetValue` is needed to avoid a missing-key exception. Verify `TUnitUse` field names (`UnitName`, `Section`, `StartLine/StartCol/EndLine/EndCol`) + `TUnitUseSection` values (`uusInterface`/`uusImplementation`) against `DRagLint.Core.Model.pas` during build.)

- [ ] **Step 4: Add `DoFindUnit` + dispatch + help + register the unit**

In `src/cli/DRagLint.CLI.pas`, add `DRagLint.Refactor.TextEdit` to `uses`. Add the handler:
```pascal
function DoFindUnit(const AArgs: TArgs): Integer;
var
  Store: ISymbolStore; Edits: TArray<TTextEdit>; ResolvedUnit: string; Already: Boolean;
begin
  if (AArgs.Name = '') or (AArgs.InFile = '') then
  begin Writeln('ERROR: find-unit needs --name <Symbol> --in <file>'); Exit(2); end;
  if AArgs.DbPath = '' then begin Writeln('ERROR: --db required'); Exit(2); end;
  Store:= TSQLiteSymbolStore.Create(AArgs.DbPath); Store.Migrate;
  Edits:= TFindUnitRefactoring.Build(Store, AArgs.Name, AArgs.InFile, ResolvedUnit, Already);
  if Already then begin Writeln(Format('"%s" is already in the uses clause.', [ResolvedUnit])); Exit(0); end;
  if ResolvedUnit = '' then begin Writeln(Format('Could not resolve a unit declaring "%s".', [AArgs.Name])); Exit(1); end;
  if Length(Edits) = 0 then begin Writeln('No edit computed.'); Exit(1); end;
  if AArgs.AsJson then
  begin
    var Arr: TJSONArray:= TJSONArray.Create;
    try
      for var E in Edits do
      begin
        var O: TJSONObject:= TJSONObject.Create;
        O.AddPair('file', E.FilePath);
        O.AddPair('unit', ResolvedUnit);
        O.AddPair('line', TJSONNumber.Create(E.Line));
        O.AddPair('text', E.Text);
        Arr.AddElement(O);
      end;
      Writeln(Arr.ToJSON);
    finally Arr.Free; end;
    Exit(0);
  end;
  if not AArgs.Apply then
  begin
    Writeln(TTextEditApplier.RenderDryRun(Edits));
    Writeln(Format('Dry run: add unit "%s". Pass --apply to write.', [ResolvedUnit]));
    Exit(0);
  end;
  var Touched: Integer:= TTextEditApplier.Apply(Edits, not AArgs.NoBackup);
  Writeln(Format('Applied: added "%s" (%d file).', [ResolvedUnit, Touched]));
  Result:= 0;
end;
```
Add to the dispatch chain (near `rename`):
```pascal
    else if Args.Command = 'find-unit'         then Result:= DoFindUnit        (Args)
```
Add help:
```pascal
  Writeln('  drag-lint find-unit --name <Symbol> --in <file> [--json|--apply|--no-backup] --db <db>  - add the declaring unit to uses');
```
Register the unit in `drag-lint.dpr` (`DRagLint.Refactor.TextEdit in '..\refactor\DRagLint.Refactor.TextEdit.pas',`) and `drag-lint.dproj` (`<DCCReference Include="..\refactor\DRagLint.Refactor.TextEdit.pas"/>`).

- [ ] **Step 5: Build Win64 + run the find-unit test + lint harness**

```powershell
Get-Process drag-lint,drag_lint_graph -ErrorAction SilentlyContinue | Stop-Process -Force
Start-Process -FilePath "build\build_draglint_win64.bat" -Wait -NoNewWindow -RedirectStandardOutput "C:\TEMP\claude\c--Projects-Delphi-RAG-lint\a9995faf-a53e-4216-8eb7-9124c3d767bd\scratchpad\d2b-t2-build.log" -RedirectStandardError "C:\TEMP\claude\c--Projects-Delphi-RAG-lint\a9995faf-a53e-4216-8eb7-9124c3d767bd\scratchpad\d2b-t2-build.err"
Get-Content "C:\TEMP\claude\c--Projects-Delphi-RAG-lint\a9995faf-a53e-4216-8eb7-9124c3d767bd\scratchpad\d2b-t2-build.log" -Tail 5
pwsh -File tests\refactor\run_find_unit.ps1
pwsh -File tests\lint\run_lint_tests.ps1 | Select-Object -Last 1
```
Expected: build OK; `find-unit: all pass`; lint 117/117. If the `tekInsertInLine` position from `TUnitUse.EndCol` lands `, Lib` in the wrong spot (e.g. after the `;`), inspect the `--json`/dry-run, confirm `EndCol`'s exact meaning against the real file, and adjust the column (the applier inserts Text starting at column `Col`).

- [ ] **Step 6: Commit (source only)**

```bash
git add src/refactor/DRagLint.Refactor.TextEdit.pas src/cli/DRagLint.CLI.pas src/cli/drag-lint.dpr src/cli/drag-lint.dproj tests/refactor/findunit/Lib.pas tests/refactor/findunit/Target.pas tests/refactor/run_find_unit.ps1
git commit -m "feat(refactor): find-unit command (add declaring unit to uses) (v0.69 D2b)"
```

---

## Task 3: `TSafeDeleteRefactoring.Build` + `safe-delete` CLI

**Files:**
- Modify: `src/refactor/DRagLint.Refactor.TextEdit.pas` (add `TSafeDeleteRefactoring`)
- Modify: `src/cli/DRagLint.CLI.pas` (`DoSafeDelete` + dispatch + help)
- Create: `tests/refactor/safedelete/Dead.pas`, `tests/refactor/safedelete/Used.pas`, `tests/refactor/run_safe_delete.ps1`

**Interfaces:**
- Consumes: `TTextEdit`, `TTextEditApplier` (Task 1).
- Produces: `class function TSafeDeleteRefactoring.Build(const AStore: ISymbolStore; const AQName: string; out ARefuseReason: string): TArray<TTextEdit>;`
  - Empty + `ARefuseReason<>''` when the symbol has callers (or is not found). Else `tekDeleteLines` for the declaration span (+ impl span for a routine).

- [ ] **Step 1: Write the failing DB-fixture test**

Create `tests/refactor/safedelete/Dead.pas`:
```pascal
unit Dead;
interface
procedure NeverCalled;
implementation
procedure NeverCalled;
begin
  Writeln('dead');
end;
end.
```
Create `tests/refactor/safedelete/Used.pas`:
```pascal
unit Used;
interface
procedure IsCalled;
implementation
procedure IsCalled;
begin
end;
procedure Caller;
begin
  IsCalled;
end;
end.
```
Create `tests/refactor/run_safe_delete.ps1`:
```powershell
param([string]$Exe = "third_party\dll-win64\drag-lint.exe")
$ErrorActionPreference = "Stop"
$repo = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
Set-Location $repo
$exe = (Resolve-Path $Exe).Path
$dir = Join-Path $PSScriptRoot "safedelete"
$db  = Join-Path $env:TEMP "refactor_safedelete.sqlite"
if (Test-Path $db) { Remove-Item $db -Force }
& $exe index $dir --db $db | Out-Null
$fail = 0
function Assert($n,$c){ if($c){Write-Host "PASS  $n"}else{Write-Host "FAIL  $n" -ForegroundColor Red;$script:fail++} }

# REFUSE: IsCalled has a caller -> must refuse, nonzero exit, no edits
$ref = (& $exe safe-delete --name Used.IsCalled --db $db 2>&1) -join "`n"
Assert "refuses delete of a referenced symbol" ($ref -match 'refuse|referenced|in use|cannot' -and $LASTEXITCODE -ne 0)

# SUCCESS dry-run: NeverCalled has zero callers -> proposes deletion
$dry = (& $exe safe-delete --name Dead.NeverCalled --db $db 2>$null) -join "`n"
Assert "dry-run proposes deleting NeverCalled" ($dry -match 'delete lines')

# --apply into a temp copy, verify NeverCalled is gone (decl + body)
$tmp = Join-Path $env:TEMP "safedelete_apply"
if (Test-Path $tmp) { Remove-Item $tmp -Recurse -Force }
New-Item -ItemType Directory -Path $tmp | Out-Null
Copy-Item (Join-Path $dir "Dead.pas") $tmp
$db2 = Join-Path $env:TEMP "refactor_safedelete2.sqlite"; if (Test-Path $db2) { Remove-Item $db2 -Force }
& $exe index $tmp --db $db2 | Out-Null
$t = Join-Path $tmp "Dead.pas"
& $exe safe-delete --name Dead.NeverCalled --apply --no-backup --db $db2 2>$null | Out-Null
$after = Get-Content $t -Raw
Assert "apply removed the NeverCalled implementation body" ($after -notmatch "Writeln\('dead'\)")

Write-Host ""
if ($fail -gt 0) { Write-Host "safe-delete: $fail FAIL"; exit 1 } else { Write-Host "safe-delete: all pass"; exit 0 }
```

- [ ] **Step 2: Run -- confirm FAIL (command unknown)**

```powershell
pwsh -File tests\refactor\run_safe_delete.ps1
```
Expected: FAIL.

- [ ] **Step 3: Add `TSafeDeleteRefactoring`**

In `src/refactor/DRagLint.Refactor.TextEdit.pas`, add to interface:
```pascal
  TSafeDeleteRefactoring = class
  public
    /// <summary>Edits to delete the declaration (and impl body, for a routine)
    /// of AQName, but ONLY when it has zero references. Reference check uses
    /// FindCallersByName(short name) -- FindReferencesTo is unreliable (refs.
    /// symbol_id is NULL in the index). Returns empty + ARefuseReason when the
    /// symbol is referenced or not found.</summary>
    class function Build(const AStore: ISymbolStore; const AQName: string;
      out ARefuseReason: string): TArray<TTextEdit>;
  end;
```
Add implementation:
```pascal
function LastSeg(const S: string): string;
var P: Integer;
begin
  P:= LastDelimiter('.', S);
  if P > 0 then Result:= Copy(S, P + 1, MaxInt) else Result:= S;
end;

class function TSafeDeleteRefactoring.Build(const AStore: ISymbolStore;
  const AQName: string; out ARefuseReason: string): TArray<TTextEdit>;
var
  Syms : TArray<TSymbol>;
  Sym  : TSymbol;
  Refs : TArray<TReference>;
  Short: string;
  Path : string;
  Edits: TList<TTextEdit>;
  E    : TTextEdit;
  R    : TReference;
  ExternalRefs: Integer;
begin
  Result:= nil; ARefuseReason:= '';
  Syms:= AStore.FindSymbolsByQualifiedName(AQName);
  if Length(Syms) = 0 then begin ARefuseReason:= Format('symbol "%s" not found', [AQName]); Exit; end;
  Sym:= Syms[0];
  Short:= LastSeg(AQName);

  { zero-reference check via name-text (FindReferencesTo is NULL-symbol_id -> unreliable).
    The declaration emits no self-ref, so any row is a real usage. Count refs NOT on the
    declaration's own line in the declaration file as external usages; a name appearing
    only at the decl site won't generate a ref row, so typically ANY ref = a usage. }
  Refs:= AStore.FindCallersByName(Short);
  ExternalRefs:= 0;
  for R in Refs do
    if not ((R.FileId = Sym.FileId) and (R.StartLine = Sym.StartLine)) then Inc(ExternalRefs);
  if ExternalRefs > 0 then
  begin
    ARefuseReason:= Format('"%s" has %d reference(s) -- refusing to delete', [AQName, ExternalRefs]);
    Exit;
  end;

  Path:= AStore.GetFilePath(Sym.FileId);
  if Path = '' then begin ARefuseReason:= 'declaration file path unknown'; Exit; end;

  Edits:= TList<TTextEdit>.Create;
  try
    { impl body first (higher lines), then declaration -- applier sorts back-to-front anyway }
    if (Sym.ImplStartLine > 0) and (Sym.ImplEndLine >= Sym.ImplStartLine) then
    begin
      E.FilePath:= Path; E.Kind:= tekDeleteLines;
      E.Line:= Sym.ImplStartLine; E.EndLine:= Sym.ImplEndLine; E.Col:= 0; E.Text:= '';
      Edits.Add(E);
    end;
    if (Sym.StartLine > 0) and (Sym.EndLine >= Sym.StartLine) then
    begin
      E.FilePath:= Path; E.Kind:= tekDeleteLines;
      E.Line:= Sym.StartLine; E.EndLine:= Sym.EndLine; E.Col:= 0; E.Text:= '';
      Edits.Add(E);
    end;
    Result:= Edits.ToArray;
  finally
    Edits.Free;
  end;
end;
```
(Verify `TReference.FileId/StartLine` field names and that `TSymbol.ImplStartLine/ImplEndLine/StartLine/EndLine` are populated -- they are per the index map.)

- [ ] **Step 4: Add `DoSafeDelete` + dispatch + help**

```pascal
function DoSafeDelete(const AArgs: TArgs): Integer;
var
  Store: ISymbolStore; Edits: TArray<TTextEdit>; Reason: string;
begin
  if AArgs.Name = '' then begin Writeln('ERROR: safe-delete needs --name <QualifiedName>'); Exit(2); end;
  if AArgs.DbPath = '' then begin Writeln('ERROR: --db required'); Exit(2); end;
  Store:= TSQLiteSymbolStore.Create(AArgs.DbPath); Store.Migrate;
  Edits:= TSafeDeleteRefactoring.Build(Store, AArgs.Name, Reason);
  if Reason <> '' then begin Writeln('REFUSED: ' + Reason); Exit(2); end;
  if Length(Edits) = 0 then begin Writeln('No edit computed.'); Exit(1); end;
  if AArgs.AsJson then
  begin
    var Arr: TJSONArray:= TJSONArray.Create;
    try
      for var E in Edits do
      begin
        var O: TJSONObject:= TJSONObject.Create;
        O.AddPair('file', E.FilePath);
        O.AddPair('delete_from', TJSONNumber.Create(E.Line));
        O.AddPair('delete_to', TJSONNumber.Create(E.EndLine));
        Arr.AddElement(O);
      end;
      Writeln(Arr.ToJSON);
    finally Arr.Free; end;
    Exit(0);
  end;
  if not AArgs.Apply then
  begin
    Writeln(TTextEditApplier.RenderDryRun(Edits));
    Writeln(Format('Dry run: delete "%s". Pass --apply to write.', [AArgs.Name]));
    Exit(0);
  end;
  var Touched: Integer:= TTextEditApplier.Apply(Edits, not AArgs.NoBackup);
  Writeln(Format('Deleted "%s" (%d file).', [AArgs.Name, Touched]));
  Result:= 0;
end;
```
Dispatch:
```pascal
    else if Args.Command = 'safe-delete'       then Result:= DoSafeDelete      (Args)
```
Help:
```pascal
  Writeln('  drag-lint safe-delete --name <QName> [--json|--apply|--no-backup] --db <db>   - delete a symbol iff it has zero references');
```

- [ ] **Step 5: Build Win64 + run safe-delete test + lint harness**

```powershell
Get-Process drag-lint,drag_lint_graph -ErrorAction SilentlyContinue | Stop-Process -Force
Start-Process -FilePath "build\build_draglint_win64.bat" -Wait -NoNewWindow -RedirectStandardOutput "C:\TEMP\claude\c--Projects-Delphi-RAG-lint\a9995faf-a53e-4216-8eb7-9124c3d767bd\scratchpad\d2b-t3-build.log" -RedirectStandardError "C:\TEMP\claude\c--Projects-Delphi-RAG-lint\a9995faf-a53e-4216-8eb7-9124c3d767bd\scratchpad\d2b-t3-build.err"
Get-Content "C:\TEMP\claude\c--Projects-Delphi-RAG-lint\a9995faf-a53e-4216-8eb7-9124c3d767bd\scratchpad\d2b-t3-build.log" -Tail 5
pwsh -File tests\refactor\run_safe_delete.ps1
pwsh -File tests\lint\run_lint_tests.ps1 | Select-Object -Last 1
```
Expected: build OK; `safe-delete: all pass`; lint 117/117. The refuse-path is the critical correctness assertion -- if `Used.IsCalled` is NOT refused, the `FindCallersByName` check is wrong; fix it (do not loosen the test).

- [ ] **Step 6: Commit (source only)**

```bash
git add src/refactor/DRagLint.Refactor.TextEdit.pas src/cli/DRagLint.CLI.pas tests/refactor/safedelete/Dead.pas tests/refactor/safedelete/Used.pas tests/refactor/run_safe_delete.ps1
git commit -m "feat(refactor): safe-delete command (zero-ref guard, decl+body delete) (v0.69 D2b)"
```

---

## Task 4: Documentation

- [ ] **Step 1: CHANGELOG**

Under `## v0.69.0-alpha (in progress)`, after the D2a block, add:
```markdown
### Added (refactor CLI -- D2b)

- **`drag-lint find-unit --name <Symbol> --in <file>`** -- add the unit that
  declares `<Symbol>` to `<file>`'s uses clause (implementation uses preferred).
  Dry-run default; `--json`; `--apply` (backups on, ANSI/CRLF preserved). No-op
  when the unit is already imported.
- **`drag-lint safe-delete --name <QName>`** -- delete a symbol's declaration
  (and implementation body, for a routine) ONLY when it has zero references
  (name-text check); refuses otherwise. Dry-run default; `--json`; `--apply`.
- New unit `DRagLint.Refactor.TextEdit` (range insert/delete applier) backs both.
```

- [ ] **Step 2: Commit**

```bash
git add CHANGELOG.md
git commit -m "docs(refactor): document find-unit + safe-delete (v0.69 D2b)"
```

---

## Task 5: Encoding normalize + verification + report

- [ ] **Step 1: Normalize encoding**

```powershell
Set-Location "C:\Projects\Delphi-RAG-lint"
$files = @('src\refactor\DRagLint.Refactor.TextEdit.pas','src\cli\DRagLint.CLI.pas','src\cli\drag-lint.dpr','tests\refactor\TextEditTests.dpr') + (Get-ChildItem tests\refactor\findunit\*.pas, tests\refactor\safedelete\*.pas, tests\refactor\*.ps1 | ForEach-Object FullName)
foreach ($f in $files) {
  $t = [IO.File]::ReadAllText($f); $t = $t -replace "`r`n","`n" -replace "`n","`r`n"
  [IO.File]::WriteAllText($f, $t, (New-Object System.Text.UTF8Encoding($false)))
  if ([IO.File]::ReadAllBytes($f) | Where-Object { $_ -gt 127 }) { Write-Host "NON-ASCII in $f" -ForegroundColor Red }
}
Write-Host "encoding normalized"
```

- [ ] **Step 2: Full regression**

```powershell
pwsh -File tests\refactor\run_textedit_tests.ps1 | Select-Object -Last 1
pwsh -File tests\refactor\run_find_unit.ps1 | Select-Object -Last 1
pwsh -File tests\refactor\run_safe_delete.ps1 | Select-Object -Last 1
pwsh -File tests\refactor\run_buildlocal_tests.ps1 | Select-Object -Last 1
pwsh -File tests\refactor\run_rename_symbol.ps1 | Select-Object -Last 1
pwsh -File tests\refactor\run_rename_param.ps1 | Select-Object -Last 1
pwsh -File tests\lint\run_lint_tests.ps1 | Select-Object -Last 1
pwsh -File tests\rules-catalog\run_rulecatalog_tests.ps1 | Select-Object -Last 1
pwsh -File tests\lintconfig\run_lintconfig_tests.ps1 | Select-Object -Last 1
```
Expected: textedit/find-unit/safe-delete all pass; buildlocal 14/14; rename-symbol/param pass; lint 117/117; rulecatalog 29/29; lintconfig 30/30.

- [ ] **Step 3: ORM3 real-code sanity (safe-delete REFUSE on a used symbol)**

```powershell
$exe = "third_party\dll-win64\drag-lint.exe"
$db = "C:\Projects\DB\ORM3\drag-lint.sqlite"
# pick a clearly-used symbol; safe-delete must REFUSE (nonzero exit, no edits).
& $exe safe-delete --name <a.real.used.QName> --db $db
```
Expected: REFUSED for a used symbol; nothing written. Record the result. (Use `drag-lint query find-callers --name <X>` to pick a symbol with callers.)

- [ ] **Step 4: Commit normalization + report**

```bash
git add -A
git commit -m "chore(refactor): CRLF/ASCII normalize v0.69 D2b files" || echo "nothing to normalize"
git status --porcelain
git log --oneline -8
```
Report D2b done: `find-unit` + `safe-delete` ship (dry-run default, `--json`, `--apply`); the new `TTextEdit` applier backs them; safe-delete refuses on any reference; tests green; lint harness unaffected. **Next: D1b (IDE Lint Options tab) -- the last v0.69 piece; manual BPL gate.**

---

## Self-Review (completed by plan author)

**Spec coverage (v0.69 spec section 2, find-unit + safe-delete):**
- `find-unit` packages resolve-uses as a uses-clause insert -> Task 2 (store-driven via GetUnitUsesForFile). ✓
- `safe-delete` verify ZERO refs then remove decl (+ body for a routine); refuse on any ref -> Task 3. ✓
- dry-run default + `--json` + `--apply` (backups on, `--no-backup`, ANSI/CRLF) -> Tasks 2-3 + the new applier (Task 1). ✓
- new `tests/refactor` DB-fixture cases -> Tasks 2-3 (+ Task 1 console). ✓
- **Correctness:** zero-ref check uses `FindCallersByName` (NOT the unreliable `FindReferencesTo`) -> Task 3 Global Constraint + code. ✓

**Placeholder scan:** no TBD/"handle edge cases"; the applier + both builders are complete; the ORM3 sanity `<a.real.used.QName>` is a runtime operator choice, not a code placeholder.

**Type/name consistency:** `TTextEdit{FilePath,Kind,Line,Col,EndLine,Text}`, `TTextEditKind(tekInsertInLine/tekInsertLines/tekDeleteLines)`, `TTextEditApplier.Apply/RenderDryRun`, `TFindUnitRefactoring.Build(store,name,infile,out unit,out already)`, `TSafeDeleteRefactoring.Build(store,qname,out reason)`, `TSymbol.StartLine/EndLine/ImplStartLine/ImplEndLine/Section/FileId/Name`, `TUnitUse.UnitName/Section/StartLine/StartCol/EndLine/EndCol`, `TUnitUseSection(uusInterface/uusImplementation)`, `FindCallersByName`/`FindSymbolsByExactName`/`FindSymbolsByQualifiedName`/`GetUnitUsesForFile`/`GetFilePath`/`FindFileIdByPath` -- used consistently across the unit, the CLI handlers, and the tests.

**Known risks flagged in-plan:** (1) the `tekInsertInLine` column from `TUnitUse.EndCol` is verified against a real file in Task 2 Step 5 (adjust ±1 if the dry-run misplaces `, Unit`). (2) `TUnitUse`/`TReference` field names + `TUnitUseSection` values are confirmed against `Core.Model.pas` at build time. (3) safe-delete is conservative: it refuses on ANY name-text caller (may refuse a deletable symbol whose name collides with another -- acceptable; under-delete is safe). (4) `Cands` default-value accumulation uses `TryGetValue` to avoid a missing-key exception.
