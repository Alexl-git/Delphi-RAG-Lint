---
id: type-at-cursor
title: Type at Cursor
summary: Resolves the static type of the expression under the editor caret
product: DL
group: search-navigation
order: 20034
since: 0.19.0-alpha
status: shipped
updated: 1.46.0-alpha
---

# Type at Cursor

Resolves the static type of the expression under the editor caret.

Read this when you are not sure what type an expression has: Type at Cursor resolves the static type of the expression under the editor caret.

## How to run it

Full flag list: [typeat in the CLI reference](../cli.md#typeat).

## Flags

| Flag | Argument | Meaning | Default |
| --- | --- | --- | --- |
| `--db` | `<file.sqlite>` |  |  |
| `--format` |  |  |  |

## Where to click

* RAD Studio main menu: **drag-lint > Inspect Symbol > Type at Cursor**
   1. Put the caret on the expression in the editor
   2. Choose drag-lint > Inspect Symbol > Type at Cursor
   3. The resolved type is shown
   4. From a shell: `drag-lint typeat <file>:<line>:<col>`

## Details

Resolves the static type of the expression under the editor caret. Reach
for it when you are not sure what type an expression evaluates to.

### Running it from the CLI
```text
drag-lint typeat <file>:<line>:<col> [--db <file.sqlite>] [--format text|json]
```
The position is given as `<file>:<line>:<col>`; `--format` selects text or
JSON.

When the index holds a stored type for the reference at that position (the
`ref_types` table, from 1.44), the answer adds it: a `StaticType:` line in
text, `static_type` and `static_type_via` in JSON. `Resolved:` names the symbol,
`StaticType:` the type the reference has: on `TThing.Create` the resolved symbol
may be an inherited `TBase.Create` while the static type is `TThing`. An older
index has no such table and gets the rest of the answer unchanged. See
[schema](schema.md).

### What it needs
The `--db` flag is optional -- drag-lint auto-resolves the index when
omitted. An index must still exist.

### Example
Illustrative only:
```text
drag-lint typeat C:\Projects\MyApp\Orders.pas:42:15 --db C:\Projects\MyApp\_D-RAG\MyApp.sqlite
```
This would report the static type of the expression at line 42, column 15
of `Orders.pas`.

---

[All features](../index.md) | [CLI reference](../cli.md) | [IDE menus](../ide.md)
