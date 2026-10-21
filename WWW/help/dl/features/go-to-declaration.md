---
id: go-to-declaration
title: Go to Declaration
summary: Jumps the editor caret to the declaration of the symbol represented by a Structure-tree node
product: DL
group: search-navigation
order: 20010
since: 0.0.0
status: shipped
updated: 1.33.0-alpha
---

# Go to Declaration

Jumps the editor caret to the declaration of the symbol represented by a Structure-tree node.

Read this when you are browsing the Structure form and want to land on where a symbol is declared. Right-click the tree node and choose Go to Declaration; it is an editor jump with no command line equivalent and needs no index.

## Where to click

* Right-click in the Structure form: **Go to Declaration**

## Details

Jumps the editor caret to the declaration of the symbol represented by a
Structure-tree node. Reach for it when you are browsing the Structure outline
and want to land on where a symbol is declared, without first clicking into
the editor.

### Reaching it in the IDE

This is a RIGHT-CLICK action, not a main-menu item. Menu path: "Structure
form (right-click a tree node)".

To reach it: open the Structure form first (drag-lint > Show Structure),
then right-click a node in the tree and choose "Go to Declaration".

### Running it from the CLI

No CLI equivalent - this is an editor navigation action.

### What it needs

Not needed. The feature map marks this row's Index column "n/a" and its
Mechanism "in-process" -- it does not shell out to the CLI or query an index
database.

### Example

Illustrative: with the Structure form open and showing the current unit,
right-click the node for `TMyForm.ButtonClick` and choose "Go to
Declaration". The editor jumps to the line where `TMyForm.ButtonClick` is
declared.

---

[All features](../index.md) | [CLI reference](../cli.md) | [IDE menus](../ide.md)
