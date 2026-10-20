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

## What the marker changes in generated docs -- project tags

A unit marked `dl:shared` -- or any doc block that holds facts the current
index cannot see, such as a production unit whose `Called from:` names callers
in a separate test project -- is documented as the UNION of what every project
sees, and since 2026-09-23 each inbound entry (`Called from:`, `Used by:`,
`Used in units:`) says which projects rendered it:

```
/// <para>Called from: [DataCopy,DataCopyTests]uX.Foo (uX.pas), [DataCopyTests]Test.X.Bar (Test.X.pas)</para>
```

* The tag is the `--db` base name (`_D-RAG\DataCopy.sqlite` -> `DataCopy`).
  With more than one `--db` no tag is written or removed.
* A `document` run adds its own tag to what it renders and removes its own tag
  from what it no longer renders; an entry goes when its set empties. Other
  projects' tags are never touched, so one project can no longer delete what
  another contributed.
* Untagged entries written before tags existed keep the old rules: kept while
  this index cannot see their unit. A wholly untagged line that has not changed
  is left alone; once any project tags a line, the others adopt their entries
  on their next run (one write per project per line).
* Lists on such a block are never windowed as `(+N more)`.

`doc-forget` reaps tags directly, without an index -- for a project that was
retired or renamed:

```
drag-lint doc-forget --scope <file.pas|dir> --list-tags
drag-lint doc-forget --scope <file.pas|dir> --project OldApp [--apply]
drag-lint doc-forget --scope <file.pas|dir> --rename OldApp=NewApp [--apply]
drag-lint doc-forget --scope <file.pas|dir> --untagged [--apply]
```
