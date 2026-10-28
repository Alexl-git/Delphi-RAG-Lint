---
id: go-to-implementation
title: Go to Implementation
summary: Jumps the editor caret to the implementation of the symbol represented by a Structure-tree node
product: DL
group: search-navigation
order: 20013
since: 0.43.0-alpha
status: shipped
updated: 1.36.0-alpha
---

# Go to Implementation

Jumps the editor caret to the implementation of the symbol represented by a Structure-tree node.

Read this when a Structure form node is a declaration (such as an interface method) and you want its implementation body. Right-click the node and choose Go to Implementation; it is an editor jump that needs no index.

## Where to click

* Right-click in the Structure form: **Go to Implementation**
   1. Open the Structure form (drag-lint > Show Structure)
   2. Right-click the declaration node
   3. Choose Go to Implementation; the caret lands on the implementation body

## Details

Jumps the editor caret to the implementation of the symbol represented by a
Structure-tree node. Reach for it when the tree node you are on is a
declaration (for example an interface method or a forward-declared routine)
and you want the actual implementation body instead.

### Running it from the CLI

No CLI equivalent - this is an editor navigation action.

### What it needs

Not needed. The feature map marks this row's Index column "n/a" and its
Mechanism "in-process" -- it does not shell out to the CLI or query an index
database.

### Example

Illustrative: with the Structure form open, right-click the node for
`TMyClass.DoWork` and choose "Go to Implementation". The editor jumps to the
`procedure TMyClass.DoWork;` body in the implementation section.

---

[All features](../index.md) | [CLI reference](../cli.md) | [IDE menus](../ide.md)
