# repo-backup-formats

Three backup formats for the field repository ([[field-repository]]). The text backup is the default and stays the
committed, reviewable form; the other two are copies for other uses. A backup of the Firebird DATABASE is another verb
([[repo-db-backup]]).

```
drag-lint repo backup  (--repo <file> | --project <project file>) [--format text|sql|zip] [--output <file>]
drag-lint repo restore --in <backup file> (--repo <file> | --project <project file>) [--format text|sql|zip] [--replace]
```

| Format | File | What it is |
|---|---|---|
| `text` (default) | `<repo>.txt` | The diffable, deterministic text backup. `restore(backup(F))` is byte for byte `F`. |
| `sql` | `<repo>.sql` | A script: `-- DLREPO-SQL <schema version>`, one `CREATE TABLE` line per table, one `INSERT` per row, a `-- end <T> <n>` trailer per table. 7-bit ASCII, CRLF, deterministic. |
| `zip` | `<repo>.zip` | A zip with `DLREPO-ZIP.txt` (the format marker and the schema version) and `repository.sqlite`, a consistent copy made by `VACUUM INTO`. |

`--format` is the same word for backup and restore, and `restore` must be given the format the file was written in: a
file of another format is refused as a malformed backup (exit 2), never half read. Without `--format` nothing changes
from before: the text format.

## Restore

* **Missing repository:** created. For `sql` it is built at the script's own schema version beside the target and renamed
  on success, so a malformed script never leaves an empty repository behind. `zip` extracts the copy beside the target
  and renames it over.
* **Existing repository:** refused unless `--replace` (exit 1).
* **sql** parses and validates the whole file first, never executes text from the file (only `INSERT` lines of the exact
  shape are understood), and writes in one transaction. An older script restored into a newer repository gets the data
  steps of `repo migrate`; a newer script into an older repository is refused ("migrate first").
* **zip** checks that the file is a zip, that it holds both entries, and that the extracted file opens as a repository
  (`PRAGMA quick_check`) before it replaces anything. A truncated or foreign archive is refused with a message and exit 2;
  the repository is unchanged. The repository is replaced as a whole file: no row migration, so an archive of an older
  schema gives an older-schema repository (`repo migrate` it).

An unknown value (`--format json`) is refused before anything is written.

## Proof

`tests\autotest\run_v156_BKZ.ps1` restores each format into a fresh repository and compares the whole text backup of the
source and the result (golden and edge fixtures), and refuses a truncated zip, a non-zip, a zip without the marker and a
zip whose repository entry is not a repository, each with the target unchanged.
