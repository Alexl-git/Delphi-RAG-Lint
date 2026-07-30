# Examine Used Properties Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let the user point ConvRulesEditor at a set of `.dfm`/`.pas` files and have the mapping grid paint green every From property those files actually use.

**Architecture:** One new pure unit, `ConvRules.Usage.pas`, holding all scanning and matching logic, tested headlessly against inline fixtures. `ConvRules.MainForm` only picks files, calls one function, and paints cells. The scanner reads text handed to it — it never touches the file system, so every rule is testable without a form or a disk.

**Tech Stack:** Delphi 13 Florence (RAD Studio 37.0), `dcc64`, plain VCL (no DevExpress, no `.dfm` — forms are built in code). Tests are the existing console runner `ConvRulesModelTests.dpr` (no DUnitX).

Spec: `docs/superpowers/specs/2026-07-28-examine-used-properties-design.md` (approved 2026-07-28).
Worktree: `C:\Projects\Delphi-RAG-lint-converter`, branch `feat/converter-editor`.

## Global Constraints

- **Encoding:** `.pas`/`.dpr` are strict 7-bit ASCII, CRLF, no BOM, no Unicode. Verify the WORKING-TREE bytes before committing (git blobs show LF because `.gitattributes` sets `*.pas text eol=crlf`).
- **DocInsight:** `///` XML doc-comments on every public type and function.
- **TDD:** failing test first, run it, see it fail, then implement. Every task ends green.
- **Purity:** `ConvRules.Usage` must not reference `Vcl.*`, `System.IOUtils`, or spawn processes. It receives text, returns data. Only the form reads files.
- **Read-only feature:** Examine never writes a file. No `.rules` change, no backup, no persistence — the result is transient view state.
- **Tests:** in `ConvRulesModelTests.dpr` using its `Check(name, cond, detail)` / `Skip(name, reason)` helpers. Register every new test procedure in the main `begin` block.
- **Baseline:** the suite is **296 pass / 0 fail / 0 skip** before this plan. It must end green with the new tests added.
- **Commits:** one per task on `feat/converter-editor`. Do NOT push.

## Staging — a previous implementer destroyed another workstream's work here

This worktree carries uncommitted edits belonging to OTHER workstreams: `ConvRulesModelTests.dpr`, `ConvRules.Engine.pas`, `docs/examples/convrules/sample.rules` and several docs. They are **not yours to commit and not yours to remove**.

- **NEVER run `git checkout`, `git restore`, `git stash`, `git clean`, or `git reset --hard`.**
- Never `git commit -- <pathspec>` — a pathspec bypasses the index and sweeps in unstaged hunks.
- Stage `ConvRulesModelTests.dpr` with `git add -p`, accepting only your own hunks; use explicit `git add <path>` for everything else; commit with NO pathspec.
- Afterwards run `git show --stat` and `git status --short`; confirm your commit holds only your changes and that the other workstreams' files are STILL listed as modified.

## Build and test

```powershell
Start-Process -Wait -NoNewWindow -FilePath "C:\Projects\Delphi-RAG-lint-converter\build\_build_convrules_tests_local.bat" -RedirectStandardOutput "$env:TEMP\ct.log"
Get-Content "$env:TEMP\ct.log" -Tail 5
& "C:\Projects\Delphi-RAG-lint-converter\src\tools\convrules-editor\tests\ConvRulesModelTests.exe" | Select-Object -Last 3
```

Editor build (Task 4 only): same shape with `_build_convrules_editor_local.bat`. Both print `BUILD_EXITCODE=0` on success. Do **NOT** run `cmd.exe /c "somebuild.bat"` from the Bash tool — it hangs until timeout. One pre-existing `W1073` warning from `ConvRules.Engine.pas:337` belongs to another workstream.

## File Structure

| File | Responsibility |
|---|---|
| `src/tools/convrules-editor/ConvRules.Usage.pas` (new, pure) | DFM block scanning, PAS name matching, candidate derivation, row matching, and the one orchestrating `ComputeUsage`. |
| `src/tools/convrules-editor/ConvRules.MainForm.pas` (modify) | `Examine...` button, multi-select dialog, file reading, `OnDrawCell` green painting, status text, clear, missing-report dialog. |
| `src/tools/convrules-editor/ConvRulesEditor.dpr` (modify) | Add the new unit to `uses`. |
| `src/tools/convrules-editor/tests/ConvRulesModelTests.dpr` (modify) | One test procedure per acceptance criterion 1-11. |

## Tasks

- Task 1 — DFM scanner (criteria 1-6)
- Task 2 — PAS matching, candidates, row test, merge (criteria 7-10)
- Task 3 — `ComputeUsage` + Missing + the real VARINSP fixture (criterion 11)
- Task 4 — form wiring and green painting (criterion 12, manual)

---

### Task 1: DFM scanner

