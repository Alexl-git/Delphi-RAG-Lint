## v0.21.0-alpha -- 2026-05-28

### Added

- **Delphi IDE plugin (OTAPI design-time package)** — `src/delphi-plugin/` with
  `dclDragLintWizard.bpl` design-time package for RAD Studio 13 Florence (37.0).
  Registers as a wizard in the IDE's Tools menu with four entries: Hover at Cursor,
  Show Completion, Show Signature Help, Run Diagnostics. Menu invocations are
  modal for v0.21 (no custom popup forms or keystroke bindings — deferred to v0.22).

- **LSP client (`TDragLintLspClient`)** — spawns `drag-lint.exe lsp` as a persistent
  subprocess with `Winapi.Windows.CreateProcess` and round-trips JSON-RPC 2.0
  requests over anonymous pipes (`CreatePipe`). Handles `initialize` → `hover` /
  `completion` / `signatureHelp` → `shutdown` lifecycle. Implemented in
  `DragLint.Plugin.LspClient` (unit).

- **publishDiagnostics notification routing** — LSP `textDocument/publishDiagnostics`
  notifications are collected and posted to RAD Studio's Messages pane via
  `IOTAMessageServices.AddToolMessage`. Thread-safe via `TThread.Queue` to marshal
  IDE callbacks from the LSP client's read pump.

### Notes

- **v0.21 is scope-reduced** — Tools menu invocation only (no keystroke bindings,
  no custom popup forms). Full editor integration with hot-keys and rich popups
  moves to v0.22 pending polish of OTAPI event wiring.
- **LSP client tested standalone** — `tests/fixtures/T27_lsp_client.dpr` exercises
  the client with real `drag-lint.exe` binary; round-trips initialize + shutdown
  + basic requests verify the pipe protocol and JSON-RPC framing.
- **Requires PATH setup** — the v0.21 wizard expects `drag-lint.exe` on the system
  PATH; plugin will not launch without it.
- **No schema changes.** All features are read-only over v0.20 symbol tables.