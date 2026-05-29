## v0.28.0-alpha -- 2026-05-28

### Added

- **5 new built-in tree-sitter-query lint rules** under `rules/`. Each rule is
  a `.scm` tree-sitter query + `.json` metadata pair. Loaded automatically at
  startup from `<exedir>/rules/` by the existing v0.3 `TQueryRules` engine.

  | Rule id | Severity | Description |
  |