**Files:**
- Create: `src/tools/convrules-editor/ConvRules.Usage.pas`
- Modify: `src/tools/convrules-editor/tests/ConvRulesModelTests.dpr`

**Interfaces:**
- Consumes: `SplitRawLines` and `TRawLine` from `ConvRules.BlockFile` (already committed) — reuse them rather than writing a second line splitter.
- Produces: `function ScanDfmText(const AText, AFromClass: string): TArray<string>;`

- [ ] **Step 1: Write the failing test**

Add to `ConvRulesModelTests.dpr` and register in the main `begin` block:

```pascal
{ Criteria 1-6: the DFM scanner records the assignments of blocks whose class is the
  From class, at that block's immediate level only, skipping binary blobs and nested
  components -- but descending into nested blocks to find further instances. }
procedure TestScanDfm;
const
  SRC =
    'object Form1: TForm1'#13#10 +
    '  Caption = ''ignored -- wrong class'''#13#10 +
    '  object btnA: TabcToggleBtn'#13#10 +
    '    Left = 4'#13#10 +
    '    Top = 175'#13#10 +
    '    Caption = ''Ac'''#13#10 +
    '    Layout = ablGlyphCenter'#13#10 +
    '    Picture.Data = {'#13#10 +
    '      07544269746D617076080000424D7606'#13#10 +
    '      Width = 999'#13#10 +          // inside the blob: must NOT be recorded
    '      0000200000000100040000000000}'#13#10 +
    '    Columns = <'#13#10 +
    '      item'#13#10 +
    '        Height = 888'#13#10 +       // inside the item list: must NOT be recorded
    '      end>'#13#10 +
    '    object lblChild: TLabel'#13#10 +
    '      Alignment = taLeftJustify'#13#10 +   // child component: NOT the From class
    '    end'#13#10 +
    '  end'#13#10 +
    '  object btnB: TabcToggleBtn'#13#10 +
    '    Hint = ''second instance'''#13#10 +
    '  end'#13#10 +
    'end'#13#10;

  function Has(const A: TArray<string>; const S: string): Boolean;
  var
    X: string;
  begin
    for X in A do
      if SameText(X, S) then Exit(True);
    Result := False;
  end;

var
  U: TArray<string>;
begin
  U := ScanDfmText(SRC, 'TabcToggleBtn');
  Check('usage.dfm.left',      Has(U, 'Left'), 'plain assignment');
  Check('usage.dfm.caption',   Has(U, 'Caption'), 'plain assignment');
  Check('usage.dfm.layout',    Has(U, 'Layout'), 'plain assignment');
  Check('usage.dfm.dotted',    Has(U, 'Picture.Data'), 'dotted path recorded whole');
  Check('usage.dfm.dotroot',   Has(U, 'Picture'), 'dotted path also records its root');
  Check('usage.dfm.blob',      not Has(U, 'Width'), 'a line inside a { } blob is not an assignment');
  Check('usage.dfm.itemlist',  not Has(U, 'Height'), 'a line inside a < > item list is not an assignment');
  Check('usage.dfm.child',     not Has(U, 'Alignment'), 'a nested component is not the From class');
  Check('usage.dfm.sibling',   Has(U, 'Hint'), 'a second instance of the From class is scanned');
  Check('usage.dfm.wrongclass', not Has(U, 'ignored'), 'the outer TForm1 block is not scanned');
  Check('usage.dfm.none', Length(ScanDfmText(SRC, 'TNotPresent')) = 0,
    'no block of the From class yields an empty set');
end;
```

Add `ConvRules.Usage in '..\ConvRules.Usage.pas',` to the runner's `uses`.

- [ ] **Step 2: Run to verify it fails**

Expected: `F2613 Unit 'ConvRules.Usage' not found`.

- [ ] **Step 3: Implement**

Create `src/tools/convrules-editor/ConvRules.Usage.pas`:

