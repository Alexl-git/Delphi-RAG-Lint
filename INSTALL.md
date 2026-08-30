# drag-lint -- Installation & Linter Quick Start

`drag-lint` is a self-contained command-line tool (plus an optional RAD Studio
IDE plugin). This guide covers the **CLI** from the release archive.

## 1. Install (CLI)

1. Download the archive for your platform: `drag-lint-vX.Y.Z-win64.zip`
   (recommended) or `...-win32.zip`.
2. **Unzip the whole folder, keeping every file together.** The archive contains:

   ```
   drag-lint.exe                 the tool
   tree-sitter-delphi13.dll      } parser DLLs -- must sit next to the exe
   tree-sitter-dfm.dll           }
   tree-sitter.dll               }
   rules\                        external lint rules (*.scm + *.json)  <-- REQUIRED for linting
     builtin-symbols.txt
   README.md  CHANGELOG.md  LICENSE  INSTALL.md
   docs\AI-USAGE.md
   ```

3. (Optional) add the folder to your `PATH`, or call `drag-lint.exe` by full path.

> **Important for the linter:** the `.scm` lint rules load from a `rules\` folder
> **next to `drag-lint.exe`**. Keep `rules\` beside the exe (the archive already
> places it there). If you move the exe, move `rules\` with it, or pass
> `--rules-dir <path>`. If no rules load, `drag-lint lint` prints a one-line note
> to stderr (the built-in checks still run).

## 2. Build an index (for query/navigation features)

```
drag-lint index C:\path\to\your\project --db myapp.sqlite
drag-lint query --name TMyClass --db myapp.sqlite
drag-lint query find-callers --name DoStuff --db myapp.sqlite
```

(The linter below does **not** require an index -- it works straight on a `.pas` file.)

## 3. Lint a unit

```
drag-lint lint C:\path\to\MyUnit.pas
```

Text output is `file:line:col [severity] rule-id: message`; add `--json` for tooling:

```
drag-lint lint MyUnit.pas --json
```

Useful options:

| Option | Meaning |
|---|---|
| `--json` | machine-readable findings (`rule`, `severity`, `file_path`, `start_line`, ...) |
| `--rule <id>` | run only one built-in rule (e.g. `--rule code-after-exit`) |
| `--rules-dir <dir>` | load external `.scm` rules from `<dir>` instead of `<exe-dir>\rules` |
| `--project <file.dproj>` | also run project-level checks (e.g. `unit-not-in-dpr`) |

Exit code is `1` when any findings are reported, `0` when clean.

### Suppressing a finding

Add a line comment on the offending source line:

```pascal
SomeQuery.SQL.Text := 'SELECT * FROM t WHERE id=' + Id;  // drag-lint:ignore sql-injection-concat
X := X;  // drag-lint:ignore           <-- suppress ALL rules on this line
```

`// drag-lint:ignore` (alone) silences every rule on that line; followed by one
or more rule ids it silences only those. Applies to both `.scm` and built-in rules.

## 4. What it checks

This release ships **177 rules** (151 enabled by default, 22 with an auto-fix)
across 16 categories: exceptions, control-flow
/ dead code, expression bugs, resource/lifetime, naming, and security (SQL
injection, hardcoded credentials). Run `drag-lint rules` for the full,
always-current catalog. The list with one-line descriptions is also in
[`rules\README.md`](rules/README.md); the design rationale and the wider Delphi
lint landscape are in [`docs\lint\`](docs/lint/) (REPORT-1 / REPORT-2).

External rules (the `*.scm` files in `rules\`) are plain text -- you can add your
own; see `rules\README.md` for the format.

## 5. IDE plugin (optional)

The RAD Studio plugin (`dclDragLintWizard.bpl`) surfaces these diagnostics live
in the editor. It spawns `drag-lint.exe`; make sure that exe has its `rules\`
folder beside it (or is launched with `--rules-dir`).

## 6. VS Code, Zed and other editors (optional)

drag-lint ships a stdio language server -- `drag-lint lsp` -- giving hover,
go-to-definition, **find-references**, **workspace symbols**, completion and
signature help from the index, across every project in your manifest at once.
(DelphiLSP implements neither find-references nor workspace symbols, so those
two are not duplicated features.)

* **VS Code** -- an extension is included; install it from
  `editors\vscode\drag-lint\`.
* **Zed** -- highlighting works today via the tree-sitter grammars; registering
  the language server needs a small Rust/WASM extension that is **not yet
  built**. It is fully specified so anyone with `rustup` can finish it.
* **Neovim / Helix / anything else** -- point it at `drag-lint lsp` over stdio.

Full instructions, settings and the Rust extension specification:
[docs/EDITORS.md](docs/EDITORS.md).

---

drag-lint is **alpha** -- expect rough edges and breaking changes.
Issues & feedback: https://github.com/Alexl-git/Delphi-RAG-Lint/issues
