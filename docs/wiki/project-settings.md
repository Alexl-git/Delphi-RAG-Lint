# project-settings

Per-project switches in one place, with a command to read and write them.
`drag-lint settings list|get|set|unset` works on two files in the project's `_D-RAG` folder:

| file | holds | commit it? |
|---|---|---|
| `_D-RAG\drag-lint-project.json` | the project's settings, shared by everyone | yes |
| `_D-RAG\drag-lint-project.local.json` | this machine's overrides (written by `set --local`) | no |

Precedence, most specific first: **command-line flag > local file > project file > built-in default**.
Keys are a fixed catalog: a typo is an error (exit 2), never a silent dead key. Keys in a file
that the catalog does not know are listed as `unknown:` and are always kept when a file is rewritten,
so hand-written `_comment` lines and the older project keys survive.

## Which project

First hit wins: `--project <x.dproj|.dpr|.dpk>` (its folder); `--in <file>` (the first folder at or
above the file that holds `_D-RAG`); `--db <db>` (the folder above its `_D-RAG`); the current
directory (same walk-up). None of them: exit 2, `no project`.

## The keys

| key | type | default | `--local` | settable | what it does |
|---|---|---|---|---|---|
| `ownRoots` | path list | the project folder | no | yes | folders whose files count as the project's own code |
| `excludeRoots` | path list | `[]` | no | yes | vendored folders inside the project, not linted as your own |
| `reportsDir` | path | `<project>\drag-lint-reports` | no | yes | snapshot / report folder |
| `fieldRepository` | path | none | no | yes | field repository for the `repo` verbs (`--repo` overrides) |
| `backupDir` | path | beside the database | no | yes | folder of the database backups of `repo backup --connection` and `repo alter-table --apply` (`--backup-dir` overrides), see [[repo-db-backup]] |
| `popupForms` | object list | `[]` | no | no | forms opened as popups; edit the file by hand |
| `checkInit` | object | `{}` | no | no | `check-init` callee answers; edit the file by hand |
| `lint.config` | path | the discovery chain | yes | yes | lint config file (relative to the project folder); `--config` overrides |
| `lint.profile` | string | none | yes | yes | named lint profile when `--profile` is not given |
| `taint.envSource` | bool | `true` | yes | yes | `false`: `GetEnvironmentVariable` is not a taint source in this project |
| `fieldrepo.bde` | string | `full` | no | yes | `repo write-dfm` on a BDE dataset (TTable, TQuery, TStoredProc, TBDE*): `full` = as any dataset; `readonly` = no field insert, no field deletion, no new event handler, no grid / layout item removal (BLOCKED `BDE dataset: read only (project policy)`); `none` = no BDE in this project, the same four BLOCKED `BDE not allowed in this project` (1.55) |

`taint.envSource = false` only ever switches that one source OFF (it is added to the taint
`disable` list of the effective config); it cannot switch ON a source your lint config disabled.
A value is plain 7-bit ASCII. Lists take a JSON array (`["src","..\\lib"]`) or `a,b`; an empty
`ownRoots` is refused because it would make the project own nothing and report clean.

## The four sub-verbs

```
drag-lint settings list  --project App.dproj
drag-lint settings get   lint.profile --project App.dproj
drag-lint settings set   taint.envSource false --project App.dproj
drag-lint settings set   lint.profile strict --local --project App.dproj
drag-lint settings unset lint.profile --local --project App.dproj
```

* `list` prints `key = value  (default|project|local)` per key, then `unknown:` lines. `--json` adds
  the file paths, the type, default, flag and description of every key.
* `get` prints the effective value alone (a bool as `true`/`false`, a list or object as compact JSON).
* `set` / `unset` print one line naming the file written. Exit 0 done; **1 nothing to do** (already
  that value / key not in that file); **2** usage error, unknown key, bad value, key not settable or
  not `--local`-allowed, a file that is not a JSON object (the file is never rewritten), no project.
* `unset` removes a nested object that it leaves empty.

A write keeps key order, uses 2-space indent, CRLF and 7-bit ASCII, goes through a temp file and a
replace, and does not touch the file when the value is unchanged.

## Local file and your ignore file

`set --local` creates `drag-lint-project.local.json` and prints a note once: add
`_D-RAG/*.local.json` to your ignore file. drag-lint never edits your `.gitignore` / `.hgignore`.

## What reads the new keys

`lint` and `lint-all` read `lint.config`, `lint.profile` and `taint.envSource` for the run's project
(the `--project` folder, else the folder above the linted file or the `--db`, else the project the
`--db` was indexed from). `--config` and
`--profile` on the command line still win. A settings file that does not parse is reported as one
stderr line and ignored by the lint run; the `settings` verbs exit 2 on it. The language server's
own config discovery is not changed in this release: it spawns `lint <file>`, which reads the keys,
but a path the LSP discovers itself does not see `lint.config`.

Not part of this release (scheduled for 1.53.1): the IDE Project Manager menu over the same store, and `reportsDir` / `fieldRepository` in the local overlay.

## VS Code

The VS Code extension (drag-lint 1.6.12 and later) has the same list as a picker: Command Palette >
"drag-lint: Project Settings..." > pick a key > type or pick the value > for a key that may be local,
pick "This project (shared, committed)" or "This machine only (local file)".

- It runs `settings list --project <P> --json` for the rows and `settings set|unset ... --json` for the
  write; the extension never edits the settings files itself.
- The project is the one set with "drag-lint: Select Project" (or `dragLint.project`); without a
  .dproj the command says so and does nothing.
- Read-only rows (`popupForms`, `checkInit`) are listed with "(read-only)" and cannot be edited there.
- A bool key offers `true`, `false` and "reset to default" (an `unset`). A value whose key looks like a
  secret (secret, token, password) is shown as `********` and the input box is masked.
- After a `lint.*` or `taint.*` change the extension refreshes the Problems list.
- "Nothing to do" (exit 1, for example an unset of a key that is not set) is reported as information, not an error.