# Changelog

All notable changes to Delphi-RAG-Lint. This project is **alpha — expect
breaking changes** until v1.0.

## v0.6.0-alpha — 2026-05-27

### Added
- **`drag-lint lsp`** — Language Server Protocol stdio server, framed with
  Content-Length headers per spec. `initialize`, `shutdown`, `exit`, and
  `workspace/symbol` work today. `textDocument/definition` and
  `textDocument/references` return empty arrays (placeholders) — they
  need position-to-token resolution which is a v0.7 item (tree-sitter
  reparse on cursor position).
- **`drag-lint top --by fanin`** — ranks names by reference count across
  the index. Aggregates refs by name first (fast path), then attaches a
  sample symbol for context. 1.5 s on 473 k-symbol corpora.
- **`drag-lint export enums`** — emit every `(enum, value)` pair from the
  index. Four formats: `firebird-sql` (CREATE TABLE + INSERTs), `csv`,
  `json` (nested-values), `delphi-const` (paste-ready arrays).
- **`drag-lint export obsidian`** — write one `.md` per unit with YAML
  frontmatter, full symbol list, and a "Referenced by" section using
  `[[wikilinks]]` so Obsidian's graph view becomes a navigable
  cross-reference map of the codebase.

### Fixed
- **Parser**: multi-segment unit names like `DRagLint.Core.Interfaces`
  were getting truncated to just the first identifier (`DRagLint`).
  `WalkUnit` now takes the full text of the `moduleName` node so the
  qualified path is preserved. **Indexes built before this commit need a
  full re-index** (delete the .sqlite and re-run `drag-lint index`) to
  pick up the correct unit names.

---

## v0.4.0-alpha — 2026-05-27

### Added
- **MCP stdio server** — `drag-lint serve --db <file>` speaks JSON-RPC 2.0
  / MCP `2024-11-05` and exposes `find_symbol`, `find_callers`, and `lint`
  as typed tools. Claude Code / Cursor / Zed can wire it via the standard
  `mcpServers` config block. The CLI is still available for token-tight
  use; same engine underneath.
- **Incremental reindex** — `IndexFile` skips files whose `mtime_unix` AND
  `sha256` are already in the `files` table. Reformatting an entire
  project (e.g. with YADF) and re-running `index` only re-parses the
  files that actually changed. The CLI summary line reports the skip
  count when nonzero.

### Notes
- Documentation external-vendor scrub: README, CHANGELOG, design doc,
  and `rules/README.md` no longer name specific commercial vendors or
  upstream open-source library authors except Delphi/Embarcadero
  themselves. Required attribution (MIT) is preserved in
  `third_party/<repo>/LICENSE`.

---

## v0.3.0-alpha — 2026-05-27

### Added
- **Persistent trigram index for fuzzy lookup.** Schema bumped to v2 with a
  new `symbol_trigrams` table populated alongside every symbol insert.
  Fuzzy queries on 473k-symbol indexes drop from ~5,500 ms to ~520 ms
  (>10× improvement). Legacy v1 databases are upgraded lazily on first
  fuzzy query.
- **`drag-lint index --scan-libraries`** — index Delphi Library + Browsing
  paths from the registry (HKCU + HKLM, Win32 + Win64) without needing a
  `.dproj`. Useful as a one-time "library knowledge base" build.
- **Multi-database queries** — repeat `--db <file.sqlite>` to query across
  several indexes at once. Results are concatenated. Useful for separating
  per-project indexes from a shared `delphi-libs.sqlite`.
- **Tree-sitter query predicates** (`#eq?`, `#not-eq?`, `#match?`,
  `#not-match?`, `#any-of?`, `#not-any-of?`) evaluated by the external
  rule loader. Sample `writeln-in-source.scm` now uses `(#eq? @callee
  "WriteLn")` so it fires only on real `WriteLn` calls.

### Changed
- README + design docs reworded to avoid naming any prior commercial tool.

### Known limitations
- Fuzzy lookup latency target was <500 ms — we hit ~520 ms on 473k symbols.
  Further wins likely need a daemon (MCP server in v0.4).
- `--scan-libraries` pulls in a wide path set — a large 3rd-party VCL
  component library alone can take 3 minutes to index. Use `--dry-run`
  first to inspect what will be scanned.

---

## v0.2.0-alpha — 2026-05-27

### Added
- **Full symbol coverage**: `interface`, `record`, `enum`, `enum_value`,
  `property`, `field` symbols emitted in addition to the v0.1 set
  (`unit`, `class`, `method`, `procedure`, `function`, `constructor`,
  `destructor`).
- **DFM form indexing** (via `tree-sitter-dfm.dll`). `object Name: TClass`
  emits `form` (root) or `component` (nested); event-handler bindings
  (`OnClick = btnOKClick`) emit references that show up in `find-callers`.
- **External lint rule plugins**. `<exedir>\rules\*.scm` query files +
  matching `*.json` metadata loaded at startup and run alongside built-in
  rules.
- **`drag-lint index --project <file.dproj>`** mode. Resolves the .dproj's
  `DCC_UnitSearchPath`, the .dpr's `uses X in 'path'` clauses, and Library
  + Browsing paths from registry (HKCU + HKLM, Win32 + Win64). Expands
  `$(BDS)` macros and deduplicates the result.
- `--dry-run` flag to inspect the resolved folder list without indexing.

### Changed
- `FindCallersByName` no longer hardcodes `kind='call'` — matches all
  reference kinds including DFM event-bindings.

---

## v0.1.0-alpha — 2026-05-27

Initial public surface:
- Indexer for `.pas`, `.dpr`, `.dpk` via `tree-sitter-delphi13`
- SQLite store (FireDAC), per-file transactions
- `query --name`, `query --qname` with **fuzzy fallback** (Levenshtein)
- `query find-callers --name <X>` returns deterministic call sites
- Built-in lint rule `field-by-name-in-loop`
- CLI: index / query / lint / --json / --version / --help

Scaled tested on:
- Micronite ORM3 (708 .pas + 86 .dfm + .dpr + .dpk = 795 files) → 44 169
  symbols, 42 341 references, 8 s
- Delphi RTL+VCL+FMX+Data (1295 files) → 212 083 symbols, 250 663 references,
  60 s
- Large 3rd-party VCL component library full install (4460 files) →
  473 756 symbols, 387 668 references, 179 s
