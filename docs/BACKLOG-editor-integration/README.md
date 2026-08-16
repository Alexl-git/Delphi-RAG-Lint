# Editor integration -- one programme, six inbound notes, now UNBLOCKED

Moved out of `docs\INBOX-*` on 2026-08-16 (session 21). **Not defects and not
done** -- so neither the defect INBOX nor `INBOX-Done\` was the right home. The
INBOX is meant to drive fixing, and six feature notes sitting in it inflated a
count that is supposed to mean "known-wrong output".

Nothing here is closed. The notes are unchanged; only their location is.

## Why they belong together

Four different senders described parts of the same programme:

| note | from | what it adds |
|---|---|---|
| `draglint-lsp-proxy-and-editor-integration` | IDE/editor workstream, 2026-08-09 | The LSP proxy goal, and what was already done |
| `editor-integration-and-delphilsp-union` | converter-editor, 2026-08-05 | DelphiLSP union design |
| `editor-native-extensions-and-build-orchestration` | converter-editor, 2026-08-05 | Native extensions + build orchestration |
| `graph-viewer-open-source-pipe-contract` | Delphi-RAG-Lint-Graph viewer | Open-in-IDE pipe contract (the one genuinely separate strand -- it is a protocol question, not an editor host) |
| `QUEUED-editor-integration-vscode-zed-delphilsp` | owner, 2026-08-10 | *"NOT YET READ. Do not action this yet."* |
| `vscode-allow-codeaction-and-lsp-marker-filtering` | 2026-08-12 | Owner ruling: **distant future** |

## What changed today, and why it matters more than the designs

**The VS Code language client had never once completed a start.** Every design in
this folder assumed a working client to build on. `ParseArgs` rejected the
`--stdio` flag that `vscode-languageclient` appends from its own `transport:`
declaration, so the server died during argument parsing, before the `lsp`
command was dispatched -- since the extension landed on 2026-08-11. Fixed in
`8d911f9`; `--clientProcessId` is accepted too.

So the cheapest next step is not a design decision: **start the client and see
what actually works** before committing to the proxy or union architecture. The
notes were written without that evidence being obtainable.

`--node-ipc`, `--pipe` and `--socket` remain deliberately rejected -- this server
speaks only stdio, and silently ignoring a transport it will not honour would
hang a client rather than fail it.

## Reading order

1. `QUEUED-...` first -- it is the owner's own framing, and was never read.
2. `draglint-lsp-proxy-...` for the goal.
3. The two converter-editor notes for design detail.
4. `graph-viewer-...` separately; it is a protocol contract, not an editor host.
5. `vscode-allow-codeaction-...` last -- explicitly distant future.
