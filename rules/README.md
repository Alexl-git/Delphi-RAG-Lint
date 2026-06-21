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

Refined existing rules: `boolean-comparison-true` now also matches `<> True`/`<> False`;
`assert-call` now fires only on single-argument `Assert` (no message); `compiler-magic-comments`
also matches `BUG`.

### Tip

If you want to discover what AST nodes look like for a fragment of Delphi
code, run the tree-sitter CLI on a sample file:

```cmd
C:\Projects\tree-sitter-delphi13\node_modules\tree-sitter-cli\tree-sitter.exe parse path\to\sample.pas
```

Use that output to write your query.
