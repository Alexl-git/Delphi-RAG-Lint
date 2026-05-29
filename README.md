# Delphi-RAG-Lint

A Delphi-native, MIT-licensed RAG + linter for Delphi/Pascal source code.
Built on `tree-sitter-delphi13` (grammar, sibling project) and a vendored
MIT-licensed third-party Pascal binding layer for libtree-sitter. **Pure
Delphi at runtime — no Python, Node, or Rust deps.** Upstream attribution
preserved in `third_party/<repo>/LICENSE` files.

**v0.34-alpha. Early work in progress -- expect breaking changes.**
v0.34 adds **workspace mode**: a `.drag-lint-workspace.json` at the repo root
lists multiple projects (PACKAGE / SERVER / CLIENT / COMMON) that all index
into a single shared SQLite. CLI: `drag-lint workspace index|status|add`. The
Delphi plugin auto-detects the workspace config by walking up from the active
`.dproj` and switches to workspace indexing automatically (`EnableWorkspaceMode`
setting, default True).

v0.33 adds two navigation forms: **Find Usages** (`Ctrl+Alt+F`) prompts for
a symbol name, shells `drag-lint query find-callers`, and shows callers
grouped by file in a stay-on-top TTreeView; double-click jumps the editor.
**Symbol Search** (`Ctrl+Alt+T`) is a modal debounced-search dialog over the
indexed symbol table. Built on v0.32 (inline code lens + 4 new lint rules,
total 10 built-in rules + 3 AST checks), v0.31 (compiler-less `check-ast`,
`parser-error` rule, `ScanLibraries` toggle), v0.30 (Structure form + native Options page),
v0.29 in-editor visual diagnostics (gutter dots + wavy underlines +
Ctrl+Alt+I hint popup), v0.28 lint rule pack (5 built-in
tree-sitter-query rules), v0.27 QoL release, v0.26 compiler diagnostic
integration, v0.25 doc-comment generator + dead-code finder, v0.24 symbol
rename, v0.23 editor reactivity, v0.22 IDE polish, v0.16 structured
doc-comment extraction, v0.15 Obsidian `--open`, v0.14 `.drag-lint.json`
per-project config, and the v0.4 MCP server stack.

Builds on v0.2 (DFM forms, full symbol coverage, external `.scm` lint
plugins, `--project <dproj>` mode).

| Corpus | Files | Symbols | Refs | Index time |
|---|---:|---:|---:|---:|
| Micronite ORM3 (full) | 795 | 44,169 | 42,341 | 8 s |
| **Large 3rd-party VCL component suite (full install)** | **4,460** | **473,756** | **387,668** | **179 s (~3 min)** |
| Delphi RTL + VCL + FMX + Data | 1,295 | 212,083 | 250,663 | 60 s |

---

## Why

- **For humans:** symbol-aware "find usages" / "find overrides" with fuzzy
  matching (`TfrmFolderClas` finds `TfrmFolderClass`). No AI. Real symbol
  table.
- **For AI assistants:** deterministic structural retrieval. `find-callers
  --name TBaseForm.AfterShow` returns the exact list with line:col. No
  hallucination.
- **For codebases:** structural lint expressed as AST walkers (tree-sitter
  query language coming). Catches things grep can't — e.g.
  `FieldByName(…)` calls inside loops only when truly inside the loop body,
  not anywhere the literal text appears.

## Differentiation

| Tool | RAG | Lint | License | Native Delphi |
|---|---|---|---|---|
| **Delphi-RAG-Lint** | Symbol + fuzzy + (BM25 planned) | Yes | MIT | Yes |
| 3rd-party RAG tools for Delphi | Text RAG + LLM | No | Commercial | Yes |
| 3rd-party Delphi lint tools | — | Yes | Commercial | Yes |
| 3rd-party Pascal AST library | Parser lib only | No | MIT | Yes |

## Quickstart (Windows)

