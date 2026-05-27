# Delphi-RAG-Lint

A Delphi-native, MIT-licensed RAG + linter for Delphi/Pascal source code.
Built on `tree-sitter-delphi13` (grammar, sibling project)
and [modersohn/delphi-tree-sitter](https://github.com/modersohn/delphi-tree-sitter)
(runtime bindings).

**Status:** v1 in development. See [docs/design/2026-05-27-v1-design.md](docs/design/2026-05-27-v1-design.md).

## Why

- **For humans:** symbol-aware "find usages" / "find overrides" with fuzzy
  matching (find `TfrmFolderClass` even when you type `TfrmFolderClas`). No
  AI required — just a real symbol table.
- **For AI assistants (Claude / Opus / etc.):** deterministic structural
  retrieval. Ask `find-callers --symbol=TBaseForm.AfterShow` and get the
  exact list with line numbers. No hallucination.
- **For codebases:** structural lint rules expressed as tree-sitter queries.
  Catch `FieldByName` calls inside loops, units missing from `.dproj`,
  inline comments hiding inside multi-line argument lists.

## Differentiation

Delphi-RAG-Lint is the first FOSS Delphi-native tool that combines symbol
RAG and structural lint in one binary. Existing tools:

| Tool | RAG | Lint | License |
|---|---|---|---|
| **Delphi-RAG-Lint** | Symbol + fuzzy + BM25 | Yes | MIT |
| theMIMER | Text RAG + LLM | No | Commercial |
| FixInsight | — | Yes | Commercial |
| Peganza Pascal Analyzer | — | Yes | Commercial |
| DelphiAST | Parser only | No | MIT |

## Status

- **Phase 0** (toolchain validation) — **done.** Grammar DLLs built; modersohn
  bindings load them; AST parse confirmed on a `.pas` fixture.
- **Phase 1** (indexer + SQLite store + CLI) — **done.** `drag-lint index`
  walks a folder, parses each Delphi source with tree-sitter, extracts
  unit/class/method symbols, writes them to SQLite. `drag-lint query --name`
  / `--qname` returns deterministic results with file:line ranges, JSON
  output supported.
- **Phase 2a** (references + fuzzy match) — next.

## Quickstart

```cmd
:: Build the grammar DLLs (one-time)
build\_buildgrammar.bat C:\Projects\tree-sitter-delphi13 third_party\dll\tree-sitter-delphi13.dll
build\_builddfm.bat
build\_buildruntime.bat

:: Build the CLI
build\build_draglint.bat

:: Index something
third_party\dll\drag-lint.exe index path\to\source --db myproject.sqlite

:: Query
third_party\dll\drag-lint.exe query --name TFormShow --db myproject.sqlite --json
```

## License

MIT. Portions of the tree-sitter binding layer derive from
modersohn/delphi-tree-sitter (MIT). Grammar derives from
[tree-sitter-pascal](https://github.com/Isopod/tree-sitter-pascal) (MIT).
