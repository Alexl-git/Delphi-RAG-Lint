# duplicate-code Clone Detection Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a `duplicate-code` lint rule that reports maximal identical runs of Type-2-normalized tokens (>= a token threshold) shared between two routines, within a file and across a project.

**Architecture:** A new isolated unit `DRagLint.Diagnostics.CloneChecks.pas` exposes `TCloneChecker.Check` (single file) and `TCloneChecker.CheckProject` (all files in a `lint-all` run). Both delegate to one internal engine: walk each `defProc` body, collect leaf tokens, normalize identifiers+literals to placeholders (Type-2), concatenate all routines' token streams separated by unique barriers, then Rabin-Karp rolling-hash every W-token window, bucket by hash, verify + left-maximal-extend each candidate pair, and emit findings. Wired into the CLI single-file `lint` path and the `lint-all` project path.

**Tech Stack:** Delphi 13 (Object Pascal), tree-sitter-delphi13 AST via `TAstParseCache`, existing lint finding/catalog/config infrastructure. Build Win64 via `build\build_draglint_win64.bat`. Tests via the two PowerShell harnesses.

## Global Constraints

- **Encoding:** all `.pas`/`.dfm` files strict 7-bit ASCII, CRLF line endings, no BOM, no Unicode. DocInsight `///` XML doc-comments required on public types/methods.
- **Rule id:** `duplicate-code`. **Category:** `complexity`. **Severity:** `info`. **Default:** ON. **Threshold param:** `threshold` (min clone length in normalized tokens); default `60` (final value set by Task 5 FP-sanity).
- **No double-reporting:** in `lint-all`, ONLY `CheckProject` runs (never the per-file `Check`); `Check` runs only in single-file `lint`.
- **Determinism:** anchor each finding at the occurrence with the lexicographically greater `(FilePath, StartLine)` key so cross-file output is independent of file-scan order. Sort the returned findings by `(FilePath, StartLine)`.
- **NULL-guard:** never call `.NodeType` on a null `TTSNode` (`.IsNull` short-circuit first) -- it access-violates in tree-sitter.DLL.
- **Build gotcha:** `Stop-Process drag-lint -Force` before building; the `.bat` `copy` step silently keeps a stale exe if the file is locked. Verify `LastWriteTime` after build. Test with the canonical `third_party\dll-win64\drag-lint.exe` (has the tree-sitter DLLs), never `src\cli\Win64\Release\drag-lint.exe`.
- **Spec:** `docs/superpowers/specs/2026-07-01-clone-detection-design.md`.

---

## File Structure

- **Create** `src/diagnostics/DRagLint.Diagnostics.CloneChecks.pas` -- the whole clone engine + `TCloneChecker`.
- **Modify** `src/cli/DRagLint.CLI.pas` -- add unit to `uses`; unknown-rule guard (~4765); help string (~4770); single-file dispatch (~4908); `lint-all` project hook (~5827).
- **Modify** `src/lint/DRagLint.Lint.RuleCatalog.pas` -- one `B('duplicate-code', ...)` line (~after 132).
- **Modify** `<drag-lint>.dproj` -- add the new unit to the project (so msbuild compiles it).
- **Create** `tests/lint/duplicate-code.pas` + `.expected` + `.config.json` -- within-file Type-2 fixture.
- **Create** `tests/lint/duplicate-code-none.pas` + `.expected` -- absent (no-clone) fixture.
- **Create** `tests/lint-store/duplicate-code/` (`unita.pas`, `unitb.pas`, `case.json`, `config.json`, `expected.txt`) -- cross-file fixture.

---

## Task 1: New unit -- clone engine + `TCloneChecker`, compiling

**Files:**
- Create: `src/diagnostics/DRagLint.Diagnostics.CloneChecks.pas`
- Modify: `<drag-lint>.dproj` (add `<DCCReference Include="src\diagnostics\DRagLint.Diagnostics.CloneChecks.pas"/>`)
- Modify: `src/cli/DRagLint.CLI.pas` (add `DRagLint.Diagnostics.CloneChecks` to the `uses` clause)

