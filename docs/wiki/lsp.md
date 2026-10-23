# lsp

Starts the LSP (Language Server Protocol) stdio server. This is what the IDE
plugin itself launches to get hover, completion, go-to-definition and
diagnostics inside the editor.

`lsp` is DIFFERENT from `serve`: `serve` is the MCP stdio server for AI
clients such as Claude or Cursor, and nothing in the IDE uses `serve`. The
IDE plugin uses `lsp`.

## Running it from the CLI

```
drag-lint lsp --db <file.sqlite>
```

### Proxy mode: merging drag-lint into DelphiLSP

```
drag-lint lsp --proxy [--delphi-lsp <path>] [--trace <file>] [--merge-diagnostics] [--merge-budget-ms <n>]
```

`--proxy` relays every LSP message between the IDE and RAD Studio's own
DelphiLSP, so the compiler front end keeps answering. The merge flags let
drag-lint add to those answers:

- `--merge-diagnostics` -- append drag-lint's lint findings to DelphiLSP's
  `textDocument/publishDiagnostics` (one notification, source-tagged). OFF by
  default; with every merge flag off the proxy relays DelphiLSP's bytes
  unchanged.
- `--merge-budget-ms <n>` -- the per-frame time budget of a merge handler
  (default 300). A handler that overruns it, raises, or cannot open the index
  makes the proxy forward DelphiLSP's original bytes untouched; merging fails
  open and never drops a message.

### Full rule set on save: `--full-rules` (opt-in)

```
drag-lint lsp --db <db> --full-rules
```

By default the publish on `didOpen`/`didSave` runs a subset of the built-in
checks. With `--full-rules` the server runs `drag-lint lint "<file>" --json`
**out-of-process** (the same path the IDE live runner uses; 8000 ms budget),
publishes that complete finding set in place of the lint subset, and keeps the
store's compiler findings. **OFF by default**: it costs one `lint` run per save.
The measured cost is written to stderr on every save:
`drag-lint lsp: full-rules <file> <ms> ms <n> findings`. On a timeout, a failed
run or invalid JSON the server falls back to the subset and says so on stderr.
Guard: `tests\autotest\run_lsp_full_rules_guard.ps1`. An in-process variant (no
second process start) is deliberately NOT built; it can follow if the measured
cost justifies it.

Status: the flags are accepted now; the diagnostics handler itself lands
with merge task A1. Until then every message is relayed unchanged.

## Reaching it in the IDE

CLI+internal: the plugin starts this process itself, from
`DragLint.Plugin.LspClient.pas:297`. There is no menu item -- the IDE
launches the `lsp` server automatically as a background stdio process, not
via a user-facing command.

## What it needs

An index IS required. The project's DB lives at
`<project folder>\_D-RAG\<project file>.sqlite`; run
`drag-lint resolve-dbs --project <X.dproj>` if unsure.

## Example

Illustrative only:

```
drag-lint lsp --db C:\Projects\MyApp\_D-RAG\MyApp.sqlite
```

This is the same command the plugin runs in the background to serve the
editor's language features for `MyApp`.

## Switching VS Code's Delphi MCP entry off and on

`drag-lint-switch --vscode --status|--on|--off [--workspace <dir>]` toggles
`servers["delphi-lsp"]` in `<dir>\.vscode\mcp.json` (default `<dir>` = current
directory). `--off` writes a whole-file backup `mcp.json.draglint-<yyyymmdd-hhmmss>.bak`
next to it and removes only that entry; `--on` restores the entry from the newest
backup, or from `--template <file>` (a JSON file holding the entry) when there is
none. Exit 0 = done, 1 = already in that state, 2 = VS Code (`Code.exe`) is running
(file untouched), 3 = failure (e.g. no backup and no template). Workspace file only:
the user-level registration in `state.vscdb` is not read or written. Guard:
`tests\autotest\run_lsp_switch_vscode_guard.ps1`.

Limits: a mcp.json containing comments (JSONC) cannot be parsed, so the tool exits 3 and leaves the file untouched. The rewritten file is JSON-equal to the original, not byte-equal (indentation is normalised to 2 spaces); the untouched original is kept in the .bak.
