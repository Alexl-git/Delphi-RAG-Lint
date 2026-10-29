---
id: cycles-fix
title: Cycles fix (mechanical, compile-gated)
summary: Plans, compile-gates and (with --apply) writes the mechanical fix of one circular uses group, verified against the predicted cycles output
product: DL
group: graphs-reports
order: 70006
since: 1.33.0-alpha
status: shipped
updated: 1.36.0-alpha
---

# Cycles fix (mechanical, compile-gated)

Plans, compile-gates and (with --apply) writes the mechanical fix of one circular uses group, verified against the predicted cycles output.

cycles --fix makes the edits a --plan playbook describes: a dry run that builds and stages the result, or --apply with .BCK backups, an in-place build, rollback on a compile error or a build timeout (no time limit by default; `--build-timeout <s>`; Cancel stands down, rolls back, exit 1 cancelled -- rolled back; kill after 90 s) and a re-indexed verify. It moves shared types into a leaf unit, inverts a call through a pointer, or extracts an interface. A cycle it cannot cut is refused with one line per reason, never half-written. --rsvars names the Studio build environment.

## How to run it

Full flag list: [cycles in the CLI reference](../cli.md#cycles).

## Flags

| Flag | Argument | Meaning | Default |
| --- | --- | --- | --- |
| `--db` | `<file.sqlite>` |  |  |
| `--edges` |  |  |  |
| `--causes` |  |  |  |
| `--plan` |  |  |  |
| `--project` | `<X.dproj>` |  |  |
| `--f2047` |  |  |  |
| `--fix` |  |  |  |
| `--cycle` | `<n>` |  |  |
| `--unit` | `<stem>` |  |  |
| `--part` |  |  |  |
| `--apply` |  |  |  |
| `--no-backup` |  |  |  |
| `--no-reindex` |  |  |  |
| `--no-compile` |  |  |  |
| `--shadow-out` | `<dir>` |  |  |
| `--rsvars` | `<rsvars.bat>` |  |  |
| `--build-timeout` | `<s>` |  |  |
| `--format` |  |  |  |
| `--library-db` | `<lib.sqlite>` |  |  |
| `--platform` |  |  |  |
| `--rules-dir` | `<dir>` |  |  |

## Where to click

* RAD Studio main menu: **drag-lint > Uses & Dependencies > Fix Circular Uses Mechanically (dry run)...**
   1. Save all files (the engine plans and compiles from disk)
   2. drag-lint > Uses & Dependencies > Fix Circular Uses Mechanically (dry run)...
   3. Read the verdict in the report: mechanical, or refused with one line per refusal
* Tool window: **View > Tool Windows > drag-lint > Uses & Deps > This project -- Circular uses (cycles --fix)**
   1. View > Tool Windows > drag-lint, tab Uses & Deps
   2. In the Circular uses section tick one group
   3. Dry run to see the verdict, then Apply and answer Yes to write, build and verify it
* Right-click in the Structure form: **Fix this cycle (dry run)...**
   1. In the drag-lint Structure window, Diagnostics tree, right-click a circular-uses finding
   2. Fix this cycle (dry run)...
* Right-click in the Structure form: **Apply cycle fix...**
   1. In the drag-lint Structure window, Diagnostics tree, right-click a circular-uses finding
   2. Apply cycle fix... (runs the dry run, asks you to confirm, then --apply)

**Needs:** index, compiler

## Details

Finds `uses` cycles among indexed units and, on request, proposes a followable
refactoring plan to break them. Reach for it when the compiler is fighting
circular references, or a project's dependency graph feels tangled.

### Running it from the CLI
```text
drag-lint cycles --db <file.sqlite> [--edges] [--causes] [--plan [--project <X.dproj>]] [--f2047 [--unit <stem>]] [--format json|text]
```
`--edges` and `--causes` add detail to the cycle report; `--plan` produces the
refactoring playbook; `--f2047` narrows the report to the interface-only cycles
the compiler rejects with F2047 (`--unit <stem>` limits it to one unit's cycle);
`--format` selects `json` or `text` output. `--fix` makes the edits
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
                 [--shadow-out <dir>] [--rsvars <rsvars.bat>]
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
1. the baseline build must pass (else `dirty-baseline`, nothing written) -- except a baseline whose ONLY error is an `F2047 Circular unit reference` on a unit of the Part A group being fixed (owner ruling 2026-10-25): the plan is made anyway, `baseline.status` is `f2047-in-group`, and the build after the edit is the only proof;
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
Part B cuts one edge: **R1** routine-call inversion (each routine on the edge whose signature
types all live outside the cycle is called through a procedural variable declared in a leaf and
assigned in the declaring unit's initialization section -- one `initialization` edit for all of
them; since plan B3 an edge may carry several routines, and globals on the same edge that can move,
or a plain type a signature names (enum, record, alias), move into the same `<Declaring>.Untangle`
leaf first); **R2** member hand-over
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
  `no-compiler` (rsvars.bat missing; name it with `--rsvars <rsvars.bat>` for a Studio the registry /
  BDS does not name, or use `--no-compile` for a dry run), `compile-error` (the
  project does not build after the edit; rolled back), `build-timeout` (a build exceeded the `--build-timeout <s>` you set; rolled back), `cancelled` (the engine was asked to stand down -- IDE Cancel or `drag-lint shutdown --db <db>`; rolled back, exit 1), `build-error` (the build itself failed to run; rolled back, exit 2),
  `write-failed` (a write failed part-way; rolled back, exit 2), `stale-file` (a file changed
  after it was indexed: a dry run or `--apply --no-reindex` refuses -- reindex and retry;
  `--apply` re-indexes once, re-plans and reports `reindex_before`, and refuses only a file
  still stale after that), `anchor-mismatch` (a line the plan edits is not
  what the planner saw), `non-ascii-text` (an inserted line holds a non-ASCII character and
  the file is ANSI; a NEW unit holding such text is written UTF-8 with a BOM instead), `outside-roots` (the plan would edit a file outside the project's own
  roots).
* **Plan:** `base-class` (a class whose bodies use the cycle would need a base class
  extracted -- a manual step; the base class stands in for the class at a const / value
  parameter, a private `TArray<TX>` field, and -- plan B4 -- a local, a plain field `F: TX`, a
  `TList<TX>` / `TObjectList<TX>` field and a property read through a method accessor, each only
  when every use is on a closed whitelist; the refusal names the first site that is not. Plan B4-f:
  an IMPLEMENTATION edge that no other recipe cuts is tried with the base class too (ranked after
  R2), and there `X is TX` and `(X as TX).M` -- M pulled into the base, never assigned -- switch to
  the base class as well; a hard cast `TX(X)` stays refused, the refusal naming its line),
  `blocked-symbol` (a declaration the move needs cannot move: a
  routine, a class whose method bodies use the cycle, an unrecognised declaration block -- an
  indented `type` / `var` / `const` header and the same-line form `var GX: T = v;` are recognised),
  `directive` (a conditional compiler directive inside an edited region; `{$REGION}`,
  `{$ENDREGION}`, `{$WARN}`, `{$HINTS}` and `{$MESSAGE}` inside a uses clause are kept byte for
  byte), `unresolved-edge` (the index could not resolve what one unit of the group uses from
  another; an INTERFACE uses entry the interface uses for nothing is moved to the
  implementation uses, or removed when nothing uses it, and the refusal stays only when a
  lexical hit names an identifier and line), `edge-still-used` (after
  an R1 / R2 cut the consumer still uses the declaring unit for another name, so the uses
  entry -- and the edge -- would stay), `manual-edit` (the default for any edit the planner
  cannot make mechanically).
* **R1 (routine-call inversion):** `not-a-routine`, `signature-in-cycle`,
  `overloaded-routine`, `signature-unknown`, `qualified-ref`, `routine-not-called`,
  `init-order`, `unsupported-directive`, `duplicate-identifier` (the leaf already declares the
  pointer type or variable differently and every suffix up to 99 is taken; an identical declaration is
  reused, a different one gets the lowest free suffix). `unit-leaves-program` is NOT a refusal
  any more (since 1.34.1): when the declaring unit is used only by the consumer and the
  program's `.dpr` does not list it, the plan adds the unit to the `.dpr` uses (and a
  `DCCReference` to the `.dproj` when absent), because after the cut the linker would drop it,
  its initialization would never assign the pointer and the call would be a nil call at run time.
* **R2 (member hand-over):** `member-write` (a plain write `F := v` is carried by a read/write
  property with a one-line setter; `Inc` / `Dec(F)`, `F` passed to a var / out parameter and a
  write into a record-typed member are refused), `construction`, `class-method` (an instance
  method the consumer calls inside `with ... as TX do` is carried as an interface method, its
  signature copied verbatim and dispatch to an override unchanged; a class method or a method
  taken as a pointer is refused), `overloaded-routine`, `signature-in-cycle`, `class-ref`,
  `type-decl`, `other-ref`, `multiple-classes`, `member-unsupported` (an inherited
  member, a `default` array property or a write to an indexed property; a plain indexed property
  is carried for reading, its index list verbatim), `duplicate-identifier` (the class has a `Get<M>`
  that is not exactly `function Get<M>: <T>;` read by the property -- that one is reused -- or the
  leaf declares `I<Class>Surface` differently with every suffix taken; an identical interface is
  reused, a different one gets the lowest free suffix), `no-iinterface`, `ref-counted`, `receiver-unknown`, `cast-unseen`
  (no IInterface ancestor outside the cycle; the walk continues past one declared inside it),
  `exception-semantics`, `ancestry-unknown`, `with-member`, `unresolved-qualified-type`,
  `type-unresolved`, `leaf-uses-cycle`.

#### What stays manual

A refused group is yours: `--plan` still prints the playbook and the standard remedy for it,
and `tools\follow-cycle-plan.ps1` applies a playbook's edits literally when you have decided
to follow it by hand. Moving a class whose method bodies use the cycle, and any cut the
refusals above name, stay human decisions.

#### Per-file finding

`lint <file> --db <db> --format json` reports `circular-uses` on every unit of a cycle, at the
first intra-cycle `uses` entry of that file (implementation section preferred), with
`"fix_hint": "cycles --fix --project \"<X.dproj>\" --db \"<db>\" --unit <stem>"`; `lint-all`
keeps one finding per cycle and no hint.

### The extended example: what DL does, what it reports, what you do

`docs\examples\cycle-lab` extends `circular-demo` with the shapes `cycles --fix` refuses, one small
unit pair each, plus `illegal\` (a project the compiler rejects). Replay it with `run-lab.sh`.
Measured on 1.36.0-alpha; the playbook text alone was handed to Haiku.

| Layer | What happens | Cases |
|---|---|---|
| DL fixes (compile-gated, `cycles --fix --apply`) | Part A leaf units; the build and the program output stay identical | the four circular-demo groups, LabInit, LabExc |
| DL reports, you cut by hand | `Verdict: refused` with the kind and line, or `Nothing can be moved mechanically` + a MANUAL list | LabVar, LabCtor, LabRc, LabCls (`blocked-symbol`), LabDir, LabGuard (`directive`) |
| DL reports only | `cycles --f2047` names both interface edges and symbols; `--fix --apply` rolls back (F2047 stays) | `illegal\` |
| DL does not see it | `uses {$I file.inc}`: parse error at index time, no cycle line | LabInc |

Haiku (playbook only, no shell): the build stayed green and the output identical, but of the six
refused groups only LabDir (delete the unused guarded entry), LabCls (class and metaclass merged into
one new unit) and `illegal\` (both classes merged into one unit, forward `TIllOrder = class;`) ended
without a cycle. For LabVar, LabGuard, LabCtor and LabRc it moved one class into a `*.Untangle` unit
that still uses its partner in the interface: the cycle only changed name. Rule for the manual step:
a cut counts only when `cycles` stops printing "has interface coupling" for the pair, not when the
project compiles.
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