**Interfaces:**
- Produces:
  - `TCloneChecker.Check(const AFile: string; AMinTokens: Integer = 60): TArray<TLintFinding>`
  - `TCloneChecker.CheckProject(const AFiles: TArray<string>; AMinTokens: Integer = 60): TArray<TLintFinding>`
- Consumes: `TAstParseCache.Get` (parse), `NodeText` (from `DRagLint.Parser.Delphi13`), `TLintFinding` (from `DRagLint.Core.Model`), `TTSNode`/`TTSTree` helpers (from `TreeSitter`).

- [ ] **Step 1: Probe the grammar for identifier / literal node-type strings**

The Type-2 normalizer must know which leaf `NodeType` strings are identifiers vs literals. The exact strings are grammar-specific (same class of gotcha as the `case`-keyword-children issue). Probe with a throwaway:

Run (from repo root, after any build that exists):
```
third_party\dll-win64\drag-lint.exe ast-dump tests\lint\duplicate-code.pas
```
If no `ast-dump` subcommand exists, instead add a temporary `Writeln(N.NodeType)` in `CollectLeaves` during Step 3's first build and eyeball the leaf types for `X := X + 1`, a numeric literal, and a string literal. Confirm/adjust the sets in `IsIdentifierType` / `IsLiteralType` below. Candidates to verify: identifier = `identifier`; literals = `literalNumber`, `literalString`, `literalChar`, `char`, `literalFloat`. **Update the two functions in Step 3 to match reality before finalizing.**

- [ ] **Step 2: Write the failing test (within-file fixture)**

This is the RED test -- the harness runs the rule and it does not exist yet, so it fails.

Create `tests/lint/duplicate-code.pas` (CRLF, ASCII):
```pascal
unit dupcode;

interface

implementation

procedure AlphaSum(const A: array of Integer; out R: Integer);
var
  i, acc: Integer;
begin
  acc := 0;
  for i := 0 to High(A) do
    if A[i] > 0 then
      acc := acc + A[i]
    else
      acc := acc - A[i];
  R := acc;
end;

procedure BetaSum(const B: array of Integer; out S: Integer);
var
  k, tot: Integer;
begin
  tot := 0;
  for k := 0 to High(B) do
    if B[k] > 0 then
      tot := tot + B[k]
    else
      tot := tot - B[k];
  S := tot;
end;

end.
```
The two bodies are token-identical after identifier normalization but use different variable names -- so a Type-1 detector would miss them and a Type-2 detector catches them.

Create `tests/lint/duplicate-code.config.json`:
```json
{ "thresholds": { "duplicate-code": 12 } }
```

Create `tests/lint/duplicate-code.expected` with a PLACEHOLDER line to be corrected in Step 5 (write `21` for now -- the `procedure BetaSum` line):
```
duplicate-code 21
```

- [ ] **Step 3: Run the test to verify it fails**

Run:
```
pwsh -File tests\lint\run_lint_tests.ps1 -Filter duplicate-code
```
Expected: `FAIL  duplicate-code` (rule unknown / no finding produced).

- [ ] **Step 4: Write the unit (minimal engine to green)**

