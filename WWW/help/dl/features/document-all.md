---
id: document-all
title: document-all
summary: Documents every public declaration in every indexed unit, with no project scope
product: DL
group: documentation
order: 40004
since: 0.93.0-alpha
status: shipped
updated: 1.33.0-alpha
---

# document-all

Documents every public declaration in every indexed unit, with no project scope.

Read this when you want to sweep DocInsight comments across everything in the index rather than one project at a time. document-all documents every public declaration in every indexed unit; the default is facts-only.

## How to run it

Full flag list: [document-all in the CLI reference](../cli.md#document-all).

## Flags

| Flag | Argument | Meaning | Default |
| --- | --- | --- | --- |
| `--stubs` |  |  |  |
| `--apply` |  |  |  |
| `--json` |  |  |  |
| `--no-backup` |  |  |  |
| `--include-accessors` |  |  |  |
| `--migrate-pure` |  |  |  |
| `--db` | `PATH` |  |  |

## Where to click

* RAD Studio main menu: **drag-lint > Generate & Export > Auto-Document Every Indexed Unit...**

## Details

Documents every public declaration in every indexed unit, with no project
scope. Reach for it to sweep DocInsight comments across the whole index at
once, rather than one project at a time.

### Running it from the CLI

```text
drag-lint document-all [--stubs|--apply|--json|--no-backup|--include-accessors|--migrate-pure] [--db PATH]
```

Like the other batch document modes, the default is facts-only: an empty
tag is never written, `<param>` never gets a skeleton, and `<summary>`
appears only when harvested from a nearby `//` comment; add `--stubs` to
keep a fresh comment that has no facts block. Trivial `Get*`/`Set*` property
accessors are skipped by default; add `--include-accessors` to document
them too. The usage line lists `--apply` as a flag; whether omitting it
produces a dry run is not documented in the help text for this verb.

`document-all` covers every indexed unit with no project scope. This is
different from `drag-lint document --project <p.dproj>`, which is scoped to
the compile closure restricted to that project's own roots (declared in
`_D-RAG\drag-lint-project.json`).

### Reaching it in the IDE

No IDE surface -- this is a CLI-only feature.

### What it needs

The `--db` flag is optional -- drag-lint auto-resolves the index when
omitted. An index must still exist.

### Example

Illustrative:

```text
drag-lint document-all --apply --db C:\Projects\MyApp\_D-RAG\MyApp.sqlite
```

This would add facts-only DocInsight comments to every public declaration
in every unit that this index covers, regardless of which project owns it.

---

[All features](../index.md) | [CLI reference](../cli.md) | [IDE menus](../ide.md)
