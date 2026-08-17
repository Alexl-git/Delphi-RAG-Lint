# Installation

drag-lint has three faces, and they install independently. Most people want the
first two.

1. **CLI** -- the engine. Everything else spawns it.
2. **RAD Studio plugin** -- the `drag-lint` menu, hover, dockable panels.
3. **Language server** -- for VS Code, Neovim, Helix, Zed.

---

## 1. CLI

1. Download `drag-lint-vX.Y.Z-win64.zip` from
   [Releases](https://github.com/Alexl-git/Delphi-RAG-Lint/releases). Win64 is
   the supported target; a Win32 build exists but is a frozen fallback.
2. **Unzip the whole folder and keep every file together:**

   ```
   drag-lint.exe                 the tool
   tree-sitter-delphi13.dll      } parser DLLs -- MUST sit next to the exe
   tree-sitter-dfm.dll           }
   tree-sitter.dll               }
   rules\                        external lint rules (*.scm + *.json)
     builtin-symbols.txt
   ```

3. Optionally add the folder to `PATH`, or call the exe by full path.

### Two things that break a fresh install

**`rules\` must sit beside the exe.** The `.scm` rules load from
`<exe-dir>\rules`. Move the exe without the folder and the external rules
silently stop loading -- the built-in checks still run, so you get *fewer*
findings rather than an error. Use `--rules-dir <path>` if you must separate
them.

**The tree-sitter DLLs must be the matching bitness.** A Win64 exe that finds
Win32 parser DLLs on `PATH` dies at process start with `0xC000007B`
(`STATUS_INVALID_IMAGE_FORMAT`). That is a bitness mismatch, not a missing DLL
(`0xC0000135`), which is why it does not look like a staging problem.

### Verify

```
.\drag-lint.exe --version
.\drag-lint.exe rules            # the full, always-current rule catalogue
```

---

## 2. Build your first index

The linter works on a bare `.pas` file, but navigation, callers, impact analysis
and documentation all need an index.

```
.\drag-lint.exe index C:\path\to\project --db myapp.sqlite
.\drag-lint.exe query --name TMyClass --db myapp.sqlite
```

For real use, prefer the **manifest** so commands find databases themselves --
see [Maintenance](Maintenance#the-manifest).

---

## 3. RAD Studio plugin

The plugin is a design-time package, `dclDragLintWizard.bpl`. It adds a top-level
**`drag-lint`** menu to the IDE menu bar (falling back to *Tools* if the main
menu is unavailable) and two dockable windows under *View > Tool Windows*.

### Install

1. Close all RAD Studio instances. A design-time BPL cannot be replaced while
   the IDE holds it.
2. Copy the BPL and the CLI (with its DLLs and `rules\`) to a folder of your
   choice.
3. In RAD Studio: **Component > Install Packages > Add...**, select
   `dclDragLintWizard.bpl`.
4. Restart the IDE. A `drag-lint` item appears in the menu bar.

### It needs the CLI

The plugin does not contain the engine -- it **spawns `drag-lint.exe`**. If the
menu items fail, check that the exe is reachable and still has `rules\` beside
it. `drag-lint > Open Plugin Log` shows what the plugin actually invoked.

### Bitness

The IDE is 32-bit, but the plugin spawns the **Win64** CLI by default: the 64-bit
engine handles large indexes that the 32-bit one cannot (it runs out of address
space on multi-gigabyte databases). The BPL is the only 32-bit artifact.

---

## 4. Editors (LSP)

drag-lint ships a stdio language server:

```
drag-lint lsp
```

It provides hover, go-to-definition, **find-references**, **workspace symbols**,
completion and signature help from the index -- across every project in the
manifest at once. Find-references and workspace-symbols are not duplicated by
DelphiLSP, which does not implement them.

* **VS Code** -- extension included at `editors\vscode\drag-lint\`.
* **Neovim / Helix / anything else** -- point the client at `drag-lint lsp` over
  stdio.
* **Zed** -- syntax highlighting works today via the tree-sitter grammars;
  registering the language server needs a small Rust/WASM extension that is
  specified but **not built**.

Full settings and the Rust extension spec: `docs/EDITORS.md` in the repository.

---

## Suppressing a finding

A line comment on the offending line:

```pascal
Q.SQL.Text := 'SELECT * FROM t WHERE id=' + Id;  // drag-lint:ignore sql-injection-concat
X := X;                                          // drag-lint:ignore   <- all rules
```

For a finding a human has *reviewed and accepted*, prefer the reviewed marker,
which is self-invalidating -- it carries a hash of the line's code tokens and
re-reports itself if the code changes:

```pascal
except // dl:ok bare-except@7f3a -- rethrown by the caller
```

Reindentation and case changes do **not** invalidate it; a real edit does.
