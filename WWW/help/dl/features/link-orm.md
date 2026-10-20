---
id: link-orm
title: link-orm
summary: Links a project's code index to a SQL index so ORM-style relationships between Delphi symbols and SQL objects can be resolved across both
product: DL
group: database
order: 100002
since: 0.40.5-alpha
status: shipped
updated: 1.32.0-alpha
---

# link-orm

Links a project's code index to a SQL index so ORM-style relationships between Delphi symbols and SQL objects can be resolved across both.

## How to run it

Full flag list: [link-orm in the CLI reference](../cli.md#link-orm).

## Flags

| Flag | Argument | Meaning | Default |
| --- | --- | --- | --- |
| `--db` | `<projDb.sqlite>` |  |  |

**Needs:** index

## Details

Links a project's code index to a SQL index so ORM-style relationships
between Delphi symbols and SQL objects can be resolved across both. Reach
for it when you want queries that cross from code into the schema it talks
to.

### Running it from the CLI

```text
drag-lint link-orm --db <projDb.sqlite> --db <sqlDb.sqlite>
```

### Reaching it in the IDE

No IDE surface -- this is a CLI-only feature.

### What it needs

An index IS required -- in fact TWO: `link-orm` takes exactly two `--db`
flags, one for the project's own DB and one for the SQL DB. The project's DB
lives at `<project folder>\_D-RAG\<project file>.sqlite`; run
`drag-lint resolve-dbs --project <X.dproj>` if unsure.

### Example

Illustrative only:

```text
drag-lint link-orm --db C:\Projects\MyApp\_D-RAG\MyApp.sqlite --db sql.sqlite
```

This would link `MyApp`'s code index to the `sql.sqlite` SQL index.

---

[All features](../index.md) | [CLI reference](../cli.md) | [IDE menus](../ide.md)
