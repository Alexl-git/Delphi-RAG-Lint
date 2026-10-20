# fb-snapshot

Connects to a Firebird database and captures a snapshot into a sqlite index.
Reach for it when you need a drag-lint-queryable index built from a Firebird
database connection.

## Running it from the CLI

```
drag-lint fb-snapshot --connection "Database=...;User=...;Password=...;DriverID=FB" --db <sql.sqlite>
```

The `--connection` value's exact contents beyond the
`Database=...;User=...;Password=...;DriverID=FB` shape shown in the usage
line are not documented here -- supply your own real Firebird connection
parameters in that form.

## Reaching it in the IDE

No IDE surface -- this is a CLI-only feature.

## What it needs

An index IS required -- the `--db` flag naming the target sqlite file is
mandatory. Whether that file must already exist beforehand is not
documented; run `drag-lint resolve-dbs` if unsure which DB is in play.

## Example

Illustrative only:

```
drag-lint fb-snapshot --connection "Database=...;User=...;Password=...;DriverID=FB" --db sql.sqlite
```

This would snapshot the connected Firebird database into `sql.sqlite`.
