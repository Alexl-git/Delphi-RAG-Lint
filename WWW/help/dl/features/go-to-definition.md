---
id: go-to-definition
title: Go to Definition
summary: Jumps the editor caret to the declaration of the symbol under the cursor
product: DL
group: search-navigation
order: 20011
since: 0.0.0
status: shipped
updated: 1.32.0-alpha
---

# Go to Definition

Jumps the editor caret to the declaration of the symbol under the cursor.

## Where to click

* RAD Studio main menu: **drag-lint > Go to Definition**

## Details

Jumps the editor caret to the declaration of the symbol under the cursor.
Reach for it to navigate straight to where a symbol is defined.

### Reaching it in the IDE
drag-lint > Go to Definition

No keyboard shortcut is documented for this menu item.

### Running it from the CLI
There is no standalone CLI verb for this (feature map CliVerb:
"(none - in-process)"). It is served in-process by the IDE plugin. The
bundled language server exposes the same capability over stdio to other
editors -- the Features page lists go-to-definition among the
methods `drag-lint lsp` implements -- but that is a stdio protocol server,
not a one-shot CLI command.

### What it needs
The feature map marks this row's Index column "n/a" and its Mechanism
"in-process" -- it does not shell out to the CLI or query an index database
through a verb. It needs an open editor with the caret on a symbol.

### Example
Illustrative: with the caret on a reference to `TCustomerOrder.Total` in
the editor, choose "Go to Definition" to jump to where `Total` is declared.

---

[All features](../index.md) | [CLI reference](../cli.md) | [IDE menus](../ide.md)
