## v0.16.0-alpha -- 2026-05-28

### Added

- **`symbol_docs` table (schema v4).** One row per documented symbol:
  `format`, `raw_block`, `summary`, `remarks`, `returns_text`, `params_json`,
  `exceptions_json`, `example_text`, `seealso_json`, `since_text`, `deprecated`
  (INTEGER flag), plus `start_line` / `end_line` for the source range.
  v3 databases are migrated transparently on first open -- no manual steps.

- **`DRagLint.Parser.DocComments` module.** A single-pass comment-region
  scanner (`TDocCommentScanner`) walks every `.pas` file and collects comment
  blocks keyed by line range. A format dispatcher (`TDocCommentParser`)
  selects the right sub-parser and populates a `TParsedDoc` record.
  `DRagLint.Parser.Delphi13` matches regions to symbols by line proximity at
  emit time.

- **XMLDoc support.** Recognises `/// <tag>...</tag>` and `{/** ... */}` blocks.
  10 tag types handled: `summary`, `remarks`, `returns`, `example`, `param`,
  `exception`, `see`, `seealso`, `since`, `deprecated`.

- **PasDoc support.** Recognises `{** ... }` and `(** ... *)` blocks with
  `@tag` prefix notation. Same 10 tags as XMLDoc.

- **Oneline support.** Single `///`, `//1`, or `///1` comment lines above a
  declaration are captured as `oneline` format with the line text as `summary`.

- **Loose comment capture** (opt-in). `{ ... }` and `(* ... *)` blocks
  immediately above a symbol are stored as `loose` format when
  `captureLooseComments: true` is set in `.drag-lint.json`. A noise filter
  (no letters = skip) suppresses divider lines. Off by default.

- **`drag-lint hover --qname X [--format md|plain|json]`.** CLI command
  returning the structured doc for any indexed symbol. Default format is
  `plain` (human-readable); `md` emits Markdown; `json` emits the raw row.

- **`drag-lint query find` extended.** Three new filters:
  - `--doc-tag deprecated` -- symbols marked `@deprecated` / `<deprecated>`.
  - `--doc-tag since` -- symbols with a `@since` / `<since>` annotation.
  - `--doc-contains TEXT` -- full-text search across `summary`, `remarks`,
    `returns_text`, `params_json`, `example_text`.
  - `--no-docs [--kind K] [--public]` -- symbols with no doc comment at all.

- **MCP: 3 new tools.**
  - `get_symbol_doc` -- returns the full structured doc row for a qualified name.
  - `find_by_doc_tag` -- returns all symbols bearing a given tag (`deprecated`
    or `since`).
  - `find_undocumented` -- returns symbols with no doc comment, with optional
    `kind` and `public_only` filters.

- **LSP `textDocument/hover` enriched.** When a symbol has a `symbol_docs`
  row the hover payload now includes summary, parameter table, returns, and
  exceptions in Markdown. Shared with the CLI `hover --format md` renderer.

- **`.drag-lint.json` `docs` section.**
  ```json
  {
    "docs": {
      "captureLooseComments": false,
      "allowBlankLineGap": 1,
      "implPrecedence": "interface"
    }
  }
  ```
  `captureLooseComments` enables the loose-comment path. `allowBlankLineGap`
  (default 1) permits up to N blank lines between a comment block and its
  symbol. `implPrecedence` (default `"interface"`, reserved for future use):
  when both interface and implementation declarations have doc comments,
  selects which side wins. v0.16 always uses interface; set up for v0.17+.

### Notes

- The comment-region scanner respects string literals (odd-quote check) and
  merges adjacent same-kind line comments (`///`) into a single block.
- Schema v3 databases auto-migrate to v4 transparently; no re-index needed
  for schema changes (existing symbols gain docs on next incremental run).