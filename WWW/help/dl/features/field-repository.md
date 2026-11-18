---
id: field-repository
title: Field repository
summary: Keeps the TableTools field registry in one SQLite file per database, filled from Firebird (read-only), with a diffable text backup
product: DL
group: maintenance
order: 120008
since: 1.52.0-alpha
status: shipped
updated: 1.51.1-alpha
---

# Field repository

Keeps the TableTools field registry in one SQLite file per database, filled from Firebird (read-only), with a diffable text backup.

Read this when you want the TableTools field repository without Firebird tables or the TableTools IDE package. Run drag-lint repo init, then repo import-fb (Micronite) or repo seed-fb (any Firebird database), keep the text backup in version control with repo backup, and point several projects at one repository with the fieldRepository key. Firebird is never modified.

## How to run it

```text
drag-lint repo <init|info|import-fb|seed-fb|refresh-schema|backup|restore|gen-memtable|gen-param-array> (--repo <file> | --project <project file>) [--connection "<Firebird connection string>"] [--in <file>] [--output <file>] [--name <Name>] [--replace] [--dry-run] [--json]   (the field repository: one SQLite file per database; Firebird is only read; gen-param-array needs no repository)
```

Full flag list: [repo in the CLI reference](../cli.md#repo).

## Flags

| Flag | Argument | Meaning | Default |
| --- | --- | --- | --- |
| `--all` |  |  |  |
| `--apply` |  |  |  |
| `--build-timeout` | `<s>` |  |  |
| `--dfm` | `<file>` |  |  |
| `--no-backup` |  |  |  |
| `--only` | `<unit,...>` |  |  |
| `--plan` |  |  |  |
| `--platform` | `<p>` |  |  |
| `--progress-form` | `<Form>` |  |  |
| `--query` | `<Name>` |  |  |
| `--rsvars` | `<bat>` |  |  |
| `--step-size` | `<n>` |  |  |
| `--table` | `<Name>` |  |  |
| `--connection` | `<Firebird connection string>` |  |  |
| `--dry-run` |  |  |  |
| `--in` | `<backup file>` |  |  |
| `--json` |  |  |  |
| `--name` | `<Name>` |  |  |
| `--output` | `<file>` |  |  |
| `--project` | `<project file>` |  |  |
| `--replace` |  |  |  |
| `--repo` | `<file>` |  |  |

## Where to click

* RAD Studio main menu: **drag-lint > Field Repository > Open Field Repository Editor...**
   1. Open a project that has a field repository (fieldRepository key or the default file)
   2. Choose drag-lint > Field Repository > Open Field Repository Editor...
   3. The grid editor dl-field-repo.exe opens on that repository
* RAD Studio main menu: **drag-lint > Field Repository > Refresh Schema from Database...**
   1. Open a project with a field repository
   2. Choose drag-lint > Field Repository > Refresh Schema from Database...
   3. Enter the Firebird connection string; the output of drag-lint repo refresh-schema is shown
* RAD Studio main menu: **drag-lint > Field Repository > FDMemTable from CSV...**
   1. Choose drag-lint > Field Repository > FDMemTable from CSV...
   2. Pick a field-definition CSV
   3. The Pascal source is written next to the CSV as `<name>.memtable.pas`

## Details

The field repository is the TableTools field registry (`FIB$FIELDS_INFO`,
`FIB$DATASETS_INFO`, `FIB$ENUMVALUES`, `FIB$ERROR_MESSAGES`) kept in ONE SQLite file
(`.dlrepo`) instead of tables in the Firebird database. The five tables are `DL_META`,
`DL_FIELDS_INFO`, `DL_DATASETS_INFO`, `DL_ENUMVALUES` and `DL_ERROR_MESSAGES`.
**Firebird is not modified**: every verb that reads it only runs SELECTs.

### Where the repository lives

One repository per DATABASE: Firebird table names are unique within one database, so
several projects that use the same database share one repository file.

Path resolution, first match wins:

1. `--repo <file>`.
2. The `fieldRepository` key of `<project folder>\_D-RAG\drag-lint-project.json`
   (relative to the project folder), when `--project <project file>` is given:
   `{ "fieldRepository": "..\\SERVER\\_DL-REPO\\Micronite.dlrepo" }`.
3. The default for `--project`: `<project folder>\_DL-REPO\<project base name>.dlrepo`.

Neither `--repo` nor `--project`: usage error, exit 1.

### The verbs

```text
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

`gen-orm`, `update-orm` and `gen-dataservice` are reserved sub-verbs; they
answer "not available in this build" and exit 1.

### gen-param-array

`drag-lint repo gen-param-array` ports the TableTools FireDAC Param Array assistant: it reads a unit's
text DFM (the table's fields, the parameterised `TFDQuery`'s params with their types), matches params to
fields by name and type, and produces the Array-DML loop (`Params.ArraySize`, one `Params[parX].AsY[I] :=
tblZ...AsW` line per pair, `Execute(I)` every `STEPSIZE` rows). It needs no repository.

| Call | What it does |
|---|---|
| `--in <unit.pas> [--dfm <file>]` | one unit; the DFM is `<unit>.dfm` beside it unless `--dfm` names it |
| `--project <X.dproj> --all [--only a,b]` | every `u*` unit of the project (the exclusion list: `uFolderCheck`, `uCOMPGRP`, `uTestHelper`) |
| no mode flag | prints the block (what the IDE assistant put on the clipboard) |
| `--plan` | prints the unified diff per unit, writes nothing |
| `--apply --project <X.dproj>` | inserts the block as a braced comment before the final `end.`, through ONE compile gate for the whole run (baseline build, all-or-nothing write under `.BCK<n>`, after build, rollback); a compile error retries once without the units dcc names |
| `--query <Name>` / `--table <Name>` | pick the components by name; the default is the LAST parameterised query and the LAST table. A named component that is absent is exit 1, never a fallback |
| `--step-size <n>` / `--progress-form <Form>` | `STEPSIZE` (default 20000); the loader-form progress lines of the original (default none) |
| `--json` | `{mode, units:[{unit, status, query, table, matched, type_mismatch, missing_params, missing_fields, plan?, block?, error?}], gate?:{applied, refusal, detail, rolled_back}}` |

Status words: `applied`, the plan-only word (a unit that would be written; see `--json`), `refused-by-gate`, `no-insert-point`, `no-block`, `excluded`,
`binary-dfm`, `missing-dfm`; a binary or missing DFM is reported per unit, never skipped silently.
Exit 0 = every processed unit is ready to write or written; 1 = a unit refused, no block (single unit), or the gate
rolled back; 2 = bad flags, a write failure, or a baseline that does not build.

The block is a fragment, not code: a column that does not match leaves a marker line (`##### TYPE
MISMATCH #####`, `// MISSING PARAMS`, `#### MISSING FIELDS ####`) for a human to finish. In 1.52 it is
therefore inserted as a comment, so the compile gate proves "the unit still builds" (and a block holding
`}` is refused before any build); live insertion at a `// dl:param-array` marker follows in 1.52.1.
The Loader2019 comparison is `tests\autotest\run_fieldrepo_paramarray_golden.ps1`: a report of assignment
triples, not text equality.

### Text backup

`repo backup` writes 7-bit ASCII with CRLF line ends and no BOM: fixed table order, rows in
key order, NULL columns left out, one `#end <table> <count>` trailer per table.
`restore(backup(F))` is byte for byte `F`, so the text file is the committed, reviewable form
of the repository; the binary `.dlrepo` is not committed.

### Connection strings

`--connection` is a FireDAC list separated by `;`, for example
`"Database=host:D:\data\micronite.fdb;User=SYSDBA;Password=...;DriverID=FB"`. `DriverID=FB` and
`CharacterSet=UTF8` are added when missing. The password is never printed or stored; the
repository keeps only the `Database` value (`source_database`).

### Known limits

* Firebird is read only; writing the repository back to Firebird (`repo publish-fb`) is not in
  1.52, so the run-time `FIB$` readers of an application still need their Firebird copy.
* `repo info` of a file that is not a repository, and every other failure, print one line on
  stderr starting with `repo <verb>:` and exit 1.

---

[All features](../index.md) | [CLI reference](../cli.md) | [IDE menus](../ide.md)
