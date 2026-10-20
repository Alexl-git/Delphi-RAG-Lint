# query typecat

Resolves a type's category -- float, string, class, interface, and so on.
Reach for it when you need to know what kind of type a name refers to
before writing code against it.

## Running it from the CLI

```
drag-lint query typecat --name <type> [--db ...] [--json]
```

`--name` is the type to resolve.

## Reaching it in the IDE

No IDE surface -- this is a CLI-only feature.

## What it needs

The `--db` flag is optional -- drag-lint auto-resolves the index when
omitted. An index must still exist.

## Example

Illustrative:

```
drag-lint query typecat --name Currency --db C:\Projects\MyApp\_D-RAG\MyApp.sqlite
```

This would report which type category `Currency` resolves to.
