---
id: heavy-initialization
title: Heavy work in an initialization section (lint rule)
summary: "Project lint rule: an initialization section reaches the file system, the registry, the network, a database or a dialog"
product: DL
group: linting
order: 30020
since: 1.44.1-alpha
status: shipped
updated: 1.44.1-alpha
---

# Heavy work in an initialization section (lint rule)

Project lint rule: an initialization section reaches the file system, the registry, the network, a database or a dialog.

Read this to see what heavy-initialization counts as heavy and what it cannot see. It runs in lint-all and lint-project over a project index.

## How to run it

```text
drag-lint lint-all [--profile <name>] [--target-compiler <ver|auto>] [--db <file.sqlite>] [--project <.dproj>] [--build-config <name>] [--rule <id>] [--disable id,...] [--output <report.txt>] [--json] [--labels] [--quiet] [--lint-third-party] [--no-preprocess] [--shared-db <db> ...] [--library-db none]
```

Example:

```text
drag-lint lint-all --db <project.sqlite> --rule heavy-initialization
```

Full flag list: [lint-all in the CLI reference](../cli.md#lint-all).

## Where to click

No IDE surface: this feature runs from the CLI (see How to run it).

## Details

An initialization section reaches the file system, the registry, the network, a database or a dialog. That work runs before the application has an exception handler or a window, and every process that links the unit pays for it at start, including a test runner. ON by default in `lint-all` and `lint-project`.

### Running it
```text
drag-lint lint-all --db <project.sqlite> --rule heavy-initialization
drag-lint lint-project --db <project.sqlite> --rule heavy-initialization
```
It needs an index that has resolved references to sections (1.44 or later).

### What it reports
One hint per section, at the call or reference in the section that starts the first path. The message names each category and a routine that shows it.

The section's own references and those of every routine it reaches count when they name:
- file system: `TFile`, `TDirectory`, `TStreamWriter`, `TFileStream`, `TIniFile`, `TMemIniFile`, a bare `AssignFile`, `Rewrite`, `Reset` or `FindFirst`, a member `LoadFromFile` or `SaveToFile`;
- registry: `TRegistry`, `TRegistryIniFile`;
- network: `THTTPClient`, `TIdHTTP`, `TNetHTTPClient`, `TIdTCPClient`;
- database: a member `ExecSQL`, `StartTransaction`, `Commit` or `Rollback`;
- dialog: `ShowMessage`, `MessageDlg`, `MessageBox`, `InputBox`.

A reached routine also counts through its stored facts: `touches` for the registry, the network and transactions, `sql_reads` and `sql_writes` for a database.

### What stays silent
- `TPath`: it computes strings.
- A closure the section only passes, such as a registration: the body of an anonymous method is not walked.
- A call through virtual dispatch, a callback or a library routine, and a call the index resolved only as ambiguous.
- A `finalization` section.

A path behind an `if` still counts: the index has no branch conditions, so a section that only logs on failure is reported.

---

[All features](../index.md) | [CLI reference](../cli.md) | [IDE menus](../ide.md)
