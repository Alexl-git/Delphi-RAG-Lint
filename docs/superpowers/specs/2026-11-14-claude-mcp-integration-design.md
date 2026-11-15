# Claude Code <-> drag-lint integration (lane CLAUDE-INT, 2026-11-14)

Owner go 2026-11-14. Backlog and numbers policy: `docs\INBOX-claude-mcp-integration-152.md`
(section 2 = conservative numbers only; sections 3-4 = website + article, WEBSITE stream).
Evidence: `C:\TEMP\claude\lanes\claude-int\` (transcripts, proofs, hook test output, report output).

## Pieces

| # | Piece | Where | What it does |
|---|---|---|---|
| 1 | MCP server | `.mcp.json` (repo root) | Registers the DEPLOYED `third_party\dll-win64\drag-lint.exe serve --db src\cli\_D-RAG\drag-lint.sqlite` as stdio server `drag-lint`. Tools appear as `mcp__drag-lint__<tool>`. |
| 2 | Tool descriptions | branch `feat/mcp-descriptions` (src\mcp\DRagLint.MCP.Server.pas) | find_symbol / find_callers / get_impact / get_context_bundle lead with "USE FOR ..."; the initialize instructions send find-unit and text search to the CLI (no MCP tool for them); run_compile_check says it is slow and not read-only. 1.51.x engine change, NOT deployed. |
| 3 | Post-edit lint hook | `~\.claude\hooks\draglint-post-edit.js`, PostToolUse `Write\|Edit\|MultiEdit` | For a .pas/.dpr/.dfm whose project has a `_D-RAG` DB (`resolve-dbs --in`, else `<dir>\_D-RAG\<dproj base>.sqlite` up to 3 parents): `lint <file> --db <db> --json`, keeps findings whose `start_line` is a changed line (structuredPatch, else the new_string located in the file), max 10 shown. 20 s hard timeout. Silent on any error / timeout / no DB / no hit. Kill switch `DRAGLINT_POST_EDIT_OFF=1`. |
| 4 | Index-first guard | `~\.claude\hooks\draglint-first.js` | Every deny names the MCP tools first when a `.mcp.json` naming `drag-lint` is in cwd or a parent (silent elsewhere: no dead-end tool names). An `mcp__drag-lint__*` call counts as an index call (PostToolUse matcher extended). The read-slice credit is capped at 6 k and tagged `cons-v1`. |
| 5 | Usage numbers | global CLAUDE.md "Logs"; `tools\draglint-usage-report.cjs` | Conservative counterfactual + `est_method` column; the report's headline is the conservative figure, the raw log only as "as logged (inflated)". |

## How serve picks DBs

One store per session from the first `--db` (extra `--db`s are ignored with a stderr warning). Tools
whose schema has `db` (get_symbol_doc, get_impact, get_neighbors, get_surface, get_slice,
get_context_bundle, get_implementors, get_wiring, get_exception_facts, get_type_at_position,
find_by_doc_tag, find_undocumented) open that DB per call; **find_symbol and find_callers have no `db`
argument** and always answer from the startup DB. serve does NOT resolve project/library DBs itself.

## Read-only proof

`OpenStore` -> `TSQLiteSymbolStore.Create(path, AReadOnly=True)`. Measured: sha256 + size + mtime of
`drag-lint.sqlite`, `-wal`, `-shm` identical before/after a scripted session
(`db-unchanged-proof.txt`). `lint <file> --db` on the fixture DB: identical (`lint-db-write-proof.txt`).
Exceptions: `run_compile_check` (spawns msbuild/dcc; tries to store findings) and `rename_symbol`
without `dry_run` (writes source files). Recommended local permissions (`.claude\settings.json`,
gitignored -- the owner applies them; an agent may not grant itself permissions):
`"enabledMcpjsonServers": ["drag-lint"]`, `"deny": ["mcp__drag-lint__run_compile_check"]`, and leave
`rename_symbol` on ask.

## Risks

* Two lint hooks per edit (on-save: whole-file fingerprint diff, no DB; post-edit: changed lines with
  the project DB) -- up to ~2 extra lint runs (3-5 s each) per Delphi edit; overlapping findings can be
  reported twice. If that is noise, set `DRAGLINT_POST_EDIT_OFF=1` or retire one.
* A stale project DB makes the post-edit hook miss DB-dependent findings (it never reindexes; the
  owner's IDE / VS Code / agents keep indexing as today).
* Settings and hooks are shared with the ORM3 account (`~\.claude-dl` links to `~\.claude`).
* MCP startup DB is a single project; other projects' questions need the `db` argument or the CLI.

## Rollback

* MCP: delete `.mcp.json` (or `claude mcp remove drag-lint`), restart sessions.
* Post-edit hook: `DRAGLINT_POST_EDIT_OFF=1`, or restore `settings.json` from
  `C:\TEMP\claude\lanes\claude-int\settings.json.bak-20261114` (the post-edit entry and the
  `|mcp__drag-lint__.*` matcher are the only differences).
* draglint-first.js: `~\.claude` is not version-controlled and no pre-change copy was taken; revert
  the marked edits by hand (the `MCP first` block + `mcpHint` calls in the three denies, the
  `mcp__drag-lint__` index-call branch in `main`, the 6 k cap + `cons-v1` in `creditSlice`) or set
  `DRAGLINT_FIRST_OFF=1`. Post-change copy: `C:\TEMP\claude\lanes\claude-int\draglint-first.js`.
* Descriptions: branch not merged; drop `feat/mcp-descriptions`.
