# Delphi-RAG-Lint

A Delphi-native, MIT-licensed RAG + linter for Delphi/Pascal source code.
Built on `tree-sitter-delphi13` (grammar) and
[modersohn/delphi-tree-sitter](https://github.com/modersohn/delphi-tree-sitter)
(runtime bindings, MIT). **Pure Delphi at runtime — no Python, Node, or Rust
deps.**

**v0.2-alpha. Adds DFM form indexing, full symbol coverage (interfaces,
records, enums, properties, fields), external lint rule plugins (S-expression
query files), and project-aware scan (`--project <file.dproj>` resolves
dependencies + Library/Browsing paths from the registry automatically).**

| Corpus | Files | Symbols | Refs | Index time |
|---|---:|---:|---:|---:|
| Micronite ORM3 (full) | 795 | 44,169 | 42,341 | 8 s |
| **DevExpress VCL (entire install)** | **4,460** | **473,756** | **387,668** | **179 s (~3 min)** |
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
| Commercial Delphi-native RAG/LLM tools | Text RAG + LLM | No | Commercial | Yes |
| FixInsight | — | Yes | Commercial | Yes |
| Peganza Pascal Analyzer | — | Yes | Commercial | Yes |
| DelphiAST | Parser lib only | No | MIT | Yes |

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

:: Find a symbol by exact name (fuzzy fallback if no exact match)
third_party\dll\drag-lint.exe query --name TBaseForm --db myproj.sqlite

:: Find a symbol by qualified name
third_party\dll\drag-lint.exe query --qname uBaseForm.TBaseForm.AfterShow --db myproj.sqlite

:: Find every caller / reference of a method or event handler
third_party\dll\drag-lint.exe query find-callers --name AfterShow --db myproj.sqlite

:: Lint a folder. Loads built-in rules + any *.scm rule files from
:: <exedir>\rules\ (see rules/README.md).
third_party\dll\drag-lint.exe lint C:\path\to\my\project

:: JSON output (for tooling integration)
third_party\dll\drag-lint.exe query --name TForm --db myproj.sqlite --json
third_party\dll\drag-lint.exe lint C:\path --json
```

### Smoke test

```cmd
tests\run_phase1_e2e.bat
```

Indexes a small fixture, runs the standard queries, prints expected output.

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

- v0.3: tree-sitter query predicates (`#eq?`/`#match?`/`#not-eq?`); MCP
  server (`drag-lint serve`); BM25 over AST-chunked text for semantic
  retrieval; project-aware mode caching to avoid re-walking the registry
- v0.5: more lint rules, IDE inspector demo, multi-platform binaries
- v1.0: BPL packaging for in-IDE use, additional `ISymbolStore` impls
  (Firebird Embedded), per-project `.drag-lint.json` config

## Project layout

```
src/core/      — interfaces, model records, indexer
src/parser/    — tree-sitter wrapper + Delphi13 AST walker
src/storage/   — SQLite schema + FireDAC ISymbolStore impl
src/query/     — fuzzy matcher (Levenshtein)
src/lint/      — linter
src/cli/       — argparse + dispatch + drag-lint.dpr/.dproj
build/         — *.bat compile scripts
third_party/   — vendored modersohn bindings + compiled DLLs
tests/         — fixtures + e2e smoke test
docs/          — v1 design doc
```

## License

MIT. Portions of the binding layer derive from
[modersohn/delphi-tree-sitter](https://github.com/modersohn/delphi-tree-sitter)
(MIT). The grammar derives from
[tree-sitter-pascal](https://github.com/Isopod/tree-sitter-pascal) (MIT).