```pascal
unit ConvRules.Usage;

{ Pure "which properties does this conversion actually use" scanner.

  A conversion's From class exposes far more properties than any real form uses --
  Abcbtn.TabcToggleBtn has 3905 proptree leaves, while a real TabcToggleBtn in
  ORM3\CLIENT\VARINSP.dfm assigns nine. This unit answers, for a chosen set of .dfm and
  .pas texts, which of the From class's properties are genuinely touched, so the editor
  can mark those rows and the user can stop mapping the rest.

  Pure + headless: it takes TEXT and returns data. No file system, no VCL, no process
  spawn -- the form reads the files and passes their contents in, which is what makes
  every rule here unit-testable against inline fixtures. }

interface

uses
  System.SysUtils, System.Generics.Collections,
  ConvRules.BlockFile;

type
  /// <summary>The outcome of examining a set of files.</summary>
  /// <remarks>Names are normalised and de-duplicated case-insensitively. Missing holds
  /// used names that match no leaf of the From property tree -- expected to be empty,
  /// and evidence of an indexer gap when it is not.</remarks>
  TUsageSet = record
    Names   : TArray<string>;
    Missing : TArray<string>;
    DfmCount: Integer;
    PasCount: Integer;
  end;

/// <summary>PURE: the property names assigned to instances of AFromClass in a .dfm text.</summary>
/// <param name="AText">The whole .dfm as text. A binary .dfm simply yields nothing.</param>
/// <param name="AFromClass">Bare class name, matched case-insensitively (e.g. 'TabcToggleBtn').</param>
/// <returns>Distinct names. A dotted assignment 'A.B' contributes BOTH 'A.B' and 'A',
/// because the root property is genuinely used and a grid row for 'A' should match.</returns>
/// <remarks>Depth-tracked line scan, not a parser. Assignments count only at the
/// immediate level of a matching block: a nested component belongs to itself, not to the
/// From class, though the scan still descends to find further instances. Values opening
/// a '{' blob, a '&lt;' item list or a '(' list are skipped to their terminator so their
/// contents are never mistaken for assignments.</remarks>
function ScanDfmText(const AText, AFromClass: string): TArray<string>;

implementation

{ A valid (possibly dotted) DFM property name: identifier chars and dots only, starting
  with a letter or underscore. This is what keeps a continuation line of a quoted string
  -- which may well contain '=' -- from being read as an assignment. }
function IsPropName(const S: string): Boolean;
var
  i: Integer;
begin
  Result := False;
  if S = '' then Exit;
  if not (CharInSet(S[1], ['A'..'Z', 'a'..'z', '_'])) then Exit;
  for i := 2 to Length(S) do
    if not CharInSet(S[i], ['A'..'Z', 'a'..'z', '0'..'9', '_', '.']) then Exit;
  Result := True;
end;

{ 'object btnA: TabcToggleBtn' -> AName='btnA', AClass='TabcToggleBtn'. Also accepts the
  'inherited' and 'inline' block keywords real DFMs use for inherited forms and frames. }
function ParseBlockHeader(const ALine: string; out AClass: string): Boolean;
var
  S, Tok: string;
  p: Integer;
begin
  Result := False;
  AClass := '';
  S := Trim(ALine);
  Tok := FirstToken(S);
  if not (SameText(Tok, 'object') or SameText(Tok, 'inherited') or SameText(Tok, 'inline')) then
    Exit;
  p := Pos(':', S);
  if p = 0 then Exit;                      // 'inherited Frame1' with no type
  AClass := Trim(Copy(S, p + 1, MaxInt));
  // a trailing '[0]' index appears on inherited collection items
  p := Pos('[', AClass);
  if p > 0 then AClass := Trim(Copy(AClass, 1, p - 1));
  Result := AClass <> '';
end;

function ScanDfmText(const AText, AFromClass: string): TArray<string>;
var
  Lines : TArray<TRawLine>;
  Stack : TList<Boolean>;      // one entry per open block: is it a From-class block?
  Names : TList<string>;
  i, ep : Integer;
  Cur, Nm, Val, Cls: string;
  SkipTo: string;              // '' = not skipping; else the terminator to look for

  procedure AddName(const AName: string);
  var
    X   : string;
    Root: string;
    dp  : Integer;   // MUST be local: reusing the enclosing `ep` corrupts the '=' position
  begin
    for X in Names do
      if SameText(X, AName) then Exit;
    Names.Add(AName);
    dp := Pos('.', AName);
    if dp > 1 then
    begin
      Root := Copy(AName, 1, dp - 1);
      for X in Names do
        if SameText(X, Root) then Exit;
      Names.Add(Root);
    end;
  end;

begin
  Lines  := SplitRawLines(AText);
  Stack  := TList<Boolean>.Create;
  Names  := TList<string>.Create;
  try
    SkipTo := '';
    for i := 0 to High(Lines) do
    begin
      Cur := Trim(Lines[i].Text);
      if Cur = '' then Continue;

      if SkipTo <> '' then
      begin
        if Pos(SkipTo, Cur) > 0 then SkipTo := '';
        Continue;
      end;

      if ParseBlockHeader(Cur, Cls) then
      begin
        Stack.Add(SameText(Cls, AFromClass));
        Continue;
      end;

      if SameText(FirstToken(Cur), 'end') then
      begin
        if Stack.Count > 0 then Stack.Delete(Stack.Count - 1);
        Continue;
      end;

      if (Stack.Count = 0) or (not Stack[Stack.Count - 1]) then Continue;

      ep := Pos('=', Cur);
      if ep = 0 then Continue;
      Nm := Trim(Copy(Cur, 1, ep - 1));
      if not IsPropName(Nm) then Continue;
      AddName(Nm);

      Val := Trim(Copy(Cur, ep + 1, MaxInt));
      if      Val = '{' then SkipTo := '}'
      else if Val = '<' then SkipTo := '>'
      else if Val = '(' then SkipTo := ')';
    end;
    Result := Names.ToArray;
  finally
    Names.Free;
    Stack.Free;
  end;
end;

end.
```

