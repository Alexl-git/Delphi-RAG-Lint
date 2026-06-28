# New Lint Rules v0.62 -- Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add 9 new pure `.scm` lint rules (no Pascal rebuild) covering security, control-flow, platform, and code-quality domains, shipped as v0.62.0-alpha.

**Architecture:** Each rule is two drop-in files (`rules/<id>.scm` tree-sitter query + `rules/<id>.json` metadata) plus a TDD fixture pair (`tests/lint/<id>.pas` + `<id>.expected`). The existing test harness (`tests/lint/run_lint_tests.ps1`) validates all fixtures automatically. No Pascal source changes; no rebuild.

**Tech Stack:** tree-sitter query language (`.scm`), Delphi/Pascal fixture files (strict ANSI), PowerShell test harness.

## Global Constraints

- `.pas` and `.scm` files: strict 7-bit ASCII, CRLF line endings. Never introduce UTF-8 or Unix LF.
- Verify tree-sitter node kinds before writing each query: `C:\Projects\tree-sitter-delphi13\tree-sitter.exe parse tests\lint\<id>.pas`
- Rule severity vocabulary: `info` | `warning` | `error`. See existing rules for calibration.
- `warn_capture` in `.json` must match the `@warn` capture name in `.scm`.
- Test harness: `pwsh tests\lint\run_lint_tests.ps1` -- all existing 55 fixtures must stay green after each addition.
- drag-lint exe (Win64, for local smoke test): `C:\Projects\Delphi-RAG-lint\third_party\dll-win64\drag-lint.exe`
- Node syntax learned from existing rules: `exprCall entity:`, `assignment lhs:/rhs:`, `exprBinary operator:/rhs:`, `kTrue`, `kFalse`, `kEq`, `kNeq`, `kAssign`, `kNil`, `kAs`, `literalNumber`, `literalString`, `identifier`.
- Capture names: typically `@fn` for the callee identifier, `@warn` for the node to highlight.
- `#any-of?` for multi-value match, `#eq?` for text equality, `#match?` for regex.
- Moved to Phase 2 (need Pascal built-in): `parambyname-in-loop` (extend `Linter.pas:236`), `loop-variable-modified` (body field TBD).

---

## File Map

| Rule | Create | Create | Create | Create |
|---|---|---|---|---|
| unsafe-string-api | `rules/unsafe-string-api.scm` | `rules/unsafe-string-api.json` | `tests/lint/unsafe-string-api.pas` | `tests/lint/unsafe-string-api.expected` |
| deprecated-rtl-function | `rules/deprecated-rtl-function.scm` | `rules/deprecated-rtl-function.json` | `tests/lint/deprecated-rtl-function.pas` | `tests/lint/deprecated-rtl-function.expected` |
| sleep-in-vcl | `rules/sleep-in-vcl.scm` | `rules/sleep-in-vcl.json` | `tests/lint/sleep-in-vcl.pas` | `tests/lint/sleep-in-vcl.expected` |
| constant-condition | `rules/constant-condition.scm` | `rules/constant-condition.json` | `tests/lint/constant-condition.pas` | `tests/lint/constant-condition.expected` |
| ifthen-both-branches | `rules/ifthen-both-branches.scm` | `rules/ifthen-both-branches.json` | `tests/lint/ifthen-both-branches.pas` | `tests/lint/ifthen-both-branches.expected` |
| sizeof-pointer-assumption | `rules/sizeof-pointer-assumption.scm` | `rules/sizeof-pointer-assumption.json` | `tests/lint/sizeof-pointer-assumption.pas` | `tests/lint/sizeof-pointer-assumption.expected` |
| pchar-arithmetic | `rules/pchar-arithmetic.scm` | `rules/pchar-arithmetic.json` | `tests/lint/pchar-arithmetic.pas` | `tests/lint/pchar-arithmetic.expected` |
| boolean-result-returned-directly | `rules/boolean-result-returned-directly.scm` | `rules/boolean-result-returned-directly.json` | `tests/lint/boolean-result-returned-directly.pas` | `tests/lint/boolean-result-returned-directly.expected` |
| concat-in-loop | `rules/concat-in-loop.scm` | `rules/concat-in-loop.json` | `tests/lint/concat-in-loop.pas` | `tests/lint/concat-in-loop.expected` |

**Modify at release:**
- `src/cli/DRagLint.CLI.pas` line 6 -- bump `VERSION` constant to `'0.62.0-alpha'`
- `CHANGELOG.md` -- prepend new entry
- `rules/README.md` -- append 9 new rule entries

---

### Task 1: `unsafe-string-api` -- unbounded C-style PChar routines

**Files:**
- Create: `rules/unsafe-string-api.scm`
- Create: `rules/unsafe-string-api.json`
- Create: `tests/lint/unsafe-string-api.pas`
- Create: `tests/lint/unsafe-string-api.expected`

**What it detects:** Calls to `StrCopy`, `StrCat`, `StrPCopy`, `StrMove`, `StrPos`, `StrLen` -- unbounded C-style routines that operate on raw PChar without length guards. Severity: **warning**.

- [ ] **Step 1: Write the fixture** (`tests/lint/unsafe-string-api.pas`)

