# v0.21 — OTAPI IDE Plugin (Slice B2)

**Date:** 2026-05-28
**Status:** Design approved (full LSP wrap, persistent subprocess), ready for plan
**Branch:** `v0.21-otapi-plugin` off `v0.20-lsp-completion`

## 1. Goal — the headline destination

A Delphi 13 IDE plugin (design-time package, .bpl) that wraps drag-lint's LSP
server and surfaces hover, completion, signatureHelp, and diagnostics inside
the RAD Studio editor. The user gets `/// <summary>` doc-aware insight,
symbol completion, signature popups, and lint markers without leaving the
IDE and without any cloud AI in the loop.

## 2. Architecture

```
                +----------------------------+
                |   RAD Studio IDE (37.0)    |
                |                            |
                | +------------------------+ |
                | |  DragLintWizard.bpl    | |
                | |  (design-time package) | |
                | |                        | |
                | |  TDragLintWizard       | |
                | |    (IOTAWizard)        | |
                | |                        | |
                | |  TDragLintLspClient    | |
                | |  - stdin pipe (write)  | |
                | |  - stdout pipe (read)  | |
                | |  - reader thread       | |
                | |  - request-id map      | |
                | |                        | |
                | |  TDragLintEditor       | |
                | |  - IOTAEditViewNotifier|
                | |  - keystroke bindings  | |
                | |                        | |
                | |  TDragLintHoverPopup   | |
                | |  TDragLintCompletion   | |
                | |  TDragLintSignature    | |
                | |  TDragLintDiagnostics  | |
                | +------------------------+ |
                +--------+-------------------+
                         | stdin / stdout pipes
                         v
                +----------------------------+
                |  drag-lint.exe lsp         |
                |  (persistent subprocess)   |
                +----------------------------+
```

## 3. Distribution

New tree `src/delphi-plugin/`:

```
src/delphi-plugin/
  dclDragLintWizard.dpk           — design-time package descriptor
  dclDragLintWizard.dproj         — MSBuild file (Win64, design-time)
  DragLint.Plugin.Wizard.pas      — TDragLintWizard, IOTAWizard, Register
  DragLint.Plugin.LspClient.pas   — TDragLintLspClient (subprocess + IPC)
  DragLint.Plugin.Editor.pas      — IOTAEditViewNotifier; keystroke bindings
  DragLint.Plugin.Hover.pas       — TDragLintHoverPopup (VCL form)
  DragLint.Plugin.Completion.pas  — completion list popup
  DragLint.Plugin.Signature.pas   — signatureHelp popup
  DragLint.Plugin.Diagnostics.pas — Messages-pane integration
  DragLint.Plugin.Settings.pas    — IDE settings: drag-lint.exe path
  README.md                       — install instructions
```

Output `dclDragLintWizard.bpl` lands in `<RAD>/bin64/`.

## 4. Wizard lifecycle

**On IDE startup** (when the package loads):
1. `Register` is called by the IDE.
2. Constructs `TDragLintWizard`, registers it via `RegisterPackageWizard`.
3. The wizard's `Execute` is bound to a menu item under Tools > drag-lint.
4. The wizard ALSO registers an `IOTAEditViewNotifier` that watches all editor
   views for activation, modification, and save events.
5. The wizard spawns `drag-lint.exe lsp` as a persistent subprocess.

**On per-file events:**
- View activated → call `textDocument/didOpen` (idempotent guard against
  duplicate open events).
- Buffer modified → defer until idle (300ms debounce) → no LSP call yet
  (we treat on-disk file as source of truth; updates trigger on save).
- File saved → call `textDocument/didSave` → receive
  `publishDiagnostics` notification → render in Messages pane.

**On keystroke triggers:**
- `Ctrl+Alt+H` — call `textDocument/hover` at cursor; show
  `TDragLintHoverPopup` near caret.
- `Ctrl+Space` (when chord configured) — call
  `textDocument/completion`; show `TDragLintCompletionList`.
- After `(` insertion in editor — call `textDocument/signatureHelp`; show
  `TDragLintSignaturePopup`. Hide on `)` or escape.

**On IDE shutdown:**
- Send `shutdown` request, wait for response (≤2s timeout).
- Send `exit` notification.
- Terminate subprocess if not exited within timeout.
- Free pipes, reader thread, notifiers.

## 5. IPC details

**Pipe creation:** `CreatePipe(hReadIn, hWriteIn, sa, 0)` for stdin (we
write); `CreatePipe(hReadOut, hWriteOut, sa, 0)` for stdout (we read).