Create `src/diagnostics/DRagLint.Diagnostics.CloneChecks.pas`:
```pascal
unit DRagLint.Diagnostics.CloneChecks;

/// <summary>Type-2 (renamed-identifier tolerant) duplicate-code detection.
///  Reports maximal identical runs of normalized tokens (>= AMinTokens) shared
///  between two routines, within one file (Check) or across a project (CheckProject).</summary>
/// <remarks>Pure-AST: identifiers and literals are normalized to placeholders so
///  copy-paste-and-rename clones match; keywords/operators/punctuation are kept as
///  themselves. No statement reordering (not Type-3). Not thread-safe (uses the
///  shared parse cache). Anchors each finding at the lexicographically-later site
///  for deterministic output.</remarks>
interface

uses
  System.Generics.Collections,
  DRagLint.Core.Model;

type
  TCloneChecker = class
  public
    /// <summary>Within-file clones in AFile.</summary>
    /// <param name="AFile">Path to the .pas file to scan.</param>
    /// <param name="AMinTokens">Minimum clone length in normalized tokens.</param>
    /// <returns>One info finding per maximal clone pair, sorted by (FilePath, StartLine).</returns>
    class function Check(const AFile: string; AMinTokens: Integer = 60): TArray<TLintFinding>;
    /// <summary>Within + cross-file clones across AFiles (used by lint-all).</summary>
    /// <param name="AFiles">All .pas files in the project scan.</param>
    /// <param name="AMinTokens">Minimum clone length in normalized tokens.</param>
    /// <returns>One info finding per maximal clone pair, sorted by (FilePath, StartLine).</returns>
    class function CheckProject(const AFiles: TArray<string>; AMinTokens: Integer = 60): TArray<TLintFinding>;
  end;

implementation

uses
  System.SysUtils,
  System.Generics.Defaults,
  TreeSitter,
  DRagLint.Diagnostics.ParseCache,
  DRagLint.Parser.Delphi13; { NodeText }

type
  TTok = record
    Code : Integer; { >0 interned normalized token; <0 unique per-routine barrier }
    FileI: Integer; { index into AFiles; -1 for a barrier }
    Line : Integer; { 1-based source line }
  end;

function IsIdentifierType(const ANodeType: string): Boolean;
begin
  { VERIFY against the grammar probe (Task 1 Step 1) and adjust if needed. }
  Result := (ANodeType = 'identifier');
end;

function IsLiteralType(const ANodeType: string): Boolean;
begin
  { VERIFY against the grammar probe (Task 1 Step 1) and adjust if needed. }
  Result := (ANodeType = 'literalNumber')
         or (ANodeType = 'literalString')
         or (ANodeType = 'literalChar')
         or (ANodeType = 'char')
         or (ANodeType = 'literalFloat');
end;

function RunEngine(const AFiles: TArray<string>; AMinTokens: Integer): TArray<TLintFinding>;
var
  Toks      : TList<TTok>;
  Interner  : TDictionary<string, Integer>;
  RoutineSeq: Integer;
  W         : Integer;
  Findings  : TList<TLintFinding>;
  Seen      : TDictionary<string, Boolean>;

  procedure AddToken(const N: TTSNode; const Src: TBytes; AFileI: Integer);
  var
    nt, key, txt: string;
    code        : Integer;
    t           : TTok;
  begin
    nt := N.NodeType;
    if IsIdentifierType(nt) then
      key := #1'ID'
    else if IsLiteralType(nt) then
      key := #2'LIT'
    else
    begin
      txt := Trim(NodeText(N, Src));
      if txt = '' then Exit; { whitespace-only terminal }
      key := #3 + LowerCase(txt);
    end;
    if not Interner.TryGetValue(key, code) then
    begin
      code := Interner.Count + 1;
      Interner.Add(key, code);
    end;
    t.Code := code; t.FileI := AFileI; t.Line := Integer(N.StartPoint.Row) + 1;
    Toks.Add(t);
  end;

  procedure CollectLeaves(const ARoot, N: TTSNode; const Src: TBytes; AFileI: Integer);
  var i: Integer;
  begin
    if N.IsNull then Exit;
    if N.IsExtra then Exit; { comments }
    if (not (N = ARoot)) and (N.NodeType = 'defProc') then Exit; { nested routine handled separately }
    if N.ChildCount = 0 then begin AddToken(N, Src, AFileI); Exit; end;
    for i := 0 to N.ChildCount - 1 do
      CollectLeaves(ARoot, N.Child(i), Src, AFileI);
  end;

  procedure EmitBarrier;
  var t: TTok;
  begin
    Inc(RoutineSeq);
    t.Code := -RoutineSeq; t.FileI := -1; t.Line := 0;
    Toks.Add(t);
  end;

  procedure VisitRoutines(const N: TTSNode; const Src: TBytes; AFileI: Integer);
  var i: Integer;
  begin
    if N.IsNull then Exit;
    if N.NodeType = 'defProc' then
    begin
      CollectLeaves(N, N, Src, AFileI);
      EmitBarrier;
      for i := 0 to N.ChildCount - 1 do
        VisitRoutines(N.Child(i), Src, AFileI); { nested routines }
    end
    else
      for i := 0 to N.ChildCount - 1 do
        VisitRoutines(N.Child(i), Src, AFileI);
  end;

  function TokensEqual(a, b, Len: Integer): Boolean;
  var k: Integer;
  begin
    Result := True;
    for k := 0 to Len - 1 do
      if Toks[a + k].Code <> Toks[b + k].Code then Exit(False);
  end;

  procedure EmitPair(a, b, Len: Integer);
  var
    ta, tb, anchor, other: TTok;
    key                  : string;
    F                    : TLintFinding;
    aKeyGreater          : Boolean;
  begin
    ta := Toks[a]; tb := Toks[b];
    { anchor = lexicographically greater (FilePath, Line) for deterministic output }
    if AFiles[ta.FileI] > AFiles[tb.FileI] then
      aKeyGreater := True
    else if AFiles[ta.FileI] < AFiles[tb.FileI] then
      aKeyGreater := False
    else
      aKeyGreater := ta.Line >= tb.Line;
    if aKeyGreater then begin anchor := ta; other := tb; end
                   else begin anchor := tb; other := ta; end;

    key := AFiles[anchor.FileI] + '|' + IntToStr(anchor.Line) + '|' +
           AFiles[other.FileI] + '|' + IntToStr(other.Line);
    if Seen.ContainsKey(key) then Exit;
    Seen.Add(key, True);

    F := Default(TLintFinding);
    F.RuleId    := 'duplicate-code';
    F.Severity  := 'info';
    F.FilePath  := AFiles[anchor.FileI];
    F.StartLine := anchor.Line;
    F.StartCol  := 1;
    F.EndLine   := anchor.Line;
    F.EndCol    := 1;
    F.Message   := Format('Duplicated code block (%d tokens) -- also at %s:%d',
                          [Len, AFiles[other.FileI], other.Line]);
    Findings.Add(F);
  end;

  procedure Match;
  var
    N, i, start, a, b, p, q, L, MaxBucket: Integer;
    NextBar  : TArray<Integer>;
    Base, PowW, h: UInt64;
    Buckets  : TDictionary<UInt64, TList<Integer>>;
    lst      : TList<Integer>;
  begin
    N := Toks.Count;
    if N < W then Exit;
    Base := UInt64(1000003);
    PowW := 1;
    for i := 1 to W do PowW := PowW * Base; { Base^W (natural mod 2^64) }

    { NextBar[i] = smallest k>=i with Toks[k] a barrier, else N }
    SetLength(NextBar, N + 1);
    NextBar[N] := N;
    for i := N - 1 downto 0 do
      if Toks[i].Code <= 0 then NextBar[i] := i else NextBar[i] := NextBar[i + 1];

    Buckets := TDictionary<UInt64, TList<Integer>>.Create;
    try
      h := 0;
      for i := 0 to N - 1 do
      begin
        h := h * Base + UInt64(Cardinal(Toks[i].Code));
        if i >= W then
          h := h - UInt64(Cardinal(Toks[i - W].Code)) * PowW;
        if i >= W - 1 then
        begin
          start := i - (W - 1);
          if NextBar[start] > i then { window [start..i] barrier-free }
          begin
            if not Buckets.TryGetValue(h, lst) then
            begin lst := TList<Integer>.Create; Buckets.Add(h, lst); end;
            lst.Add(start);
          end;
        end;
      end;

      MaxBucket := 64; { degenerate boilerplate guard -- skip pathological buckets }
      for lst in Buckets.Values do
      begin
        if lst.Count < 2 then Continue;
        if lst.Count > MaxBucket then Continue;
        for p := 0 to lst.Count - 2 do
          for q := p + 1 to lst.Count - 1 do
          begin
            a := lst[p]; b := lst[q];
            if not TokensEqual(a, b, W) then Continue; { hash-collision guard }
            { left-maximal: skip if this is a right-shift of a longer match }
            if (a > 0) and (b > 0)
               and (Toks[a - 1].Code > 0) and (Toks[b - 1].Code > 0)
               and (Toks[a - 1].Code = Toks[b - 1].Code) then Continue;
            { extend right within both routines }
            L := W;
            while (a + L < N) and (b + L < N)
                  and (Toks[a + L].Code > 0)
                  and (Toks[a + L].Code = Toks[b + L].Code) do
              Inc(L);
            if Abs(a - b) < L then Continue; { same-routine overlap }
            EmitPair(a, b, L);
          end;
      end;
    finally
      for lst in Buckets.Values do lst.Free;
      Buckets.Free;
    end;
  end;

var
  fi: Integer;
  PF: TParsedFile;
begin
  Result := nil;
  W := AMinTokens;
  if W < 1 then W := 60;
  Toks     := TList<TTok>.Create;
  Interner := TDictionary<string, Integer>.Create;
  Findings := TList<TLintFinding>.Create;
  Seen     := TDictionary<string, Boolean>.Create;
  try
    RoutineSeq := 0;
    for fi := 0 to High(AFiles) do
    begin
      PF := TAstParseCache.Get(AFiles[fi]);
      if PF.Tree = nil then Continue;
      VisitRoutines(PF.Tree.RootNode, PF.Src, fi);
    end;
    Match;
    Findings.Sort(TComparer<TLintFinding>.Construct(
      function(const L, R: TLintFinding): Integer
      begin
        Result := CompareStr(L.FilePath, R.FilePath);
        if Result = 0 then Result := L.StartLine - R.StartLine;
      end));
    Result := Findings.ToArray;
  finally
    Seen.Free; Findings.Free; Interner.Free; Toks.Free;
  end;
end;

class function TCloneChecker.Check(const AFile: string; AMinTokens: Integer): TArray<TLintFinding>;
begin
  Result := RunEngine([AFile], AMinTokens);
end;

class function TCloneChecker.CheckProject(const AFiles: TArray<string>; AMinTokens: Integer): TArray<TLintFinding>;
begin
  Result := RunEngine(AFiles, AMinTokens);
end;

end.
```

