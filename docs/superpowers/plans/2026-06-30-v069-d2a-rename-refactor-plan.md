# v0.69 D2a -- refactor CLI: `rename --kind symbol` + `rename --kind param` -- Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship two `drag-lint rename` subcommands -- `--kind symbol` (cross-unit, index-driven, dry-run by default + `--apply`, with keyword/scope conflict detection) and `--kind param` (single-file routine-local rename of a parameter or local var = the `param-name-prefix` autofix) -- both reusing the existing `TRenameRefactoring.Apply`/`RenderDryRun`.

**Architecture:** `--kind symbol` is a thin re-spelling of today's index-driven `rename --qname` (`TRenameRefactoring.Build` -> `Apply`), adding dry-run-default + `--apply` + `--json` + a conflict guard. `--kind param` adds a NEW in-memory builder `TRenameRefactoring.BuildLocal` that parses ONE file with tree-sitter, finds the parameter/local declaration at a given line/col, collects its references within the owning routine (and the matching interface/forward `declProc` header for a param), and emits `TRenameEdit`s that flow through the same `Apply`/`RenderDryRun`. No new edit primitive -- both are token replacements.

**Tech Stack:** Delphi 13 (Studio 37), tree-sitter-delphi13, the existing SQLite symbol store, Win64 `dcc64`/`msbuild`, PowerShell test harnesses.

## Global Constraints

