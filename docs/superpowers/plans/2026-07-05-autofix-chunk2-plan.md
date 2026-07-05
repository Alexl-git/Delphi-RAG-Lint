# AutoFix Chunk 2 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make 6 more lint rules mechanically fixable (`redundant-not-not`, `redundant-as-tobject`, `boolean-comparison-true`, `reserved-word-casing`, `redundant-assigned-free`, `off-by-one-count`), add a `risky`-fix tag to contain the one behaviour-changing rule, lock+document the already-correct batch-gating behaviour, close 2 deferred Minors, and publish v0.89.0-alpha.

**Architecture:** AutoFix keys off one registry (`FIXABLE_RULE_IDS` in `src/cli/DRagLint.CLI.pas`) and one builder (`BuildAutofixEdits`). Each new rule = one array entry + one guarded `else if` branch emitting a single `tekReplaceInLine` edit over the finding's span. The catalog `fixable` flag, the CLI fix verbs, the IDE "Fix it" menu, and the auto-fix checkbox all read the registry, so they light up automatically. A second registry `RISKY_FIX_RULE_IDS` + `IsRiskyFixRule` tags the one behaviour-changing rule (`off-by-one-count`); its fix still applies (Fix-it + Fix-all) but the `--fix --json` output carries `risky:true` and the text output notes it. No new CLI verb, no IDE code, no index-schema change.

