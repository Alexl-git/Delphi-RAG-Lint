---
id: find-usages-context
title: Find Usages
summary: Lists references to the symbol represented by a Structure-tree node
product: DL
group: search-navigation
order: 20010
since: 0.33.0-alpha
status: shipped
updated: 1.38.0-alpha
---

# Find Usages

Lists references to the symbol represented by a Structure-tree node.

Read this when you are browsing the Structure form and want the usages of a symbol without first opening it in the editor. Right-click the tree node and choose Find Usages; it uses the usages verb behind the scenes.

## How to run it

Full flag list: [usages in the CLI reference](../cli.md#usages).

## Flags

| Flag | Argument | Meaning | Default |
| --- | --- | --- | --- |
| `--name` | `<X>` |  |  |
| `--width` |  |  |  |
| `--db` | `<path>` |  |  |
| `--depth` | `N` |  |  |
| `--format` |  |  |  |
| `--json` |  |  |  |

## Where to click

* Right-click in the Structure form: **Find Usages**
   1. Open the Structure form (drag-lint > Show Structure)
   2. Right-click the node
   3. Choose Find Usages

## Details

Lists references to the symbol represented by a Structure-tree node. Reach
for it when you are browsing the Structure outline and want the usages of a
symbol without first navigating to it in the editor and using the main
"Find Usages..." menu item (a separate, in-process feature-map row).

### Running it from the CLI

The feature map lists the underlying verb as `usages`. See the
[usages](usages.md) page for the full flag list; this page covers only the
right-click Structure-tree access path.

### What it needs

Optional, per the feature map's Index column.

### Example

Illustrative: with the Structure form open, right-click the node for
`TMyClass.DoWork` and choose "Find Usages" to list every reference to
`DoWork` across the indexed project.

---

[All features](../index.md) | [CLI reference](../cli.md) | [IDE menus](../ide.md)
