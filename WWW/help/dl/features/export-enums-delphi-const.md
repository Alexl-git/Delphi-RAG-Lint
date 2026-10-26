---
id: export-enums-delphi-const
title: Export Enums (Delphi const)
summary: Uses export enums with --format delphi-const to dump indexed enum types as Delphi const declarations
product: DL
group: graphs-reports
order: 70008
since: 0.6.0-alpha
status: shipped
updated: 1.35.1-alpha
---

# Export Enums (Delphi const)

Uses export enums with --format delphi-const to dump indexed enum types as Delphi const declarations.

Read this when you need the enum types of a project as Delphi const declarations, for interop or code generation. Run drag-lint export enums --format delphi-const against the project index, or use drag-lint > Generate & Export in the IDE.

## How to run it

Full flag list: [export in the CLI reference](../cli.md#export).

## Flags

| Flag | Argument | Meaning | Default |
| --- | --- | --- | --- |
| `--db` | `<file.sqlite>` |  |  |
| `--format` |  |  |  |
| `--output` | `<file>` |  |  |

## Where to click

* RAD Studio main menu: **drag-lint > Generate & Export > Export Enums (Delphi const)...**
   1. Choose drag-lint > Generate & Export > Export Enums (Delphi const)...
   2. Follow the dialog; the indexed enum types are written as Delphi const declarations

**Needs:** index

## Details

Uses `export enums` with `--format delphi-const` to dump indexed enum types
as Delphi const declarations. Reach for it to generate a const-based mirror
of an enum for interop or codegen.

### Running it from the CLI
```text
drag-lint export enums --db <file.sqlite> [--format firebird-sql|csv|json|delphi-const]
```
`--format` selects the output flavor: `firebird-sql`, `csv`, `json`, or
`delphi-const`.

### What it needs
An index IS required. The project's DB lives at
`<project folder>\_D-RAG\<project file>.sqlite`; run
`drag-lint resolve-dbs --project <X.dproj>` if unsure.

### Example
Illustrative only:
```text
drag-lint export enums --db C:\Projects\MyApp\_D-RAG\MyApp.sqlite --format delphi-const
```
This would print `MyApp`'s indexed enum types as Delphi const declarations.

---

[All features](../index.md) | [CLI reference](../cli.md) | [IDE menus](../ide.md)
