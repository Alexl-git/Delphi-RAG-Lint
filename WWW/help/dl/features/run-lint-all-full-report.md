---
id: run-lint-all-full-report
title: Run Lint All (Full Report)
summary: Runs the whole rule catalog against a project's indexed code and reports every surviving finding -- the overall project health check
product: DL
group: linting
order: 30023
since: 0.61.0-alpha
status: shipped
updated: 1.38.0-alpha
---

# Run Lint All (Full Report)

Runs the whole rule catalog against a project's indexed code and reports every surviving finding -- the overall project health check.

Read this when you want an overall health check of a project: it runs the whole rule catalog over the indexed code and reports every surviving finding, optionally limited to one project with --project.

## How to run it

Full flag list: [lint-all in the CLI reference](../cli.md#lint-all).

## Flags

| Flag | Argument | Meaning | Default |
| --- | --- | --- | --- |
| `--db` | `<file.sqlite>` |  |  |
| `--project` | `<.dproj>` |  |  |
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

* RAD Studio main menu: **drag-lint > Code Quality > Run Lint All (Full Report)...**
   1. Open the project in RAD Studio (its index must be current)
   2. Choose drag-lint > Code Quality > Run Lint All (Full Report)...
   3. Read the findings in the report
   4. From a shell: `drag-lint lint-all [--db <file.sqlite>] [--project <.dproj>] [--output <report.txt>]`

## Pitfalls

* lint `<file>` is a strict SUBSET: project-wide rules can only fire in lint-all.
* A vendored folder INSIDE the project folder is linted as your own code until `excludeRoots` names it in `<project>\_D-RAG\drag-lint-project.json`.

## Details

Runs the full rule catalog (290 rules, 246 on by default across 18 categories,
111 auto-fixable) against a project's indexed code and reports every surviving
finding. Reach for it as the overall project health check.

### Running it from the CLI
```text
drag-lint lint-all [--db <file.sqlite>] [--project <.dproj>] [--disable id,...] [--output <report.txt>] [--json] [--quiet] [--lint-third-party]
```
`--project <.dproj|.dpr>` reports only on the units that project compiles (its
compile closure + their `.dfm` siblings) -- use it when one folder holds
several projects, or when the DB spans more than the project you are
reviewing. `--quiet` suppresses per-file progress lines written to stderr.
`--lint-third-party` restores the old unscoped whole-index count instead of
only the project's own roots. The own roots come from `ownRoots` in
`<project>\_D-RAG\drag-lint-project.json` (default: the project folder);
`excludeRoots` carves a vendored subfolder out of them, e.g.
`{ "ownRoots": ["."], "excludeRoots": ["vendor"] }` -- an excluded folder is
named in the skip block like any third-party root. `--disable id,...` turns off specific rule ids;
`--output` writes the report to a file; `--json` emits JSON.

The shared Output/CI flags also apply: `--format sarif`, `--fail-on <level>`,
`--config <file>`, `--enable id1,id2`, `--profile <name>`, `--baseline <file>`,
`--write-baseline <file>`.

### What it needs
The `--db` flag is optional -- drag-lint auto-resolves the project's index
when omitted. An index must still exist.

### Example
Illustrative only:
```text
drag-lint lint-all --project C:\Projects\MyApp\MyApp.dproj --db C:\Projects\MyApp\_D-RAG\MyApp.sqlite --output report.txt
```
This would report every surviving finding across `MyApp`'s own compile
closure and write it to `report.txt`.

---

[All features](../index.md) | [CLI reference](../cli.md) | [IDE menus](../ide.md)
