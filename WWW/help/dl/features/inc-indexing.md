---
id: inc-indexing
title: Include-file indexing and IF evaluation
summary: Include files are indexed under the active build, value defines and IF expressions are evaluated, and an undecidable IF is reported as a pp-unresolved-if hint
product: DL
group: indexing
order: 10002
since: 1.37.0-alpha
status: shipped
updated: 1.38.0-alpha
---

# Include-file indexing and IF evaluation

Include files are indexed under the active build, value defines and IF expressions are evaluated, and an undecidable IF is reported as a pp-unresolved-if hint.

Read this when units pull code from .inc files or choose branches with IF directives. The indexer follows includes, evaluates value defines, Declared() and true constants, and says so when it cannot decide a branch.

## How to run it

Full flag list: [index in the CLI reference](../cli.md#index).

## Where to click

No IDE surface: this feature runs from the CLI (see How to run it).

## Details

The indexer follows `{$I file.inc}` the way the compiler would for the project's active build, and evaluates the conditions that choose the branch.

### Running it from the CLI
```text
drag-lint index --project <file.dproj> --db <file.sqlite>
drag-lint pp-profile --dproj <file.dproj>      (the define set the indexer sees)
```
A project DB indexes only the ACTIVE includes, parsed in the includer's define context. Which include is chosen follows the exact preprocessor values: value defines, `CompilerVersion`, `IFOPT`, true constants of the same file or of a used project / library unit, `Declared()` and arithmetic in `{$IF}`. `lint-all` lints an `.inc` file in the context of its includer. When an `{$IF}` cannot be decided, `lint` reports the `pp-unresolved-if` hint instead of guessing.

### What it needs
A project index built with the 1.37.0 extractor; older DBs re-parse on the next index run.

---

[All features](../index.md) | [CLI reference](../cli.md) | [IDE menus](../ide.md)