- [ ] **Step 4: Run to verify it passes**

Expected: all eleven `usage.dfm.*` checks PASS, `0 fail`, no regression from 296.

- [ ] **Step 5: Commit**

```bash
git add src/tools/convrules-editor/ConvRules.Usage.pas
git add -p src/tools/convrules-editor/tests/ConvRulesModelTests.dpr
git commit -m "feat(convrules): DFM scanner for properties a conversion actually uses"
```

---

### Task 2: PAS matching, candidates, row test, merge

**Files:**
- Modify: `src/tools/convrules-editor/ConvRules.Usage.pas`
- Modify: `src/tools/convrules-editor/tests/ConvRulesModelTests.dpr`

**Interfaces:**
- Consumes: Task 1's unit.
- Produces:
  - `function CandidatesFor(const AFromPaths: TArray<string>): TArray<string>;`
  - `function ScanPasText(const AText: string; const ACandidates: TArray<string>): TArray<string>;`
  - `function MergeUsage(const AParts: TArray<TArray<string>>): TArray<string>;`
  - `function IsRowUsed(const AFromPath: string; const AUsed: TArray<string>): Boolean;`

- [ ] **Step 1: Write the failing test**

```pascal
{ Criteria 7-10: loose '.PropName' matching in a .pas, candidate derivation from the
  From tree, the row test, and case-insensitive de-duplication across files. }
procedure TestScanPasAndMatch;
const
  PAS =
    'procedure TForm1.Go;'#13#10 +
    'begin'#13#10 +
    '  btnA.Caption := ''x'';'#13#10 +
    '  with btnA do Layout := ablGlyphLeft;'#13#10 +   // no dot: NOT matched, by design
    '  Self.CaptionExtra := 1;'#13#10 +                // must not mark Caption used
    '  lbl.Font.Size := 9;'#13#10 +
    'end;'#13#10;

  function Has(const A: TArray<string>; const S: string): Boolean;
  var X: string;
  begin
    for X in A do
      if SameText(X, S) then Exit(True);
    Result := False;
  end;

var
  Cand, U, M: TArray<string>;
begin
  Cand := CandidatesFor(['Caption', 'Layout', 'Font.Size', 'Hint']);
  Check('usage.cand.leaf',   Has(Cand, 'Size'), 'last segment of a dotted path is a candidate');
  Check('usage.cand.full',   Has(Cand, 'Font.Size'), 'the full dotted path is a candidate');
  Check('usage.cand.plain',  Has(Cand, 'Caption'), 'plain names are candidates');

  U := ScanPasText(PAS, Cand);
  Check('usage.pas.hit',      Has(U, 'Caption'), '.Caption is used');
  Check('usage.pas.boundary', not Has(U, 'Hint'), 'Hint never appears');
  Check('usage.pas.suffix',   Has(U, 'Caption'), 'CaptionExtra must not be the only reason');
  Check('usage.pas.nested',   Has(U, 'Size'), '.Size matches through lbl.Font.Size');
  Check('usage.pas.nodot',    not Has(U, 'Layout'),
    'a with-block assignment has no dot, so the loose match cannot see it');

  // criterion 8 in isolation: a longer identifier must not mark the shorter one used
  Check('usage.pas.notprefix',
    not Has(ScanPasText('  x.CaptionExtra := 1;'#13#10, ['Caption']), 'Caption'),
    '.CaptionExtra must not mark Caption used');

  // criterion 9: the row test
  Check('usage.row.exact',  IsRowUsed('Caption', ['caption']), 'case-insensitive exact path');
  Check('usage.row.leaf',   IsRowUsed('Font.Size', ['Size']), 'last segment matches');
  Check('usage.row.full',   IsRowUsed('Font.Size', ['Font.Size']), 'full path matches');
  Check('usage.row.miss',   not IsRowUsed('Font.Size', ['Color']), 'unrelated name does not match');

  // criterion 10: merge de-duplicates case-insensitively
  M := MergeUsage([TArray<string>.Create('Caption', 'Left'),
                   TArray<string>.Create('caption', 'Top')]);
  Check('usage.merge.count', Length(M) = 3, IntToStr(Length(M)));
end;
```

- [ ] **Step 2: Run to verify it fails**

Expected: `E2003 Undeclared identifier: 'CandidatesFor'`.

- [ ] **Step 3: Implement**

Add to the interface of `ConvRules.Usage.pas`:

