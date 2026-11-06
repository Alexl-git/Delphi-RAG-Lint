---
id: opaque-to-analysis
title: Opaque to analysis (lint rule)
summary: "Project-wide lint rule (info, off by default): a routine whose non-library calls are mostly unresolvable, so impact and call trees are blind inside it"
product: DL
group: linting
order: 30029
since: 1.42.0-alpha
status: shipped
updated: 1.44.1-alpha
---

# Opaque to analysis (lint rule)

Project-wide lint rule (info, off by default): a routine whose non-library calls are mostly unresolvable, so impact and call trees are blind inside it.

Read this to find the routines the index cannot see through. It runs in lint-all over a project index plus the library index; library calls are left out, and what remains is reported with its numbers.

## How to run it

Full flag list: [lint-all in the CLI reference](../cli.md#lint-all).

## Where to click

No IDE surface: this feature runs from the CLI (see How to run it).

## Details

A project-wide lint rule, severity **info**, OFF by default: a routine whose calls that do not provably leave the project are predominantly calls the index cannot resolve.

This is a rule about the limits of drag-lint's own analysis, not a complaint about the code. `impact`, `find-callers`, call trees and dead-code detection all stand on `call_edges`. In a routine made mostly of calls with no edge, they see almost nothing, and a reader of those answers should know that.

### Running it from the CLI
```text
drag-lint lint-all --db <project.sqlite> --db <library.sqlite> --rule opaque-to-analysis
drag-lint lint-all --db <project.sqlite> --db <library.sqlite> --enable opaque-to-analysis
drag-lint lint <unit.pas> --db <project.sqlite> --library-db <library.sqlite> --rule opaque-to-analysis
```

### What it reports
One finding per routine, at its implementation line, for example:

`uContainerConfig.RegisterDependencies: 137 of 137 calls that do not provably leave the project could not be resolved (AsSingleton, AsSingletonPerThread, Build) -- impact analysis, call trees and dead-code detection are blind inside this routine`

It fires at **3 or more** opaque calls that make up **60 percent or more** of (opaque calls + calls with a `call_edges` row). An ambiguous edge counts as resolved.

### What counts as opaque
* A procedural value: a parameter, local or field called like a routine.
* A member of a receiver the index could not type, such as a chain through a cast, or `var X := Foo.Create` (`X.Bar` has no type text today).
* A project routine or member the resolver declined to pick, for example an overload tie.

### What is left out of both figures
* Compiler intrinsics and type casts (`Exit`, `Length`, `Writeln`, `Integer(x)`, `TFoo(x)`).
* A stored `refs.external_target`.
* A receiver typed by a name the project does not declare (`FMemTable.Post`): the type is known, and it is not ours.
* A project-typed receiver whose chain does not declare the member: it is inherited from outside.
* A call the library oracle binds live (`Application.ProcessMessages`, `CodeSite.Send`, an inherited `Close`, `Format`).

Dispatch into project code through a library virtual or an event is NOT counted as opaque. The rule measures what the index cannot place, not every path it cannot follow.

Without a library index the rule stays SILENT: every RTL and VCL call would read as opaque.

### How the thresholds were picked
Measured 2026-11-04 on 1.42.0-alpha indexes, before the thresholds were fixed:

| Project | Routines with 2+ opaque calls | 3+ and 50% | 3+ and 60% (shipped) | 3+ and 80% | 5+ and 60% |
|---|---|---:|---:|---:|---:|
| ORM3 CLIENT | 33 | 17 | 15 | 14 | 9 |
| ORM3 SERVER | 24 | 10 | 10 | 6 | 5 |
| YADF | 33 | 13 | 12 | 6 | 5 |

These rows predate a last addition to the intrinsic list (file I/O: `Writeln`, `Rewrite`, `CloseFile`). With it, and the shipped thresholds, the final counts are:

| Project | Findings | Opaque calls in them |
|---|---:|---:|
| ORM3 CLIENT | 14 | 91 |
| ORM3 SERVER | 9 | 582 |
| YADF | 12 | 54 |
| drag-lint engine | 244 | 1879 |

The engine's count is mostly `var X := ...` locals, which have no type text in the index.

The measurement also changed the premise. The charts team's `SendDeltaOperation` (32 calls, 2 edges) read as 30 unresolvable interface dispatches. With the library judged properly, the rest are `TFDMemTable` and `TMemoryStream` calls, RTL routines and bindable heads, and the routine does not fire.

To suppress a finding: `// dl:ok opaque-to-analysis -- <reason>` on the routine's line.

Guard: `tests\autotest\run_opaque_to_analysis.ps1` (fixture `tests\lint-project\opaque-to-analysis`).

---

[All features](../index.md) | [CLI reference](../cli.md) | [IDE menus](../ide.md)