**Subprocess:** `CreateProcessW` with `STARTUPINFOW.hStdInput = hReadIn`,
`hStdOutput = hWriteOut`, `dwFlags |= STARTF_USESTDHANDLES`.

**Reader thread:** loops reading 1 byte at a time until `\r\n\r\n` header
terminator; parses `Content-Length: N`; reads N bytes; deserializes JSON;
dispatches by `id` to a waiting `TEvent` keyed in a dictionary.

**Synchronous request API:**
```pascal
function TDragLintLspClient.Request(const AMethod: string;
  AParams: TJSONValue; ATimeoutMs: Integer): TJSONValue;
```
Generates unique `id`, writes the framed JSON, waits on event, returns
result. Returns `nil` on timeout (caller responsible for graceful UX
fallback — empty completion list, no hover, etc.).

**Async notifications:** wizard registers handlers for `publishDiagnostics`
keyed by URI; reader thread invokes them via `TThread.Synchronize`.

## 6. Hover popup (TDragLintHoverPopup)

A borderless `TForm` with a single `TMemo` (or `TRichEdit`) sized to content.
Positioned just below the caret. Rendered from the LSP `Hover.contents.value`
markdown (basic Markdown renderer: headings → bold, code blocks → mono
font, lists → indent). Auto-hides on cursor move, ESC, or click outside.

## 7. Completion popup (TDragLintCompletion)

A borderless `TForm` with a `TListView` sized to N items max. Each item
shows `kind icon` + `label` + truncated `detail`. Arrow keys navigate;
Enter inserts (sends `insertText` into the editor via
`IOTAEditWriter.Insert`); ESC cancels.

## 8. Signature popup (TDragLintSignature)

Smaller, single-line popup. Bold-highlights the active parameter
(`SignatureHelp.activeParameter` index → range in label).

## 9. Diagnostics (Messages pane)

Use `IOTAMessageServices.AddToolMessage` per finding:
- `FileName` = file path
- `LineNumber` / `ColumnNumber` from diagnostic range
- `Group` = "drag-lint"
- `Tool` = rule code
- `Text` = message

Findings clear on each fresh `publishDiagnostics` for the same URI.

## 10. Settings (TDragLintSettings)

IDE config form under Tools > Options > drag-lint:
- `drag-lint.exe path` (text + browse button; default: same dir as the .bpl)
- `Project database path` (.sqlite; default `<projdir>\.drag-lint.sqlite`)
- `Enable hover` / `completion` / `signatureHelp` / `diagnostics` toggles

Stored in registry under `HKCU\Software\drag-lint\DelphiPlugin`.

## 11. Auto-verifiable vs manual-verify

| Component | Auto-verifiable? | How |
|---|---|---|
| .dpk compiles | YES | msbuild |
| LSP client unit standalone | YES | tests/fixtures/T27_lsp_client_standalone.dpr drives it without IDE |
| JSON-RPC framing | YES | unit-style test |
| Hover popup UI | NO | needs IDE |
| Completion popup UI | NO | needs IDE |
| Signature popup UI | NO | needs IDE |
| Diagnostics in Messages pane | NO | needs IDE |
| Wizard registration | NO | needs IDE (.bpl install) |
| End-to-end editor interaction | NO | needs IDE + user |

The plan ships everything; v0.21's acceptance requires user manual
verification after IDE install.

## 12. Stop criteria

1. `dclDragLintWizard.bpl` compiles with no errors.
2. `tests/fixtures/T27_lsp_client_standalone.exe` drives the LSP client
   class against a real drag-lint.exe subprocess: round-trips
   initialize + textDocument/completion + shutdown without hanging.
3. Plugin install README documents the exact steps to load the BPL in
   RAD Studio.
4. v0.16-v0.20 tests still pass.
5. (Manual verify, user to do) Install BPL, hover popup appears via
   Ctrl+Alt+H on an identifier in an indexed Delphi project.

## 13. Out of scope (deferred to v0.22+)

- Pre-built installer (.msi)
- Auto-update mechanism
- Pre-D13 IDE versions (D10/D11/D12)
- BeyondCompare-style diff in the Messages pane
- Refactor-as-you-type (rename, extract method) — these need OTAPI's
  refactoring API which is heavier than hover
- AI-assisted CodeInsight that mixes drag-lint context bundles with a
  separate LLM call
- macOS / Linux RAD Studio support (Win64 only in v0.21)

## 14. Versioning

Branch `v0.21-otapi-plugin` off `v0.20-lsp-completion`. Local tag
`v0.21.0-alpha`. Do not push.
