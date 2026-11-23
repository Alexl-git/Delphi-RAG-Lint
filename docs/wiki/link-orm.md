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

An index IS required, usually two or more: each `--db` names one, the project's
own DB (or several projects' DBs) and the SQL DB. The project's DB
lives at `<project folder>\_D-RAG\<project file>.sqlite`; run
`drag-lint resolve-dbs --project <X.dproj>` if unsure.

## Example

Illustrative only:

```
drag-lint link-orm --db C:\Projects\MyApp\_D-RAG\MyApp.sqlite --db sql.sqlite
```

This would link `MyApp`'s code index to the `sql.sqlite` SQL index.

## What several --db values do

* Every `--db` is a source, in any order: each one is read for Delphi symbols and for SQL symbols.
* One `orm_links` table is written, in the **last** `--db`, and nowhere else. Its previous rows are
  replaced. The summary line ends with `-- written to <that db>`.
* Why one table: `delphi_db_index` / `sql_db_index` are positions in this run's `--db` list (0 = first)
  and the symbol ids are local to those indexes, so the rows mean something only with that list.
* A field is linked only through its own class in its own index. Before 1.53 two project indexes in one
  run could mix the fields of classes that happened to have the same local symbol id.
