# Converter Editor -- Unit-Replacement Rules Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give the converter editor first-class authoring of unit-replacement rules (`#use` / `#useswap`) -- standalone, one-to-many, and auto-derived from `#convert` blocks with library-wide dedup.

**Architecture:** Two new DSL directives (`#useswap` is sugar over the atomic `#use`/`#unuse`). Pure model + a new pure normalization/derive unit carry all logic and are TDD-covered; the engine parser learns to *recognize* the directives (no apply) so Save-validate stays green; the UI adds a Unit Rules tab that writes through the model.

**Tech Stack:** Delphi 13 / RAD Studio 37 (Win64), plain VCL (no DevExpress), self-contained console test runner (no DUnitX), PowerShell autotests, drag-lint CLI.

## Global Constraints

- Worktree: `C:\Projects\Delphi-RAG-lint-converter`, branch `feat/converter-editor`. ALL work here.
- `.pas` files: strict 7-bit ASCII, CRLF. Verify after every write. No Unicode, no BOM, no LF.
- The ONLY drag-lint core file touched: `src/report/DRagLint.Convert.Rules.pas` (additive parser recognition). Everything else under `src/tools/convrules-editor/` or `docs/converter/`.
- Build recipe = the `delphi-build` skill: 3-line rsvars+cd+msbuild/dcc `.bat` run via PowerShell `Start-Process -Wait` with output to a log; success = `BUILD_EXITCODE=0` and no `[dcc] Error`. Do NOT use the MCP build tool; do NOT run `cmd.exe /c build.bat` from the Bash tool.
- Existing build bats: editor `build/_build_convrules_editor.bat`; editor tests `build/_build_convrules_tests.bat`; CLI `build/build_draglint_win64.bat`.
- A running `ConvRulesEditor.exe` or `drag-lint.exe`/`drag_lint_graph.exe` locks its own file (F2039 / "used by another process") -- `Stop-Process` the orphan before rebuilding.
- `#useswap` grammar: `#useswap <Old> -> <New1>[, <New2> ...]` (one-to-many). `#use` grammar: `#use <unit>`.
- Normalization ("no doubles"): ADD = every `#use` + every `#useswap` right-side + every `#convert` trailing `, unit`. REMOVE = every `#unuse` + every `#useswap` left-side. Dedup case-insensitive; a unit in both -> ADD wins (listed as a conflict).

---

## Task 0: Baseline (no commit)

**Files:** none changed.

- [ ] **Step 1: Build the editor tests and run them (green baseline).**

Write `build/_run_baseline.bat` is unnecessary -- use the existing bats. Build the test runner:
Run (PowerShell): `Start-Process -FilePath "cmd.exe" -ArgumentList '/c','build\_build_convrules_tests.bat' -WorkingDirectory 'C:\Projects\Delphi-RAG-lint-converter' -Wait -RedirectStandardOutput 'C:\TEMP\claude\base_tests_build.log' -RedirectStandardError 'C:\TEMP\claude\base_tests_err.log'`
Then run the produced `ConvRulesModelTests.exe` and confirm the summary line reads `... FAIL 0 ...`.
Expected: build `BUILD_EXITCODE=0`; test run `FAIL 0` (some SKIP allowed).

- [ ] **Step 2: Build the editor and the CLI (confirm the worktree compiles).**

Build `build/_build_convrules_editor.bat` and `build/build_draglint_win64.bat` the same way (separate logs). Confirm both `BUILD_EXITCODE=0`, no `[dcc] Error`.
Expected: both succeed. If any fails, STOP and report -- do not edit code on a red baseline.

---

## Task 1: Engine parser recognizes `#use` / `#useswap`

**Files:**
- Modify: `src/report/DRagLint.Convert.Rules.pas` (enum `TRuleKind` ~line 47; parse loop, insert arms after the `#unuse` arm ~line 299; grammar doc-comment ~line 110-120)
- Test: `tests/autotest/run_convert_rules.ps1`
- Rebuild+deploy: `third_party/dll-win64/drag-lint.exe`

**Interfaces:**
- Consumes: existing `Directive(key, out arg): Boolean`, `SplitHeadAndUnits(rhs, out head, out units)`, `ARROW_MIGRATE = ' -> '`, `AddRule`, `Default(TConversionRule)`.
- Produces: `TRuleKind` gains `rkUse, rkUseSwap`. `rkUse` populates `UnitName`. `rkUseSwap` populates `UnitName` (Old) + `UnitsAdd` (the New list). Neither is path-validated (joins the `rkUnuse`/`rkMigrate` no-check family).