```pascal
unit UnsafeStringApi;

interface

implementation

uses SysUtils;

procedure Bad;
var
  Src, Dst: array[0..255] of AnsiChar;
begin
  StrCopy(Dst, Src);
  StrCat(Dst, Src);
  StrMove(Dst, Src, 10);
  StrLen(Src);
  StrPos(Src, Dst);
end;

procedure Good;
var
  S: string;
begin
  S := S + 'ok';
  Copy(S, 1, 3);
end;

end.
```

- [ ] **Step 2: Write the expected file** (`tests/lint/unsafe-string-api.expected`)

```
# StrCopy/StrCat/StrMove/StrLen/StrPos calls at lines 14-18
unsafe-string-api 14
unsafe-string-api 15
unsafe-string-api 16
unsafe-string-api 17
unsafe-string-api 18
```

- [ ] **Step 3: Verify node kinds with tree-sitter**

```powershell
C:\Projects\tree-sitter-delphi13\tree-sitter.exe parse tests\lint\unsafe-string-api.pas 2>&1 | Select-String -Pattern "exprCall|entity|identifier" | Select-Object -First 20
```

Confirm that `StrCopy(Dst, Src)` parses as `(exprCall entity: (identifier))`. Adjust query field names if different.

- [ ] **Step 4: Write the query** (`rules/unsafe-string-api.scm`)

```scheme
; Calls to unbounded C-style PChar string routines -- no length protection.
; Use System.AnsiStrings equivalents or the string/TStringHelper APIs instead.
((exprCall entity: (identifier) @fn) @warn
 (#any-of? @fn "StrCopy" "StrCat" "StrPCopy" "StrMove" "StrPos" "StrLen"))
```

- [ ] **Step 5: Write the metadata** (`rules/unsafe-string-api.json`)

```json
{
  "id": "unsafe-string-api",
  "severity": "warning",
  "message": "Unsafe PChar string routine -- no length bound. Use System.AnsiStrings or TStringHelper equivalents.",
  "warn_capture": "warn"
}
```

- [ ] **Step 6: Smoke test (single file)**

```powershell
C:\Projects\Delphi-RAG-lint\third_party\dll-win64\drag-lint.exe lint tests\lint\unsafe-string-api.pas --rules-dir rules
```

Expected: 5 findings on lines 14-18, rule `unsafe-string-api`. Zero findings on the `Good` procedure.

- [ ] **Step 7: Run full harness**

```powershell
pwsh tests\lint\run_lint_tests.ps1
```

Expected: all tests PASS (56 total after addition).

- [ ] **Step 8: Commit**

```
git add rules/unsafe-string-api.scm rules/unsafe-string-api.json tests/lint/unsafe-string-api.pas tests/lint/unsafe-string-api.expected
git commit -m "feat(lint): unsafe-string-api rule -- flags StrCopy/StrCat/StrPCopy/StrMove/StrPos/StrLen"
```

---

### Task 2: `deprecated-rtl-function` -- obsolete RTL routines

**Files:**
- Create: `rules/deprecated-rtl-function.scm`
- Create: `rules/deprecated-rtl-function.json`
- Create: `tests/lint/deprecated-rtl-function.pas`
- Create: `tests/lint/deprecated-rtl-function.expected`

**What it detects:** Calls to `OemToAnsi`, `AnsiToOem`, `StrPas`. (`Str` and `Val` are omitted because they are common short identifiers with high FP risk -- add them only if confirmed non-FP on the ORM3 corpus.) Severity: **info**.

- [ ] **Step 1: Write the fixture** (`tests/lint/deprecated-rtl-function.pas`)

```pascal
unit DeprecatedRtl;

interface

implementation

procedure Bad;
var
  S: string;
  P: PAnsiChar;
begin
  OemToAnsi(P, P);
  AnsiToOem(P, P);
  S := StrPas(P);
end;

procedure Good;
var
  S: string;
  I: Integer;
begin
  I := StrToInt(S);
  S := IntToStr(I);
end;

end.
```

- [ ] **Step 2: Write the expected file** (`tests/lint/deprecated-rtl-function.expected`)

```
# OemToAnsi/AnsiToOem/StrPas calls at lines 12-14
deprecated-rtl-function 12
deprecated-rtl-function 13
deprecated-rtl-function 14
```

- [ ] **Step 3: Write the query** (`rules/deprecated-rtl-function.scm`)

```scheme
; Obsolete RTL routines -- prefer modern encoding/conversion equivalents.
; OemToAnsi/AnsiToOem: use TEncoding. StrPas: use string() cast directly.
((exprCall entity: (identifier) @fn) @warn
 (#any-of? @fn "OemToAnsi" "AnsiToOem" "StrPas"))
```

- [ ] **Step 4: Write the metadata** (`rules/deprecated-rtl-function.json`)

```json
{
  "id": "deprecated-rtl-function",
  "severity": "info",
  "message": "Obsolete RTL routine. Prefer TEncoding / modern string APIs.",
  "warn_capture": "warn"
}
```

- [ ] **Step 5: Smoke test and full harness**

```powershell
C:\Projects\Delphi-RAG-lint\third_party\dll-win64\drag-lint.exe lint tests\lint\deprecated-rtl-function.pas --rules-dir rules
pwsh tests\lint\run_lint_tests.ps1
```

