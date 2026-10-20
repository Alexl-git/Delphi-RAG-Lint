# query ancestors

Resolves the transitive class/interface hierarchy of a type. Reach for it
to see everything a type descends from -- or to check whether it descends
from one specific ancestor -- read straight from the index.

## Running it from the CLI

```
drag-lint query ancestors --name <type> [--of <ancestor>] [--db ...] [--json]
```

`--name` is the type to resolve. `--of <ancestor>` narrows the query to a
specific ancestor.

## Reaching it in the IDE

No IDE surface -- this is a CLI-only feature.

## What it needs

The `--db` flag is optional -- drag-lint auto-resolves the index when
omitted. An index must still exist.

## Example

Illustrative:

```
drag-lint query ancestors --name TMyForm --db C:\Projects\MyApp\_D-RAG\MyApp.sqlite
```

This would list `TMyForm`'s full transitive ancestor chain.
