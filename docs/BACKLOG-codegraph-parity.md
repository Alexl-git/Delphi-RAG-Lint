# Backlog: ideas from the CodeGraph review (2026-06-17)

[CodeGraph](https://github.com/colbymchenry/codegraph) is a tree-sitter knowledge
graph for AI agents (the same category as Graphify - see
`BACKLOG-graphify-parity.md`). Reviewed 2026-06-17. drag-lint v0.41 already matches
or beats it on almost everything except breadth (20+ langs - intentionally declined)
and onboarding polish.

The one genuinely-new, on-strategy idea (framework-aware DI + DFM edges) is being
built now - see `docs/superpowers/specs/2026-06-17-framework-aware-edges-design.md`.

The two onboarding ideas below are **saved as future ideas, not yet scheduled**:

## Future idea #2 - one-command install / auto-wire MCP

CodeGraph's `npx` auto-detects Claude Code / Cursor / Codex / Gemini / etc. and
writes each agent's MCP server config + permissions, zero-config. drag-lint needs
manual `serve` wiring, `--db` paths, and CLAUDE.md guidance.

- Add `drag-lint init` that writes the MCP server entry into the detected agent's
  config + a per-project `.drag-lint.json` (config already roadmapped; this is the
  installer wrapper around it).
- Low effort, removes adoption friction. Non-AI.

## Future idea #3 - MCP initialize-time self-guidance

CodeGraph's MCP server returns usage guidance in the `initialize` handshake
("treat results as pre-read, don't re-grep"). drag-lint's "drag-lint FIRST"
contract currently lives only in CLAUDE.md, so it only works where that file is
edited. Bake the contract into `serve`'s initialize response so it travels to any
project/agent automatically.

- Tiny change in `DRagLint.MCP.Server.pas` (initialize result), big portability win.

## Also reinforced by CodeGraph (already on graphify backlog - bump priority)

- Self-contained `graph.json` + interactive `graph.html` export.
- `path <A> <B>` / `neighbors <qname>` queries + MCP `get_neighbors` / `shortest_path`.
- `report` codebase-health markdown.