Expected: 3 findings (lines 12-14), all other tests still PASS.

- [ ] **Step 6: Commit**

```
git add rules/deprecated-rtl-function.scm rules/deprecated-rtl-function.json tests/lint/deprecated-rtl-function.pas tests/lint/deprecated-rtl-function.expected
git commit -m "feat(lint): deprecated-rtl-function rule -- OemToAnsi/AnsiToOem/StrPas"
```

---

### Task 3: `sleep-in-vcl` -- Sleep() freezes the VCL thread

**Files:**
- Create: `rules/sleep-in-vcl.scm`
- Create: `rules/sleep-in-vcl.json`
- Create: `tests/lint/sleep-in-vcl.pas`
- Create: `tests/lint/sleep-in-vcl.expected`

**What it detects:** Any call to `Sleep()`. In a VCL application the main thread owns the message pump; `Sleep` on the main thread freezes the UI for the full duration. Use a `TTimer` or `TThread.Sleep` in a background thread. Severity: **warning**.

- [ ] **Step 1: Write the fixture** (`tests/lint/sleep-in-vcl.pas`)

```pascal
unit SleepInVcl;

interface

implementation

uses Windows;

procedure Bad;
begin
  Sleep(500);
  Sleep(0);
end;

procedure Good;
begin
  // no Sleep call here
end;

end.
```

- [ ] **Step 2: Write the expected file** (`tests/lint/sleep-in-vcl.expected`)

```
# Sleep calls at lines 11-12
sleep-in-vcl 11
sleep-in-vcl 12
```

- [ ] **Step 3: Write the query** (`rules/sleep-in-vcl.scm`)

```scheme
; Sleep() on the main VCL thread freezes the UI. Use TTimer or TThread.Sleep
; in a background thread instead. Sleep(0) as a yield hint is also flagged --
; prefer Application.ProcessMessages or TThread.Yield if that is the intent.
((exprCall entity: (identifier) @fn) @warn
 (#eq? @fn "Sleep"))
```

- [ ] **Step 4: Write the metadata** (`rules/sleep-in-vcl.json`)

```json
{
  "id": "sleep-in-vcl",
  "severity": "warning",
  "message": "Sleep() on the main thread freezes the VCL UI. Use TTimer for delays or TThread.Sleep in a background thread.",
  "warn_capture": "warn"
}
```

- [ ] **Step 5: Smoke test and full harness**

```powershell
C:\Projects\Delphi-RAG-lint\third_party\dll-win64\drag-lint.exe lint tests\lint\sleep-in-vcl.pas --rules-dir rules
pwsh tests\lint\run_lint_tests.ps1
```

Expected: 2 findings (lines 11-12), all other tests still PASS.

- [ ] **Step 6: Commit**

```
git add rules/sleep-in-vcl.scm rules/sleep-in-vcl.json tests/lint/sleep-in-vcl.pas tests/lint/sleep-in-vcl.expected
git commit -m "feat(lint): sleep-in-vcl rule -- Sleep() freezes the VCL main thread"
```

---

### Task 4: `constant-condition` -- always-true or always-false condition

**Files:**
- Create: `rules/constant-condition.scm`
- Create: `rules/constant-condition.json`
- Create: `tests/lint/constant-condition.pas`
- Create: `tests/lint/constant-condition.expected`

**What it detects:** `if True`, `if False`, `while False`, `repeat ... until True`. These are constant-folded at compile time and represent dead code or logic errors. Note: `while True` is intentional (event loops) and is NOT flagged. Severity: **warning**.

- [ ] **Step 1: Write the fixture** (`tests/lint/constant-condition.pas`)

```pascal
unit ConstantCondition;

interface

implementation

procedure Bad;
begin
  if True then
    Writeln('dead');
  if False then
    Writeln('also dead');
  while False do
    Writeln('never runs');
end;

procedure Good;
var
  B: Boolean;
begin
  if B then
    Writeln('ok');
  while True do  // intentional -- event loop, NOT flagged
    break;
end;

end.
```

- [ ] **Step 2: Write the expected file** (`tests/lint/constant-condition.expected`)

```
# if True at line 9, if False at line 11, while False at line 13
constant-condition 9
constant-condition 11
constant-condition 13
```

- [ ] **Step 3: Verify node kinds**

```powershell
C:\Projects\tree-sitter-delphi13\tree-sitter.exe parse tests\lint\constant-condition.pas 2>&1 | Select-String -Pattern "kTrue|kFalse|if|while|repeat|condition"
```

Confirm the field name for the condition child of `if`/`ifElse`/`while`. Common possibilities: `condition:` or the first unnamed child. Adjust query if field is unnamed (use positional match).

- [ ] **Step 4: Write the query** (`rules/constant-condition.scm`)

```scheme
; Conditions that are always-constant -- dead code or logic error.
; while True is intentional (event loop) and is NOT flagged.
[(if condition: (kTrue) @warn)
 (ifElse condition: (kTrue) @warn)
 (if condition: (kFalse) @warn)
 (ifElse condition: (kFalse) @warn)
 (while condition: (kFalse) @warn)
 (repeat condition: (kTrue) @warn)]
```

If verification shows the condition child is positional rather than a named field, replace `condition: (kTrue)` with `(kTrue)` as the first child of the enclosing node.

