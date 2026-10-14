# Multi-Project Rename

A naming fix renames a symbol: its declaration and every use the index knows
about. When the unit is compiled by MORE THAN ONE project, renaming it against
one project's index would leave the other projects on the old name -- a broken
build in a project nobody was looking at. Since 1.29.0 a naming fix on such a
unit renames the symbol in EVERY project that compiles it, or in none.

It applies to the seven naming fixes: `const-casing`, `method-pascalcase`,
`local-var-casing`, `field-name-prefix`, `param-name-prefix`,
`type-name-prefix`, `local-field-prefix`. Every other fix is unchanged.

## Which projects count

A project counts as an OWNER of the unit when its drag-lint index contains the
unit's FULL PATH (case does not matter). Every index the manifest lists is
checked. Two consequences:

* A project that compiles its OWN copy of a unit with the same name is not an
  owner -- only the exact file counts.
* A project that compiles the unit but has NO drag-lint index cannot be seen,
  and is not renamed. The confirmation says so. The remedy is to add the
  project to the manifest (`drag-lint register-project <file.dproj> --apply`)
  and index it.

A unit only one project owns behaves exactly as before: no preview dialog for
Fix it, no extra output lines.

## In the IDE: Fix it

Right-click a naming finding in the Structure form and choose "Fix it".

1. A PREVIEW runs first, in the background. It writes nothing.
2. If the unit has two or more owners, a confirmation opens:
   * the rename (`Rename Lot_Notes -> LotNotes in BASICS.PAS?`);
   * every owning project with its index state and how many references it
     holds (`DMTEST -- index reindexed, 1 reference(s)`);
   * what will NOT be renamed, if anything;
   * the note that only projects with a drag-lint index were checked.

   The default button is **No**. No writes nothing, in any file.
3. Yes applies the rename in every owner, reloads the editor buffer, reindexes
   and re-lints.

A Fix it is ALL OR NOTHING: if any owner cannot take the rename, nothing is
written and the Diagnostics root row says why, e.g.
`rename refused -- project DMTEST: name LotNotes already declared in uLots`.

## In the IDE: Fix all in unit

When the unit has any naming finding (and the project has an index), "Fix all
in unit" counts the naming findings too, and ALWAYS asks before renaming:

* a unit one project owns: `Rename N identifier(s) in <project>?`;
* a shared unit: the multi-project confirmation above, listing up to 10
  renames and up to 10 that will not be done (`... and K more`).

Both default to No. Unlike Fix it, Fix all drops only the renames that cannot
be done safely, lists them, and applies the rest.

## When a rename is refused, and what to do

| Reason in the message | What it means | What to do |
|---|---|---|
| `name X already declared in <unit>` | the new name would clash with, or capture, a symbol in that project | the other candidate styles were tried and were taken too; rename by hand to a free name |
| `unverified -- still stale after reindex: <file>` | the owner's index could not be brought up to date | `drag-lint index --project <file.dproj> --db <db>`, then retry |
| `unverified -- no project file -- folder DBs are not reindexed by a rename` | the owner is a folder index, not a project index | index that code as a project, or rename by hand |
| `library <Sec>: a library unit is not project code` | the unit is in a library index | do not rename library code from a project |
| `ownership unknown: <db>: <reason>` | an index could not be opened (locked, corrupt, missing) | close what holds it, or rebuild it, then retry |
| `ownership unknown: manifest did not load completely: <file>` | a `drag-lint.json` / `.drag-lint.json` has a syntax error, so the owners cannot be known -- EVERY naming fix is refused until it is fixed | fix the named file |
| `two projects edit <file> line N col M differently` | the owners disagree about a reference | reindex both owners; if it persists, report it |
| `rename-dropped-at-write: ... (stale)` | the file changed on disk between planning and writing; the WHOLE rename was dropped | save, let the index catch up, retry |

A naming fix the index cannot place because the index is stale says so instead
of `no fixable findings` (`<N>` is 0 when nothing else in the run was fixable):

```
autofix: <N> fixable finding(s), <K> skipped (stale index) -- reindex: drag-lint index --project "<proj>" --db "<db>"
```

## From the CLI

Single finding (all or nothing), preview then apply:

```
drag-lint lint --file C:\Projects\DB\ORM3\COMMON\BASICS.PAS --fix --fix-line 48 --fix-rule const-casing --db <db>
drag-lint lint --file C:\Projects\DB\ORM3\COMMON\BASICS.PAS --fix --fix-line 48 --fix-rule const-casing --db <db> --apply
```

Batch, with explicit consent to the naming fixes (`--fix-naming`; without it a
batch renames only rules listed in `"autofix": [...]` in `drag-lint-lint.json`):

```
drag-lint lint --file <f> --fix --fix-naming --db <db>            (preview)
drag-lint lint --file <f> --fix --fix-naming --db <db> --apply
```

For a unit with two or more owners (or when ownership is unknown) the output
carries the plan:

```
rename-owners: 4 of 37 indexes
rename-project: Micronite2027 index=fresh
rename-project: DMTEST index=reindexed
rename-target: L48 Lot_Notes -> LotNotes apply Micronite2027=3 DMTEST=1
rename-target: L52 Other_X -> ? dropped project DMTEST: name OtherX already declared in uFoo
```

* `rename-owners:` -- owners found, of how many indexes checked.
* `rename-project:` -- per owner: `index=fresh`, `reindexed`, `unverified`
  (with the reason in parentheses) or `library`.
* `rename-unknown:` -- an index (or the manifest) that could not be read.
* `rename-target:` -- per rename: `apply` with the references per project, or
  `dropped` with the reason.
* `rename-dropped-at-write:` -- a rename dropped whole by the write-time check.
* `autofix: rename refused -- <reason>` -- a single-finding fix that wrote
  nothing; always the last `autofix:` line.
* `rename-local: <N>` (stderr, `--fix-naming` only) -- naming renames in
  units one project owns.

With `--json`, stdout stays one JSON document (the `rename-*` lines go to
stderr) and each finding gains `projects` (`name`, `index`, `refs`) and
`dropped_reason`.

## What it needs

* A drag-lint index for the active project (the IDE does not offer naming
  fixes without one).
* A manifest that loads cleanly, listing an index for every project that
  compiles the unit.
* A stale owner is reindexed automatically with `index --project` (only the
  changed files are re-parsed); on a large project that can take a while.

See also: [Fix it](Fix-it), [Fix all in unit](Fix-all-in-unit).
