# repo-db-backup

A verified backup of a Firebird database, made through the Firebird service API (no `gbak.exe`). `repo alter-table --apply`
makes one itself before its first DDL ([[repo-alter-table]]); the verbs below make, list and purge them by hand.

```
drag-lint repo backup --connection "<Firebird connection string>" [--verify full|quick] [--table <T>]
                      [--backup-dir <folder>] [--backup-name <name>] [--project <project file>] [--json]
drag-lint repo backup list  [--connection "<Firebird connection string>"] [--json]
drag-lint repo backup purge --keep <N> [--connection "<Firebird connection string>" [--apply]] [--dry-run] [--json]
```

`repo backup` with nothing but `--repo`, `--project` and `--output` is the text backup of the field repository
([[field-repository]]). Everything else on the line makes it a database verb: a flag or word that does not belong, has no
value (`--connection ""`) or is given twice is an error (exit 1) and nothing is written, so a forgotten `--connection`
never ends in a text backup. `list` / `purge` stand directly after `backup`.
Beside `--repo` the error names the flag that does not belong and says to drop it (1.54.1); `--repo` with
`--connection` says which of the two to drop.

| Flag | Meaning |
|---|---|
| `--verify full` | The default: the backup is restored into a temporary database beside it, the list of tables and views and (with `--table`) the row count are compared, then only that temporary database is dropped. The row count is taken before the backup starts, so a writer in between fails the verification. |
| `--verify quick` | No restore; the backup was written without an error, nothing more. |
| `--backup-dir` | The folder; created when missing. Else `"backupDir"` of the `--project`'s `_D-RAG\drag-lint-project.json` (relative to the project folder), else the folder of the database. |

`--connection` is read as FireDAC reads it (`$(NAME)` expanded); a key given twice is refused. The temporary database is opened
without its database triggers.

The file is `DLFR_BACKUP_<database>_<yyyymmdd>_<hhnnss>.fbk` (before 1.55: `<database>-<yyyymmdd>-<hhnnsszzz>.fbk`). Two backups of the same second
get `_2`, `_3` ... before the extension. `--backup-name <name>` chooses the name instead: a name, not a path (a path separator or
drive is refused; `--backup-dir` picks the folder), `.fbk` is added when missing. An existing file is never overwritten. Free space is checked first, with 10 % head
room: one database size, two with the restore test. When anything fails the exit code is 1 and the source database was
only read. A backup whose verification failed stays on disk, recorded as `failed`; an incomplete one is removed.

## The list and the purge

Every backup is recorded in `%LOCALAPPDATA%\drag-lint\db-backups.json` (file, database, size, date, `full` / `quick` / `failed`); no
connection string or password is stored. The total size is printed after each backup.

`purge` is a dry run unless `--apply` is given, and `--apply` needs `--connection`: only backups of the database that
connection opens are deleted. Without `--connection` the plan of every database is shown. Per database these stay: the newest backup
whatever its state, the newest `N` fully verified ones, the newest `N` that did not fail, and, while there is no fully
verified one, the newest failed one. So the only backup of a database is never purged.

Only a file of the list is ever deleted, and only when the entry is a full plain path (no relative part, link or junction)
with a name drag-lint gives (either form above) or a name chosen with `--backup-name` (the list records that choice), the file is listed once, and its size and date are as recorded; that is checked again on the handle the
file is deleted through. Anything else is skipped and counts for nothing. An entry whose file is gone is dropped from the
list; when its folder is gone too (an unplugged drive) it stays. A list that cannot be read, or was written by a newer
drag-lint, stops the verb and is left as it is.
## The server must be on this machine

The SERVER writes the backup file and the temporary database. When `--connection` names another host (or NetBEUI / WNET) the
verb refuses before anything is opened: neither free space nor the file could be checked. What the open connection says is
checked too: a remote attachment is refused (over TCP use `localhost` or the name of this machine), and `repo alter-table --apply` refuses a backup of
another database than the one it is connected to. Run it on the server with
`localhost:`. A connection string without a host uses the engine of the client library, as the connection itself does.
The Firebird service needs the right to write into the folder, and the user the right to back the database up.

Measured on Firebird 4.0.6 (embedded): a damaged backup file can end a restore WITHOUT an error. The new database then is
not online (`MON$SHUTDOWN_MODE` <> 0), because only the last step of a restore puts it online; that is what the verification checks.

See also: [[repo-alter-table]], [[field-repository]].