- [ ] **Step 5: Write the metadata** (`rules/constant-condition.json`)

```json
{
  "id": "constant-condition",
  "severity": "warning",
  "message": "Condition is always the same constant -- likely dead code or a logic error.",
  "warn_capture": "warn"
}
```

- [ ] **Step 6: Smoke test and full harness**

```powershell
C:\Projects\Delphi-RAG-lint\third_party\dll-win64\drag-lint.exe lint tests\lint\constant-condition.pas --rules-dir rules
pwsh tests\lint\run_lint_tests.ps1
```

Expected: 3 findings (lines 9, 11, 13); `while True` at line 22 NOT flagged; all other tests PASS.

- [ ] **Step 7: Commit**

```
git add rules/constant-condition.scm rules/constant-condition.json tests/lint/constant-condition.pas tests/lint/constant-condition.expected
git commit -m "feat(lint): constant-condition rule -- if True/False, while False, until True"
```

---

### Task 5: `ifthen-both-branches` -- SysUtils.IfThen evaluates both arguments

**Files:**
- Create: `rules/ifthen-both-branches.scm`
- Create: `rules/ifthen-both-branches.json`
- Create: `tests/lint/ifthen-both-branches.pas`
- Create: `tests/lint/ifthen-both-branches.expected`

**What it detects:** `IfThen(cond, A, B)` from `SysUtils`. Unlike a real `if`-`then`-`else`, `IfThen` is a plain function: BOTH `A` and `B` are evaluated before the call. Passing expressions with side effects (function calls, database access) into `IfThen` is a bug. Severity: **warning**.

- [ ] **Step 1: Write the fixture** (`tests/lint/ifthen-both-branches.pas`)

```pascal
unit IfThenBoth;

interface

implementation

uses SysUtils;

function Expensive: Integer;
begin
  Result := 42;
end;

procedure Bad;
var
  B: Boolean;
  N: Integer;
begin
  N := IfThen(B, Expensive, 0);
  N := IfThen(B, 1, Expensive);
end;

procedure Good;
var
  B: Boolean;
  N: Integer;
begin
  if B then
    N := Expensive
  else
    N := 0;
end;

end.
```

- [ ] **Step 2: Write the expected file** (`tests/lint/ifthen-both-branches.expected`)

```
# IfThen calls at lines 19-20
ifthen-both-branches 19
ifthen-both-branches 20
```

- [ ] **Step 3: Write the query** (`rules/ifthen-both-branches.scm`)

```scheme
; SysUtils.IfThen evaluates ALL arguments before calling -- unlike if/then/else.
; Side-effecting expressions (function calls, DB reads) in either branch always execute.
; Replace with a real if/then/else when branches have side effects.
((exprCall entity: (identifier) @fn) @warn
 (#eq? @fn "IfThen"))
```

- [ ] **Step 4: Write the metadata** (`rules/ifthen-both-branches.json`)

```json
{
  "id": "ifthen-both-branches",
  "severity": "warning",
  "message": "IfThen() evaluates both branches unconditionally -- side effects in either argument always execute. Use if/then/else instead.",
  "warn_capture": "warn"
}
```

- [ ] **Step 5: Smoke test and full harness**

```powershell
C:\Projects\Delphi-RAG-lint\third_party\dll-win64\drag-lint.exe lint tests\lint\ifthen-both-branches.pas --rules-dir rules
pwsh tests\lint\run_lint_tests.ps1
```

Expected: 2 findings (lines 19-20); `if/then/else` pattern NOT flagged; all tests PASS.

- [ ] **Step 6: Commit**

```
git add rules/ifthen-both-branches.scm rules/ifthen-both-branches.json tests/lint/ifthen-both-branches.pas tests/lint/ifthen-both-branches.expected
git commit -m "feat(lint): ifthen-both-branches rule -- SysUtils.IfThen evaluates both args"
```

---

### Task 6: `sizeof-pointer-assumption` -- platform-specific pointer size baked in

**Files:**
- Create: `rules/sizeof-pointer-assumption.scm`
- Create: `rules/sizeof-pointer-assumption.json`
- Create: `tests/lint/sizeof-pointer-assumption.pas`
- Create: `tests/lint/sizeof-pointer-assumption.expected`

**What it detects:** Comparing `SizeOf(Pointer)` to the literal `4` or `8` -- bakes in a platform assumption. On Win64 `SizeOf(Pointer)` is 8; the literal breaks on the other platform. Use `{$IFDEF WIN64}` or compare only against `SizeOf` of another type. Severity: **warning**.

- [ ] **Step 1: Write the fixture** (`tests/lint/sizeof-pointer-assumption.pas`)

```pascal
unit SizeofPointer;

interface

implementation

procedure Bad;
var
  N: Integer;
begin
  if SizeOf(Pointer) = 4 then
    N := 1;
  if SizeOf(Pointer) = 8 then
    N := 2;
end;

procedure Good;
begin
  if SizeOf(Pointer) = SizeOf(NativeInt) then
    ;
  {$IFDEF WIN64}
  if SizeOf(Pointer) = 8 then  // guarded by IFDEF -- not detectable, accepted
    ;
  {$ENDIF}
end;

end.
```

