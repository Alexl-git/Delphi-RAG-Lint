# Register the MCP Server

**Adds drag-lint's MCP server (`drag-lint serve`) to Claude Code and VS Code in one command**, so an AI client can query the index without hand-editing JSON. The installer runs it with `-All` as an optional task; the script is `charts\src\Set-DragLintMcpConfig.ps1`.

## Running it

```
pwsh -NoProfile -File charts\src\Set-DragLintMcpConfig.ps1 -All -DryRun        (print the change, write nothing)
pwsh -NoProfile -File charts\src\Set-DragLintMcpConfig.ps1 -ClaudeCode -DbPath C:\Projects\MyApp\_D-RAG\MyApp.sqlite
pwsh -NoProfile -File charts\src\Set-DragLintMcpConfig.ps1 -All -Remove
```

## Targets

* `-ClaudeCode` -- user scope, the top-level `mcpServers` of `~\.claude.json`; through the `claude mcp` CLI when it is on PATH, else a file edit.
* `-VSCode` -- `servers` in `%APPDATA%\Code\User\mcp.json`.
* `-All` -- both; a client that is not installed is skipped. Claude Code counts as installed with a `~\.claude` folder, an existing `CLAUDE_CONFIG_DIR`, an existing `.claude.json` or a `claude` CLI; VS Code with `%APPDATA%\Code\User`.

## What it writes

`{ "type": "stdio", "command": "<engine>", "args": ["serve", "--db", "<-DbPath>"] }` (Claude Code adds `"env": {}`). Without `-DbPath` the args are `["serve"]` and the engine picks the index from its manifest when the client starts it. `serve` answers from ONE index, so register one entry per index with `-Name`. The engine path is found the same way the charts find it -- see [Charts and the IDE](Charts-and-the-IDE#what-you-need).

## Safe on a real config

* `-DryRun` writes nothing.
* A real write backs the file up to `<file>.bak-<timestamp>`, merges (other servers and keys untouched) and is idempotent: a second run says "no change" and writes nothing.
* `-Remove` deletes only its own entry; an entry by that name whose command is not `drag-lint.exe` is refused, never touched.
* An entry carrying any key beyond type/command/args -- a user-added `env` included -- is updated by file edit, never the CLI, so an env value never lands on the `claude` command line; in every printed Before / After / Commands / dry-run line an env VALUE reads `***` (the keys stay).
* Malformed JSON, or JSON with comments a rewrite would drop, is refused with nothing written. A file a running client rewrote while the script ran is not overwritten. JSON is written UTF-8 without BOM.

## Related

[serve](serve) -- the MCP server itself. Tests: `charts\src\Test-McpConfig.ps1` (temp copies via `-ConfigPath`; it never writes the real files).