```pascal
/// <summary>PURE: the names worth searching a .pas for, derived from the From tree:
/// every distinct full path plus every distinct last segment.</summary>
function CandidatesFor(const AFromPaths: TArray<string>): TArray<string>;

/// <summary>PURE: which candidates appear in a .pas text as '.Name' followed by a
/// non-identifier character.</summary>
/// <remarks>DELIBERATELY LOOSE (the user's ruling): it does not check which object the
/// member belongs to, and does not exclude comments or string literals. The cost is
/// over-reporting -- another component's '.Caption' marks Caption used; the gain is that
/// typed locals and any dotted access are caught. A 'with X do Caption := ...' has no
/// dot and is therefore NOT seen.</remarks>
function ScanPasText(const AText: string; const ACandidates: TArray<string>): TArray<string>;

/// <summary>PURE: union of several scans, de-duplicated case-insensitively.</summary>
function MergeUsage(const AParts: TArray<TArray<string>>): TArray<string>;

/// <summary>PURE: is a grid row's From path used? True when the path itself, or its last
/// dotted segment, is in AUsed (case-insensitive).</summary>
function IsRowUsed(const AFromPath: string; const AUsed: TArray<string>): Boolean;
```

And to the implementation:

```pascal
function LastSegment(const APath: string): string;
var
  i: Integer;
begin
  Result := APath;
  for i := Length(APath) downto 1 do
    if APath[i] = '.' then Exit(Copy(APath, i + 1, MaxInt));
end;

function HasName(const A: TArray<string>; const S: string): Boolean;
var
  X: string;
begin
  for X in A do
    if SameText(X, S) then Exit(True);
  Result := False;
end;

function CandidatesFor(const AFromPaths: TArray<string>): TArray<string>;
var
  List: TList<string>;
  P   : string;

  procedure Add(const S: string);
  begin
    if (S <> '') and not HasName(List.ToArray, S) then List.Add(S);
  end;

begin
  List := TList<string>.Create;
  try
    for P in AFromPaths do
    begin
      Add(P);
      Add(LastSegment(P));
    end;
    Result := List.ToArray;
  finally
    List.Free;
  end;
end;

function ScanPasText(const AText: string; const ACandidates: TArray<string>): TArray<string>;
var
  Low  : string;
  List : TList<string>;
  C, Nd: string;
  p, aft: Integer;
  Found: Boolean;
begin
  Low  := LowerCase(AText);
  List := TList<string>.Create;
  try
    for C in ACandidates do
    begin
      Nd := '.' + LowerCase(C);
      p  := Pos(Nd, Low);
      Found := False;
      while (p > 0) and not Found do
      begin
        aft := p + Length(Nd);
        if (aft > Length(Low))
           or not CharInSet(Low[aft], ['a'..'z', '0'..'9', '_']) then
          Found := True
        else
          p := Pos(Nd, Low, p + 1);
      end;
      if Found and not HasName(List.ToArray, C) then List.Add(C);
    end;
    Result := List.ToArray;
  finally
    List.Free;
  end;
end;

function MergeUsage(const AParts: TArray<TArray<string>>): TArray<string>;
var
  List: TList<string>;
  Part: TArray<string>;
  S   : string;
begin
  List := TList<string>.Create;
  try
    for Part in AParts do
      for S in Part do
        if not HasName(List.ToArray, S) then List.Add(S);
    Result := List.ToArray;
  finally
    List.Free;
  end;
end;

function IsRowUsed(const AFromPath: string; const AUsed: TArray<string>): Boolean;
begin
  Result := HasName(AUsed, AFromPath) or HasName(AUsed, LastSegment(AFromPath));
end;
```

Note `Pos(Substr, S, Offset)` is the three-argument overload in `System.SysUtils`; if the compiler rejects it, use `System.StrUtils.PosEx` and add `System.StrUtils` to the implementation `uses`.

- [ ] **Step 4: Run to verify it passes**

Expected: every `usage.cand.*`, `usage.pas.*`, `usage.row.*` and `usage.merge.*` check PASSes, `0 fail`.

- [ ] **Step 5: Commit**

```bash
git add src/tools/convrules-editor/ConvRules.Usage.pas
git add -p src/tools/convrules-editor/tests/ConvRulesModelTests.dpr
git commit -m "feat(convrules): loose PAS matching, candidates and row test for Examine"
```

---

### Task 3: `ComputeUsage`, Missing, and the real DFM fixture

**Files:**
- Modify: `src/tools/convrules-editor/ConvRules.Usage.pas`
- Modify: `src/tools/convrules-editor/tests/ConvRulesModelTests.dpr`

**Interfaces:**
- Produces: `function ComputeUsage(const ADfmTexts, APasTexts: TArray<string>; const AFromClass: string; const AFromPaths: TArray<string>): TUsageSet;`

- [ ] **Step 1: Write the failing test**