- [ ] **Step 2: Write the expected file** (`tests/lint/sizeof-pointer-assumption.expected`)

```
# SizeOf(Pointer) = 4 at line 11, SizeOf(Pointer) = 8 at line 13
sizeof-pointer-assumption 11
sizeof-pointer-assumption 13
```

- [ ] **Step 3: Verify node kinds**

```powershell
C:\Projects\tree-sitter-delphi13\tree-sitter.exe parse tests\lint\sizeof-pointer-assumption.pas 2>&1 | Select-String -Pattern "exprCall|exprBinary|SizeOf|Pointer|literalNumber|entity|arguments"
```

Confirm: `SizeOf(Pointer) = 4` parses as `exprBinary` with an `exprCall` on one side and a `literalNumber` on the other. Note the field names for the exprCall's entity and arguments.

- [ ] **Step 4: Write the query** (`rules/sizeof-pointer-assumption.scm`)

```scheme
; SizeOf(Pointer) = 4 / = 8 bakes in a platform assumption.
; On Win64 pointers are 8 bytes; on Win32 they are 4. The literal breaks cross-platform.
; Use {$IFDEF WIN64} or compare SizeOf(Pointer) to SizeOf of another platform-aware type.
((exprBinary
  (exprCall entity: (identifier) @fn
            (identifier) @arg)
  (literalNumber) @lit) @warn
 (#eq? @fn "SizeOf")
 (#eq? @arg "Pointer")
 (#match? @lit "^[48]$"))
```

If tree-sitter verification shows different field names for the arguments (e.g. `arguments:` wrapping an `exprList`), adjust accordingly:

```scheme
; Alternative form if arguments are wrapped in exprList:
((exprBinary
  (exprCall entity: (identifier) @fn
            arguments: (exprList . (identifier) @arg))
  (literalNumber) @lit) @warn
 (#eq? @fn "SizeOf")
 (#eq? @arg "Pointer")
 (#match? @lit "^[48]$"))
```

- [ ] **Step 5: Write the metadata** (`rules/sizeof-pointer-assumption.json`)

```json
{
  "id": "sizeof-pointer-assumption",
  "severity": "warning",
  "message": "SizeOf(Pointer) compared to a literal -- breaks on Win32 vs Win64. Guard with {$IFDEF WIN64} or compare to SizeOf of a platform-aware type.",
  "warn_capture": "warn"
}
```

- [ ] **Step 6: Smoke test and full harness**

```powershell
C:\Projects\Delphi-RAG-lint\third_party\dll-win64\drag-lint.exe lint tests\lint\sizeof-pointer-assumption.pas --rules-dir rules
pwsh tests\lint\run_lint_tests.ps1
```

Expected: 2 findings (lines 11, 13); `SizeOf(Pointer) = SizeOf(NativeInt)` NOT flagged; all tests PASS.

- [ ] **Step 7: Commit**

```
git add rules/sizeof-pointer-assumption.scm rules/sizeof-pointer-assumption.json tests/lint/sizeof-pointer-assumption.pas tests/lint/sizeof-pointer-assumption.expected
git commit -m "feat(lint): sizeof-pointer-assumption -- SizeOf(Pointer) = 4/8 is platform-specific"
```

---

### Task 7: `pchar-arithmetic` -- unsafe pointer arithmetic on PChar

**Files:**
- Create: `rules/pchar-arithmetic.scm`
- Create: `rules/pchar-arithmetic.json`
- Create: `tests/lint/pchar-arithmetic.pas`
- Create: `tests/lint/pchar-arithmetic.expected`

**What it detects:** Binary `+` or `-` where the left operand is an identifier whose name starts with `P` (PChar naming convention). Pointer arithmetic is unsafe and pointer size differs between Win32 (4) and Win64 (8). Prefer indexed `PChar[N]` access or high-level string APIs. Severity: **warning**.

- [ ] **Step 1: Write the fixture** (`tests/lint/pchar-arithmetic.pas`)

```pascal
unit PCharArith;

interface

implementation

procedure Bad;
var
  PStr: PChar;
  N: Integer;
begin
  PStr := PStr + N;
  PStr := PStr + 1;
end;

procedure Good;
var
  S: string;
  N: Integer;
begin
  N := N + 1;
  S := S + 'x';
end;

end.
```

- [ ] **Step 2: Write the expected file** (`tests/lint/pchar-arithmetic.expected`)

```
# PStr + N at line 12, PStr + 1 at line 13
pchar-arithmetic 12
pchar-arithmetic 13
```

- [ ] **Step 3: Verify node kinds**

```powershell
C:\Projects\tree-sitter-delphi13\tree-sitter.exe parse tests\lint\pchar-arithmetic.pas 2>&1 | Select-String -Pattern "exprBinary|kAdd|kSub|kPlus|kMinus|operator"
```

Confirm what node kind is used for the `+` operator in a binary expression. Candidates: `kAdd`, `kPlus`, or a literal `+` token. Adjust `#any-of?` list accordingly.

- [ ] **Step 4: Write the query** (`rules/pchar-arithmetic.scm`)

```scheme
; Pointer arithmetic on a PChar-named variable -- unsafe, pointer size is platform-specific.
; Use PChar[N] indexed access or string APIs instead.
; Heuristic: left operand starts with uppercase P (Delphi PChar naming convention).
((exprBinary
  lhs: (identifier) @ptr
  operator: [(kAdd) (kSub)]) @warn
 (#match? @ptr "^P[A-Z]"))
```