**Scope note (revised):** The original plan had 3 fixable rules (Tasks 2-4). This revision adds 3 more (Tasks 4A reserved-word-casing, 4B redundant-assigned-free, 4C off-by-one-count) + the risky-tag mechanism (Task 4D, done before 4C's test needs it), per the 163-rule sweep + user decision to include ALL verified finds. Task 5 (catalog) now expects **9** fixable. Tasks 6-9 unchanged in intent.

**Tech Stack:** Delphi 13 (RAD Studio 37), Object Pascal, tree-sitter (`.scm` query rules + Pascal AST checks), PowerShell test harnesses, delphi-build skill (rsvars + msbuild).

## Global Constraints

- **Encoding:** all `.pas` fixtures and source edits are strict 7-bit ASCII, CRLF line endings, no BOM. Never introduce Unicode or LF.
- **DocInsight:** any new public function gets a `///` `<summary>` spec-comment; keep the comment, the test, and the code in agreement.
- **Build:** use the `delphi-build` skill (3-line wrapper `.bat` -> `rsvars` -> `cd` -> `msbuild`, run via PowerShell `Start-Process -Wait`, read the log for `BUILD_EXITCODE=0` and no `[dcc] Error`). The staged CLI exe is `third_party\dll-win64\drag-lint.exe` (Win64). Do NOT run the raw Release exe (0xC0000135) and do NOT use the MCP build tool.
- **Test CWD:** run PowerShell harnesses from a NEUTRAL CWD (`C:\TEMP`) so no ambient `drag-lint-lint.json` is picked up.
- **Fixture naming:** each fixture's `unit` name must match its filename so `unit-name-matches-file` stays quiet.
- **Guardrail (must stay green after every task):** lint suite 154/154, store 16/16, and the existing autofix suites (`run_fix_single.ps1`, `run_fix_unit.ps1`, `run_fix_project.ps1`, `run_fixable_catalog.ps1`).
- **Release commit hygiene:** the release commit contains ONLY `DRagLint.CLI.pas` (VERSION bump) + CHANGELOG + BACKLOG (+ the new source/test/doc changes belong to their own feature commits). Any rebuilt BPL/DCP goes in a SEPARATE `build(plugin):` commit. The release ZIP is CLI-only.

**Key existing locations (verified this session):**
- `FIXABLE_RULE_IDS` const array: `src/cli/DRagLint.CLI.pas:4458`
- `IsFixableRule`: `src/cli/DRagLint.CLI.pas:4461`
- `BuildAutofixEdits` (the 3 existing branches): `src/cli/DRagLint.CLI.pas:4489-4592`
- The `--fix` block (JSON emit + text emit): `src/cli/DRagLint.CLI.pas:4653-4714`; the `applied` pair is line 4689; the sarif output path (bypassed by `--fix`) is line 4717.
- `VERSION` const: `src/cli/DRagLint.CLI.pas:6`
- `TTextEdit` / `TTextEditApplier` / `tekReplaceInLine`: `src/refactor/DRagLint.Refactor.TextEdit.pas:17-41` (record fields: `FilePath, Kind, Line, Col, EndCol, EndLine, Text`; `tekReplaceInLine` replaces 1-based `[Col, EndCol)` with `Text`).
- Fixture dir: `tests/autofix/fixtures/`; harness pattern: `tests/autofix/run_fix_single.ps1`.
- `.scm` span = whole `@warn` node (`src/lint/DRagLint.Lint.QueryRules.pas:306-309`), so each rule's finding span already bounds the whole offending expression.

---

## Task 1: `IsSingleTokenAtom` helper (correctness-critical)

**Files:**
- Modify: `src/cli/DRagLint.CLI.pas` (add the function just above `BuildAutofixEdits`, near line 4488)
- Test: `tests/autofix/run_atom_helper.ps1` (drives it indirectly via the boolean fixture in Task 4; a direct DUnit-style test is not wired here, so Task 1's verification is a compile + a targeted `boolean-comparison-true` compound case). See Step 2.

**Interfaces:**
- Produces: `function IsSingleTokenAtom(const S: string): Boolean;` -- returns True iff `Trim(S)` is a lone primary term (identifier / dotted chain with only balanced `()`/`[]` suffixes and `.ident` segments, no top-level operator, no top-level whitespace); False otherwise (compound -> caller wraps in parens). Consumed by the `boolean-comparison-true` branch in Task 4.

- [ ] **Step 1: Write the helper with its DocInsight comment**

Insert into the `implementation` section of `src/cli/DRagLint.CLI.pas`, immediately BEFORE the `BuildAutofixEdits` DocInsight comment (line ~4476):

```pascal
/// <summary>True iff S (trimmed) is a lone primary term -- an identifier or
/// dotted chain, optionally followed only by balanced call '(...)' / index
/// '[...]' groups and '.ident' segments, with NO top-level operator and NO
/// top-level whitespace. Answers "can 'not S' be written WITHOUT parentheses?".
/// Errs toward False (compound): over-wrapping 'not (X)' is harmless, but
/// under-wrapping 'not a and b' silently changes meaning.</summary>
function IsSingleTokenAtom(const S: string): Boolean;
var
  T   : string ;
  I   : Integer;
  Depth: Integer;
  C   : Char   ;
  function IsIdentStart(Ch: Char): Boolean;
  begin Result:= CharInSet(Ch, ['A'..'Z','a'..'z','_']); end;
  function IsIdentChar(Ch: Char): Boolean;
  begin Result:= CharInSet(Ch, ['A'..'Z','a'..'z','_','0'..'9']); end;
begin
  T:= Trim(S);
  if (T = '') or (not IsIdentStart(T[1])) then Exit(False);
  Depth:= 0;
  I:= 1;
  while I <= Length(T) do
  begin
    C:= T[I];
    if (C = '(') or (C = '[') then Inc(Depth)
    else if (C = ')') or (C = ']') then
    begin
      Dec(Depth);
      if Depth < 0 then Exit(False);
    end
    else if Depth = 0 then
    begin
      { at top level, only identifier chars and a '.' between segments are allowed;
        anything else (whitespace, operator char, ',', ':', etc.) => compound. }
      if not (IsIdentChar(C) or (C = '.')) then Exit(False);
    end;
    Inc(I);
  end;
  Result:= (Depth = 0);
end;
```

- [ ] **Step 2: Compile to verify it builds**

Build the CLI via the delphi-build skill. Expected: `BUILD_EXITCODE=0`, no `[dcc] Error`. (The helper is exercised behaviorally by Task 4's compound fixture case `(A and B) = False`; there is no standalone unit-test host in this repo for a private CLI function, so the compound behaviour is asserted through the fix output in Task 4.)

- [ ] **Step 3: Commit**

```bash
git add src/cli/DRagLint.CLI.pas
git commit -m "feat(autofix): IsSingleTokenAtom helper for the compound-operand paren guard"
```

---

## Task 2: `redundant-not-not` fix branch + fixture

**Files:**
- Modify: `src/cli/DRagLint.CLI.pas` -- add `'redundant-not-not'` to `FIXABLE_RULE_IDS` (line 4458) and a branch in `BuildAutofixEdits` (after the `redundant-cast` branch, ~line 4586); update the `BuildAutofixEdits` DocInsight summary list.
- Create: `tests/autofix/fixtures/redundant_not_not.pas`
- Create: `tests/autofix/run_fix_newrules.ps1` (shared harness for Tasks 2-4; this task adds the `redundant-not-not` case)

**Interfaces:**
- Consumes: `IsFixableRule`, `BuildAutofixEdits`, `tekReplaceInLine` (unchanged signatures).
- Produces: fixture `redundant_not_not.pas` with `B := not not Flag;` on a known line; harness `run_fix_newrules.ps1` asserting preview+apply.

- [ ] **Step 1: Write the failing test (fixture + harness case)**

Create `tests/autofix/fixtures/redundant_not_not.pas` (ASCII, CRLF):

```pascal
unit redundant_not_not;

interface

implementation

procedure Demo;
var
  Flag, B: Boolean;
begin
  Flag := True;
  B := not not Flag;
end;

end.
```

(The `B := not not Flag;` line is line 12.)

Create `tests/autofix/run_fix_newrules.ps1` with a reusable checker and the `redundant-not-not` case:

```powershell
[CmdletBinding()]
param([string]$Exe = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe")
$ErrorActionPreference = 'Stop'; $fail = $false
function Check($n,$ok){ Write-Host ("[{0}] {1}" -f (@('FAIL','PASS')[[int]$ok]),$n) -ForegroundColor (@('Red','Green')[[int]$ok]); if(-not $ok){$script:fail=$true} }
$exePath = (Resolve-Path $Exe).Path

# Apply the single fix (rule R at line L) to a fresh copy of $fixtureName and
# assert the resulting 1-based line $L equals $expect (trimmed).
function Assert-Fix($fixtureName, $L, $R, $expect, $tag) {
  $fixture = (Resolve-Path (Join-Path $PSScriptRoot "fixtures\$fixtureName")).Path
  $scratch = Join-Path C:\TEMP ('draglint_newrules_' + [IO.Path]::GetFileNameWithoutExtension($fixtureName))
  if (Test-Path $scratch) { Remove-Item $scratch -Recurse -Force }
  New-Item -ItemType Directory -Path $scratch | Out-Null
  $target = Join-Path $scratch $fixtureName
  Copy-Item $fixture $target -Force
  Push-Location C:\TEMP
  try {
    $args = @('lint','--file',$target,'--fix','--fix-line',$L,'--fix-rule',$R,'--json','--apply')
    $raw = & $exePath @args 2>$null | Out-String
    $arr = $null; try { $arr = ($raw | ConvertFrom-Json) } catch { $arr = $null }
    if ($null -ne $arr -and $arr -isnot [System.Array]) { $arr = @($arr) }
    $t = $null; if ($null -ne $arr) { $t = $arr | Where-Object { $_.rule -eq $R } | Select-Object -First 1 }
    Check "$tag: targeted finding present"    ($null -ne $t)
    if ($null -ne $t) { Check "$tag: applied=true" ($t.applied -eq $true) }
    $lines = [IO.File]::ReadAllLines($target)
    $got = if ($lines.Count -ge $L) { $lines[$L-1].Trim() } else { '' }
    Check "$tag: line $L => '$expect' (got '$got')" ($got -eq $expect)
  } finally { Pop-Location }
}

Assert-Fix 'redundant_not_not.pas' 12 'redundant-not-not' 'B := Flag;' '[not-not]'

if($fail){ Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
```

- [ ] **Step 2: Run the harness to verify it fails**

From `C:\TEMP`, run:
`pwsh -File C:\Projects\Delphi-RAG-lint\tests\autofix\run_fix_newrules.ps1`
Expected: FAIL on `[not-not]: applied=true` and the line-content check -- the rule is not yet in `FIXABLE_RULE_IDS`, so no fix is produced (line stays `B := not not Flag;`).

- [ ] **Step 3: Add the rule to the registry + a fix branch**

In `src/cli/DRagLint.CLI.pas`, extend the array at line 4458:

```pascal
  FIXABLE_RULE_IDS: array[0..3] of string =
    ('self-assignment', 'redundant-parentheses', 'redundant-cast',
     'redundant-not-not');
```

Add this branch in `BuildAutofixEdits` after the `redundant-cast` branch (the `end` at ~line 4586), before the closing `end;` of the `for` loop:

```pascal
      else if SameText(F.RuleId, 'redundant-not-not')
              and (F.StartLine = F.EndLine) and (F.EndCol > F.StartCol) then
      begin
        { span covers 'not not X' (the outer exprUnary). Strip the two leading
          'not' keywords + their trailing whitespace; the remainder is X. }
        SL:= LinesFor(F.FilePath);
        if (F.StartLine >= 1) and (F.StartLine <= SL.Count) then
        begin
          Ln:= SL[F.StartLine - 1];
          Span:= Copy(Ln, F.StartCol, F.EndCol - F.StartCol);
          var Rest: string:= Span;
          var Ok: Boolean:= True;
          { consume 'not' then >=1 whitespace, twice }
          for var Pass: Integer:= 1 to 2 do
          begin
            var LR: string:= TrimLeft(Rest);
            if (Length(LR) >= 3) and SameText(Copy(LR, 1, 3), 'not')
               and ((Length(LR) = 3) or (LR[4] <= ' ')) then
              Rest:= TrimLeft(Copy(LR, 4, MaxInt))
            else
            begin Ok:= False; Break; end;
          end;
          if Ok and (Rest <> '') then
          begin
            E:= Default(TTextEdit);
            E.FilePath:= F.FilePath;
            E.Kind    := tekReplaceInLine;
            E.Line    := F.StartLine;
            E.Col     := F.StartCol;
            E.EndCol  := F.EndCol;
            E.Text    := Rest;
            Result:= Result + [E];
            Inc(AFixableCount);
          end;
        end;
      end
```

Update the `BuildAutofixEdits` `<summary>` (line ~4479) to append a line:
`///   redundant-not-not      -> strip the two leading 'not' keywords;`

- [ ] **Step 4: Build, then run the harness to verify it passes**

Build via delphi-build (`BUILD_EXITCODE=0`). Then from `C:\TEMP`:
`pwsh -File C:\Projects\Delphi-RAG-lint\tests\autofix\run_fix_newrules.ps1`
Expected: PASS (`[not-not]` line 12 becomes `B := Flag;`, applied=true).

- [ ] **Step 5: Commit**

```bash
git add src/cli/DRagLint.CLI.pas tests/autofix/fixtures/redundant_not_not.pas tests/autofix/run_fix_newrules.ps1
git commit -m "feat(autofix): redundant-not-not is fixable (not not X -> X)"
```

---

## Task 3: `redundant-as-tobject` fix branch + fixture

**Files:**
- Modify: `src/cli/DRagLint.CLI.pas` -- add `'redundant-as-tobject'` to `FIXABLE_RULE_IDS`; add a branch in `BuildAutofixEdits`; update the summary.
- Create: `tests/autofix/fixtures/redundant_as_tobject.pas`
- Modify: `tests/autofix/run_fix_newrules.ps1` (add the case)

**Interfaces:**
- Consumes: `BuildAutofixEdits`, `Assert-Fix` (from Task 2).
- Produces: fixture with `Obj := Sender as TObject;`.

- [ ] **Step 1: Write the failing test (fixture + harness case)**

Create `tests/autofix/fixtures/redundant_as_tobject.pas` (ASCII, CRLF):

```pascal
unit redundant_as_tobject;

interface

uses
  System.Classes;

implementation

procedure Demo(Sender: TObject);
var
  Obj: TObject;
begin
  Obj := Sender as TObject;
end;

end.
```

(The `Obj := Sender as TObject;` line is line 14.)

Add to `tests/autofix/run_fix_newrules.ps1`, immediately after the `redundant-not-not` `Assert-Fix` line:

```powershell
Assert-Fix 'redundant_as_tobject.pas' 14 'redundant-as-tobject' 'Obj := Sender;' '[as-tobject]'
```

- [ ] **Step 2: Run the harness to verify the new case fails**

From `C:\TEMP`: `pwsh -File ...\run_fix_newrules.ps1`
Expected: FAIL on `[as-tobject]` (rule not yet fixable; line stays `Obj := Sender as TObject;`). The `[not-not]` case still PASSES.

- [ ] **Step 3: Add the rule to the registry + a fix branch**

Extend `FIXABLE_RULE_IDS` to `array[0..4]` adding `'redundant-as-tobject'`.

Add this branch after the `redundant-not-not` branch:

```pascal
      else if SameText(F.RuleId, 'redundant-as-tobject')
              and (F.StartLine = F.EndLine) and (F.EndCol > F.StartCol) then
      begin
        { span covers 'X as TObject' (the exprBinary). Find the depth-0 whole-word
          'as' keyword; the lhs before it is X. }
        SL:= LinesFor(F.FilePath);
        if (F.StartLine >= 1) and (F.StartLine <= SL.Count) then
        begin
          Ln:= SL[F.StartLine - 1];
          Span:= Copy(Ln, F.StartCol, F.EndCol - F.StartCol);
          { scan for ' as ' at bracket depth 0 (whole word, case-insensitive) }
          var Depth: Integer:= 0;
          var AsPos: Integer:= 0;
          for var K: Integer:= 1 to Length(Span) - 2 do
          begin
            var Ch: Char:= Span[K];
            if (Ch = '(') or (Ch = '[') then Inc(Depth)
            else if (Ch = ')') or (Ch = ']') then Dec(Depth)
            else if (Depth = 0) and (K > 1) and (Span[K-1] <= ' ')
                    and SameText(Copy(Span, K, 2), 'as')
                    and ((K + 2 > Length(Span)) or (Span[K+2] <= ' ')) then
            begin AsPos:= K; Break; end;
          end;
          if AsPos > 1 then
          begin
            Repl:= TrimRight(Copy(Span, 1, AsPos - 1));
            if Repl <> '' then
            begin
              E:= Default(TTextEdit);
              E.FilePath:= F.FilePath;
              E.Kind    := tekReplaceInLine;
              E.Line    := F.StartLine;
              E.Col     := F.StartCol;
              E.EndCol  := F.EndCol;
              E.Text    := Repl;
              Result:= Result + [E];
              Inc(AFixableCount);
            end;
          end;
        end;
      end
```

Append to the summary: `///   redundant-as-tobject   -> strip the ' as TObject' suffix;`

- [ ] **Step 4: Build, then run the harness to verify it passes**

Build (`BUILD_EXITCODE=0`). From `C:\TEMP`: `pwsh -File ...\run_fix_newrules.ps1`
Expected: PASS on both `[not-not]` and `[as-tobject]` (line 14 becomes `Obj := Sender;`).

- [ ] **Step 5: Commit**

```bash
git add src/cli/DRagLint.CLI.pas tests/autofix/fixtures/redundant_as_tobject.pas tests/autofix/run_fix_newrules.ps1
git commit -m "feat(autofix): redundant-as-tobject is fixable (X as TObject -> X)"
```

---

## Task 4: `boolean-comparison-true` fix branch (with compound guard) + fixture

**Files:**
- Modify: `src/cli/DRagLint.CLI.pas` -- add `'boolean-comparison-true'` to `FIXABLE_RULE_IDS`; add a branch in `BuildAutofixEdits` (uses `IsSingleTokenAtom` from Task 1); update the summary.
- Create: `tests/autofix/fixtures/boolean_comparison.pas`
- Modify: `tests/autofix/run_fix_newrules.ps1` (add 5 cases)

**Interfaces:**
- Consumes: `IsSingleTokenAtom` (Task 1), `BuildAutofixEdits`, `Assert-Fix` (Task 2).
- Produces: fixture with all 4 forms + the compound-guard case.

- [ ] **Step 1: Write the failing test (fixture + harness cases)**

Create `tests/autofix/fixtures/boolean_comparison.pas` (ASCII, CRLF):

```pascal
unit boolean_comparison;

interface

implementation

procedure Demo;
var
  Flag, A, B: Boolean;
begin
  Flag := True; A := False; B := True;
  if Flag = True then Flag := False;
  if Flag <> False then Flag := False;
  if Flag = False then Flag := False;
  if Flag <> True then Flag := False;
  if (A and B) = False then Flag := False;
end;

end.
```

Line map (the flagged comparison is the `if ...` head on each line):
- line 12: `if Flag = True then`      -> `if Flag then`
- line 13: `if Flag <> False then`    -> `if Flag then`
- line 14: `if Flag = False then`     -> `if not Flag then`
- line 15: `if Flag <> True then`     -> `if not Flag then`
- line 16: `if (A and B) = False then`-> `if not (A and B) then`

**Important:** `Assert-Fix` asserts the TRIMMED full line equals `$expect`. Because each line has a trailing `then Flag := False;`, pass the full expected line text. Add these cases to `run_fix_newrules.ps1` after the `[as-tobject]` line:

```powershell
Assert-Fix 'boolean_comparison.pas' 12 'boolean-comparison-true' 'if Flag then Flag := False;'        '[bc:=True]'
Assert-Fix 'boolean_comparison.pas' 13 'boolean-comparison-true' 'if Flag then Flag := False;'        '[bc:<>False]'
Assert-Fix 'boolean_comparison.pas' 14 'boolean-comparison-true' 'if not Flag then Flag := False;'    '[bc:=False]'
Assert-Fix 'boolean_comparison.pas' 15 'boolean-comparison-true' 'if not Flag then Flag := False;'    '[bc:<>True]'
Assert-Fix 'boolean_comparison.pas' 16 'boolean-comparison-true' 'if not (A and B) then Flag := False;' '[bc:compound]'
```

- [ ] **Step 2: Run the harness to verify the new cases fail**

From `C:\TEMP`: `pwsh -File ...\run_fix_newrules.ps1`
Expected: FAIL on the 5 `[bc:*]` cases (rule not yet fixable). The `[not-not]` and `[as-tobject]` cases still PASS.

- [ ] **Step 3: Add the rule to the registry + a fix branch**

Extend `FIXABLE_RULE_IDS` to `array[0..5]` adding `'boolean-comparison-true'`.

Add this branch after the `redundant-as-tobject` branch:

```pascal
      else if SameText(F.RuleId, 'boolean-comparison-true')
              and (F.StartLine = F.EndLine) and (F.EndCol > F.StartCol) then
      begin
        { span covers 'X <op> <bool>', op in {=,<>}, bool in {True,False}.
          Scan for the LAST depth-0 '=' or '<>' operator; split into lhs/op/rhs.
          positive (= True / <> False) -> lhs; negative (= False / <> True) ->
          'not ' + (lhs, parenthesized when not a single-token atom). }
        SL:= LinesFor(F.FilePath);
        if (F.StartLine >= 1) and (F.StartLine <= SL.Count) then
        begin
          Ln:= SL[F.StartLine - 1];
          Span:= Copy(Ln, F.StartCol, F.EndCol - F.StartCol);
          var Depth: Integer:= 0;
          var OpPos: Integer:= 0;
          var OpLen: Integer:= 0;
          for var K: Integer:= 1 to Length(Span) do
          begin
            var Ch: Char:= Span[K];
            if (Ch = '(') or (Ch = '[') then Inc(Depth)
            else if (Ch = ')') or (Ch = ']') then Dec(Depth)
            else if Depth = 0 then
            begin
              if (K < Length(Span)) and (Ch = '<') and (Span[K+1] = '>') then
              begin OpPos:= K; OpLen:= 2; end
              else if Ch = '=' then
              begin OpPos:= K; OpLen:= 1; end;
            end;
          end;
          if OpPos > 1 then
          begin
            var LhsText: string:= Trim(Copy(Span, 1, OpPos - 1));
            var OpText : string:= Copy(Span, OpPos, OpLen);
            var RhsText: string:= Trim(Copy(Span, OpPos + OpLen, MaxInt));
            var IsTrue : Boolean:= SameText(RhsText, 'True');
            var IsFalse: Boolean:= SameText(RhsText, 'False');
            var Positive: Boolean;
            var Valid   : Boolean:= (LhsText <> '') and (IsTrue or IsFalse);
            if Valid then
            begin
              { (= True) or (<> False) => positive; (= False) or (<> True) => negative }
              if OpText = '=' then Positive:= IsTrue else Positive:= IsFalse;
              if Positive then
                Repl:= LhsText
              else if IsSingleTokenAtom(LhsText) then
                Repl:= 'not ' + LhsText
              else
                Repl:= 'not (' + LhsText + ')';
              E:= Default(TTextEdit);
              E.FilePath:= F.FilePath;
              E.Kind    := tekReplaceInLine;
              E.Line    := F.StartLine;
              E.Col     := F.StartCol;
              E.EndCol  := F.EndCol;
              E.Text    := Repl;
              Result:= Result + [E];
              Inc(AFixableCount);
            end;
          end;
        end;
      end
```

Append to the summary: `///   boolean-comparison-true -> X=True/X<>False->X; X=False/X<>True->not X;`

- [ ] **Step 4: Build, then run the harness to verify it passes**

Build (`BUILD_EXITCODE=0`). From `C:\TEMP`: `pwsh -File ...\run_fix_newrules.ps1`
Expected: PASS on all 8 cases (3 rules). Line 16 shows the compound guard produced `if not (A and B) then ...`.

- [ ] **Step 5: Commit**

```bash
git add src/cli/DRagLint.CLI.pas tests/autofix/fixtures/boolean_comparison.pas tests/autofix/run_fix_newrules.ps1
git commit -m "feat(autofix): boolean-comparison-true is fixable (=True->X, =False->not X, compound-guarded)"
```

---

## Task 4A: `reserved-word-casing` fix branch + fixture

**Files:**
- Modify: `src/cli/DRagLint.CLI.pas` -- add `'reserved-word-casing'` to `FIXABLE_RULE_IDS`; add a branch in `BuildAutofixEdits`; update the summary.
- Create: `tests/autofix/fixtures/reserved_word_casing.pas`
- Modify: `tests/autofix/run_fix_newrules.ps1` (add the case)

**Interfaces:**
- Consumes: `BuildAutofixEdits`, `Assert-Fix` (Task 2).
- Produces: fixture with a mis-cased keyword.

**Span note:** `reserved-word-casing` is a Pascal-emitted rule (`NamingChecks.pas:463`, via `EmitAt` at :341: `EndCol := StartCol + Length(Trim(NodeStr(keyword)))`). The finding span exactly bounds the keyword token on one line. The rule only fires when the keyword is not already all-lowercase and is not True/False/nil.

- [ ] **Step 1: Write the failing test (fixture + harness case)**

Create `tests/autofix/fixtures/reserved_word_casing.pas` (ASCII, CRLF). Note the mis-cased `IF` keyword on line 12:

```pascal
unit reserved_word_casing;

interface

implementation

procedure Demo;
var
  Flag: Boolean;
begin
  Flag := True;
  IF Flag then Flag := False;
end;

end.
```

(The `IF` keyword is on line 12 at column 3.)

Add to `tests/autofix/run_fix_newrules.ps1` after the boolean-comparison cases:

```powershell
Assert-Fix 'reserved_word_casing.pas' 12 'reserved-word-casing' 'if Flag then Flag := False;' '[kw-casing]'
```

- [ ] **Step 2: Run the harness to verify the new case fails**

From `C:\TEMP`: `pwsh -File ...\run_fix_newrules.ps1`
Expected: FAIL on `[kw-casing]` (rule not yet fixable; line stays `IF Flag then Flag := False;`). Prior cases still PASS.

- [ ] **Step 3: Add the rule to the registry + a fix branch**

Extend `FIXABLE_RULE_IDS` to `array[0..6]` adding `'reserved-word-casing'`.

Add this branch after the `boolean-comparison-true` branch:

```pascal
      else if SameText(F.RuleId, 'reserved-word-casing')
              and (F.StartLine = F.EndLine) and (F.EndCol > F.StartCol) then
      begin
        { span covers the keyword token; keywords are case-insensitive and have no
          reference sites, so lowercasing the span is a safe local edit. }
        SL:= LinesFor(F.FilePath);
        if (F.StartLine >= 1) and (F.StartLine <= SL.Count) then
        begin
          Ln:= SL[F.StartLine - 1];
          Span:= Copy(Ln, F.StartCol, F.EndCol - F.StartCol);
          if (Span <> '') and (Span <> LowerCase(Span)) then
          begin
            E:= Default(TTextEdit);
            E.FilePath:= F.FilePath;
            E.Kind    := tekReplaceInLine;
            E.Line    := F.StartLine;
            E.Col     := F.StartCol;
            E.EndCol  := F.EndCol;
            E.Text    := LowerCase(Span);
            Result:= Result + [E];
            Inc(AFixableCount);
          end;
        end;
      end
```

Append to the summary: `///   reserved-word-casing   -> LowerCase the keyword token;`

- [ ] **Step 4: Build, then run the harness to verify it passes**

Build (`BUILD_EXITCODE=0`). From `C:\TEMP`: `pwsh -File ...\run_fix_newrules.ps1`
Expected: PASS on `[kw-casing]` (line 12 becomes `if Flag then Flag := False;`) + all prior cases.

- [ ] **Step 5: Commit**

```bash
git add src/cli/DRagLint.CLI.pas tests/autofix/fixtures/reserved_word_casing.pas tests/autofix/run_fix_newrules.ps1
git commit -m "feat(autofix): reserved-word-casing is fixable (lowercase the keyword)"
```

---

## Task 4B: `redundant-assigned-free` fix branch + fixture

**Files:**
- Modify: `src/cli/DRagLint.CLI.pas` -- add `'redundant-assigned-free'` to `FIXABLE_RULE_IDS`; add a branch in `BuildAutofixEdits`; update the summary.
- Create: `tests/autofix/fixtures/redundant_assigned_free.pas`
- Modify: `tests/autofix/run_fix_newrules.ps1` (add cases)

**Interfaces:**
- Consumes: `BuildAutofixEdits`, `Assert-Fix` (Task 2).
- Produces: fixture with `if Assigned(X) then X.Free;` + a `then`-substring var guard case.

**Span note:** `.scm` rule (`rules/redundant-assigned-free.scm`); `@warn` is on the whole single-line `if` statement including the trailing `;` (sweep-verified: e.g. cols [3,34) for `if Assigned(Obj) then Obj.Free;`). The else-clause form does NOT fire (the rule matches only the guard-less `if`).

- [ ] **Step 1: Write the failing test (fixture + harness cases)**

Create `tests/autofix/fixtures/redundant_assigned_free.pas` (ASCII, CRLF):

```pascal
unit redundant_assigned_free;

interface

uses
  System.Classes, System.SysUtils;

implementation

procedure Demo;
var
  Obj: TObject;
  Authenticated: Boolean;
begin
  Obj := TObject.Create;
  if Assigned(Obj) then Obj.Free;
  Authenticated := True;
  if Authenticated then Obj := nil;
end;

end.
```

Line map: line 16 `if Assigned(Obj) then Obj.Free;` = redundant-assigned-free. Line 18 `if Authenticated then Obj := nil;` has a var whose name contains `then` inside `Authenticated` -- it must NOT be flagged (it is not an Assigned-guard, so the rule does not fire; but the delimited-`then` scan in the fix must not mis-split if a future finding lands near it). This is a guard fixture: it should produce NO redundant-assigned-free finding on line 18.

Add to `tests/autofix/run_fix_newrules.ps1`:

```powershell
Assert-Fix 'redundant_assigned_free.pas' 16 'redundant-assigned-free' 'Obj.Free;' '[assigned-free]'
```

Also add a direct no-mangle assertion (line 18 must be unchanged after the line-16 fix -- `Assert-Fix` only touches the targeted finding, so this holds; add an explicit check by re-reading the file inside a small inline block, OR rely on `Assert-Fix` targeting only line 16). For clarity add after the Assert-Fix call:

```powershell
# guard: the 'Authenticated' line (contains substring 'then') must be untouched
$scratch18 = Join-Path C:\TEMP 'draglint_newrules_redundant_assigned_free'
$t18 = Join-Path $scratch18 'redundant_assigned_free.pas'
if (Test-Path $t18) {
  $l18 = ([IO.File]::ReadAllLines($t18))[17].Trim()
  Check '[assigned-free] line 18 (Authenticated) untouched' ($l18 -eq 'if Authenticated then Obj := nil;')
}
```

- [ ] **Step 2: Run the harness to verify the new case fails**

From `C:\TEMP`: `pwsh -File ...\run_fix_newrules.ps1`
Expected: FAIL on `[assigned-free]` (rule not yet fixable; line 16 unchanged). Prior cases PASS.

- [ ] **Step 3: Add the rule to the registry + a fix branch**

Extend `FIXABLE_RULE_IDS` to `array[0..7]` adding `'redundant-assigned-free'`.

Add this branch after the `reserved-word-casing` branch:

```pascal
      else if SameText(F.RuleId, 'redundant-assigned-free')
              and (F.StartLine = F.EndLine) and (F.EndCol > F.StartCol) then
      begin
        { span covers 'if Assigned(X) then <stmt>;'. Take the text after the
          delimited 'then' keyword (whole word, not a substring of an identifier)
          to end of span. The Assigned guard is redundant (Free is nil-safe). }
        SL:= LinesFor(F.FilePath);
        if (F.StartLine >= 1) and (F.StartLine <= SL.Count) then
        begin
          Ln:= SL[F.StartLine - 1];
          Span:= Copy(Ln, F.StartCol, F.EndCol - F.StartCol);
          { find delimited 'then' at depth 0 }
          var Depth: Integer:= 0;
          var ThenEnd: Integer:= 0;  { 1-based index one past the 'then' }
          var LS: string:= LowerCase(Span);
          for var K: Integer:= 1 to Length(Span) - 3 do
          begin
            var Ch: Char:= Span[K];
            if (Ch = '(') or (Ch = '[') then Inc(Depth)
            else if (Ch = ')') or (Ch = ']') then Dec(Depth)
            else if (Depth = 0)
                    and (Copy(LS, K, 4) = 'then')
                    and ((K = 1) or (Span[K-1] <= ' ') or (Span[K-1] = ')'))
                    and ((K + 4 > Length(Span)) or (Span[K+4] <= ' ')) then
            begin ThenEnd:= K + 4; Break; end;
          end;
          if ThenEnd > 0 then
          begin
            Repl:= TrimLeft(Copy(Span, ThenEnd, MaxInt));
            if Repl <> '' then
            begin
              E:= Default(TTextEdit);
              E.FilePath:= F.FilePath;
              E.Kind    := tekReplaceInLine;
              E.Line    := F.StartLine;
              E.Col     := F.StartCol;
              E.EndCol  := F.EndCol;
              E.Text    := Repl;
              Result:= Result + [E];
              Inc(AFixableCount);
            end;
          end;
        end;
      end
```

Append to the summary: `///   redundant-assigned-free-> drop the 'if Assigned(X) then' guard;`

- [ ] **Step 4: Build, then run the harness to verify it passes**

Build (`BUILD_EXITCODE=0`). From `C:\TEMP`: `pwsh -File ...\run_fix_newrules.ps1`
Expected: PASS on `[assigned-free]` (line 16 becomes `Obj.Free;`) + line-18-untouched guard + all prior cases.

- [ ] **Step 5: Commit**

```bash
git add src/cli/DRagLint.CLI.pas tests/autofix/fixtures/redundant_assigned_free.pas tests/autofix/run_fix_newrules.ps1
git commit -m "feat(autofix): redundant-assigned-free is fixable (drop the Assigned guard)"
```

---

## Task 4D: Risky-fix registry + `risky` tag in fix output

**(Do this BEFORE Task 4C, because 4C's test asserts `risky:true`.)**

**Files:**
- Modify: `src/cli/DRagLint.CLI.pas` -- add `RISKY_FIX_RULE_IDS` + `IsRiskyFixRule` near `FIXABLE_RULE_IDS` (line ~4458); add a `risky` pair to the `--fix --json` emit block (line ~4688) and a `[risky]` note to the text/dry-run path.
- Create: `tests/autofix/run_fix_risky_tag.ps1`

**Interfaces:**
- Produces: `function IsRiskyFixRule(const ARuleId: string): Boolean;`; a `risky` boolean in each `--fix --json` finding object; a `[risky: behaviour-changing]` note in the `--fix` text output when a risky-rule edit is present.

- [ ] **Step 1: Write the failing test**

Create `tests/autofix/run_fix_risky_tag.ps1`. It uses the `off_by_one.pas` fixture created in Task 4C -- so create a minimal off-by-one fixture now (Task 4C reuses it):

Create `tests/autofix/fixtures/off_by_one.pas` (ASCII, CRLF):

```pascal
unit off_by_one;

interface

uses
  System.Generics.Collections;

implementation

procedure Demo(List: TList<Integer>);
var
  I: Integer;
begin
  for I := 0 to List.Count do
    List[I] := 0;
end;

end.
```

(The `for I := 0 to List.Count do` is line 14; the `List.Count` end-bound is what @warn captures.)

```powershell
[CmdletBinding()]
param([string]$Exe = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe")
$ErrorActionPreference = 'Stop'; $fail = $false
function Check($n,$ok){ Write-Host ("[{0}] {1}" -f (@('FAIL','PASS')[[int]$ok]),$n) -ForegroundColor (@('Red','Green')[[int]$ok]); if(-not $ok){$script:fail=$true} }
$exePath = (Resolve-Path $Exe).Path
function CopyFixture($name) {
  $src = (Resolve-Path (Join-Path $PSScriptRoot "fixtures\$name")).Path
  $dir = Join-Path C:\TEMP ('draglint_risky_' + [IO.Path]::GetFileNameWithoutExtension($name))
  if (Test-Path $dir) { Remove-Item $dir -Recurse -Force }
  New-Item -ItemType Directory -Path $dir | Out-Null
  $dst = Join-Path $dir $name; Copy-Item $src $dst -Force; return $dst
}
Push-Location C:\TEMP
try {
  # risky rule -> risky:true (preview JSON)
  $t = CopyFixture 'off_by_one.pas'
  $raw = & $exePath lint --file $t --fix --fix-line 14 --fix-rule off-by-one-count --json 2>$null | Out-String
  $arr = $null; try { $arr = ($raw | ConvertFrom-Json) } catch { $arr = $null }
  if ($null -ne $arr -and $arr -isnot [System.Array]) { $arr = @($arr) }
  $o = $arr | Where-Object { $_.rule -eq 'off-by-one-count' } | Select-Object -First 1
  Check 'off-by-one-count fixable=true'  ($o.fixable -eq $true)
  Check 'off-by-one-count risky=true'    ($o.risky   -eq $true)

  # non-risky rule -> risky:false
  $t2 = CopyFixture 'redundant_not_not.pas'
  $raw2 = & $exePath lint --file $t2 --fix --fix-line 12 --fix-rule redundant-not-not --json 2>$null | Out-String
  $arr2 = $null; try { $arr2 = ($raw2 | ConvertFrom-Json) } catch { $arr2 = $null }
  if ($null -ne $arr2 -and $arr2 -isnot [System.Array]) { $arr2 = @($arr2) }
  $n = $arr2 | Where-Object { $_.rule -eq 'redundant-not-not' } | Select-Object -First 1
  Check 'redundant-not-not risky=false' ($n.risky -eq $false)

  # text dry-run for the risky fix mentions [risky
  $raw3 = & $exePath lint --file $t --fix --fix-line 14 --fix-rule off-by-one-count 2>$null | Out-String
  Check 'text dry-run notes [risky' ($raw3 -match '\[risky')
} finally { Pop-Location }
if($fail){ Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
```

- [ ] **Step 2: Run to verify it fails**

From `C:\TEMP`: `pwsh -File ...\run_fix_risky_tag.ps1`
Expected: FAIL -- off-by-one-count is not yet fixable (no finding produced) AND `risky` is absent. (Both the fixability and the tag are added in Task 4C + this task; run again after both.)

- [ ] **Step 3: Add the risky registry + JSON/text tagging**

In `src/cli/DRagLint.CLI.pas`, right after the `FixableRuleIds` function (line ~4474), add:

```pascal
{ Behaviour-CHANGING fixes: still applied by Fix-it/Fix-all, but tagged so a
  human/AI orchestrator is warned. Currently only off-by-one-count (adds ' - 1'
  to a loop bound, which breaks an intentionally-inclusive loop). }
const
  RISKY_FIX_RULE_IDS: array[0..0] of string = ('off-by-one-count');

function IsRiskyFixRule(const ARuleId: string): Boolean;
var S: string;
begin
  for S in RISKY_FIX_RULE_IDS do
    if SameText(S, ARuleId) then Exit(True);
  Result := False;
end;
```

In the `--fix --json` emit block, add the `risky` pair right after the `applied`/`preview` pairs (the exact insertion depends on Task 7's rework; add it inside the same `for F in Targeted` loop):

```pascal
            JObj.AddPair('risky', TJSONBool.Create(IsRiskyFixRule(F.RuleId)));
```

For the text dry-run, after `Write(TTextEditApplier.RenderDryRun(Edits));` (line ~4710), add a risky note when any targeted finding is a risky rule:

```pascal
      var HasRisky: Boolean:= False;
      for F in Targeted do
        if IsRiskyFixRule(F.RuleId) then begin HasRisky:= True; Break; end;
      if HasRisky then
        Writeln('[risky] one or more fixes are behaviour-changing -- review before --apply.');
```

- [ ] **Step 4: Build; verify the tag (after Task 4C makes off-by-one fixable)**

Task 4C adds the off-by-one-count fix branch. After BOTH 4C and this task are implemented and built (`BUILD_EXITCODE=0`), from `C:\TEMP`: `pwsh -File ...\run_fix_risky_tag.ps1`
Expected: PASS (off-by-one-count fixable=true + risky=true; redundant-not-not risky=false; text dry-run notes [risky). If running this task's build BEFORE 4C, the fixability checks will still FAIL -- that is expected; the tag plumbing is in place and 4C completes it.

- [ ] **Step 5: Commit**

```bash
git add src/cli/DRagLint.CLI.pas tests/autofix/run_fix_risky_tag.ps1 tests/autofix/fixtures/off_by_one.pas
git commit -m "feat(autofix): risky-fix registry + risky tag in --fix output (behaviour-changing fixes)"
```

---

## Task 4C: `off-by-one-count` fix branch (behaviour-changing, risky-tagged)

**Files:**
- Modify: `src/cli/DRagLint.CLI.pas` -- add `'off-by-one-count'` to `FIXABLE_RULE_IDS`; add a branch in `BuildAutofixEdits`; update the summary.
- Modify: `tests/autofix/run_fix_newrules.ps1` (add the case)
- (Fixture `off_by_one.pas` already created in Task 4D.)

**Interfaces:**
- Consumes: `BuildAutofixEdits`, `Assert-Fix` (Task 2), `IsRiskyFixRule` (Task 4D, for the risky tag).
- Produces: the off-by-one-count fix; combined with Task 4D's tag, `run_fix_risky_tag.ps1` passes.

**Span note:** `.scm` rule (`rules/off-by-one-count.scm`); `@warn` is on the loop END-BOUND only (`exprDot X.Count` or `exprCall Length(X)`), single-line. The fix appends ` - 1`. BEHAVIOUR-CHANGING.

- [ ] **Step 1: Write the failing test (harness case)**

Add to `tests/autofix/run_fix_newrules.ps1` after the redundant-assigned-free case:

```powershell
Assert-Fix 'off_by_one.pas' 14 'off-by-one-count' 'for I := 0 to List.Count - 1 do' '[off-by-one]'
```

- [ ] **Step 2: Run the harness to verify the new case fails**

From `C:\TEMP`: `pwsh -File ...\run_fix_newrules.ps1`
Expected: FAIL on `[off-by-one]` (rule not yet fixable; line stays `for I := 0 to List.Count do`). Prior cases PASS.

- [ ] **Step 3: Add the rule to the registry + a fix branch**

Extend `FIXABLE_RULE_IDS` to `array[0..8]` adding `'off-by-one-count'`.

Add this branch after the `redundant-assigned-free` branch:

```pascal
      else if SameText(F.RuleId, 'off-by-one-count')
              and (F.StartLine = F.EndLine) and (F.EndCol > F.StartCol) then
      begin
        { span covers the loop end-bound (X.Count / Length(X)). Append ' - 1'.
          BEHAVIOUR-CHANGING (tagged risky via IsRiskyFixRule). The bound is
          isolated by 'to .. do', so no precedence hazard. }
        SL:= LinesFor(F.FilePath);
        if (F.StartLine >= 1) and (F.StartLine <= SL.Count) then
        begin
          Ln:= SL[F.StartLine - 1];
          Span:= Copy(Ln, F.StartCol, F.EndCol - F.StartCol);
          if Trim(Span) <> '' then
          begin
            E:= Default(TTextEdit);
            E.FilePath:= F.FilePath;
            E.Kind    := tekReplaceInLine;
            E.Line    := F.StartLine;
            E.Col     := F.StartCol;
            E.EndCol  := F.EndCol;
            E.Text    := Span + ' - 1';
            Result:= Result + [E];
            Inc(AFixableCount);
          end;
        end;
      end
```

Append to the summary: `///   off-by-one-count       -> append ' - 1' to the loop bound (RISKY);`

- [ ] **Step 4: Build, then run both harnesses to verify they pass**

Build (`BUILD_EXITCODE=0`). From `C:\TEMP`:
- `pwsh -File ...\run_fix_newrules.ps1` -> PASS on `[off-by-one]` (line 14 becomes `for I := 0 to List.Count - 1 do`) + all prior cases.
- `pwsh -File ...\run_fix_risky_tag.ps1` -> PASS (now that off-by-one-count is fixable AND tagged risky).

- [ ] **Step 5: Commit**

```bash
git add src/cli/DRagLint.CLI.pas tests/autofix/run_fix_newrules.ps1
git commit -m "feat(autofix): off-by-one-count is fixable (append ' - 1'), tagged risky"
```

---

## Task 5: Fixable-catalog test update (9 fixable)

**Files:**
- Modify: `tests/autofix/run_fixable_catalog.ps1`

**Interfaces:**
- Consumes: `rules --json` `fixable` flags (emit for the 6 new ids via `IsFixableRule`, added in Tasks 2-4, 4A-4C).

- [ ] **Step 1: Extend the catalog assertions**

Add after line 12 (the `redundant-cast` check) in `tests/autofix/run_fixable_catalog.ps1`:

```powershell
  Check 'redundant-not-not fixable=true'       ($byId['redundant-not-not'].fixable -eq $true)
  Check 'redundant-as-tobject fixable=true'    ($byId['redundant-as-tobject'].fixable -eq $true)
  Check 'boolean-comparison-true fixable=true' ($byId['boolean-comparison-true'].fixable -eq $true)
  Check 'reserved-word-casing fixable=true'    ($byId['reserved-word-casing'].fixable -eq $true)
  Check 'redundant-assigned-free fixable=true' ($byId['redundant-assigned-free'].fixable -eq $true)
  Check 'off-by-one-count fixable=true'        ($byId['off-by-one-count'].fixable -eq $true)
  $fixableCount = ($obj.rules | Where-Object { $_.fixable -eq $true }).Count
  Check 'exactly 9 fixable rules' ($fixableCount -eq 9)
```

- [ ] **Step 2: Run to verify it passes**

From `C:\TEMP`: `pwsh -File C:\Projects\Delphi-RAG-lint\tests\autofix\run_fixable_catalog.ps1`
Expected: PASS (all 6 new-rule fixable checks + the 3 existing + the count = 9). No rebuild needed (exe already built in Task 4C).

- [ ] **Step 3: Commit**

```bash
git add tests/autofix/run_fixable_catalog.ps1
git commit -m "test(autofix): fixable catalog now expects 6 rules"
```

---

## Task 6: Batch-gating regression test + doc

**Files:**
- Create: `tests/autofix/fixtures/gating/gating.pas` (contains a `self-assignment` finding AND a `redundant-not-not` finding)
- Create: `tests/autofix/run_fix_respects_config.ps1`
- Modify: `docs/lint/AI-USAGE.md` (document the behaviour); CHANGELOG entry deferred to Task 9.

**Interfaces:**
- Consumes: the `--fix` block's `FinalizeAndOutput` `ShouldKeep` gating (already present, `src/cli/DRagLint.CLI.pas:4623-4651`).

- [ ] **Step 1: Write the fixture**

Create `tests/autofix/fixtures/gating/gating.pas` (ASCII, CRLF):

```pascal
unit gating;

interface

implementation

procedure Demo;
var
  X, Flag, B: Integer;
begin
  X := X;
  Flag := 0;
  B := 0;
end;

end.
```

Note: `X := X;` (line 11) is `self-assignment`. Add a `redundant-not-not` too -- change the body to include a boolean:

```pascal
unit gating;

interface

implementation

procedure Demo;
var
  X: Integer;
  Flag, B: Boolean;
begin
  X := X;
  Flag := True;
  B := not not Flag;
end;

end.
```

Line map: line 12 `X := X;` = self-assignment; line 14 `B := not not Flag;` = redundant-not-not.

- [ ] **Step 2: Write the failing test**

Create `tests/autofix/run_fix_respects_config.ps1`:

```powershell
[CmdletBinding()]
param([string]$Exe = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe")
$ErrorActionPreference = 'Stop'; $fail = $false
function Check($n,$ok){ Write-Host ("[{0}] {1}" -f (@('FAIL','PASS')[[int]$ok]),$n) -ForegroundColor (@('Red','Green')[[int]$ok]); if(-not $ok){$script:fail=$true} }
$exePath = (Resolve-Path $Exe).Path
$fixture = (Resolve-Path (Join-Path $PSScriptRoot 'fixtures\gating\gating.pas')).Path

# Disable self-assignment via a local drag-lint-lint.json; leave redundant-not-not enabled.
$scratch = Join-Path C:\TEMP 'draglint_gating'
if (Test-Path $scratch) { Remove-Item $scratch -Recurse -Force }
New-Item -ItemType Directory -Path $scratch | Out-Null
$target = Join-Path $scratch 'gating.pas'
Copy-Item $fixture $target -Force
@'
{ "disabled": ["self-assignment"] }
'@ | Set-Content -Path (Join-Path $scratch 'drag-lint-lint.json') -Encoding Ascii

Push-Location $scratch
try {
  $raw = & $exePath lint --file $target --fix --json --apply 2>$null | Out-String
  $arr = $null; try { $arr = ($raw | ConvertFrom-Json) } catch { $arr = $null }
  if ($null -ne $arr -and $arr -isnot [System.Array]) { $arr = @($arr) }

  $sa = $arr | Where-Object { $_.rule -eq 'self-assignment' } | Select-Object -First 1
  $nn = $arr | Where-Object { $_.rule -eq 'redundant-not-not' } | Select-Object -First 1

  Check 'disabled self-assignment NOT in fix output' ($null -eq $sa)
  Check 'enabled redundant-not-not IS in fix output'  ($null -ne $nn)

  $lines = [IO.File]::ReadAllLines($target)
  Check 'self-assignment line 12 UNCHANGED (X := X;)' ($lines[11].Trim() -eq 'X := X;')
  Check 'redundant-not-not line 14 FIXED (B := Flag;)' ($lines[13].Trim() -eq 'B := Flag;')
} finally { Pop-Location }

if($fail){ Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
```

- [ ] **Step 3: Run to verify current behaviour**

From `C:\TEMP`: `pwsh -File C:\Projects\Delphi-RAG-lint\tests\autofix\run_fix_respects_config.ps1`
Expected: PASS on all 4 checks (the behaviour already exists per the diagnosis; this test LOCKS it). If instead the self-assignment line got fixed, that would reveal the gating is NOT applied and the `--fix` block would need to filter on `ShouldKeep` -- but per CLI.pas:4623-4651 it operates only on `Survivors`, so PASS is expected. NOTE: if the JSON key for disabling is not `"disabled"`, inspect `LoadLintConfig` / an existing `drag-lint-lint.json` for the correct key and adjust the fixture config before concluding failure.

- [ ] **Step 4: Document the behaviour**

Add a short subsection to `docs/lint/AI-USAGE.md` (near the AutoFix section) with this exact text:

```markdown
### Batch fix respects the active rule set

`lint --fix` and `lint-all --fix` apply quick-fixes only for findings from
*enabled* rules. A rule disabled in `drag-lint-lint.json` (or via `--disable`)
is filtered out before the fix stage, so its findings are neither reported nor
fixed. Enabling/disabling a rule therefore also controls whether it participates
in batch autofix. (The separate per-rule "auto-fix" checkbox is a save-time
auto-apply preference, not the batch gate.)
```

- [ ] **Step 5: Commit**

```bash
git add tests/autofix/fixtures/gating/gating.pas tests/autofix/run_fix_respects_config.ps1 docs/lint/AI-USAGE.md
git commit -m "test+docs(autofix): batch fix respects the active rule set (disabled rules not fixed)"
```

---

## Task 7: Minor 1 -- per-finding `applied` accounting

**Files:**
- Modify: `src/cli/DRagLint.CLI.pas` -- the `--fix` JSON emit block (line ~4680-4692).
- Modify: `tests/autofix/run_fix_respects_config.ps1` (add an assertion) OR a small new harness.

**Interfaces:**
- Consumes: `Edits` array (from `BuildAutofixEdits`), each with `FilePath`+`Line`.
- Produces: JSON `applied` per finding reflects whether an edit was actually produced for that finding.

- [ ] **Step 1: Write the failing test**

Add a fixture case where a finding is a fixable RULE but its span yields NO edit. The cleanest: a `redundant-parentheses` finding that the branch skips (its guard requires the span literally start with `(` and end with `)`). Instead, target a simpler provable case: a fixable-rule finding on a line, but pass a `--fix-line` that has the finding while the branch guard fails.

Simplest robust test: assert that for the DISABLED-then-absent case there is no false `applied`. But Minor 1 is specifically about a fixable-rule finding with no produced edit. Add to `run_fix_respects_config.ps1` after the existing checks, using a NEW fixture `tests/autofix/fixtures/noedit.pas`:

Create `tests/autofix/fixtures/noedit.pas` (ASCII, CRLF) -- a `redundant-cast` finding whose operand is multi-token so the branch (single-identifier precondition) still fires detection but... Actually, to guarantee a fixable-rule finding with a guard-skip is brittle. Use this deterministic approach instead:

Assert in a new harness `tests/autofix/run_fix_applied_accounting.ps1` that when `--apply` is given and the branch DOES produce an edit, `applied=true`; and construct a no-edit case by running `--fix` WITHOUT `--apply` (preview): `applied` must be `false` for every finding (preview never applies). Then separately assert that a fixable finding that produced an edit reports `applied=true` only under `--apply`.

```powershell
[CmdletBinding()]
param([string]$Exe = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe")
$ErrorActionPreference = 'Stop'; $fail = $false
function Check($n,$ok){ Write-Host ("[{0}] {1}" -f (@('FAIL','PASS')[[int]$ok]),$n) -ForegroundColor (@('Red','Green')[[int]$ok]); if(-not $ok){$script:fail=$true} }
$exePath = (Resolve-Path $Exe).Path
$fixture = (Resolve-Path (Join-Path $PSScriptRoot 'fixtures\redundant_not_not.pas')).Path
$scratch = Join-Path C:\TEMP 'draglint_applied'
if (Test-Path $scratch) { Remove-Item $scratch -Recurse -Force }
New-Item -ItemType Directory -Path $scratch | Out-Null
$target = Join-Path $scratch 'redundant_not_not.pas'
Copy-Item $fixture $target -Force
Push-Location C:\TEMP
try {
  # preview (no --apply): applied must be false for the fixable finding
  $raw = & $exePath lint --file $target --fix --fix-line 12 --fix-rule redundant-not-not --json 2>$null | Out-String
  $arr = $null; try { $arr = ($raw | ConvertFrom-Json) } catch { $arr = $null }
  if ($null -ne $arr -and $arr -isnot [System.Array]) { $arr = @($arr) }
  $t = $arr | Where-Object { $_.rule -eq 'redundant-not-not' } | Select-Object -First 1
  Check 'preview: fixable=true'  ($t.fixable -eq $true)
  Check 'preview: applied=false' ($t.applied -eq $false)
} finally { Pop-Location }
if($fail){ Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
```

The genuine Minor-1 defect is: `applied` = `AArgs.Apply` regardless of whether THIS finding produced an edit. To expose it deterministically, add a second targeted case: a finding whose rule IS fixable but whose branch produces no edit. Use `boolean_comparison.pas` line 16's compound case is fixable, so not that. Instead use a `redundant-parentheses` finding whose span does NOT start/end with parens is impossible (the rule only fires on parens). Given the guards, the only reliable no-edit-but-fixable case is a malformed span, which we cannot force from real input. THEREFORE: scope Minor 1's test to the accounting invariant we CAN assert -- `applied` reflects `--apply` AND an edit existing for that finding -- and verify no regression: with `--apply` on a real fixable finding, `applied=true`; on preview, `applied=false`. Full no-edit coverage is documented as a known limitation if not deterministically reproducible.

- [ ] **Step 2: Run to see current behaviour**

From `C:\TEMP`: `pwsh -File ...\run_fix_applied_accounting.ps1`
Expected: PASS on preview (applied=false) with the CURRENT code (preview already sets applied=false). This test guards the invariant.

- [ ] **Step 3: Implement the per-finding accounting**

In the `--fix` JSON block (`src/cli/DRagLint.CLI.pas`), before the `for F in Targeted` loop (line ~4682), build a set of "produced-edit" keys from `Edits`:

```pascal
      { Minor 1: 'applied' must reflect whether an edit was actually produced for
        THIS finding, not merely that --apply was passed. Key edits by file|line. }
      var EditedKeys: TDictionary<string, Boolean>:= TDictionary<string, Boolean>.Create;
      try
        for var Ed: TTextEdit in Edits do
          EditedKeys.AddOrSetValue(LowerCase(Ed.FilePath) + '|' + IntToStr(Ed.Line), True);
        if AArgs.Apply and (FixCount > 0) then
          TTextEditApplier.Apply(Edits, not AArgs.NoBackup);
        JArr:= TJSONArray.Create;
        try
          for F in Targeted do
          begin
            var HasEdit: Boolean:= EditedKeys.ContainsKey(
              LowerCase(F.FilePath) + '|' + IntToStr(F.StartLine));
            JObj:= TJSONObject.Create;
            JObj.AddPair('file'   , F.FilePath);
            JObj.AddPair('line'   , TJSONNumber.Create(F.StartLine));
            JObj.AddPair('rule'   , F.RuleId);
            JObj.AddPair('fixable', TJSONBool.Create(IsFixableRule(F.RuleId)));
            JObj.AddPair('applied', TJSONBool.Create(AArgs.Apply and HasEdit));
            JObj.AddPair('preview', TJSONBool.Create((not AArgs.Apply) and HasEdit));
            JArr.AddElement(JObj);
          end;
          Writeln(JArr.Format(2));
        finally
          JArr.Free;
        end;
      finally
        EditedKeys.Free;
      end;
      Exit(0);
```

Replace the existing JSON block (lines 4678-4697) with the above. (Keep the surrounding `if AArgs.AsJson or SameText(AArgs.Format, 'json')` guard.)

Ensure `System.Generics.Collections` is in the CLI `uses` (it is -- `TDictionary` is already used elsewhere).

- [ ] **Step 4: Build, then run the accounting test + regression the existing single/unit/project fix tests**

Build (`BUILD_EXITCODE=0`). From `C:\TEMP`, run:
- `pwsh -File ...\run_fix_applied_accounting.ps1` -> PASS
- `pwsh -File ...\run_fix_single.ps1`  -> PASS (preview applied=false, apply applied=true unchanged)
- `pwsh -File ...\run_fix_unit.ps1`    -> PASS
- `pwsh -File ...\run_fix_project.ps1` -> PASS
- `pwsh -File ...\run_fix_newrules.ps1` -> PASS (applied=true still holds; each new-rule finding produces an edit)
- `pwsh -File ...\run_fix_respects_config.ps1` -> PASS

- [ ] **Step 5: Commit**

```bash
git add src/cli/DRagLint.CLI.pas tests/autofix/run_fix_applied_accounting.ps1
git commit -m "fix(autofix): --fix --json 'applied' reflects per-finding edit, not just --apply"
```

---

## Task 8: Minor 2 -- `--fix --format sarif` stderr note

**Files:**
- Modify: `src/cli/DRagLint.CLI.pas` -- top of the `--fix` block (line ~4653).
- Create: `tests/autofix/run_fix_sarif_note.ps1`

**Interfaces:**
- Produces: a stderr note when `--fix` is combined with `--format sarif`; stdout stays text/JSON (never SARIF for fix mode).

- [ ] **Step 1: Write the failing test**

Create `tests/autofix/run_fix_sarif_note.ps1`:

```powershell
[CmdletBinding()]
param([string]$Exe = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe")
$ErrorActionPreference = 'Stop'; $fail = $false
function Check($n,$ok){ Write-Host ("[{0}] {1}" -f (@('FAIL','PASS')[[int]$ok]),$n) -ForegroundColor (@('Red','Green')[[int]$ok]); if(-not $ok){$script:fail=$true} }
$exePath = (Resolve-Path $Exe).Path
$fixture = (Resolve-Path (Join-Path $PSScriptRoot 'fixtures\redundant_not_not.pas')).Path
$scratch = Join-Path C:\TEMP 'draglint_sarifnote'
if (Test-Path $scratch) { Remove-Item $scratch -Recurse -Force }
New-Item -ItemType Directory -Path $scratch | Out-Null
$target = Join-Path $scratch 'redundant_not_not.pas'
Copy-Item $fixture $target -Force
Push-Location C:\TEMP
try {
  $errFile = Join-Path $scratch 'err.txt'
  $outFile = Join-Path $scratch 'out.txt'
  Start-Process -FilePath $exePath -ArgumentList @('lint','--file',$target,'--fix','--format','sarif') `
    -NoNewWindow -Wait -RedirectStandardError $errFile -RedirectStandardOutput $outFile
  $err = Get-Content $errFile -Raw
  $out = Get-Content $outFile -Raw
  Check 'stderr mentions SARIF-not-supported note' ($err -match 'sarif' -and $err -match 'text')
  Check 'stdout is NOT sarif json ($schema absent)' (-not ($out -match '\$schema'))
} finally { Pop-Location }
if($fail){ Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
```

- [ ] **Step 2: Run to verify it fails**

From `C:\TEMP`: `pwsh -File ...\run_fix_sarif_note.ps1`
Expected: FAIL on the stderr-note check (no note is printed today).

- [ ] **Step 3: Implement the stderr note**

At the very top of the `--fix` block, right after `if AArgs.Fix then begin` (line ~4653), add:

```pascal
    { Minor 2: fix mode cannot emit SARIF. Warn on stderr and fall through to
      text/JSON output rather than silently swallowing --format sarif. }
    if SameText(AArgs.Format, 'sarif') then
      Writeln(ErrOutput, '--fix does not support SARIF output; using text output.');
```

(`ErrOutput` is the RTL stderr `TextFile`; confirm it is accessible -- it is a `System` global. If the unit already writes to stderr elsewhere, mirror that idiom.)

- [ ] **Step 4: Build, then run to verify it passes**

Build (`BUILD_EXITCODE=0`). From `C:\TEMP`: `pwsh -File ...\run_fix_sarif_note.ps1`
Expected: PASS (stderr has the note; stdout is text, not SARIF).

- [ ] **Step 5: Commit**

```bash
git add src/cli/DRagLint.CLI.pas tests/autofix/run_fix_sarif_note.ps1
git commit -m "fix(autofix): --fix --format sarif prints a stderr note and uses text output"
```

---

## Task 9: Full battery + publish v0.89.0-alpha

**Files:**
- Modify: `src/cli/DRagLint.CLI.pas:6` (VERSION), `CHANGELOG.md`, `docs/lint/BACKLOG.md`.

- [ ] **Step 1: Run the full battery**

From `C:\TEMP`, run every suite and confirm all PASS:
- lint suite (154/154), store (16/16) -- the standard harness runners.
- `run_fix_single.ps1`, `run_fix_unit.ps1`, `run_fix_project.ps1`, `run_fixable_catalog.ps1` (9 fixable), `run_fix_newrules.ps1` (all 6 new rules' cases), `run_fix_risky_tag.ps1`, `run_fix_respects_config.ps1`, `run_fix_applied_accounting.ps1`, `run_fix_sarif_note.ps1`.

Record the exact pass counts. Any FAIL blocks the release.

- [ ] **Step 2: Final whole-branch opus review**

Use superpowers:requesting-code-review on the whole Chunk-2 branch diff (all commits since `b03a192`). Address any Critical/Important findings before tagging (bundle small fixes as fast-follow commits).

- [ ] **Step 3: Bump VERSION + CHANGELOG + BACKLOG**

Set `src/cli/DRagLint.CLI.pas:6` to `VERSION = '0.89.0-alpha';`. Add a CHANGELOG entry for v0.89.0-alpha listing: 6 new fixable rules (redundant-not-not, redundant-as-tobject, boolean-comparison-true, reserved-word-casing, redundant-assigned-free, off-by-one-count [risky]), the risky-fix tag (behaviour-changing fixes flagged `risky:true` in `--fix --json` + text note; off-by-one-count applies but is warned), batch-fix-respects-config (test+doc), Minor 1 (applied accounting), Minor 2 (fix+sarif stderr note). Note in the CHANGELOG that the 163-rule sweep confirmed 9/163 total fixable (no rule-widening remains). Update BACKLOG resume section to "v0.89.0-alpha SHIPPED (9 fixable, all sweep-verified); NEXT Track-1 item = FAutoFix save-time auto-apply control".

- [ ] **Step 4: Rebuild the CLI, reindex self, pack the release zips**

Build the CLI (`BUILD_EXITCODE=0`), stage the win64 exe. Reindex the drag-lint self-index incrementally for the changed files. Pack win64 + win32 CLI-only zips (kill any orphaned `drag-lint.exe` lock if Copy-Item fails).

- [ ] **Step 5: Commit the release, tag, and GitHub release**

```bash
git add src/cli/DRagLint.CLI.pas CHANGELOG.md docs/lint/BACKLOG.md
git commit -m "release: v0.89.0-alpha -- AutoFix Chunk 2 (widen fixable set +6, risky tag, gating test/doc, 2 Minors)"
git tag v0.89.0-alpha
git push && git push --tags
```

Then create the GitHub release (`gh release create v0.89.0-alpha ... --latest`, isPrerelease=false) with the two CLI zips. If the IDE BPL is rebuilt, commit it SEPARATELY as `build(plugin): ...` (NOT in the release commit, NOT in the zip).

- [ ] **Step 6: Update auto-memory + handoff pointer**

Update `project_lint_rules_v062.md` RESUME + `MEMORY.md` index line to record v0.89.0-alpha shipped (9 fixable, all sweep-verified) and NEXT Track-1 item = FAutoFix save-time auto-apply control.

---

## Self-review notes (author)

- **Spec coverage:** 6 rules (Tasks 2-4, 4A-4C) + risky tag (Task 4D) + IsSingleTokenAtom (Task 1) + catalog test =9 (Task 5) + gating test/doc (Task 6) + Minor 1 (Task 7) + Minor 2 (Task 8) + publish (Task 9). All spec sections mapped.
- **Task order note:** Task 4D (risky registry + tag plumbing) is placed BEFORE Task 4C (off-by-one-count fix) because 4C's `run_fix_risky_tag.ps1` asserts `risky:true` -- but 4D also depends on 4C to make off-by-one-count *fixable* (so a finding is produced). Resolution: 4D creates the `off_by_one.pas` fixture + tag plumbing and its risky-tag test partially fails until 4C lands; 4C completes it. Both must be green before Task 5. Alternatively implement 4C then 4D -- either order works as long as both are done before Task 5. Task 7 (Minor 1) reworks the same `--fix --json` loop where 4D adds the `risky` pair; when doing Task 7, PRESERVE the `risky` pair inside the rebuilt loop.
- **Type consistency:** `IsSingleTokenAtom(const S: string): Boolean` (Task 1) consumed in Task 4. `IsRiskyFixRule(const ARuleId: string): Boolean` (Task 4D) consumed in the `--fix` JSON/text paths + Task 4C context. `Edits: TArray<TTextEdit>`, `TTextEdit.FilePath/Line`, `tekReplaceInLine` consistent with `DRagLint.Refactor.TextEdit.pas`. `FIXABLE_RULE_IDS` bounds grow 0..2 -> 0..3 (T2) -> 0..4 (T3) -> 0..5 (T4) -> 0..6 (T4A) -> 0..7 (T4B) -> 0..8 (T4C). `RISKY_FIX_RULE_IDS` = array[0..0].
- **Known soft spots flagged inline:** Task 6 config key (`"disabled"`) may differ -- inspect `LoadLintConfig` if the gating assertion fails. Task 7 no-edit-but-fixable case is not deterministically reproducible from real input; the test asserts the accounting invariant (preview=>applied:false, apply+edit=>applied:true) and the fix makes `applied` conditional on `HasEdit`. Task 8 `ErrOutput` idiom -- confirm the unit's existing stderr pattern. Task 4B delimited-`then` scan: the fixture's `Authenticated` line is the guard; whole-word `then` matching (bounded by whitespace/`)`) is required. Task 4C off-by-one is behaviour-changing -- its risky tag (Task 4D) is what keeps it safe to ship.
