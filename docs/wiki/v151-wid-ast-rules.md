# Wider built-in rules (1.51)

Six built-in rules read more of the source in 1.51. Defaults are unchanged: a rule that was ON stays ON, an OFF rule stays OFF.

## What changed
* `magic-literal` no longer fires on a string code page (`AnsiString(1252)`), a label declaration, a numeric label or a `goto` target.
* `division-by-zero-literal` also reports `X / Z` where `Z` is a constant of the same file declared as 0. `div` and `mod` by a zero constant are left to the compiler (E2098).
* `repeated-else-if-condition` also reports a branch whose condition is already implied by an earlier one: `if A or B ... else if A`, and `if A ... else if A and B`.
* `ui-access-in-thread` also reports `ShowMessage`, `ShowMessageFmt`, `MessageDlg`, `MessageDlgPos`, `.ShowModal` and `.Invalidate` inside a `TThread.Execute`.
* `missing-inherited-ctor` / `missing-inherited-dtor` also check `AfterConstruction` and `BeforeDestruction` overrides. A body that touches `RefCount` (the `TInterfacedObject` idiom) is skipped.
* `interface-object-mixing` (OFF by default) also follows the variable that `Supports(X, IFoo, V)` assigns, and reports `DisposeOf` on an interface-held object.

## Try it
```
drag-lint lint <file.pas> --rule division-by-zero-literal
drag-lint lint <file.pas> --rule repeated-else-if-condition
drag-lint lint <file.pas> --enable interface-object-mixing
```
