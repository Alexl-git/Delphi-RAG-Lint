# extract-method and create-enum-helper through the compile gate

Since 1.52 `extract-method --apply` and `create-enum-helper --apply` build the
project before and after they write, without `--project` on the command line.
Before 1.52 they built only when `--project` was given; without it they wrote
unbuilt.

## Which project is built

The first that applies:

1. `--project <X.dproj>`.
2. The database's own project: a DB at `<dir>\_D-RAG\<base>.sqlite` belongs to
   `<dir>\<base>.dproj` when that file exists (the IDE passes `--db` only).
3. The project that names the unit: walking up from the edited unit's folder,
   the one `.dproj` whose text, or whose `.dpr` / `.dpk`, names the unit's file.

stderr names the project and how it was found:

```
extract-method: note: --apply writes through the compile gate of App.dproj (the project that names Foo.pas; --no-compile-gate writes unbuilt)
```

## What the gate does

* Build 1 fails: `REFUSED (dirty-baseline)`, exit 1, nothing written.
* Build 2 fails (the fix broke the build): every file is rolled back, exit 1.
* Both build: the files stay written (with `.BCK<n>` backups unless
  `--no-backup`), exit 0.

## No project found

```
REFUSED (no-project): extract-method --apply: no project builds C:\x\Foo.pas -- pass --project <X.dproj>, or --no-compile-gate to write unbuilt; nothing written
```

Exit 2. The same refusal is given when the nearest folder holds two or more
projects that name the unit (pass `--project` to choose one).

## Writing without a build

`--no-compile-gate` writes unbuilt, as before 1.52, and says so on stderr.

## Limits

The unit is matched to a project by FILE NAME in the project text, so a
same-named unit in another folder can match. The gate then builds a project
the edit does not reach; it still refuses a project that does not build.

Runner: `tests\autotest\run_v152_GATE2_fixers.ps1`.

## 1.52 follow-ups (BK-GATE)

* `lint --fix --apply --db <db>` on a unit that no project builds is refused like the two verbs above:
  `REFUSED (no-project)`, exit 2, nothing written (owner ruling 2026-11-18). With `--db` the project is the DB's own
  project or the one that names the unit; `--no-compile-gate` writes unbuilt. A loose file with no `--db` is
  unchanged.
* `extract-method --apply` listens for `drag-lint shutdown --db <db>`: the after-build is stopped, the files are
  rolled back, exit 1 (as `narrow-param` and `create-enum-helper`).
* A gated write says `.BCK backup written` (the gate keeps `.BCK<n>` copies), not `.bak written`.
* The IDE's Rename Symbol and Extract Method apply spawn gets a 300 s stall budget (a preview keeps 60 s); the gate
  builds the project twice, baseline and after, by design.

Runner: `tests\autotest\run_v152_BK-GATE.ps1`.
