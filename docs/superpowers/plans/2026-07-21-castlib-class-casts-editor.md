# Class casts (`.castlib`) — Editor Half — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make class-to-class casts (e.g. `TPicture`/`TBitmap` → `TdxSmartGlyph`) definable in a shipped `.castlib` file and usable in the conversion editor — castability, Auto-Match, and `#link … : <CastName>` emission — without touching the DSL grammar.

**Architecture:** A new pure unit `ConvRules.CastLib.pas` parses the `.castlib` into `TCastDef` records and resolves a From/To type pair to a cast name. The editor loads the library once at startup and consults it as a THIRD castability path alongside the scalar classifier; the chosen cast's name goes into the existing free-string `#link` cast slot. The engine realization (DFM/pas/TODO) is out of scope here (separate handoff).

**Tech Stack:** Delphi 13 (RAD Studio 37), Win64, `dcc64`. Pure Object Pascal, no VCL in the parser, no engine linkage, no process spawn.

## Global Constraints

- **Design spec:** `docs/superpowers/specs/2026-07-21-castlib-class-casts-design.md` — the contract for the `.castlib` schema and the editor/engine split.
- **Encoding:** all `.pas` and `.castlib` files are strict 7-bit ASCII, CRLF. No Unicode, no BOM, no LF.
- **DocInsight:** every public type/function in a new unit gets a `///` spec-comment (`<summary>`, `<param>`, `<returns>`, `<remarks>` as applicable).
- **Purity:** `ConvRules.CastLib.pas` links only `System.*` (SysUtils, Classes, Generics.Collections, IOUtils). No `Vcl.*`, no `ConvRules.Engine`, no process spawn — so it is unit-tested headlessly.
- **No grammar change:** the `#link … : <name>` cast slot already carries a free string; class casts reuse it. Do NOT add a directive or change `ConvRules.Model`.
- **Regression gate:** the model suite must stay green (currently **134 pass / 0 fail / 1 skip**). New tests add to it.
- **Do NOT touch** `docs/examples/convrules/sample.rules` (the user's live test data).
- **Build (worktree):** editor `build_editor.bat`, tests `build_tests.bat` (scratchpad wrappers: `rsvars` → `cd` worktree dir → `dcc64 -B`), run from PowerShell `Start-Process -Wait` with output to a log; success = `BUILD_EXITCODE=0`, no `[dcc64] Error`. Run a test exe the same way; success = `model-tests: N pass / 0 fail`.

---

### Task 1: `ConvRules.CastLib.pas` — pure parser + resolver

**Files:**
- Create: `src/tools/convrules-editor/ConvRules.CastLib.pas`
- Modify: `src/tools/convrules-editor/tests/ConvRulesModelTests.dpr` (add unit to `uses`; add tests; register in run block)

**Interfaces:**
- Consumes: nothing (leaf unit).
- Produces:
  - `TCastDef = record Name: string; Accepts, Yields: TArray<string>; Dfm, Compat, PasTemplate, Todo: string; end;`
  - `function LoadCastLibText(const AText: string): TArray<TCastDef>;`
  - `function LoadCastLib(const APath: string): TArray<TCastDef>;`
  - `function ClassCastFor(const ADefs: TArray<TCastDef>; const AFrom, ATo: string): string;`

- [ ] **Step 1: Create the unit**

Create `src/tools/convrules-editor/ConvRules.CastLib.pas`:

```pascal
unit ConvRules.CastLib;

{ Pure parser + resolver for the shipped class-cast library (.castlib).

  A .castlib defines named CLASS casts (TPicture -> TdxSmartGlyph, ...) that the
  scalar TCastFn enum cannot express. Each cast lists the From types it accepts, the
  To type(s) it yields, and realization hints (dfm strategy, pas template, todo text)
  the ENGINE convert-apply consumes -- the editor only needs name/accepts/yields to
  decide castability and emit the '#link ... : <name>' suffix.

  Pure + headless (no VCL, no engine, no process spawn) so it is unit-tested against
  inline fixtures. }

interface

uses
  System.SysUtils, System.Classes, System.Generics.Collections;

type
  /// <summary>One named class cast from the .castlib.</summary>
  /// <remarks>Accepts/Yields are bare type names, matched case-insensitively by
  /// EXACT name (no ancestry walk in v1 -- list the concrete types). Dfm/Compat/
  /// PasTemplate/Todo are engine realization hints; the editor stores them verbatim
  /// and does not interpret them.</remarks>
  TCastDef = record
    Name       : string;
    Accepts    : TArray<string>;
    Yields     : TArray<string>;
    Dfm        : string;
    Compat     : string;
    PasTemplate: string;
    Todo       : string;
  end;

/// <summary>PURE: parse .castlib text into cast definitions. Tolerant -- skips blank
/// lines, '#' comments, and unknown keys; a malformed block (missing name or 'end')
/// is dropped without aborting the rest of the file.</summary>
function LoadCastLibText(const AText: string): TArray<TCastDef>;

/// <summary>Read + parse a .castlib file. Returns [] when APath is empty or missing
/// (class casts simply unavailable -- never raises).</summary>
/// <param name="APath">Absolute path to the .castlib, or '' for none.</param>
function LoadCastLib(const APath: string): TArray<TCastDef>;

/// <summary>The name of the class cast whose Accepts contains AFrom AND Yields
/// contains ATo (case-insensitive), or '' when no cast bridges the pair.</summary>
function ClassCastFor(const ADefs: TArray<TCastDef>; const AFrom, ATo: string): string;

implementation

uses
  System.IOUtils;

{ Split 'a, b ,c' -> ['a','b','c'], trimmed, empties dropped. }
function SplitList(const AValue: string): TArray<string>;
var
  parts: TArray<string>;
  p    : string;
  list : TList<string>;
begin
  list := TList<string>.Create;
  try
    parts := AValue.Split([',']);
    for p in parts do
      if Trim(p) <> '' then list.Add(Trim(p));
    Result := list.ToArray;
  finally
    list.Free;
  end;
end;

{ Strip one layer of surrounding single quotes from a value ('x' -> x). }
function Unquote(const AValue: string): string;
begin
  Result := Trim(AValue);
  if (Length(Result) >= 2) and (Result[1] = '''') and (Result[Length(Result)] = '''') then
    Result := Copy(Result, 2, Length(Result) - 2);
end;

{ Case-insensitive membership over a bare-name array. }
function Has(const AArr: TArray<string>; const AName: string): Boolean;
var s: string;
begin
  for s in AArr do
    if SameText(s, AName) then Exit(True);
  Result := False;
end;

function LoadCastLibText(const AText: string): TArray<TCastDef>;
var
  SL   : TStringList;
  i, sp: Integer;
  Line, Key, Val: string;
  cur  : TCastDef;
  inBlk: Boolean;
  defs : TList<TCastDef>;
begin
  defs := TList<TCastDef>.Create;
  SL := TStringList.Create;
  try
    SL.Text := AText;
    inBlk := False;
    cur := Default(TCastDef);
    for i := 0 to SL.Count - 1 do
    begin
      Line := Trim(SL[i]);
      if (Line = '') or Line.StartsWith('#') then Continue;   // blank / comment
      sp := Pos(' ', Line);
      if sp > 0 then
      begin
        Key := LowerCase(Copy(Line, 1, sp - 1));
        Val := Trim(Copy(Line, sp + 1, MaxInt));
      end
      else
      begin
        Key := LowerCase(Line);
        Val := '';
      end;

      if Key = 'cast' then
      begin
        // a new block; a prior unclosed block (no 'end') is discarded
        inBlk := True;
        cur := Default(TCastDef);
        cur.Name := Val;
      end
      else if Key = 'end' then
      begin
        if inBlk and (cur.Name <> '') then defs.Add(cur);
        inBlk := False;
        cur := Default(TCastDef);
      end
      else if inBlk then
      begin
        if      Key = 'accepts' then cur.Accepts := SplitList(Val)
        else if Key = 'yields'  then cur.Yields := SplitList(Val)
        else if Key = 'dfm'     then cur.Dfm := Val
        else if Key = 'compat'  then cur.Compat := Val
        else if Key = 'pas'     then cur.PasTemplate := Unquote(Val)
        else if Key = 'todo'    then cur.Todo := Unquote(Val);
        // unknown keys tolerated (skipped)
      end;
    end;
    Result := defs.ToArray;
  finally
    SL.Free;
    defs.Free;
  end;
end;

function LoadCastLib(const APath: string): TArray<TCastDef>;
begin
  if (APath = '') or not TFile.Exists(APath) then Exit(nil);
  Result := LoadCastLibText(TFile.ReadAllText(APath));
end;

function ClassCastFor(const ADefs: TArray<TCastDef>; const AFrom, ATo: string): string;
var
  d: TCastDef;
begin
  Result := '';
  for d in ADefs do
    if Has(d.Accepts, AFrom) and Has(d.Yields, ATo) then Exit(d.Name);
end;

end.
```

- [ ] **Step 2: Add the unit + tests to the test runner**

In `src/tools/convrules-editor/tests/ConvRulesModelTests.dpr`, add to the `uses` clause (after `ConvRules.Casts in '..\ConvRules.Casts.pas',`):

```pascal
  ConvRules.CastLib in '..\ConvRules.CastLib.pas',
```

Add these three test procedures before the final `begin` block:

```pascal
{ .castlib parse: a well-formed block yields one cast with multi-type accepts, the
  single yield, and the unquoted pas/todo templates. }
procedure TestCastLibParse;
const
  SRC =
    '# a comment'#13#10 +
    'cast AssignGraphic'#13#10 +
    '  accepts TPicture, TBitmap, TGraphic'#13#10 +
    '  yields  TdxSmartGlyph'#13#10 +
    '  dfm     keep-bytes-if-compatible'#13#10 +
    '  pas     ''{dst}.Assign({src});'''#13#10 +
    '  todo    ''do it by hand'''#13#10 +
    'end'#13#10;
var
  D: TArray<TCastDef>;
begin
  D := LoadCastLibText(SRC);
  Check('castlib.count', Length(D) = 1, IntToStr(Length(D)));
  if Length(D) = 0 then Exit;
  Check('castlib.name',   D[0].Name = 'AssignGraphic', D[0].Name);
  Check('castlib.accepts.count', Length(D[0].Accepts) = 3, IntToStr(Length(D[0].Accepts)));
  Check('castlib.accepts.bitmap', Contains(D[0].Accepts, 'TBitmap'));
  Check('castlib.yields',  (Length(D[0].Yields) = 1) and (D[0].Yields[0] = 'TdxSmartGlyph'));
  Check('castlib.dfm',     D[0].Dfm = 'keep-bytes-if-compatible', D[0].Dfm);
  Check('castlib.pas',     D[0].PasTemplate = '{dst}.Assign({src});', D[0].PasTemplate);
  Check('castlib.todo',    D[0].Todo = 'do it by hand', D[0].Todo);
end;

{ Tolerance: blank lines, comments, unknown keys, and a malformed (unclosed) block
  must not stop the good block from parsing. }
procedure TestCastLibTolerant;
const
  SRC =
    'cast Broken'#13#10 +          // no 'end' -> discarded when the next 'cast' starts
    '  accepts TFoo'#13#10 +
    'cast Good'#13#10 +
    ''#13#10 +
    '  # inline comment line'#13#10 +
    '  accepts TA, TB'#13#10 +
    '  yields  TC'#13#10 +
    '  boguskey whatever here'#13#10 +   // unknown key tolerated
    'end'#13#10;
var
  D: TArray<TCastDef>;
begin
  D := LoadCastLibText(SRC);
  Check('castlib.tolerant.count', Length(D) = 1, IntToStr(Length(D)));
  if Length(D) = 0 then Exit;
  Check('castlib.tolerant.name', D[0].Name = 'Good', D[0].Name);
  Check('castlib.tolerant.yields', (Length(D[0].Yields) = 1) and (D[0].Yields[0] = 'TC'));
end;

{ ClassCastFor: matches a pair whose From is accepted AND To is yielded, case-
  insensitively; returns '' for an unbridged pair. }
procedure TestClassCastFor;
var
  D: TArray<TCastDef>;
begin
  D := LoadCastLibText(
    'cast AssignGraphic'#13#10 +
    '  accepts TPicture, TBitmap, TGraphic'#13#10 +
    '  yields  TdxSmartGlyph'#13#10 +
    'end'#13#10);
  Check('castfor.picture',   ClassCastFor(D, 'TPicture', 'TdxSmartGlyph') = 'AssignGraphic');
  Check('castfor.bitmap',    ClassCastFor(D, 'TBitmap',  'TdxSmartGlyph') = 'AssignGraphic');
  Check('castfor.ci',        ClassCastFor(D, 'tpicture', 'tdxsmartglyph') = 'AssignGraphic');
  Check('castfor.wrongto',   ClassCastFor(D, 'TPicture', 'TStrings') = '', 'should be blocked');
  Check('castfor.wrongfrom', ClassCastFor(D, 'TFont',    'TdxSmartGlyph') = '', 'should be blocked');
end;
```

Register them in the run block (after `TestCastClassifier;`):

```pascal
    TestCastLibParse;
    TestCastLibTolerant;
    TestClassCastFor;
```

- [ ] **Step 3: Build the test runner and verify the new tests FAIL first is not applicable — verify they PASS (implementation written in Step 1)**

Because Delphi compiles the whole unit, write-then-test is one build. Build the tests:

Run (PowerShell):
```powershell
$sp = "C:\TEMP\claude\c--Projects-Delphi-RAG-Lint-Graph\79435088-f711-47e7-93e7-031f83feea7d\scratchpad"
Start-Process cmd.exe -ArgumentList "/c","`"$sp\build_tests.bat`"" -RedirectStandardOutput "$sp\t1.log" -RedirectStandardError "$sp\t1.err" -NoNewWindow -Wait
Select-String -Path "$sp\t1.log" -Pattern 'BUILD_EXITCODE|Error|Fatal'
```
Expected: `BUILD_EXITCODE=0`, no `[dcc64] Error`.

- [ ] **Step 4: Run the suite and confirm the CastLib tests pass**

Run (PowerShell):
```powershell
$exe = "C:\Projects\Delphi-RAG-lint-converter\src\tools\convrules-editor\tests\ConvRulesModelTests.exe"
Start-Process $exe -RedirectStandardOutput "$sp\r1.log" -NoNewWindow -Wait
Get-Content "$sp\r1.log" | Select-String -Pattern 'castlib|castfor|model-tests:'
```
Expected: all `castlib.*` and `castfor.*` lines are `PASS`; `model-tests: N pass / 0 fail / …` (N grew by the new checks).

- [ ] **Step 5: Commit**

```bash
git add src/tools/convrules-editor/ConvRules.CastLib.pas src/tools/convrules-editor/tests/ConvRulesModelTests.dpr
git commit -m "feat(convrules-editor): ConvRules.CastLib -- pure .castlib parser + ClassCastFor"
```

---

### Task 2: Ship `casts.castlib` + resolve/load it in the editor

**Files:**
- Create: `docs/examples/convrules/casts.castlib`
- Modify: `src/tools/convrules-editor/ConvRulesEditor.dpr` (add `ResolveCastLib` + set `GEditorCastLib`)
- Modify: `src/tools/convrules-editor/ConvRules.MainForm.pas` (add `GEditorCastLib` global + `FCastDefs` field; load in constructor; add `ConvRules.CastLib` to `uses`)
- Modify: `src/tools/convrules-editor/tests/ConvRulesModelTests.dpr` (add `TestCastLibFile` reading the shipped file)

**Interfaces:**
- Consumes: `LoadCastLib`, `TCastDef` (Task 1).
- Produces: `GEditorCastLib: string` global; `FCastDefs: TArray<TCastDef>` form field (used by Task 3).

- [ ] **Step 1: Create the shipped library**

Create `docs/examples/convrules/casts.castlib` (ASCII, CRLF):

```
# Shipped class-cast library for the conversion editor.
# Each 'cast <Name> ... end' block defines a class-to-class cast the DSL names as the
# '#link To <- From : <Name>' suffix. Realization hints (dfm/compat/pas/todo) are
# consumed by the engine convert-apply; the editor uses name/accepts/yields.
# Strict 7-bit ASCII, CRLF.

cast AssignGraphic
  accepts TPicture, TBitmap, TGraphic, TPngImage, TIcon
  yields  TdxSmartGlyph
  dfm     keep-bytes-if-compatible
  compat  png, bmp
  pas     '{dst}.Assign({src});'
  todo    'transfer image from {src} by hand (TBitmap/TPicture -> TdxSmartGlyph)'
end
```

- [ ] **Step 2: Add the `GEditorCastLib` global + `FCastDefs` field + load**

In `src/tools/convrules-editor/ConvRules.MainForm.pas`:

(a) Add `ConvRules.CastLib` to the `interface` `uses` clause (append to the line ending `ConvRules.Platform;`):
```pascal
  ConvRules.Model, ConvRules.Casts, ConvRules.Engine, ConvRules.Platform, ConvRules.CastLib;
```

(b) Add the form field (in the `private` fields, after `FSurfaceMinVis: string;`):
```pascal
    FCastDefs : TArray<TCastDef>;     // shipped class-cast library (.castlib)
```

(c) Add the global (in the `var` section, after `GEditorProjectDb: string = '';`):
```pascal
  { Path to the shipped class-cast library (.castlib); '' = class casts unavailable
    (scalar-only, today's behavior). Resolved + set by the .dpr before CreateForm. }
  GEditorCastLib: string = '';
```

(d) Load it in the constructor (after `FSurfaceMinVis := 'published';`):
```pascal
  FCastDefs := LoadCastLib(GEditorCastLib);   // [] when no .castlib is found
```

- [ ] **Step 3: Resolve the path in the `.dpr`**

In `src/tools/convrules-editor/ConvRulesEditor.dpr`, first add the unit to the `uses` clause (after `ConvRules.Casts in 'ConvRules.Casts.pas',`) so `dcc64` maps its source path explicitly:
```pascal
  ConvRules.CastLib in 'ConvRules.CastLib.pas',
```

Then add after `ResolveDragLintExe`:

```pascal
{ Resolve the shipped .castlib: next to this editor (co-deployed), else the repo
  default under docs\examples\convrules, else '' (class casts unavailable). }
function ResolveCastLib: string;
var
  Dir: string;
begin
  Dir := ExtractFilePath(ParamStr(0));
  Result := TPath.Combine(Dir, 'casts.castlib');                         // (1) beside exe
  if TFile.Exists(Result) then Exit;
  Result := TPath.GetFullPath(TPath.Combine(Dir,                         // (2) repo docs
    '..\..\docs\examples\convrules\casts.castlib'));
  if TFile.Exists(Result) then Exit;
  Result := '';                                                          // (3) none
end;
```

Set the global before `Application.CreateForm` (after `GEditorProjectDb := ProjectDb;`):
```pascal
  GEditorCastLib := ResolveCastLib;
```

- [ ] **Step 4: Add a file-level test for the shipped library**

In `ConvRulesModelTests.dpr`, add this test (after `TestClassCastFor`) — it reads the ACTUAL shipped file via `LoadCastLib`:

```pascal
{ The shipped casts.castlib parses and provides AssignGraphic. Skipped (not failed)
  when the file is not found from the test exe (lean checkout). }
procedure TestCastLibFile;
var
  P: string;
  D: TArray<TCastDef>;
begin
  // test exe lives at <root>\src\tools\convrules-editor\tests\ -> climb 4 to root.
  P := TPath.GetFullPath(TPath.Combine(ExtractFilePath(ParamStr(0)),
    '..\..\..\..\docs\examples\convrules\casts.castlib'));
  if not TFile.Exists(P) then
  begin
    Skip('castlib.file', 'casts.castlib not found: ' + P);
    Exit;
  end;
  D := LoadCastLib(P);
  Check('castlib.file.nonempty', Length(D) > 0, IntToStr(Length(D)));
  Check('castlib.file.assigngraphic',
    ClassCastFor(D, 'TPicture', 'TdxSmartGlyph') = 'AssignGraphic',
    'AssignGraphic (TPicture->TdxSmartGlyph) not resolved from the shipped file');
end;
```

Register it in the run block (after `TestClassCastFor;`):
```pascal
    TestCastLibFile;
```

- [ ] **Step 5: Stage casts.castlib beside the deployed exe (build wrapper)**

Append to the editor build wrapper `build_editor.bat` (scratchpad), after the exe copy line:
```bat
if exist "C:\Projects\Delphi-RAG-lint-converter\docs\examples\convrules\casts.castlib" copy /Y "C:\Projects\Delphi-RAG-lint-converter\docs\examples\convrules\casts.castlib" "C:\Projects\Delphi-RAG-lint-converter\third_party\dll-win64\casts.castlib" >NUL
```

- [ ] **Step 6: Build editor + tests, run suite**

Run (PowerShell):
```powershell
$sp = "C:\TEMP\claude\c--Projects-Delphi-RAG-Lint-Graph\79435088-f711-47e7-93e7-031f83feea7d\scratchpad"
Start-Process cmd.exe -ArgumentList "/c","`"$sp\build_editor.bat`"" -RedirectStandardOutput "$sp\e2.log" -NoNewWindow -Wait
Select-String -Path "$sp\e2.log" -Pattern 'BUILD_EXITCODE|STAGED|Error|Fatal'
Start-Process cmd.exe -ArgumentList "/c","`"$sp\build_tests.bat`"" -RedirectStandardOutput "$sp\t2.log" -NoNewWindow -Wait
$exe = "C:\Projects\Delphi-RAG-lint-converter\src\tools\convrules-editor\tests\ConvRulesModelTests.exe"
Start-Process $exe -RedirectStandardOutput "$sp\r2.log" -NoNewWindow -Wait
Get-Content "$sp\r2.log" | Select-String -Pattern 'castlib.file|model-tests:'
```
Expected: editor `BUILD_EXITCODE=0`; `castlib.file.*` PASS; `model-tests: N pass / 0 fail`.

- [ ] **Step 7: Commit**

```bash
git add docs/examples/convrules/casts.castlib src/tools/convrules-editor/ConvRulesEditor.dpr src/tools/convrules-editor/ConvRules.MainForm.pas src/tools/convrules-editor/tests/ConvRulesModelTests.dpr
git commit -m "feat(convrules-editor): ship casts.castlib (AssignGraphic) + resolve/load it"
```

---

### Task 3: Wire class casts into the editor's castability + emission

**Files:**
- Modify: `src/tools/convrules-editor/ConvRules.MainForm.pas` (add `ClassCastName` + `CanCast`; extend `AssignLink`; swap `IsCastable` gates in `DoAssign` + `DoAutoMatch`)
- Modify: `src/tools/convrules-editor/tests/ConvRulesModelTests.dpr` (model round-trip test for a class-cast link name)

**Interfaces:**
- Consumes: `FCastDefs` (Task 2), `ClassCastFor` (Task 1), `IsCastable`/`ValidCasts`/`SameFamily`/`CastFnName` (existing `ConvRules.Casts`).
- Produces: editor behavior only (no new public symbols).

- [ ] **Step 1: Add the two helper method declarations**

In `ConvRules.MainForm.pas`, in the `private` method list (after `function LeafWritable(...)`):
```pascal
    function  ClassCastName(const AFromType, AToType: string): string;
    function  CanCast(const AFromType, AToType: string): Boolean;
```

- [ ] **Step 2: Implement the two helpers**

Add near `LeafWritable`'s implementation (after its `end;`):
```pascal
{ The library class-cast name bridging AFromType -> AToType, or '' if none. }
function TConvRulesForm.ClassCastName(const AFromType, AToType: string): string;
begin
  Result := ClassCastFor(FCastDefs, AFromType, AToType);
end;

{ Castable when the scalar classifier allows it OR a library class cast bridges it. }
function TConvRulesForm.CanCast(const AFromType, AToType: string): Boolean;
begin
  Result := IsCastable(AFromType, AToType) or (ClassCastName(AFromType, AToType) <> '');
end;
```

- [ ] **Step 3: Teach `AssignLink` to pick a class cast**

In `AssignLink`, replace the cast-selection `else` block:
```pascal
  else
  begin
    casts := ValidCasts(AFromType, AToType);
    Link.Cast := '';
    for c := Low(TCastFn) to High(TCastFn) do
      if c in casts then begin Link.Cast := CastFnName(c); Break; end;
  end;
```
with:
```pascal
  else
  begin
    casts := ValidCasts(AFromType, AToType);
    Link.Cast := '';
    for c := Low(TCastFn) to High(TCastFn) do
      if c in casts then begin Link.Cast := CastFnName(c); Break; end;
    if Link.Cast = '' then
      Link.Cast := ClassCastName(AFromType, AToType);   // library class cast (e.g. AssignGraphic)
  end;
```

- [ ] **Step 4: Swap the castability GATES from `IsCastable` to `CanCast`**

In `DoAssign`, change:
```pascal
  if not IsCastable(fromType, toType) then
```
to:
```pascal
  if not CanCast(fromType, toType) then
```

In `DoAutoMatch`, there are two candidate checks `if IsCastable(fT, tT) then` (PASS 1 exact-path and PASS 2 last-segment). Change BOTH to:
```pascal
        if CanCast(fT, tT) then
```
(Auto-Match already requires an exact-path or globally-unique-name match, so this only enables a class cast on a same-named, type-compatible pair — the conservative bar from the spec.)

- [ ] **Step 5: Build the editor and verify it compiles**

Run (PowerShell):
```powershell
$sp = "C:\TEMP\claude\c--Projects-Delphi-RAG-Lint-Graph\79435088-f711-47e7-93e7-031f83feea7d\scratchpad"
Start-Process cmd.exe -ArgumentList "/c","`"$sp\build_editor.bat`"" -RedirectStandardOutput "$sp\e3.log" -NoNewWindow -Wait
Select-String -Path "$sp\e3.log" -Pattern 'BUILD_EXITCODE|STAGED|Error|Fatal'
```
Expected: `BUILD_EXITCODE=0`, no `[dcc64] Error`.

- [ ] **Step 6: Add a model round-trip test proving the DSL carries a class-cast name**

In `ConvRulesModelTests.dpr`, add (after `TestCastLibFile`):
```pascal
{ A #link with a class-cast NAME suffix (a single identifier) parses into Cast and
  re-emits byte-faithfully -- the existing DSL slot carries library cast names with no
  grammar change. }
procedure TestClassCastLinkRoundTrip;
var
  Book: TRuleBook;
begin
  Book := TRuleBook.Create;
  try
    Book.LoadFromString('#link Glyph <- Glyph : AssignGraphic'#13#10);
    Check('classcast.link.cast', Book.Nodes[0].Cast = 'AssignGraphic', Book.Nodes[0].Cast);
    Check('classcast.link.from', Book.Nodes[0].LinkFrom = 'Glyph', Book.Nodes[0].LinkFrom);
    Check('classcast.link.reemit',
      Book.Nodes[0].Emit = '#link Glyph <- Glyph : AssignGraphic', Book.Nodes[0].Emit);
  finally
    Book.Free;
  end;
end;
```
Register it in the run block (after `TestCastLibFile;`):
```pascal
    TestClassCastLinkRoundTrip;
```

- [ ] **Step 7: Build tests, run suite**

Run (PowerShell):
```powershell
Start-Process cmd.exe -ArgumentList "/c","`"$sp\build_tests.bat`"" -RedirectStandardOutput "$sp\t3.log" -NoNewWindow -Wait
Select-String -Path "$sp\t3.log" -Pattern 'BUILD_EXITCODE|Error|Fatal'
$exe = "C:\Projects\Delphi-RAG-lint-converter\src\tools\convrules-editor\tests\ConvRulesModelTests.exe"
Start-Process $exe -RedirectStandardOutput "$sp\r3.log" -NoNewWindow -Wait
Get-Content "$sp\r3.log" | Select-String -Pattern 'classcast|model-tests:'
```
Expected: `classcast.*` PASS; `model-tests: N pass / 0 fail`.

- [ ] **Step 8: Commit**

```bash
git add src/tools/convrules-editor/ConvRules.MainForm.pas src/tools/convrules-editor/tests/ConvRulesModelTests.dpr
git commit -m "feat(convrules-editor): offer + emit library class casts (AssignGraphic) via CanCast"
```

---

## Manual verification (after Task 3)

Launch the staged editor and confirm the class cast is offered end-to-end:
1. `C:\Projects\Delphi-RAG-lint-converter\third_party\dll-win64\ConvRulesEditor.exe`
2. New Conversion with a From class exposing a `TBitmap`/`TPicture` glyph property and To = a control whose glyph is `TdxSmartGlyph` (e.g. via the pickers). Select the From glyph row + the To glyph leaf, click Assign.
3. Expected: the link is NOT blocked; the grid's cast column shows `AssignGraphic`; the Raw DSL tab shows `#link … : AssignGraphic`.

(Realization — the actual DFM/pas output — is the engine half and not exercised here.)

## Out of scope (engine handoff — separate spec)

`convert-apply` realization: DFM byte-carry / pas `Assign` insertion / TODO marker, and the `{src}`-sourcing decision. To be written up as an engine spec (mirroring the proptree/2 handoff) and delivered on `main`. `convert-validate` must also accept a known library cast name so authored links validate.
