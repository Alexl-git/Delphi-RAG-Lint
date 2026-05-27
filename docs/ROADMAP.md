# Roadmap & Open Questions

A running answer-thread for design decisions that come up during development.
Lives under `docs/` so anyone (humans, AI assistants, contributors) can pick
up cold and understand *why* the project shape is what it is.

## What v0.4 is doing right now

1. **Incremental reindex on file change** (hash + mtime tracking) — see
   "Reformat & reindex" section below
2. **MCP server** (`drag-lint serve`) — for Claude Code / Cursor / Zed AI
   tools that speak the protocol natively
3. **Direct CLI/JSON API mode** — for AI tools that prefer fewer tokens per
   call (see "MCP vs API" below) and for plain shell scripts
4. **`.dproj` cleanup** — the inherited template references hundreds of
   packages a console exe doesn't need

---

## Reformat & reindex — what happens if I run YADF (or any reformatter)?

**Short answer:** v0.4 lands the answer. Files that changed since the last
index get re-emitted; everything else is skipped.

### How it works
- The `files` table already stores `mtime_unix` + `sha256` per indexed file
- v0.4's `Indexer.IndexFile` short-circuits when both match the on-disk
  values for an already-indexed file (no re-parse, no symbol churn)
- When `sha256` differs (YADF moved your lines, you edited the file, etc.),
  the indexer:
  - opens a per-file transaction
  - **cascade-deletes** the existing `symbols` rows for that file (the
    `symbol_trigrams` FK cascade kicks in too, so the trigram index stays
    consistent)
  - re-parses, re-emits symbols + references + trigrams
- Net result: reformatting touches only the affected files, sub-second per
  file, and your saved queries / find-callers results stay correct without
  any manual re-index step

### A daemon mode (v0.5+) will watch the file tree
- Either polling for mtime changes every N seconds, or hooking
  `ReadDirectoryChangesW` for instant-notification reindex
- Useful if you want "always-fresh" symbol lookups while editing — the
  Claude Code / Cursor case
- Not in v0.4 — the per-call `index` mode is enough to demonstrate the
  hash-based skip path

---

## MCP vs API — should we do both?

**Short answer: yes, both. They serve different jobs.**

### What MCP gives you
- **Auto-discovery by the host:** Claude Code, Cursor, Zed, Codeium list
  your tools without configuration. Calling `find_callers` is a typed
  tool the AI knows about by name.
- **Negotiated schemas:** the host shows the human the actual parameter
  shapes from your server, not a free-form prompt.
- **Long-lived process:** the server stays warm — the trigram index stays
  in memory, queries are sub-100 ms after the first call.

### What MCP costs you
- **More tokens up front:** every conversation that has MCP enabled
  consumes some context to enumerate the tools and their schemas. For an
  always-on assistant you pay that cost every session — common pushback
  on Twitter/LinkedIn from people running tight context budgets.
- **More protocol surface to maintain:** JSON-RPC handshake, capability
  exchange, error encoding.

### What direct CLI / JSON gives you
- **Zero token cost when not used:** the AI only spends tokens when it
  *decides* to call drag-lint (vs MCP, where the tool list is in context
  every turn).
- **Works from anything:** bash, Python, Powershell, another Delphi
  program, a CI pipeline. No client library required.
- **Stable forever:** stdout is JSON, exit codes are documented. No
  protocol versioning surprise.
- **Better for batch jobs:** "index a folder, dump every callers-of-X to
  JSON, feed to a script" doesn't need MCP at all.

### The plan in v0.4
Both modes share the **same** core engine (`DRagLint.Core.Interfaces` →
`TSQLiteSymbolStore` → `TLinter`). MCP is a thin stdio JSON-RPC adapter on
top; CLI is the existing argparse. AI tools pick the mode that fits:

- **Light-touch AI integration (most cases):** AI shells out to
  `drag-lint query find-callers --name X --json` once, parses one JSON
  blob, done. No always-on tool context.
- **Always-on integration (Claude Code, Cursor with the user's permission):**
  point at `drag-lint serve` and use typed tool calls.

Same .exe; different invocation. You don't pick one and lose the other.

---

## What else would actually improve this?

Ranked by leverage, what I'd reach for next:

1. **BM25 over AST-chunked text** — full-text search across docstrings,
   comments, string literals, code identifiers — answers "what file
   discusses the loader cleanup we did" in the way grep can't. SQLite has
   FTS5 built-in; the schema only needs one virtual table + triggers.

2. **Cross-database joins via SQLite ATTACH** — current multi-DB iterates
   sequentially. `ATTACH DATABASE` lets SQL `UNION` across in one round
   trip — relevant when query latency starts to matter (live editor
   integrations).

3. **More built-in lint rules** — there are ~5 candidate rules in my own
   project memory: units-not-registered-in-both-.dpr-AND-.dproj,
   case-sensitive identifier mismatch, dangling `TBytes` after a stream
   close, `Result := nil` on a TInterfacedObject, FormGlobal coupling in
   data modules. Each is 10–50 lines of walker code.

4. **LSP server** — many editors support LSP but not MCP. A thin LSP
   adapter that exposes "go to definition" and "find references" would
   make drag-lint useful from Vim, VS Code, Sublime, Lazarus IDE without
   any AI in the loop.

5. **Embedding-aware semantic search** — currently fuzzy is Levenshtein,
   which catches typos but not synonyms. Optional embedding hookup
   (calling a local server's `/embeddings` API when configured) would let
   `query --semantic "loop that aggregates dataset rows"` work. Optional
   means "off by default, on if you set a config flag" — keeps the no-AI
   promise intact for users who want that.

6. **In-IDE BPL package** — drag-lint's query + lint as menu items inside
   the Delphi IDE. Hits the audience that doesn't want a CLI.

7. **Visual call-graph export** — `drag-lint graph --root TMyForm --format
   dot` → graphviz file → PNG. Lint review + onboarding aid.

8. **`.drag-lint.json` per-project config** — rule enable/disable, scan
   exclusions, target Delphi version. Makes the tool feel like ESLint /
   golangci-lint in muscle memory.

---

## Roadmap (planned releases)

- **v0.4** — incremental reindex (hash + mtime), MCP server, direct
  JSON-API mode for AI tools that prefer it, .dproj cleanup
- **v0.5** — BM25 over AST chunks, daemon mode with `ReadDirectoryChanges`
  watching, ATTACH-based multi-DB joins, 3+ new lint rules
- **v0.6** — LSP server, `.drag-lint.json` config
- **v0.7** — embedding hookup (optional), graph export
- **v1.0** — BPL in-IDE package, additional `ISymbolStore` backends, stable
  CLI surface

Everything alpha until v1.0. Breaking changes between minors are expected.
