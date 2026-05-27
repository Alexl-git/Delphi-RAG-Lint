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

### Known limitation (v0.2)

The runner **does not evaluate predicates yet** (`#eq?`, `#match?`, `#not-eq?`,
etc.). Predicates compile fine but are ignored — your rule must be
structurally specific enough to avoid false positives, or filter
findings downstream. Predicate evaluation is on the v0.3 backlog. Until then,
treat `*.scm` rules as "AST shape detectors" and the JSON metadata as the
human label.

### Tip

If you want to discover what AST nodes look like for a fragment of Delphi
code, run the tree-sitter CLI on a sample file:

```cmd
C:\Projects\tree-sitter-delphi13\node_modules\tree-sitter-cli\tree-sitter.exe parse path\to\sample.pas
```

Use that output to write your query.
