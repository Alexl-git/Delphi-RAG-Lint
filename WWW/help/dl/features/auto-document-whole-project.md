---
id: auto-document-whole-project
title: Auto-Document Whole Project
summary: Writes DocInsight documentation into every public declaration a project owns
product: DL
group: indexing
order: 10001
since: 0.1.0-alpha
status: shipped
updated: 1.38.0-alpha
---

# Auto-Document Whole Project

Writes DocInsight documentation into every public declaration a project owns.

Read this when a whole project needs documentation coverage instead of symbol-by-symbol work. It writes DocInsight comments into every public declaration the project owns, as a batch of reindex, document and reindex.

## How to run it

Full flag list: [index in the CLI reference](../cli.md#index).

Full flag list: [document in the CLI reference](../cli.md#document).

## Flags

| Flag | Argument | Meaning | Default |
| --- | --- | --- | --- |
| `--db` | `<file.sqlite>` |  |  |
| `--watch` |  |  |  |
| `--interval` | `N` |  |  |
| `--library-db` | `<lib.sqlite>` | consult another index for calls THIS one cannot resolve (value receivers typed by name bind too; the manifest key libraryResolve opts a section in). |  |
| `--wait-library` | `<min>` | when the platform library of a libraryResolve section is NOT READY, probe every 30 s up to `min` minutes, then continue (marked pending). |  |
| `--require-library` |  | a not-ready platform library is ERROR, exit 2, instead of continuing against the project only. |  |
| `--max-file-kb` | `N` |  |  |
| `--no-use-ignore` |  |  |  |
| `--no-sql-ms` |  |  |  |
| `--deep` |  |  |  |
| `--shallow` |  |  |  |
| `--exclude-under` |  |  |  |
| `--include-only` |  |  |  |
| `--qname` | `<Foo.TBar.Baz>` |  |  |
| `--apply` |  |  |  |
| `--json` |  |  |  |
| `--no-backup` |  |  |  |
| `--migrate-pure` |  |  |  |
| `--db` | `PATH` |  |  |

## Where to click

* RAD Studio main menu: **drag-lint > Generate & Export > Auto-Document Whole Project...**
   1. Choose drag-lint > Generate & Export > Auto-Document Whole Project...
   2. Follow the dialog
   3. The batch reindexes, documents every public declaration the project owns, then reindexes again

## Details

Writes DocInsight documentation into every public declaration a project owns.
Reach for it to bulk-document a project rather than symbol by symbol.

### Running it from the CLI
This runs as a 3-step batch, not a single command:
```text
drag-lint index --project <file.dproj> --db <db>
drag-lint document --project <file.dproj> --apply --db <db>
drag-lint index --project <file.dproj> --db <db>
```
Step 1 freshens the index. Step 2 writes documentation into every public
declaration the project owns (`--apply` commits the edits; without it the
command only previews). Step 3 re-indexes: `--apply` shifts line numbers in
the files it edited, and the index has to reflect the new positions before
it is trusted again.

`document --project` also accepts `--stubs`, `--json`, `--no-backup`,
`--include-accessors`, `--reindex` (self-freshens the index after applying,
folding steps 2-3 into one call), and `--document-third-party`.

### What it needs
An active project. Unusually for this tool, **no pre-existing index is
required**: step 1 of the batch is an `index` run, and indexing creates the
database if it is missing and re-parses only stale or absent files. So this
action is safe to run on a project that has never been indexed -- it will
simply do the indexing first.

The `--db` flag is optional when you run `document` yourself -- drag-lint
auto-resolves the project's index when it is omitted.

### Example
Illustrative only:
```text
drag-lint document --project C:\Projects\MyApp\MyApp.dproj --apply --db C:\Projects\MyApp\_D-RAG\MyApp.sqlite
```
This would document every public declaration `MyApp.dproj` owns, followed by
a re-index of the same project and DB.

---

[All features](../index.md) | [CLI reference](../cli.md) | [IDE menus](../ide.md)