- [ ] **Step 1: Add failing autotest cases.**

Append to `tests/autotest/run_convert_rules.ps1` a fixture + assertions (match the script's existing pattern for writing a temp `.rules` and asserting `convert-validate` exit code). The fixture text:
```
#use imcFOLDERS
#useswap FOLDERDEF -> imcFOLDERS
#useswap ovcTable -> cxGrid, cxGridDBTableView
```
Assert: `drag-lint convert-validate --rules <fixture>` (no `--from/--to`, parse-only) exits **0** and prints `OK`. Add a second assertion that `convert-validate --print-parsed` reports `parsed 3 rule(s)` (or the script's equivalent count check).

- [ ] **Step 2: Run the autotest against the CURRENT exe -- verify it FAILS.**

Run (PowerShell): `powershell -File tests\autotest\run_convert_rules.ps1` from the worktree.
Expected: FAIL -- the new cases report `unknown directive: #use` and a non-zero exit (current exe rejects the directives).

- [ ] **Step 3: Add the two rule kinds.**

In `src/report/DRagLint.Convert.Rules.pas`, change the enum (line ~47):
```pascal
  TRuleKind = (rkUnuse, rkRemove, rkMigrate, rkConvert, rkLink, rkDefault, rkNote, rkPcre, rkIgnore, rkUse, rkUseSwap);
```
Update the `TRuleKind` doc-comment `<remarks>` (line ~37-46) with two sentences:
`rkUse=#use (ADD a unit to the uses clause -- companion to #unuse). rkUseSwap=#useswap (replace Old with one-or-more New units; UnitName=Old, UnitsAdd=the New list; canonically #unuse Old + #use New...).`

- [ ] **Step 4: Add the parse arms.**

Insert immediately AFTER the `#unuse` arm's closing `end` (the block that ends ~line 299, before `else if Directive('#remove', ...)`). Order: `#useswap` before `#use` is not required (the `Directive` helper's trailing-whitespace guard prevents `#use` from matching `#useswap`), but keep both grouped with `#unuse`:
```pascal
      else if Directive('#useswap', Arg) then
      begin
        R.Kind:= rkUseSwap;
        ArrPos:= Pos(ARROW_MIGRATE, Arg);
        if ArrPos > 0 then
        begin
          R.UnitName:= Trim(Copy(Arg, 1, ArrPos - 1));            // Old
          Rhs       := Trim(Copy(Arg, ArrPos + Length(ARROW_MIGRATE), MaxInt));
        end
        else begin R.UnitName:= Trim(Arg); Rhs:= ''; end;
        // Rhs is a pure comma list of New units (no head/units distinction).
        SplitHeadAndUnits(Rhs, Head, Units);                      // Head='New1', Units=['New2'...]
        if Head <> '' then R.UnitsAdd:= Concat([Head], Units)
        else               R.UnitsAdd:= Units;
        AddRule(R);
      end
      else if Directive('#use', Arg) then
      begin
        R.Kind    := rkUse;
        R.UnitName:= Arg;
        AddRule(R);
      end
```

- [ ] **Step 5: Add the grammar doc line.**

In the `ParseConversionRules` `<remarks>` (line ~110-120), add after the `#unuse` mention:
`'#use &lt;unit&gt;' (add a unit); '#useswap &lt;Old&gt; -&gt; &lt;New1&gt; [, &lt;New2&gt; ...]' (replace a unit with one-or-more units);`

- [ ] **Step 6: Confirm ASCII/CRLF, rebuild + deploy the CLI.**

Verify the edited file is ASCII+CRLF. Build `build/build_draglint_win64.bat` (PowerShell Start-Process, log). Confirm `BUILD_EXITCODE=0`, no `[dcc] Error`. Copy the built `drag-lint.exe` to `third_party/dll-win64/drag-lint.exe` (the deploy step the build bat may already do -- verify the file mtime updated).

- [ ] **Step 7: Run the autotest -- verify it PASSES.**

Run: `powershell -File tests\autotest\run_convert_rules.ps1`.
Expected: PASS -- new cases validate `OK`, exit 0; all pre-existing cases still pass.

- [ ] **Step 8: Commit.**
```bash
git add src/report/DRagLint.Convert.Rules.pas tests/autotest/run_convert_rules.ps1
git commit -m "feat(convert): recognize #use/#useswap directives (parse-only, no apply)

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```
(Deploy of `third_party/dll-win64/drag-lint.exe` is a build artifact -- add it too if the repo tracks it, else leave untracked.)

---

## Task 2: Editor model -- `#use` / `#useswap` nodes

**Files:**
- Modify: `src/tools/convrules-editor/ConvRules.Model.pas` (enum `TRuleNodeKind`; `TRuleNode` fields + `Emit`; `TRuleBook.ParseLine`; add `TRuleBook.UnitNodes`)
- Test: `src/tools/convrules-editor/tests/ConvRulesModelTests.dpr`

**Interfaces:**
- Consumes: existing `TRuleNode`, `TRuleBook`, `ARROW_MIGRATE`, `SplitArrow` (local to ParseLine).
- Produces: `TRuleNodeKind` gains `rnkUse, rnkUseSwap`. `TRuleNode` gains `UseUnit: string` (rnkUse), `SwapOld: string` + `SwapNew: TArray<string>` (rnkUseSwap). `TRuleBook.UnitNodes: TArray<TRuleNode>` returns all rnkUse/rnkUnuse/rnkUseSwap nodes in file order.

- [ ] **Step 1: Write the failing tests.**

Add to `tests/ConvRulesModelTests.dpr` a `procedure TestUnitDirectives;` and call it from the main body (next to `TestParseKinds`). Test code:
```pascal
procedure TestUnitDirectives;
const
  SRC =
    '#use imcFOLDERS'#13#10 +
    '#useswap FOLDERDEF -> imcFOLDERS'#13#10 +
    '#useswap ovcTable -> cxGrid, cxGridDBTableView'#13#10;
var
  Book: TRuleBook;
  Units: TArray<TRuleNode>;
begin
  Book := TRuleBook.Create;
  try
    Book.LoadFromString(SRC);
    Check('unit.use.kind',     Book.Nodes[0].Kind = rnkUse);
    Check('unit.use.unit',     Book.Nodes[0].UseUnit = 'imcFOLDERS', Book.Nodes[0].UseUnit);
    Check('unit.swap.kind',    Book.Nodes[1].Kind = rnkUseSwap);
    Check('unit.swap.old',     Book.Nodes[1].SwapOld = 'FOLDERDEF', Book.Nodes[1].SwapOld);
    Check('unit.swap.new1',    (Length(Book.Nodes[1].SwapNew) = 1) and (Book.Nodes[1].SwapNew[0] = 'imcFOLDERS'));
    Check('unit.swap.multi',   (Length(Book.Nodes[2].SwapNew) = 2) and (Book.Nodes[2].SwapNew[0] = 'cxGrid') and (Book.Nodes[2].SwapNew[1] = 'cxGridDBTableView'));
    Check('unit.roundtrip',    Book.SaveToString = SRC, Format('got %d want %d', [Length(Book.SaveToString), Length(SRC)]));
    Units := Book.UnitNodes;
    Check('unit.gather.count', Length(Units) = 3, IntToStr(Length(Units)));
  finally
    Book.Free;
  end;
end;
```

- [ ] **Step 2: Build + run the tests -- verify FAIL.**

Build `build/_build_convrules_tests.bat`; run `ConvRulesModelTests.exe`.
Expected: compile FAILS (`rnkUse` undeclared) -- that is the failing state.

- [ ] **Step 3: Extend the enum and node fields.**

In `ConvRules.Model.pas`, enum (line ~24-37) add before `rnkUnknown`:
```pascal
    rnkUse,        // #use unit  (add a unit to uses)
    rnkUseSwap,    // #useswap Old -> New1[, New2 ...]
```
In `TRuleNode` (after the rnkUnuse field, ~line 71):
```pascal
    // rnkUse
    UseUnit: string;
    // rnkUseSwap
    SwapOld: string;
    SwapNew: TArray<string>;
```

- [ ] **Step 4: Add parse arms in `ParseLine`.**

Insert after the `#unuse` arm (ends ~line 330), before the `#migrate` arm:
```pascal
    if Dir = '#useswap' then
    begin
      N.Kind := rnkUseSwap;
      if SplitArrow(Body, ARROW_MIGRATE, N.SwapOld, Rest) then
      begin
        var Parts: TArray<string> := Rest.Split([',']);
        var Tmp: TList<string> := TList<string>.Create;
        try
          for var P in Parts do
            if Trim(P) <> '' then Tmp.Add(Trim(P));
          N.SwapNew := Tmp.ToArray;
        finally
          Tmp.Free;
        end;
      end;
      Exit(N);
    end;

    if Dir = '#use' then
    begin
      N.Kind := rnkUse;
      N.UseUnit := Body;
      Exit(N);
    end;
```
(Confirm `System.Generics.Collections` is already in `uses` -- it is.)

- [ ] **Step 5: Add `Emit` cases.**

In `TRuleNode.Emit`, add to the `case Kind of` (after the `rnkUnuse` arm):
```pascal
    rnkUse:
      Result := Format('#use %s', [UseUnit]);
    rnkUseSwap:
      Result := Format('#useswap %s -> %s', [SwapOld, string.Join(', ', SwapNew)]);
```

- [ ] **Step 6: Add `TRuleBook.UnitNodes`.**

Declare in the class (near `ConvertHeaders`): `function UnitNodes: TArray<TRuleNode>;`. Implement:
```pascal
function TRuleBook.UnitNodes: TArray<TRuleNode>;
var
  L: TList<TRuleNode>;
  N: TRuleNode;
begin
  L := TList<TRuleNode>.Create;
  try
    for N in FNodes do
      if N.Kind in [rnkUse, rnkUnuse, rnkUseSwap] then L.Add(N);
    Result := L.ToArray;
  finally
    L.Free;
  end;
end;
```

- [ ] **Step 7: Build + run tests -- verify PASS.**

Build `_build_convrules_tests.bat`; run the exe.
Expected: `TestUnitDirectives` cases PASS; the full suite `FAIL 0` (prior tests unaffected -- round-trip of the existing corpus untouched).

- [ ] **Step 8: Commit.**
```bash
git add src/tools/convrules-editor/ConvRules.Model.pas src/tools/convrules-editor/tests/ConvRulesModelTests.dpr
git commit -m "feat(convrules-editor): model #use/#useswap nodes + UnitNodes gatherer

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 3: Pure normalization + auto-derive (`ConvRules.Units.pas`)

**Files:**
- Create: `src/tools/convrules-editor/ConvRules.Units.pas`
- Test: `src/tools/convrules-editor/tests/ConvRulesModelTests.dpr` (add `TestUnitSets`; add the unit to the runner `uses`)

**Interfaces:**
- Consumes: `ConvRules.Model` (`TRuleBook`, `TRuleNode`, node kinds; `rnkConvert.Units` is a comma-joined string).
- Produces:
  - `TUnitSets = record Adds, Removes, Conflicts: TArray<string>; end;`
  - `TConvPair = record FromType, ToType: string; end;`
  - `TUnitResolver = reference to function(const ATypeName: string): string;`
  - `function NormalizeUnitSets(ABook: TRuleBook): TUnitSets;`
  - `function DeriveUnits(const APairs: TArray<TConvPair>; const AResolve: TUnitResolver): TUnitSets;` (Adds = resolved ToType units; Removes = resolved FromType units; empty resolver result skipped; each list deduped).

- [ ] **Step 1: Write the failing tests.**

Add `procedure TestUnitSets;` to the runner and call it. Code:
```pascal
procedure TestUnitSets;
var
  Book: TRuleBook;
  S: TUnitSets;
  Pairs: TArray<TConvPair>;
begin
  Book := TRuleBook.Create;
  try
    Book.LoadFromString(
      '#convert A.TFrom -> B.TTo, cxButtons'#13#10 +
      '#use cxButtons'#13#10 +            // dup of the #convert unit-add
      '#useswap FOLDERDEF -> imcFOLDERS'#13#10 +
      '#unuse cxButtons'#13#10);          // conflict: also in ADD
    S := NormalizeUnitSets(Book);
    Check('norm.add.has.cxButtons',  Contains(S.Adds, 'cxButtons'));
    Check('norm.add.has.imcFOLDERS', Contains(S.Adds, 'imcFOLDERS'));
    Check('norm.add.dedup',          CountOf(S.Adds, 'cxButtons') = 1);
    Check('norm.remove.has.FOLDERDEF', Contains(S.Removes, 'FOLDERDEF'));
    Check('norm.conflict.addwins',   Contains(S.Conflicts, 'cxButtons') and not Contains(S.Removes, 'cxButtons'));
  finally
    Book.Free;
  end;

  SetLength(Pairs, 1);
  Pairs[0].FromType := 'Abcbtn.TabcToggleBtn';
  Pairs[0].ToType   := 'cxButtons.TcxButton';
  S := DeriveUnits(Pairs,
    function(const ATypeName: string): string
    begin
      if ATypeName.StartsWith('cxButtons') then Exit('cxButtons');
      if ATypeName.StartsWith('Abcbtn')    then Exit('Abcbtn');
      Result := '';
    end);
  Check('derive.add',    Contains(S.Adds, 'cxButtons'));
  Check('derive.remove', Contains(S.Removes, 'Abcbtn'));
end;
```
Add a small `CountOf` helper next to `Contains` in the runner:
```pascal
function CountOf(const AArr: TArray<string>; const AName: string): Integer;
var S: string;
begin
  Result := 0;
  for S in AArr do if SameText(S, AName) then Inc(Result);
end;
```
Add `ConvRules.Units in '..\ConvRules.Units.pas',` to the runner `uses`.

- [ ] **Step 2: Build + run -- verify FAIL (unit missing).**

Build `_build_convrules_tests.bat`.
Expected: compile FAILS (`ConvRules.Units` not found).

- [ ] **Step 3: Create `ConvRules.Units.pas`.**
```pascal
unit ConvRules.Units;

{ Pure, headless "no doubles" brain for unit-replacement rules. Computes the
  normalized ADD/REMOVE unit sets from a rule book (dedup + ADD-wins conflicts),
  and the auto-derive from #convert type pairs via a resolver callback. No UI,
  no engine, no I/O -- the DUnitX/console-runner spec target. }

interface

uses
  System.SysUtils, System.Classes, System.Generics.Collections,
  ConvRules.Model;

type
  TUnitSets = record
    Adds     : TArray<string>;
    Removes  : TArray<string>;
    Conflicts: TArray<string>;   // in both ADD and REMOVE -> ADD wins
  end;

  TConvPair = record
    FromType: string;
    ToType  : string;
  end;

  TUnitResolver = reference to function(const ATypeName: string): string;

/// <summary>Normalized ADD/REMOVE unit sets for a whole rule book. ADD = every
/// #use + every #useswap New + every #convert trailing unit. REMOVE = every
/// #unuse + every #useswap Old. Case-insensitive dedup; a unit in both lands in
/// Conflicts and is dropped from Removes (ADD wins).</summary>
function NormalizeUnitSets(ABook: TRuleBook): TUnitSets;

/// <summary>Auto-derive: Adds = each ToType's resolved unit; Removes = each
/// FromType's resolved unit. An empty resolver result (unresolved type) is
/// skipped. Each list deduped case-insensitively.</summary>
function DeriveUnits(const APairs: TArray<TConvPair>;
  const AResolve: TUnitResolver): TUnitSets;

implementation

procedure AddUniq(AList: TStringList; const AUnit: string);
begin
  if Trim(AUnit) = '' then Exit;
  if AList.IndexOf(AUnit) < 0 then AList.Add(AUnit); // TStringList set to CaseInsensitive
end;

function ToArr(AList: TStringList): TArray<string>;
var i: Integer;
begin
  SetLength(Result, AList.Count);
  for i := 0 to AList.Count - 1 do Result[i] := AList[i];
end;

function NormalizeUnitSets(ABook: TRuleBook): TUnitSets;
var
  Adds, Removes, Conflicts: TStringList;
  N: TRuleNode;
  U: string;
  Parts: TArray<string>;
  P: string;
begin
  Adds := TStringList.Create; Removes := TStringList.Create; Conflicts := TStringList.Create;
  try
    Adds.CaseSensitive := False; Removes.CaseSensitive := False; Conflicts.CaseSensitive := False;
    for N in ABook.Nodes do
      case N.Kind of
        rnkUse:     AddUniq(Adds, N.UseUnit);
        rnkUnuse:   AddUniq(Removes, N.UnuseUnit);
        rnkUseSwap:
          begin
            AddUniq(Removes, N.SwapOld);
            for U in N.SwapNew do AddUniq(Adds, U);
          end;
        rnkConvert:
          begin
            Parts := N.Units.Split([',']);
            for P in Parts do AddUniq(Adds, Trim(P));
          end;
      end;
    // ADD wins: any unit in both -> Conflicts, drop from Removes.
    for U in ToArr(Adds) do
      if Removes.IndexOf(U) >= 0 then
      begin
        AddUniq(Conflicts, U);
        Removes.Delete(Removes.IndexOf(U));
      end;
    Result.Adds := ToArr(Adds);
    Result.Removes := ToArr(Removes);
    Result.Conflicts := ToArr(Conflicts);
  finally
    Adds.Free; Removes.Free; Conflicts.Free;
  end;
end;

function DeriveUnits(const APairs: TArray<TConvPair>;
  const AResolve: TUnitResolver): TUnitSets;
var
  Adds, Removes: TStringList;
  Pair: TConvPair;
begin
  Adds := TStringList.Create; Removes := TStringList.Create;
  try
    Adds.CaseSensitive := False; Removes.CaseSensitive := False;
    for Pair in APairs do
    begin
      AddUniq(Adds, AResolve(Pair.ToType));
      AddUniq(Removes, AResolve(Pair.FromType));
    end;
    Result.Adds := ToArr(Adds);
    Result.Removes := ToArr(Removes);
    Result.Conflicts := nil;
  finally
    Adds.Free; Removes.Free;
  end;
end;

end.
```

- [ ] **Step 4: Build + run -- verify PASS.**

Build `_build_convrules_tests.bat`; run the exe.
Expected: `TestUnitSets` PASS; suite `FAIL 0`.

- [ ] **Step 5: Commit.**
```bash
git add src/tools/convrules-editor/ConvRules.Units.pas src/tools/convrules-editor/tests/ConvRulesModelTests.dpr
git commit -m "feat(convrules-editor): pure ConvRules.Units -- normalize + auto-derive unit sets

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 4: Engine adapter -- `DeclaringUnitOf`

**Files:**
- Modify: `src/tools/convrules-editor/ConvRules.Engine.pas` (add public method; impl wraps private `ResolveClassQName`)
- Test: `tests/ConvRulesModelTests.dpr` (add a SKIP-guarded real-DB test)

**Interfaces:**
- Consumes: private `ResolveClassQName(name): string` (returns `Unit.TClass` or the input unchanged).
- Produces: `function TEngineAdapter.DeclaringUnitOf(const ATypeName: string): string;` -- the unit prefix of the resolved qname (everything before the LAST dot), or `''` if unresolved (no dot).

- [ ] **Step 1: Write the SKIP-guarded test.**

Add to the runner (follows the existing picker-datasource pattern that Skips when the exe/DB is absent):
```pascal
procedure TestDeclaringUnit;
var
  Eng: TEngineAdapter;
  U: string;
begin
  if (GEditorExe = '') or not TFile.Exists(GEditorExe) then
  begin
    Skip('engine.declaringunit', 'no drag-lint exe configured');
    Exit;
  end;
  Eng := TEngineAdapter.Create(GEditorExe, GTestDbs);   // GTestDbs = the runner's real DB set, or []
  try
    U := Eng.DeclaringUnitOf('TcxButton');
    if U = '' then Skip('engine.declaringunit', 'TcxButton not indexed here')
    else Check('engine.declaringunit', SameText(U, 'cxButtons'), U);
  finally
    Eng.Free;
  end;
end;
```
(If the runner has no `GTestDbs`/exe wiring, reuse whatever globals the existing picker-datasource test uses; if none, keep the test but always Skip when `GEditorExe=''`.)

- [ ] **Step 2: Build + run -- verify FAIL (method missing).**

Expected: compile FAILS (`DeclaringUnitOf` undeclared).

- [ ] **Step 3: Add the public method.**

In the `public` section of `TEngineAdapter` (after `GetProptree`):
```pascal
    /// <summary>The unit that declares ATypeName, derived by resolving it to its
    /// unit-qualified form (ResolveClassQName) and taking the part before the last
    /// dot. '' when the type does not resolve (no dot in the qname).</summary>
    function DeclaringUnitOf(const ATypeName: string): string;
```
Implement (in `implementation`):
```pascal
function TEngineAdapter.DeclaringUnitOf(const ATypeName: string): string;
var
  QN: string;
  DotPos: Integer;
begin
  QN := ResolveClassQName(ATypeName);
  DotPos := QN.LastIndexOf('.');
  if DotPos > 0 then Result := QN.Substring(0, DotPos)
  else Result := '';
end;
```

- [ ] **Step 4: Build + run -- verify PASS (or SKIP on a lean box).**

Expected: `engine.declaringunit` PASS if a real lib DB with TcxButton is configured, else SKIP; suite `FAIL 0`.

- [ ] **Step 5: Commit.**
```bash
git add src/tools/convrules-editor/ConvRules.Engine.pas src/tools/convrules-editor/tests/ConvRulesModelTests.dpr
git commit -m "feat(convrules-editor): TEngineAdapter.DeclaringUnitOf for auto-derive

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 5: UI -- Unit Rules tab + Derive + Check + library filter

**Files:**
- Modify: `src/tools/convrules-editor/ConvRules.MainForm.pas` (private fields; `BuildUI`; new handlers; wire `CheckUnits` into `DoSave`; add filter to the Rules Library)
- Rebuild+deploy: `third_party/dll-win64/ConvRulesEditor.exe`

**Interfaces:**
- Consumes: `FBook: TRuleBook`, `FEngine: TEngineAdapter`, `FTabs: TPageControl`, `SetStatus/SetError`, `RefreshRulesList`, `FBook.UnitNodes`, `ConvRules.Units` (`NormalizeUnitSets`, `DeriveUnits`, `TConvPair`), `FEngine.DeclaringUnitOf`.
- Produces: a new `TabUnits` tab with a `TListView FUnitList`; handlers `DoAddSwap/DoAddUse/DoAddUnuse/DoDeleteUnit/DoDeriveUnits/DoCheckUnits/RefreshUnitList`; a `FRulesFilter: TEdit` above `FRules`.

**Note:** UI is not unit-tested; the deliverable is "compiles clean, launches, Check/Derive behave in a smoke run." Follow the existing code-built `BuildUI` pattern (parent/SetBounds/OnClick). Every mutation goes through `FBook` then `RefreshUnitList` + `SyncRawFromModel`.

- [ ] **Step 1: Add fields + `uses`.**

Add `ConvRules.Units` to the `implementation uses`. Add private fields:
```pascal
    FUnitList  : TListView;   // Unit Rules tab
    FRulesFilter: TEdit;      // filter over the Rules Library
```
Declare the handlers in the private section:
```pascal
    procedure RefreshUnitList;
    procedure DoAddSwap(Sender: TObject);
    procedure DoAddUse(Sender: TObject);
    procedure DoAddUnuse(Sender: TObject);
    procedure DoDeleteUnit(Sender: TObject);
    procedure DoDeriveUnits(Sender: TObject);
    procedure DoCheckUnits(Sender: TObject);
    procedure RulesFilterChange(Sender: TObject);
```

- [ ] **Step 2: Build the Unit Rules tab in `BuildUI`.**

After the `TabRaw` block (line ~299), add a third tab with a top button row (Swap / Add / Remove / Delete / Derive / Check) and a `TListView` (columns Kind, Old, New(s), Source, Flag). Use the same `TTabSheet.Create(FTabs)` pattern. Add a `TEdit` (`FRulesFilter`) docked `alTop` inside `TabRules` above `FRules`, `OnChange := RulesFilterChange`. Full control-construction code mirrors the existing tabs (parent, Align/SetBounds, Caption, OnClick).

- [ ] **Step 3: Implement `RefreshUnitList`.**

Clear `FUnitList.Items`; for each `N in FBook.UnitNodes` add a row: Kind (`#use`/`#unuse`/`#useswap`), Old (`SwapOld`/`UnuseUnit`/''), New(s) (`string.Join(', ', SwapNew)` or `UseUnit`), Source (derived rows carry a trailing `#note` marker or a model flag -- v1: leave 'hand' unless the node's originating block is known; keep simple = ''), Flag (blank; filled by Check). Then call `SyncRawFromModel`.

- [ ] **Step 4: Implement the add/delete handlers.**

`DoAddSwap`: prompt via two `InputQuery` calls (Old unit; comma list of New units), create a `TRuleNode` (Kind=rnkUseSwap, SwapOld, SwapNew from comma-split, Dirty=True), `FBook.Add(N)`, `RefreshUnitList`. `DoAddUse`/`DoAddUnuse`: one `InputQuery`, create rnkUse/rnkUnuse node. `DoDeleteUnit`: remove the selected node from `FBook.Nodes` (match by identity/index), `RefreshUnitList`. (Autocomplete combos are a v1.1 nicety; `InputQuery` is the YAGNI baseline and still writes through the model.)

- [ ] **Step 5: Implement `DoDeriveUnits`.**

Build `TArray<TConvPair>` from `FBook.ConvertHeaders` (each header node's `FromType`/`ToType`); call `DeriveUnits(pairs, function(t) begin Result := FEngine.DeclaringUnitOf(t) end)`; for each Add not already a `#use`, append a `rnkUse` node; for each Remove not already `#unuse`, append a `rnkUnuse` node (dedup against existing `FBook.UnitNodes`). `SetStatus(Format('Derived: +%d #use, +%d #unuse', [addedUse, addedUnuse]))`; `RefreshUnitList`.

- [ ] **Step 6: Implement `DoCheckUnits` + wire into `DoSave`.**

`DoCheckUnits`: `S := NormalizeUnitSets(FBook)`; if `Length(S.Conflicts) > 0` then `SetError('Unit conflicts (ADD wins): ' + string.Join(', ', S.Conflicts))` else `SetStatus(Format('Units OK: %d add, %d remove, no doubles', [Length(S.Adds), Length(S.Removes)]))`. In `DoSave`, call `DoCheckUnits(nil)` after the existing validate so conflicts surface on every save (non-blocking -- report only).

- [ ] **Step 7: Implement `RulesFilterChange`.**

Re-run `RefreshRulesList` but skip rows whose From/To don't contain `FRulesFilter.Text` (case-insensitive). Simplest: give `RefreshRulesList` an internal filter read from `FRulesFilter.Text` (empty = all).

- [ ] **Step 8: ASCII/CRLF check, build the editor, deploy, smoke.**

Verify ASCII+CRLF. `Stop-Process -Name ConvRulesEditor -ErrorAction SilentlyContinue`. Build `build/_build_convrules_editor.bat`; confirm `BUILD_EXITCODE=0`, no `[dcc] Error`; copy exe to `third_party/dll-win64/ConvRulesEditor.exe`. Launch it for ~2s headless (`Start-Process ... ; Start-Sleep 2 ; Stop-Process`) to confirm the form constructs (no exception). Note in the commit that live click-through is user-verified.

- [ ] **Step 9: Commit.**
```bash
git add src/tools/convrules-editor/ConvRules.MainForm.pas
git commit -m "feat(convrules-editor): Unit Rules tab -- add/derive/check + library filter

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 6: Docs -- grammar rows

**Files:**
- Modify: `docs/CONVERSION-RULES.md` (the "reFind directives" / "drag-lint superset directives" tables)

- [ ] **Step 1: Add the two directive rows.**

In the superset-directives table (after the `#ignore` row), add:
```
| `#use <unit>` | add a unit to the PAS `uses` clause (companion to `#unuse`). |
| `#useswap <Old> -> <New1>[, <New2> ...]` | replace `<Old>` with one-or-more `<New>` units. Equivalent to `#unuse Old` + `#use New...`. |
```
Add one paragraph noting these are recognized by the parser now (parse-only) and executed by `convert-apply` in a later phase; and the ADD/REMOVE dedup rule ("no doubles", ADD wins on conflict).

- [ ] **Step 2: Commit.**
```bash
git add docs/CONVERSION-RULES.md
git commit -m "docs(convert): document #use/#useswap unit-replacement directives

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Self-Review Notes

- **Spec coverage:** DSL (Task 1+2), normalization/dedup + auto-derive (Task 3), declaring-unit resolver (Task 4), Unit Rules UX + Check + Derive + filter (Task 5), docs (Task 6). Save-validate-green requirement met by Task 1 (proven by the autotest). Deferred items (apply engine, DFM inventory, casts, AI apply-by-name) are out of plan by design.
- **Type consistency:** `TUnitSets`/`TConvPair`/`TUnitResolver` defined in Task 3 and consumed by name in Tasks 4-5; `DeclaringUnitOf` defined Task 4, used Task 5; `UnitNodes` defined Task 2, used Tasks 3+5; engine `UnitName`/`UnitsAdd` reused (Task 1) -- no new record fields there.
- **Known soft spot:** Task 5 "Source" column can't cheaply distinguish hand vs derived in v1 (the model doesn't tag origin). Left blank -- a v1.1 `TRuleNode.Origin` flag is the clean follow-up; not blocking.
