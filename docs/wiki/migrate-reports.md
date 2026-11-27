# migrate-reports: saved reports in the CLI style

```
drag-lint migrate-reports <file-or-folder>... [--project <P.dproj>] [--dry-run] [--json]
```

Rewrites the `COMMAND` line of saved reports from the old PowerShell style (`-Target "T" -Project "P"`) to the CLI style
of 1.56 (`--target "T" --project "P"`). Only that line changes. A folder is searched with its subfolders; `--project`
adds that project's snapshot folder.

The verb lists what it left alone and why: no `COMMAND` line, a wrapped or mixed-style line, an unknown argument, or a file
that is not a report. A left-alone file is never an error. Forms CSV and chart DOT snapshots carry no command line and are
reported as current.

[compare](compare) reads both styles, so running this verb is optional.

| Flag | Meaning |
|---|---|
| `--project <P.dproj>` | also search the snapshot folder of that project |
| `--dry-run` | list what would change, write nothing |
| `--json` | `{verb, dryRun, files, migrated[], current[], leftAlone[], failed[]}` |

| Exit | Meaning |
|---|---|
| 0 | done |
| 1 | a path is missing or a file is unreadable |
| 2 | usage error |
