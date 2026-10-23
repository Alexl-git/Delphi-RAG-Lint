---
id: document-it
title: Document it
summary: Generates or repairs a managed DocInsight comment on the single symbol represented by a Structure-tree node
product: DL
group: documentation
order: 40005
since: 0.90.0-alpha
status: shipped
updated: 1.33.0-alpha
---

# Document it

Generates or repairs a managed DocInsight comment on the single symbol represented by a Structure-tree node.

Read this when one declaration needs a doc comment and you do not want to touch the rest of the unit. Right-click the symbol in the Structure form and choose Document it to generate or repair its managed DocInsight comment.

## How to run it

Full flag list: [document in the CLI reference](../cli.md#document).

## Flags

| Flag | Argument | Meaning | Default |
| --- | --- | --- | --- |
| `--qname` | `<Foo.TBar.Baz>` |  |  |
| `--apply` |  |  |  |
| `--json` |  |  |  |
| `--no-backup` |  |  |  |
| `--migrate-pure` |  |  |  |
| `--db` | `PATH` |  |  |

## Where to click

* Right-click in the Structure form: **Document it**
   1. Open the Structure form (drag-lint > Show Structure)
   2. Right-click the symbol node
   3. Choose Document it; its managed DocInsight comment is generated or repaired

## Details

Generates or repairs a managed DocInsight comment on the single symbol
represented by a Structure-tree node. Reach for it when one declaration
needs a doc comment and you do not want to touch the rest of the unit.

### Reaching it in the IDE

This is a RIGHT-CLICK action, not a main-menu item. Menu path: "Structure
form (right-click a tree node)".

To reach it: open the Structure form first (drag-lint > Show Structure),
then right-click a node in the tree and choose "Document it".

### Running it from the CLI

The feature map lists the underlying verb as `document`. From the usage
banner, the single-symbol form:

```text
drag-lint document --qname <Foo.TBar.Baz> [--apply|--json|--no-backup] [--db PATH]
```

Generates/repairs a managed DocInsight comment for that one qualified name.

### What it needs

Optional, per the feature map's Index column.

### Example

Illustrative:

```text
drag-lint document --qname Unit1.TMyClass.DoWork --apply --db C:\Projects\MyApp\_D-RAG\MyApp.sqlite
```

This would write a managed DocInsight comment onto `DoWork`.

---

[All features](../index.md) | [CLI reference](../cli.md) | [IDE menus](../ide.md)
