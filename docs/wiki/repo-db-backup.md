# repo-db-backup

A verified backup of a Firebird database, made through the Firebird service API (no `gbak.exe`). `repo alter-table --apply`
makes one itself before its first DDL ([[repo-alter-table]]); the verbs below make, list and purge them by hand.

```
drag-lint repo backup --connection "<Firebird connection string>" [--verify full|quick] [--table <T>]
                      [--backup-dir <folder>] [--project <project file>] [--json]
drag-lint repo backup list  [--json]
drag-lint repo backup purge --keep <N> [--apply] [--dry-run] [--json]
```

Without `--connection`, `list` and `purge`, `repo backup` is the text backup of the field repository ([[field-repository]]).
`--repo` does not go with a database backup.

| Flag | Meaning |
|---|---|
| `--verify full` | The default: the backup is restored into a temporary database beside it, the list of tables and views and (with `--table`) the row count are compared, then only that temporary database is dropped. The row count is taken before the backup starts, so a writer in between fails the verification. |
| `--verify quick` | No restore; the backup was written without an error, nothing more. |
| `--backup-dir` | The folder; created when missing. Else `"backupDir"` of the `--project`'s `_D-RAG\drag-lint-project.json` (relative to the project folder), else the folder of the database. |

The file is `<database>-<yyyymmdd>-<hhnnsszzz>.fbk`; an existing file is never overwritten. Free space is checked first, with 10 % head
room: one database size, two with the restore test. When anything fails the exit code is 1 and the source database was
only read. A backup whose verification failed stays on disk, recorded as `failed`; an incomplete one is removed.

## The list and the purge

Every backup is recorded in `%LOCALAPPDATA%\drag-lint\db-backups.json` (file, database, size, date, `full` / `quick` / `failed`); no
connection string or password is stored. The total size is printed after each backup.

`purge` is a dry run unless `--apply` is given. Per database it keeps the newest `N` good backups and always the newest
fully verified one; failed ones go. It touches only files of the list whose size and date are still as recorded: a modified
file is skipped (and does not count as kept), any other file is never looked at. A list that cannot be read stops the verb and is left as it is.

## The server must be on this machine

The SERVER writes the backup file and the temporary database. When `--connection` names another host (or NetBEUI / WNET) the
verb refuses before anything is opened: neither free space nor the file could be checked. Run it on the server with
`localhost:`. A connection string without a host uses the engine of the client library, as the connection itself does.
The Firebird service needs the right to write into the folder, and the user the right to back the database up.

Measured on Firebird 4.0.6 (embedded): a damaged backup file can end a restore WITHOUT an error. The new database then is
not online (`MON$SHUTDOWN_MODE` <> 0), because only the last step of a restore puts it online; that is what the verification checks.

See also: [[repo-alter-table]], [[field-repository]].
