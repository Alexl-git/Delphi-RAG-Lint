# query --kind --all

Lists every symbol of one kind -- every unit, every class, every enum -- with
no name, no doc clause and no row cap. Reach for it when you need the complete
set, for example every unit in a project or library index to fill a picker.

## Running it from the CLI

```
drag-lint query --kind <kind> --all [--public] [--db ...] [--json]
```

`--kind` is required (`unit`, `class`, `interface`, `record`, `enum`,
`procedure`, `function`, `method`, `property`, `field`, ...). `--public` keeps
only symbols usable from other units. `--json` prints one object per symbol
with its file.

Do not use `query find --no-docs --kind unit` for this: `--no-docs` is a
FILTER that keeps only UNDOCUMENTED symbols. On a library index it listed
2,103 of 5,646 units. `sql` works too, but its default row cap is 200.

## Reaching it in the IDE

No IDE surface -- this is a CLI-only feature.

## What it needs

The `--db` flag is optional -- drag-lint auto-resolves the index when
omitted. An index must still exist.

## Example

Illustrative:

```
drag-lint query --kind unit --all --json --db C:\Projects\.drag-lint\library-Win64.sqlite
```

This would print every unit the Win64 platform library index holds.
