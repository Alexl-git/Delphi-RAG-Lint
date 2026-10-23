---
id: uses-cleanup-preview-compiler-verified-this-unit
title: Uses Cleanup Preview (compiler-verified, this unit)
summary: The removals a Uses Audit suggests, but verified by actually compiling
product: DL
group: refactoring
order: 50014
since: 0.43.0-alpha
status: shipped
updated: 1.33.0-alpha
---

# Uses Cleanup Preview (compiler-verified, this unit)

The removals a Uses Audit suggests, but verified by actually compiling.

Read this before applying a Uses Audit: it previews the same removals but verifies them by compiling, so a unit needed only by an inline routine or an IF branch is not stripped by mistake.

## How to run it

Full flag list: [uses-fix in the CLI reference](../cli.md#uses-fix).

## Flags

| Flag | Argument | Meaning | Default |
| --- | --- | --- | --- |
| `--project` | `<dproj>` |  |  |
| `--db` | `<file.sqlite>` |  |  |
| `--platform` |  |  |  |
| `--apply` |  |  |  |
| `--remove-unused` |  |  |  |
| `--only` | `<unit,...>` |  |  |
| `--format` |  |  |  |

## Where to click

* RAD Studio main menu: **drag-lint > Uses & Dependencies > Uses Cleanup Preview (compiler-verified, this unit)...**
   1. Open the unit in the editor
   2. Choose drag-lint > Uses & Dependencies > Uses Cleanup Preview (compiler-verified, this unit)...
   3. Review each candidate (verified by compiling) before applying
   4. From a shell: `drag-lint uses-fix <unit.pas> --project <dproj> --db <file.sqlite> [--apply] [--remove-unused]`

**Needs:** index

## Details

The removals a Uses Audit suggests, but verified by actually compiling -- so
a unit only needed for an inline routine or a `{$IF}` branch is not stripped
by mistake. Reach for it before applying an audit's suggestions.

### Running it from the CLI
```text
drag-lint uses-fix <unit.pas> --project <dproj> --db <file.sqlite> [--platform win32|win64] [--apply] [--remove-unused]
```
Without `--apply` this previews the cleanup; `--apply` writes it.
`--remove-unused` extends the cleanup to unused units; `--platform` selects
`win32` or `win64`.

### Asking about ONE unit, library units included

`--only <Unit>` narrows the run to the units you name. Candidates are normally
chosen from the PROJECT index, which never contains RTL, VCL or third-party
library units -- so before 2026-10-13 a library unit came back `unmatched`.
Now a unit you name that is in the uses clause is decided by compiling,
whichever index it lives in:

* no `initialization`/`finalization` section -> **removed** (needs
  `--remove-unused`);
* otherwise, when it is an interface entry -> **moved** to the implementation
  `uses` (the section keeps running, so a unit with one is never removed);
* when neither edit compiles -> `skipped`, with the reason.

The section is read from the platform library index (or `--library-db`), the
same one the `unused-unit-in-uses` rule reads. This is what the IDE's
[Fix it](fix-it.md) runs on an `unused-unit-in-uses` finding:

```text
drag-lint uses-fix Unit1.pas --project MyApp.dproj --db MyApp.sqlite --platform win32 --remove-unused --only System.Win.Registry --apply --format json
```

Each try is a real compile of the unit, so expect seconds to a minute or more
for a large unit.

### Reaching it in the IDE
drag-lint > Uses & Dependencies > Uses Cleanup Preview (compiler-verified, this unit)...

### What it needs
Required. You must have indexed the project first.

### Example
Illustrative only:
```text
drag-lint uses-fix C:\Projects\MyApp\CustomerOrder.pas --project C:\Projects\MyApp\MyApp.dproj --db C:\Projects\MyApp\_D-RAG\MyApp.sqlite --platform win32
```
This would preview the compiler-verified uses cleanup for `CustomerOrder.pas`
without changing the file; add `--apply` to write it.

---

[All features](../index.md) | [CLI reference](../cli.md) | [IDE menus](../ide.md)
