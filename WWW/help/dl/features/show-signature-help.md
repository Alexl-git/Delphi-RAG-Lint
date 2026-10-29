---
id: show-signature-help
title: Show Signature Help
summary: Shows parameter help for the call being typed at the editor caret
product: DL
group: search-navigation
order: 20028
since: 0.21.0-alpha
status: shipped
updated: 1.38.0-alpha
---

# Show Signature Help

Shows parameter help for the call being typed at the editor caret.

Read this while writing a call and you need the parameter list and order of the routine: it shows signature help at the caret, bound to Ctrl+Alt+S.

## Where to click

* RAD Studio main menu: **drag-lint > Show Signature Help**
   1. Put the caret inside the call's parentheses in the editor
   2. Choose drag-lint > Show Signature Help
   3. The parameter help for the routine is shown

## Details

Shows parameter help for the call being typed at the editor caret. Reach
for it to check a routine's parameter list and order while writing a call.

### Running it from the CLI
There is no standalone CLI verb for this (feature map CliVerb:
"(none - in-process)"). It is served in-process by the IDE plugin. The
bundled language server exposes signature help over stdio to other editors
-- the Features page lists signature help among the methods
`drag-lint lsp` implements -- but that is a stdio protocol server, not a
one-shot CLI command.

### What it needs
The feature map marks this row's Index column "n/a" and its Mechanism
"in-process". It needs an open editor with the caret inside a call's
argument list.

### Example
Illustrative: position the caret inside the parentheses of a call to
`TCustomerOrder.Create(...)` and press Ctrl+Alt+S to show that
constructor's parameter help.

---

[All features](../index.md) | [CLI reference](../cli.md) | [IDE menus](../ide.md)