If `lhs:` is not a named field (use positional match as first child):

```scheme
((exprBinary
  (identifier) @ptr
  operator: [(kAdd) (kSub)]) @warn
 (#match? @ptr "^P[A-Z]"))
```

If the operator node kind is different (e.g. `kPlus`/`kMinus`), replace `kAdd`/`kSub`.

- [ ] **Step 5: Write the metadata** (`rules/pchar-arithmetic.json`)

```json
{
  "id": "pchar-arithmetic",
  "severity": "warning",
  "message": "Pointer arithmetic on PChar -- unsafe and platform-specific (pointer size differs Win32/Win64). Use PChar[N] or string APIs.",
  "warn_capture": "warn"
}
```

- [ ] **Step 6: Smoke test and full harness**

```powershell
C:\Projects\Delphi-RAG-lint\third_party\dll-win64\drag-lint.exe lint tests\lint\pchar-arithmetic.pas --rules-dir rules
pwsh tests\lint\run_lint_tests.ps1
```

Expected: 2 findings (lines 12-13); `N := N + 1` and `S := S + 'x'` NOT flagged; all tests PASS.

- [ ] **Step 7: Commit**

```
git add rules/pchar-arithmetic.scm rules/pchar-arithmetic.json tests/lint/pchar-arithmetic.pas tests/lint/pchar-arithmetic.expected
git commit -m "feat(lint): pchar-arithmetic -- PChar + / - pointer arithmetic is platform-unsafe"
```

---

### Task 8: `boolean-result-returned-directly` -- redundant if/else assigning True/False to Result

**Files:**
- Create: `rules/boolean-result-returned-directly.scm`
- Create: `rules/boolean-result-returned-directly.json`
- Create: `tests/lint/boolean-result-returned-directly.pas`
- Create: `tests/lint/boolean-result-returned-directly.expected`

**What it detects:** `if Cond then Result := True else Result := False` (and the negated form `True`/`False` swapped). Always equivalent to `Result := Cond` (or `Result := not Cond`). Severity: **info**.

- [ ] **Step 1: Write the fixture** (`tests/lint/boolean-result-returned-directly.pas`)

```pascal
unit BoolResultDirect;

interface

function IsPositive(N: Integer): Boolean;
function IsNegative(N: Integer): Boolean;
function IsZero(N: Integer): Boolean;

implementation

function IsPositive(N: Integer): Boolean;
begin
  if N > 0 then
    Result := True
  else
    Result := False;
end;

function IsNegative(N: Integer): Boolean;
begin
  if N < 0 then
    Result := False
  else
    Result := True;
end;

function IsZero(N: Integer): Boolean;
begin
  Result := N = 0;
end;

end.
```

- [ ] **Step 2: Write the expected file** (`tests/lint/boolean-result-returned-directly.expected`)

```
# if/else assigning True/False to Result at lines 13 and 21
boolean-result-returned-directly 13
boolean-result-returned-directly 21
```

- [ ] **Step 3: Verify node kinds**

```powershell
C:\Projects\tree-sitter-delphi13\tree-sitter.exe parse tests\lint\boolean-result-returned-directly.pas 2>&1 | Select-String -Pattern "ifElse|consequence|alternative|assignment|lhs|kTrue|kFalse"
```

Confirm: `ifElse` has `consequence:` and `alternative:` fields; each contains a single `assignment`; `kTrue`/`kFalse` are the rhs. Adjust field names to match.

- [ ] **Step 4: Write the query** (`rules/boolean-result-returned-directly.scm`)

```scheme
; if Cond then Result := True else Result := False
; Equivalent to: Result := Cond. Write it directly.
((ifElse
  consequence: (_ (assignment lhs: (identifier) @r1 rhs: (kTrue)))
  alternative: (_ (assignment lhs: (identifier) @r2 rhs: (kFalse)))) @warn
 (#eq? @r1 "Result")
 (#eq? @r2 "Result"))

; if Cond then Result := False else Result := True (negated form)
; Equivalent to: Result := not Cond.
((ifElse
  consequence: (_ (assignment lhs: (identifier) @r3 rhs: (kFalse)))
  alternative: (_ (assignment lhs: (identifier) @r4 rhs: (kTrue)))) @warn
 (#eq? @r3 "Result")
 (#eq? @r4 "Result"))
```

If the consequence/alternative body is a direct `assignment` rather than wrapped in a `statements` node, remove the `_` wildcard wrapper:

```scheme
((ifElse
  consequence: (assignment lhs: (identifier) @r1 rhs: (kTrue))
  alternative: (assignment lhs: (identifier) @r2 rhs: (kFalse))) @warn
 (#eq? @r1 "Result")
 (#eq? @r2 "Result"))
```

- [ ] **Step 5: Write the metadata** (`rules/boolean-result-returned-directly.json`)

```json
{
  "id": "boolean-result-returned-directly",
  "severity": "info",
  "message": "Redundant if/else assigning True/False to Result. Write 'Result := <cond>' (or 'Result := not <cond>') directly.",
  "warn_capture": "warn"
}
```

