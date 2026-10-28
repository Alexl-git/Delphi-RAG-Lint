---
id: hover-at-cursor
title: Hover at Cursor
summary: "Shows a hover card for the symbol under the editor caret: signature, documentation, and callers"
product: DL
group: search-navigation
order: 20015
since: 0.7.0-alpha
status: shipped
updated: 1.36.0-alpha
---

# Hover at Cursor

Shows a hover card for the symbol under the editor caret: signature, documentation, and callers.

Read this to check what a symbol is and who calls it without leaving the line you are on. With the caret on it choose drag-lint > Hover at Cursor (Ctrl+Alt+H); on the command line, hover --qname Foo.Bar gives the same card.

## How to run it

Full flag list: [hover in the CLI reference](../cli.md#hover).

## Flags

| Flag | Argument | Meaning | Default |
| --- | --- | --- | --- |
| `--qname` | `<Foo.Bar>` |  |  |
| `--db` | `<file.sqlite>` |  |  |
| `--format` |  |  |  |

## Where to click

* RAD Studio main menu: **drag-lint > Hover at Cursor**
   1. Needs an index of the project
   2. Put the editor caret on the symbol
   3. drag-lint > Hover at Cursor

## Details

Shows a hover card for the symbol under the editor caret: signature,
documentation, and callers. Reach for it to check what a symbol is and how
it is used without leaving the line you are on.

### Running it from the CLI
In the IDE this action is served in-process (the feature map's Mechanism
column marks it "in-process") -- no exe is spawned per hover. The same
capability is also exposed as a standalone CLI verb, and over stdio by the
bundled language server (the Features page lists hover among
the methods `drag-lint lsp` implements):
```text
drag-lint hover --qname <Foo.Bar> [--db <file.sqlite>] [--format plain|md|json]
```
`--qname` is the fully qualified symbol; `--format` selects plain text,
markdown, or JSON.

### What the card says about effects

A routine the purity analysis PROVED changes nothing outside its own locals
carries the analysis fact **Effect-free (proven)**. The JSON form
(`hover --format json`) carries the verdict for every routine as
`effect_free` (1 / 0), `effect_summary` (tokens: `g` globals, `h` heap, `s` own
fields, `p<k>` parameter k, `?` not analysable) and `effect_witness` (the first
effect in words, e.g. `writes through parameter #1 (AReason)`). Every token,
and the difference between an empty summary and a missing one, is spelled out
in the [Effect Summary Legend](effect-summary-legend.md). Older builds
printed `Pure`; that word is no longer emitted. For the same data as a chart,
see `ask effects`.

Hovering a forward declaration (`TFoo = class;`) shows the REAL declaration,
led by `forward declaration -> line N`.

### What it needs
The `--db` flag is optional -- drag-lint auto-resolves the index when
omitted. An index must still exist. In the IDE, it also needs an open
editor with the caret on a symbol.

### Example
Illustrative only:
```text
drag-lint hover --qname CustomerOrder.TCustomerOrder.Total --db C:\Projects\MyApp\_D-RAG\MyApp.sqlite --format md
```
This would print the hover card for the `Total` member of `TCustomerOrder`
as markdown.

---

[All features](../index.md) | [CLI reference](../cli.md) | [IDE menus](../ide.md)
