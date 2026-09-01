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

## Settings

| Setting | Default | Meaning |
|---|---|---|
| `dragLint.engineSource` | the deployed `drag-lint.exe` | The binary the private copy MIRRORS FROM |
| `dragLint.engineUpdate` | `onActivate` | When the copy is refreshed: `onActivate`, `manual`, or `off` |
| `dragLint.serverPath` | *(empty)* | Absolute path to an exe to run AS-IS; disables the copy |
| `dragLint.databases` | *(empty)* | Explicit `--db` paths; empty means auto-select from the manifest |
| `dragLint.trace.server` | `off` | Log the LSP conversation to the `drag-lint` output channel |

Setting `dragLint.engineUpdate` to `off`, or pointing `dragLint.serverPath` at
the deployed path, restores the pre-1.4 behaviour -- VS Code and the Delphi IDE
then always run the identical file, and a live VS Code session blocks engine
rebuilds again.

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
