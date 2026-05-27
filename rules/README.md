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

### Tip

If you want to discover what AST nodes look like for a fragment of Delphi
code, run the tree-sitter CLI on a sample file:

```cmd
C:\Projects\tree-sitter-delphi13\node_modules\tree-sitter-cli\tree-sitter.exe parse path\to\sample.pas
```

Use that output to write your query.
