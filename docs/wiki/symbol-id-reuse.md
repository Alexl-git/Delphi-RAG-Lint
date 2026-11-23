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

The line before it says where the pass's references come from:

```
resolve: calls      ... scope refs: 89111 in changed files, 11997 by name, 875 by receiver text, 0 by typed use in 0 routine(s)
```

* **in changed files** -- every reference of a re-parsed file.
* **by name** -- a reference anywhere that names a removed, added or changed symbol.
* **by receiver text** -- `H.Field.Show` when `Field` moved: the receiver expression
  mentions the name, at any hop of the chain.
* **by typed use** -- in a routine that used a removed or changed symbol with a type,
  the references that can depend on that type without mentioning it: the routine's
  calls of overloaded names, or every reference of a routine with an inline variable
  typed from its initializer or a `with`.

`follow-up pass N: M ref(s)` appears when an added symbol took over a reference in an
unchanged file (a field that hides an inherited one): what depends on it in that
routine is resolved again. Usually there is none.
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

## What it costs and saves

drag-lint's own CLI project (426 files, 714,459 references), one engine, the switch
below against the default. Calls stage, median of 3 alternated runs on a busy machine:

| edit | call sites resolved | calls stage |
|---|---|---|
| blank line in `DRagLint.Analysis.Cfg.pas` (a hub) | 13,186 -> 1,009 | 44.0 s -> 4.0 s |
| blank line in `DRagLint.CLI.Hover.pas` (the run also re-parses `DRagLint.CLI.pas`) | 43,658 -> 22,231 | 148.0 s -> 97.0 s |
| 3 large units, 394 symbols added and 249 removed | 75,296 -> 48,408 | 215.3 s -> 206.5 s |

The call-site counts do not depend on the machine's load; the times do.

A one-unit edit that moves no declaration saves most; an edit that adds and removes
declarations in large units still re-resolves those whole files.

## When to switch it off

`DRAGLINT_NO_SYMBOL_ID_REUSE=1` writes every file the 1.52 way (delete, then
insert) and scopes the pass as 1.52 did. Use it to compare a result or to roll back
if you suspect reuse. It also brings back what 1.52 leaves stale after an incremental
run and reuse does not: a reference typed as a withdrawn type, a call bound through an
ancestor the class no longer has, the tail of a receiver chain whose head changed
type, a variable inferred from a changed declaration.

## Limits

A reference in an untouched file is selected by what the index stores: names, receiver
texts and bindings. A dependency that leaves none of them -- a type inferred through a
reference the resolver never bound -- is not followed; a full `--rebuild` resolves it.

## How it is tested

`tests\autotest\run_v153_GH18_SYMID.ps1` runs 26 edits of a small fixture and a chain
of edits on one database. For each it compares three databases with
`tools\measure\index_db_diff.py`: reuse, the switch, and a fresh full index. Reuse must
equal the fresh index on every edit, with no exception list. A test seam that treats
every changed symbol as unchanged must make the comparison fail. It also rolls a file
back half way through the write (its rows, ids and foreign bindings must be untouched)
and makes SQLite hand out a deleted id again in the same run.
`tests\autotest\run_v153_symid_fk_classes.ps1` fails if a new table column holds a
symbol id without saying how a kept id treats it.
Related: [Maintenance](Maintenance) (reading a long run, scoped and whole-database
passes).
