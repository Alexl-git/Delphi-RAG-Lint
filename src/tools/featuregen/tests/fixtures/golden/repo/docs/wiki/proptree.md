# proptree

Recursive deep-property enumerator for a class: flattens its own and
inherited properties into dotted paths, recursing into class-typed
properties. Reach for it to see a class's full property surface, including
nested sub-objects, without walking the class hierarchy by hand.

## Running it from the CLI
```
drag-lint proptree --qname <X> [--depth N] [--no-to-persistent] [--refs-as-leaves] [--no-write-back] [--min-visibility published|public] [--format text|json] [--json] --db PATH [--db ...]
```
`--qname <X>` is the class to enumerate. `--depth N` bounds recursion.
`--no-to-persistent` is present in the usage line; its effect is not
documented beyond the flag name. `--refs-as-leaves` leaves
`TComponent`-typed properties unexpanded (treated as references, not owned
sub-objects). Types recovered by the ancestry-bridge are memoized back into
the index automatically unless `--no-write-back` is given, which forces a
read-only, non-mutating query. `--min-visibility published|public` filters
emitted leaves by effective visibility (default: all). `--format text|json`
selects output format; `--db PATH` may be repeated.

## Reaching it in the IDE
No IDE surface -- this is a CLI-only feature.

## What it needs
An index IS required. The project's DB lives at
`<project folder>\_D-RAG\<project file>.sqlite`; run
`drag-lint resolve-dbs --project <X.dproj>` if unsure.

## Example
Illustrative only:
```
drag-lint proptree --qname CustomerOrder.TCustomerOrder --depth 2 --min-visibility published --db C:\Projects\MyApp\_D-RAG\MyApp.sqlite --format text
```
This would print `TCustomerOrder`'s published properties, up to 2 levels
deep into any class-typed properties.
