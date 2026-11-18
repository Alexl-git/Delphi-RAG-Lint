---
id: v152-fixer-compile-gate
title: extract-method and create-enum-helper through the compile gate by default
summary: extract-method / create-enum-helper --apply build the project before and after the write; no project found = REFUSED, --no-compile-gate writes unbuilt
product: DL
group: refactoring
order: 50023
since: 1.52.0-alpha
status: shipped
updated: 1.51.1-alpha
---

# extract-method and create-enum-helper through the compile gate by default

extract-method / create-enum-helper --apply build the project before and after the write; no project found = REFUSED, --no-compile-gate writes unbuilt.

Read this when extract-method or create-enum-helper refuses with REFUSED (no-project) or (dirty-baseline), or when you want to know which project they build. Since 1.52 --apply goes through the compile gate without --project: the project is --project, else the project a DB at `<dir>\_D-RAG\<base>.sqlite` belongs to, else the nearest .dproj (walking up from the unit's folder) whose .dproj / .dpr names the unit. A project that does not build is refused; a fix that breaks the build is rolled back. No project = refused (exit 2).

## How to run it

```text
drag-lint extract-method --in <F> --from-line <L1> --to-line <L2> --name <N> --apply [--project <X.dproj> | --no-compile-gate] [--platform <p>] [--rsvars <bat>] [--build-timeout <s>] [--no-backup]
```

Example:

```text
drag-lint extract-method --in <F> --from-line <L1> --to-line <L2> --name <N> --apply
```

Full flag list: [extract-method in the CLI reference](../cli.md#extract-method).

```text
drag-lint create-enum-helper --qname <TEnum> --db <db> --apply [--project <X.dproj> | --no-compile-gate] [--platform <p>] [--rsvars <bat>] [--build-timeout <s>] [--no-backup]
```

Example:

```text
drag-lint create-enum-helper --qname <TEnum> --db <db> --apply
```

Full flag list: [create-enum-helper in the CLI reference](../cli.md#create-enum-helper).

## Flags

| Flag | Argument | Meaning | Default |
| --- | --- | --- | --- |
| `--apply` |  |  |  |
| `--project` | `<X.dproj>` |  |  |
| `--no-compile-gate` |  |  |  |
| `--apply` |  |  |  |
| `--project` | `<X.dproj>` |  |  |
| `--no-compile-gate` |  |  |  |

## Where to click

No IDE surface: this feature runs from the CLI (see How to run it).

## Details

Since 1.52 `extract-method --apply` and `create-enum-helper --apply` build the
project before and after they write, without `--project` on the command line.
Before 1.52 they built only when `--project` was given; without it they wrote
unbuilt.

### Which project is built

The first that applies:

1. `--project <X.dproj>`.
2. The database's own project: a DB at `<dir>\_D-RAG\<base>.sqlite` belongs to
   `<dir>\<base>.dproj` when that file exists (the IDE passes `--db` only).
3. The project that names the unit: walking up from the edited unit's folder,
   the one `.dproj` whose text, or whose `.dpr` / `.dpk`, names the unit's file.

stderr names the project and how it was found:

```text
extract-method: note: --apply writes through the compile gate of App.dproj (the project that names Foo.pas; --no-compile-gate writes unbuilt)
```

### What the gate does

* Build 1 fails: `REFUSED (dirty-baseline)`, exit 1, nothing written.
* Build 2 fails (the fix broke the build): every file is rolled back, exit 1.
* Both build: the files stay written (with `.BCK<n>` backups unless
  `--no-backup`), exit 0.

### No project found

```text
REFUSED (no-project): extract-method --apply: no project builds C:\x\Foo.pas -- pass --project <X.dproj>, or --no-compile-gate to write unbuilt; nothing written
```

Exit 2. The same refusal is given when the nearest folder holds two or more
projects that name the unit (pass `--project` to choose one).

### Writing without a build

`--no-compile-gate` writes unbuilt, as before 1.52, and says so on stderr.

### Limits

The unit is matched to a project by FILE NAME in the project text, so a
same-named unit in another folder can match. The gate then builds a project
the edit does not reach; it still refuses a project that does not build.

Runner: `tests\autotest\run_v152_GATE2_fixers.ps1`.

---

[All features](../index.md) | [CLI reference](../cli.md) | [IDE menus](../ide.md)
