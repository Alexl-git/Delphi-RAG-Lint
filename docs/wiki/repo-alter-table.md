# repo-alter-table

`drag-lint repo alter-table` makes ONE Firebird table match the field repository (direction `repo-to-db`). It prints a
change set with the exact DDL and **writes nothing unless `--apply` is given**.

```
drag-lint repo alter-table --table <T> --direction repo-to-db --connection "<Firebird connection string>"
    (--repo <file> | --project <project file>)
    [--safe-path] [--rename OLD=NEW[,...]] [--order A,B,...] [--hook <name>]
    [--select <id file>] [--apply] [--dry-run] [--json]
    [--backup-dir <folder>] [--verify full|quick]
```

| Flag | Meaning |
|---|---|
| `--direction repo-to-db` | Required; there is no default direction. |
| `--apply` | Makes a verified backup of the database, then writes the checked changes. `--dry-run` wins over it. |
| `--backup-dir`, `--verify` | Where the backup goes and whether it is restored for a test (`full`, the default) or not (`quick`): [[repo-db-backup]]. |
| `--select <file>` | Ids to apply, one per line, or `all` (never a blocked one, and never a DROP COLUMN: a drop needs its own id, alone or beside `all`). Alone it writes nothing. With `--apply` the file must also hold the line `plan <hash>` that the dry run printed (`plan_hash` in JSON): ids are positions in ONE plan, and when the table or the repository changed since, the apply is refused. |
| `--safe-path` | Offers add-copy-compare-swap for type changes Firebird refuses. Unchecked: they need `--select`. |
| `--rename OLD=NEW` | A rename must be named: the repository knows columns by name only. Without it a rename reads as an add and an unchecked drop. |
| `--order A,B` | Moves the listed columns to the front, in this order. The repository holds no column positions. |
| `--hook <name>` | `generic` (default, does nothing) or `micronite` (vetoes `FIB$` tables, reminds of `repo update-orm`). |
| `--json` | One JSON object: `changes[]` with `ddl`, `safe`, `prechecks`, `blocked`, `depends_on`; `outcome` after an apply. |

Exit: 0 = ok (a dry run included); 1 = bad arguments, a refused or a failed apply. The report is printed also when a
group failed.

## What is checked, unchecked, blocked

* **Checked**: CREATE DOMAIN a column needs, rename, widening (a longer CHAR / VARCHAR, SMALLINT -> INTEGER -> BIGINT ->
  INT128 at the same scale, FLOAT -> DOUBLE), a domain change of the same type, SET NOT NULL, ADD column, order.
* **Unchecked** (only `--select` takes them): DROP column, DROP NOT NULL, every safe-path change, and the widening of a
  column that other objects use; those are listed as `dependent:` (`dependents[]` in JSON).
* **BLOCKED**, with a code:

| Code | Reason |
|---|---|
| `dependency` | a view, trigger, procedure, function or package uses the column (a WIDENING is offered unchecked instead), or its rename is blocked |
| `constraint` | PK, UNIQUE, FK or CHECK on the column |
| `index` | an index or expression index on the column; for a widening only an index key that would be too long and an expression index on text |
| `computed-by` | a computed column uses it, or it is one |
| `identity`, `column-grants`, `update-triggers`, `default` | the column (or the safe path on it) cannot be replaced without losing something |
| `temp-name` | `<column>_NEW` exists, is added by the same run, or is too long |
| `refused-shrink`, `refused-conversion` | Firebird refuses, or the change is not a known widening |
| `lossy` | Firebird ACCEPTS the change and loses data (fewer decimals, TIMESTAMP -> DATE) |
| `domain`, `charset` | the domains differ, the domain would be lost, has a CHECK, or has another character set |
| `unsupported-type` | BLOB, OCTETS, a WITH TIME ZONE type or an unknown type |
| `repo-inconsistent` | the repository row contradicts itself (CHAR_LENGTH and STRING_SIZE, row and domain) or a text column has no character length |
| `dialect`, `hook`, `pending-type-change` | the database cannot do it; a hook refuses; a type change comes first |
| `nulls`, `rows`, `cast-failures`, `value-loss` | found by the pre-checks in the live data |

## Widening a column that other objects use

Measured on Firebird 4.0.6, pages of 4, 8 and 16 KB (`tests\fieldrepo\AlterTests.dpr` F80-F89). Nothing is recompiled.

