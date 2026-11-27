# Copy events and columns between grid views

```
drag-lint repo copy-grid --dfm <file.dfm> [--unit <file.pas>] --from <view> --to <view>
                         [--event <name> [--from-column <col> [--to-column <col>]]]
                         (--repo | --project) [--apply | --select <id file>] [--dry-run] [--json]
drag-lint repo copy-grid --dfm <file.dfm> --list [--from <view>] (--repo | --project)
```

Copies what one grid view of a form has to another view of the SAME form: the events of the view, its columns
and their events. The views may be of different kinds (table, banded table, card, layout view). With `--event` it
copies ONE event (`OnCustomDrawCell`, `DataController.OnCompare`, ...); `--from-column` names the source column
that has it, `--to-column` the target (default: the column that shows the same field). The unit is the `.pas`
beside the DFM unless `--unit` says otherwise; a new column needs it, because the column is declared there.
`--repo` / `--project` only select the `repo` command: the repository is not opened.

Nothing is written without `--apply` (the checked changes) or `--select` (exactly the ids in the file).
`--dry-run` wins over both. Every changed file gets a backup beside it:
`<file>.before-write-dfm-<yyyymmdd-hhnnss>`.

**The plan id.** The dry run starts with `# plan <id>`. A `--select` file (one id per line, or `all`: every
change that is not blocked) must hold that line; without it exit 2, with another plan nothing is written and the
exit is 1.

**Checked, unchecked, blocked.** A change is BLOCKED when it can never be applied (the target class has no such
event, no unit, a layout view, text that is not 7-bit ASCII). It is unchecked when it needs a look: the target
already has another handler, or the handler's body names the source view. `--apply` writes the checked ones;
unchecked ones go in with `--select` and `all` or their ids.

| Exit | Meaning |
|---|---|
| 0 | ok, a dry run and a plan without changes included |
| 1 | a DFM / unit that cannot be read, a view or event the form does not have, source = target, a plan the `--select` file does not belong to, a write failure |
| 2 | usage: no `--dfm`, no `--from` / `--to`, `--from-column` without `--event`, a `--select` file that is missing, has no plan line or names an unknown or blocked id |

`--json` prints the plan (`plan`, `file`, `source`, `target`, `count`, `blocked`, `unchecked`, `changes[]`,
`remarks[]`) plus `mode` (`dry-run` / `apply`), `applied`, `written[]` and `backups[]`. `--list --json` prints
`views[]` and `events[]`.

Not built: copy between two forms, creating the target view, server-mode and chart views.

Tests: `tests\autotest\run_v156_GCPC.ps1`.
