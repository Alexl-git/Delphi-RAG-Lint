---
id: identifier-case-mismatch
title: Identifier case mismatch (lint rule)
summary: "Lint rule, OFF by default: a name spelled in a different case from its declaration"
product: DL
group: linting
order: 30018
since: 1.42.0-alpha
status: shipped
updated: 1.42.0-alpha
---

# Identifier case mismatch (lint rule)

Lint rule, OFF by default: a name spelled in a different case from its declaration.

Read this to see what identifier-case-mismatch covers: locals and parameters from the syntax tree, bound refs from an index, reported once per spelling.

## How to run it

```text
drag-lint lint-all [--profile <name>] [--target-compiler <ver|auto>] [--db <file.sqlite>] [--project <.dproj>] [--build-config <name>] [--rule <id>] [--disable id,...] [--output <report.txt>] [--json] [--labels] [--quiet] [--lint-third-party] [--no-preprocess] [--shared-db <db> ...]
```

Example:

```text
drag-lint lint-all --db <project.sqlite> --rule identifier-case-mismatch
```

Full flag list: [lint-all in the CLI reference](../cli.md#lint-all).

## Where to click

No IDE surface: this feature runs from the CLI (see How to run it).

## Details

A name is spelled in a different case from its declaration. Delphi does not care, so this is a readability rule, and also a way to catch code that was never read after a rename. OFF by default.

### Running it
```text
drag-lint lint <file> --rule identifier-case-mismatch
drag-lint lint-all --db <project.sqlite> --rule identifier-case-mismatch
```

### What it covers
- Locals and parameters, from the syntax tree, so no index is needed.
- With an index: every ref the resolver bound to a project symbol (methods, properties, routines), across units.

One finding per spelling per routine for locals, and one per spelling per symbol per file for bound refs, so a legacy file does not produce one line per use.

### What stays silent
- Anything inside `with`: a bare name may be a member there.
- A name after a dot, unless the resolver bound it.
- A local declared twice in different spellings (two inline blocks).
- A nested routine's use of an outer local: the nested routine is judged on its own declarations.
- A ref the resolver did not bind, and names from the platform library.

---

[All features](../index.md) | [CLI reference](../cli.md) | [IDE menus](../ide.md)
