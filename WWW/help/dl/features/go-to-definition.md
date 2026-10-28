---
id: go-to-definition
title: Go to Definition
summary: Jumps the editor caret to the declaration of the symbol under the cursor
product: DL
group: search-navigation
order: 20012
since: 0.47.0-alpha
status: shipped
updated: 1.36.0-alpha
---

# Go to Definition

Jumps the editor caret to the declaration of the symbol under the cursor.

Read this to jump straight to where the symbol under the cursor is declared. Choose drag-lint > Go to Definition; the plugin asks the drag-lint language server, so the project needs an index, and a pick list appears when several declarations match. There is no one-shot command line verb; use query --name for that.

## Where to click

* RAD Studio main menu: **drag-lint > Go to Definition**
   1. Needs an index of the project
   2. Put the editor caret on the symbol
   3. drag-lint > Go to Definition

## Details

Jumps the editor caret to the declaration of the symbol under the cursor.
Reach for it to navigate straight to where a symbol is defined.

### Running it from the CLI
There is no standalone CLI verb for this (feature map CliVerb:
"(none - in-process)"). The menu item sends a `textDocument/definition`
request (5 second limit) to the long-lived `drag-lint lsp --stdio` engine the
plugin keeps running, and jumps to the location it answers; with several
candidates (for example `ToUpper`) it lets you pick one. The same capability
is exposed over stdio to other editors -- the Features page lists
go-to-definition among the methods `drag-lint lsp` implements -- but that is a
stdio protocol server, not a one-shot CLI command.

### What it needs
The feature map marks this row's Index column "n/a" and its Mechanism
"in-process" -- no CLI verb is shelled out. It still depends on the language
server engine, which answers from the project's index, so the project must
be indexed for the jump to find anything ("definition not found" otherwise).
It needs an open editor with the caret on a symbol.

### Example
Illustrative: with the caret on a reference to `TCustomerOrder.Total` in
the editor, choose "Go to Definition" to jump to where `Total` is declared.

---

[All features](../index.md) | [CLI reference](../cli.md) | [IDE menus](../ide.md)
