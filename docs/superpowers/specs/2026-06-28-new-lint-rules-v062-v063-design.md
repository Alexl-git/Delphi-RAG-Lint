# New Lint Rules v0.62 / v0.63 -- Design Spec

> Status: approved 2026-06-28
> Companion: [BACKLOG.md](../../lint/BACKLOG.md) (ss 4-5), [REPORT-2](../../lint/REPORT-2-draglint-implementation-plan.md)

---

## 1. Goal

Add ~20 new lint rules across two releases, covering all four domains (FireDAC, Security,
Bugs/Control-flow, Quality/Metrics), ordered by implementation cost so cheaper rules ship first.

---

## 2. Three-phase roadmap

| Phase | Rules | Engine | Release |
|---|---|---|---|
| **1** | ~10 pure `.scm` drop-ins | No rebuild required | v0.62 |
| **2** | ~10 T2/T3 Pascal built-ins | Win64 rebuild | v0.63 |
| **3** | Category deep-dive (TBD) | TBD | v0.64+ |

Phase 3 category is chosen after Phase 2 ships, based on which domain has the most
remaining high-signal rules.

---

## 3. Engine reminder

- **T1 -- pure `.scm`**: drop `rules/<id>.scm` + `<id>.json`; add fixture; no rebuild.
- **T2 -- `.scm` + Pascal post-filter**: `.scm` captures the call, a Pascal method in
  `TAstChecker` refines (checks argument node kind, counts, etc.); rebuild required.
- **T3 -- Pascal built-in**: new `TAstChecker.CheckXxx` method; wire in `DoLint` and the
  `--rule` allow-list; rebuild required.

Index queries (`ISymbolStore`) are available to T3 built-ins when the `--db` flag is
passed; rules that need the DB degrade gracefully (skip) when no DB is available.

---

## 4. Phase 1 -- pure `.scm` rules (~10 rules, v0.62)

All rules follow the standard fixture pattern: `tests/lint/<id>.pas` + `<id>.expected`.
Run `pwsh tests/lint/run_lint_tests.ps1` after each addition. No rebuild needed.

### 4.1 FireDAC

#### `parambyname-in-loop` (warning)

`.ParamByName('X')` call inside a `for`/`while`/`repeat` body. The parameter object is
looked up by name on every iteration; save it to a local before the loop.

Extends the existing `field-by-name-in-loop` tree-sitter pattern. Add `ParamByName` to
the `#any-of?` predicate (and verify node kind against grammar: no-paren call = `exprDot`,
paren call = `exprCall`).

### 4.2 Security / Platform

#### `unsafe-string-api` (warning)

Calls to unbounded C-style PChar routines: `StrCopy`, `StrCat`, `StrPCopy`, `StrMove`,
`StrPos`, `StrLen`. These operate without length bounds and are a classic buffer-overrun
source. Use `AnsiStrings`, `TStringHelper`, or `System.StrUtils` equivalents.

Implementation: `#any-of?` predicate on the function identifier.

#### `deprecated-rtl-function` (info)

Calls to obsolete RTL routines: `Str`, `Val`, `OemToAnsi`, `AnsiToOem`, `StrPas`.
Prefer modern equivalents (`IntToStr`/`StrToInt`, `TEncoding`, etc.).

Implementation: `#any-of?` on the identifier. Ships as `info` to avoid noise on legacy
code that can't easily migrate.

#### `sizeof-pointer-assumption` (warning)

`SizeOf(Pointer) = 4` or `SizeOf(Pointer) = 8`. The literal bakes in a platform
assumption that breaks on the other target. Use `{$IFDEF WIN64}` or compare
`SizeOf(Pointer)` only against `SizeOf` of another type.

Implementation: match binary `kEq`/`kNe` where one side is `SizeOf(Pointer)` and the
other is a `literalNumber`. Use `#match?` on the literal to catch both 4 and 8.

### 4.3 Control-flow / Bugs

#### `constant-condition` (warning)

`if True`, `if False`, `while False`, `repeat ... until True`. A permanently-constant
condition is almost always dead code or a logic error.

Note: `while True` is intentional (event loops) and is NOT flagged.

Implementation: match the condition child of `if`/`ifElse`/`while`/`until` against
`kTrue`/`kFalse` literal nodes.

#### `loop-variable-modified` (error)

Assignment to a `for`-loop control variable inside the loop body (e.g.
`for I := 0 to N do begin ... I := 5; end`). Delphi's behaviour is undefined when the
loop variable is written; the compiler may silently ignore the write or produce
incorrect results.

Implementation: capture the loop control identifier from the `for` header (`@loopvar`),
then match an `assignmentStatement` inside the body where the left side equals `@loopvar`
via `#eq?`. Verify the exact node kind for the `for` control variable field in the grammar.

#### `sleep-in-vcl` (warning)

