## v0.25.0-alpha -- 2026-05-29

### Added

- **`drag-lint generate-docs --qname X [--format xmldoc|pasdoc]`** --
  generates a doc-comment stub for a symbol. Parses the signature
  (or falls back to reading the declaration line from source when
  the signature field is empty), extracts parameters and return type,
  and emits an XMLDoc `/// <summary>...` block or a PasDoc `{** ... *}`
  block. Pipe stdout into your editor or clipboard.

- **MCP tool `generate_doc_stub`** -- same as the CLI.

- **`drag-lint find-deadcode [--kind K] [--include-private]`** --
  inverse of v0.17 `impact`. Lists symbols with zero callers in the
  index (excluding constructors/destructors and known entry points
  like `Main`, `Register`, `initialization`, `finalization`).
  Output: `<qname>  [<kind>]  <file>:<line>`.

- **MCP tool `find_deadcode`** -- same as the CLI.

### Notes

- Refactor preview form (the originally-planned v0.25 F1) moves to
  v0.26 along with the bigger compiler-diagnostic integration scope.
- Dead-code analysis is name-based (same caveat as v0.24 rename):
  symbols in unrelated classes with the same short name are treated
  as cross-referenced. Precision-perfect mode awaits `refs.symbol_id`
  population (still parked).
- Doc stubs are pure scaffolding -- they emit TODO placeholders for
  the user to fill in. v0.26 may add LLM-assisted prose suggestions
  via the existing context-bundle infrastructure.