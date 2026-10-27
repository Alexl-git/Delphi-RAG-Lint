---
id: doc-comment-stub-symbol
title: Doc Comment Stub (symbol)
summary: Uses generate-docs to produce a doc-comment stub for one qualified symbol
product: DL
group: documentation
order: 40001
since: 0.25.0-alpha
status: shipped
updated: 1.35.1-alpha
---

# Doc Comment Stub (symbol)

Uses generate-docs to produce a doc-comment stub for one qualified symbol.

Read this when you want to start a DocInsight comment on one specific method, type or property. It produces a doc-comment stub for the chosen qualified symbol.

## How to run it

Full flag list: [generate-docs in the CLI reference](../cli.md#generate-docs).

## Flags

| Flag | Argument | Meaning | Default |
| --- | --- | --- | --- |
| `--qname` | `<Foo.TBar.Baz>` |  |  |
| `--format` |  |  |  |
| `--db` | `PATH` |  |  |

## Where to click

* RAD Studio main menu: **drag-lint > Generate & Export > Doc Comment Stub (symbol)...**
   1. Put the caret on the symbol in the editor
   2. Choose drag-lint > Generate & Export > Doc Comment Stub (symbol)...
   3. The doc-comment stub for the symbol is produced

## Details

Uses `generate-docs` to produce a doc-comment stub for one qualified symbol.
Reach for it to start a DocInsight comment on a specific method, type, or
property.

### Running it from the CLI
```text
drag-lint generate-docs --qname <Foo.TBar.Baz> [--format xmldoc|pasdoc] [--db PATH]
```
`--qname` is the fully qualified symbol; `--format` selects `xmldoc` or
`pasdoc` output.

### What it needs
The `--db` flag is optional -- drag-lint auto-resolves the project's index
when omitted. An index must still exist.

### Example
Illustrative only:
```text
drag-lint generate-docs --qname MyApp.TCustomerOrder.Total --format xmldoc --db C:\Projects\MyApp\_D-RAG\MyApp.sqlite
```
This would produce a doc-comment stub for the `Total` member of
`TCustomerOrder`.

---

[All features](../index.md) | [CLI reference](../cli.md) | [IDE menus](../ide.md)
