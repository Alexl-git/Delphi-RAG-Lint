---
id: doc-comment-stub-symbol
title: Doc Comment Stub (symbol)
summary: Uses generate-docs to produce a doc-comment stub for one qualified symbol
product: DL
group: documentation
order: 40001
since: 0.25.0-alpha
status: shipped
updated: 0.25.0-alpha
---

# Doc Comment Stub (symbol)

Uses generate-docs to produce a doc-comment stub for one qualified symbol.

## How to run it

Full flag list: [generate-docs in the CLI reference](../cli.md#generate-docs).

## Where to click

* RAD Studio main menu: **drag-lint > Generate & Export > Doc Comment Stub (symbol)...**

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

### Reaching it in the IDE
drag-lint > Generate & Export > Doc Comment Stub (symbol)...

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
