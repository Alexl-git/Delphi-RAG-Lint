---
id: compile-diagnose
title: Compile & Diagnose
summary: Compiles a project or unit and folds the compiler's errors and warnings into drag-lint findings
product: DL
group: compiler
order: 90005
since: 0.0.0
status: shipped
updated: 1.33.0-alpha
---

# Compile & Diagnose

Compiles a project or unit and folds the compiler's errors and warnings into drag-lint findings.

Read this when you want compiler errors and warnings for the current file or project inside the IDE. It compiles the project or unit and folds the compiler messages into drag-lint findings.

## Where to click

* RAD Studio main menu: **drag-lint > Compile & Diagnose**

## Details

Compiles a project or unit and folds the compiler's errors and warnings
into drag-lint findings. Reach for it to get compiler diagnostics for the
current file or project without leaving the IDE.

### Running it from the CLI
The feature map lists this action's CliVerb as "(none - in-process)", but
this IDE action actually runs the `compile-check` verb:
```text
drag-lint compile-check <target.dproj|.pas> [--db PATH] [--format json|text]
```
`<target.dproj|.pas>` is the project or unit to compile; `--db` is an
index database; `--format` selects `json` or `text` output.

### Reaching it in the IDE
drag-lint > Compile & Diagnose

### What it needs
The feature map marks this row's Index column "n/a". It needs an active
project or the current file to compile, and an open editor to show the
resulting diagnostics.

### Example
Illustrative only:
```text
drag-lint compile-check C:\Projects\MyApp\MyApp.dproj --format json
```
This would compile `MyApp.dproj` and print the resulting diagnostics as
JSON.

---

[All features](../index.md) | [CLI reference](../cli.md) | [IDE menus](../ide.md)
