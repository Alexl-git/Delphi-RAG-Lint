---
id: helpers-of
title: helpers-of
summary: Lists record/class helper edges targeting a given type, anywhere in the index
product: DL
group: search-navigation
order: 20014
since: 0.94.0-alpha
status: shipped
updated: 1.36.0-alpha
---

# helpers-of

Lists record/class helper edges targeting a given type, anywhere in the index.

Read this to see every record or class helper that extends a type anywhere in the indexed code. helpers-of T --db lists the helper edges targeting T; it is read-only and adds --json for machine output.

## How to run it

Full flag list: [helpers-of in the CLI reference](../cli.md#helpers-of).

## Flags

| Flag | Argument | Meaning | Default |
| --- | --- | --- | --- |
| `--json` |  |  |  |
| `--db` | `<db>` |  |  |

## Where to click

* RAD Studio main menu: **drag-lint > Inspect Symbol > Helpers of Type...**
   1. Needs an index of the project
   2. drag-lint > Inspect Symbol > Helpers of Type...
   3. Enter the type; its helpers are listed

**Needs:** index

## Details

Lists record/class helper edges targeting a given type, anywhere in the
index. Reach for it to see which helpers extend a type across the whole
indexed codebase.

### Running it from the CLI

```text
drag-lint helpers-of <T> [--json] --db <db>
```

`<T>` is the target type name. `--db` is required (not bracketed in the
usage line). This verb has no `--apply` flag -- it is a read-only listing.

### What it needs

An index IS required. The project's DB lives at
`<project folder>\_D-RAG\<project file>.sqlite`; run
`drag-lint resolve-dbs --project <X.dproj>` if unsure.

### Example

Illustrative:

```text
drag-lint helpers-of TColorKind --db C:\Projects\MyApp\_D-RAG\MyApp.sqlite
```

This would list every record/class helper in the index that targets
`TColorKind`.

---

[All features](../index.md) | [CLI reference](../cli.md) | [IDE menus](../ide.md)
