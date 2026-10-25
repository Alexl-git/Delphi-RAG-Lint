---
id: rename-symbol
title: Rename Symbol
summary: Renames a symbol across the whole indexed project
product: DL
group: refactoring
order: 50010
since: 0.24.0-alpha
status: shipped
updated: 1.34.1-alpha
---

# Rename Symbol

Renames a symbol across the whole indexed project.

Read this instead of a text find and replace when a symbol appears in many units. It renames the symbol and every reference the index knows about across the indexed project in one step (Ctrl+Alt+R in the IDE).

## How to run it

Full flag list: [rename in the CLI reference](../cli.md#rename).

## Flags

| Flag | Argument | Meaning | Default |
| --- | --- | --- | --- |
| `--kind` |  |  |  |
| `--name` | `<QName>` |  |  |
| `--to` | `<New>` |  |  |
| `--json` |  |  |  |
| `--apply` |  |  |  |
| `--no-backup` |  |  |  |
| `--db` | `<db>` |  |  |

## Where to click

* RAD Studio main menu: **drag-lint > Rename Symbol...**
   1. Put the caret on the symbol in the editor (Ctrl+Alt+R)
   2. Choose drag-lint > Rename Symbol...
   3. Enter the new name and review the affected places
   4. Confirm; backups are written unless disabled

**Needs:** index

## Details

Renames a symbol across the whole indexed project. Reach for it instead of
a text find/replace when a symbol appears in many units, so every
reference is updated together.

### Reaching it in the IDE
drag-lint > Rename Symbol...

Keyboard shortcut: Ctrl+Alt+R.

### Running it from the CLI
The feature map's Mechanism column marks this row "delegates" -- the menu
item runs the CLI `rename` verb rather than an in-process edit:
```text
drag-lint rename --kind symbol --name <QName> --to <New> [--json|--apply|--no-backup] --db <db>
```
Two related forms also exist: `--kind param --file <F> --line <L> --col <C> --to <New> [...]` for a routine-local parameter/var rename, and
`--qname <Foo.TBar.Baz> --to <NewName> [--db PATH] [--dry-run] [--no-backup]`.
Without `--apply` (or with `--dry-run`), the run is a preview only.

**Include files.** The index records no references inside `{$I}` included
text yet (extractor 1.22). So when the old name is used as an identifier in an
`.inc` file the index holds (comments and string literals are ignored), both
the preview and `--apply` REFUSE with exit 2 and name the `.inc` file(s),
instead of renaming the declaration and leaving those uses stale. Rename the
include's uses by hand together with the declaration.

### Same-named handlers and .dfm bindings
A handler name shared by several forms (for example `Button1Click`) is renamed
only on the form that owns the symbol being renamed, and on forms that inherit
from it. A same-named handler declared on any other form is left untouched, and
so is its `.dfm` binding. The `.dfm` event bindings (`OnClick = Button1Click`)
that point at the renamed handler are rewritten with the declaration, again only
for the owner form and the forms inheriting from it. `--apply` keeps each file's
encoding, BOM and line breaks. Known limits: references the index cannot bind
are still matched by name, and an unindexed or binary `.dfm` is skipped
silently.

### What it needs
An index IS required. The project's DB lives at
`<project folder>\_D-RAG\<project file>.sqlite`; run
`drag-lint resolve-dbs --project <X.dproj>` if unsure.

### Example
Illustrative only:
```text
drag-lint rename --kind symbol --name CustomerOrder.TCustomerOrder.Total --to GrandTotal --db C:\Projects\MyApp\_D-RAG\MyApp.sqlite --apply
```
This would rename `Total` to `GrandTotal` everywhere it is referenced in
the index.

---

[All features](../index.md) | [CLI reference](../cli.md) | [IDE menus](../ide.md)
