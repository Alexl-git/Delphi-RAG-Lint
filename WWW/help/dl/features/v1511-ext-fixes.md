---
id: v1511-ext-fixes
title: References for declaration positions
summary: The index keeps a reference for pointer base types, generic constraints, generic method headers, dotted property specifiers and message constants
product: DL
group: indexing
order: 10012
since: 1.51.1-alpha
status: shipped
updated: 1.51.1-alpha
---

# References for declaration positions

The index keeps a reference for pointer base types, generic constraints, generic method headers, dotted property specifiers and message constants.

Read this to see which declaration positions hold a reference a rename or usages can find, the kind each gets, and the positions that still hold none.

## How to run it

```text
drag-lint index <path> [--db <file.sqlite>] [--watch [--interval N]] [--library-db <lib.sqlite> ...] [--wait-library <min>] [--require-library] [--stall-exit-min <min>] [--target-compiler <ver|auto>]
```

Example:

```text
drag-lint index --project <file.dproj> --db <file.sqlite>
```

Full flag list: [index in the CLI reference](../cli.md#index).

```text
drag-lint usages --name <X> [--width narrow|wide|very-wide] [--db <path>] [--depth N] [--format json|--json] [--limit N] [--rw] [--in <file> [--no-create]] [--library-db <lib.sqlite>]
```

Example:

```text
drag-lint usages --name <QualifiedName> --db <file.sqlite>
```

Full flag list: [usages in the CLI reference](../cli.md#usages).

## Where to click

No IDE surface: this feature runs from the CLI (see How to run it).

## Details

A rename, `usages` and the unused rules can only see a name where the index holds a reference for it. Most names sit in routine bodies; this page lists the declaration positions that hold one too, and the kind each gets.

### Looking at them from the CLI
```text
drag-lint index --project <file.dproj> --db <file.sqlite>
drag-lint usages --name <QualifiedName> --db <file.sqlite>
drag-lint rename --plan --kind symbol --name <QualifiedName> --to <NewName> --db <file.sqlite>
```
`rename --plan` names a token it finds without a reference as `no-ref-occurrence`.

### What holds a reference

| Source | Reference | Since |
|---|---|---|
| `PFoo = ^TFoo;`, `Next: ^TNode` | `type_use` of the base type | 1.51.1 |
| `TBox<T: TBase> = class` | `type_use` of each constraint type; `T` itself declares and has none | 1.51.1 |
| `function TBox<T>.GetAt(...)` in the implementation | `type_use` of the class, as for `procedure TFoo.Run` | 1.51.1 |
| `V: TBox<TItem>.TInner` | `type_use` of `TBox` and `TItem` as well as `TInner` | 1.51.1 |
| `property X: T read FRec.Field write FRec.Field` | `FRec` is a `property-spec` reference bound to the field; `Field` is a `record-field` reference bound through the field's type | 1.51.1 |
| `property X: T read FArr[0].Field` | `FArr` is a `property-spec` reference bound to the field | 1.51.1 |
| `procedure WMSize(var M: TMessage); message WM_SIZE;` | `read` of the constant | 1.51.1 |
| `property X: T read FCount write SetCount stored IsStored` | `property-spec` references | 1.44 |
| `const C: TRec = (Alpha: 1; Beta: 2)` | `record-field` references | 1.44 |
| `inherited Run`, `inherited Count := 1` | `call` / `member-access` with receiver `inherited` | 1.44 |

### Limits

* The parameters of an anonymous method are not symbols yet, so `O.Field` inside `function(const O: TRec): Integer begin ... end` has an untyped receiver and a rename of `Field` refuses there (`receiver-untyped`).
* `TOuter.TInner.Run` in the implementation holds a reference for `TOuter` only.
* `Unit.TFoo` holds a reference for `TFoo` only: the tree cannot tell a unit name from an outer class.

These references are written by the extractor: a project picks them up on its next re-parse (the extractor version of 1.51.1).

---

[All features](../index.md) | [CLI reference](../cli.md) | [IDE menus](../ide.md)
