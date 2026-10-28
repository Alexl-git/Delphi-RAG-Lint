---
id: symbol-search
title: Symbol Search
summary: Searches symbols by name across the indexed projects
product: DL
group: search-navigation
order: 20028
since: 0.1.0-alpha
status: shipped
updated: 1.36.0-alpha
---

# Symbol Search

Searches symbols by name across the indexed projects.

Read this when you know or can guess a symbol name but not its file: Symbol Search finds types, methods and fields by name across the indexed projects, bound to Ctrl+Alt+T.

## How to run it

Full flag list: [query in the CLI reference](../cli.md#query).

## Flags

| Flag | Argument | Meaning | Default |
| --- | --- | --- | --- |
| `--name` | `<symbol-name>` |  |  |
| `--db` |  |  |  |
| `--json` |  |  |  |
| `--case-sensitive` |  |  |  |
| `--exact` |  |  |  |

## Where to click

* RAD Studio main menu: **drag-lint > Symbol Search...**
   1. Choose drag-lint > Symbol Search...
   2. Type part of the symbol name in the search box
   3. Pick a result to open its declaration; the dialog also has a Usages view

## Pitfalls

* a project DB IS the compile closure, so a hit is membership and a MISS is non-membership.

## Details

Searches symbols by name across the indexed projects. Reach for it to jump
to a type, method, or field when you know (or can guess) its name but not
its file.

### Running it from the CLI
```text
drag-lint query --name <symbol-name> [--db <file.sqlite>] [--json] [--case-sensitive] [--exact]
drag-lint query --qname <qualified> [--db <file.sqlite>] [--json] [--case-sensitive]
```
`--name`/`--qname` match case-insensitively by default (`--case-sensitive`
restores byte-exact matching); `--name` also accepts a qualified name.
`--exact` suppresses the fuzzy fallback, so zero rows means "no such
symbol". The same lookup is also exposed over stdio as the language
server's "workspace symbols" method (the Features page lists
it under `drag-lint lsp`).

### What it needs
The `--db` flag is optional -- drag-lint auto-resolves the index when
omitted. An index must still exist.

### Example
Illustrative only:
```text
drag-lint query --name TCustomerOrder --db C:\Projects\MyApp\_D-RAG\MyApp.sqlite --json
```
This would return every symbol named `TCustomerOrder` (exact or fuzzy) as
JSON.

---

[All features](../index.md) | [CLI reference](../cli.md) | [IDE menus](../ide.md)
