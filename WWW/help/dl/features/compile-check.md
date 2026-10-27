---
id: compile-check
title: compile-check
summary: Runs a compiler-backed check against a single Delphi project (.dproj) or source file (.pas) and reports the result
product: DL
group: compiler
order: 90003
since: 0.26.0-alpha
status: shipped
updated: 1.35.1-alpha
---

# compile-check

Runs a compiler-backed check against a single Delphi project (.dproj) or source file (.pas) and reports the result.

Read this when you want a compiler-backed check of one project or one source file without a full build. compile-check takes a .dproj or .pas target and reports the result as text or json.

## How to run it

Full flag list: [compile-check in the CLI reference](../cli.md#compile-check).

## Flags

| Flag | Argument | Meaning | Default |
| --- | --- | --- | --- |
| `--project` | `<X.dproj>` |  |  |
| `--db` | `PATH` |  |  |
| `--format` |  |  |  |

## Where to click

No IDE surface: this feature runs from the CLI (see How to run it).

## Details

Runs a compiler-backed check against a single Delphi project (`.dproj`) or
source file (`.pas`) and reports the result. Reach for it when you want a
compile-style verification of one target without a full project build.

### Running it from the CLI

```text
drag-lint compile-check <target.dproj|.pas> [--project <X.dproj>] [--db PATH] [--format json|text]
```

### What it needs

The `--db` flag is optional -- drag-lint auto-resolves the index when
omitted. An index must still exist.

### Example

Illustrative:

```text
drag-lint compile-check C:\Projects\MyApp\MyApp.dproj --format json
```

This would compile-check `MyApp.dproj` and print the result as JSON.

---

[All features](../index.md) | [CLI reference](../cli.md) | [IDE menus](../ide.md)
