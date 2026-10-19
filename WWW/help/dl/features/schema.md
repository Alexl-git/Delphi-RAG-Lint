---
id: schema
title: schema
summary: "Prints the live schema of an index database: schemaversion, every table and column, and row counts"
product: DL
group: indexing
order: 10007
since: 0.3.0-alpha
status: shipped
updated: 0.3.0-alpha
---

# schema

Prints the live schema of an index database: schemaversion, every table and column, and row counts.

## How to run it

Full flag list: [schema in the CLI reference](../cli.md#schema).

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

### Reaching it in the IDE

No IDE surface -- this is a CLI-only feature.

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
