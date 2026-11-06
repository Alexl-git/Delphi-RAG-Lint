---
id: rename-symbol
title: Rename Symbol
summary: Renames a symbol across the whole indexed project
product: DL
group: refactoring
order: 50012
since: 0.24.0-alpha
status: shipped
updated: 1.44.1-alpha
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
  reaches the target first, a property's `read`/`write`/`stored`, an `inherited` call;
- another symbol's: bound elsewhere, or the receiver's chain reaches another declarer or the library first;
- otherwise a refusal, by name, with `file:line:col`. Nothing is written.

A method renames with its overloads, overrides and interface implementers, all or nothing. Then every token of the NEW name
is checked: a bare `Helper` that bound to a global would bind to a member renamed to `Helper` inside its class, and that
compiles. So would a call renamed to a name a local of that routine already has.

| refusal | why |
|---|---|
| `receiver-untyped` | an unbound ref whose receiver has no typed ref: `A[i].X`, a chain over lines, a library-only cast |
| `bare-unbound` | an unbound ref with no receiver |
| `no-ref-occurrence` | a token the index holds no ref for: an inactive `{$IFDEF}` branch, a record-constant field name, `F().X`, `for X in` |
| `unresolved-ancestor`, `no-library`, `ambiguous-type` | the receiver's chain cannot be walked to its end |
| `helper-member`, `overload-set`, `invisible-member` | the first declarer is not certainly what the compiler picks |
| `low-confidence`, `conflicting-binding` | the resolver's binding of the token is not certain |
| `override-of-library`, `implements-unindexed`, `group-name-differs`, `group-uncertain` | the method group cannot be renamed whole |
| `redeclared-property` | a descendant republishes the property |
| `dfm-not-rewritten`, `dfm-name-unbound` | a form may name it and nothing rewrites that form |
| `new-name-collides`, `new-name-in-library` | the new name meets a member of the class family, a unit-level symbol, or the library |
| `capture-bare`, `capture-unbound`, `capture-no-ref`, `capture-in-with` | an occurrence of the new name could bind to the renamed symbol |
| `shadowed-at-site`, `shadowed-in-with` | something nearer answers to the new name at a renamed site |
| `with-undecided`, `with-needs-index`, `capture-local` | `--kind param`: an occurrence under a `with`, or a routine already using the name |
| `no-facts` | the index predates `ref_receivers`: run `index --resolve-only` |
| `no-project`, `no-compile` | a write needs the compile gate |

A proved rewrite then passes the compile gate (`--project`; `--platform`, `--rsvars`, `--build-timeout`, `--no-backup`):
baseline build (`dirty-baseline`), all-or-nothing write, after build, rollback (`compile-error`, exit 1). `--library-db`
names the platform library; the manifest's is the default. The LSP rename and `lint --fix` naming fixes still use the
unproved edit set: the editor reviews a WorkspaceEdit, and `lint --fix` has its own refusals.
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