Add the unit to the `.dproj` `<ItemGroup>` of source references (find the sibling line for `DRagLint.Diagnostics.DeadCodeChecks.pas` and copy its form for CloneChecks).

Add `DRagLint.Diagnostics.CloneChecks` to the `uses` clause of `src/cli/DRagLint.CLI.pas` (next to `DRagLint.Diagnostics.DeadCodeChecks`).

- [ ] **Step 5: Wire the single-file dispatch and correct the fixture line**

In `src/cli/DRagLint.CLI.pas`:

1. Unknown-rule guard -- change the tail of line ~4765 from:
```pascal
  (AArgs.Rule <> 'lossy-cast') and (AArgs.Rule <> 'cognitive-complexity') then
```
to:
```pascal
  (AArgs.Rule <> 'lossy-cast') and (AArgs.Rule <> 'cognitive-complexity') and
  (AArgs.Rule <> 'duplicate-code') then
```

2. Help/known-rule string -- in the literal at line ~4770 change `..., cognitive-complexity)'` to `..., cognitive-complexity, duplicate-code)'`.

3. Single-file dispatch -- immediately after the DeadCodeChecker block (after line ~4908, before `TAstParseCache.Clear`) insert:
```pascal
      { v0.77: clone / duplicate-code detection (#6) -- within-file (single-file lint).
        lint-all uses CheckProject instead (see DoLintAll) so within-file clones are
        not double-reported. }
      if (AArgs.Rule = '') or (AArgs.Rule = 'duplicate-code') then
        for F in DRagLint.Diagnostics.CloneChecks.TCloneChecker.Check(AArgs.Path,
            Cfg.ThresholdFor('duplicate-code', 60)) do
          if (AArgs.Rule = '') or (AArgs.Rule = F.RuleId) then Findings:= Findings + [F];
```

