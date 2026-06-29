# External Lint Rules

Drop tree-sitter S-expression query files here. `drag-lint lint` loads every
`*.scm` from this directory on startup, compiles each against the Delphi 13
grammar, and runs all of them against every file. Match captures produce
`TLintFinding` rows.

## Rule files

Each rule is a pair:

- `<name>.scm` — the tree-sitter query
- `<name>.json` — optional metadata

If the `.json` is missing, defaults apply (severity = "warning", message =
the rule id, warn capture name = `warn`).

### .json schema

```json
{
  "id": "rule-id",
  "severity": "info | warning | error",
  "message": "Human-readable message printed with each finding.",
  "warn_capture": "name-of-the-capture-to-pin-the-finding-to"
}
```

If `warn_capture` is omitted (or no capture by that name is present in a
match), the finding is pinned to the **first** capture in the match.

### .scm format

Standard tree-sitter S-expression query syntax. Captures use `@name`.

```
((exprCall
  entity: (identifier) @callee) @warn)
```

### Supported predicates (v0.3)

The runner evaluates these standard tree-sitter predicates:

| Predicate | Meaning |
|---|---|
| `#eq? @cap "lit"` / `#not-eq?` | Capture text equals the literal |
| `#eq? @c1 @c2` / `#not-eq?` | Two captures have identical text |
| `#match? @cap "re"` / `#not-match?` | Capture text matches the regex (TRegEx) |
| `#any-of? @cap "a" "b" ...` / `#not-any-of?` | Capture text equals any of the listed |