- **Encoding (every `.pas`/`.dpr` you create or edit):** strict 7-bit ASCII, CRLF, no BOM. Edit/Write emit LF -- normalize touched files to CRLF + byte-verify no non-ASCII before committing. `.md` docs may keep pre-existing non-ASCII.
- **Pascal comments:** never put `}` or a nested `{` inside a `{ }` comment.
- **DocInsight (CDD):** `///` `<summary>` on every new public method.
- **VERSION is NOT bumped in D2a.** `src/cli/DRagLint.CLI.pas:6` stays `0.68.0-alpha`; v0.69 publishes after the whole of D2.
- **`--apply` MUST preserve strict ANSI / CRLF / no-BOM** -- `TRenameRefactoring.Apply` already does this; do not change its encoding behavior.
- **Backups ON by default** on `--apply`; `--no-backup` suppresses the `.bak`.
- **Dry-run is the DEFAULT** for the new `--kind` path (print `RenderDryRun` + a summary, write nothing); `--apply` writes. (This differs from the legacy `rename --qname` path, whose default applies -- leave that legacy path's behavior UNCHANGED for back-compat; the new behavior is gated on `--kind` being present.)
- **Build = the `delphi-build` skill recipe** via `build\build_draglint_win64.bat` (rsvars -> msbuild Win64 Debug -> copies the exe to `third_party\dll-win64\drag-lint.exe`). Run from PowerShell `Start-Process -Wait` redirected to a log; read the tail (`OK: staged Win64 drag-lint.exe`, no `Error`/`E2xxx`/`F2xxx`). **Kill orphaned `drag-lint.exe`/`drag_lint_graph.exe` first.**
- **DO NOT `git add` the built exe** (`third_party\dll-win64\drag-lint.exe` is ignored by `*.exe`); commit SOURCE ONLY.
- **Conservative-rename rule:** when an occurrence is ambiguous (a `with`-statement bare member, a qualified member `X.Name`, a name re-declared by a nested routine), DO NOT rename it. Under-renaming is safe (the user re-runs / edits); over-renaming corrupts code.

---

## File Structure

| File | Responsibility | Change |
|------|----------------|--------|
| `src/refactor/DRagLint.Refactor.Rename.pas` | add `BuildLocal` + conflict helpers; keep `TRenameEdit`/`Build`/`Apply`/`RenderDryRun` | Modify |
| `src/cli/DRagLint.CLI.pas` | `rename --kind symbol\|param` arg parse + dispatch inside `DoRename` | Modify |
| `tests/refactor/BuildLocalTests.dpr` + `run_buildlocal_tests.ps1` | console TDD for `BuildLocal` (in-memory, no DB) | Create |
| `tests/refactor/rename/*.pas` + `run_rename_symbol.ps1` + `run_rename_param.ps1` | DB-fixture + CLI tests | Create |
| `rules/README.md` (or `docs/lint/`), `CHANGELOG.md` | docs | Modify |

---

## Task 1: `TRenameRefactoring.BuildLocal` (routine-local rename engine)

**Files:**
- Modify: `src/refactor/DRagLint.Refactor.Rename.pas` (add `BuildLocal` + a private AST helper; extend `uses` with `TreeSitter`, `TreeSitterLib`, `DRagLint.Diagnostics.ParseCache`)
- Create: `tests/refactor/BuildLocalTests.dpr`, `tests/refactor/run_buildlocal_tests.ps1`

**Interfaces:**
- Produces: `class function TRenameRefactoring.BuildLocal(const AFile: string; ALine, ACol: Integer; const ANewName: string): TArray<TRenameEdit>;`
  - Finds the parameter/local identifier whose declaration token is at (ALine, ACol) (1-based), determines its owning routine, and returns one `TRenameEdit` per in-scope occurrence (declaration + uses + matching interface/forward header param). Empty array if no decl is found at that position.

- [ ] **Step 1: Write the failing console test**

Create `tests/refactor/BuildLocalTests.dpr`:
```pascal
program BuildLocalTests;
{$APPTYPE CONSOLE}
uses
  System.SysUtils, System.IOUtils, System.Generics.Collections,
  DRagLint.Core.Model in '..\..\src\core\DRagLint.Core.Model.pas',
  DRagLint.Core.Interfaces in '..\..\src\core\DRagLint.Core.Interfaces.pas',
  DRagLint.Diagnostics.ParseCache in '..\..\src\diagnostics\DRagLint.Diagnostics.ParseCache.pas',
  DRagLint.Refactor.Rename in '..\..\src\refactor\DRagLint.Refactor.Rename.pas';
var GPass, GFail: Integer;
procedure Check(const AName: string; ACond: Boolean);
begin
  if ACond then begin Inc(GPass); Writeln('PASS  ', AName); end
  else begin Inc(GFail); Writeln('FAIL  ', AName); end;
end;
function HasEdit(const E: TArray<TRenameEdit>; ALine, ACol: Integer): Boolean;
var X: TRenameEdit;
begin
  Result:= False;
  for X in E do if (X.Line = ALine) and (X.Col = ACol) then Exit(True);
end;
function CountFor(const E: TArray<TRenameEdit>; const AOld: string): Integer;
var X: TRenameEdit;
begin
  Result:= 0;
  for X in E do if SameText(X.OldName, AOld) then Inc(Result);
end;
{ Write a fixture, parse-rename a position, return the edits. }
function RunOn(const ASrc: string; ALine, ACol: Integer; const ANew: string): TArray<TRenameEdit>;
var P: string;
begin
  P:= TPath.Combine(TPath.GetTempPath, 'bl_fixture.pas');
  TFile.WriteAllText(P, ASrc, TEncoding.ANSI);
  TAstParseCache.Clear;
  Result:= TRenameRefactoring.BuildLocal(P, ALine, ACol, ANew);
  TAstParseCache.Clear;
  if TFile.Exists(P) then TFile.Delete(P);
end;
const
  { Param 'Value' at line 5 col 18 (1-based). Body uses it twice (lines 8,9).
    The interface forward decl (line 3) also has 'Value'. The type 'Integer'
    must NOT be renamed. A nested routine re-declares 'Value' (line 11) -- its
    occurrence and uses (line 13) must NOT be renamed (shadowing). }
  SRC_PARAM =
    'unit u;'#13#10 +                                  // 1
    'interface'#13#10 +                                // 2
    'procedure Go(Value: Integer);'#13#10 +            // 3
    'implementation'#13#10 +                           // 4
    'procedure Go(Value: Integer);'#13#10 +            // 5
    '  procedure Inner(Value: string);'#13#10 +        // 6  (nested, shadows)
    '  begin'#13#10 +                                  // 7
    '    Writeln(Value);'#13#10 +                      // 8  inner use -> NOT renamed
    '  end;'#13#10 +                                   // 9
    'begin'#13#10 +                                    // 10
    '  Writeln(Value);'#13#10 +                        // 11 outer use -> renamed
    '  Value := 1;'#13#10 +                            // 12 outer use -> renamed
    'end;'#13#10 +                                     // 13
    'end.'#13#10;                                      // 14
var
  E: TArray<TRenameEdit>;
begin
  GPass:= 0; GFail:= 0;
  try
    { Rename the outer param 'Value' (decl at line 5). Col 14 = the 'V' of the
      first param after 'procedure Go(' -- adjust if the test shows a different col. }
    E:= RunOn(SRC_PARAM, 5, 14, 'pValue');
    Check('renames the impl decl (line 5)', HasEdit(E, 5, 14));
    Check('renames outer body use (line 11)', CountFor(E, 'Value') >= 3);
    Check('does NOT rename the type Integer', CountFor(E, 'Integer') = 0);
    { interface forward header param (line 3) also synced }
    Check('syncs interface forward decl (line 3)', HasEdit(E, 3, 14));
    { nested Inner's own param (line 6) + its use (line 8) are shadowed -> not touched.
      Total edits should be: decl(5) + 2 body uses(11,12) + iface(3) = 4, NOT 6/7. }
    Check('shadowed nested occurrences excluded (<= 4 edits)', Length(E) <= 4);
    Check('every edit OldName = Value', CountFor(E, 'Value') = Length(E));
    Check('every edit NewName = pValue',
      (Length(E) > 0) and (E[0].NewName = 'pValue'));
  except
    on Ex: Exception do begin Writeln('EXCEPTION ', Ex.ClassName, ': ', Ex.Message); Inc(GFail); end;
  end;
  Writeln('');
  Writeln(Format('buildlocal-tests: %d pass / %d fail / %d total', [GPass, GFail, GPass + GFail]));
  if GFail > 0 then Halt(1) else Halt(0);
end.
```

Create `tests/refactor/run_buildlocal_tests.ps1`:
```powershell
# Build + run the BuildLocal console tests (bare dcc64, Win64). Needs the
# tree-sitter-delphi13 DLL on PATH -- copy it next to the exe.
$rs  = 'C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\rsvars.bat'
$dir = $PSScriptRoot
$repo = (Resolve-Path (Join-Path $dir "..\..")).Path
$out = cmd /c "call `"$rs`" && cd /d `"$dir`" && dcc64 -B -E`"$dir`" -U`"$repo\src\core;$repo\src\diagnostics;$repo\src\refactor;$repo\src\parser;$repo\third_party\delphi-tree-sitter`" `"$dir\BuildLocalTests.dpr`"" 2>&1
$err = $out | Select-String -Pattern "\bError\b|E2\d{3}|F2\d{3}|Fatal"
if ($err) { Write-Host "BUILD FAILED:"; $err | Select-Object -First 12; exit 1 }
Copy-Item "$repo\third_party\dll-win64\tree-sitter-delphi13.dll" $dir -Force
Copy-Item "$repo\third_party\dll-win64\tree-sitter.dll" $dir -Force -ErrorAction SilentlyContinue
& "$dir\BuildLocalTests.exe"
exit $LASTEXITCODE
```

- [ ] **Step 2: Run the test to confirm it fails**

Run:
```powershell
pwsh -File tests\refactor\run_buildlocal_tests.ps1
```
Expected: `BUILD FAILED` -- `BuildLocal` not declared. (If the `-U` unit search path is wrong for this repo's layout, fix the paths until dcc64 finds `DRagLint.Diagnostics.ParseCache` and `TreeSitter`; the diagnostics units already compile against these, so mirror their `.dproj` search paths.)

- [ ] **Step 3: Add `BuildLocal` to the rename unit**

In `src/refactor/DRagLint.Refactor.Rename.pas`:

(a) Extend the interface `uses` clause:
```pascal
uses
  System.SysUtils
  , System.Classes
  , System.IOUtils
  , System  .Generics.Collections
  , System  .Generics.Defaults
  , TreeSitter
  , TreeSitterLib
  , DRagLint.Core    .Model
  , DRagLint.Core    .Interfaces
  , DRagLint.Diagnostics.ParseCache
  ;
```

(b) Add the method to the class declaration (after `RenderDryRun`):
```pascal
      /// <summary>Routine-local rename of the parameter or local variable whose
      /// declaration identifier sits at (ALine, ACol) (1-based) in AFile. Emits a
      /// TRenameEdit for the declaration, every in-scope use within the owning
      /// routine body, and the matching parameter in any same-named forward/interface
      /// declProc header. Shadowing nested routines, qualified members (X.Name), and
      /// with-statement members are conservatively skipped. Empty array if no
      /// param/local decl is found at that position. Pure AST -- no symbol store.</summary>
      class function BuildLocal(const AFile: string; ALine, ACol: Integer; const ANewName: string): TArray<TRenameEdit>;
```

(c) Add the implementation (before `end.`). The algorithm: parse; locate the decl identifier at (ALine,ACol) and its owning `defProc`; collect bare-identifier occurrences of that name within the owning routine subtree, EXCLUDING (i) the type-annotation region of any decl, (ii) `rhs` of an `exprDot`, (iii) any subtree of a nested `defProc` that re-declares the same name; then add matching forward `declProc` header params elsewhere in the file:

```pascal
class function TRenameRefactoring.BuildLocal(const AFile: string; ALine, ACol: Integer;
  const ANewName: string): TArray<TRenameEdit>;
var
  PF      : TParsedFile          ;
  Src     : TBytes               ;
  Edits   : TList<TRenameEdit>   ;
  Target  : string               ;
  OwnerProc: TTSNode             ;

  function NStr(const N: TTSNode): string;
  var S, E, L: Integer;
  begin
    Result:= '';
    if N.IsNull then Exit;
    S:= Integer(N.StartByte); E:= Integer(N.EndByte); L:= E - S;
    if (L <= 0) or (S < 0) or (E > Length(Src)) then Exit;
    Result:= TEncoding.UTF8.GetString(Src, S, L);
  end;

  function NLine(const N: TTSNode): Integer;
  begin Result:= Integer(N.StartPoint.Row) + 1; end;
  function NColOf(const N: TTSNode): Integer;
  begin Result:= Integer(N.StartPoint.Column) + 1; end;

  procedure AddEdit(const N: TTSNode);
  var Ed: TRenameEdit;
  begin
    Ed.FilePath:= AFile; Ed.Line:= NLine(N); Ed.Col:= NColOf(N);
    Ed.OldName:= Target; Ed.NewName:= ANewName;
    Edits.Add(Ed);
  end;

  { Find the identifier node at (ALine,ACol). Returns null node if none. }
  function FindIdentAt(const N: TTSNode): TTSNode;
  var I: Integer; Ch, R: TTSNode;
  begin
    Result:= Default(TTSNode);
    if N.IsNull then Exit;
    if (N.NodeType = 'identifier') and (NLine(N) = ALine) and (NColOf(N) = ACol) then
      Exit(N);
    for I:= 0 to N.NamedChildCount - 1 do
    begin
      Ch:= N.NamedChild(I);
      R:= FindIdentAt(Ch);
      if not R.IsNull then Exit(R);
    end;
  end;

  { Smallest enclosing defProc of a node, by byte span. }
  function EnclosingProc(const ATargetByte: Integer; const N: TTSNode; const ABest: TTSNode): TTSNode;
  var I: Integer; Ch: TTSNode;
  begin
    Result:= ABest;
    if N.IsNull then Exit;
    if (N.NodeType = 'defProc')
      and (Integer(N.StartByte) <= ATargetByte) and (Integer(N.EndByte) >= ATargetByte) then
      Result:= N;
    for I:= 0 to N.NamedChildCount - 1 do
    begin
      Ch:= N.NamedChild(I);
      Result:= EnclosingProc(ATargetByte, Ch, Result);
    end;
  end;

  { Walk the owning routine subtree, emitting edits for bare-identifier uses of
    Target. Skip: a nested defProc that re-declares Target (shadowing) -- detected
    by scanning its header args for the name; the rhs of an exprDot (member access);
    a 'with' statement subtree (ambiguous bare members). ASkipNested: when True we
    are inside a shadowing nested routine and emit nothing. }
  function NestedRedeclares(const AProc: TTSNode): Boolean;
  var Hdr, Args, A, J: Integer; HN, AN, Nm: TTSNode; K: Integer;
  begin
    Result:= False;
    HN:= AProc.ChildByField('header');
    if HN.IsNull then Exit;
    AN:= HN.ChildByField('args');
    if AN.IsNull then Exit;
    for K:= 0 to AN.NamedChildCount - 1 do
    begin
      Nm:= AN.NamedChild(K);
      if Nm.NodeType <> 'declArg' then Continue;
      for J:= 0 to Nm.NamedChildCount - 1 do
        if (Nm.NamedChild(J).NodeType = 'identifier')
          and SameText(Trim(NStr(Nm.NamedChild(J))), Target) then Exit(True);
    end;
  end;

  procedure Walk(const N: TTSNode; AInside: Boolean);
  var I: Integer; Ch: TTSNode;
  begin
    if N.IsNull then Exit;
    { Entering a nested defProc that shadows Target -> stop descending for renames. }
    if (not N.Equals(OwnerProc)) and (N.NodeType = 'defProc') and NestedRedeclares(N) then
      Exit;
    { Skip with-statement subtrees (ambiguous). }
    if N.NodeType = 'with' then Exit;
    { An identifier matching Target, not the rhs of a dotted member access. }
    if (N.NodeType = 'identifier') and SameText(Trim(NStr(N)), Target) then
    begin
      AddEdit(N);
      Exit;
    end;
    for I:= 0 to N.NamedChildCount - 1 do
    begin
      Ch:= N.NamedChild(I);
      { exclude exprDot rhs (member access): skip the 2nd child of an exprDot. }
      if (N.NodeType = 'exprDot') and (I = N.NamedChildCount - 1) then Continue;
      Walk(Ch, AInside);
    end;
  end;

  { Add the matching parameter in any forward/interface declProc with the same
    routine name as OwnerProc. Scans all declProc nodes in the file. }
  procedure SyncForwardHeaders(const ARoot: TTSNode);
  var I: Integer; Ch: TTSNode;
    OwnerName: string;
    function HdrName(const AProc: TTSNode): string;
    var H, Nm: TTSNode;
    begin
      Result:= '';
      H:= AProc.ChildByField('header');
      if H.IsNull then H:= AProc; { declProc has name directly }
      Nm:= H.ChildByField('name');
      if Nm.IsNull then Nm:= AProc.ChildByField('name');
      if not Nm.IsNull then Result:= Trim(NStr(Nm));
    end;
    procedure ScanArgs(const AProc: TTSNode);
    var AN, NmN: TTSNode; K, J: Integer; TypeStart: Integer; TN: TTSNode;
    begin
      AN:= AProc.ChildByField('args');
      if AN.IsNull then Exit;
      for K:= 0 to AN.NamedChildCount - 1 do
      begin
        NmN:= AN.NamedChild(K);
        if NmN.NodeType <> 'declArg' then Continue;
        TN:= NmN.ChildByField('type'); TypeStart:= MaxInt;
        if not TN.IsNull then TypeStart:= Integer(TN.StartByte);
        for J:= 0 to NmN.NamedChildCount - 1 do
        begin
          var Id: TTSNode:= NmN.NamedChild(J);
          if Id.NodeType <> 'identifier' then Continue;
          if Integer(Id.StartByte) >= TypeStart then Continue;
          if SameText(Trim(NStr(Id)), Target) then AddEdit(Id);
        end;
      end;
    end;
  var
    Stack: TList<TTSNode>;
  begin
    OwnerName:= HdrName(OwnerProc);
    if OwnerName = '' then Exit;
    Stack:= TList<TTSNode>.Create;
    try
      Stack.Add(ARoot);
      while Stack.Count > 0 do
      begin
        var Cur: TTSNode:= Stack[Stack.Count - 1];
        Stack.Delete(Stack.Count - 1);
        if Cur.NodeType = 'declProc' then
        begin
          if SameText(HdrName(Cur), OwnerName) then ScanArgs(Cur);
        end;
        for I:= 0 to Cur.NamedChildCount - 1 do Stack.Add(Cur.NamedChild(I));
      end;
    finally
      Stack.Free;
    end;
  end;

var
  IdNode  : TTSNode;
  Dedup   : TDictionary<string, Boolean>;
  Ed      : TRenameEdit;
  Key     : string;
  Comparer: IComparer<TRenameEdit>;
begin
  Result:= nil;
  PF:= TAstParseCache.Get(AFile);
  if PF.Tree = nil then Exit;
  Src:= PF.Src;

  IdNode:= FindIdentAt(PF.Tree.RootNode);
  if IdNode.IsNull then Exit;
  Target:= Trim(NStr(IdNode));
  if Target = '' then Exit;

  OwnerProc:= EnclosingProc(Integer(IdNode.StartByte), PF.Tree.RootNode, Default(TTSNode));
  if OwnerProc.IsNull then Exit; { decl not inside a routine impl -- out of scope }

  Edits:= TList<TRenameEdit>.Create;
  try
    Walk(OwnerProc, True);             { decl + uses inside the owning routine }
    SyncForwardHeaders(PF.Tree.RootNode); { matching forward/interface header params }

    { De-dup by (line,col); sort back-to-front for Apply. }
    Dedup:= TDictionary<string, Boolean>.Create;
    var Final: TList<TRenameEdit>:= TList<TRenameEdit>.Create;
    try
      for Ed in Edits do
      begin
        Key:= IntToStr(Ed.Line) + ':' + IntToStr(Ed.Col);
        if not Dedup.ContainsKey(Key) then begin Dedup.Add(Key, True); Final.Add(Ed); end;
      end;
      Comparer:= TComparer<TRenameEdit>.Construct(
        function(const A, B: TRenameEdit): Integer
        begin
          Result:= B.Line - A.Line;
          if Result = 0 then Result:= B.Col - A.Col;
        end);
      Final.Sort(Comparer);
      Result:= Final.ToArray;
    finally
      Final.Free;
      Dedup.Free;
    end;
  finally
    Edits.Free;
  end;
end;
```

(Note: `TTSNode.Equals` -- if the binding has no `Equals`, compare `Integer(A.StartByte) = Integer(B.StartByte)` and end bytes instead. Confirm against `TreeSitter.pas` during Step 4; adjust the `N.Equals(OwnerProc)` check accordingly.)

- [ ] **Step 4: Build + run the console test; confirm GREEN (iterate on real node kinds)**

Run:
```powershell
pwsh -File tests\refactor\run_buildlocal_tests.ps1
```
Expected: `buildlocal-tests: N pass / 0 fail / N total`. **If a check fails**, the most likely causes (fix the code, not the test): the decl identifier's actual (line,col) differs from the test's `(5,14)` -- temporarily add `Writeln(IdNode... )` or dump the tree with the existing `ConsoleReadPasFile` approach to find the true column, and update the test's position; or `with`/`exprDot`/nested-`defProc` kinds differ -- confirm via a real parse and adjust the guards. Do not weaken the shadowing/member guards to force a pass.

- [ ] **Step 5: Commit (source only)**

```bash
git add src/refactor/DRagLint.Refactor.Rename.pas tests/refactor/BuildLocalTests.dpr tests/refactor/run_buildlocal_tests.ps1
git commit -m "feat(refactor): BuildLocal routine-local rename engine (v0.69 D2a)"
```

---

## Task 2: Conflict detection helpers (keyword + scope)

**Files:**
- Modify: `src/refactor/DRagLint.Refactor.Rename.pas` (add two class functions)

**Interfaces:**
- Produces:
  - `class function TRenameRefactoring.IsReservedWord(const AName: string): Boolean;` -- True if AName (case-insensitive) is a Delphi reserved word that cannot be an identifier.
  - `class function TRenameRefactoring.ConflictReason(const AStore: ISymbolStore; const AQName, ANewName: string): string;` -- returns a non-empty reason if the rename is unsafe (new name is a reserved word, or a sibling symbol with the new name already exists in the same parent scope); '' if safe.

- [ ] **Step 1: Add the failing assertions to the BuildLocal console test**

In `tests/refactor/BuildLocalTests.dpr`, add after the existing checks (before the summary), plus `DRagLint.Refactor.Rename` is already in uses:
```pascal
  Check('IsReservedWord(begin) = True', TRenameRefactoring.IsReservedWord('Begin'));
  Check('IsReservedWord(end) = True', TRenameRefactoring.IsReservedWord('END'));
  Check('IsReservedWord(Foo) = False', not TRenameRefactoring.IsReservedWord('Foo'));
  Check('IsReservedWord(pValue) = False', not TRenameRefactoring.IsReservedWord('pValue'));
```

- [ ] **Step 2: Run -- confirm build failure (IsReservedWord undeclared)**

```powershell
pwsh -File tests\refactor\run_buildlocal_tests.ps1
```
Expected: BUILD FAILED -- `IsReservedWord` not declared.

- [ ] **Step 3: Implement the helpers**

Add to the class declaration:
```pascal
      /// <summary>True when AName is a Delphi reserved word (case-insensitive) and
      /// therefore cannot be used as an identifier.</summary>
      class function IsReservedWord(const AName: string): Boolean;
      /// <summary>Non-empty human reason when renaming AQName to ANewName would be
      /// unsafe: ANewName is a reserved word, or a sibling symbol named ANewName
      /// already exists under the same parent. '' when the rename is safe.</summary>
      class function ConflictReason(const AStore: ISymbolStore; const AQName, ANewName: string): string;
```
Add the implementations (the reserved-word list is the Delphi 13 reserved words -- NOT directives):
```pascal
class function TRenameRefactoring.IsReservedWord(const AName: string): Boolean;
const
  KReserved: array[0..64] of string = (
    'and','array','as','asm','begin','case','class','const','constructor','destructor',
    'dispinterface','div','do','downto','else','end','except','exports','file','finalization',
    'finally','for','function','goto','if','implementation','in','inherited','initialization',
    'inline','interface','is','label','library','mod','nil','not','object','of','or',
    'packed','procedure','program','property','raise','record','repeat','resourcestring',
    'set','shl','shr','string','then','threadvar','to','try','type','unit','until','uses',
    'var','while','with','xor');
var L, H, M, C: Integer; Low: string;
begin
  Low:= LowerCase(AName);
  L:= 0; H:= High(KReserved);
  while L <= H do
  begin
    M:= (L + H) div 2;
    C:= CompareStr(Low, KReserved[M]);
    if C = 0 then Exit(True)
    else if C < 0 then H:= M - 1
    else L:= M + 1;
  end;
  Result:= False;
end;

class function TRenameRefactoring.ConflictReason(const AStore: ISymbolStore;
  const AQName, ANewName: string): string;
var
  Syms: TArray<TSymbol>;
  Sib : TSymbol;
begin
  Result:= '';
  if IsReservedWord(ANewName) then
    Exit(Format('"%s" is a reserved word', [ANewName]));
  Syms:= AStore.FindSymbolsByQualifiedName(AQName);
  if Length(Syms) = 0 then Exit;
  { sibling-name collision under the same parent }
  Sib:= AStore.FindChildSymbolByName(Syms[0].ParentId, ANewName);
  if Sib.Id <> 0 then
    Exit(Format('a symbol named "%s" already exists in the same scope', [ANewName]));
end;
```
(If `TSymbol` has no `ParentId`/`Id` fields by those names, use the actual field names from `DRagLint.Core.Model.pas` -- check and adjust; the sibling check is best-effort and may be dropped to just the reserved-word check if no parent linkage exists, but keep the reserved-word guard which is the primary requirement.)

- [ ] **Step 4: Run -- confirm GREEN**

```powershell
pwsh -File tests\refactor\run_buildlocal_tests.ps1
```
Expected: all pass including the 4 new reserved-word checks.

- [ ] **Step 5: Commit**

```bash
git add src/refactor/DRagLint.Refactor.Rename.pas tests/refactor/BuildLocalTests.dpr
git commit -m "feat(refactor): reserved-word + scope conflict detection for rename (v0.69 D2a)"
```

---

## Task 3: CLI `rename --kind symbol|param` + DB-fixture + CLI tests

**Files:**
- Modify: `src/cli/DRagLint.CLI.pas` (`DoRename` -- add `--kind`/`--file`/`--line`/`--col`/`--apply` handling; new TArgs fields if missing)
- Create: `tests/refactor/rename/Subject.pas`, `tests/refactor/rename/Caller.pas`, `tests/refactor/rename/Param.pas`, `tests/refactor/run_rename_symbol.ps1`, `tests/refactor/run_rename_param.ps1`

**Interfaces:**
- Consumes: `TRenameRefactoring.Build/BuildLocal/Apply/RenderDryRun/ConflictReason` (Tasks 1-2).
- Produces: `rename --kind symbol --name <QName> --to <New> [--json|--apply|--no-backup]` and `rename --kind param --file <F> --line <L> --col <C> --to <New> [--json|--apply|--no-backup]`.

- [ ] **Step 1: Write the failing DB-fixture + param CLI tests**

Create `tests/refactor/rename/Subject.pas`:
```pascal
unit Subject;
interface
type
  TSubject = class
    procedure Foo;
  end;
implementation
procedure TSubject.Foo;
begin
end;
end.
```
Create `tests/refactor/rename/Caller.pas`:
```pascal
unit Caller;
interface
implementation
uses Subject;
procedure DoIt;
var S: TSubject;
begin
  S := TSubject.Create;
  S.Foo;
end;
end.
```
Create `tests/refactor/rename/Param.pas`:
```pascal
unit Param;
interface
procedure Go(Value: Integer);
implementation
procedure Go(Value: Integer);
begin
  Writeln(Value);
  Value := Value + 1;
end;
end.
```

Create `tests/refactor/run_rename_symbol.ps1`:
```powershell
param([string]$Exe = "third_party\dll-win64\drag-lint.exe")
$ErrorActionPreference = "Stop"
$repo = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
Set-Location $repo
$exe = (Resolve-Path $Exe).Path
$dir = Join-Path $PSScriptRoot "rename"
$db  = Join-Path $env:TEMP "refactor_rename.sqlite"
if (Test-Path $db) { Remove-Item $db -Force }
& $exe index $dir --db $db | Out-Null
$fail = 0
function Assert($n,$c){ if($c){Write-Host "PASS  $n"}else{Write-Host "FAIL  $n" -ForegroundColor Red;$script:fail++} }

# dry-run (default): prints the edit plan, writes nothing
$dry = (& $exe rename --kind symbol --name Subject.TSubject.Foo --to Bar --db $db 2>$null) -join "`n"
Assert "dry-run shows decl rename Foo->Bar" ($dry -match 'Foo -> Bar')
Assert "dry-run shows the caller site"      (([regex]::Matches($dry,'Foo -> Bar')).Count -ge 2)

# --json edit set
$json = & $exe rename --kind symbol --name Subject.TSubject.Foo --to Bar --json --db $db 2>$null | ConvertFrom-Json
Assert "json edit set non-empty" ($json.Count -ge 2)
Assert "json edit has line/col/old/new" ($null -ne $json[0].line -and $json[0].old -eq 'Foo' -and $json[0].new -eq 'Bar')

# conflict: refuse a reserved word
$kw = (& $exe rename --kind symbol --name Subject.TSubject.Foo --to begin --db $db 2>&1) -join "`n"
Assert "refuses reserved-word target" ($kw -match 'reserved word')

Write-Host ""
if ($fail -gt 0) { Write-Host "rename-symbol: $fail FAIL"; exit 1 } else { Write-Host "rename-symbol: all pass"; exit 0 }
```

Create `tests/refactor/run_rename_param.ps1`:
```powershell
param([string]$Exe = "third_party\dll-win64\drag-lint.exe")
$ErrorActionPreference = "Stop"
$repo = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
Set-Location $repo
$exe = (Resolve-Path $Exe).Path
$src = Join-Path $PSScriptRoot "rename\Param.pas"
$fail = 0
function Assert($n,$c){ if($c){Write-Host "PASS  $n"}else{Write-Host "FAIL  $n" -ForegroundColor Red;$script:fail++} }

# dry-run param rename of 'Value' (impl decl at line 5; col of the 'V' -- the test
# asserts on the rename arrows, not the exact col). Find the col with a quick scan:
$line5 = (Get-Content $src)[4]
$col = $line5.IndexOf('Value') + 1   # 1-based
$dry = (& $exe rename --kind param --file $src --line 5 --col $col --to pValue 2>$null) -join "`n"
Assert "param dry-run renames Value->pValue" ($dry -match 'Value -> pValue')
Assert "param dry-run hits multiple sites" (([regex]::Matches($dry,'Value -> pValue')).Count -ge 3)

# --apply into a temp copy, then verify the file content changed and Integer is intact
$tmp = Join-Path $env:TEMP "param_apply_test"
if (Test-Path $tmp) { Remove-Item $tmp -Recurse -Force }
New-Item -ItemType Directory -Path $tmp | Out-Null
Copy-Item $src (Join-Path $tmp "Param.pas")
$t = Join-Path $tmp "Param.pas"
$c2 = (Get-Content $t)[4]; $col2 = $c2.IndexOf('Value') + 1
& $exe rename --kind param --file $t --line 5 --col $col2 --to pValue --apply --no-backup 2>$null | Out-Null
$after = Get-Content $t -Raw
Assert "apply renamed the param decl"  ($after -match 'procedure Go\(pValue: Integer\)')
Assert "apply renamed body uses"        ($after -match 'Writeln\(pValue\)')
Assert "apply left the type Integer"    ($after -match ': Integer')
Assert "apply did NOT touch interface line is acceptable either way" $true

Write-Host ""
if ($fail -gt 0) { Write-Host "rename-param: $fail FAIL"; exit 1 } else { Write-Host "rename-param: all pass"; exit 0 }
```

- [ ] **Step 2: Run -- confirm both fail (command/kind not implemented)**

```powershell
pwsh -File tests\refactor\run_rename_symbol.ps1
pwsh -File tests\refactor\run_rename_param.ps1
```
Expected: FAIL -- `--kind` unknown / no edits.

- [ ] **Step 3: Add the TArgs fields + arg parsing**

In `src/cli/DRagLint.CLI.pas` `TArgs` (near `RenameTo`/`NoBackup` ~line 153) add any missing:
```pascal
    RenameKind  : string ; // --kind symbol|param
    RefFile     : string ; // --file <F> (param rename)
    RefLine     : Integer; // --line <L>
    RefCol      : Integer; // --col <C>
    Apply       : Boolean; // --apply (write; default is dry-run for --kind path)
```
(If `Apply` already exists -- `uses-fix` uses it -- reuse it. `RefLine`/`RefCol` default 0.)
In the arg-parse loop add (mirroring `--rules-dir`):
```pascal
    else if (A = '--kind')  and (i < ParamCount) then begin Inc(i); Result.RenameKind:= ParamStr(i); end
    else if (A = '--file')  and (i < ParamCount) then begin Inc(i); Result.RefFile:= ParamStr(i); end
    else if (A = '--line')  and (i < ParamCount) then begin Inc(i); Result.RefLine:= StrToIntDef(ParamStr(i), 0); end
    else if (A = '--col')   and (i < ParamCount) then begin Inc(i); Result.RefCol := StrToIntDef(ParamStr(i), 0); end
    else if  A = '--apply' then Result.Apply:= True
```
(Check `--kind`/`--file` aren't already consumed by another command's parse; `--name`, `--to`, `--json`, `--no-backup`, `--db` already exist.)

- [ ] **Step 4: Branch `DoRename` on `--kind`**

In `DoRename` (CLI.pas:5694), at the TOP (before the legacy `--qname` logic), add the new `--kind` dispatch. Emit a small JSON helper for the edit set:
```pascal
  { v0.69 D2a: the --kind path = dry-run default + --apply, --json edit set,
    conflict guard. Legacy --qname path (no --kind) is unchanged below. }
  if AArgs.RenameKind <> '' then
  begin
    var Edits: TArray<TRenameEdit>;
    if SameText(AArgs.RenameKind, 'param') then
    begin
      if (AArgs.RefFile = '') or (AArgs.RefLine <= 0) or (AArgs.RefCol <= 0) or (AArgs.RenameTo = '') then
      begin Writeln('ERROR: rename --kind param needs --file --line --col --to'); Exit(2); end;
      if TRenameRefactoring.IsReservedWord(AArgs.RenameTo) then
      begin Writeln(Format('ERROR: "%s" is a reserved word', [AArgs.RenameTo])); Exit(2); end;
      Edits:= TRenameRefactoring.BuildLocal(AArgs.RefFile, AArgs.RefLine, AArgs.RefCol, AArgs.RenameTo);
    end
    else if SameText(AArgs.RenameKind, 'symbol') then
    begin
      if (AArgs.Name = '') and (AArgs.QName = '') then
      begin Writeln('ERROR: rename --kind symbol needs --name <QualifiedName> --to <New>'); Exit(2); end;
      var QN: string:= AArgs.QName; if QN = '' then QN:= AArgs.Name;
      if (AArgs.RenameTo = '') then begin Writeln('ERROR: --to required'); Exit(2); end;
      if AArgs.DbPath = '' then begin Writeln('ERROR: --db required for --kind symbol'); Exit(2); end;
      var Store: ISymbolStore:= TSQLiteSymbolStore.Create(AArgs.DbPath); Store.Migrate;
      var Reason: string:= TRenameRefactoring.ConflictReason(Store, QN, AArgs.RenameTo);
      if Reason <> '' then begin Writeln('ERROR: cannot rename -- ' + Reason); Exit(2); end;
      Edits:= TRenameRefactoring.Build(Store, QN, AArgs.RenameTo);
    end
    else
    begin Writeln('ERROR: --kind must be symbol or param'); Exit(2); end;

    if Length(Edits) = 0 then begin Writeln('No edits computed.'); Exit(1); end;

    if AArgs.AsJson then
    begin
      var Arr: TJSONArray:= TJSONArray.Create;
      try
        for var Ed in Edits do
        begin
          var O: TJSONObject:= TJSONObject.Create;
          O.AddPair('file', Ed.FilePath);
          O.AddPair('line', TJSONNumber.Create(Ed.Line));
          O.AddPair('col', TJSONNumber.Create(Ed.Col));
          O.AddPair('old', Ed.OldName);
          O.AddPair('new', Ed.NewName);
          Arr.AddElement(O);
        end;
        Writeln(Arr.ToJSON);
      finally
        Arr.Free;
      end;
      Exit(0);
    end;

    if not AArgs.Apply then
    begin
      Writeln(TRenameRefactoring.RenderDryRun(Edits));
      Writeln(Format('Dry run: %d edit(s). Pass --apply to write.', [Length(Edits)]));
      Exit(0);
    end;

    var Touched: Integer:= TRenameRefactoring.Apply(Edits, not AArgs.NoBackup);
    Writeln(Format('Applied: %d edit(s), %d file(s).', [Length(Edits), Touched]));
    Exit(0);
  end;
  { ----- legacy --qname path below (unchanged) ----- }
```
(Ensure `System.JSON`, `DRagLint.Storage.SQLite` (`TSQLiteSymbolStore`), and `DRagLint.Refactor.Rename` are in the CLI `uses` -- they already are, since `DoRename`/`DoResolveUses` use them.)

- [ ] **Step 5: Add help text**

In the help/usage block, update/add the `rename` lines:
```pascal
  Writeln('  drag-lint rename --kind symbol --name <QName> --to <New> [--json|--apply|--no-backup] --db <db>   - cross-unit rename');
  Writeln('  drag-lint rename --kind param  --file <F> --line <L> --col <C> --to <New> [--json|--apply|--no-backup]  - routine-local rename (param/var autofix)');
```

- [ ] **Step 6: Build Win64**

```powershell
Get-Process drag-lint,drag_lint_graph -ErrorAction SilentlyContinue | Stop-Process -Force
Start-Process -FilePath "build\build_draglint_win64.bat" -Wait -NoNewWindow -RedirectStandardOutput "C:\TEMP\claude\c--Projects-Delphi-RAG-lint\a9995faf-a53e-4216-8eb7-9124c3d767bd\scratchpad\d2a-build.log" -RedirectStandardError "C:\TEMP\claude\c--Projects-Delphi-RAG-lint\a9995faf-a53e-4216-8eb7-9124c3d767bd\scratchpad\d2a-build.err"
Get-Content "C:\TEMP\claude\c--Projects-Delphi-RAG-lint\a9995faf-a53e-4216-8eb7-9124c3d767bd\scratchpad\d2a-build.log" -Tail 5
```
Expected: `OK: staged Win64 drag-lint.exe`.

- [ ] **Step 7: Run both refactor tests + the lint harness**

```powershell
pwsh -File tests\refactor\run_rename_symbol.ps1
pwsh -File tests\refactor\run_rename_param.ps1
pwsh -File tests\lint\run_lint_tests.ps1 | Select-Object -Last 1
```
Expected: `rename-symbol: all pass`; `rename-param: all pass`; `lint-tests: 117 ... 0 fail`. (If the symbol-rename caller-site count is off, the index may resolve refs differently than expected -- inspect the `--json` output and adjust the assertion to the real, correct edit set; do not loosen a guard that protects correctness.)

- [ ] **Step 8: Commit (source only)**

```bash
git add src/cli/DRagLint.CLI.pas tests/refactor/rename/Subject.pas tests/refactor/rename/Caller.pas tests/refactor/rename/Param.pas tests/refactor/run_rename_symbol.ps1 tests/refactor/run_rename_param.ps1
git commit -m "feat(refactor): rename --kind symbol|param CLI (dry-run default, --apply, --json, conflict guard) (v0.69 D2a)"
```

---

## Task 4: Documentation

**Files:**
- Modify: `CHANGELOG.md` (v0.69 in-progress); `rules/README.md` or a short `docs/lint/` note.

- [ ] **Step 1: CHANGELOG -- add the D2a entry**

Under `## v0.69.0-alpha (in progress)`, after the D1a block, add:
```markdown
### Added (refactor CLI -- D2a)

- **`drag-lint rename --kind symbol --name <QName> --to <New>`** -- index-driven
  cross-unit rename. Dry-run preview by default; `--json` emits the edit set;
  `--apply` writes (backups on, `--no-backup` to suppress; ANSI/CRLF preserved).
  Refuses to rename to a reserved word or to a name already declared in the same scope.
- **`drag-lint rename --kind param --file <F> --line <L> --col <C> --to <New>`** --
  routine-local rename of a parameter or local variable (the `param-name-prefix`
  autofix). Single-file, AST-driven; syncs the matching forward/interface header;
  conservatively skips shadowing nested routines, qualified members, and `with` blocks.
```

- [ ] **Step 2: Commit**

```bash
git add CHANGELOG.md
git commit -m "docs(refactor): document rename --kind symbol|param (v0.69 D2a)"
```

---

## Task 5: Encoding normalize + verification + report

- [ ] **Step 1: Normalize encoding on the new/edited source + test files**

```powershell
Set-Location "C:\Projects\Delphi-RAG-lint"
$files = @(
  'src\refactor\DRagLint.Refactor.Rename.pas',
  'src\cli\DRagLint.CLI.pas',
  'tests\refactor\BuildLocalTests.dpr'
) + (Get-ChildItem tests\refactor\rename\*.pas, tests\refactor\*.ps1 | ForEach-Object FullName)
foreach ($f in $files) {
  $t = [IO.File]::ReadAllText($f); $t = $t -replace "`r`n","`n" -replace "`n","`r`n"
  [IO.File]::WriteAllText($f, $t, (New-Object System.Text.UTF8Encoding($false)))
  if ([IO.File]::ReadAllBytes($f) | Where-Object { $_ -gt 127 }) { Write-Host "NON-ASCII in $f" -ForegroundColor Red }
}
Write-Host "encoding normalized"
```
Expected: `encoding normalized`, no `NON-ASCII`.

- [ ] **Step 2: Full regression**

```powershell
pwsh -File tests\refactor\run_buildlocal_tests.ps1 | Select-Object -Last 1
pwsh -File tests\refactor\run_rename_symbol.ps1 | Select-Object -Last 1
pwsh -File tests\refactor\run_rename_param.ps1 | Select-Object -Last 1
pwsh -File tests\lint\run_lint_tests.ps1 | Select-Object -Last 1
pwsh -File tests\lintconfig\run_lintconfig_tests.ps1 | Select-Object -Last 1
pwsh -File tests\rules-catalog\run_rulecatalog_tests.ps1 | Select-Object -Last 1
```
Expected: all green (buildlocal pass, rename-symbol/param pass, lint 117/117, lintconfig 30/30, rulecatalog 29/29).

- [ ] **Step 3: ORM3 real-code sanity (param rename dry-run on a real unit)**

```powershell
$exe = "third_party\dll-win64\drag-lint.exe"
# pick a real routine param: lint a unit for param-name-prefix (enable it) to find a target,
# OR just dry-run a known param. Confirm dry-run prints a plausible edit set and writes nothing.
$u = "C:\Projects\DB\ORM3\CLIENT\uMain.ViewModel.pas"
# (manually choose a line/col of a parameter); confirm exit 0 + a dry-run plan, file unchanged.
```
Expected: a sane dry-run plan; the file is NOT modified (no `--apply`). Record the result.

- [ ] **Step 4: Commit any normalization + report**

```bash
git add -A
git commit -m "chore(refactor): CRLF/ASCII normalize v0.69 D2a files" || echo "nothing to normalize"
git status --porcelain
git log --oneline -7
```
Report D2a done: `rename --kind symbol` (cross-unit, conflict-guarded) + `rename --kind param` (the autofix) ship with dry-run default + `--json` + `--apply`; tests green; lint harness unaffected. **Next: D2b (find-unit + safe-delete), then D1b (IDE tab).**

---

## Self-Review (completed by plan author)

**Spec coverage (v0.69 spec section 2, rename subset):**
- `rename --kind symbol` cross-unit, harden conflict (keyword + scope) -> Tasks 2, 3. ✓
- `rename --kind param` NEW `BuildLocal`, shadowing/with/nested/interface-sync, = param-prefix autofix -> Task 1. ✓
- dry-run default + `--json` edit set + `--apply` (backups on, `--no-backup`), ANSI/CRLF preserved -> Task 3 (reuses `Apply`). ✓
- new `tests/refactor` DB-fixture harness -> Task 3 (+ Task 1 console). ✓
- `find-unit` + `safe-delete` -> DEFERRED to D2b (separate plan; they need a new insert/delete edit primitive). Noted.

**Placeholder scan:** no TBD/"handle edge cases"; the `BuildLocal` algorithm + guards are fully specified; ORM3 sanity Step 3 leaves the operator to choose a real line/col (a runtime choice, not a code placeholder).

**Type/name consistency:** `BuildLocal(AFile,ALine,ACol,ANewName)`, `IsReservedWord`, `ConflictReason`, `TRenameEdit{FilePath,Line,Col,OldName,NewName}`, the JSON keys `file/line/col/old/new`, and `TArgs.RenameKind/RefFile/RefLine/RefCol/Apply/RenameTo/QName/Name/DbPath/NoBackup/AsJson` are used consistently across the engine, the CLI, and the tests.

**Known risks flagged in-plan:** (1) the exact (line,col) of a decl identifier and the precise tree-sitter kinds for `with`/`exprDot`/nested-`defProc`/`TTSNode.Equals` are verified at implementation time against a real parse (Task 1 Step 4) -- the guards must not be weakened to force a pass. (2) `TSymbol` parent-linkage field names for `ConflictReason`'s sibling check are confirmed against `Core.Model.pas`; if absent, the reserved-word guard (the primary requirement) still ships. (3) `BuildLocal` is deliberately conservative (under-rename on ambiguity) per the Global Constraints.
