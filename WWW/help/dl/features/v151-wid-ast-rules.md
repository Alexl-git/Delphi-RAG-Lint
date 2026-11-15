---
id: v151-wid-ast-rules
title: Wider built-in rules (1.51)
summary: "Six built-in rules read more constructs: code-page and label exemptions, named zero constants, implied else-if, thread dialogs, Supports aliases"
product: DL
group: linting
order: 30060
since: 1.51.0-alpha
status: shipped
updated: 1.51.0-alpha
---

# Wider built-in rules (1.51)

Six built-in rules read more constructs: code-page and label exemptions, named zero constants, implied else-if, thread dialogs, Supports aliases.

Read this when you want to know which constructs six built-in lint rules newly report or exempt in version 1.51.

## How to run it

```text
drag-lint lint <path> [--profile <name>] [--target-compiler <ver|auto>] [--rule <id>|help] [--disable id1,id2] [--rules-dir <dir>] [--json] [--labels] [--no-preprocess] [--library-db <lib.sqlite>] [--build-config <name>]
```

Full flag list: [lint in the CLI reference](../cli.md#lint).

## Where to click

No IDE surface: this feature runs from the CLI (see How to run it).

## Details

Six built-in rules read more of the source in 1.51. Defaults are unchanged: a rule that was ON stays ON, an OFF rule stays OFF.

### What changed
* `magic-literal` no longer fires on a string code page (`AnsiString(1252)`), a label declaration, a numeric label or a `goto` target.
* `division-by-zero-literal` also reports `X / Z` where `Z` is a constant of the same file declared as 0. `div` and `mod` by a zero constant are left to the compiler (E2098).
* `repeated-else-if-condition` also reports a branch whose condition is already implied by an earlier one: `if A or B ... else if A`, and `if A ... else if A and B`.
* `ui-access-in-thread` also reports `ShowMessage`, `ShowMessageFmt`, `MessageDlg`, `MessageDlgPos`, `.ShowModal` and `.Invalidate` inside a `TThread.Execute`.
* `missing-inherited-ctor` / `missing-inherited-dtor` also check `AfterConstruction` and `BeforeDestruction` overrides. A body that touches `RefCount` (the `TInterfacedObject` idiom) is skipped.
* `interface-object-mixing` (OFF by default) also follows the variable that `Supports(X, IFoo, V)` assigns, and reports `DisposeOf` on an interface-held object.

### Try it
```text
drag-lint lint <file.pas> --rule division-by-zero-literal
drag-lint lint <file.pas> --rule repeated-else-if-condition
drag-lint lint <file.pas> --enable interface-object-mixing
```

---

[All features](../index.md) | [CLI reference](../cli.md) | [IDE menus](../ide.md)
