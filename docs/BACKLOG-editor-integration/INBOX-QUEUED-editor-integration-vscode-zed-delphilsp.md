# QUEUED -- editor integration: VS Code, Zed, and DelphiLSP

**Status: NOT YET READ. Do not action this yet.**

**Filed:** 2026-08-10, mid-session, by the owner.
**Trigger to open it:** when the **autodoc + linter** workstream is finished --
i.e. the noise purge has converged, the doc engine is stable, and `relint` has
been run on YADF and DataCopy. Not before.

This note exists only to make sure the topic is not lost between sessions. It
carries **no new analysis** -- everything below already exists in writing. Its
job is to be the one place a cold session looks to find all of it.

---

## The ask, in one line

Make drag-lint usable from **VS Code** and **Zed**, and put **Embarcadero's
`DelphiLSP.exe`** behind it so editors get compiler-exact answers and index
answers from one server.

## What already exists -- read these, in this order

| Doc | What it holds |
|---|---|
| `docs/editors/vscode-and-zed-mcp.md` | The path that **works today**: MCP via `drag-lint serve`, pure configuration, no extension. Config blocks for both editors, the 15 tools, troubleshooting table. |
| `docs/INBOX-draglint-lsp-proxy-and-editor-integration.md` | The **why and the ask**. The proxy design, the deadline-with-fallback rule, the three silent traps, the four-stage plan. |
| `docs/INBOX-ide-lsp-ram-and-shim-todo.md` | Measurements + the IDE-side TODOs (companion to the above). |
| `docs/superpowers/specs/2026-08-05-delphilsp-union-design.md` | The union design itself. |
| `docs/INBOX-editor-integration-and-delphilsp-union.md` | Earlier framing of the same union. |
| `docs/INBOX-editor-native-extensions-and-build-orchestration.md` | Native-extension and build-orchestration angle. |

## The three facts that shape the work

1. **DelphiLSP does not implement find-references, workspace symbols, or rename.**
   drag-lint advertises `referencesProvider` and `workspaceSymbolProvider`, so for
   those methods there is nothing to merge -- drag-lint is the only provider. That
   is the capability argument, and it is stronger than the speed argument.
2. **Do not sell this on RAM.** It was measured: DelphiLSP is out-of-process and
   costs the 32-bit IDE essentially nothing. Sell it on **fault isolation** -- today
   a wedged DelphiLSP is a manual-kill outage; under a proxy it degrades to
   index-only and restarts itself.
3. **MCP works now; LSP needs a per-editor launcher that does not exist.** Neither
   editor can spawn a bare LSP binary from settings. VS Code needs a TypeScript
   extension wrapping `vscode-languageclient`; Zed needs a **Rust/WASM** extension
   (`wasm32-wasip1`) -- and **there is no Rust toolchain on this machine**. Stage 2
   of the plan (drive the proxy from VS Code / Zed) has standalone value even if
   the IDE file-swap in stage 3 never happens.

## The one small engine item that is genuinely ours

`drag-lint lsp` reports `serverInfo.version` as `0.40.5-alpha` while the CLI
banner says `1.2.2-alpha`. Editors surface that string in their LSP logs. Cheap
fix; do it whenever the file is open for another reason.

## Why it is deferred

`document --apply` rewrites source and the lint rules are still moving. Editor
work touches a different surface (servers, extensions, process supervision) and
would fork attention away from the finding-count work that is currently mid-flight.
The IDE workstream explicitly wrote its notes "to be picked up *after* your current
work lands so there is no interference." Honour that.