### Prerequisites
- RAD Studio 12 / Delphi 13 (37.0) with the Win64 toolchain
- Visual Studio 2022 BuildTools (for compiling parser.c + libtree-sitter to DLLs)
- A clone of [`tree-sitter-delphi13`](https://github.com/) at `C:\Projects\tree-sitter-delphi13` (sibling project — see `docs/design/`)
- Adjust the `tree-sitter-delphi13` path inside `build\_buildruntime.bat`, `build\_buildgrammar.bat`, and `build\_builddfm.bat` if you keep it elsewhere

### Build all three DLLs and the CLI

```cmd
:: 1. libtree-sitter runtime (one-time)
build\_buildruntime.bat

:: 2. grammar DLLs (one-time, or after grammar updates)
build\_buildgrammar.bat C:\Projects\tree-sitter-delphi13 third_party\dll\tree-sitter-delphi13.dll
build\_builddfm.bat

:: 3. drag-lint.exe
build\build_draglint.bat
```

The build script stages `drag-lint.exe` into `third_party\dll\` next to the
three DLLs so it can find them at load time.

### Use it

```cmd
:: Index a folder of Delphi sources (writes to .\drag-lint.sqlite by default)
third_party\dll\drag-lint.exe index C:\path\to\my\project --db myproj.sqlite

:: Index a .dproj — pulls in dependencies, Library, and Browsing paths
:: from the registry (HKCU and HKLM, both 32-bit and 64-bit views) and
:: expands $(BDS) macros.
third_party\dll\drag-lint.exe index --project C:\path\to\MyProject.dproj --db myproj.sqlite

:: Index just the Delphi Library + Browsing paths (no .dproj needed).
:: Useful as a one-time "library knowledge base" your AI can query.
third_party\dll\drag-lint.exe index --scan-libraries --db delphi-libs.sqlite

:: Preview which folders --project / --scan-libraries would index, without
:: actually indexing.
third_party\dll\drag-lint.exe index --project MyApp.dproj --dry-run

:: Find a symbol by exact name (fuzzy fallback if no exact match)
third_party\dll\drag-lint.exe query --name TBaseForm --db myproj.sqlite

:: Query across multiple indexes at once
third_party\dll\drag-lint.exe query --name TcxGrid --db myproj.sqlite --db delphi-libs.sqlite

:: Find a symbol by qualified name
third_party\dll\drag-lint.exe query --qname uBaseForm.TBaseForm.AfterShow --db myproj.sqlite

:: Find every caller / reference of a method or event handler
third_party\dll\drag-lint.exe query find-callers --name AfterShow --db myproj.sqlite

:: Lint a folder. Loads built-in rules + any *.scm rule files from
:: <exedir>\rules\ (see rules/README.md).
third_party\dll\drag-lint.exe lint C:\path\to\my\project

:: Run as an MCP server (JSON-RPC 2.0 over stdio) so Claude Code / Cursor
:: / Zed can discover and call find_symbol / find_callers / lint as
:: typed tools. See "MCP integration" below for the config block.
third_party\dll\drag-lint.exe serve --db myproj.sqlite

:: v0.8: feed your msbuild/dcc log into the index, then query it
::       (great for finding dead code H2077s across a 500k-symbol corpus)
msbuild /p:Config=Debug /p:Platform=Win64 MyApp.dproj /v:minimal > build.log
third_party\dll\drag-lint.exe import-log build.log --db myproj.sqlite
third_party\dll\drag-lint.exe query hints --name H2077 --db myproj.sqlite

:: Re-running index is incremental — files whose mtime+sha256 are
:: unchanged are skipped automatically. Reformat your project, then
:: re-run; only the changed files re-parse.

:: JSON output (for tooling integration)
third_party\dll\drag-lint.exe query --name TForm --db myproj.sqlite --json
third_party\dll\drag-lint.exe lint C:\path --json
```

### Smoke test

```cmd
tests\run_phase1_e2e.bat
```

Indexes a small fixture, runs the standard queries, prints expected output.

## MCP integration

`drag-lint serve --db <file.sqlite>` starts an MCP stdio server speaking
protocol version `2024-11-05`. AI editors that natively support MCP
(Claude Code, Cursor, Zed, Codeium, …) call `find_symbol`, `find_callers`,
and `lint` as typed tools — no shell parsing on their side.

### Claude Code config (`~/.claude.json` or per-project `.mcp.json`)

```json
{
  "mcpServers": {
    "drag-lint": {
      "command": "C:/Projects/Delphi-RAG-lint/third_party/dll/drag-lint.exe",
      "args": ["serve", "--db", "C:/Projects/myproject/drag-lint.sqlite"]
    }
  }
}
```

After the index exists (run `drag-lint index --project MyApp.dproj --db
.../drag-lint.sqlite` once), point your editor at the MCP block above and
the AI can ask drag-lint for symbols, callers, and lint findings as part
of its normal tool-use.

Prefer not to keep the server always-on? Skip the MCP config and just
call the CLI directly — `drag-lint query find-callers --name X --json`
returns the same data and only consumes tokens when actually invoked.

## Doc-comment extraction (v0.16)

`drag-lint` extracts structured documentation from Delphi doc comments at
index time and stores them in the `symbol_docs` table (schema v4). Three
comment formats are supported: XMLDoc (`/// <summary>...</summary>`), PasDoc
(`{** @param ... }`), and oneline (`/// one-liner above the declaration`).
Loose `{ ... }` block comments can be enabled per-project via `.drag-lint.json`.

Full design: [`docs/superpowers/specs/2026-05-28-v016-doc-extraction-design.md`](docs/superpowers/specs/2026-05-28-v016-doc-extraction-design.md)

### CLI usage

```cmd
:: Show the doc for a symbol (plain text, Markdown, or JSON)
drag-lint hover --qname Docs.TDocDemo.GetBaz --db myproj.sqlite
drag-lint hover --qname Docs.TDocDemo.GetBaz --db myproj.sqlite --format md
drag-lint hover --qname Docs.TDocDemo.GetBaz --db myproj.sqlite --format json

:: Find all deprecated symbols
drag-lint query find --doc-tag deprecated --db myproj.sqlite

:: Find all symbols with "baz" anywhere in their doc
drag-lint query find --doc-contains baz --db myproj.sqlite

:: Find undocumented public methods
drag-lint query find --no-docs --kind method --public --db myproj.sqlite
```

### MCP tools added in v0.16

| Tool | Description |
|---|---|
| `get_symbol_doc` | Full structured doc row for a qualified name |
| `find_by_doc_tag` | All symbols bearing `deprecated` or `since` tag |
| `find_undocumented` | Symbols with no doc comment (optional kind / public filter) |

### .drag-lint.json docs section

```json
{
  "docs": {
    "captureLooseComments": false,
    "allowBlankLineGap": 0,
    "implPrecedence": false
  }
}
```

## Blast-radius queries (v0.17)

For impact analysis, refactoring preview, and AI context optimization,
v0.17 adds `impact`, `surface`, and `slice` commands that traverse the
call graph and extract minimal source slices.

Full design: [`docs/superpowers/specs/2026-05-28-v017-blast-radius-design.md`](docs/superpowers/specs/2026-05-28-v017-blast-radius-design.md)

### CLI usage

```cmd
:: Transitive callers to depth N — how many units impact a change to X?
drag-lint impact --qname Foo.TBar.DoSomething --depth 2 --db myproj.sqlite

:: Class interface block (no impl bodies) — understand the contract
drag-lint surface --qname Foo.TBar --db myproj.sqlite
drag-lint surface --qname Foo.TBar --all-visibility --db myproj.sqlite

:: Minimal symbol slice for AI context — unit header + class decl + methods only
drag-lint slice --qname Foo.TBar --db myproj.sqlite

:: Find callers with surrounding source context (N lines before + after)
drag-lint query find-callers --name DoSomething --context 3 --db myproj.sqlite
drag-lint query find-callers --name DoSomething --context 3 --db myproj.sqlite --json
```

### MCP tools added in v0.17

| Tool | Arguments | Description |
|---|---|---|
| `get_impact` | `qname`, `depth` (optional, default 3) | Transitive callers by depth |
| `get_surface` | `qname`, `include_impl` (optional), `all_visibility` (optional) | Class interface slice |
| `get_slice` | `qname` | Unit header + class decl + method impls |
| `find_callers` | existing + `context` (optional, default 0) | Find-callers with surrounding source lines |

## Token reduction (v0.18)

`drag-lint` cuts AI assistant per-task token usage on Delphi codebases by an
order of magnitude, with zero data leaving the machine.

v0.18 adds `context` and `bench-context` commands that compose v0.16 docs +
v0.17 surface/slice/callers/impact into one minimal AI-ready payload
(Markdown, JSON, or raw source). The bundler estimates token count using a
simple chars / 3.7 heuristic and reports reduction ratio vs the naive baseline
(indexing the entire source file).

### CLI usage

```cmd
:: Compose one AI-ready bundle for a symbol (docs + interface + impl + callers)
drag-lint context --task "modify Foo.TBar.Baz" --db myproj.sqlite

:: Compose for refactor — includes impact summary and transitive callers
drag-lint context --task "refactor Foo.TBar.Baz" --caller-context 3 --db myproj.sqlite

:: Output as JSON instead of Markdown
drag-lint context --task "inspect Foo.TBar" --format json --db myproj.sqlite

:: Benchmark token reduction over N random documented symbols
drag-lint bench-context --n 10 --db myproj.sqlite
drag-lint bench-context --n 10 --md --db myproj.sqlite
```

### MCP tools added in v0.18

| Tool | Arguments | Description |
|---|---|---|
| `get_context_bundle` | `task`, `db` (optional), `caller_context` (optional), `max_callers` (optional), `format` (optional) | Compose docs + surface + slice + callers into one payload |

Full design: [`docs/superpowers/specs/2026-05-28-v018-context-bundles-design.md`](docs/superpowers/specs/2026-05-28-v018-context-bundles-design.md)

## Type-at-position (v0.19)

`drag-lint typeat` resolves the identifier at a specific source file position
(line and column) and returns the containing symbol, the resolved symbol's
qualified name, signature, and documentation. Useful for IDE hovering,
AI-assisted navigation, and type inference in editor extensions.

Pragmatic scope: top-level symbols + dotted access (`Foo.Bar`) against
class / record / interface parents. Local variable inference, generic
substitution, and `with`-statement scope are deferred to v0.21.

### CLI usage

```cmd
:: Resolve identifier at source position (line:col are 1-based)
drag-lint typeat Docs.pas:42:15 --db myproj.sqlite

:: Output as JSON
drag-lint typeat Docs.pas:42:15 --db myproj.sqlite --json

:: Verbose output (containing symbol + full resolution chain)
drag-lint typeat Docs.pas:42:15 --db myproj.sqlite --verbose
```

### MCP tools added in v0.19

| Tool | Arguments | Description |
|---|---|---|
| `get_type_at_position` | `file`, `line`, `col`, `db` (optional) | Resolve identifier at position; return qualified name + signature + doc |

### LSP enhancement

Hover (textDocument/hover) is enriched when the cursor is on an identifier
reference: in addition to declaration hover data, the response now includes
resolved symbol details (via type-at-position lookup) so clients can display
the inferred type and documentation inline.

## IDE-grade LSP (v0.20)

v0.20 adds LSP `textDocument/completion`, `textDocument/signatureHelp`, and
`textDocument/publishDiagnostics` (triggered on file save), bringing full
IDE autocomplete, signature hints, and inline diagnostics to any editor with
LSP support.

### Features

- **Completion (`textDocument/completion`)**: member completion after `.` and
  identifier completion via prefix matching. Trigger characters: `.`, `(`, `,`.
- **Signature Help (`textDocument/signatureHelp`)**: function/procedure
  signature with active parameter highlighting. Trigger characters: `(`, `,`.
- **Diagnostics (`textDocument/publishDiagnostics`)**: lint findings pushed to
  the editor on file save, with severity levels (Error/Warning/Information/Hint),
  source attribution (`drag-lint`), and rule codes for filtering.

### Configuration (VS Code example)

In `.vscode/settings.json`:

```json
{
  "[delphi]": {
    "editor.defaultFormatter": "delphi.delphi-for-vscode"
  }
}
```

Or via a launch config that connects to the LSP server:

```json
{
  "name": "Delphi LSP (drag-lint)",
  "server": {
    "command": "C:\\path\\to\\drag-lint.exe",
    "args": ["lsp", "--db", "C:\\path\\to\\myproj.sqlite"]
  }
}
```

### Notes

- `textDocument/didChange` is deliberately not wired — the server re-runs lint
  only on `didSave` (matching the indexer's file-based model). v0.21 (with
  OTAPI incremental updates) will enable fine-grained incremental diagnostics.
- Completion uses prefix-LIKE matching (no fuzzy yet; defer to v0.21+).
- v0.21 (below) will add OTAPI integration for in-IDE plugin support.

## Delphi IDE plugin (v0.21)

v0.21 brings a design-time OTAPI package for RAD Studio 13 Florence that surfaces
drag-lint LSP capabilities directly in the IDE. The plugin registers a Tools menu
with four entries: Hover at Cursor, Show Completion, Show Signature Help, Run Diagnostics.
Invocations are synchronous (modal dialogs) in v0.21; custom popups and keystroke
bindings move to v0.22 after OTAPI event wiring is finalized.

### Build & Install

See [`src/delphi-plugin/README.md`](src/delphi-plugin/README.md) for full instructions.

Quick summary:
```bash
cd src/delphi-plugin
cmd.exe /c "call ""C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\rsvars.bat"" && msbuild dclDragLintWizard.dproj /p:Platform=Win64 /p:Config=Debug /v:minimal"
# Output: build/v021/dclDragLintWizard.bpl
```

1. Ensure `drag-lint.exe` is on your PATH.
2. In RAD Studio 13: **Component → Install Packages... → Add** → browse to the .bpl.
3. Restart the IDE.
4. Tools menu now shows **drag-lint** with four entries.

### Architecture

- **LSP client (`TDragLintLspClient`)** — spawns `drag-lint.exe lsp` as a persistent
  subprocess and round-trips JSON-RPC 2.0 requests over anonymous pipes.
- **OTAPI integration** — `IOTAWizard` registration hooks into IDE startup;
  menu items route through `IOTAActionServices` and message dialogs.
- **Diagnostics routing** — `publishDiagnostics` notifications post to the
  Messages pane via `IOTAMessageServices.AddToolMessage` (thread-safe).

### Limitations (deferred to v0.22)

- No custom popup forms — results appear in ShowMessage dialogs.
- No keystroke bindings — invocation is Tools menu only.
- No index auto-build — assumes you've run `drag-lint index` already.
- No incremental updates — diagnostics run on menu-click, not on every keystroke.

## IDE Polish (v0.22)

v0.22 builds on v0.21's IDE integration with four polish features moving the
plugin from demo-quality to daily-driver:

- **Auto-index on project open** — when a `.dproj` opens in the IDE, the
  plugin asynchronously spawns `drag-lint.exe index` to refresh the symbol
  database. Togglable via **Tools > drag-lint > Settings...**.
- **Settings UI** — registry-backed configuration dialog (no .dfm required)
  with seven fields: ExePath, DbPathTemplate (use `<projdir>` placeholder),
  and five feature toggles (AutoIndex, EnableHover, EnableCompletion,
  EnableSignature, EnableDiagnostics).
- **Keystroke bindings** — `Ctrl+Alt+H` (Hover), `Ctrl+Alt+C` (Completion),
  `Ctrl+Alt+S` (Signature), `Ctrl+Alt+D` (Diagnostics) via
  `IOTAKeyboardServices.AddKeyboardBinding`. Each respects its Enable* setting.
- **Custom hover popup** — borderless `fsStayOnTop` form with TMemo content
  (Consolas 9pt), auto-sized up to 600×400, positioned below the cursor,
  auto-closes on ESC / click-outside / 30s timeout.

Completion and signature help custom popups, plus incremental `didChange`
editor updates, move to v0.23. Full spec: [2026-05-29 IDE polish design](docs/superpowers/specs/2026-05-29-v022-ide-polish-design.md).

## Exit codes

| Code | Meaning |
|---|---|
| 0 | success / clean / match found |
| 1 | no match / findings present |
| 2 | usage error (bad args, missing path/db) |
| 3 | fatal exception |

## What works in v0.2

- **Indexer** for `.pas` / `.dpr` / `.dpk` / `.dfm`
- **Symbol kinds emitted:** `unit`, `class`, `interface`, `record`, `enum`,
  `enum_value`, `procedure`, `function`, `method`, `constructor`,
  `destructor`, `property`, `field`, `form`, `component`
- **DFM**: every `object Name: TClass` emits a `form` (top-level) or
  `component` (nested); event-handler bindings (`OnClick = btnOKClick`)
  emit references that show up in `find-callers`
- **Project-aware scan**: `drag-lint index --project <file.dproj>` parses
  the .dproj's `DCC_UnitSearchPath`, walks the `.dpr`'s `uses X in 'path'`
  clauses, reads HKCU + HKLM Library and Browsing paths for Win32 + Win64,
  expands `$(BDS)` macros, deduplicates the resulting folder set, indexes
  the union
- **Per-file SQLite transactions** with full re-emit semantics on re-index
- **Symbol-exact query** by name or qualified name
- **Fuzzy fallback** (Levenshtein, adaptive threshold by pattern length)
- `find-callers` — every site referencing a name (call site, event-handler
  binding, etc.)
- **Built-in lint rule**: `field-by-name-in-loop` (AST-precise; no false
  positives in comments/strings)
- **External lint rules**: drop `*.scm` query files into `rules/`; sister
  `*.json` provides metadata. See `rules/README.md`. Predicate evaluation
  (`#eq?`, `#match?`) is v0.3 — for now rules must be structurally
  specific.

## Roadmap

- v0.5: BM25 over AST-chunked text for semantic retrieval; daemon mode
  watching the filesystem for changes; ATTACH-based cross-DB query joins;
  3+ new lint rules; project-aware mode caching
- v0.6: LSP server (for editors that speak LSP but not MCP), per-project
  `.drag-lint.json` config, optional embedding hookup for semantic search
- v1.0: BPL packaging for in-IDE use, additional `ISymbolStore` impls,
  stable CLI surface, multi-platform binaries

## Project layout

```
src/core/      — interfaces, model records, indexer
src/parser/    — tree-sitter wrapper + Delphi13 AST walker
src/storage/   — SQLite schema + FireDAC ISymbolStore impl
src/query/     — fuzzy matcher (Levenshtein)
src/lint/      — linter
src/cli/       — argparse + dispatch + drag-lint.dpr/.dproj
build/         — *.bat compile scripts
third_party/   — vendored MIT-licensed Pascal bindings + compiled DLLs
tests/         — fixtures + e2e smoke test
docs/          — v1 design doc
```

## License

MIT. Portions of the binding layer derive from an upstream MIT-licensed
Pascal binding for libtree-sitter; the grammar derives from an upstream
MIT-licensed Pascal/Delphi tree-sitter grammar. Full attributions are in
the LICENSE files under `third_party/`.
