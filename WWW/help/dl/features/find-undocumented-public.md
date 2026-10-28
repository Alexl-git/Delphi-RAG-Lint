---
id: find-undocumented-public
title: Find Undocumented (public)
summary: Uses query find to list indexed symbols filtered by documentation state, kind, or visibility
product: DL
group: search-navigation
order: 20007
since: 0.1.0-alpha
status: shipped
updated: 1.36.0-alpha
---

# Find Undocumented (public)

Uses query find to list indexed symbols filtered by documentation state, kind, or visibility.

Read this when you want to know which public symbols still lack a DocInsight comment. query find with --no-docs and --public lists them; --doc-tag and --doc-contains filter by comment content instead. Also under drag-lint > Code Quality in the IDE.

## How to run it

Full flag list: [query in the CLI reference](../cli.md#query).

## Flags

| Flag | Argument | Meaning | Default |
| --- | --- | --- | --- |
| `--doc-tag` | `X` |  |  |
| `--doc-contains` | `Y` |  |  |
| `--decl-contains` | `Z` |  |  |
| `--no-docs` |  |  |  |
| `--kind` | `K` |  |  |
| `--name` | `N` |  |  |
| `--unit` | `U` |  |  |
| `--public` |  |  |  |
| `--db` |  |  |  |

## Where to click

* RAD Studio main menu: **drag-lint > Code Quality > Find Undocumented (public)...**
   1. Needs an index of the project
   2. drag-lint > Code Quality > Find Undocumented (public)...
   3. Review the list of public declarations without a documentation comment

## Pitfalls

* --no-docs is a FILTER (UNDOCUMENTED symbols only), not "hide the docs" -- to list them all use query --kind `<k>` --all
* --decl-contains searches the DECLARING SOURCE LINE (`stored X`, `default V`, `read F write S`) -- clauses the index does not model. Needs --kind, --name or --unit; it re-reads source per candidate.
* case-insensitive, over /// blocks and harvested // above a declaration.
* declaration clauses the index does not model. `query --text` sees string literals and comment prose, not declaring lines -- this reads the declaring line instead.

## Details

Uses `query find` to list indexed symbols filtered by documentation state,
kind, or visibility. Reach for it to see which public symbols still have no
DocInsight comment.

### Running it from the CLI
```text
drag-lint query find [--doc-tag X | --doc-contains Y | --no-docs] [--kind K] [--public] [--db ...]
```
`--no-docs` restricts results to symbols with no doc comment; `--public`
restricts to public symbols; `--doc-tag`/`--doc-contains` filter by tag or
tag content instead of by absence; `--kind` filters by symbol kind.

`--doc-tag` accepts exactly nine tags: `summary`, `remarks`, `returns`,
`param`, `exception`, `example`, `seealso`, `since`, `deprecated`. An
unrecognized tag errors (exit 2) and lists the valid set.

### What it needs
The `--db` flag is optional -- drag-lint auto-resolves the project's index
when omitted. An index must still exist.

### Example
Illustrative only:
```text
drag-lint query find --no-docs --public --db C:\Projects\MyApp\_D-RAG\MyApp.sqlite
```
This would list `MyApp`'s public symbols that carry no doc comment.

---

[All features](../index.md) | [CLI reference](../cli.md) | [IDE menus](../ide.md)
