# document-all

Documents every public declaration in every indexed unit, with no project
scope. Reach for it to sweep DocInsight comments across the whole index at
once, rather than one project at a time.

## Running it from the CLI

```
drag-lint document-all [--stubs|--apply|--json|--no-backup|--include-accessors] [--db PATH]
```

Like the other batch document modes, the default is facts-only: an empty
tag is never written, `<param>` never gets a skeleton, and `<summary>`
appears only when harvested from a nearby `//` comment; add `--stubs` to
keep a fresh comment that has no facts block. Trivial `Get*`/`Set*` property
accessors are skipped by default; add `--include-accessors` to document
them too. The usage line lists `--apply` as a flag; whether omitting it
produces a dry run is not documented in the help text for this verb.

`document-all` covers every indexed unit with no project scope. This is
different from `drag-lint document --project <p.dproj>`, which is scoped to
the compile closure restricted to that project's own roots (declared in
`_D-RAG\drag-lint-project.json`).

## Reaching it in the IDE

No IDE surface -- this is a CLI-only feature.

## What it needs

The `--db` flag is optional -- drag-lint auto-resolves the index when
omitted. An index must still exist.

## Example

Illustrative:

```
drag-lint document-all --apply --db C:\Projects\MyApp\_D-RAG\MyApp.sqlite
```

This would add facts-only DocInsight comments to every public declaration
in every unit that this index covers, regardless of which project owns it.
