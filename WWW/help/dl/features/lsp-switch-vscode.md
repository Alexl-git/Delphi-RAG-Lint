---
id: lsp-switch-vscode
title: Switch VS Code Delphi MCP entry
summary: Turns the VS Code Delphi MCP entry off and on with a backup
product: DL
group: editor-integration
order: 110015
since: 1.33.0-alpha
status: shipped
updated: 1.38.0-alpha
---

# Switch VS Code Delphi MCP entry

Turns the VS Code Delphi MCP entry off and on with a backup.

Read this when VS Code's own Delphi MCP server and drag-lint should not both run. drag-lint-switch removes the entry with a backup and restores it later.

## Details

The LSP stream's feature page: the DelphiLSP proxy merge and the three other
LSP-owned features (protocol extensions, full rule set on save, the VS Code
switch). The full flag reference is [lsp](lsp.md); this page says what each
feature is for and how it was verified.

### Proxy merge

`drag-lint lsp --proxy` relays every message between the editor and RAD Studio's
DelphiLSP. Four opt-in merge flags add drag-lint answers to DelphiLSP's, so one
session shows the compiler's errors and drag-lint's findings together; two more
flags tune the proxy itself:

| flag | effect |
|---|---|
| `--merge-diagnostics` | drag-lint findings appended to `publishDiagnostics`, tagged `source: "drag-lint"` |
| `--merge-completion` | drag-lint items unioned into the completion reply, keyed on label and kind |
| `--merge-hover` | drag-lint hover facts appended after a `---` rule |
| `--merge-definition` | drag-lint locations when DelphiLSP answers null or empty; also references and workspace symbols |
| `--merge-budget-ms` | per-frame time budget, default 300 |
| `--delphi-lsp-bits` | `32` forwards to the 32-bit DelphiLSP, `64` (default) to bin64 |

With every merge flag off the proxy relays DelphiLSP's bytes unchanged. Merging
fails open: a handler that overruns the budget, raises or finds no index makes
the proxy forward DelphiLSP's original bytes.

The merged findings are linted from the preprocessed text, exactly as plain
`drag-lint lsp` and `drag-lint lint` lint it: `{$IFDEF}` branches are resolved
with the platform built-ins, or with the defines of the `.dproj` that owns the
file (`--project` wins), so an inactive branch never adds a parser error. Both
modes run one shared setup; the proxy runs it on its merge worker the first time
it lints, so its startup still opens no index.
Guard: `tests\autotest\run_lsp_proxy_preprocess_guard.ps1`.

`--proxy` and `--full-rules` are separate modes. With `--proxy` the engine only
relays and merges: it starts the relay before it reads `--full-rules`, so that
flag does nothing there. The merge flags, in turn, do nothing without `--proxy`.

Guards: `tests\autotest\run_lsp_proxy_*_guard.ps1`.

### Protocol extensions

Without a proxy, `drag-lint lsp` answers from the index: `textDocument/documentSymbol`,
`implementation`, `declaration`, `prepareRename` / `rename`, `codeLens` (caller
counts), `semanticTokens/full`, `inlayHint`, `workspace/executeCommand`
(`draglint.showCallers`) and the `draglint/ping` request. The per-method
behaviour is in [lsp](lsp.md).

### Full rule set on save

`drag-lint lsp --full-rules` runs `drag-lint lint "file" --json` on save, so the
editor shows the same findings as the CLI, including `dl:ok` review markers.
Without the flag the server keeps its small built-in check set unchanged. It
applies to the plain server only; `lsp --proxy` ignores it (see above).

### VS Code switch

`drag-lint-switch.exe` switches VS Code's Delphi MCP entry off and on
(`drag-lint-switch --vscode --off` / `--on`), keeping a whole-file backup of the `mcp.json` it edits. See the end of
[lsp](lsp.md).

### Verification

The proxy merge and the extensions are covered by fixture guards that drive the
built engine over stdio with a stub DelphiLSP; each names a positive control so
that a silent run cannot pass with the feature off. Run the targeted set with
`tests\autotest\run_lsp_*_guard.ps1`.

---

[All features](../index.md) | [CLI reference](../cli.md) | [IDE menus](../ide.md)