```pascal
{ Criterion 11 plus the orchestration: ComputeUsage merges both sources, counts files, and
  reports used names with no From-tree leaf. Also pins criterion 1 against the REAL block
  shape from ORM3\CLIENT\VARINSP.dfm (an ABC5 TabcToggleBtn with a Picture.Data blob),
  copied here as a fixture so the suite never depends on a path outside the repo. }
procedure TestComputeUsage;
const
  REAL_DFM =
    '            object btnEWAcAQL: TabcToggleBtn'#13#10 +
    '              Left = 4'#13#10 +
    '              Top = 175'#13#10 +
    '              Width = 44'#13#10 +
    '              Height = 39'#13#10 +
    '              GroupIndex = 58114708'#13#10 +
    '              Caption = ''Ac'''#13#10 +
    '              Images = imlGlyphList'#13#10 +
    '              Layout = ablGlyphCenter'#13#10 +
    '              Picture.Data = {'#13#10 +
    '                07544269746D617076080000424D760800000000000076000000280000008000'#13#10 +
    '                0000200000000100040000000000000800000000000000000000100000000000}'#13#10 +
    '            end'#13#10;
  PAS = '  btnEWAcAQL.Enabled := True;'#13#10;

  function Has(const A: TArray<string>; const S: string): Boolean;
  var X: string;
  begin
    for X in A do
      if SameText(X, S) then Exit(True);
    Result := False;
  end;

var
  U: TUsageSet;
begin
  U := ComputeUsage([REAL_DFM], [PAS], 'TabcToggleBtn',
    ['Left', 'Top', 'Width', 'Height', 'GroupIndex', 'Caption', 'Images', 'Layout',
     'Picture', 'Picture.Data', 'Enabled', 'Hint']);

  Check('usage.compute.dfmcount', U.DfmCount = 1, IntToStr(U.DfmCount));
  Check('usage.compute.pascount', U.PasCount = 1, IntToStr(U.PasCount));
  Check('usage.compute.dfm',      Has(U.Names, 'GroupIndex'), 'from the DFM');
  Check('usage.compute.pas',      Has(U.Names, 'Enabled'), 'from the PAS');
  Check('usage.compute.blob',     not Has(U.Names, '07544269746D617076080000424D760800000000000076000000280000008000'),
    'hex blob lines are not names');
  Check('usage.compute.unused',   not Has(U.Names, 'Hint'), 'Hint is used nowhere');
  Check('usage.compute.nomissing', Length(U.Missing) = 0,
    'every used name has a From-tree leaf here');

  // criterion 11: a used name with no From-tree leaf is reported
  U := ComputeUsage([REAL_DFM], [], 'TabcToggleBtn', ['Caption']);
  Check('usage.compute.missing', Has(U.Missing, 'GroupIndex'),
    'GroupIndex is assigned in the DFM but absent from the From tree');
  Check('usage.compute.missing.notused', not Has(U.Missing, 'Caption'),
    'a name WITH a leaf is not Missing');
end;
```

- [ ] **Step 2: Run to verify it fails**

Expected: `E2003 Undeclared identifier: 'ComputeUsage'`.

- [ ] **Step 3: Implement**

Interface:

```pascal
/// <summary>PURE: examine a set of already-read file texts and report what the From class
/// actually uses.</summary>
/// <param name="ADfmTexts">Contents of the selected .dfm files.</param>
/// <param name="APasTexts">Contents of the selected .pas files.</param>
/// <param name="AFromClass">Bare From class name, e.g. 'TabcToggleBtn'.</param>
/// <param name="AFromPaths">Every leaf path of the From property tree, used both to derive
/// PAS candidates and to decide which used names have no row.</param>
function ComputeUsage(const ADfmTexts, APasTexts: TArray<string>;
  const AFromClass: string; const AFromPaths: TArray<string>): TUsageSet;
```

Implementation:

```pascal
function ComputeUsage(const ADfmTexts, APasTexts: TArray<string>;
  const AFromClass: string; const AFromPaths: TArray<string>): TUsageSet;
var
  Parts: TList<TArray<string>>;
  Cand : TArray<string>;
  T, N : string;
  Miss : TList<string>;
begin
  Result := Default(TUsageSet);
  Cand   := CandidatesFor(AFromPaths);
  Parts  := TList<TArray<string>>.Create;
  Miss   := TList<string>.Create;
  try
    for T in ADfmTexts do
    begin
      Parts.Add(ScanDfmText(T, AFromClass));
      Inc(Result.DfmCount);
    end;
    for T in APasTexts do
    begin
      Parts.Add(ScanPasText(T, Cand));
      Inc(Result.PasCount);
    end;
    Result.Names := MergeUsage(Parts.ToArray);

    // A used name is Missing when no From-tree leaf matches it by either rule.
    for N in Result.Names do
    begin
      var Found: Boolean := False;
      for var P in AFromPaths do
        if SameText(P, N) or SameText(LastSegment(P), N) then
        begin
          Found := True;
          Break;
        end;
      if not Found then Miss.Add(N);
    end;
    Result.Missing := Miss.ToArray;
  finally
    Miss.Free;
    Parts.Free;
  end;
end;
```

