# vscode-extension

The **drag-lint VS Code extension** (`editors\vscode\drag-lint`) runs `drag-lint lsp` as the
language server for Pascal files: hover, go-to-definition, references, completion, signature
help and lint diagnostics in the Problems panel.

## Commands

Open the Command Palette (Ctrl+Shift+P) and type `drag-lint`.

| Command | Use it when |
|---|---|
| `drag-lint: Refresh Problems` (`dragLint.refreshProblems`) | Problems look stale. Re-lints, from disk, every file that currently shows a drag-lint problem. No restart, no reload. First thing to try. |
| `drag-lint: Restart Language Server` (`dragLint.restartServer`) | Refresh did not help, the server crashed or latched into a failed state, or you changed `dragLint.serverPath` / `dragLint.databases`. Restarts the client and its engine process. |
| `drag-lint: Update Engine Copy Now` (`dragLint.updateEngine`) | You rebuilt or redeployed the engine and want the extension's private engine copy refreshed now instead of on the next window start. |
| `drag-lint: Apply RAD Studio Colours (Pascal only)` (`dragLint.applyRadStudioColours`) | You want Pascal files coloured like your RAD Studio editor. Instant, leaves other languages alone. |
| `drag-lint: Generate Theme From RAD Studio Colours` (`dragLint.generateTheme`) | You changed your RAD Studio colour scheme and want the **Delphi IDE (drag-lint)** theme rebuilt. VS Code reads a theme once, so it offers a window reload. |
| `drag-lint: Select Platform` / `Select Project` (`dragLint.selectPlatform`, `dragLint.selectProject`) | You want a different platform or project index to answer lookups. Also reachable from the status-bar context item. |

## Problems follow files edited on disk

The extension watches `**/*.{pas,dpr,dpk,inc,dfm}` (VS Code uses OS change notifications) and
sends `workspace/didChangeWatchedFiles` to the server. For a `.pas`, `.dpr` or `.dpk` file that
is **not open** in an editor, the server re-lints it from disk and publishes the result; a
deleted file gets an empty diagnostics array. A file that **is open** is left alone: the editor
buffer is authoritative, and VS Code sends `didChange` when it reloads the buffer.

* Bursts are bounded: duplicates inside one message are dropped and at most 64 files are
  re-linted per message.
* Nothing here reindexes the project. Lint findings follow the file at once; index-backed answers
  (hover, find-references) follow the next reindex.
* `drag-lint: Refresh Problems` uses the custom notification `draglint/refreshDiagnostics`,
  which also refreshes open documents (using the live buffer).

## Auto uses on save

VS Code runs `editor.codeActionsOnSave` on every save. The extension ships a default for
Pascal files, so the uses clause adds what is missing without a click:

| Code action kind | Default | What it does |
|---|---|---|
| `source.addMissingImports` | on (`"explicit"`) | adds the unit that declares an undeclared name, but only when exactly one unit declares it. An ambiguous name (two or more units) is never applied silently; it stays a light-bulb quick fix. |
| `source.removeUnusedImports` | **off** | removes a dead `uses` entry (`unused-unit-in-uses`). Enable it in your settings: `"[pascal]": { "editor.codeActionsOnSave": { "source.removeUnusedImports": "explicit" } }` |

**Removal is gated.** VS Code runs the save actions before the file reaches disk and before the
index rescans it, so an ungated removal could delete the unit the code you just typed needs.
The action is offered only when the buffer is identical to what the index last read AND the
whole index is fresh. In practice a removal lands on the first save after the index has caught
up with the buffer; a stale index, or an `{$IFDEF}` (any `{$` directive) inside the uses
clause, suppresses it. The light-bulb quick fix stays available in every case.

**Never reported or removed:** a unit with an `initialization` or `finalization` section, a unit
declaring a `class constructor` or `class destructor`, and a unit instantiated by the form's
`.dfm` -- they are linked for their side effect.

**No while-typing mode.** Half-typed names resolve to the wrong unit or none, and the index is
never fresh mid-keystroke. The light bulb already works while typing.
## Problems look stale

1. Run **drag-lint: Refresh Problems**.
2. Still wrong, or the server looks dead: **drag-lint: Restart Language Server**.
3. Avoid **Developer: Reload Window** when Claude Code sessions run in that window: the reload
   ends them. Refresh Problems and Restart Language Server do not touch other extensions.

Guard: `tests\autotest\run_lsp_watch_pascal_guard.ps1` (drives the LSP over stdio: Changed on a
closed file with a finding publishes it, rewritten clean publishes an empty array, an open file
and a non-source file publish nothing). Related guards: `run_lsp_clear_diags_guard.ps1`,
`run_vscode_extension_contract.ps1`.
