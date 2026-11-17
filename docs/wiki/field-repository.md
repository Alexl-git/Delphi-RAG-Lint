# field-repository

The field repository is the TableTools field registry (`FIB$FIELDS_INFO`,
`FIB$DATASETS_INFO`, `FIB$ENUMVALUES`, `FIB$ERROR_MESSAGES`) kept in ONE SQLite file
(`.dlrepo`) instead of tables in the Firebird database. The five tables are `DL_META`,
`DL_FIELDS_INFO`, `DL_DATASETS_INFO`, `DL_ENUMVALUES` and `DL_ERROR_MESSAGES`.
**Firebird is not modified**: every verb that reads it only runs SELECTs.

## Where the repository lives

One repository per DATABASE: Firebird table names are unique within one database, so
several projects that use the same database share one repository file.

Path resolution, first match wins:

1. `--repo <file>`.
2. The `fieldRepository` key of `<project folder>\_D-RAG\drag-lint-project.json`
   (relative to the project folder), when `--project <project file>` is given:
   `{ "fieldRepository": "..\\SERVER\\_DL-REPO\\Micronite.dlrepo" }`.
3. The default for `--project`: `<project folder>\_DL-REPO\<project base name>.dlrepo`.

Neither `--repo` nor `--project`: usage error, exit 1.

## The verbs

```
drag-lint repo init           (--repo <file> | --project <project file>)
drag-lint repo info           (--repo <file> | --project <project file>) [--json]
drag-lint repo import-fb      --connection "<Firebird connection string>" (--repo | --project) [--replace]
drag-lint repo seed-fb        --connection "<Firebird connection string>" (--repo | --project) [--dry-run]
drag-lint repo refresh-schema --connection "<Firebird connection string>" (--repo | --project) [--dry-run]
drag-lint repo backup         (--repo | --project) [--output <file>]
drag-lint repo restore        --in <backup file> (--repo | --project) [--replace]
drag-lint repo gen-memtable   --in <csv file> [--name <Name>] [--output <file>]
```

| Verb | What it does | Exit |
|---|---|---|
| `init` | Creates an empty repository (all five tables) and prints its path. | 0; 1 when the file exists |
| `info` | Path, schema version, rows per table and the `DL_META` keys; `--json` prints one object (`path`, `schema_version`, `tables`, `meta`). | 0; 1 when the file is missing or not a repository |
| `import-fb` | The Micronite path: copies the four `FIB$` tables as they are (the `FIB$VERSION` column is not carried). Creates the repository when missing. A non-empty repository needs `--replace`, which first writes `<repo>.before-import-<yyyymmdd-hhnnss>.txt` (a text backup) and prints its path. Prints `<table>: <n> rows (source <m>)` per table; exit 0 only when every n equals m. | 0; 1 failure; 2 when a source table does not match the repository columns (nothing written) |
| `seed-fb` | The non-Micronite start: fills an EMPTY repository from the Firebird schema: one `DL_FIELDS_INFO` row per user table column with the schema-derived columns set and the hand-maintained ones at their defaults, and `DL_DATASETS_INFO` for every table with a primary key. Sets the `source_database` meta key. | 0; 1 |
| `refresh-schema` | The old "Update Fields Info": overwrites ONLY the schema-derived columns, keeps every hand-maintained column, marks vanished columns `ISCALCULATED` (never deletes), regenerates `DL_DATASETS_INFO`. Prints added / changed / orphaned counts; `--dry-run` also prints the diff and writes nothing. | 0; 1 |
| `backup` | Writes the diffable text backup (default `<repo>.txt`). Deterministic: the same rows give the same bytes. | 0; 1 |
| `restore` | Reads a text backup into the repository, creating it when missing. A non-empty repository needs `--replace`. The whole file is validated first; a malformed file prints `line <n>: ...` and changes nothing (a missing repository is not left behind). | 0; 1; 2 malformed backup |
| `gen-memtable` | Prints (or writes with `--output`) the Pascal source of `Create<Name>Fields`, a procedure that builds the fields of a `TFDMemTable` from a CSV (`FieldName,FieldType,Size,FieldKind,...`). `--name` defaults to `FDMemTable`. | 0; 1; 2 bad CSV |

`gen-param-array`, `gen-orm`, `update-orm` and `gen-dataservice` are reserved sub-verbs; they
answer "not available in this build" and exit 1.

## Text backup

`repo backup` writes 7-bit ASCII with CRLF line ends and no BOM: fixed table order, rows in
key order, NULL columns left out, one `#end <table> <count>` trailer per table.
`restore(backup(F))` is byte for byte `F`, so the text file is the committed, reviewable form
of the repository; the binary `.dlrepo` is not committed.

## Connection strings

`--connection` is a FireDAC list separated by `;`, for example
`"Database=host:D:\data\micronite.fdb;User=SYSDBA;Password=...;DriverID=FB"`. `DriverID=FB` and
`CharacterSet=UTF8` are added when missing. The password is never printed or stored; the
repository keeps only the `Database` value (`source_database`).

## Known limits

* Firebird is read only; writing the repository back to Firebird (`repo publish-fb`) is not in
  1.52, so the run-time `FIB$` readers of an application still need their Firebird copy.
* `repo info` of a file that is not a repository, and every other failure, print one line on
  stderr starting with `repo <verb>:` and exit 1.
