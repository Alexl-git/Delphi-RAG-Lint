# Changelog

All notable changes to Delphi-RAG-Lint. This project is **alpha — expect
breaking changes** until v1.0.

## v0.11.0-alpha — 2026-05-27

### Added
- **`drag-lint index --watch [--interval N]`** — keep the index hot by
  polling the target folder(s) every `N` seconds (default 5). Each tick
  re-walks every resolved file; the existing mtime+sha256 incremental
  skip means unchanged files cost roughly nothing. Self-test on the
  drag-lint corpus: first tick = 0.14s for 16 files / 315 symbols,
  subsequent ticks = 0.02s (all skipped). Combine with `--project` to
  watch every folder pulled in by a .dproj's DCC paths.

### Notes
- Polling, not OS-level filesystem events. Trade-off: simpler, portable,
  no signal-handling subtleties; latency capped at `--interval` seconds.
  A v0.12 candidate is `ReadDirectoryChangesW`-backed watcher for
  sub-second response.
- No schema bump.

---

## v0.10.0-alpha — 2026-05-27

### Added
- **`drag-lint graph`** — emit a unit-level dependency graph from the
  index. One node per indexed source file, one edge per (file A
  references symbol defined in file B) pair, edge weight = count of
  references. Two output formats:
  - `--format dot` — Graphviz, renders via `dot -Tsvg drag-graph.dot -o
    drag-graph.svg` (or pasted into any online Graphviz viewer)
  - `--format mermaid` — Mermaid syntax, renders inline in
    GitHub/Obsidian/most Markdown viewers without external tools
- `--name <substr>` filter restricts the graph to edges whose source OR
  target path contains the substring. Useful for "show me everything
  depending on or used by the parser layer" → `--name Parser`.
- `--output <file>` writes the graph to a file instead of stdout.

### Notes
- Edge resolution is name-only: refs are joined to symbols by
  `LOWER(name)` because the indexer leaves `refs.symbol_id` NULL today.
  That means a ref to a generic name like `Create` will fan out to every
  unit defining a `Create`. Still useful as a structural snapshot — the
  real architectural arrows dominate the small noise. A future iteration
  will resolve `symbol_id` at index time.
- Self-test on drag-lint corpus: `CLI -> Storage.SQLite (48), CLI ->
  Core.Indexer (46), CLI -> Lint.Linter (44), ...` — matches the real
  hierarchy.

---

## v0.9.0-alpha — 2026-05-27

### Added — two project-shaped lint rules

- **`unit-not-in-dpr`** (project-level). Cross-checks the .dproj's
  `<DCCReference Include="..."/>` list against the matching .dpr/.dpk's
  `uses` clause. Emits a warning for every unit listed in the .dproj but
  missing from the program/package source (the dangerous case — drops out
  of the build on next IDE re-open), and an info-level finding for the
  reverse (compiles via search path today, but IDE doesn't track it).
  Invoked via `drag-lint lint --project <file.dproj>`. Self-test on
  drag-lint itself: 0 findings (clean). Real-world test on a 700-file
  Micronite client: 22 mismatches caught, every one a real "I forgot to
  add this to the dpr" bug.

- **`inline-comment-in-multiline-args`** (file-level, layout heuristic).
  Detects trailing `// ...` comments placed inside multi-line argument
  lists, array/set literals, and record initialisers — the exact pattern
  that YADF and other Pascal reformatters reflow incorrectly, silently
  destroying the next array element. Tracks paren/bracket depth,
  `{...}` and `(* ... *)` block comments, and `'string'` literals so URL
  fragments inside license headers don't false-trip. Skips closing-paren
  lines (no reflow target). Real-world test on Micronite client: 70 hits
  across array-of-record initialisers in `Blueprint4.ViewModel.pas`.

### Notes
- Project-level lint introduces `--project <file.dproj>` to the lint
  subcommand. File/folder lint and project lint are independent and can
  be combined in one invocation (run together, findings merge).
- No schema bump in v0.9.

---

## v0.8.0-alpha — 2026-05-27

### Added
- **Type-use references.** The indexer now emits `kind='type_use'` references
  for every `typeref` AST node — field types, parameter types, function
  return types, class/interface inheritance lists, generic type arguments,
  and qualified type names (`Unit.TFoo`). `find-callers --name ISymbolStore`
  on the drag-lint self-corpus now returns 5 sites (was 1): the interface
  decl, the field decl in the Indexer, the ctor parameter, the LSP field,
  and the concrete `TSQLiteSymbolStore` inheritance line. Total refs across
  the same corpus went 1251 → 1528 (+277).
- **`drag-lint import-log <logfile>`** — parse a msbuild/dcc compiler log
  and store findings in a new `compiler_findings` table (schema v3). Cross-
  references each finding to the indexed `files` row when the path matches,
  preserves the raw path otherwise. Accepts three formats:
  - `Foo.pas(45,10): Error E2010: ...`
  - `Foo.pas(45): Hint warning H2077: Value assigned to 'X' never used`
  - `[dcc64 Error] Foo.pas(45,10): E2010 ...`
- **`drag-lint query hints --name <code>`** — query the compiler-finding
  store. `--name H2077` returns every dead-write the compiler flagged across
  the project, with file/line. `--rule <severity>` filters by severity
  (Fatal/Error/Warning/Hint). Useful answer to "where's the dead code?" —
  the Delphi compiler already knows; this just stores its answer for
  cross-session querying.

### Notes
- Schema bumped to v3 (`compiler_findings` table + index). v2 indexes are
  upgraded transparently — existing fuzzy/symbol tables are untouched.

---

## v0.7.0-alpha — 2026-05-27

### Added
- **LSP position resolution.** `textDocument/definition`,
  `textDocument/references`, and (new) `textDocument/hover` now work on
  the cursor position. Implementation reparses the file under the URI
  with tree-sitter, walks to the smallest named node containing the
  cursor, drills into `genericDot`/`exprDot` to pick the rhs identifier
  if the cursor is on a qualified name, then queries the symbol table by
  that identifier text.
- **Hover** returns a Markdown block with the symbol kind + every
  qualified name matching that bare name + first declaration line.

### Fixed
- `file:///` URI encoding emitted an extra leading slash for absolute
  Windows paths (`file:////C:/...`). Strip the leading slash from the
  encoded path before prepending.

### Verified
- Cursor on `FStore.UpsertSymbol` in `DRagLint.Core.Indexer.pas`:
  - definition → 2 results: `ISymbolStore.UpsertSymbol` (interface) and
    `TSQLiteSymbolStore.UpsertSymbol` (concrete impl), each with proper
    file URI + range
  - references → 3 results: the call site + both declarations
- Cursor on `ISymbolStore` in the interface declaration: definition
  returns the interface decl range; references currently returns just
  the declaration because v0.7 refs are call-site-only (not type-use).
  Type-use refs are a v0.8 enhancement.

### Known limitations to flag publicly
- LSP `textDocument/references` only finds call sites today. Type uses
  (`X: ISymbolStore`, class inheritance, parameter types) are NOT
  emitted as refs by the indexer — they'd need a parser-side
  enhancement. Tracked as v0.8.
- No incremental parse on `textDocument/didChange`. The LSP server uses
  the on-disk index + reparses the cursor's file on each request.
  Re-running `drag-lint index` is sub-second per file thanks to v0.4
  incremental, so editor save + index-on-save covers most cases.

---

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
