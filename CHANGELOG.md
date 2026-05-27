# Changelog

All notable changes to Delphi-RAG-Lint. This project is **alpha — expect
breaking changes** until v1.0.

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