Any `Sleep()` call in production code. In a VCL application this freezes the main thread
for the entire duration. Use `TTimer` for delays or `TThread.Sleep` inside a background
thread.

Implemented identically to `outputdebugstring`: simple identifier match on `Sleep`.
Ships as a warning (not error) because `Sleep(0)` is sometimes used as a yield hint.
Message should note the VCL freeze risk.

#### `boolean-result-returned-directly` (info)

```
if Cond then
  Result := True
else
  Result := False
```

Always equivalent to `Result := Cond`. Also matches the negated form (`True`/`False`
swapped -> `Result := not Cond`).

Implementation: match `ifElse` node where consequence assigns `kTrue` to `Result` and
alternative assigns `kFalse` to `Result` (and vice versa for the negated form), using
`#eq?` on the identifier `Result`.

### 4.4 Code Quality / Performance

#### `concat-in-loop` (info)

`S := S + X` inside a `for`/`while`/`repeat` body. String concatenation in a loop is
O(n^2) in Delphi because each `+` allocates a new string. Accumulate with `TStringList`
or use `string.Join`.

Implementation: match an `assignmentStatement` where the right side is a binary `+` and
the left identifier (`@id`) appears as the first operand (`#eq?`), with a loop node as
an ancestor. Ancestor matching is done by nesting the assignment query inside a loop
body pattern.

#### `pchar-arithmetic` (warning)

Arithmetic on a `PChar` variable: `P + N`, `P - N` in a binary expression context.
Platform-unsafe (pointer size differs between Win32/Win64); prefer indexed access
`PChar[N]` or higher-level string APIs.

Implementation: match binary `kAdd`/`kSub` expressions where one operand is an
identifier whose name starts with `P` (case-sensitive prefix heuristic, consistent with
`win64-pointer-cast`). Low FP on Delphi naming conventions.

---

## 5. Phase 2 -- T2/T3 Pascal built-ins (~10 rules, v0.63)

All built-ins follow the pattern: new `class function TAstChecker.CheckXxx` in
`DRagLint.Diagnostics.AstChecks.pas`; one wire-up line in `DoLint`; one entry in the
`--rule` allow-list; fixture in `tests/lint/`. Rebuild Win64 after each group.

### 5.1 T2 -- `.scm` + Pascal post-filter

#### `unsanitized-shellexecute` (error)

`ShellExecute`, `WinExec`, or `CreateProcess` call where the executable/command
argument is not a `literalString` node. A runtime-built path can be injected by an
attacker or contain unexpected content.

Implementation: `.scm` captures the call; Pascal post-filter checks the relevant argument
position for `literalString` node kind. Flag if it is an identifier or expression.

#### `path-traversal` (warning)

`AssignFile`, `FileOpen`, `TFile.Open`, `CreateFile` (Win32 API) calls where the
path argument is a binary `+` expression (string concatenation). A user-controlled
prefix may escape the intended directory.

Implementation: same T2 pattern. `.scm` captures the call; Pascal checks argument node
is `exprBinary` with `kAdd` operator.

#### `loop-executes-at-most-once` (warning)

`Exit`, `Break`, or `raise` as the first unconditional statement in a `for`/`while`/
`repeat` body (i.e. not inside a nested `if`/`case`). The loop will never complete a
second iteration -- either the loop is wrong or the exit should be before the loop.

Implementation: `.scm` matches the structural pattern (loop body starts with
exit/break/raise); Pascal post-filter confirms the statement is not nested inside a
conditional by walking its parent chain.

#### `format-argument-count` (error) + `format-specifier-type-mismatch` (error)

Two checks on the same `Format('...', [...])` call; both require a literal string +
array constructor (skip silently if either is a variable).

**Count check** (`format-argument-count`): number of `%s`/`%d`/`%f`/`%g`/`%n`/`%e`/
`%x`/`%p`/`%u` specifiers in the literal does not match the element count of the array
constructor.

**Type check** (`format-specifier-type-mismatch`): for each argument that is a literal
node (not a variable), verify the specifier family is compatible:
- `%d`/`%u`/`%x`/`%i` -- argument must be an integer literal; a string literal is an
  error.
- `%f`/`%g`/`%e`/`%n` -- argument must be a numeric literal (integer or float).
- `%s` -- any literal is accepted (`%s` coerces via `string()`).
- Variables and compound expressions -- skip type check, only count.

Type checking for variable arguments (e.g. `Format('%d', [MyStr])`) requires a type
resolver and is deferred to a future T5 pass. The literal-only subset still catches a
meaningful class of copy/paste mistakes.

Implementation: single `CheckFormatCall` Pascal method handles both checks in one walk.
`NodeText` extracts the literal; `specifierFamily` maps each `%x` character to a family
enum; per-argument node kind (`literalNumber`, `literalString`, `identifier`) drives the
type gate. Both rule IDs share the same implementation file; they are wired separately
in `DoLint` so each can be individually disabled.

