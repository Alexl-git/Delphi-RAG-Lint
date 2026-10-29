# XERJ evaluation for drag-lint (2026-10-28)

## Verdict

**Do not clone the DL index into a vector/RAG store. Not worth it.** DL's index is
already a structured, exact, compiler-grade graph (symbols, refs, call edges, uses,
types). A vector or fuzzy store would answer the same questions less precisely and add a
second source of truth that goes stale. XERJ itself concedes the point: its graph layer is
"not a graph database", its code ranking is lexical, and its default embedder is a
feature-hashing one. DL is already ahead of XERJ on code structure.

Worth borrowing is small and cheap: (1) a measured token-savings counter, (2) bounded
traversal with an explicit "not shown" report, (3) a graph-proximity / concept lookup built
on the FTS5 DL already has, not on vectors. A neural embedding column is an optional later
experiment, only if a measured failure class justifies it.

## What XERJ is, and how sure I am

Identification: **XERJ**, spelled as the owner wrote it (not a mishearing). Confidence in
the identity: about 85%. It is a 2026 project matching "RAG / agent memory / code search"
and the name is exact. I could not find the specific video, so the link to the owner's
video is inferred.

- Local-first search engine and MCP server for AI agents; one Rust binary, Apache-2.0.
- Indexes code, docs, logs, JSONL/CSV, PDF; Elasticsearch-compatible API; 21 MCP tools.
- Code: tree-sitter symbols and line numbers (`xerj def` = file:line + signature),
  content-hash incremental reindex.
- Search: BM25, kNN, hybrid (RRF / linear). Default embedder is a local lexical
  feature-hashing one; neural embedding is opt-in (about 90 MB model).
- `/_graph` "link index": 8 deterministic detectors (7 structural: wikilinks, markdown
  links, hrefs, path citations, section order, directory chains; 1 shared-term), evidence
  per edge, max 2 hops (3 hops is an HTTP 400 refusal), caps and a `not_shown` count in
  every response.
- `/_memory/{namespace}`: agent memory store/recall; recall can be blended or restricted by
  graph proximity (1.0 for a seed, 0.5^hop x weight otherwise).
- `xerj gain`: reports tokens saved from counted usage.
- "Reference coding": the agent indexes similar open-source repos and searches how they
  solved the task.

Claims: 2.7x fewer output tokens and 2.1x cheaper than grep-driven work on 8 tasks, 4
languages, 16 runs per arm (vendor-run); "about 5x" is field anecdote. The vendor itself
says the gain is neutral to harmful on popular libraries the model has memorised.
Maturity: about 17k stars, but release-candidate builds (rc.96 to rc.99), failing CI seen
by a reviewer, and an `--insecure` mode that makes every caller superuser. Treat all
numbers as unverified.

## Why a RAG clone of the DL index is a waste

1. **Wrong tool for the question classes.** DL's questions are exact: who calls Bar, which
   unit declares X, what breaks if I change Y. A nearest-neighbour hit is the wrong answer
   shape; the call-edge table is the right one. XERJ's own FAQ lists variable-depth
   traversal, shortest paths and typed reasoning as things it does NOT do. DL does them
   (`call-path`, `impact`, `graph`).
2. **Staleness doubles.** The index is already the thing that goes stale (see the
   stale-count lessons). A second store needs its own incremental sync, fingerprint and
   "files > walked" rule, and every extractor bump would re-embed on top of the hours-long
   re-parse.
3. **Delphi code is poor embedding material.** Small corpus per project, identifiers
   dominate, vocabulary is German/English/project jargon. General embedders add little
   over trigram FTS. XERJ's own default embedder is lexical, i.e. effectively FTS.
4. **Footprint.** DL is a local, no-LLM-call tool. A neural model means a ~90 MB asset, a
   runtime dependency and an installer story for an unmeasured gain.
5. **XERJ's win is over grep on raw text.** DL already replaces grep over Delphi sources
   (`query`, `query --text`, `context`).
6. **Associative graph walks are already native.** `find-callers`, `find-callees`,
   `impact --depth`, `ask butterfly|change-impact|deps` are bounded graph walks with
   compiler-resolved edges, not co-occurrence guesses (cf. EcphoryRAG-style co-occurrence
   graphs, an approximation DL does not need).