- [ ] **Step 6: Smoke test and full harness**

```powershell
C:\Projects\Delphi-RAG-lint\third_party\dll-win64\drag-lint.exe lint tests\lint\boolean-result-returned-directly.pas --rules-dir rules
pwsh tests\lint\run_lint_tests.ps1
```

Expected: 2 findings (lines 13, 21); `Result := N = 0` NOT flagged; all tests PASS.

- [ ] **Step 7: Commit**

```
git add rules/boolean-result-returned-directly.scm rules/boolean-result-returned-directly.json tests/lint/boolean-result-returned-directly.pas tests/lint/boolean-result-returned-directly.expected
git commit -m "feat(lint): boolean-result-returned-directly -- redundant if/else True/False to Result"
```

---

### Task 9: `concat-in-loop` -- O(n^2) string self-concatenation

**Files:**
- Create: `rules/concat-in-loop.scm`
- Create: `rules/concat-in-loop.json`
- Create: `tests/lint/concat-in-loop.pas`
- Create: `tests/lint/concat-in-loop.expected`

**What it detects:** `S := S + X` -- an assignment where the same identifier appears on the left and as the first operand of a binary `+` on the right. Each concatenation allocates a new string, making repeated concatenation O(n^2). Accumulate with `TStringList` or use `string.Join`. Severity: **info**.

Note: this rule does not require loop context -- `S := S + X` is always worth flagging as a pattern regardless of where it appears. The message notes "especially in loops."

- [ ] **Step 1: Write the fixture** (`tests/lint/concat-in-loop.pas`)

```pascal
unit ConcatInLoop;

interface

implementation

procedure Bad;
var
  S: string;
  I: Integer;
begin
  for I := 1 to 100 do
    S := S + IntToStr(I);
  S := S + 'more';
end;

procedure Good;
var
  SL: TStringList;
  I: Integer;
begin
  SL := TStringList.Create;
  for I := 1 to 100 do
    SL.Add(IntToStr(I));
  // SL.Text is the accumulated result
end;

end.
```

- [ ] **Step 2: Write the expected file** (`tests/lint/concat-in-loop.expected`)

```
# S := S + ... at lines 13 and 14
concat-in-loop 13
concat-in-loop 14
```

- [ ] **Step 3: Verify node kinds**

```powershell
C:\Projects\tree-sitter-delphi13\tree-sitter.exe parse tests\lint\concat-in-loop.pas 2>&1 | Select-String -Pattern "assignment|exprBinary|lhs|rhs|identifier|kAdd|kPlus"
```

Confirm: `S := S + IntToStr(I)` parses as `assignment` with `lhs: (identifier)` and `rhs: (exprBinary ...)`. Check whether the left operand of `exprBinary` is named `lhs:` or is the first unnamed child.

- [ ] **Step 4: Write the query** (`rules/concat-in-loop.scm`)

```scheme
; S := S + X -- self-concatenation is O(n^2): each + allocates a new string.
; Use TStringList.Add + TStringList.Text, or string.Join, especially inside loops.
((assignment
  lhs: (identifier) @id
  rhs: (exprBinary
    lhs: (identifier) @lhs_id)) @warn
 (#eq? @id @lhs_id))
```

If `exprBinary` does not have a named `lhs:` field, capture the first child positionally:

```scheme
((assignment
  lhs: (identifier) @id
  rhs: (exprBinary
    (identifier) @lhs_id .)) @warn
 (#eq? @id @lhs_id))
```

- [ ] **Step 5: Write the metadata** (`rules/concat-in-loop.json`)

```json
{
  "id": "concat-in-loop",
  "severity": "info",
  "message": "S := S + X self-concatenation is O(n^2) -- each '+' allocates a new string. Accumulate with TStringList or use string.Join, especially inside loops.",
  "warn_capture": "warn"
}
```

- [ ] **Step 6: Smoke test and full harness**

```powershell
C:\Projects\Delphi-RAG-lint\third_party\dll-win64\drag-lint.exe lint tests\lint\concat-in-loop.pas --rules-dir rules
pwsh tests\lint\run_lint_tests.ps1
```

Expected: 2 findings (lines 13-14); `SL.Add(...)` NOT flagged; all tests PASS.

- [ ] **Step 7: Commit**

```
git add rules/concat-in-loop.scm rules/concat-in-loop.json tests/lint/concat-in-loop.pas tests/lint/concat-in-loop.expected
git commit -m "feat(lint): concat-in-loop -- S := S + X self-concatenation is O(n^2)"
```

---

### Task 10: v0.62 release -- version bump, changelog, docs, tag

**Files:**
- Modify: `src/cli/DRagLint.CLI.pas` line 6 (VERSION constant)
- Modify: `CHANGELOG.md`
- Modify: `rules/README.md`

**Note:** This task requires a Win64 rebuild ONLY because the version constant is in Pascal source. Alternatively, check if `VERSION` is a resource or .txt file that avoids a rebuild. If a rebuild is needed, use the `delphi-build` skill (the reliable rsvars + msbuild recipe).

- [ ] **Step 1: Check whether a rebuild is needed**

```powershell
Select-String -Path "src\cli\DRagLint.CLI.pas" -Pattern "VERSION\s*=" | Select-Object -First 3
```

