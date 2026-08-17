# shared-unit

Reads or extends the `dl:shared` marker on a unit, recording which projects
share it. Reach for it when a unit is used by more than one project and you
want that fact recorded in the source itself.

## Running it from the CLI

```
drag-lint shared-unit --in <file.pas> [--add-project <name>] [--apply] [--json]
```

`--in` is the unit file. `--add-project <name>` adds a project name to the
marker. Per the usage banner, this is a dry run without `--apply`:
"read/extend the dl:shared marker; dry-run without --apply".

## Reaching it in the IDE

No IDE surface -- this is a CLI-only feature.

## What it needs

No index required -- the usage line has no `--db` flag; `shared-unit` reads
and writes the `dl:shared` marker directly in the given file.

## Example

Illustrative:

```
drag-lint shared-unit --in C:\Projects\Common\SharedUtils.pas --add-project MyApp --apply
```

This would add `MyApp` to `SharedUtils.pas`'s `dl:shared` marker.
