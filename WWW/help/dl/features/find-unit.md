---
id: find-unit
title: find-unit
summary: Finds which indexed unit declares a symbol, and adds that unit to a file's uses clause
product: DL
group: search-navigation
order: 20008
since: 0.69.0-alpha
status: shipped
updated: 1.38.0-alpha
---

# find-unit

Finds which indexed unit declares a symbol, and adds that unit to a file's uses clause.

Read this when a symbol is undeclared and you need the unit to add to uses. find-unit --name X --in file looks the declaring unit up in the index and can add it to the file (--apply, with a backup unless --no-backup). Without --apply it is a dry run: it prints the uses-clause edit, exits 0 and writes nothing (--json prints the edit set and never writes). Exit 0 for a preview, an applied edit or a unit already in uses; 1 when no unit declares the symbol or no edit can be computed; 2 on missing arguments or no database.

## How to run it

Full flag list: [find-unit in the CLI reference](../cli.md#find-unit).

## Flags

| Flag | Argument | Meaning | Default |
| --- | --- | --- | --- |
| `--name` | `<Symbol>` |  |  |
| `--in` | `<file>` |  |  |
| `--json` |  |  |  |
| `--apply` |  |  |  |
| `--no-backup` |  |  |  |
| `--db` | `<db>` |  |  |

## Where to click

* RAD Studio main menu: **drag-lint > Uses & Dependencies > Find Unit for Symbol (add to uses)...**
   1. Needs an index; for an RTL/VCL symbol use the platform library DB
   2. drag-lint > Uses & Dependencies > Find Unit for Symbol (add to uses)...
   3. The declaring unit is named; Yes adds it to the active unit's uses clause, No previews a dry run

**Needs:** index

## Pitfalls

* for an RTL/VCL/third-party X, point --db at the PLATFORM LIBRARY database (resolve-dbs --platform win64) -- a project DB holds only that project's units.

## Details

Finds which indexed unit declares a symbol, and adds that unit to a file's
`uses` clause. Reach for it when a symbol is undeclared and you want the fix
looked up straight from the index.

### Running it from the CLI

```text
drag-lint find-unit --name <Symbol> --in <file> [--json|--apply|--no-backup] --db <db>
```

`--name` is the undeclared symbol; `--in` is the file to add the `uses`
entry to. `--db` is required (not bracketed in the usage line). The usage
line lists `--apply` as a flag; whether omitting it produces a dry run is
not documented in the help text for this verb.

### What it needs

An index IS required. The project's DB lives at
`<project folder>\_D-RAG\<project file>.sqlite`; run
`drag-lint resolve-dbs --project <X.dproj>` if unsure.

### Example

Illustrative:

```text
drag-lint find-unit --name TStringList --in C:\Projects\MyApp\Unit1.pas --apply --db C:\Projects\MyApp\_D-RAG\MyApp.sqlite
```

This would look up which indexed unit declares `TStringList` and add it to
`Unit1.pas`'s `uses` clause.

---

[All features](../index.md) | [CLI reference](../cli.md) | [IDE menus](../ide.md)
