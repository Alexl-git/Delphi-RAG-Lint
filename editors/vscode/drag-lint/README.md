# drag-lint (Delphi) for VS Code

Delphi / Object Pascal language features in VS Code, backed by the
[drag-lint](https://github.com/) AST index rather than by text search: hover,
go-to-definition, find-references, workspace symbols, completion and signature
help.

The extension is a thin client. All of the intelligence lives in the drag-lint
engine (`drag-lint.exe`), which speaks LSP and answers from the same SQLite
indexes the CLI and the Delphi IDE plugin use.

## Requirements

A built drag-lint engine on the machine. By default the extension mirrors from:

```
C:\Projects\Delphi-RAG-lint\third_party\dll-win64\drag-lint.exe
```

Databases are auto-selected from the `drag-lint.json` manifest beside that exe,
so the extension follows whatever the manifest currently says -- including
per-project `_D-RAG` indexes -- with no configuration.

## Why the extension runs a private COPY of the engine

A running language server holds an execute lock on its own image. When VS Code
ran the deployed engine directly, a live VS Code session made
`build_draglint_win64.bat` fail to stage a fresh build -- the engine could not
be overwritten while the editor was open.

So the extension copies the engine to its own storage and runs the copy. The
Delphi IDE keeps the deployed binary; VS Code deliberately sits a few builds
behind, and rebuilds are never blocked.

The copy is refreshed only when the extension activates (VS Code start, window
reload, or the first Pascal file opened) -- never mid-session. **After an engine
rebuild, the copy is stale until you reload the window** or run
**drag-lint: Update Engine Copy Now**.

## Commands

| Command | What it does |
|---|---|
| `drag-lint: Restart Language Server` | Restarts the LSP client and its engine process |
| `drag-lint: Update Engine Copy Now` | Refreshes the private engine copy immediately |
| `drag-lint: Apply RAD Studio Colours (Pascal only)` | Reads your RAD Studio editor scheme and applies it to Pascal files via `editor.tokenColorCustomizations`. Instant, no reload, leaves other languages alone |
| `drag-lint: Generate Theme From RAD Studio Colours` | Rebuilds the **Delphi IDE (drag-lint)** theme from your current IDE scheme (offers a window reload) |

## Settings

| Setting | Default | Meaning |
|---|---|---|
| `dragLint.engineSource` | the deployed `drag-lint.exe` | The binary the private copy MIRRORS FROM |
| `dragLint.engineUpdate` | `onActivate` | When the copy is refreshed: `onActivate`, `manual`, or `off` |
| `dragLint.serverPath` | *(empty)* | Absolute path to an exe to run AS-IS; disables the copy |
| `dragLint.databases` | *(empty)* | Explicit `--db` paths; empty means auto-select from the manifest |
| `dragLint.colors.bdsVersion` | `auto` | Which RAD Studio install the colour commands read, e.g. `37.0`; `auto` picks the newest |
| `dragLint.trace.server` | `off` | Log the LSP conversation to the `drag-lint` output channel |

Setting `dragLint.engineUpdate` to `off`, or pointing `dragLint.serverPath` at
the deployed path, restores the pre-1.4 behaviour -- VS Code and the Delphi IDE
then always run the identical file, and a live VS Code session blocks engine
rebuilds again.

## Syntax colouring

Since **v1.5** the extension ships a Pascal TextMate grammar. Before it, nothing
coloured Pascal in VS Code: this extension contributed no grammar, VS Code has no
built-in Pascal grammar, and the `begin`/`end` colours you may have seen were
bracket-pair colourization, not highlighting.

It also ships the theme **Delphi IDE (drag-lint)** (`Ctrl+K Ctrl+T`), which is
GENERATED from `HKCU\Software\Embarcadero\BDS\<ver>\Editor\Highlight` -- your
own IDE scheme, so the match is literal rather than approximate. Prefer to keep
your VS Code theme? Run **drag-lint: Apply RAD Studio Colours (Pascal only)**
instead: it recolours Pascal files only and applies with no reload.

For pure IDE fidelity also set `"editor.bracketPairColorization.enabled": false`
-- it overrides theme colours on `begin`/`end` and brackets.

A TextMate grammar is a regex cascade, so it disagrees with drag-lint's own
tree-sitter parse in the corners (generics vs comparison, nested `{$IFDEF}`,
`asm` bodies). `textDocument/semanticTokens` fed by the real parse is the fix,
and VS Code layers it OVER a grammar -- a complement, not a replacement.

Do not also install a third-party Pascal extension: a second one declaring
`source.pascal` conflicts with this grammar.
## Packaging

From this directory:

```
npm install
npm run package
```

The `.vsix` is written to `dist\` at the repository root. Install it with:

```
code --install-extension <path to the .vsix>
```

## License

MIT -- see `LICENSE`.