## Ideas worth borrowing, ranked by value / effort

| # | Idea | From XERJ | DL change | Value | Effort |
|---|------|-----------|-----------|-------|--------|
| 1 | Counted savings report | `xerj gain` | `context` / `query` record `tokens_returned` and `source_bytes_avoided` to a per-user log; a `gain` view sums it. Replaces the hand-written `stats\draglint-usage.log` estimates. | High: turns manual logging into a product feature and an honest number | Low |
| 2 | Explicit "not shown" accounting | `not_shown`; 3 hops = refusal, not truncation | `impact`, `ask`, `context --max-callers`: always print "N omitted by cap; rerun with --cap M". Audit which verbs truncate silently. | High for agents: they cannot tell a short answer from a clipped one (the "answers SHORT, never visibly wrong" lesson) | Low |
| 3 | Evidence per edge | edge carries detector + type | Expose in `--json` the resolution kind of each call/ref edge (exact / name-only / ambiguous) so an agent can weight a caller. May already be in the DB. | Medium-high | Low-Med |
| 4 | Blend/restrict by graph proximity | `_recall graph:{mode,seeds,hops,weight}` | `query --text` and doc-prose search gain `--near <QName> --hops 2`: restrict or boost hits to symbols within N call/uses hops of a seed. Pure SQL over existing tables, no vectors. | Medium: the one genuinely "associative" gain | Med |
| 5 | Concept lookup over doc facts | hybrid BM25 + kNN | BM25-ranked FTS5 over doc-comment summary/remarks plus identifier tokens split on camelCase (`ApplyDelta` -> apply delta), so "where do we apply row changes" finds it. If measured recall still fails, THEN trial a small embedding column. | Medium | Med |
| 6 | Overview tool | `xerj_map`, `brain_overview` | One bounded `overview` call for an agent's first turn: units by layer, top fan-in symbols, entry points, forms. Parts exist (`graph`, `outline`). | Medium | Med |
| 7 | Content-hash skip | hash match skips parse | Confirm DL's incremental hashes content, not mtime only. Probably done. | Low | Low |
| 8 | One-command MCP/LSP wiring | `xerj init` | Register DL with Claude Code / Cursor in one command. | Medium (adoption) | Low-Med |

Suggested first step: items 1 and 2 together (small, immediately measurable), then 4 as
the only truly associative feature.

## What to skip

- Vector DB or cloned RAG store of the DL index (see above).
- Elasticsearch-compatible API: DL's consumers are CLI, LSP and IDE.
- Generic autoindex of logs/PDFs/CSV: out of scope for a Delphi code tool.
- Agent memory namespaces (`/_memory`): DL is a code index; handoffs, MEMORY.md and the
  wiki already do that job.
- "Reference coding" (indexing other people's repos): a separate product; DL's platform
  library DBs already cover RTL/VCL/DevExpress, and the vendor's own caveat says it helps
  least on well-known code.
- Remote reranking: sends source text off-machine; conflicts with local-only, no-LLM-call.
- Co-occurrence knowledge graphs: DL has resolved edges, which are strictly better.
- Copying the benchmark claims: vendor-run, 8 tasks. If DL wants a number, measure its own
  (idea 1) on real Micronite tasks.

## Caveats

- Web research only; I did not run XERJ and did not find the owner's video.
- All XERJ performance figures are the vendor's; no independent verification found.
- Ideas 3 and 7 assume the data is already in the DB; check with `schema --format json`
  before scoping.

## Sources

- [xerj-org/xerj (GitHub, official)](https://github.com/xerj-org/xerj)
- [XERJ site](https://xerj.org/)
- [XERJ: Should agent memory use a graph?](https://xerj.org/answers/knowledge-graphs-for-agent-memory)
- [The Menon Lab: XERJ review](https://themenonlab.blog/blog/xerj-local-search-reference-coding-agents)
- [EcphoryRAG (arXiv 2510.08958), unrelated associative-memory RAG paper](https://arxiv.org/pdf/2510.08958)
- DL: `README.md`, `docs\AI-USAGE.md` (query --text FTS5, context, ask, impact).