Unknown predicates pass through (don't suppress) so future tree-sitter
extensions don't silently filter matches.

## Suppressing a finding

Put a line comment on the offending source line:

- `// drag-lint:ignore` -- silence **all** rules on that line.
- `// drag-lint:ignore <rule-id> [<rule-id> ...]` -- silence only those rule ids.

Works for both external `.scm` rules and the built-in checks.

## Shipped rules (v0.28)

| Rule id | Severity | Description |
|---------|----------|-------------|
| `writeln-in-source` | info | Direct `WriteLn` call — use a logger |
| `goto-statement` | warning | `goto` statement is generally considered harmful |
| `with-statement` | info | `with` statement makes symbol scope ambiguous |
| `empty-procedure-body` | info | Empty `procedure`/`function` body (begin..end with no statements) |
| `large-magic-number` | info | Numeric literal not in the common-constants allow-list |
| `string-equality-comparison` | info | `=` comparison on expressions — fires on all `=` binary expressions until type-resolution is plumbed in (v0.19+) |

## Shipped rules (v0.31)

| Rule id | Severity | Description |
|---------|----------|-------------|
| `parser-error` | error | Tree-sitter `ERROR` node — malformed syntax that the parser could not recover |

## Shipped rules (v0.32)

| Rule id | Severity | Description |
|---------|----------|-------------|
| `compiler-magic-comments` | info | Comment contains TODO/FIXME/HACK/XXX — track in issue tracker |
| `nested-with` | warning | Nested `with` statement — scope becomes highly ambiguous |
| `assert-call` | info | `Assert()` call — ensure the second argument provides a descriptive message |
| `case-magic-numbers` | info | `case` label is an integer literal — consider naming the constant |

## Shipped rules (v0.35)

| Rule id | Severity | Description |
|---------|----------|-------------|
| `boolean-comparison-true` | info | `X = True` or `X = False` -- redundant boolean comparison |
| `redundant-as-tobject` | info | `(X as TObject)` -- every Delphi object is already a TObject |
| `inherited-bare` | info | Bare `inherited;` call -- verify it invokes the intended ancestor method |

## Shipped rules (v0.47 -- lint expansion, Wave 1)

New high-signal, low-false-positive rules (see `docs/lint/REPORT-2-draglint-implementation-plan.md`).
Each has a TDD fixture under `tests/lint/` verified by `tests/lint/run_lint_tests.ps1`.

| Rule id | Severity | Description |
|---------|----------|-------------|
| `empty-except` | warning | Empty `except` block silently swallows every exception |
| `empty-on-handler` | warning | `on E: ... do ;` -- empty exception handler swallows that exception |
| `empty-finally` | warning | Empty `finally` block does nothing |
| `bare-except` | info | `except` with no `on E: ... do` clause catches everything (incl. EOutOfMemory) |
| `empty-conditional` | warning | Empty `then`/`else` branch -- stray `;` after `then`/`else` |
| `raise-bare-exception` | warning | `raise Exception.Create(...)` raises the root class -- use a subclass |
| `reraise-loses-stack` | warning | `raise E;` resets the stack trace -- use a bare `raise;` |
| `off-by-one-count` | warning | `for I := 0 to X.Count/Length(X)` runs one past the end |
| `nil-comparison` | info | Prefer `Assigned(X)` over `X = nil` / `X <> nil` |
| `not-in-precedence` | warning | `not X in S` parses as `(not X) in S` -- write `not (X in S)` |
| `classname-string-compare` | warning | `X.ClassName = 'TFoo'` is fragile -- use `is` / `InheritsFrom` |
| `inline-assembly` | info | `asm ... end` block -- not portable across platforms |
| `self-assignment` | warning | `X := X` is a no-op self-assignment -- likely a copy-paste error |
| `with-multiple-items` | warning | `with A, B do` -- multiple objects make name resolution highly ambiguous |
| `empty-loop-body` | warning | `while/for ... do ;` or `repeat until` with no body -- stray `;` or busy-wait |
| `redundant-assigned-free` | info | `if Assigned(X) then X.Free` -- guard redundant (Free/FreeAndNil handle nil) |
| `sql-injection-concat` | warning | SQL string literal concatenated with a variable -- injection risk (CWE-89) |
| `hardcoded-credential` | warning | secret-named variable OR const set to a string literal -- hardcoded credential (CWE-798) |
| `comparison-same-operands` | warning | `X = X` / `X < X` -- both operands identical, result is constant (likely a typo) |
| `division-by-zero-literal` | warning | `X div 0` / `X / 0` / `X mod 0` -- always raises a runtime division error |
| `empty-case-branch` | info | `1: ;` -- case branch with a label but no statement |
| `not-comparison-precedence` | warning | `not A = B` parses as `(not A) = B` -- write `not (A = B)` |
| `redundant-not-not` | info | `not not X` -- redundant double negation, simplify to `X` |
| `public-field` | info | public data field on a class -- breaks encapsulation; use a property |
| `locale-sensitive-conversion` | warning | `StrToFloat`/`FloatToStr`/`StrToDate`/... without a `TFormatSettings` |
| `hardcoded-absolute-path` | info | string literal that is an absolute drive path (`'C:\...'`) |
| `uppercase-compare` | warning | `UpperCase(X) = 'literal'` -- fragile/slow; use `SameText` |
| `outputdebugstring` | info | `OutputDebugString` debug tracing left in code |
| `length-zero-compare` | info | `Length(X) = 0` / `> 0` -- prefer `X = ''` for strings |
| `hardcoded-connection-string` | warning | string literal with connection-string keywords (CWE-798) |
| `gettickcount-wraparound` | warning | `GetTickCount` wraps after ~49.7 days -- use `GetTickCount64` |
| `hardcoded-ip-address` | info | string literal that is an IPv4 address |

Refined existing rules: `boolean-comparison-true` now also matches `<> True`/`<> False`;
`assert-call` now fires only on single-argument `Assert` (no message); `compiler-magic-comments`
also matches `BUG`.

## Shipped rules (v0.62 -- Phase 1, pure `.scm`)

Nine new query-only rules -- no exe rebuild is needed to add a `.scm` rule. Each
has a TDD fixture under `tests/lint/` verified by `tests/lint/run_lint_tests.ps1`.

| Rule id | Severity | Description |
|---------|----------|-------------|
| `unsafe-string-api` | warning | Calls to `StrCopy`/`StrCat`/`StrPCopy`/`StrMove`/`StrPos`/`StrLen` -- unbounded PChar routines |
| `deprecated-rtl-function` | info | `OemToAnsi`/`AnsiToOem`/`StrPas` -- obsolete RTL routines |
| `sleep-in-vcl` | warning | `Sleep()` on the main thread freezes the VCL UI |
| `constant-condition` | warning | `if True`/`if False`/`while False` -- always-constant condition (`while True` is left alone) |
| `ifthen-both-branches` | warning | `SysUtils.IfThen` evaluates both branches unconditionally |
| `sizeof-pointer-assumption` | warning | `SizeOf(Pointer) = 4`/`8` bakes in a platform assumption |
| `pchar-arithmetic` | warning | `+`/`-` on a PChar-named variable -- unsafe pointer arithmetic |
| `boolean-result-returned-directly` | info | redundant `if/else` assigning `True`/`False` to `Result` |
| `concat-in-loop` | info | `S := S + X` self-concatenation is O(n^2) |

## Shipped rules (v0.63 -- Phase 2, built-ins)

Eleven new built-in (`TAstChecker`) rules -- compiled into the exe, no `.scm`/`.json`.
Each has a TDD fixture under `tests/lint/` verified by `tests/lint/run_lint_tests.ps1`.

| Rule id | Severity | Description |
|---------|----------|-------------|
| `unsafe-shellexecute` | error | `WinExec`/`ShellExecute`/`CreateProcess` with a non-literal command (CWE-78) |
| `path-traversal` | warning | concatenated path to `AssignFile`/`FileOpen`/`CreateFile`/`TFile.Open` (CWE-22) |
| `loop-executes-at-most-once` | warning | `for`/`while`/`repeat` whose first body statement is `Exit`/`Break`/`raise` |
| `format-argument-count` | error | `Format` specifier count != argument count |
| `format-specifier-type-mismatch` | error | literal `Format` argument type incompatible with its specifier |
| `try-except-swallowed` | warning | `try..except` with no raise/log/`HandleException` |
| `dataset-open-without-close` | warning | dataset opened without a matching `Close` in a `finally` |
| `criticalsection-not-released` | error | lock `Enter`/`Acquire` without a `finally` `Leave`/`Release` |
| `too-many-exit-points` | info | routine with more than 5 `Exit` statements |
| `cyclomatic-complexity` | info | routine decision-point count over 15 |
| `virtual-method-in-constructor` | warning | constructor calls a `virtual`/`dynamic`/`override` method of its own class |
| `used-before-assignment` | warning/info | unmanaged local read before assignment (warning = on every path; info = on some path) |
| `function-result-not-set` | warning/info | function `Result` not assigned (warning = never; info = not on every path) |
| `out-param-not-set` | warning/info | `out` parameter not assigned on every path |
| `overwrite-before-read` | info | local assigned then overwritten/discarded before any read (dead store) |
| `write-only-local` | info | local assigned at least once but never read |

### Built-in rules (compiled into the exe, not `.scm`)

Some rules need scope/flow analysis a single tree-sitter query can't express, so they live in
Pascal (`src/diagnostics/DRagLint.Diagnostics.AstChecks.pas`) and run from `drag-lint lint <file>`
(single `.pas`/`.inc`): `unused-local` (H2164), `syntax-error`, `unbalanced-begin-end`,
`undeclared-identifier` (needs `--db`), and -- new in v0.47:
- **`raise-in-finally`** (warning): a `raise` inside a `finally` masks the in-flight exception
  (walks the finally subtree, not descending into nested `try`).
- **`code-after-exit`** (warning): unreachable statement directly after an unconditional
  `Exit`/`raise`/`Break`/`Continue`/`Halt` (same statement list; a terminator nested in an if/case
  does not flag code after the if/case).
- **`missing-inherited-ctor`** / **`missing-inherited-dtor`** (warning): a constructor/destructor whose
  body never calls `inherited` (skips ancestor init/cleanup). Class ctors/dtors and asm bodies skipped.
- **`control-flow-in-finally`** (warning): `Exit`/`Break`/`Continue`/`Halt` inside a `finally` block
  silently discards the in-flight exception (companion to `raise-in-finally`).
- **`too-many-parameters`** / **`too-many-locals`** / **`method-too-long`** / **`deep-nesting`** (info):
  routine size/complexity metrics with conservative defaults (params > 7, locals > 25, body > 120
  lines, nesting > 5). Use `--disable <id>` to turn any off.

- **`float-equality-comparison`** (warning) / **`freeandnil-on-interface`** (warning): type-aware
  checks using a lightweight per-file name-to-type map (`=`/`<>` on float operands; `FreeAndNil`
  on an interface-typed variable).
- **`firedac-open-execsql-mismatch`** (warning): `Open` on a DML statement or `ExecSQL` on a SELECT
  (correlates a literal `X.SQL.Text := '...'` with a later `X.Open`/`X.ExecSQL` on the same variable).
- **`unprotected-object-free`** (warning): a locally-created object freed without `try-finally`
  (leaks if code between creation and `Free`/`FreeAndNil` raises).
- **`use-after-free`** (warning): use of an object after a raw `X.Free` (dangling reference) before
  `X` is reassigned (block-scoped; `FreeAndNil` clears tracking).
- **`win64-pointer-cast`** (warning): a 32-bit cast (`Integer`/`Cardinal`/...) of a pointer-typed
  value -- truncates on Win64; use `NativeInt`/`NativeUInt`.
- **`ui-access-in-thread`** (warning): VCL/FMX UI access (`.Caption :=`, `.SetFocus`, ...) inside a
  `TThread.Execute` not wrapped in `Synchronize`/`Queue` -- VCL/FMX is not thread-safe.

Index-wide rules (need `--db`, run via `drag-lint lint-project`): **`god-class`**, **`unused-public-symbol`**,
**`interface-reference-cycle`** (class A holds an interface implemented by B and vice-versa -- ARC leak;
mark one side `[weak]`/`[unsafe]`), **`layering-violation`** (config-driven architecture enforcement via
`--layers <file.json>` -- flags forbidden cross-layer `uses`; see CHANGELOG for the config shape).

Plus `field-by-name-in-loop` and `inline-comment-in-multiline-args` from the linter core, and
`unit-not-in-dpr` (project check).

### Tip

If you want to discover what AST nodes look like for a fragment of Delphi
code, run the tree-sitter CLI on a sample file:

```cmd
C:\Projects\tree-sitter-delphi13\node_modules\tree-sitter-cli\tree-sitter.exe parse path\to\sample.pas
```

Use that output to write your query.