Build (Task template below) and run:
```
third_party\dll-win64\drag-lint.exe lint tests\lint\duplicate-code.pas --config tests\lint\duplicate-code.config.json
```
Note the reported line for `duplicate-code`. If it differs from `21`, set `tests/lint/duplicate-code.expected` to the actual reported line.

- [ ] **Step 6: Build Win64**

```
pwsh -Command "Stop-Process -Name drag-lint -Force -ErrorAction SilentlyContinue; Start-Process -Wait -NoNewWindow -FilePath build\build_draglint_win64.bat -RedirectStandardOutput $env:TEMP\dl_build.log -RedirectStandardError $env:TEMP\dl_build.err.log; Get-Content $env:TEMP\dl_build.log -Tail 8"
```
Expected: `BUILD_EXITCODE=0`, no `[dcc] Error`. Verify the exe `LastWriteTime` is now.

- [ ] **Step 7: Run the within-file test to verify it passes**

```
pwsh -File tests\lint\run_lint_tests.ps1 -Filter duplicate-code
```
Expected: `PASS  duplicate-code`.

- [ ] **Step 8: Commit**

```
git add src/diagnostics/DRagLint.Diagnostics.CloneChecks.pas src/cli/DRagLint.CLI.pas *.dproj tests/lint/duplicate-code.pas tests/lint/duplicate-code.expected tests/lint/duplicate-code.config.json
git commit -m "feat(lint): duplicate-code clone engine + within-file detection (#6)"
```

