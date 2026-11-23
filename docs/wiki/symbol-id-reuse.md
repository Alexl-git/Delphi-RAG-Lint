# Stable symbol ids on an incremental index

Since 1.53.0 an incremental `index` run keeps the id of every symbol whose
declaration did not change. Before, re-indexing one file deleted all of its
symbols and inserted them again with new ids. Every row in other files that
pointed at those ids then lost its binding: the reference that called the routine,
the call edge, the member access, the resolved type. The call-target pass had to
rebind all of them, and it could find them only by name. A body edit in a unit
that many others use (a "hub") pulled every reference to every name that unit
declares into the pass.

Now the store matches each re-emitted symbol to its old row and rewrites that row
in place. Only the symbols that really disappeared are deleted. A body-only edit,
a blank line or a re-parse of an unchanged file keeps 100 % of the file's ids, and
none of its names enter the resolve scope.

## Running it from the CLI

Nothing to switch on; it is how `index` writes a file it re-parses:

```
drag-lint index --project src\cli\drag-lint.dproj --db <project.sqlite>
```

With `DRAGLINT_PROFILE=1` the calls stage reports what reuse did:

```
resolve: calls      ... symbol-id reuse: 231 kept, 0 changed, 0 added, 0 removed in 1 file(s); 0 name(s) in the name scope
```

* **kept** -- re-emitted unchanged; every foreign row stays bound.
* **changed** -- same identity, different declaration (a property's type or
  accessors, a class's ancestor, modifiers, directives). The id is kept, but every
  foreign row is detached exactly as a delete would have done, and the pass binds
  it again.
* **added** / **removed** -- new or gone; a signature change is a remove plus an
  add.
* **names in the name scope** -- what the scoped pass will re-resolve by name.

## What counts as the same symbol

The identity is the kind, the qualified name (case ignored), the signature (not
for a property), the parent's identity and the position among same-named
siblings. Positions are not part of it: a line shift keeps every id.

Some edits re-number on purpose:

* **An overload inserted before an existing one.** The resolver breaks a tie
  between same-named candidates by id, and a full index numbers them in source
  order. So within one file the ids of a name stay in source order: the later
  overloads get new ids. The names are in scope anyway.
* **A file that hosts or is an include.** The ids are still kept, but every old
  and new name of the file goes into the scope, as in 1.52 (a routine body split
  over an include reaches across files).

## When to switch it off

`DRAGLINT_NO_SYMBOL_ID_REUSE=1` writes every file the 1.52 way (delete, then
insert). Use it to compare a result or to roll back if you suspect reuse; the
database it writes is the same apart from the ids.

## How it is tested

`tests\autotest\run_v153_GH18_SYMID.ps1` runs 18 edits of a 16-unit fixture and,
for each one, compares three databases with `tools\measure\index_db_diff.py`: reuse,
the hatch and a fresh full index. A test seam that treats every changed symbol as
unchanged must make the comparison fail, so the comparison can see a stale
binding. `tests\autotest\run_v153_symid_fk_classes.ps1` fails if a new table column
holds a symbol id without saying how a kept id treats it.

Related: [Maintenance](Maintenance) (reading a long run, scoped and whole-database
passes).
