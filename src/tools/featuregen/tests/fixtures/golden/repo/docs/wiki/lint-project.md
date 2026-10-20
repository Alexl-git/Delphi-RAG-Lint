# lint-project

Runs project-scoped structural lint rules against an index -- checks such as
god-class, unused-public-symbol, circular-uses and layering-violation that
need whole-project context rather than a single file. Reach for it for
cross-file architectural findings, not per-file diagnostics.

## Running it from the CLI

```
drag-lint lint-project --db <file.sqlite> [--rule god-class|unused-public-symbol|interface-reference-cycle|layering-violation|unused-private-member|unused-unit-in-uses|circular-uses|repeated-type-switch] [--layers <f.json>] [--json]
```

## Reaching it in the IDE

No IDE surface -- this is a CLI-only feature.

## What it needs

An index IS required. The project's DB lives at
`<project folder>\_D-RAG\<project file>.sqlite`; run
`drag-lint resolve-dbs --project <X.dproj>` if unsure.

## Example

Illustrative only:

```
drag-lint lint-project --db C:\Projects\MyApp\_D-RAG\MyApp.sqlite --rule circular-uses --json
```

This would report circular-uses findings for `MyApp` as JSON.
