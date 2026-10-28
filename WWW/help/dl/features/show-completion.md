---
id: show-completion
title: Show Completion
summary: Shows an index-backed completion list at the editor caret
product: DL
group: search-navigation
order: 20025
since: 0.21.0-alpha
status: shipped
updated: 1.36.0-alpha
---

# Show Completion

Shows an index-backed completion list at the editor caret.

Read this when you want to know what you can type next at the editor caret: it shows an index-backed completion list, bound to Ctrl+Alt+C.

## Where to click

* RAD Studio main menu: **drag-lint > Show Completion**
   1. Put the caret in the editor where you want a completion
   2. Choose drag-lint > Show Completion
   3. Pick an entry from the list

## Details

Shows an index-backed completion list at the editor caret. Reach for it to
see what identifiers are valid to type next.

### Running it from the CLI
There is no standalone CLI verb for this (feature map CliVerb:
"(none - in-process)"). It is served in-process by the IDE plugin. The
bundled language server exposes completion over stdio to other editors --
the Features page lists completion among the methods
`drag-lint lsp` implements -- but that is a stdio protocol server, not a
one-shot CLI command.

### What it needs
The feature map marks this row's Index column "n/a" and its Mechanism
"in-process". It needs an open editor buffer with the caret positioned
where completion is requested.

### Example
Illustrative: type a partial identifier in the editor and press Ctrl+Alt+C
to show the completion list for what follows.

---

[All features](../index.md) | [CLI reference](../cli.md) | [IDE menus](../ide.md)
