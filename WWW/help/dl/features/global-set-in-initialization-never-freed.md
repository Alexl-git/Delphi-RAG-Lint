---
id: global-set-in-initialization-never-freed
title: Global set in initialization and never freed (lint rule)
summary: "Project lint rule: a unit's initialization sets its own global to a new object and no source that names the variable frees it"
product: DL
group: linting
order: 30021
since: 1.44.1-alpha
status: shipped
updated: 1.50.0-alpha
---

# Global set in initialization and never freed (lint rule)

Project lint rule: a unit's initialization sets its own global to a new object and no source that names the variable frees it.

Read this to see when global-set-in-initialization-never-freed fires and what silences it. It runs in lint-all and lint-project over a project index.

## How to run it

```text
drag-lint lint-all [--profile <name>] [--target-compiler <ver|auto>] [--db <file.sqlite>] [--project <.dproj>] [--build-config <name>] [--rule <id>] [--disable id,...] [--output <report.txt>] [--json] [--labels] [--quiet] [--lint-third-party] [--no-preprocess] [--shared-db <db> ...] [--library-db none]
```

Example:

```text
drag-lint lint-all --db <project.sqlite> --rule global-set-in-initialization-never-freed
```

Full flag list: [lint-all in the CLI reference](../cli.md#lint-all).

## Where to click

No IDE surface: this feature runs from the CLI (see How to run it).

## Details

A unit's initialization sets its own global variable to a new object (`G:= TFoo.Create`), and no source that names the variable frees it. The object lives to process exit and shows in every leak report, which hides the leaks that matter. ON by default in `lint-all` and `lint-project`.

### Running it
```text
drag-lint lint-all --db <project.sqlite> --rule global-set-in-initialization-never-freed
drag-lint lint-project --db <project.sqlite> --rule global-set-in-initialization-never-freed
```
It needs an index that has resolved references to sections (1.44 or later).

### What it reports
One hint per variable, at the assignment. The assignment is in the section, or in a routine of the same unit that the section calls.

### What stays silent
- Any unit that names the variable and frees it: `G.Free`, `G.Destroy`, `G.DisposeOf`, `G.Release`, `FreeAndNil(G)` or any `Free...(G)`. The check is on the text, so a free in a comment also silences it.
- `G.FreeOnTerminate`, and a variable handed to `Add`, `AddObject`, `Insert`, `Push`, `Enqueue` or a `Register...` call: something else owns it.
- A constructor with an owner argument: a first argument that is an identifier other than `nil`, `True` or `False`.
- An interface-typed variable, and a type not proven to be a class: a record has a `Create` too, such as `TRegEx`. The project index and the platform library answer; with no library loaded only project classes and a short list of common RTL classes count.
- A factory call: only `.Create` proves a new object.
- A variable of another unit.

---

[All features](../index.md) | [CLI reference](../cli.md) | [IDE menus](../ide.md)
