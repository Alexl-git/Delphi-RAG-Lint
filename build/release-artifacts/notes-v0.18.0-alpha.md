## v0.18.0-alpha -- 2026-05-28

### Added

- **`drag-lint context --task "verb qname"`** — composes v0.16 docs + v0.17
  surface/slice/callers/impact into one AI-ready Markdown/JSON/raw payload.
  Verbs: `modify` (default), `inspect`, `refactor`, `delete`, `extend`.
  Automatically includes class surface, implementation slice, caller context
  (configurable depth), and impact summary (for refactor/delete). Output
  formats: `--format md|json|raw`. Example: `drag-lint context --task "modify
  Foo.TBar.Baz" --caller-context 3 --max-callers 10 --db myproj.sqlite`.

- **`drag-lint bench-context [--n N] [--md]`** — measures AI token-reduction
  ratio by sampling N random documented symbols from the database. For each
  symbol, computes the bundle token estimate (using chars / 3.7 heuristic) and
  compares against the baseline (full source file char count / 3.7). Reports
  average reduction ratio: "Bundle avg 234 tokens vs Baseline avg 1847 tokens
  = 7.9x reduction". Useful for understanding bundle efficiency on real
  codebases. Token estimate is a heuristic (not BPE); v0.19+ may add real
  tokenization.

- **MCP: `get_context_bundle` tool** — same as CLI `context` but callable from
  Claude Code, Cursor, or Zed. Arguments: `task` (string), `db` (optional path
  to SQLite), `caller_context` (optional integer, default 3), `max_callers`
  (optional integer, default 5), `format` (optional "md"|"json"|"raw").

### Notes

- **No schema changes.** All features are read-only over v0.16/v0.17 tables.
- **Token heuristic:** Reduction ratio uses simple chars / 3.7 estimate.
  Small single-file fixtures (Docs.pas, ~500 lines) may show ratio < 1 due to
  overhead. Real-project benchmarks (Micronite ORM3 with 795 files) should show
  5-10x reduction. Scaling improves as corpus size increases.
- **TBundleCaller record:** Internal structure introduced. `TContextBundle.Callers`
  array now resolves FilePath at bundle-build time (no lazy lookup).