- [ ] **Step 4: Run to verify it passes**

Expected: every `usage.compute.*` check PASSes, `0 fail`.

- [ ] **Step 5: Commit**

```bash
git add src/tools/convrules-editor/ConvRules.Usage.pas
git add -p src/tools/convrules-editor/tests/ConvRulesModelTests.dpr
git commit -m "feat(convrules): ComputeUsage orchestration + missing-property report"
```

---

### Task 4: Form wiring and green painting

**Files:**
- Modify: `src/tools/convrules-editor/ConvRules.MainForm.pas`
- Modify: `src/tools/convrules-editor/ConvRulesEditor.dpr`

No automated test — this is code-built VCL, verified by a clean build plus the manual checklist below, consistent with the standing ruling for this project's forms.

- [ ] **Step 1: Wire the unit**

Add `ConvRules.Usage in 'ConvRules.Usage.pas',` to `ConvRulesEditor.dpr`'s `uses`, and `ConvRules.Usage` to `ConvRules.MainForm`'s implementation `uses`.

- [ ] **Step 2: Add state and the button**

Private fields:

```pascal
    FUsedProps  : TArray<string>;   // Examine result; empty = no examination active
    FUsedFiles  : TArray<string>;   // the examined file set, retained for the session
    FExamineInfo: string;           // status summary, re-shown when blocks change
```

In `BuildUI`, beside the grid-filter controls added for the search boxes, add two buttons following the surrounding style (`TButton.Create(Self)`, `Parent :=`, `SetBounds`, `Caption`, `Hint`, `ShowHint := True`, `OnClick :=`):

- `Examine...` -> `DoExamine`
- `Clear marks` -> `DoClearExamine`

- [ ] **Step 3: Implement the handlers**

```pascal
procedure TConvRulesForm.DoExamine(Sender: TObject);
var
  Dlg  : TOpenDialog;
  Dfms, Pass: TArray<string>;
  Bad  : TArray<string>;
  Paths: TArray<string>;
  U    : TUsageSet;
  L    : TPropLeaf;
  F    : string;
begin
  if FActiveHdr < 0 then
  begin
    SetStatus('Select a conversion first -- Examine marks the From properties of the active rule.');
    Exit;
  end;
  Dlg := TOpenDialog.Create(Self);
  try
    Dlg.Filter := 'Delphi form and source (*.dfm;*.pas)|*.dfm;*.pas|'
      + 'Form files (*.dfm)|*.dfm|Source (*.pas)|*.pas|All files (*.*)|*.*';
    Dlg.Options := Dlg.Options + [ofAllowMultiSelect, ofFileMustExist];
    if not Dlg.Execute then Exit;
    FUsedFiles := Dlg.Files.ToStringArray;
  finally
    Dlg.Free;
  end;

  var LGuard: IInterface := HourGlass;
  Dfms := nil; Pass := nil; Bad := nil;
  for F in FUsedFiles do
    try
      if SameText(ExtractFileExt(F), '.dfm') then
        Dfms := Dfms + [TFile.ReadAllText(F)]
      else
        Pass := Pass + [TFile.ReadAllText(F)];
    except
      on E: Exception do Bad := Bad + [ExtractFileName(F)];
    end;

  Paths := nil;
  for L in FFromTree.Leaves do
    Paths := Paths + [L.Path];

  U := ComputeUsage(Dfms, Pass, FBook.Nodes[FActiveHdr].FromType, Paths);
  FUsedProps := U.Names;
  FExamineInfo := Format('Examined %d file(s): %d of %d From properties used.',
    [U.DfmCount + U.PasCount, Length(U.Names), Length(Paths)]);
  if Length(Bad) > 0 then
    FExamineInfo := FExamineInfo + ' Unreadable: ' + string.Join(', ', Bad);
  SetStatus(FExamineInfo);
  FGrid.Invalidate;

  if Length(U.Missing) > 0 then
    ShowUsageReport(U.Missing);
end;

procedure TConvRulesForm.DoClearExamine(Sender: TObject);
begin
  FUsedProps := nil;
  FExamineInfo := '';
  FGrid.Invalidate;
  SetStatus('Examination cleared.');
end;
```

`FFromTree.Leaves` is the existing `TProptree` field; `TPropLeaf` has `Path` (see `ConvRules.Engine.pas`). `FBook.Nodes[FActiveHdr].FromType` is the active rule's From type — pass its BARE name to `ComputeUsage`: if it contains dots, take the segment after the last one, because a DFM writes `TabcToggleBtn`, never `Abcbtn.TabcToggleBtn`. Implement that as a two-line local, not inline in the call.

`ShowUsageReport` is a small private method showing a `CreateNew` form with a read-only `TMemo` listing the missing names, headed by one line explaining that these are used in the examined files but have no row in this grid.

