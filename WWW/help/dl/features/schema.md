---
id: schema
title: schema
summary: "Prints the live schema of an index database: schemaversion, every table and column, and row counts"
product: DL
group: indexing
order: 10009
since: 0.95.0-alpha
status: shipped
updated: 1.38.0-alpha
---

# schema

Prints the live schema of an index database: schemaversion, every table and column, and row counts.

Read this when you need to know exactly what an index database contains before you query it: schema prints the schema version, every table and column, and row counts, read-only.

## How to run it

Full flag list: [schema in the CLI reference](../cli.md#schema).

## Flags

| Flag | Argument | Meaning | Default |
| --- | --- | --- | --- |
| `--db` | `<file.sqlite>` |  |  |
| `--format` |  |  |  |
| `--output` | `<file>` |  |  |

## Where to click

No IDE surface: this feature runs from the CLI (see How to run it).

**Needs:** index

## Details

Prints the live schema of an index database: schema_version, every table
and column, and row counts. Reach for it when you need to know exactly what
an index DB contains before querying it, or to check its schema_version.

### Running it from the CLI

```text
drag-lint schema --db <file.sqlite> [--format text|json] [--output <file>]
```

Read-only.

### What it needs

An index IS required. The project's DB lives at
`<project folder>\_D-RAG\<project file>.sqlite`; run
`drag-lint resolve-dbs --project <X.dproj>` if unsure.

### Example

Illustrative only:

```text
drag-lint schema --db C:\Projects\MyApp\_D-RAG\MyApp.sqlite --format json
```

This would print `MyApp`'s index schema -- version, tables, columns, and row
counts -- as JSON.

---

[All features](../index.md) | [CLI reference](../cli.md) | [IDE menus](../ide.md)
