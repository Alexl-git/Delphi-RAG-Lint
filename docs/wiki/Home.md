# drag-lint

An AST-exact index, linter and documentation engine for Delphi / Object Pascal.

drag-lint parses your source with tree-sitter, stores symbols, references and
call edges in SQLite, and answers questions about them: *where is this declared*,
*who calls it*, *what breaks if I change it*, *what is undocumented*, *what is
wrong with it*. It ships as a command-line tool, a RAD Studio IDE plugin, and a
language server.

**Status: alpha.** Expect breaking changes. The index format is stable within a
schema version; the CLI surface is not yet frozen.

## Start here

| Page | For |
|---|---|
| **[Installation](Installation)** | Getting the CLI, the IDE plugin, or the LSP running |
| **[Maintenance](Maintenance)** | Indexes, the manifest, reindexing, and what to do when something looks wrong |
| **[IDE Menu Reference](IDE-Menu-Reference)** | What every item in the `drag-lint` menu does |

## The one-paragraph model

Everything drag-lint knows lives in a **SQLite index**. One index per project,
stored beside the project file at `<project folder>\_D-RAG\<projectname>.sqlite`,
plus one **per-platform library index** covering the RTL, VCL and third-party
units. A **manifest** (`drag-lint.json`, beside the exe) lists the sections and
lets every command find the right database without being told. If an answer looks
wrong, the first question is almost always *is the index fresh?* -- see
[Maintenance](Maintenance).

## Two commands that answer most questions

```
drag-lint query --name TMyClass --db <index>
drag-lint query find-callers --name DoStuff --db <index>
```

and one that finds problems:

```
drag-lint lint-all --db <index>
```

## A trap worth knowing on day one

On Windows, if `NoDefaultCurrentDirectoryInExePath` is set (it is, in many
corporate images), then

```
cd C:\tools\drag-lint
drag-lint lint-all --db ...        <-- may run a DIFFERENT drag-lint.exe from PATH
```

does **not** run the exe in that folder. Always use `.\drag-lint.exe` or a full
path. This is not hypothetical: it once produced 33,626 findings against the real
14,764, silently, because an old binary answered.

## Links

* [Issues](https://github.com/Alexl-git/Delphi-RAG-Lint/issues)
* [Releases](https://github.com/Alexl-git/Delphi-RAG-Lint/releases)
* `CHANGELOG.md` in the repository root
