# Third-party code in a project lint-all (lane OWNFILTER, 1.54)

A project index holds everything the project compiles, third-party source included. `lint-all` leaves the
findings located in that code out, says how many and why, and never hides a unit of your own.

```
drag-lint lint-all --db <project.sqlite>
drag-lint lint-all --db <project.sqlite> --lint-third-party
```

`--lint-third-party` is the switch that shows everything again (only `exclude_paths` still applies).

## What counts as third-party

The first line that matches a file decides. **When none matches, the file is yours.**

| # | Test | Verdict |
|---|---|---|
| 1 | `exclude_paths` in `drag-lint-lint.json` | skipped |
| 2 | `excludeRoots` in `<project>\_D-RAG\drag-lint-project.json` (inside or outside the project folder) | skipped |
| 3 | `own_paths` in `drag-lint-lint.json` (path globs) | yours |
| 4 | a folder named `third_party`, `third-party`, `thirdparty`, `3rdparty`, `3rd_party`, `3rd-party` or `vendored` on the path, or one of `vendored_folders` | skipped |
| 5 | under a declared `ownRoots` folder, or under the project folder when none is declared | yours |
| 6 | `ownRoots` is declared and the file is outside it | skipped |
| 7 | under an `include` folder of the manifest's Library section | skipped |
| 8 | under an IDE library path, and the project file does not list the unit | skipped |
| 9 | nothing matched | yours |

So a `COMMON` folder beside the project, shared by several projects, is reported without any declaration. It
stays yours when it is on the IDE library path too, as long as the project lists its units (line 8).

A vendored folder name says nothing when the project itself lives under that folder, or when an `ownRoots` entry
names that folder or one inside it. A library folder that contains the project says nothing either. A folder named `vendor` is not a
built-in name, because in business code a vendor is a supplier: add it yourself.

```json
{ "vendored_folders": ["vendor", "-vendored"], "own_paths": ["*\\third_party\\our-fork\\*"] }
```

`vendored_folders` adds names; `-name` takes a built-in one out. Both keys go into `drag-lint-lint.json`.

## What the report says

```
lint-all: third-party: 3 file(s) not scanned, 5 project-wide finding(s) dropped (per-file rules did not run there); --lint-third-party shows them
          vendored folder 'third_party': 2 file(s), 4 finding(s)
          library path C:\Work\lib: 1 file(s), 1 finding(s)
          dropped by rule: unused-public-symbol 5
lint-all: 41 finding(s) -- 0 error(s), 41 warning(s), 0 info, 0 hint -- 12 file(s) scanned; 3 third-party file(s) skipped
```

A skipped file is not read, so only the findings of project-wide rules can be counted; `--lint-third-party` gives
the full number. The same lines stand in the report file.

`--json` ends with one note row when something was skipped: `rule` `third-party-skipped`, `severity` `info`,
`files_skipped`, `findings_dropped`, `reasons` (`reason`, `where`, `files`, `findings`), `rules` (rule id to
count), `show_with`. It is not a finding: it has no part in the exit code, `--fail-on` or a baseline. SARIF has no such row.

A `drag-lint-project.json` that exists but is not a JSON object (truncated, a stray comma, a list) used to default
to the project folder in silence, which widens the report. It now says so: a `lint-all: NOTE: ... is malformed` line (and in the
report file), and in `--json` a second note row, rule `own-roots-malformed`, severity `info`, `file_path` = the file.

## Limits

* A file you name (`lint <file>`, the editor, the LSP, VS Code) is always reported, third-party or not.
* A `--fix` run keeps to the own roots (the project folder when none is declared): it skips an unmarked file
  outside them instead of rewriting it, and says so. `document`, `exceptions-sync` and the refactorings use
  the own roots as before.
* An index with no project folder (a copy outside `_D-RAG`, no `--project`) is not filtered; a note says so.
