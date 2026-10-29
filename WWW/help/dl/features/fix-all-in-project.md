---
id: fix-all-in-project
title: Fix all in project
summary: Applies autofixes for every fixable finding across the whole project, starting from the Structure form
product: DL
group: linting
order: 30008
since: 0.61.0-alpha
status: shipped
updated: 1.38.0-alpha
---

# Fix all in project

Applies autofixes for every fixable finding across the whole project, starting from the Structure form.

Read this when you want every auto-fixable finding in the whole project resolved in one action. In the Structure form right-click the Diagnostics root and choose Fix all in project; it is not on the main menu and runs lint-all --fix --apply, so it can rewrite many files.

## How to run it

Full flag list: [lint-all in the CLI reference](../cli.md#lint-all).

## Flags

| Flag | Argument | Meaning | Default |
| --- | --- | --- | --- |
| `--db` | `<file.sqlite>` |  |  |
| `--project` | `<.dproj>` |  |  |
| `--build-config` | `<name>` |  |  |
| `--rule` | `<id>` |  |  |
| `--disable` |  |  |  |
| `--output` | `<report.txt>` |  |  |
| `--json` |  |  |  |
| `--labels` |  |  |  |
| `--quiet` |  | suppress per-file progress lines written to stderr |  |
| `--lint-third-party` |  |  |  |
| `--no-preprocess` |  |  |  |
| `--fix` |  |  |  |
| `--fix-naming` |  |  |  |
| `--apply` |  |  |  |

## Where to click

* Right-click in the Structure form: **Fix all in project**
   1. Open the Structure form (drag-lint > Show Structure)
   2. Right-click a node
   3. Choose Fix all in project (it is not on the main menu)

## Pitfalls

* lint `<file>` is a strict SUBSET: project-wide rules can only fire in lint-all.

## Details

Applies autofixes for every fixable finding across the whole project,
starting from the Structure form. Reach for it when you want a
project-wide sweep of autofixes in one action instead of fixing unit by
unit.

### Running it from the CLI

The menu item runs `lint-all` with the autofix flags across the whole
indexed project:

```text
drag-lint lint-all --db <project.sqlite> --fix --apply
```

Without `--apply` the command is a DRY RUN. Dry-run first -- this one can
rewrite many files at once.

Known limitation, from the plugin source: after a project-wide fix only the
CURRENT file's editor buffer is reloaded. Other edited files stay stale in
their open editor buffers until you re-open them.

### What it needs

The `--db` flag is optional -- drag-lint auto-resolves the project's index
when it is omitted. But `lint-all` does read an index, so one must exist.
The project's DB lives at `<project folder>\_D-RAG\<project file>.sqlite`;
run `drag-lint resolve-dbs --project <X.dproj>` if you are unsure which
one.

### Example

Dry run:
```text
drag-lint lint-all --db C:\Projects\MyApp\_D-RAG\MyApp.sqlite --fix
```
Apply for real:
```text
drag-lint lint-all --db C:\Projects\MyApp\_D-RAG\MyApp.sqlite --fix --apply
```

---

[All features](../index.md) | [CLI reference](../cli.md) | [IDE menus](../ide.md)
