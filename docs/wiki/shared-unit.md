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
/// <para>Called from: [MyTool,MyToolTests]uX.Foo (uX.pas), [MyToolTests]Test.X.Bar (Test.X.pas)</para>
```

* The tag is the `--db` base name (`_D-RAG\MyTool.sqlite` -> `MyTool`).
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
* `Registered as:` is tagged the same way since 1.54.1, because two projects
  that compile one unit have their own DI registrations:

  ```
  /// <para>Registered as: [CliApp]IFoo (singleton), [SrvApp]IFoo (transient)</para>
  ```

  It applies to every block of a unit that is marked `dl:shared`, or whose file
  holds a project tag or a fact naming a unit this index does not hold (usually
  the other project's registrar in `Used by:`). A unit of one project is never
  tagged. An untagged line from before is tagged once by the project that
  renders it; the other projects leave it as it stands, except where they
  register the same interface themselves. When both registrars are units of the same
  name, or both are compiled by both projects, there is no evidence in the file:
  mark the unit `dl:shared`.

`doc-forget` reaps tags directly, without an index -- for a project that was
retired or renamed:

```
drag-lint doc-forget --scope <file.pas|dir> --list-tags
drag-lint doc-forget --scope <file.pas|dir> --project OldApp [--apply]
drag-lint doc-forget --scope <file.pas|dir> --rename OldApp=NewApp [--apply]
drag-lint doc-forget --scope <file.pas|dir> --untagged [--apply]
```

## Cross-project verdicts with an unindexed peer

`lint-all` judges `unused-global`, `unused-public` and `member-could-be-private` across the projects of the
`.groupproj`. A peer project with no index makes the verdict UNDECIDABLE (the finding is withheld and one stderr
line names the peer and the `index --project` command that fixes it) on every unit the peer lists in its `.dproj` /
`.dpr`, and on every unit in a folder it searches: its own folder and its `DCC_UnitSearchPath`. Since 1.52.3 a
search-path entry written as a `$(MACRO)` counts too -- the macro is expanded from the IDE's Environment Variables
or the process environment, as the indexer does. A unit on the IDE LIBRARY path needs no such rule: `lint-all`
treats a unit under a library root as library and reports nothing on it.
