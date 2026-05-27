# Delphi-RAG-Lint

A Delphi-native, MIT-licensed RAG + linter for Delphi/Pascal source code.
Built on `tree-sitter-delphi13` (grammar) and
[modersohn/delphi-tree-sitter](https://github.com/modersohn/delphi-tree-sitter)
(runtime bindings, MIT). **Pure Delphi at runtime — no Python, Node, or Rust
deps.**

**v0.1-alpha. Indexer + symbol query + fuzzy fallback + find-callers + one
lint rule, all working end-to-end on a real codebase (Micronite ORM3 COMMON,
310 .pas files, ~12k symbols, ~6k references, indexed in ~1.7 seconds).**

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
| theMIMER | Text RAG + LLM | No | Commercial | Yes |
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
:: Index a Delphi project (writes to .\drag-lint.sqlite by default)
third_party\dll\drag-lint.exe index C:\path\to\my\project --db myproj.sqlite

:: Find a symbol by exact name (fuzzy fallback if no exact match)
third_party\dll\drag-lint.exe query --name TBaseForm --db myproj.sqlite

:: Find a symbol by qualified name
third_party\dll\drag-lint.exe query --qname uBaseForm.TBaseForm.AfterShow --db myproj.sqlite

:: Find every caller of a method
third_party\dll\drag-lint.exe query find-callers --name AfterShow --db myproj.sqlite

:: Lint a folder for FieldByName-in-loop anti-pattern
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

## What works in v0.1

- Indexer for `.pas` / `.dpr` / `.dpk` (`.dfm` deferred to v0.2)
- Symbol kinds emitted: `unit`, `class`, `method`, `procedure`, `function`,
  `constructor`, `destructor`. (`interface`-as-type, `record`, `enum`,
  `property`, `field` are next.)
- Per-file SQLite transactions with full re-emit semantics on re-index
- Symbol-exact query by name or qualified name
- **Fuzzy fallback** (Levenshtein, adaptive threshold by pattern length)
- `find-callers` — every call site whose callee text matches a name
  (`bare()` or `Foo.bare()` both detected)
- One lint rule: `field-by-name-in-loop`
- Sub-second query latency on ~12k-symbol indexes

## Roadmap

- v0.2: `.dfm` form indexing, `declInterface` support, more lint rules,
  README screenshots
- v0.5: BM25 over AST-chunked text (full-text retrieval), MCP server
  (`drag-lint serve`), VCL inspector demo
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
