---
id: cycle-edge-in-include
title: Cycle edge written in an include (lint rule)
summary: "Project lint rule: a uses entry or declaration a uses cycle runs through is written in an include, which cycles --fix never edits; write it in the .pas"
product: DL
group: linting
order: 30007
since: 1.50.0-alpha
status: shipped
updated: 1.50.0-alpha
---

# Cycle edge written in an include (lint rule)

Project lint rule: a uses entry or declaration a uses cycle runs through is written in an include, which cycles --fix never edits; write it in the .pas.

Read this when circular-uses names a cycle whose entries live in a {$I} include: it says what drag-lint cannot fix there and what to move into the .pas. It runs in lint-all and lint-project.

## How to run it

```text
drag-lint lint-all [--profile <name>] [--target-compiler <ver|auto>] [--db <file.sqlite>] [--project <.dproj>] [--build-config <name>] [--rule <id>] [--disable id,...] [--output <report.txt>] [--json] [--labels] [--quiet] [--lint-third-party] [--no-preprocess] [--shared-db <db> ...] [--library-db none]
```

Full flag list: [lint-all in the CLI reference](../cli.md#lint-all).

```text
drag-lint lint <path> [--profile <name>] [--target-compiler <ver|auto>] [--rule <id>|help] [--disable id1,id2] [--rules-dir <dir>] [--json] [--labels] [--no-preprocess] [--library-db <lib.sqlite>] [--build-config <name>]
```

Full flag list: [lint in the CLI reference](../cli.md#lint).

## Where to click

No IDE surface: this feature runs from the CLI (see How to run it).

## Details

A uses cycle runs through a uses entry or a declaration that is written in a `{$I}` include file. `drag-lint cycles --fix` edits uses clauses and declarations in `.pas` files and never edits an include, so it cannot untangle that cycle. This rule names the include and says what to move into the `.pas`.

### Running it
```text
drag-lint lint-all --db <project.sqlite> --rule cycle-edge-in-include
drag-lint lint-project --db <project.sqlite> --rule cycle-edge-in-include
```
It ships on, at severity hint, and runs on a project index. It uses the same strongly-connected groups that `circular-uses` reports, so the two rules always agree on which units cycle. An index built before the file facts (schema 24) yields nothing, and so does an index made with `--no-preprocess`.

### Shape U: a uses entry in an include
```pascal
unit LabIncA;
interface
uses
  {$I LabIncUses.inc}   // LabIncUses.inc holds:  LabIncB;
```
`LabIncA` uses `LabIncB` through the include, and `LabIncB` uses `LabIncA` back. The finding sits on the `{$I}` line of the host and names the host, the target, the include file (and the line inside it) and the cycle. Fix: write `LabIncB` in the uses clause of `LabIncA.pas` itself, or take the entry out of the include, then run `drag-lint cycles --plan`.

### Shape D: a declaration in an include
```pascal
unit IncDeclA;
interface
{$I IncDeclTypes.inc}   // declares TIncDeclARec
```
`IncDeclB` is in the same cycle and uses `TIncDeclARec`. `cycles --fix` would have to move the record into a leaf unit, and the record lives in a file it does not edit. The finding sits on the `{$I}` line that brings the include in and names the symbol, its kind, the include, and up to three units that use it. Only top-level declarations count: fields, members, parameters and locals are not listed. Fix: declare the type in the `.pas` of the host, or in a unit of its own.

An include shared by several units of the cycle gets one finding per host, and the message adds "also included by" the other hosts.

### What stays silent
- A uses entry or declaration written in the `.pas`.
- An include-borne entry whose target is not in the same cycle as the host.
- A declaration in an include that only units outside the cycle use.
- An index with no cycle.

### Reviewing it
A `dl:ok cycle-edge-in-include@<hash>` marker goes on the host's `{$I}` line, the line the finding is anchored at. Nothing in the include file changes.

### Why drag-lint never edits an include
An include is shared text: one `.inc` can be pulled into several units, in different configurations, and an edit made from one host cannot be proven to leave the others compiling (ruling N-06 A5). `cycles --plan` still prints the step; this rule is the reminder that the step is yours to take by hand. See [the cycles --fix plan](circular-uses-report-cycles-fix-plan.md).

---

[All features](../index.md) | [CLI reference](../cli.md) | [IDE menus](../ide.md)
