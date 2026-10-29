# Hover at Cursor

Shows a hover card for the symbol under the editor caret: signature,
documentation, and callers. Reach for it to check what a symbol is and how
it is used without leaving the line you are on.

## Reaching it in the IDE
drag-lint > Hover at Cursor

Keyboard shortcut: Ctrl+Alt+H.

## Running it from the CLI
In the IDE this action is served in-process (the feature map's Mechanism
column marks it "in-process") -- no exe is spawned per hover. The same
capability is also exposed as a standalone CLI verb, and over stdio by the
bundled language server (the [Features](Features) page lists hover among
the methods `drag-lint lsp` implements):
```
drag-lint hover --qname <Foo.Bar> [--db <file.sqlite>] [--format plain|md|json]
```
`--qname` is the fully qualified symbol; `--format` selects plain text,
markdown, or JSON. Hover never writes the index.

## What the card says about types

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

## What the card says about effects

A routine the purity analysis PROVED changes nothing outside its own locals
carries the analysis fact **Effect-free (proven)**. The JSON form
(`hover --format json`) carries the verdict for every routine as
`effect_free` (1 / 0), `effect_summary` (tokens: `g` globals, `h` heap, `s` own
fields, `p<k>` parameter k, `?` not analysable) and `effect_witness` (the first
effect in words, e.g. `writes through parameter #1 (AReason)`). Every token,
and the difference between an empty summary and a missing one, is spelled out
in the [Effect Summary Legend](Effect-Summary-Legend). Older builds
printed `Pure`; that word is no longer emitted. For the same data as a chart,
see [`ask effects`](ask-effects).

Hovering a forward declaration (`TFoo = class;`) shows the REAL declaration,
led by `forward declaration -> line N`.

## What it needs
The `--db` flag is optional -- drag-lint auto-resolves the index when
omitted. An index must still exist. In the IDE, it also needs an open
editor with the caret on a symbol.

## Example
Illustrative only:
```
drag-lint hover --qname CustomerOrder.TCustomerOrder.Total --db C:\Projects\MyApp\_D-RAG\MyApp.sqlite --format md
```
This would print the hover card for the `Total` member of `TCustomerOrder`
as markdown.
