---
id: go-to-declaration
title: Go to Declaration
summary: Jumps the editor caret to the declaration of the symbol represented by a Structure-tree node
product: DL
group: search-navigation
order: 20012
since: 0.43.0-alpha
status: shipped
updated: 1.38.0-alpha
---

# Go to Declaration

Jumps the editor caret to the declaration of the symbol represented by a Structure-tree node.

Read this when you are in the Structure form and want the editor to jump to where a node's symbol is declared. Right-click the node and choose Go to Declaration; it is an editor jump with no command line equivalent.

## Where to click

* Right-click in the Structure form: **Go to Declaration**
   1. Open the Structure form (drag-lint > Show Structure)
   2. Right-click the node
   3. Choose Go to Declaration; the editor caret lands on the declaration

## Details

Jumps the editor caret to the declaration of the symbol represented by a
Structure-tree node. Reach for it when you are browsing the Structure outline
and want to land on where a symbol is declared, without first clicking into
the editor.

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
