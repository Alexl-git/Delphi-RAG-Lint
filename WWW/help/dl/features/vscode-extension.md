---
id: vscode-extension
title: "VS Code extension: Problems stay current"
summary: VS Code extension commands, and Problems that follow files an agent edits on disk
product: DL
group: editor-integration
order: 110022
since: 1.38.0-alpha
status: shipped
updated: 1.38.0-alpha
---

# VS Code extension: Problems stay current

VS Code extension commands, and Problems that follow files an agent edits on disk.

Read this when the VS Code Problems panel looks stale or you want to know what each drag-lint command does. Pascal edits made on disk now re-lint on their own.

## Details

The **drag-lint VS Code extension** (`editors\vscode\drag-lint`) runs `drag-lint lsp` as the
language server for Pascal files: hover, go-to-definition, references, completion, signature
help and lint diagnostics in the Problems panel.

### Commands

Open the Command Palette (Ctrl+Shift+P) and type `drag-lint`.

| Command | Use it when |
|---|---|
| `drag-lint: Refresh Problems` (`dragLint.refreshProblems`) | Problems look stale. Re-lints, from disk, every file that currently shows a drag-lint problem. No restart, no reload. First thing to try. |
| `drag-lint: Restart Language Server` (`dragLint.restartServer`) | Refresh did not help, the server crashed or latched into a failed state, or you changed `dragLint.serverPath` / `dragLint.databases`. Restarts the client and its engine process. |
| `drag-lint: Update Engine Copy Now` (`dragLint.updateEngine`) | You rebuilt or redeployed the engine and want the extension's private engine copy refreshed now instead of on the next window start. |
| `drag-lint: Apply RAD Studio Colours (Pascal only)` (`dragLint.applyRadStudioColours`) | You want Pascal files coloured like your RAD Studio editor. Instant, leaves other languages alone. |
| `drag-lint: Generate Theme From RAD Studio Colours` (`dragLint.generateTheme`) | You changed your RAD Studio colour scheme and want the **Delphi IDE (drag-lint)** theme rebuilt. VS Code reads a theme once, so it offers a window reload. |
| `drag-lint: Select Platform` / `Select Project` (`dragLint.selectPlatform`, `dragLint.selectProject`) | You want a different platform or project index to answer lookups. Also reachable from the status-bar context item. |

### Problems follow files edited on disk

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

### Problems look stale

1. Run **drag-lint: Refresh Problems**.
2. Still wrong, or the server looks dead: **drag-lint: Restart Language Server**.
3. Avoid **Developer: Reload Window** when Claude Code sessions run in that window: the reload
   ends them. Refresh Problems and Restart Language Server do not touch other extensions.

Guard: `tests\autotest\run_lsp_watch_pascal_guard.ps1` (drives the LSP over stdio: Changed on a
closed file with a finding publishes it, rewritten clean publishes an empty array, an open file
and a non-source file publish nothing). Related guards: `run_lsp_clear_diags_guard.ps1`,
`run_vscode_extension_contract.ps1`.

---

[All features](../index.md) | [CLI reference](../cli.md) | [IDE menus](../ide.md)
