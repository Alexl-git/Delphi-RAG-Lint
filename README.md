# drag-lint

[![Release](https://img.shields.io/github/v/release/Alexl-git/Delphi-RAG-Lint?include_prereleases)](https://github.com/Alexl-git/Delphi-RAG-Lint/releases)
[![License](https://img.shields.io/github/license/Alexl-git/Delphi-RAG-Lint)](LICENSE)

A symbol-aware retrieval + lint + refactoring + IDE-integration tool for Delphi.
Pure Object Pascal at runtime -- no Python, Node, or Rust. No cloud AI.

**Use it as:** CLI tool &middot; LSP server (Zed / VS Code) &middot; MCP server (Claude / Cursor) &middot; RAD Studio 13 plugin.

Built on [`tree-sitter-delphi13`](https://github.com/Alexl-git/tree-sitter-delphi13)
(sibling project) and a vendored Pascal binding for libtree-sitter.

---

## Quick start

### Standalone CLI

1. Download the [latest release](https://github.com/Alexl-git/Delphi-RAG-Lint/releases)
   (`drag-lint.exe` + `tree-sitter*.dll`).
2. Put them in the same directory.
3. Index a Delphi project:
   ```
   drag-lint index C:\Projects\MyApp --db myapp.sqlite
   ```
4. Query symbols:
   ```
   drag-lint query --name TFoo --db myapp.sqlite
   drag-lint surface --qname Unit.TFoo --db myapp.sqlite
   drag-lint impact --qname Unit.TFoo.DoBar --db myapp.sqlite
   ```

### LSP server (Zed / VS Code)

Point your editor's LSP config at `drag-lint.exe lsp --db <path>.sqlite`.
The server speaks JSON-RPC over stdio.

Capabilities: hover, definition, references, completion, signatureHelp,
diagnostics (publishDiagnostics on didSave), workspaceSymbols.

### MCP server (Claude / Cursor)

Add to your MCP config (e.g. `~/.claude/claude_desktop_config.json`):

```json
{
  "drag-lint": {
    "command": "drag-lint.exe",
    "args": ["serve", "--db", "C:\\Projects\\MyApp\\.drag-lint.sqlite"]
  }
}
```

14+ tools are then available to Claude: `find_symbol`, `find_callers`,
`get_symbol_doc`, `get_context_bundle`, `rename_symbol`, `run_compile_check`,
and more (see [MCP tools](#mcp-tools-14) below).

### RAD Studio 13 plugin

1. Build the BPL:
   ```
   msbuild src/delphi-plugin/dclDragLintWizard.dproj /p:Platform=Win64 /p:Config=Debug
   ```
   Or download `dclDragLintWizard.bpl` from the latest GitHub release.
2. In RAD Studio: **Component > Install Packages > Add** -- browse to the BPL.
3. Restart RAD Studio.
4. The **Tools > drag-lint** menu now has 12+ entries.

---

## Features

### CLI (~25 commands)

| Command | Description |
|---------|-------------|
| `index <path>` | Parse and index a Delphi project into SQLite |
| `query --name <name>` | Find symbols by name (fuzzy) |
| `surface --qname <qname>` | Show the full source surface of a symbol |
| `slice --qname <qname>` | Extract the call-slice reachable from a symbol |
| `impact --qname <qname>` | Show everything that would be affected by changing a symbol |
| `hover --file <f> --line <n> --col <c>` | Hover info at a source position |
| `rename --qname <q> --new-name <n>` | Preview or apply a symbol rename |
| `generate-docs --qname <q>` | Generate an XML doc-comment stub |
| `generate-test --qname <q>` | Generate a test-method stub |
| `find-deadcode` | List symbols with no callers outside their own unit |
| `compile-check <dproj>` | Run msbuild and store diagnostics in the DB |
| `import-log <log>` | Import a saved msbuild log into the DB |
| `format <file>` | Format a .pas file with the YADF formatter |
| `check-ast <file>` | Run tree-sitter lint rules without compiling |
| `lint <file>` | Run all built-in + external .scm rules |
| `find-callers --name <n>` | List every call-site for a symbol |
| `workspace index` | Index all projects in a workspace config |
| `workspace status` | Show per-project file counts |
| `workspace add <dproj>` | Add a project to the workspace config |
| `context --qname <q>` | Emit a compact context bundle for AI prompts |
| `bench-context <dir>` | Benchmark context bundle throughput |
| `lsp [--db <db>]` | Start the LSP server (stdio) |
| `serve [--db <db>]` | Start the MCP server (stdio) |
| `--version` | Print version |
| `--help` | Print help |

### MCP tools (14+)

| Tool | Description |
|------|-------------|
| `find_symbol` | Search the index by name |
| `find_callers` | List all call-sites for a symbol |
| `get_symbol_doc` | Retrieve the doc-comment for a symbol |
| `get_context_bundle` | Compact context bundle for AI consumers |
| `rename_symbol` | Preview or apply a symbol rename |
| `run_compile_check` | Trigger msbuild and return diagnostics |
| `import_log` | Import a saved build log |
| `run_ast_checks` | Run AST lint rules on a file |
| `format_file` | Format a source file with YADF |
| `get_surface` | Full source surface of a symbol |
| `get_impact` | Call-impact set for a symbol |
| `get_slice` | Reachable call-slice |
| `workspace_status` | Workspace project/file summary |
| `workspace_index` | Re-index all workspace projects |

### Lint rule pack (~13 built-in rules)

| Rule id | Severity | Description |
|---------|----------|-------------|
| `writeln-in-source` | info | Direct `WriteLn` -- use a logger |
| `goto-statement` | warning | `goto` considered harmful |
| `with-statement` | info | `with` makes scope ambiguous |
| `nested-with` | warning | Nested `with` -- scope ambiguity compounds |
| `empty-procedure-body` | info | Empty `begin..end` block |
| `large-magic-number` | info | Unaliased numeric literal |
| `case-magic-numbers` | info | Integer literal as `case` label |
| `string-equality-comparison` | info | `=` comparison on string expressions |
| `parser-error` | error | Tree-sitter `ERROR` node (malformed syntax) |
| `compiler-magic-comments` | info | TODO/FIXME/HACK/XXX in a comment |
| `assert-call` | info | `Assert()` -- ensure descriptive second argument |
| `boolean-comparison-true` | info | `X = True` or `X = False` -- redundant |
| `redundant-as-tobject` | info | `(X as TObject)` -- every object is already TObject |
| `inherited-bare` | info | Bare `inherited;` -- verify it calls the right ancestor |

Drop custom `.scm` + `.json` pairs in the `rules/` directory; see
[rules/README.md](rules/README.md) for the schema.

### RAD Studio plugin

**Tools menu** (12 entries): Hover at Cursor, Show Completion, Show Signature
Help, Run Diagnostics, Rename Symbol, Compile & Diagnose, Import Build Log,
Format with YADF, Show Structure, Run AST Checks, Find Usages, Symbol Search,
Settings.

**Keystroke bindings** (registered via `IOTAKeyBindingServices`):

| Shortcut | Action |
|----------|--------|
| Ctrl+Alt+H | Hover at Cursor |
| Ctrl+Alt+C | Show Completion |
| Ctrl+Alt+S | Show Signature Help |
| Ctrl+Alt+D | Run Diagnostics |
| Ctrl+Alt+I | In-editor diagnostic hint popup |
| Ctrl+Alt+R | Rename Symbol |
| Ctrl+Alt+F | Find Usages |
| Ctrl+Alt+T | Symbol Search |

**In-editor diagnostics**: gutter dot markers + wavy underlines via
`IOTAEditViewNotifier.BeforeDrawLine`. Severity colours from the IDE colour
scheme registry.

**Hover tooltip** (v0.35): a 200ms timer shows `Application.HintWindow` with
the diagnostic message when the cursor is stable for 600ms over a row that has
a diagnostic. Caret-based (not pixel-precise). Toggle via Settings.

**Code lens** (v0.32): dim grey `[N callers]` text next to method declarations.

**Structure form** (v0.30): floating `fsStayOnTop` form showing the symbol
tree of the active file, updated on view activation.

**Find Usages form** (v0.33): `Ctrl+Alt+F` prompts for a symbol name; shows
callers grouped by file in a TTreeView; double-click jumps the editor.

**Symbol Search form** (v0.33): `Ctrl+Alt+T` debounced live search over the
indexed symbol table; Enter navigates the editor to the selected location.

**Native Tools > Options page** (v0.30): all settings via `INTAAddInOptions`.

---

## Architecture

```
drag-lint.exe
  |
  +-- CLI dispatch (DRagLint.CLI)
  |     |
  |     +-- Indexer (DRagLint.Core.Indexer)
  |     |     +-- tree-sitter-delphi13.dll  (Delphi 13 grammar)
  |     |     +-- tree-sitter-dfm.dll        (DFM grammar)
  |     |     +-- tree-sitter.dll            (libtree-sitter runtime)
  |     |     +-- SQLite storage
  |     |
  |     +-- Query / Surface / Impact / Slice
  |     +-- Lint (rule runner over .scm files)
  |     +-- Refactor (rename, doc stubs, test stubs, YADF format)
  |     +-- Compiler diagnostics (msbuild integration)
  |     +-- Workspace (multi-project shared DB)
  |
  +-- LSP server (DRagLint.LSP.Server) -- stdio JSON-RPC
  |
  +-- MCP server (DRagLint.MCP.Server) -- stdio JSON-RPC
  |
  +-- CLI context bundler (DRagLint.Context.Bundler)

dclDragLintWizard.bpl  (Delphi IDE plugin)
  +-- Wizard / menu / keystrokes / EditViewNotifier
  +-- LSP client -> drag-lint.exe lsp
  +-- DiagnosticCache -> in-editor markers + hover tooltip
  +-- CodeLensCache -> inline [N callers]
  +-- Structure / Refactor / Usages / SymbolSearch forms
  +-- Options (INTAAddInOptions)
```

All three entry-points (CLI, LSP, MCP) call the same indexer, query, lint,
and refactor engine. The IDE plugin is a thin wrapper around the LSP client
plus direct CLI calls for features the LSP protocol doesn't cover.

---

## Building from source

Prerequisites:
- RAD Studio 13 Florence (37.0) with Win64 target
- `tree-sitter-delphi13` DLLs in `third_party/dll/`

Build the CLI:
```
call "C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\rsvars.bat"
msbuild drag-lint.dproj /p:Config=Release /p:Platform=Win64
```

Build the IDE plugin:
```
msbuild src/delphi-plugin/dclDragLintWizard.dproj /p:Config=Debug /p:Platform=Win64
```

Run the test suite (batch files in `tests/fixtures/`):
```
tests\fixtures\T61_hovertracker.bat
tests\fixtures\T62_lint_rules_v035.bat
tests\fixtures\T56_lint_rules_v032.bat
:: ... etc.
```

---

## Version history

See [CHANGELOG.md](CHANGELOG.md) for the full v0.16 to v0.35 history
(20 versions, released 2026-05-28 through 2026-05-29).

---

## License

MIT. See [LICENSE](LICENSE).
