# link-orm

Links a project's code index to a SQL index so ORM-style relationships
between Delphi symbols and SQL objects can be resolved across both. Reach
for it when you want queries that cross from code into the schema it talks
to.

## Running it from the CLI

```
drag-lint link-orm --db <projDb.sqlite> --db <sqlDb.sqlite>
```

## Reaching it in the IDE

No IDE surface -- this is a CLI-only feature.

## What it needs

An index IS required -- in fact TWO: `link-orm` takes exactly two `--db`
flags, one for the project's own DB and one for the SQL DB. The project's DB
lives at `<project folder>\_D-RAG\<project file>.sqlite`; run
`drag-lint resolve-dbs --project <X.dproj>` if unsure.

## Example

Illustrative only:

```
drag-lint link-orm --db C:\Projects\MyApp\_D-RAG\MyApp.sqlite --db sql.sqlite
```

This would link `MyApp`'s code index to the `sql.sqlite` SQL index.
