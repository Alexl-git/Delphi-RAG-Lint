# lsp-proxy-merge

The LSP stream's feature page: the DelphiLSP proxy merge and the three other
LSP-owned features (protocol extensions, full rule set on save, the VS Code
switch). The full flag reference is [lsp](lsp.md); this page says what each
feature is for and how it was verified.

## Proxy merge

`drag-lint lsp --proxy` relays every message between the editor and RAD Studio's
DelphiLSP. Five opt-in merge flags add drag-lint answers to DelphiLSP's, so one
session shows the compiler's errors and drag-lint's findings together; two more
flags tune the proxy itself:

| flag | effect |
|---|---|
| `--merge-diagnostics` | drag-lint findings appended to `publishDiagnostics`, tagged `source: "drag-lint"` |
| `--merge-completion` | drag-lint items unioned into the completion reply, keyed on label and kind |
| `--merge-hover` | drag-lint hover facts appended after a `---` rule |
| `--merge-definition` | drag-lint locations when DelphiLSP answers null or empty; also references and workspace symbols |
| `--merge-navigation` | type and call hierarchy, type definition, document highlight and folding answered from the index, for each provider DelphiLSP does not advertise |
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

## Protocol extensions

Without a proxy, `drag-lint lsp` answers from the index: `textDocument/documentSymbol`,
`implementation`, `declaration`, `prepareRename` / `rename`, `codeLens` (caller
counts), `semanticTokens/full`, `inlayHint`, `workspace/executeCommand`
(`draglint.showCallers`) and the `draglint/ping` request. The per-method
behaviour is in [lsp](lsp.md).

## Full rule set on save

`drag-lint lsp --full-rules` runs `drag-lint lint "file" --json` on save, so the
editor shows the same findings as the CLI, including `dl:ok` review markers.
Without the flag the server keeps its small built-in check set unchanged. It
applies to the plain server only; `lsp --proxy` ignores it (see above).

## VS Code extension: DelphiLSP proxy (1.6.8)

The drag-lint VS Code extension starts plain `lsp` by default. Setting
`dragLint.delphiLsp` = `true` makes it start `lsp --proxy` plus the flags of
`dragLint.delphiLspMerge` (default all five `--merge-*` flags; an empty list is a
plain relay), then the usual `--db` pairs and `--full-rules` (ignored by the
proxy). The args line is written to the drag-lint output channel. Changing
either setting restarts the server.

What DelphiLSP needs to start (measured headless against
`Studio\37.0\bin64\DelphiLSP.exe`, 2026-11-20): the proxy finds `bin64\DelphiLSP.exe`
itself, but DelphiLSP learns the project only from a
`workspace/didChangeConfiguration` carrying the `settings` of the IDE's
`<Project>.delphilsp.json` (RAD Studio writes it when the project is opened).
Without it DelphiLSP publishes no diagnostics and hover answers null. The
extension sends it after every server start and when the active Pascal unit
changes project, and shows a warning when none is found. It picks, in order:
`dragLint.delphiLspConfig`; the `*.delphilsp.json` nearest the active unit
(walking up to the workspace root); the config it already sent, when the active
unit has no usable nearest one; the first one found in the workspace. Files
under `.claude`, `worktrees`, `node_modules` and `.git` are never picked, so a
unit opened from a stale agent worktree does not move DelphiLSP to that
worktree's project or to an unrelated one (1.52.3). The `.delphilsp.json` must
carry the unit search path (`-U`/`-I` in `dccOptions`); a file without it gives
`F1027 Unit not found: 'System'` from DelphiLSP.

Exit code (1.52.3): `lsp --proxy` exits with DelphiLSP's exit code, except after
the client's `shutdown` request: then it exits 0 and writes DelphiLSP's code to
stderr. DelphiLSP itself (Studio 37.0) exits `0xC0000005` or 1 in about a third
of sessions after a correct shutdown/exit, with or without a config; that was
the "access violation at shutdown" seen in the proxy, and it is not drag-lint's.

If DelphiLSP dies BEFORE a `shutdown` (it crashed, or something killed it), the
proxy still exits with DelphiLSP's code and now also writes one stderr line:
`drag-lint lsp --proxy: DelphiLSP exited with code 0x... before the client's
shutdown request (it crashed or was killed)`. Code `0xFFFFFFFF` (VS Code shows
`4294967295`) means DelphiLSP was terminated from outside: on 2026-11-21 the
proxy tests killed every DelphiLSP on the machine, including the one under VS
Code. Those tests now kill only DelphiLSP processes they started themselves
(`tests\autotest\run_v1523_PROXY_child_killed.ps1`).

## VS Code switch

`drag-lint-switch.exe` switches VS Code's Delphi MCP entry off and on
(`drag-lint-switch --vscode --off` / `--on`), keeping a whole-file backup of the `mcp.json` it edits. See the end of
[lsp](lsp.md).

## Verification

The proxy merge and the extensions are covered by fixture guards that drive the
built engine over stdio with a stub DelphiLSP; each names a positive control so
that a silent run cannot pass with the feature off. Run the targeted set with
`tests\autotest\run_lsp_*_guard.ps1`.
