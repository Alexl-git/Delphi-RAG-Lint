---
id: multi-project-rename
title: Rename across every project that compiles a shared unit
summary: A naming fix on a unit several project indexes own renames it in every owner or in none, after an IDE confirmation listing the projects
product: DL
group: linting
order: 30019
since: 1.29.0-alpha
status: shipped
updated: 1.38.0-alpha
---

# Rename across every project that compiles a shared unit

A naming fix on a unit several project indexes own renames it in every owner or in none, after an IDE confirmation listing the projects.

Use it when a naming finding (const-casing, type-name-prefix, ...) sits in a unit that more than one project compiles: the rename is checked and applied in every indexed project, or refused with the reason.

## How to run it

```text
drag-lint lint <path> [--rule <id>] [--disable id1,id2] [--rules-dir <dir>] [--json] [--labels] [--no-preprocess] [--library-db <lib.sqlite>]
```

Example:

```text
lint --in <f> --fix --fix-line <L> --fix-rule const-casing --db <db>
```

Full flag list: [lint in the CLI reference](../cli.md#lint).

## Flags

| Flag | Argument | Meaning | Default |
| --- | --- | --- | --- |
| `--rule` | `<id>` |  |  |
| `--disable` |  |  |  |
| `--rules-dir` | `<dir>` |  |  |
| `--json` |  |  |  |
| `--labels` |  |  |  |
| `--no-preprocess` |  |  |  |
| `--library-db` | `<lib.sqlite>` |  |  |
| `--db` | `<index.sqlite>` |  |  |
| `--project-rules` |  |  |  |
| `--stand-in-for` | `<realpath>` |  |  |

## Where to click

* Right-click in the Structure form: **Fix it**
   1. Open the Structure form (drag-lint > Show Structure)
   2. Right-click the naming finding node
   3. Choose Fix it; confirm the dialog listing the owning projects
* Right-click in the Structure form: **Fix all in unit**
   1. Open the Structure form (drag-lint > Show Structure)
   2. Right-click a node
   3. Choose Fix all in unit; confirm the dialog listing the owning projects

## Details

A naming fix renames a symbol: its declaration and every use the index knows
about. When the unit is compiled by MORE THAN ONE project, renaming it against
one project's index would leave the other projects on the old name -- a broken
build in a project nobody was looking at. Since 1.29.0 a naming fix on such a
unit renames the symbol in EVERY project that compiles it, or in none.

It applies to the seven naming fixes: `const-casing`, `method-pascalcase`,
`local-var-casing`, `field-name-prefix`, `param-name-prefix`,
`type-name-prefix`, `local-field-prefix`. Every other fix is unchanged.

### Which projects count

A project counts as an OWNER of the unit when its drag-lint index contains the
unit's FULL PATH (case does not matter). Every index the manifest lists is
checked. Two consequences:

* A project that compiles its OWN copy of a unit with the same name is not an
  owner -- only the exact file counts.
* A project that compiles the unit but has NO drag-lint index cannot be seen,
  and is not renamed. The confirmation says so. The remedy is to add the
  project to the manifest (`drag-lint register-project <file.dproj> --apply`)
  and index it.
* A project the manifest lists but whose index FILE does not exist yet (a
  section never built) is "no index", not an error: it is not checked, never
  blocks a fix, and is named on a `rename-unindexed: <section> (<db>)` line and
  in the confirmation -- for a single-owner unit too: any `rename-unindexed:`
  line makes the IDE ask first (see Fix it, step 2).

A unit only one project owns, with every configured project indexed, is fixed
as before -- no preview dialog for Fix it, no `rename-owners` /
`rename-project` / `rename-target` lines. What a
single-project user CAN now see:

* every naming fix probes the manifest and opens each configured index
  read-only to find the unit's owners (one SQL lookup per index);
* the fix is REFUSED (fail-closed) when that probe cannot answer: the manifest
  did not load completely, or an index that exists cannot be opened (locked,
  corrupt) -- `rename-unknown:` plus `autofix: rename refused -- ownership unknown: ...`;
* a `rename-unindexed:` line for each configured index whose file does not
  exist.

### In the IDE: Fix it

Right-click a naming finding in the Structure form and choose "Fix it".

1. A PREVIEW runs first, in the background. It writes no source file and no
   index: an owner whose index is stale is NOT reindexed by the preview -- it
   is reported `index=stale (<n> changed file(s))` and planned on its index as
   it is, so its reference count is provisional.
2. If the unit has two or more owners, a confirmation opens:
   * the rename (`Rename Lot_Notes -> LotNotes in BASICS.PAS?`);
   * every owning project with its index state and how many references it
     holds (`DMTEST -- index fresh, 1 reference(s)`);
   * what will NOT be renamed, if anything;
   * when any owner is stale: `<N> project index(es) are stale and will be reindexed before writing -- this can take several minutes.`;
   * the note that only projects with a drag-lint index were checked, naming
     the configured projects whose index was never built:
     `Not checked (no index): <section>[, <section>] -- projects without a drag-lint index may still compile this unit.` (up to 10 sections, then
     `and K more`).

   A unit with ONE owner also gets this confirmation whenever the preview
   printed a `rename-unindexed:` line: one project index owns it, but a
   configured project with no index may compile it too and would stop
   compiling if only the indexed one were renamed. The dialog says one project
   index owns the unit and names the unindexed sections as above.

   The default button is **No**. No writes nothing, in any file.
3. Yes runs the APPLY: it reindexes every stale owner first (`index --project`,
   the owner's own index DB is written), plans again on the fresh indexes,
   applies the rename in every owner, reloads the editor buffer, reindexes and
   re-lints. The apply can still drop a rename the preview showed (it says so).

A Fix it is ALL OR NOTHING: if any owner cannot take the rename, nothing is
written and the Diagnostics root row says why, e.g.
`rename refused -- project DMTEST: name LotNotes already declared in uLots`.

### In the IDE: Fix all in unit

When the unit has any naming finding (and the project has an index), "Fix all
in unit" counts the naming findings too, and ALWAYS asks before renaming:

* a unit one project owns: `Rename N identifier(s) in <project>?` -- or, when
  the preview printed a `rename-unindexed:` line, the confirmation above with
  its `Not checked (no index): ...` line;
* a shared unit: the multi-project confirmation above, listing up to 10
  renames and up to 10 that will not be done (`... and K more`).

Both default to No. Unlike Fix it, Fix all drops only the renames that cannot
be done safely, lists them, and applies the rest.

### When a rename is refused, and what to do

| Reason in the message | What it means | What to do |
|---|---|---|
| `name X already declared in <unit>` | the new name would clash with, or capture, a symbol in that project | the other candidate styles were tried and were taken too; rename by hand to a free name |
| `unverified -- still stale after reindex: <file> -- if this DB was once widened by a folder index, rebuild it: ...` | the owner's index could not be brought up to date | `drag-lint index --project <file.dproj> --db <db>`; if it stays stale, `... --rebuild` (rows a folder index once swept in are only cleared by a rebuild), then retry |
| `unverified -- index was built from project <P>, not <X>.dproj -- rebuild it: drag-lint index --project <pf> --db <db> --rebuild` | the owner's index is stamped with ANOTHER project's tag: it is that project's closure, so its counts for this project are meaningless (a reindex would keep the other closure's rows, so none is attempted) | run the named `--rebuild`, or point the section at the right DB, then retry |
| `unverified -- still missing after reindex: N project member(s) not in the index: <files> -- rebuild it: ...` | a unit the `.dproj`/`.dpr` declares has no row in the owner's index, and the apply's reindex did not add it (a preview reports the same owner `index=stale (N project member(s) not in the index: ...)` and plans on it as is) | check the unit is really a member (`reconcile-project` on a COPY of the DB), run the named `--rebuild`, then retry |
| `unverified -- no project file -- folder DBs are not reindexed by a rename` | the owner is a folder index, not a project index | index that code as a project, or rename by hand |
| `library <Sec>: a library unit is not project code` | the unit is in a library index | do not rename library code from a project |
| `ownership unknown: <db>: <reason>` | an index that exists could not be opened (locked, corrupt) | close what holds it, or rebuild it, then retry |
| `ownership unknown: manifest did not load completely: <file>` | a `drag-lint.json` / `.drag-lint.json` has a syntax error, so the owners cannot be known -- EVERY naming fix is refused until it is fixed | fix the named file |
| `two projects edit <file> line N col M differently` | the owners disagree about a reference | reindex both owners; if it persists, report it |
| `rename-dropped-at-write: ... (stale)` | the file changed on disk between planning and writing; the WHOLE rename was dropped | save, let the index catch up, retry |

A naming fix the index cannot place because the index is stale says so instead
of `no fixable findings` (`<N>` is 0 when nothing else in the run was fixable):

```text
autofix: <N> fixable finding(s), <K> skipped (stale index) -- reindex: drag-lint index --project "<proj>" --db "<db>"
```

### From the CLI

Single finding (all or nothing), preview then apply:

```text
drag-lint lint --in C:\Projects\DB\ORM3\COMMON\BASICS.PAS --fix --fix-line 48 --fix-rule const-casing --db <db>
drag-lint lint --in C:\Projects\DB\ORM3\COMMON\BASICS.PAS --fix --fix-line 48 --fix-rule const-casing --db <db> --apply
```

Batch (every fix is on by default since 1.37.0; `--fix-naming` is still accepted
and does nothing; list a rule in `"autofix_off": [...]` in `drag-lint-lint.json`
to withhold it). The dry run prints `rename: N symbol(s) across M project(s)`
before `--apply` writes:

```text
drag-lint lint --in <f> --fix --fix-naming --db <db>            (preview)
drag-lint lint --in <f> --fix --fix-naming --db <db> --apply
```

For a unit with two or more owners (or when ownership is unknown) the output
carries the plan:

```text
rename-owners: 4 of 37 indexes
rename-project: Micronite2027 index=fresh
rename-project: DMTEST index=stale (2 changed file(s))
rename-target: L48 Lot_Notes -> LotNotes apply Micronite2027=3 DMTEST=1
rename-target: L52 Other_X -> ? dropped project DMTEST: name OtherX already declared in uFoo
rename-unindexed: TEST_Foo (C:\Projects\...\_D-RAG\TEST_Foo.sqlite)
```

* `rename-owners:` -- owners found, of how many existing indexes checked.
* `rename-project:` -- per owner: `index=fresh`, `stale` (preview only, with
  the changed-file count), `reindexed` (apply only), `unverified` (with the
  reason in parentheses) or `library`.
* `rename-unknown:` -- an index that exists but could not be read, or the
  manifest.
* `rename-unindexed:` -- a configured index whose file does not exist (printed
  on any run that plans naming fixes, single-project units included).
* `rename-target:` -- per rename: `apply` with the references per project, or
  `dropped` with the reason.
* `rename-dropped-at-write:` -- a rename dropped whole by the write-time check.
* `autofix: rename refused -- <reason>` -- a single-finding fix that wrote
  nothing; always the last `autofix:` line.
* `rename-local: <N>` (stderr, only with the `--fix-naming` no-op flag) -- naming renames in
  units one project owns.

With `--json`, stdout stays one JSON document (the `rename-*` lines go to
stderr) and each finding gains `projects` (`name`, `index`, `refs`) and
`dropped_reason`.

### What it needs

* A drag-lint index for the active project (the IDE does not offer naming
  fixes without one).
* A manifest that loads cleanly, listing an index for every project that
  compiles the unit.
* A stale owner is reindexed automatically with `index --project` -- by the
  APPLY only, never the preview (only the changed files are re-parsed, but the
  resolve stages run over the whole project: measured 2026-10-14 on copies,
  MicroniteMW1Service ~69 s with 2 of 471 files changed, TEST_uSetupDefaultsFrm ~11 s with 1 of 38).

See also: [Fix it](fix-it.md), [Fix all in unit](fix-all-in-unit.md).

---

[All features](../index.md) | [CLI reference](../cli.md) | [IDE menus](../ide.md)