---

## Task 2: Cross-file detection via `lint-all` (`CheckProject`)

**Files:**
- Modify: `src/cli/DRagLint.CLI.pas:5827` (DoLintAll project-rule region)
- Create: `tests/lint-store/duplicate-code/unita.pas`, `unitb.pas`, `case.json`, `config.json`, `expected.txt`

**Interfaces:**
- Consumes: `TCloneChecker.CheckProject(FilePaths, AMinTokens)` from Task 1; `FilePaths: TArray<string>` (already built in DoLintAll at line ~5735) and `Cfg.ThresholdFor`.

- [ ] **Step 1: Write the failing test (cross-file store fixture)**

Create `tests/lint-store/duplicate-code/unita.pas` (CRLF, ASCII):
```pascal
unit unita;

interface

implementation

procedure AlphaSum(const A: array of Integer; out R: Integer);
var
  i, acc: Integer;
begin
  acc := 0;
  for i := 0 to High(A) do
    if A[i] > 0 then
      acc := acc + A[i]
    else
      acc := acc - A[i];
  R := acc;
end;

end.
```

Create `tests/lint-store/duplicate-code/unitb.pas` (CRLF, ASCII):
```pascal
unit unitb;

interface

implementation

procedure BetaSum(const B: array of Integer; out S: Integer);
var
  k, tot: Integer;
begin
  tot := 0;
  for k := 0 to High(B) do
    if B[k] > 0 then
      tot := tot + B[k]
    else
      tot := tot - B[k];
  S := tot;
end;

end.
```

Create `tests/lint-store/duplicate-code/case.json`:
```json
{ "mode": "lint-all" }
```

Create `tests/lint-store/duplicate-code/config.json`:
```json
{ "thresholds": { "duplicate-code": 12 } }
```

Create `tests/lint-store/duplicate-code/expected.txt` (anchor is `unitb.pas` because `"unitb..." > "unita..."` lexicographically; correct the line number after Step 4):
```
duplicate-code unitb.pas:6
```

- [ ] **Step 2: Run to verify it fails**

```
pwsh -File tests\lint-store\run_store_tests.ps1 -Filter duplicate-code
```
Expected: `FAIL  duplicate-code` (no cross-file finding yet -- `CheckProject` is not wired).

- [ ] **Step 3: Wire `CheckProject` into DoLintAll**

In `src/cli/DRagLint.CLI.pas`, immediately after the project-wide `ProjectRules...Run` call (line ~5827) insert:
```pascal
  { v0.77: cross-file + within-file clone detection (#6). Runs ONLY here in
    lint-all (never the per-file Check) so within-file clones are reported once. }
  Findings:= Findings +
    DRagLint.Diagnostics.CloneChecks.TCloneChecker.CheckProject(FilePaths,
      Cfg.ThresholdFor('duplicate-code', 60));
```

- [ ] **Step 4: Build, then correct the expected line**

Build (Task 1 Step 6 recipe). Then run the store harness (Step 2). If it fails only on the line number, read the `actual:` line the harness prints and set `expected.txt` to that `unitb.pas:<line>`.

