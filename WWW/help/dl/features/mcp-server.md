---
id: mcp-server
title: MCP server
summary: Exposes the index to MCP clients as 15 tools
product: DL
group: editor-integration
order: 110017
since: 0.4.0-alpha
status: shipped
updated: 1.38.0-alpha
---

# MCP server

Exposes the index to MCP clients as 15 tools.

The drag-lint MCP server lets an MCP client (an AI assistant) query the index and run checks through 15 tools.

## Details

**Adds drag-lint's MCP server (`drag-lint serve`) to Claude Code, VS Code and Cursor in one command**, so an AI client can query the index without hand-editing JSON. The installer runs it with `--all` as an optional task; the verb is `drag-lint mcp-config`.

### Running it

```text
drag-lint mcp-config --all --dry-run        (print the change, write nothing)
drag-lint mcp-config --claude-code --db C:\Projects\MyApp\_D-RAG\MyApp.sqlite
drag-lint mcp-config --all --remove
```

### Targets

* `--claude-code` -- user scope, the top-level `mcpServers` of `~\.claude.json`, by file edit (the verb never runs the `claude` CLI).
* `--vscode` -- `servers` in `%APPDATA%\Code\User\mcp.json`.
* `--cursor` -- `mcpServers` in `~\.cursor\mcp.json` (same entry as VS Code, no `env`); counts as installed with a `~\.cursor` folder or an existing `mcp.json`.
* `--all` -- all three; a client that is not installed is skipped. Claude Code counts as installed with a `~\.claude` folder, an existing `CLAUDE_CONFIG_DIR` or an existing `.claude.json`; VS Code with `%APPDATA%\Code\User`.

### What it writes

`{ "type": "stdio", "command": "<engine>", "args": ["serve", "--db", "<index>"] }` (Claude Code adds `"env": {}`). Without `--db` the args are `["serve"]` and the engine picks the index from its manifest when the client starts it. `serve` answers from ONE index, so register one entry per index with `--name`. The engine defaults to the running `drag-lint.exe`; `--engine <exe>` overrides it.

### Safe on a real config

* `--dry-run` writes nothing.
* A real write backs the file up to `<file>.bak-<stamp>`, merges (other servers and keys untouched) and is idempotent: a second run says "unchanged" and writes nothing.
* `--remove` deletes only its own entry; an entry by that name whose command is not `drag-lint.exe` is refused, never touched.
* Keys you added to the entry, an `env` included, survive an update; every `env` and `headers` VALUE prints as `***` (the keys stay).
* Malformed JSON, or JSON with comments a rewrite would drop, is refused with nothing written (the entry to paste by hand is printed). JSON is written UTF-8 without BOM.

### Related

[serve](serve.md) -- the MCP server itself. [init](init-wiring.md) -- registers, indexes and runs `mcp-config --all` for a project in one command. Tests: `tests\autotest\run_mcp_config_verb.ps1` (scratch copies; it asserts the real config files are unchanged).

---

[All features](../index.md) | [CLI reference](../cli.md) | [IDE menus](../ide.md)
