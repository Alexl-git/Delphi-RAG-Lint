# drag-lint

[![Release](https://img.shields.io/github/v/release/Alexl-git/Delphi-RAG-Lint?include_prereleases)](https://github.com/Alexl-git/Delphi-RAG-Lint/releases)
[![License](https://img.shields.io/github/license/Alexl-git/Delphi-RAG-Lint)](LICENSE)

> **⚠️ Alpha / work in progress.** This is an early alpha under active, daily
> development — expect rough edges, unfinished corners, and breaking changes
> between versions. It is shared early so the Delphi community can try it and
> shape it. **Feedback and suggestions are very welcome** — please open an
> [Issue](https://github.com/Alexl-git/Delphi-RAG-Lint/issues) with ideas, bugs,
> or "I wish it could…". Not yet recommended for unattended/production use.

A symbol-aware retrieval + lint + refactoring + IDE-integration tool for Delphi.
Pure Object Pascal at runtime -- no Python, Node, or Rust. No cloud AI.

**Use it as:** CLI tool &middot; LSP server (Zed / VS Code) &middot; MCP server (Claude / Cursor) &middot; RAD Studio 13 plugin.

**→ Driving it from an AI agent? See [docs/AI-USAGE.md](docs/AI-USAGE.md)** — copy-paste instructions so your AI uses drag-lint over CLI or MCP (and reads ~10-60x fewer tokens than opening whole units).

Built on [`tree-sitter-delphi13`](https://github.com/Alexl-git/tree-sitter-delphi13)
(sibling project) and a vendored Pascal binding for libtree-sitter.

**Companion:** [`Delphi-RAG-Lint-Graph`](https://github.com/Alexl-git/Delphi-RAG-Lint-Graph)
— an experimental standalone VCL viewer that turns this index into an interactive
symbol graph + structure panel, with click-to-jump into RAD Studio.

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

### Indexing the Delphi RTL/VCL libraries

To build one index over everything Delphi itself knows about - the IDE's
**Library** and **Browsing** search paths, read straight from the registry,
deduplicated, with `$(BDS)` / `$(Platform)` macros expanded - use the
`--scan-libraries-*` flags (no project or path needed):

```
drag-lint index --scan-libraries-win --db Library.sqlite   # Win32 + Win64 (default)
drag-lint index --scan-libraries-all --db Library.sqlite   # every registered platform
```

- **`--scan-libraries-win`** covers the IDE's native targets (Win32 + Win64).
  Because the RTL / VCL / FMX `.pas` source is shared across platforms, this
  already captures essentially all library source. (`--scan-libraries` is kept
  as a back-compat alias for this.)
- **`--scan-libraries-all`** enumerates **every** platform subkey under
  `...\BDS\37.0\Library` (Android*, iOS*, Linux64, OSX*, Win64x, ...). On top of
  the Win set it pulls in the platform-specific source trees - `source\rtl\posix`,
  `source\rtl\ios`, `posix\osx` - so symbols like `Posix.*`, `iOSapi.*`,
  `Macapi.*` and `Androidapi.*` resolve too.

Both probe HKCU + HKLM in both the 32- and 64-bit registry views and fold the
results into a single deduplicated folder set. Add `--dry-run` to print the
resolved folder list without indexing.

### Untangling unit dependencies (cycles + uses cleanup)

Find circular unit dependencies and the exact `uses` lines that form them:

```
drag-lint cycles --db myapp.sqlite --edges
```

Each cycle lists its `A uses B [interface|implementation]` edges, marks the
**interface** edges as move-to-implementation candidates, and flags layering
inversions (e.g. a COMMON unit reaching into CLIENT). Add **`--causes`** to
pinpoint the *specific symbols* in `A`'s interface that force the dependency on
`B` (the types/vars/methods to move or extract) — with the line numbers, and an
honest note where the index couldn't resolve a reference.

Or generate a full **followable refactoring playbook** that a junior dev (or a
small model) can execute:

```
drag-lint cycles --db myapp.sqlite --plan > cycle-plan.md
```

Per cycle it gives the files, the load-bearing symbols (use site **and**
declaration site, with line numbers), an auto-classified fix (*extract the shared
contract*, or *invert the dependency* for layering inversions), numbered steps,
and a verify command. Build after each cycle and re-run `cycles` to confirm. Then propose and apply the
cleanup, **verified by the compiler** so it never breaks the build:

```
drag-lint uses-audit MyUnit.pas --db myapp.sqlite                       # propose
drag-lint uses-fix --project MyApp.dproj --db myapp.sqlite              # dry-run sweep report
drag-lint uses-fix MyUnit.pas --project MyApp.dproj --db myapp.sqlite --apply   # apply (.bak backup)
```

> **Caveat (important):** `uses-fix`'s per-unit verify is **best-effort, not a
> faithful full-build check** — a single-unit `dcc` compile can reuse a stale
> `.dcu` (masking a real error) or abort on an RTL dependency. Treat
> `cycles`/`uses-audit` as **advisory** (they pinpoint candidates, and the index
> can miss refs like `set` types), and **always do a full project build** after
> `--apply` (revert from `.bak` if it fails). Reliable bulk cleanup needs
> full-project-build verification, not per-unit compiles.

### Semantic errors without a full build

`check-unit` compiles a single unit in its project's context, so you get real
compiler errors (e.g. `E2003 Undeclared identifier`) fast -- and on the
**unsaved** buffer via a shadow overlay:

```
drag-lint check-unit MyUnit.pas --project MyApp.dproj --platform win64 \
          --db myapp.sqlite --resolve-uses
```

`--resolve-uses` turns an undeclared identifier into a fix: *"add unit X to the
uses clause."*

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
| `index --scan-libraries-win` | Index the IDE's Win32+Win64 Library + Browsing paths (from the registry) |
| `index --scan-libraries-all` | Same, but every registered platform (adds Posix/iOS/Android/OSX source) |
| `query --name <name>` | Find symbols by name (fuzzy) |
| `surface --qname <qname>` | Show the full source surface of a symbol |
| `slice --qname <qname>` | Extract the call-slice reachable from a symbol |
| `impact --qname <qname>` | Show everything that would be affected by changing a symbol |
| `wiring --qname <IIntf\|TForm>` | Spring4D DI wiring edges (impl class + lifetime + resolve-sites) and DFM event handlers (`--coverage` lists unresolved DI registrations) |
| `hover --file <f> --line <n> --col <c>` | Hover info at a source position |
| `rename --qname <q> --new-name <n>` | Preview or apply a symbol rename |
| `generate-docs --qname <q>` | Generate an XML doc-comment stub |
| `generate-test --qname <q>` | Generate a test-method stub |
| `find-deadcode` | List symbols with no callers outside their own unit |
| `compile-check <dproj>` | Run msbuild and store diagnostics in the DB |
| `check-unit <unit.pas>` | Compile one unit in project context (semantic errors; `--shadow` for unsaved buffers, `--resolve-uses` to suggest the missing unit) |
| `cycles` | Circular unit dependencies (`--edges` shows edges + move/layering candidates) |
| `uses-audit <unit.pas>` | Propose interface→implementation moves + unused units |
| `uses-fix <unit.pas> --project <dproj>` | Compiler-verified uses cleanup (move/remove; dry-run by default, `--apply`) |
| `resolve-uses --name <X>` | Which unit defines `X` and should be added to `uses` |
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
| `forms-csv --project <dproj> --db <db>` | Test-helper CSV: one row per form with the button/menu path from the main form (`Navigation`), the forms that open it (`Called From`), unit + line count (`--out <f.csv>`, `--root <TfrmMAIN>`) |
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
| `get_wiring` | Spring4D DI edges + DFM event handlers for an interface or form |
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

**Tools menu** (20+ items, organized into submenus): Hover at Cursor, Show Completion, 
Show Signature Help, Run Diagnostics, Rename Symbol, Compile & Diagnose, Import Build Log,
Format with YADF, Show Structure, Run AST Checks, Find Usages, Symbol Search, dockable 
panels (Structure / Usages / Symbol Search / Graph), Generate Test Helper CSV..., 
**Uses & Dependencies** submenu (cycles, uses-audit, uses-fix, reconcile, wiring, impact), 
**Inspect Symbol** submenu (surface, slice, type-at-cursor), 
**Code Quality** submenu (dead code, undocumented, TODOs, compiler hints, top symbols),
**Generate & Export** submenu (docs, tests, enums, graph, Obsidian),
**Index & Maintenance** submenu, plus diagnostics & test tools. Settings.

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

PowerShell smoke scripts in `tests/autotest/` exercise the built exe end to end:
```
pwsh -File tests/autotest/run_smoke.ps1       # CLI + LSP server smoke
pwsh -File tests/autotest/run_formsmap.ps1    # forms-csv navigation-map smoke (fixture project)
```

---

## Version history

See [CHANGELOG.md](CHANGELOG.md) for the full v0.16 to v0.35 history
(20 versions, released 2026-05-28 through 2026-05-29).

---

## License

MIT. See [LICENSE](LICENSE).