### 5.2 T3 -- Pascal built-ins (flow / scope)

#### `try-except-swallowed` (warning)

An `except` block that contains none of: `raise`, `Application.HandleException`,
`Application.ShowException`, `ShowException`, or any identifier matching a logging
convention (e.g. contains "Log", "Logger", "Report"). Silent swallowing is one of the
hardest-to-diagnose production bugs.

Implementation: `TAstChecker.CheckSwallowedExcept` walks each `except` clause body and
checks for the presence of any of the above. Message: "Exception silently swallowed --
add raise, logging, or Application.HandleException."

#### `dataset-open-without-close` (warning)

`TFDQuery.Open` or `Active := True` in a routine without a matching `Close`/
`Active := False` in a `finally` block. Datasets left open hold server cursors and may
exhaust connection pools.

Implementation: mirrors `unprotected-object-free` flow pattern. Walk routine body;
track Open/Active-True sites and finally-block Close/Active-False sites; report any
unmatched Open.

#### `criticalsection-not-released` (error)

`TCriticalSection.Enter` (or `.Acquire`) without a matching `.Leave`/`.Release` in a
`finally` block in the same routine. A lock leaked on an exception path causes a deadlock.

Implementation: same flow pattern as `dataset-open-without-close`. Track Acquire/Release
pairs within try-finally scope.

#### `virtual-method-in-constructor` (warning)

A call to a `virtual` or `dynamic` method inside a constructor body. The VMT is set up
before the constructor runs, so the call dispatches to the descendant's override -- but
the descendant's fields are uninitialised at this point, causing AV or corrupt state.

Implementation: `TAstChecker.CheckVirtualInConstructor` identifies the enclosing routine
as a constructor (node kind `constructor`), then for each `exprCall`/`exprDot` call,
queries `ISymbolStore` for the called method's `modifiers` column to check for `virtual`
or `dynamic`. Requires `--db`; skips gracefully if no DB.

#### `too-many-exit-points` (info, default threshold: 5)

A routine with more than N `Exit` statements. Hard to reason about control flow; refactor
to a single exit or use guard clauses consistently. Threshold configurable via the future
`drag-lint-lint.json` config (BACKLOG ss5).

Implementation: `TAstChecker.CheckTooManyExitPoints` counts `Exit` identifier nodes in
the routine body. Threshold wired as a const (default 5); follows the existing pattern
of `too-many-parameters`/`too-many-locals`.

#### `cyclomatic-complexity` (info, default threshold: 15)

Counts decision points per routine: `if`, `ifElse`, `while`, `for`, `repeat`, `case`
branch label, `kAnd`, `kOr`. Above the threshold the routine is statistically harder to
test and maintain.

Pre-implementation step: verify node names for `and`/`or` operators against the grammar
via `tree-sitter.exe parse` on a sample file (BACKLOG note: "verify `kAnd`/`kOr` node
names first"). Base count = 1 (the routine itself).

Implementation: `TAstChecker.CheckCyclomaticComplexity` recursive walk; sum decision
points. Threshold wired as a const (default 15).

---

## 6. Phase 3 -- category deep-dive (TBD)

Category is chosen after Phase 2 ships. Candidates:
- **Resource / lifetime**: `stream-not-freed`, `file-not-closed`, `double-free`
- **FireDAC extended**: `query-created-without-owner-never-freed`, `firedac-transaction-not-committed`
- **Naming conventions**: `field-not-f-prefixed`, `class-not-t-prefixed`, etc. (ships OFF by default)
- **Metrics extended**: `cognitive-complexity`, `too-many-nested-routines`

---

## 7. Testing strategy

Each rule gets:
1. A positive fixture `tests/lint/<id>.pas` with at least two findings (different lines/cases).
2. A negative fixture or negative section in the same file that must produce zero findings.
3. An `.expected` file listing `<rule-id>:<line>` pairs.

Run: `pwsh tests/lint/run_lint_tests.ps1` -- all 55+ fixtures must stay green after each
addition.

For T3 rules that need a DB (`virtual-method-in-constructor`): add a
`tests/lint-project/` fixture with a minimal indexed project, following the pattern in
`tests/lint-project/README.md`.

---

## 8. Release plan

- **v0.62**: Phase 1 complete (10 `.scm` rules). Bump `VERSION`, update `CHANGELOG`,
  update `rules/README.md` with new rule list, commit, push, `git tag v0.62.0-alpha`,
  `gh release create`.
- **v0.63**: Phase 2 complete (10 built-ins). Same release process; rebuild Win64+Win32
  zips via `build/pack-lint-release.ps1 -Version 0.63.0-alpha`.
- **v0.64+**: Phase 3 TBD.
