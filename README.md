# Delphi-RAG-Lint

A Delphi-native, MIT-licensed RAG + linter for Delphi/Pascal source code.
Built on `tree-sitter-delphi13` (grammar, sibling project) and a vendored
MIT-licensed third-party Pascal binding layer for libtree-sitter. **Pure
Delphi at runtime — no Python, Node, or Rust deps.** Upstream attribution
preserved in `third_party/<repo>/LICENSE` files.

**v0.12-alpha. Early work in progress — expect breaking changes.** Adds
`drag-lint todos` — scan `.pas/.dpr/.dpk/.inc` for `// TODO`, `// FIXME`,
`// HACK`, `// XXX`, `// REVIEW`, `// NOTE` comments with optional
author capture, JSON output, and Delphi-priority-digit awareness.
Builds on v0.11 watch mode, v0.10 graph export, v0.9 project-shaped
lint rules, v0.8 type-use refs + compiler-log ingest, v0.7 LSP position
resolution, v0.4 MCP server, and the export/top/fuzzy stack.

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
