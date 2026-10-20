---
id: add-missing-units-to-uses-whole-unit
title: Add Missing Units to uses (whole unit)
summary: "The whole-unit form of the undeclared-identifier quick-fix: resolves every unresolved name in a unit at once and adds the units that declare them"
product: DL
group: compiler
order: 90001
since: 0.43.0-alpha
status: shipped
updated: 1.32.0-alpha
---

# Add Missing Units to uses (whole unit)

The whole-unit form of the undeclared-identifier quick-fix: resolves every unresolved name in a unit at once and adds the units that declare them.

## How to run it

Full flag list: [check-unit in the CLI reference](../cli.md#check-unit).

## Flags

| Flag | Argument | Meaning | Default |
| --- | --- | --- | --- |
| `--project` | `<dproj>` |  |  |
| `--platform` |  |  |  |
| `--shadow` | `<dir>` |  |  |
| `--resolve-uses` |  |  |  |
| `--db` | `PATH` |  |  |
| `--format` |  |  |  |

## Where to click

* RAD Studio main menu: **drag-lint > Uses & Dependencies > Add Missing Units to uses (whole unit)...**

## Details

The whole-unit form of the undeclared-identifier quick-fix: resolves every
unresolved name in a unit at once and adds the units that declare them. Reach
for it after a large paste or a big refactor leaves several names unresolved.

### Running it from the CLI
```text
drag-lint check-unit <unit.pas> [--project <dproj>] [--platform win32|win64] [--shadow <dir>] [--resolve-uses] [--db PATH] [--format json|text]
```
`--resolve-uses` is what drives the add-missing-units behaviour; `--project`
and `--platform` scope the check; `--shadow <dir>` and `--format` are also available.

### Reaching it in the IDE
drag-lint > Uses & Dependencies > Add Missing Units to uses (whole unit)...

### What it needs
Optional. An index is not marked required, but resolving names to their
declaring units depends on what has been indexed.

### Example
Illustrative only:
```text
drag-lint check-unit C:\Projects\MyApp\CustomerOrder.pas --project C:\Projects\MyApp\MyApp.dproj --resolve-uses --db C:\Projects\MyApp\_D-RAG\MyApp.sqlite
```
This would resolve every unresolved name in `CustomerOrder.pas` and add the
units that declare them.

---

[All features](../index.md) | [CLI reference](../cli.md) | [IDE menus](../ide.md)
