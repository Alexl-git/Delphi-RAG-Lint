---
id: hover-at-cursor
title: Hover at Cursor
summary: "Shows a hover card for the symbol under the editor caret: signature, declared type, documentation, and callers"
product: DL
group: search-navigation
order: 20016
since: 0.7.0-alpha
status: shipped
updated: 1.38.0-alpha
---

# Hover at Cursor

Shows a hover card for the symbol under the editor caret: signature, declared type, documentation, and callers.

Read this to check what a symbol is and who calls it without leaving the line you are on. With the caret on it choose drag-lint > Hover at Cursor (Ctrl+Alt+H); on the command line, hover --qname Foo.Bar gives the same card. The IDE never waits for the engine: the card appears when the answer arrives, and a busy engine shows 'drag-lint: engine busy' instead of freezing the editor.

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
markdown, or JSON. Hover never writes the index.

### What the card says about types

A property, field, var, const, parameter or local variable shows its declared
type (`Text: string`). A bare re-publication such as `property Text;` stores no
type in the source, so `index` fills it in: its last link stage, `prop-types`,
takes the type from the nearest ancestor that declares it (bridging an unlinked
ancestor by scope, the converter's climb) and stores it on the row as
`: <type>`, generics intact (`TDictionary<string, Integer>`); a type it cannot
find is never stored. A run that parsed files re-checks the bare rows of those
files plus every same-named row of the properties they declare, so editing the
ancestor's type updates the re-publications in unchanged units too (renaming or
removing the declaring property, or re-parenting a class, is seen after a
`--rebuild`); a run that parsed nothing skips the
stage once the index carries its `prop_types_filled` marker, so an index built
by an older engine is filled by its next plain `index` run. The card names the
declaring class: `Text: string (declared in dxBar.TdxBarWindowItem)`. The JSON
form carries the same as `type` and `declared_in`, and `signature` holds the
type. Hover and the language server (which opens its indexes read-only) read
the stored type; the ancestor name is found per session and cached.
(`hover --write-back`, the 2026-10-29 opt-in that stored the type at hover time,
was removed the same day: the index-time fill made it redundant.)

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

### When the engine is slow
The IDE never waits for the engine. A hover (the menu command or a mouse
dwell) is sent and the card appears when the answer arrives:

* A mouse-dwell card is shown only if the pointer is still over the same
  editor and the same identifier (anywhere along it, and within about half a
  line above or below). Otherwise the answer is dropped; pointing back at the
  identifier shows it at once from the cache.
* Only one dwell hover is asked at a time. Moving to another identifier
  cancels the previous question.
* If the engine has left a question unanswered for about 3 seconds, the status
  strip reads `drag-lint: engine busy` and no new hover is asked; findings on
  the line still show. An engine silent for 60 seconds with questions pending
  is restarted automatically.

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
