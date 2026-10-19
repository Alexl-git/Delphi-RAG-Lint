---
id: reconcile-project-members-dpr-dproj
title: Reconcile Project Members (.dpr/.dproj)
summary: Compares a project file's declared member list against what is on disk and in the compile closure
product: DL
group: refactoring
order: 50009
since: 1.18.0-alpha
status: shipped
updated: 1.18.0-alpha
---

# Reconcile Project Members (.dpr/.dproj)

Compares a project file's declared member list against what is on disk and in the compile closure.

## How to run it

Full flag list: [reconcile-project in the CLI reference](../cli.md#reconcile-project).

## Where to click

* RAD Studio main menu: **drag-lint > Uses & Dependencies > Reconcile Project Members (.dpr/.dproj)...**

## Details

Compares a project file's declared member list against what is on disk and in
the compile closure, and can also re-scan and recompile every member to heal
the index and findings. Reach for it after moving or adding units by hand.

### Running it from the CLI
```text
drag-lint reconcile-project <App.dpr|.dproj> [--apply] [--db <db>] [--full] [--json] [--config <path>]
```
`--apply` writes the sync; without it the command reports only. `--db` also
heals the index and findings for every project member (re-scan + recompile)
without editing the `.dpr`; `--full` forces the recompile even when nothing
looks incoherent.

### Reaching it in the IDE
drag-lint > Uses & Dependencies > Reconcile Project Members (.dpr/.dproj)...

### What it needs
Optional. An index is not required to run this command, but pass `--db` to
also heal the index and findings for the project's members.

### Example
Illustrative only:
```text
drag-lint reconcile-project C:\Projects\MyApp\MyApp.dproj --db C:\Projects\MyApp\_D-RAG\MyApp.sqlite
```
This would compare `MyApp.dproj`'s member list against disk and the compile
closure, and re-scan/recompile its members -- one of which might be the unit
that owns `TfrmMain`.

---

[All features](../index.md) | [CLI reference](../cli.md) | [IDE menus](../ide.md)
