---
id: rename-symbol
title: Rename Symbol
summary: Renames a symbol across the whole indexed project
product: DL
group: refactoring
order: 50012
since: 0.24.0-alpha
status: shipped
updated: 1.46.0-alpha
---

# Rename Symbol

Renames a symbol across the whole indexed project.

Read this instead of a text find and replace when a symbol appears in many units. It renames the symbol and every reference the index knows about across the indexed project in one step (Ctrl+Alt+R in the IDE).

## How to run it

Full flag list: [rename in the CLI reference](../cli.md#rename).

## Flags

| Flag | Argument | Meaning | Default |
| --- | --- | --- | --- |
| `--kind` |  |  |  |
| `--name` | `<QName>` |  |  |
| `--to` | `<New>` |  |  |
| `--json` |  |  |  |
| `--apply` |  |  |  |
| `--plan` |  |  |  |
| `--project` | `<X.dproj>` |  |  |
| `--library-db` | `<lib>` |  |  |
| `--no-backup` |  |  |  |
| `--db` | `<db>` |  |  |

## Where to click

* RAD Studio main menu: **drag-lint > Rename Symbol...**
   1. Put the caret on the symbol in the editor (Ctrl+Alt+R)
   2. Choose drag-lint > Rename Symbol...
   3. Enter the new name and review the affected places
   4. Confirm; backups are written unless disabled

**Needs:** index

## Details

Renames a symbol across the whole indexed project. Reach for it instead of
a text find/replace when a symbol appears in many units, so every
reference is updated together.

### Running it from the CLI
The feature map's Mechanism column marks this row "delegates" -- the menu
item runs the CLI `rename` verb rather than an in-process edit:
```text
drag-lint rename --kind symbol --name <QName> --to <New> [--json|--apply|--no-backup] --db <db>
```
Two related forms also exist: `--kind param --in <F> --line <L> --col <C> --to <New> [...]` for a routine-local parameter/var rename, and
`--qname <Foo.TBar.Baz> --to <NewName> [--db PATH] [--dry-run] [--no-backup]`.
Without `--apply` (or with `--dry-run`), the run is a preview only. `--plan [--json]` adds what was decided and every refusal, exit 0.

**Include files.** The index records no references inside `{$I}` included
text yet. So when the old name is used as an identifier in an
`.inc` file the index holds (comments and string literals are ignored), both
the preview and `--apply` REFUSE with exit 2 and name the `.inc` file(s),
instead of renaming the declaration and leaving those uses stale. Rename the
include's uses by hand together with the declaration.

### Same-named handlers and .dfm bindings
A handler name shared by several forms (for example `Button1Click`) is renamed
only on the form that owns the symbol being renamed, and on forms that inherit
from it. A same-named handler declared on any other form is left untouched, and
so is its `.dfm` binding. The `.dfm` event bindings (`OnClick = Button1Click`)
that point at the renamed handler are rewritten with the declaration, again only
for the owner form and the forms inheriting from it. `--apply` keeps each file's
encoding, BOM and line breaks. A BINARY `.dfm` of the owner form that holds the name as an identifier refuses every form of the verb (exit 2, naming the file), because event bindings are rewritten in text `.dfm` files only. A binary `.dfm` of a descendant form, or a text `.dfm` that is not in the index, is noted on a preview and refuses `--apply` (`dfm-not-rewritten`): a form that no longer loads is no compile error.

### What --apply proves
A rename that compiles can still bind differently, and dcc cannot see it. So `--apply` walks every identifier token of the
old name in the project's sources, not only the refs the index holds, and decides each one:

- the target's: a declaration, an implementation header, a ref bound to it, an unbound ref whose receiver's static type
  reaches the target first, a property's `read`/`write`/`stored`, an `inherited` call, the iterator of `for X in`, a field
  name in a record constant (decided by the constant's declared type: `(Alpha: 1)` on a `TOtherPt` is not `TPoint2.Alpha`);
- another symbol's: bound elsewhere, or the receiver's chain reaches another declarer or the library first;
- otherwise a refusal, by name, with `file:line:col`. Nothing is written.

A method renames with its overloads, overrides and interface implementers, all or nothing. Then every token of the NEW name
is checked: a bare `Helper` that bound to a global would bind to a member renamed to `Helper` inside its class, and that
compiles. So would a call renamed to a name a local of that routine already has.

A form component (a published field of a form class) renames with its form: `object Name: TType`, `inherited Name: TType`, `Prop = Name` and `Prop = Owner.Name` in the owning form's and its descendants' text `.dfm`. A same-named component of another form is that form's and is left alone. Text in strings, such as `FindComponent('Name')`, is not looked at.

A symbol declared inside a routine (a local, a parameter, a local constant or type, a nested routine) is proved inside that routine, in every form of the verb: no other unit can name it or capture the new name, and no library is needed. A parameter's implementation header renames with its declaration. Any bare occurrence of the new name in the routine, a declaration included, refuses (`capture-local`); so does an `{$I}` inside the routine (`no-ref-occurrence`), because included text holds no refs.

| refusal | why |
|---|---|
| `receiver-untyped` | an unbound ref whose receiver has no typed ref: a subscript the index cannot type (`F()[0].X`, a project class with a default property, a generic parameter), a chain over lines, a library-only cast |
| `bare-unbound` | an unbound ref with no receiver |
| `no-ref-occurrence` | a token the index holds no ref for: an inactive `{$IFDEF}` branch, or a chain the parse dropped |
| `unresolved-ancestor`, `no-library`, `ambiguous-type` | the receiver's chain cannot be walked to its end |
| `helper-member`, `overload-set`, `invisible-member` | the first declarer is not certainly what the compiler picks |
| `low-confidence`, `conflicting-binding` | the resolver's binding of the token is not certain |
| `override-of-library`, `implements-unindexed`, `group-name-differs`, `group-uncertain` | the method group cannot be renamed whole |
| `redeclared-property` | a descendant republishes the property |
| `dfm-not-rewritten`, `dfm-name-unbound` | a form may name it and cannot be rewritten: binary, a published property, or a component name under an `inline`, in a list, in a form whose root class is not indexed |
| `new-name-collides`, `new-name-in-library` | the new name meets a member of the class family, a unit-level symbol, or the library |
| `capture-bare`, `capture-unbound`, `capture-no-ref`, `capture-in-with` | an occurrence of the new name could bind to the renamed symbol |
| `shadowed-at-site`, `shadowed-in-with` | something nearer answers to the new name at a renamed site |
| `with-undecided`, `with-needs-index`, `capture-local` | a routine's local: an occurrence under a `with`, or a routine already using the name |
| `no-facts` | the index predates `ref_receivers`: run `index --resolve-only` |
| `no-project`, `no-compile` | a write needs the compile gate |

A proved rewrite then passes the compile gate (`--project`; `--platform`, `--rsvars`, `--build-timeout`, `--no-backup`):
baseline build (`dirty-baseline`), all-or-nothing write, after build, rollback (`compile-error`, exit 1). `--library-db`
names the platform library; the manifest's is the default.

The same proof stands behind the LSP's `textDocument/rename` (a refusal answers error -32803 with its kind) and the
`lint --fix` naming fixes (`skipped (not-proved): N` on stderr, one `note:` per finding; `--fix-line` prints
`autofix: rename refused`). The only exception is a re-casing (`doIt` to `DoIt`): identifiers are case-insensitive, so it
cannot change a binding and a token it misses still compiles. Neither path builds: the LSP only describes the edit, and
`lint --fix` writes without the gate.

**A unit other projects compile.** The manifest's indexes say which projects own each edited file (by full path, as
[Multi-Project Rename](multi-project-rename.md) does). Every owner's index is proved too, its edits merged, its refusals
named `project B: ...`; `--plan` prints `also: the gate builds <dproj>`; `--apply` builds every owner before and after the
write and rolls all of it back when any of them fails, naming that project. A stale owner is reindexed first by `--apply`,
never by a preview.

| refusal | why |
|---|---|
| `owner-library` | a registry library's index holds the file: a library unit is not project code |
| `owner-unknown` | an index or the manifest could not be read, so a project may be missed |
| `owner-unverified` | an owner's index cannot be trusted (another project's closure, still stale) or does not hold the target |

A folder index that owns the file is proved but cannot be built; a `note:` says so.

### What it needs
An index IS required. The project's DB lives at
`<project folder>\_D-RAG\<project file>.sqlite`; run
`drag-lint resolve-dbs --project <X.dproj>` if unsure.

### Example
Illustrative only:
```text
drag-lint rename --kind symbol --name CustomerOrder.TCustomerOrder.Total --to GrandTotal --db C:\Projects\MyApp\_D-RAG\MyApp.sqlite --apply
```
This would rename `Total` to `GrandTotal` everywhere it is referenced in
the index.

---

[All features](../index.md) | [CLI reference](../cli.md) | [IDE menus](../ide.md)