| Dependent | Firebird | Afterwards | Here |
|---|---|---|---|
| view, plain column | accepts | follows the new type, over a domain too | unchecked |
| view, expression (`A \|\| 'x'`) or UNION column | accepts | keeps the old length: a longer value raises "string right truncation" when it is read | unchecked |
| procedure, function, package, trigger: `TYPE OF COLUMN` | accepts | follows | unchecked |
| the same with a fixed `VARCHAR(10)` variable, parameter or result | accepts | a longer value raises "string right truncation" there; a trigger then refuses the write, nothing is cut silently | unchecked |
| index (also descending, unique, several columns): SMALLINT .. INT128, FLOAT, CHAR, VARCHAR | accepts | rebuilt: same answers as a scan, duplicates still refused, `gfix -v -full` clean | unchecked |
| index whose key gets longer than page size / 4 - 9 bytes (2039 with 8 KB pages) | REFUSES: "key size exceeds implementation restriction" | - | BLOCKED `index`. A collation that needs more bytes per character (UNICODE_CI: 6) is not counted: Firebird then refuses at the apply, rolled back |
| expression index on a number | accepts | answers right | unchecked |
| expression index on text | accepts | a value over the key limit fails with "Error during savepoint backout" and left a record error in `gfix -v` | BLOCKED `index` |
| PK, UNIQUE, FK or CHECK constraint, computed column | not part of this | - | BLOCKED `constraint`, `computed-by` |

## Pre-checks and apply

Every run, dry or not, scans the live data read-only: NULLs before SET NOT NULL, existing rows before ADD NOT NULL, rows
whose CAST fails and rows whose value would change before a safe-path change (truncated blanks, decimals, the time of
day, leading zeros such as `007`, the words `TODAY` / `NOW` in a date column). An apply refuses to start without the
pre-checks of the same call on the same connection, and when the table changed since the plan was made.

A plan is **not atomic as a whole**. It is atomic per group, and the outcome names the state of each:

| Group | Transactions | When it fails |
|---|---|---|
| direct (domains, renames, types, NOT NULL, adds) | one | `rolled-back`: the table is as before |
| safe, one per column | ADD; copy; compare + swap | `compensated`: the copy column is dropped, the old column was never touched |
| drop | one | `rolled-back`; runs after the safe changes, so a failed copy never costs a column |
| order | one | `rolled-back`; earlier groups stay committed |

The safe path cannot be one transaction: Firebird does not let a transaction fill a column it has just added. The swap
transaction reserves the table (PROTECTED WRITE), compares every row of the copy with the old column and only then
drops it, so a value another session changed after the copy stops the swap. `leftover` = the clean-up failed too and
`<column>_NEW` is still there; drop it by hand after looking at the error. `unknown` = the rollback failed too (the
connection is gone): look at the table. After an apply `not applied:` lists every change of the plan that was not made.

Before the first write the apply makes a backup of the database, restores it into a temporary database and compares the list of
tables and the row count of the altered table ([[repo-db-backup]]). When the backup or its verification fails, when there is not
enough space, or when the server is another machine, nothing is applied (exit 1). Nothing to apply = no backup. The table
is compared with the plan again after the backup.

Firebird allows DDL only while nobody else uses the table: run it in a maintenance window.

## Known limits

* Not created or dropped: tables, constraints, indices, triggers. Existing columns keep their default.
* The repository does not know which column is computed or an identity column: one taken from another database would be
  added as a plain column.
* `NULL_FLAG` in the repository is the DOMAIN's flag; that is why DROP NOT NULL is offered unchecked.
* `OpenMode`, `CreateDatabase`, `DropDatabase`, connection definitions and another `DriverID` than `FB` are refused in
  `--connection`, before anything is opened.
* A table with a delimited mixed-case column name is refused. A named NOT NULL constraint loses its name on the safe path.
* A CHAR column cannot be shortened (its padding counts as a changed length).
* Firebird only (SQL dialect 3). Another database implements `IFrDbDialect` and `IFrDbProvider`
  (`DRagLint.FieldRepo.DbProvider`); another site registers an `IFrSchemaHook` (`DRagLint.FieldRepo.SchemaHook`).

See also: [[repo-db-backup]], [[field-repository]].
