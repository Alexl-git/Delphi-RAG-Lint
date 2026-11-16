# References the index keeps for declaration positions

A rename, `usages` and the unused rules can only see a name where the index holds a reference for it. Most names sit in routine bodies; this page lists the declaration positions that hold one too, and the kind each gets.

## Looking at them from the CLI
```
drag-lint index --project <file.dproj> --db <file.sqlite>
drag-lint usages --name <QualifiedName> --db <file.sqlite>
drag-lint rename --plan --kind symbol --name <QualifiedName> --to <NewName> --db <file.sqlite>
```
`rename --plan` names a token it finds without a reference as `no-ref-occurrence`.

## What holds a reference

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

## Limits

* The parameters of an anonymous method are not symbols yet, so `O.Field` inside `function(const O: TRec): Integer begin ... end` has an untyped receiver and a rename of `Field` refuses there (`receiver-untyped`).
* `TOuter.TInner.Run` in the implementation holds a reference for `TOuter` only.
* `Unit.TFoo` holds a reference for `TFoo` only: the tree cannot tell a unit name from an outer class.

These references are written by the extractor: a project picks them up on its next re-parse (the extractor version of 1.51.1).
