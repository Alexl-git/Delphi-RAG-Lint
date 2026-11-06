---
id: run-lint-all-full-report
title: Run Lint All (Full Report)
summary: Runs the whole rule catalog against a project's indexed code and reports every surviving finding -- the overall project health check
product: DL
group: linting
order: 30035
since: 0.61.0-alpha
status: shipped
updated: 1.45.0-alpha
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
| `--shared-db` | `<db>` | another project index, repeatable: evidence for a closure-dependent dl:ok on a dl:shared unit |  |
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

* A second --db is the library slot, not another project: to judge a dl:ok on a dl:shared unit use --shared-db.
* `--library-db <lib>` names the library slot too and wins over a second --db and the manifest; a missing file refuses (exit 2), `none` means no library. Without a library, a type whose ancestry lives there stays unknown and the type-aware rules stay silent on it.
* lint `<file>` is a strict SUBSET: project-wide rules can only fire in lint-all.
* A vendored folder INSIDE the project folder is linted as your own code until `excludeRoots` names it in `<project>\_D-RAG\drag-lint-project.json`.

## Details

Runs the full rule catalog (308 rules, 260 on by default across 18 categories,
110 auto-fixable) against a project's indexed code and reports every surviving
finding. Reach for it as the overall project health check.

### Running it from the CLI
```text
drag-lint lint-all [--db <file.sqlite>] [--library-db <lib>|none] [--project <.dproj>] [--disable id,...] [--output <report.txt>] [--json] [--quiet] [--lint-third-party] [--shared-db <db> ...]
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

### Judging a marker on a unit several projects share

A `dl:ok` for a closure-dependent rule (project-scope, class-metric, taint,
doc-drift, cross-file `duplicate-code`) on a unit whose `dl:shared` marker lists
several projects may be live only under another project's compile closure. One
index cannot tell, so a plain `lint-all` skips the verdict on such a marker and
says how many it left unjudged, in one note on stderr.
`--shared-db <db>`, repeatable, names the other projects' indexes:
```text
drag-lint lint-all --db <A.sqlite> --shared-db <B.sqlite>
```
Each `--shared-db` runs as its own `lint-all --db <it>` (a full run per peer, with
the same `--rule`, `--enable`, `--disable`, `--config`, `--platform`,
`--target-compiler`, `--no-preprocess` and `--lint-third-party`), and the report stays the primary's:

* `review-marker-unused` only if NO DB produces the finding.
* `review-marker-stale` when a peer's finding no longer matches the marker's hash,
  naming that peer.
* No verdict -- today's skip -- when fewer DBs scanned the unit than its `dl:shared`
  lists, when a DB has no evidence for the line (preprocessor-blanked, undecided),
  or when a peer could not run (named on stderr). A closing note counts the markers
  judged and left.

`--db A --db B` is NOT this: the second `--db` is the library slot.

`--library-db <lib>` names that slot as well: it wins over a second `--db` and the manifest, a file that does not exist refuses (exit 2), and `none` means no library. The type-aware rules read the library for ancestry (`TLabel`, `TStringList`, `TThread`), so without it they stay silent on those types.

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
