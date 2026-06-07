# Backlog: non-AI features inspired by Graphify

[Graphify](https://github.com/safishamsi/graphify) is a knowledge-graph builder
for AI coding assistants. Reviewed 2026-06-07.

## How Graphify works (answers to the questions)

- **Does it index like us, or is it all LLM?** Both, in two layers:
  - **Stage 1 (code) = tree-sitter static analysis — NO LLM.** Same family as
    drag-lint: it parses code with tree-sitter to extract ASTs, **call graphs**,
    symbols and docstrings. This first stage has **no AI**.
  - **Stage 2 (semantic) = LLM**, only for *prose* (concepts/"why" from Markdown,
    PDFs, papers) and **vision models** for diagrams/images. It does **not bundle
    an LLM** — it reuses the host assistant's model API and sends only semantic
    text, never raw source.
- **Net:** everything Graphify does on the **code** side is non-AI, and we
  already do most of it for Delphi (AST-exact symbols, refs, call refs, uses,
  docs) — arguably deeper, and Delphi-specialised. Their AI is for non-code
  artifacts + design-rationale narration. Their token-saving claim (~49x) is the
  same idea as our context bundles (~60x measured).

## Non-AI things they do that we could add (TODO)

All of these are pure graph/aggregation over data we already index — **no AI**.

- [ ] **`path <A> <B>`** — shortest call/dependency path between two symbols
      (BFS over call + uses edges). Graphify has `graphify path "X" "Y"`.
- [ ] **`neighbors <qname> [--hops N]`** — N-hop neighbourhood of a symbol
      (callers + callees + type uses). We have `impact` (transitive callers);
      this is the bidirectional/“neighbours” view.
- [ ] **`cycles`** — detect circular **unit** dependencies from the `unit_uses`
      table (the schema was literally designed for circular-dependency
      detection). High value for a big Delphi codebase; entirely non-AI.
- [ ] **`report`** — generate a codebase-health Markdown (Graphify's
      `GRAPH_REPORT.md` analogue): top fan-in/fan-out symbols (`top`), circular
      deps (`cycles`), dead code (`find-deadcode`), undocumented public API
      (`find-undocumented`). Pure aggregation of commands we already have.
- [ ] **MCP graph tools** — add `get_neighbors` and `shortest_path` to the MCP
      server (we already expose `get_impact`). Mirrors Graphify's
      `get_neighbors` / `shortest_path`.
- [ ] **Graph export `graph.json` / `graph.html`** — Graphify emits a persistent
      `graph.json` + interactive `graph.html`. We already have `graph`
      (dot/mermaid) + the native VCL viewer; a self-contained JSON + static HTML
      export would round it out (non-AI).
- [ ] *(optional, low priority)* **index Markdown/docs as text nodes** linked to
      code by name — the non-AI slice of their "multi-artifact" ingestion. PDFs
      / images are the AI parts; skip those.

## Where we already match or beat them
- Incremental cache / only-reprocess-changed: we have `--watch` + up-to-date
  skipping already.
- MCP server + token-saving context bundles: done (`serve`, `get_context_bundle`,
  ~60x).
- AST-exact, Delphi-13-specific (+ DFM + Firebird SQL): beyond their generic
  tree-sitter pass.
