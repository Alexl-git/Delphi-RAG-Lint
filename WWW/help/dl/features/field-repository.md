---
id: field-repository
title: Field repository
summary: Keeps the TableTools field registry in one SQLite file per database, filled from Firebird (read-only), with a diffable text backup
product: DL
group: maintenance
order: 120008
since: 1.52.0-alpha
status: shipped
updated: 1.52.0-alpha
---

# Field repository

Keeps the TableTools field registry in one SQLite file per database, filled from Firebird (read-only), with a diffable text backup.

Read this when you want the TableTools field repository without Firebird tables or the TableTools IDE package. Run drag-lint repo init, then repo import-fb (Micronite) or repo seed-fb (any Firebird database), keep the text backup in version control with repo backup, and point several projects at one repository with the fieldRepository key. Firebird is never modified.

## How to run it

```text
drag-lint repo init (--repo <file> | --project <project file>) (create an empty field repository; exit 1 when the file exists)
```

Full flag list: [repo in the CLI reference](../cli.md#repo).

```text
drag-lint repo info (--repo <file> | --project <project file>) [--json] (path, schema version, rows per table, DL_META keys; exit 1 when not a repository)
```

Full flag list: [repo in the CLI reference](../cli.md#repo).

```text
drag-lint repo import-fb --connection "<Firebird connection string>" (--repo <file> | --project <project file>) [--replace] (copy the FIB$ registry tables; read-only on Firebird; --replace writes a before-import text backup first; exit 1 failure, 2 schema drift)
```

Full flag list: [repo in the CLI reference](../cli.md#repo).

```text
drag-lint repo seed-fb --connection "<Firebird connection string>" (--repo <file> | --project <project file>) [--dry-run] (fill an EMPTY repository from the Firebird schema; read-only on Firebird)
```

Full flag list: [repo in the CLI reference](../cli.md#repo).

```text
drag-lint repo refresh-schema --connection "<Firebird connection string>" (--repo <file> | --project <project file>) [--dry-run] (re-read the Firebird schema into a filled repository, keep hand-edited columns, mark vanished columns; --dry-run prints the diff only)
```

Full flag list: [repo in the CLI reference](../cli.md#repo).

```text
drag-lint repo backup (--repo <file> | --project <project file>) [--output <file>] (write the diffable text backup; default <repo>.txt)
```

Full flag list: [repo in the CLI reference](../cli.md#repo).

```text
drag-lint repo restore --in <backup file> (--repo <file> | --project <project file>) [--replace] (create the repository when missing; a malformed backup prints "line <n>: ..." and exits 2, nothing changed)
```

Full flag list: [repo in the CLI reference](../cli.md#repo).

```text
drag-lint repo gen-memtable --in <csv file> [--name <Name>] [--output <file>] (Pascal source that builds the fields of a TFDMemTable from a field-definition CSV; exit 2 on a bad CSV)
```

Full flag list: [repo in the CLI reference](../cli.md#repo).

```text
drag-lint repo gen-param-array (--in <unit.pas> [--dfm <file>] | --project <X.dproj> --all [--only <unit,...>]) [--query <Name>] [--table <Name>] [--step-size <n>] [--progress-form <Form>] [--prepare-queries] [--plan | --apply --project <X.dproj> [--no-backup] [--platform <p>] [--rsvars <bat>] [--build-timeout <s>]] [--json] (FireDAC Array-DML loop from the unit's DFM, inserted as a braced comment before the final end.; no flag prints the block, --plan the diff, --apply writes through ONE compile gate; --prepare-queries first does the IDE assistant's query preparation (each SELECT TFDQuery gets its TFDUpdateSQL INSERT SQL, ObjectView=False, no CachedUpdates; update object / schema adapter renamed ZZZ*, persistent fields removed with their declarations; .dfm + .pas diffs in --plan, both written through the gate); exit 1 a unit refused or no block, 2 bad flags or a baseline that does not build)
```

Full flag list: [repo in the CLI reference](../cli.md#repo).

```text
drag-lint repo gen-orm (--repo <file> | --project <project file>) --code-dir <folder> [--table <T,...>] [--apply [--no-backup]] (new i<T>.PAS + u<T>.PAS ORM units per repository table; dry run prints the diff, --apply writes 7-bit ASCII, an existing file is first copied to <file>.BCKn; prints add to project: per new file)
```

Full flag list: [repo in the CLI reference](../cli.md#repo).

```text
drag-lint repo update-orm (--repo <file> | --project <project file>) --code-dir <folder> [--server-dir <folder>] [--client-dir <folder>] [--table <T,...>] [--save-form legacy|current] [--apply [--no-backup]] (rewrites ONLY the DB-RAD regions of the existing i/u/_SERVER/_CLIENT units, every other byte kept; --save-form legacy (default) = the FIELD_AS_TYPE parameter binding the ORM3 units carry, current = TableTools 2026-05-19 .Value / .AsWideMemo / Set1Byte / NULL-timestamp Clear)
```

Full flag list: [repo in the CLI reference](../cli.md#repo).

```text
drag-lint repo gen-dataservice (--repo <file> | --project <project file>) --server-dir <folder> --client-dir <folder> [--table <T,...>] [--save-form legacy|current] [--apply [--no-backup]] (new u<T>_SERVER.PAS + u<T>_CLIENT.PAS per table and the two DI container units; prints add to project: per new file)
```

Full flag list: [repo in the CLI reference](../cli.md#repo).

```text
drag-lint repo <init|info|import-fb|seed-fb|refresh-schema|backup|restore|gen-memtable|gen-param-array|gen-orm|update-orm|gen-dataservice> (--repo <file> | --project <project file>) [--connection "<Firebird connection string>"] [--in <file>] [--output <file>] [--name <Name>] [--replace] [--dry-run] [--json]   (the field repository: one SQLite file per database; Firebird is only read; gen-param-array needs no repository)
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
| `--prepare-queries` |  |  |  |
| `--code-dir` | `<folder>` |  |  |
| `--server-dir` | `<folder>` |  |  |
| `--client-dir` | `<folder>` |  |  |
| `--save-form` | `<legacy\|current>` |  |  |

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
* RAD Studio main menu: **drag-lint > Field Repository > Generate / Update ORM Source...**
   1. Open the project whose field repository describes the tables
   2. Choose drag-lint > Field Repository > Generate / Update ORM Source...
   3. Pick the folder of the `i<T>`/`u<T>` units; give table names for NEW units, or leave it empty to update the DB-RAD regions of every existing unit (optionally also the _SERVER/_CLIENT folders)
   4. Read the dry-run summary and answer Yes to write (repo gen-orm / update-orm --apply)
* RAD Studio main menu: **drag-lint > Field Repository > Generate DataService Units...**
   1. Choose drag-lint > Field Repository > Generate DataService Units...
   2. Give the table names, then pick the _SERVER and _CLIENT folders
   3. Read the dry-run summary and answer Yes to write (repo gen-dataservice --apply); add the listed units to the projects
* RAD Studio main menu: **drag-lint > Field Repository > Param Array Assistant...**
   1. Open and save the form unit
   2. Choose drag-lint > Field Repository > Param Array Assistant...
   3. Answer whether to prepare the queries first (--prepare-queries)
   4. Read the --plan summary and answer Yes to write through the compile gate (repo gen-param-array --apply)

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

### gen-orm, update-orm, gen-dataservice

Ports of the TableTools ORM / DataService generators, fed by `DL_FIELDS_INFO` (rows with `FIELD_KIND = 1`).
Every verb prints a dry-run diff (`new` / `changed` / `unchanged` per file, then the hunks) and writes only with
`--apply` (7-bit ASCII; an existing file is first copied to `<file>.BCKn` unless `--no-backup`).

| Sub-verb | Folders | What it writes |
|---|---|---|
| `gen-orm` | `--code-dir` | new `i<T>.PAS` + `u<T>.PAS` per table (`--table T,...`; empty = every table) |
| `update-orm` | `--code-dir` [`--server-dir`] [`--client-dir`] | ONLY the lines inside the `{$REGION 'DB-RAD <id>'}` regions of the existing units; every other byte, line ends included, is kept. A missing file or a table without `FIELD_KIND = 1` rows is skipped and named |
| `gen-dataservice` | `--server-dir` `--client-dir` | new `u<T>_SERVER.PAS` + `u<T>_CLIENT.PAS` and the two DI container units; prints `add to project:` per new file |

`--save-form legacy|current` picks how region 9 (Save) binds its parameters. `legacy` (the default) is the form
the ORM3 units carry (TableTools before 2026-05-19): the `FIELD_AS_TYPE` accessor (`.AsString`, `.AsInteger`, ...),
`.AsString` for a `TStringList`, `.AsByte` for an enum, a timestamp without a NULL guard. `current` is TableTools
2026-05-19: `.Value`, `.AsWideMemo` (FB-338), `Set1Byte` for an enum, `Clear` when the timestamp `Year = 0`.

Golden (release gate): `tests\autotest\run_fieldrepo_ormgen_golden.ps1 -RequireForm -RepoFile <dev.dlrepo>` runs
`update-orm` over a COPY of ORM3: 521 of 528 units come out the same ignoring blanks and case and nothing outside
the regions moves; the 7 others are listed with their reason in `tests\fieldrepo\ormgen-golden-known-drift.txt`
(schema drift, a hand-ported unit, a hand-edited region). Byte parity is not the gate: the ORM3 units were
re-formatted after TableTools wrote them.

IDE: **drag-lint > Field Repository > Generate / Update ORM Source...** (pick the `i/u` folder; table names =
`gen-orm`, empty = `update-orm`, optionally with the `_SERVER` / `_CLIENT` folders) and **Generate DataService
Units...** run the dry run, show its summary and write after **Yes**. **Param Array Assistant...** runs
`gen-param-array --plan` on the unit in the active editor (optionally with `--prepare-queries`) and, after
**Yes**, `--apply --project` through the compile gate.

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