- [ ] **Step 4: Paint the rows**

Assign `FGrid.OnDrawCell` in `BuildUI` and implement:

```pascal
procedure TConvRulesForm.GridDrawCell(Sender: TObject; ACol, ARow: Integer;
  Rect: TRect; State: TGridDrawState);
var
  Cv: TCanvas;
begin
  Cv := FGrid.Canvas;
  // Default painting for the header and for any row we are not marking, and always for
  // the selected cell so the selection stays visible on a green row.
  if (ARow > 0) and (gdSelected not in State)
     and (Length(FUsedProps) > 0)
     and IsRowUsed(PathOfGridCell(FGrid.Cells[0, ARow]), FUsedProps) then
    Cv.Brush.Color := $00D8F5D8   // pale green, readable behind black text
  else if gdSelected in State then
    Cv.Brush.Color := clHighlight
  else if gdFixed in State then
    Cv.Brush.Color := clBtnFace
  else
    Cv.Brush.Color := clWindow;

  if gdSelected in State then Cv.Font.Color := clHighlightText
  else Cv.Font.Color := clWindowText;

  Cv.FillRect(Rect);
  Cv.TextRect(Rect, Rect.Left + 2, Rect.Top + 2, FGrid.Cells[ACol, ARow]);
end;
```

`FGrid.DefaultDrawing` must be set `False` in `BuildUI` for `OnDrawCell` to own the painting; verify the grid still renders its header and selection correctly after the change.

`PathOfGridCell` already exists in the implementation section and strips the `' : type'` suffix.

- [ ] **Step 5: Re-apply on block change**

Wherever the grid is refilled for a newly selected block (`RefreshGrid` from the search-box work, or `LoadGridForBlock`), keep `FUsedProps` as-is so the marking re-applies to the new rows, and re-show `FExamineInfo` in the status bar when it is non-empty. Do NOT clear the examination on block change — the file set is a property of the session, not of the rule.

- [ ] **Step 6: Build both, run the suite**

Expected: both `BUILD_EXITCODE=0`, suite unchanged from Task 3's result, `0 fail`.

- [ ] **Step 7: Manual checklist**

Launch the freshly staged exe pinned to the healthy index (the Win32 library index is a broken fragment, so the default "Both" gives a truncated From list):

```
third_party\dll-win64\ConvRulesEditor.exe --from-platform win64
```

Work on a COPY of the rules file (`Copy-Item docs\examples\convrules\sample.rules "$env:TEMP\examine-test.rules"`); **never** open or save the repo's `docs\examples\convrules\sample.rules`.

Record what you actually observe for each:

1. With no examination run, no row is green (criterion 12).
2. `Examine...` with no conversion selected reports that a conversion must be selected, and does nothing.
3. Selecting `C:\Projects\DB\ORM3\CLIENT\VARINSP.dfm` for a `TabcToggleBtn` conversion turns `Left`, `Top`, `Width`, `Height`, `GroupIndex`, `Caption`, `Images`, `Layout` and `Picture` green, and leaves the great majority of the 3905 rows unpainted.
4. The status bar shows the examined/used counts.
5. Adding a `.pas` to the selection turns further rows green and the count rises.
6. `Clear marks` removes all green; the counts message is replaced.
7. Switching to another `#convert` block keeps the examination and re-marks the new rows.
8. Selection highlight is still clearly visible when the selected row is green.
9. The From/To search boxes still filter correctly with marking active, and a green row stays green when filtered.

- [ ] **Step 8: Commit**

```bash
git add src/tools/convrules-editor/ConvRules.MainForm.pas src/tools/convrules-editor/ConvRulesEditor.dpr
git commit -m "feat(convrules-editor): Examine button marks used From properties green"
```

## Acceptance criteria coverage

| # | Criterion | Task | Test |
|---|---|---|---|
| 1 | DFM assignments at the block's immediate level | 1, 3 | `TestScanDfm`, `TestComputeUsage` (real fixture) |
| 2 | Dotted assignment records path and root | 1 | `TestScanDfm` |
| 3 | `{ }` blob contents are not assignments | 1 | `TestScanDfm` |
| 4 | Nested component not attributed to From class | 1 | `TestScanDfm` |
| 5 | Nested instance OF the From class is scanned | 1 | `TestScanDfm` |
| 6 | No block of the From class yields empty | 1 | `TestScanDfm` |
| 7 | `.PropName` marks it used | 2 | `TestScanPasAndMatch` |
| 8 | `.PropNameExtra` does not | 2 | `TestScanPasAndMatch` |
| 9 | Row test: full path and last segment | 2 | `TestScanPasAndMatch` |
| 10 | Merge de-duplicates case-insensitively | 2 | `TestScanPasAndMatch` |
| 11 | Used names with no leaf are reported Missing | 3 | `TestComputeUsage` |
| 12 | No examination -> no green | 4 | manual step 1 |
