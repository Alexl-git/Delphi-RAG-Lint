## v0.19.0-alpha -- 2026-05-28

### Added

- **`drag-lint typeat file:line:col`** — resolves the identifier at the given
  source position and returns containing symbol (unit, class, method),
  token text, resolved symbol (with qualified name), signature, and documentation.
  Supports dotted access (e.g., `Foo.Bar`) via parent_id lookup against class
  / record / interface parent symbols. Example: `drag-lint typeat Docs.pas:42:15
  --db myproj.sqlite` resolves the symbol at line 42, column 15.

- **MCP: `get_type_at_position` tool** — same as CLI `typeat` but callable from
  Claude Code, Cursor, or Zed. Arguments: `file` (relative path from repo root),
  `line` (1-based), `col` (1-based), `db` (optional path to SQLite).

- **LSP: textDocument/hover enriched** — when hovering over an identifier
  reference (not just declaration), hover now includes resolved symbol info
  (qualified name, signature, doc) via the type-at-position resolver.

### Notes

- **Pragmatic scope:** Top-level symbols (units, classes, methods) and dotted
  access against known class/record/interface parent symbols. Unresolved
  positions (e.g., inside `with` statements, generic substitutions, local
  variables) return a clear note rather than an error.
- **Deferred to v0.21 (OTAPI):** Local variable inference, generic type
  substitution, scope-based symbol lookup (e.g., `with TMyClass do Foo` →
  resolve Foo as a method of TMyClass).