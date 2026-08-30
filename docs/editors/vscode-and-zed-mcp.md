# Using drag-lint from VS Code and Zed (MCP)

drag-lint ships two stdio servers. This page covers the one that works **today with
no extension to install**:

* `drag-lint serve --db <db>` -- MCP server (JSON-RPC 2.0, protocol 2024-11-05).
  Both VS Code and Zed consume MCP natively, so this is pure configuration.
* `drag-lint lsp --db <db>` -- LSP server. Neither editor can launch a bare LSP
  binary from settings alone; each needs a small extension to spawn it. Those
  extensions do not exist yet -- see "LSP: not yet" at the bottom.

Everything here is Windows-only, matching the engine.

## Prerequisites

1. `drag-lint.exe` (Win64) and its `tree-sitter*.dll` companions in the same folder.
   The canonical location is `third_party\dll-win64\`. A bare exe with no DLLs
   beside it falls through to `PATH`, can pick up an x86 DLL, and dies with
   `0xC000007B`.
2. A built index (`.sqlite`). Build one with `drag-lint index <path> --db <db>`.
3. Know which DB answers for the code you are editing. One MCP server entry = one
   DB, so add one entry per codebase you want queryable.

Index locations on a standard setup (`third_party\dll-win64\drag-lint.json`):

Since 2026-08-09 there is **one DB per project**. Since 2026-08-11 each
project's DB lives in a hidden `_D-RAG` folder **beside that project's own
`.dproj`** (`<project folder>\_D-RAG\<project file base name>.sqlite`), not in
a shared folder. Only the SQL and Library indexes -- which have no owning
project folder -- still live under `C:\Projects\.drag-lint\`:

| Section | DB |
|---|---|
| `ORM3-Micronite2027` | `C:\Projects\DB\ORM3\CLIENT\_D-RAG\Micronite2027.sqlite` (+ seven more `ORM3-*` DBs, each in its own project's `_D-RAG`) |
| `SQL` | `C:\Projects\DB\SQL\drag-lint-sql.sqlite` |
| `DragLint-Cli` | `C:\Projects\Delphi-RAG-lint\src\cli\_D-RAG\drag-lint.sqlite` (+ `DragLint-Wizard`, `DragLint-Tests`, `DragLint-CorpusScan`, each in their own project's `_D-RAG`) |
| `Library[Win32]` | `C:\Projects\.drag-lint\library-Win32.sqlite` |
| `Library[Win64]` | `C:\Projects\.drag-lint\library-Win64.sqlite` |

Run `drag-lint resolve-dbs --platform <p>` for the authoritative list, or
`resolve-dbs --project <x.dproj>` / `--in <x.pas>` to resolve one target.

> **Multi-DB:** `query` accepts repeated `--db`. **`serve` does NOT** -- verified
> 2026-08-30. It accepts repeated `--db`, opens only the FIRST, and answers every
> request from that one. Since 2026-08-30 it says so: passing more than one
> prints a warning to stderr naming each ignored database. Use one DB per server
> entry.

## VS Code

VS Code reads MCP servers from `mcp.json`. User-level applies everywhere:

`%APPDATA%\Code\User\mcp.json`

```json
{
  "servers": {
    "drag-lint": {
      "type": "stdio",
      "command": "C:\\Projects\\Delphi-RAG-lint\\third_party\\dll-win64\\drag-lint.exe",
      "args": ["serve", "--db", "C:\\Projects\\DB\\ORM3\\CLIENT\\_D-RAG\\Micronite2027.sqlite"]
    }
  }
}
```

Per-workspace instead, commit `.vscode/mcp.json` in the repo with the same
`servers` block -- useful when each repo has its own index.

Add more codebases as sibling entries (`drag-lint-library`, `drag-lint-sql`, ...),
each with its own `--db`.

## Zed

Zed calls them **context servers**. Edit `%APPDATA%\Zed\settings.json`:

```json
{
  "context_servers": {
    "drag-lint": {
      "source": "custom",
      "command": "C:\\Projects\\Delphi-RAG-lint\\third_party\\dll-win64\\drag-lint.exe",
      "args": ["serve", "--db", "C:\\Projects\\DB\\ORM3\\CLIENT\\_D-RAG\\Micronite2027.sqlite"],
      "env": {}
    }
  }
}
```

Zed's context-server schema has changed across releases (an older shape nested
`command` as an object with `path`/`args`/`env`). If the server does not appear,
check the shape against your installed Zed's docs before assuming drag-lint is at
fault.

## What you get

15 typed tools, all read-only except `rename_symbol`:

`find_symbol`, `find_callers`, `find_by_doc_tag`, `find_undocumented`,
`get_symbol_doc`, `get_impact`, `get_wiring`, `get_surface`, `get_slice`,
`get_context_bundle`, `get_type_at_position`, `lint`, `rename_symbol`,
`run_ast_checks`, `run_compile_check`.

Two are worth calling out to an agent explicitly:

* `get_context_bundle` -- doc + class surface + the target's own body + capped
  callers. Measured ~60x leaner than reading the source files. Prefer it over
  "read the whole unit".
* `run_compile_check` -- spawns `dcc64` (for `.pas`/`.dpr`/`.dpk`) or msbuild (for
  `.dproj`) and returns parsed H/W/E/F findings as JSON. Needs a licensed,
  non-Community Delphi install; Community Edition forbids command-line
  compilation.

## Verifying it works

Before wiring an editor, confirm the server starts and the DB answers:

```
drag-lint query --name TFDManager --db <db> --quiet --exact
```

A row back means the exe, its DLLs and the DB are all healthy. If that works but
the editor shows no server, the problem is the editor's config shape, not
drag-lint.

`serve` speaks JSON-RPC on stdin/stdout and will sit waiting when launched by
hand -- that is correct behaviour, not a hang.

## Troubleshooting

| Symptom | Cause |
|---|---|
| `0xC000007B` on start | tree-sitter DLLs missing beside the exe; an x86 DLL got picked up from `PATH` |
| Server starts, every query returns nothing | Wrong `--db` for the code you are editing |
| `0 match(es)` for a symbol you can see | Stale index -- reindex that path, then retry |
| Banner text mixed into output | Pass `--quiet`; the `(loaded defaults from ...)` line is stderr by design |

## LSP: not yet

`drag-lint lsp --db <db>` implements 12 methods -- `initialize`, `shutdown`,
`textDocument/` `hover`, `definition`, `references`, `completion`,
`signatureHelp`, `didOpen`, `didChange`, `didSave`, `publishDiagnostics`, and
`workspace/symbol`. Diagnostics merge lint findings with `dcc` compiler findings.

It is exercised today by the RAD Studio design-time plugin. What does **not**
exist is the per-editor launcher each needs:

* **VS Code** -- a TypeScript extension wrapping `vscode-languageclient` to spawn
  the process and bind it to Pascal files.
* **Zed** -- a Rust/WASM Zed extension registering the same binary as a language
  server.

Neither needs engine work. Until they exist, MCP is the supported path.