- [ ] **Step 5: Run to verify it passes**

```
pwsh -File tests\lint-store\run_store_tests.ps1 -Filter duplicate-code
```
Expected: `PASS  duplicate-code`.

- [ ] **Step 6: Commit**

```
git add src/cli/DRagLint.CLI.pas tests/lint-store/duplicate-code
git commit -m "feat(lint): cross-file duplicate-code via CheckProject in lint-all (#6)"
```

---

## Task 3: Absent-case fixture (no false positive on distinct routines)

**Files:**
- Create: `tests/lint/duplicate-code-none.pas`, `tests/lint/duplicate-code-none.expected`, `tests/lint/duplicate-code-none.config.json`

**Interfaces:** none new (exercises Task 1's `Check`).

- [ ] **Step 1: Write the test (two genuinely different routines)**

Create `tests/lint/duplicate-code-none.pas` (CRLF, ASCII):
```pascal
unit dupnone;

interface

implementation

function Greet(const AName: string): string;
begin
  Result := 'Hello, ' + AName + '!';
end;

procedure Countdown(AFrom: Integer);
var
  n: Integer;
begin
  n := AFrom;
  while n > 0 do
  begin
    Writeln(n);
    Dec(n);
  end;
end;

end.
```

Create `tests/lint/duplicate-code-none.config.json`:
```json
{ "thresholds": { "duplicate-code": 12 } }
```

Create `tests/lint/duplicate-code-none.expected`:
```
!duplicate-code
```

- [ ] **Step 2: Run to verify it passes (no build needed -- rule already built)**

```
pwsh -File tests\lint\run_lint_tests.ps1 -Filter duplicate-code-none
```
Expected: `PASS  duplicate-code-none`. If it FAILS (a clone was reported), the threshold/normalizer is too aggressive -- investigate before proceeding (do not just raise the fixture threshold to mask it).

- [ ] **Step 3: Commit**

```
git add tests/lint/duplicate-code-none.pas tests/lint/duplicate-code-none.expected tests/lint/duplicate-code-none.config.json
git commit -m "test(lint): duplicate-code absent-case fixture (no FP on distinct routines)"
```

---

## Task 4: Register in the rule catalog

**Files:**
- Modify: `src/lint/DRagLint.Lint.RuleCatalog.pas` (complexity section, after line ~132)

**Interfaces:** none new.

- [ ] **Step 1: Add the catalog entry**

After the `boolean-expression-complexity` line (~132) add:
```pascal
    B('duplicate-code',       'complexity', 'info', 'Duplicated code block detected (Type-2, renamed-identifier tolerant)', True, [MkParam('threshold','int','60')]);
```

- [ ] **Step 2: Build and run the catalog test**

Build (Task 1 Step 6 recipe), then:
```
pwsh -File tests\lint\run_rulecatalog_tests.ps1
```
Expected: all catalog tests pass (relative self-checks; no count bump needed).

- [ ] **Step 3: Commit**

```
git add src/lint/DRagLint.Lint.RuleCatalog.pas
git commit -m "feat(lint): register duplicate-code in rule catalog (complexity)"
```

---

## Task 5: FP-sanity over `src/` and set the shipped default threshold

**Files:**
- Modify: `src/cli/DRagLint.CLI.pas` (two `Cfg.ThresholdFor('duplicate-code', 60)` defaults), `src/lint/DRagLint.Lint.RuleCatalog.pas` (MkParam default), `docs/superpowers/specs/2026-07-01-clone-detection-design.md` (record chosen default), `CHANGELOG.md`.

**Interfaces:** none new.

- [ ] **Step 1: Measure findings on the codebase's own source**

Build first (Task 1 Step 6). Then:
```
third_party\dll-win64\drag-lint.exe lint-all src --rule duplicate-code --json > %TEMP%\dup.json 2>NUL
pwsh -Command "(Get-Content $env:TEMP\dup.json -Raw | ConvertFrom-Json).Count"
```
(If `lint-all` needs a `--db`, index first: `drag-lint index src --db %TEMP%\dl_src.sqlite` then `lint-all --db %TEMP%\dl_src.sqlite --rule duplicate-code --json`.)

- [ ] **Step 2: Inspect and choose the default**

Read the findings. For each, confirm it is genuine duplication (open the two sites). Raise the default `threshold` (start 60; try 80, 100) until the remaining findings on `src/` are ~0 or all legitimately-duplicated blocks. Pick the smallest threshold that achieves that -- call it `W_final`.

- [ ] **Step 3: Apply `W_final` in all three default sites**

Replace `60` with `W_final` in:
- `src/cli/DRagLint.CLI.pas` single-file dispatch (Task 1 Step 5 item 3)
- `src/cli/DRagLint.CLI.pas` DoLintAll `CheckProject` call (Task 2 Step 3)
- `src/lint/DRagLint.Lint.RuleCatalog.pas` `MkParam('threshold','int','60')`
- the unit's two `AMinTokens: Integer = 60` default parameters in `CloneChecks.pas`

- [ ] **Step 4: Rebuild and re-run all three harnesses**

Build (Task 1 Step 6), then:
```
pwsh -File tests\lint\run_lint_tests.ps1
pwsh -File tests\lint-store\run_store_tests.ps1
pwsh -File tests\lint\run_rulecatalog_tests.ps1
```
Expected: all green (file harness count +2, store harness +1 vs pre-task baselines). The fixtures use a per-case config threshold of 12, so they are unaffected by `W_final`.

- [ ] **Step 5: Record the default and commit**

Update the spec (replace `<W>`/60 mentions with `W_final` and a one-line rationale) and add a CHANGELOG "Unreleased" bullet:
```
- feat(lint): duplicate-code (#6) -- Type-2 clone detection, within-file + cross-file, info/ON, default threshold <W_final> tokens.
```
Then:
```
git add src/cli/DRagLint.CLI.pas src/lint/DRagLint.Lint.RuleCatalog.pas src/diagnostics/DRagLint.Diagnostics.CloneChecks.pas docs/superpowers/specs/2026-07-01-clone-detection-design.md CHANGELOG.md
git commit -m "feat(lint): calibrate duplicate-code default threshold to <W_final> (FP-sanity on src/)"
```

---

## Notes for the implementer

- **Release is out of scope for this plan.** `duplicate-code` ships as part of the v0.77 milestone alongside the CK suite and M2-flow items. Do NOT bump VERSION / tag / gh-release here -- leave the CHANGELOG bullet under "Unreleased".
- **If the within-file clone anchor line surprises you:** the finding anchors at the FIRST token of the duplicated run in the lexicographically-later routine -- because the two routines' headers also normalize identically, the run usually starts at the routine's `procedure`/`function` line. That is expected; set `.expected` to whatever the tool deterministically reports.
- **If the store harness cross-file case reports the finding in `unita.pas` instead of `unitb.pas`:** the anchor rule compares full file PATHS, not basenames -- confirm both temp paths share a directory so `unitb...` sorts after `unita...`; they do (same case dir). If a path quirk flips it, set `expected.txt` to the file the tool reports.

## Self-Review

- **Spec coverage:** new unit + two entry points (Task 1/2) ✓; Type-2 normalization (Task 1 Step 4) ✓; Rabin-Karp maximal-match (Task 1 `Match`) ✓; within-file + cross-file (Task 1/2) ✓; info/ON + threshold param (Task 4) ✓; no-double-report (Task 2 wiring note) ✓; fixtures in tests/lint + tests/lint-store (Task 1/2/3) ✓; FP-sanity to set default (Task 5) ✓; deterministic anchor + sort (Task 1 `EmitPair`/sort) ✓.
- **Placeholders:** the `21` / `unitb.pas:6` expected lines are explicitly corrected against tool output in Task 1 Step 5 / Task 2 Step 4 (a run-and-record step, not a leftover TODO). `W_final` is resolved in Task 5. Grammar node-type strings are probed in Task 1 Step 1.
- **Type consistency:** `Check`/`CheckProject` signatures identical across unit, CLI wiring, and catalog; `TLintFinding` fields match `Core.Model.pas`; `ThresholdFor(name, default)` matches existing usage.
