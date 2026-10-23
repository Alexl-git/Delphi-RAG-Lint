---
id: circular-uses-report-cycles-fix-plan
title: Circular Uses Report (cycles + fix plan)
summary: Finds uses cycles among indexed units and, on request, proposes a followable refactoring plan to break them
product: DL
group: graphs-reports
order: 70005
since: 0.43.0-alpha
status: shipped
updated: 1.33.0-alpha
---

# Circular Uses Report (cycles + fix plan)

Finds uses cycles among indexed units and, on request, proposes a followable refactoring plan to break them.

Read this when the compiler complains about circular references or a project dependency graph feels tangled. It finds uses cycles among indexed units and, on request, proposes a followable refactoring plan to break them.

## How to run it

Full flag list: [cycles in the CLI reference](../cli.md#cycles).

## Flags

| Flag | Argument | Meaning | Default |
| --- | --- | --- | --- |
| `--db` | `<file.sqlite>` |  |  |
| `--edges` |  |  |  |
| `--causes` |  |  |  |
| `--plan` |  |  |  |
| `--format` |  |  |  |

## Where to click

* RAD Studio main menu: **drag-lint > Uses & Dependencies > Circular Uses Report (cycles + fix plan)...**
   1. Choose drag-lint > Uses & Dependencies > Circular Uses Report (cycles + fix plan)...
   2. Read the reported cycles
   3. Ask for the plan to get the refactoring playbook that breaks them

**Needs:** index

## Details

Finds `uses` cycles among indexed units and, on request, proposes a followable
refactoring plan to break them. Reach for it when the compiler is fighting
circular references, or a project's dependency graph feels tangled.

### Running it from the CLI
```text
drag-lint cycles --db <file.sqlite> [--edges] [--causes] [--plan [--project <X.dproj>]] [--format json|text]
```
`--edges` and `--causes` add detail to the cycle report; `--plan` produces the
refactoring playbook; `--format` selects `json` or `text` output. `--fix` makes the edits
for you -- see [Fix it mechanically](#fix-it-mechanically-cycles---fix) below.

### What `--plan` gives you
A mechanical procedure, written so that a reader with no project context can
follow it literally:

* **What moves where** -- each symbol that ties the cycle together, with its kind
  and the recipe for that kind. Enums, records, constants and variables move
  unchanged into a new leaf unit `<Declaring>.Untangle` (or into an existing one that is still a leaf) (exact line ranges, doc
  comment included). A class whose method bodies use the cycle is not moved: a
  base class with just the members its consumers use is extracted instead, and
  the playbook says why. Every consuming unit is listed with its section and
  first-use line.
* **Uses decisions** -- per unit: keep the old partner, move it from the
  interface to the implementation uses, or remove it.
* **The new units' full text**, and the rule for their uses clause.
* **Every edit** (units, `.dpr`, `.dproj`) as current text + new text, bottom-up.
* **DONE** and a **checklist** ending in the re-index command and the exact
  output `cycles` must print afterwards, plus what to do for each compile error.

An interface-coupled cycle becomes a legal implementation-only one (Part A). The
optional Part B names the edge that can be cut next; re-running `--plan` after
Part A prints it as the same kind of steps. When no edge can be cut mechanically
(it carries a routine, or a class whose bodies use the cycle), the playbook says
so and gives the standard remedy instead of guessing.

### Worked example, and whether a model can follow it

[Circular Dependency Report](circular-dependency-report.md) walks through a real
four-unit cycle. The full, unabridged playbook for it is
`circular-demo/CYCLE-REPORT.md` in the repository -- that is the file to hand to
a model. Its followability is measured: Haiku at its lowest effort, given only
that report and a fresh copy of the project ("Break the cycle."), produced a
tree that compiled with 0 errors, printed the predicted `cycles` output, and
touched only the named files (4 of 4 criteria; re-run on engine 1.19.0-alpha).
The examples are regenerated from the engine and checked for drift by the test
battery, so they always show what the current `--plan` prints.

### Fix it mechanically: `cycles --fix`

`--plan` tells you what to edit; `--fix` makes the edits for you, one circular group per run,
and proves them with the compiler.

```text
drag-lint cycles --fix --project <X.dproj> --db <file.sqlite> [--cycle <n> | --unit <stem>]
                 [--part a|b|all] [--apply] [--no-backup] [--no-reindex] [--no-compile]
                 [--platform win32|win64] [--library-db <lib.sqlite>] [--rules-dir <dir>]
                 [--format json|text]
```

**Which group.** `--cycle <n>` (the number `drag-lint cycles` prints) or `--unit <stem>` (the
group that unit belongs to). Without either, the run walks the groups in order, prints each
refused one with its first refusal, and plans the first mechanical one; the text output then
ends with one line naming every group it never reached:

```text
Not planned: cycle(s) 2, 3 -- this run plans one group; add --cycle <n> to plan another
```

**Dry run (the default).** Plans the group, checks the plan against the files on disk, stages
the result in a shadow tree (`C:\TEMP\draglint_cyclefix_<pid>\`, or `--shadow-out <dir>`) and
prints the verdict. No source file of the project is written -- but the dry run **builds the
project by default** (the baseline gate), and that build writes what any build writes (dcu,
exe). `--no-compile` skips it. Exit 0 mechanical, 1 refused, 2 error (bad flags, no such group).

**Builds.** Every build is `msbuild /p:Config=Debug` of the project for `--platform` (default
`win64`; the IDE passes its active platform). The Release configuration is never built.

**Scratch.** The default shadow tree and the gate's `C:\TEMP\draglint_cyclefix_<pid>_build\`
(build logs, `reindex.log`, `all-iteration-<n>.json`) are **deleted at exit** -- the text dry run
says so on its line: `Shadow tree: <dir> (deleted at exit; --shadow-out keeps it)`. A run whose
output **cites a file in there** (a build log after an msbuild failure or timeout, `reindex.log`,
`all-iteration-<n>.json`, ...) **keeps** them, so the cited file still exists, and names each kept
dir on stderr: `drag-lint: note: cycles --fix exited 1; its scratch is kept for the files it cites: <dir>`.
A message cites a scratch file only when it exists. An ordinary refusal cites none and keeps
nothing. A `--shadow-out` dir is never deleted. In the JSON, `shadow_kept` says whether `shadow`
still exists after the run.

**Apply.** `--apply` runs the same plan, then:
1. the baseline build must pass (else `dirty-baseline`, nothing written);
2. every file it touches is backed up as `<file>.BCK<n>` (the lowest free n) plus a
   `recovery.txt`, unless `--no-backup`;
3. the edits are written and the project is built in place; one bounded repair (R4: a cast
   through the plan's ancestor, a missing leaf unit in `uses`, a re-emitted pointer type) is
   tried on a compile error, otherwise every file is rolled back. The rollback restores the
   sources byte for byte but not the DCUs the failed build wrote: **rebuild the project after a
   rollback** before you trust its output;
4. the project is re-indexed (unless `--no-reindex`) and `cycles` re-run: the output must
   equal the plan's prediction.

Exit codes with `--apply`: **0** written and verified (or written with `--no-reindex`);
**1** refused, rolled back after a compile error or build timeout, or written but not
verified; **2** error -- a write or build failed part-way (rolled back, project not changed,
or the rollback failure is named), or bad flags. `--apply --no-compile` is refused with
exit 2: an apply always builds.

**Parts.** An interface-coupled group is Part A (it becomes a legal implementation-only
group); an implementation-only one is Part B (one edge is cut). `--part a|b` asks for one;
`--part all` applies Part A and then Part B in one run, re-planning on the re-indexed project
after each iteration -- so it **needs `--apply` and refuses `--no-reindex`**.

**Recipes.** Part A moves globals into a `<Declaring>.Untangle` leaf, as `--plan` describes.
Part B cuts one edge: **R1** routine-call inversion (an edge that is exactly one routine whose
signature types all live outside the cycle is called through a procedural variable declared in
a leaf and assigned in the declaring unit's initialization section); **R2** member hand-over
(an edge that is only `is` / `as` against one class plus reads of its members: the class
implements an `I<Class>Surface` interface declared in its leaf, and the consumer uses
`Supports` / `as`).

**JSON.** `--format json` prints one `cycle-fix/1` document: `mode`, `cycles[]` (per group:
`n`, `units`, `part`, `verdict`, `recipe`, `edge`, `refusals[]`, `moves`, `uses`, `new_units`,
`edits`, `compile`, `baseline`, `repairs`, `written`, `backups`, `reindex`, `predicted`,
`actual`, `verified`), `shadow`, `shadow_kept`, `baseline`, `ok`, `exit_code`. An error that
ends the run before any group is planned (bad flags, a `--library-db` that does not open) is
the document `{schema, error, ok: false, exit_code: 2}`. Separately,
`cycles --format json --causes [--project <X.dproj>]` adds a `fix` object to every group of
the report -- `available`, `part`, `dry_run` and `apply` (the exact commands; `--project` names
the project in them, else `<your.dproj>`), `edges[]`, `reason`, and for a Part A group whose
Part B would cut an edge afterwards, `followup {from,to,recipe}`.

#### Refusal kinds

A refused group prints `Verdict: refused` and one `  - <kind>: <reason>` line per refusal.
The engine never guesses; every kind it can give:

* **Run and gate:** `dirty-baseline` (the project does not build before any edit),
  `no-compiler` (rsvars.bat missing; use `--no-compile` for a dry run), `compile-error` (the
  project does not build after the edit; rolled back), `build-timeout` (the build did not
  finish; rolled back), `build-error` (the build itself failed to run; rolled back, exit 2),
  `write-failed` (a write failed part-way; rolled back, exit 2), `stale-file` (a file changed
  after it was indexed: reindex and retry), `anchor-mismatch` (a line the plan edits is not
  what the planner saw), `non-ascii-text` (an inserted line holds a non-ASCII character and
  the file is ANSI), `outside-roots` (the plan would edit a file outside the project's own
  roots).
* **Plan:** `base-class` (a class whose bodies use the cycle would need a base class
  extracted -- a manual step), `blocked-symbol` (a declaration the move needs cannot move: a
  routine, a class whose method bodies use the cycle, an unrecognised declaration block),
  `directive` (a compiler directive inside an edited region), `unresolved-edge` (the index
  could not resolve what one unit of the group uses from another), `edge-still-used` (after
  an R1 / R2 cut the consumer still uses the declaring unit for another name, so the uses
  entry -- and the edge -- would stay), `manual-edit` (the default for any edit the planner
  cannot make mechanically).
* **R1 (routine-call inversion):** `not-a-routine`, `signature-in-cycle`,
  `overloaded-routine`, `signature-unknown`, `qualified-ref`, `routine-not-called`,
  `init-order`, `unsupported-directive`, `duplicate-identifier` (the leaf already declares the
  pointer type or variable), `unit-leaves-program` (the declaring unit is used only by the
  consumer and the program's `.dpr` does not list it: after the cut the linker drops it, its
  initialization never assigns the pointer and the call is a nil call at run time -- add the
  unit to the `.dpr` uses; a `DCCReference` alone does not link it).
* **R2 (member hand-over):** `member-write`, `construction`, `class-method`, `class-ref`,
  `type-decl`, `type-cast`, `other-ref`, `multiple-classes`, `member-unsupported`,
  `duplicate-identifier`, `no-iinterface`, `ref-counted`, `receiver-unknown`, `cast-unseen`,
  `exception-semantics`, `ancestry-unknown`, `with-member`, `unresolved-qualified-type`,
  `type-unresolved`, `leaf-uses-cycle`.

#### What stays manual

A refused group is yours: `--plan` still prints the playbook and the standard remedy for it,
and `tools\follow-cycle-plan.ps1` applies a playbook's edits literally when you have decided
to follow it by hand. Moving a class whose method bodies use the cycle, and any cut the
refusals above name, stay human decisions.

#### Per-file finding

`lint <file> --db <db> --format json` reports `circular-uses` on every unit of a cycle, with
`"fix_hint": "cycles --fix --project \"<X.dproj>\" --db \"<db>\" --unit <stem>"`; `lint-all`
keeps one finding per cycle and no hint.

### Reaching it in the IDE
* drag-lint > Uses & Dependencies > Circular Uses Report (cycles + fix plan)...
* drag-lint > Uses & Dependencies > Fix Circular Uses Mechanically (dry run)... -- a dry
  run only (the engine picks the group; no `--apply` from a menu click). Save first: the
  engine plans and compiles from the files on disk.
* View > Tool Windows > drag-lint > Uses & Deps tab, section *This project -- Circular uses
  (cycles --fix)*: one row per group, Dry run / Apply buttons. Apply asks first (Yes / No,
  default No), like the Structure tree.
* drag-lint Structure window, Diagnostics tree, right-click a `circular-uses` finding:
  *Fix this cycle (dry run)...* and *Apply cycle fix...* (a dry run, your confirmation, then
  `--apply`).

Every IDE-started run passes the IDE's active platform as `--platform`. The IDE gives each
cycle-fix job a 120 minute limit: above the longest run the engine's own limits allow one
`--apply` (three builds of up to 30 minutes -- baseline, after, one repair rebuild -- plus a
re-index and a `cycles` run of up to 10 minutes each), so the engine always times out and
rolls back first; a kill by the IDE would bypass the rollback. A `--part all` iteration gets
the same 120 minutes.

### What it needs
Required. You must have indexed the project before running this -- cycle
detection reads unit-to-unit `uses` edges from the index, not from disk.

### Example
Illustrative only, against a project database that has already been indexed:
```text
drag-lint cycles --db C:\Projects\MyApp\_D-RAG\MyApp.sqlite --plan --format text
```
This would report any `uses` cycles involving, say, the unit that declares
`TfrmMain`, plus a suggested order of moves to break them.

---

[All features](../index.md) | [CLI reference](../cli.md) | [IDE menus](../ide.md)