If `VERSION` is a Pascal `const`, a rebuild is required. If it is read from a file, skip the rebuild. Given the existing release pattern requires a version bump + rebuild, proceed with rebuild.

- [ ] **Step 2: Bump the VERSION constant**

In `src/cli/DRagLint.CLI.pas` near line 6, change:
```pascal
  VERSION = '0.61.0-alpha';
```
to:
```pascal
  VERSION = '0.62.0-alpha';
```

- [ ] **Step 3: Prepend CHANGELOG entry**

At the top of `CHANGELOG.md` (after the header), add:

```markdown
## v0.62.0-alpha -- 2026-06-28

### New lint rules (Phase 1 -- pure .scm, no rebuild required to add)

- `unsafe-string-api` (warning): calls to StrCopy/StrCat/StrPCopy/StrMove/StrPos/StrLen -- unbounded PChar routines.
- `deprecated-rtl-function` (info): OemToAnsi/AnsiToOem/StrPas -- obsolete RTL routines.
- `sleep-in-vcl` (warning): Sleep() on the main thread freezes the VCL UI.
- `constant-condition` (warning): if True/False, while False, repeat...until True -- always-constant condition.
- `ifthen-both-branches` (warning): SysUtils.IfThen() evaluates both branches unconditionally.
- `sizeof-pointer-assumption` (warning): SizeOf(Pointer) = 4/8 bakes in a platform assumption.
- `pchar-arithmetic` (warning): + / - on PChar-named variable -- unsafe pointer arithmetic.
- `boolean-result-returned-directly` (info): redundant if/else assigning True/False to Result.
- `concat-in-loop` (info): S := S + X self-concatenation is O(n^2).
```

- [ ] **Step 4: Append 9 entries to `rules/README.md`**

Append after the last existing rule entry:

```markdown
| `unsafe-string-api` | warning | Calls to StrCopy/StrCat/StrPCopy/StrMove/StrPos/StrLen -- unbounded PChar routines |
| `deprecated-rtl-function` | info | OemToAnsi/AnsiToOem/StrPas -- obsolete RTL |
| `sleep-in-vcl` | warning | Sleep() freezes the VCL main thread |
| `constant-condition` | warning | Condition is always True or False |
| `ifthen-both-branches` | warning | SysUtils.IfThen evaluates both branches unconditionally |
| `sizeof-pointer-assumption` | warning | SizeOf(Pointer) = 4/8 assumes pointer size |
| `pchar-arithmetic` | warning | PChar arithmetic is platform-unsafe |
| `boolean-result-returned-directly` | info | if/else assigning True/False to Result is redundant |
| `concat-in-loop` | info | S := S + X self-concatenation is O(n^2) |
```

- [ ] **Step 5: Rebuild Win64 (use delphi-build skill)**

Follow the `delphi-build` skill recipe. Write a 3-line wrapper bat, run via PowerShell `Start-Process -Wait`, read the log. Confirm `BUILD_EXITCODE=0` and no `[dcc] Error` in the log. Expected build time: under 30 seconds.

- [ ] **Step 6: Run full test harness one final time**

```powershell
pwsh tests\lint\run_lint_tests.ps1
```

Expected: all 64 tests PASS (55 original + 9 new).

- [ ] **Step 7: Commit, tag, and release**

```powershell
git add src/cli/DRagLint.CLI.pas CHANGELOG.md rules/README.md
git commit -m "chore(release): bump version to 0.62.0-alpha + changelog + rules README"
git tag v0.62.0-alpha
git push origin main --tags
```

Then build and publish the release zip:

```powershell
pwsh build\pack-lint-release.ps1 -Version 0.62.0-alpha
gh release create v0.62.0-alpha --repo Alexl-git/Delphi-RAG-Lint --latest `
  --notes "v0.62.0-alpha: 9 new pure .scm lint rules (no rebuild required to add)" `
  <win64-zip> <win32-zip>
```

---

## Self-Review

**Spec coverage check:**

| Spec item | Task |
|---|---|
| `unsafe-string-api` | Task 1 |
| `deprecated-rtl-function` | Task 2 |
| `sleep-in-vcl` | Task 3 |
| `constant-condition` | Task 4 |
| `ifthen-both-branches` (replaces `loop-variable-modified`) | Task 5 |
| `sizeof-pointer-assumption` | Task 6 |
| `pchar-arithmetic` | Task 7 |
| `boolean-result-returned-directly` | Task 8 |
| `concat-in-loop` | Task 9 |
| v0.62 release | Task 10 |
| `parambyname-in-loop` | Deferred to Phase 2 (extend `Linter.pas:236`) |
| `loop-variable-modified` | Deferred to Phase 2 (body field needs verification) |
| IDE lint-all menu command | Phase 2 / v0.63 plan (separate plan) |

**Placeholder scan:** No TBDs. All queries include actual `.scm` code plus an alternative if field names differ. All fixture files are complete Pascal units with both positive and negative cases.

**Type consistency:** All capture names (`@fn`, `@warn`, `@id`, `@r1`, etc.) are consistent between the `.scm` query and the `.json` `warn_capture` field (`"warn"`). All tasks reference the same node kinds (`kTrue`, `kFalse`, `kAdd`, etc.) consistently.
