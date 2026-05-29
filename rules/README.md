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

### Tip

If you want to discover what AST nodes look like for a fragment of Delphi
code, run the tree-sitter CLI on a sample file:

```cmd
C:\Projects\tree-sitter-delphi13\node_modules\tree-sitter-cli\tree-sitter.exe parse path\to\sample.pas
```

Use that output to write your query.
