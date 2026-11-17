---
id: v151-typ-rules
title: Typing and ownership lint rules (casts, Self as interface, destructors)
summary: "Five rules: unrelated class casts, Self as interface during construction, nil-unsafe destructors, Free without nil, unclear field ownership"
product: DL
group: linting
order: 30059
since: 1.51.0-alpha
status: shipped
updated: 1.51.1-alpha
---

# Typing and ownership lint rules (casts, Self as interface, destructors)

Five rules: unrelated class casts, Self as interface during construction, nil-unsafe destructors, Free without nil, unclear field ownership.

Read this to see what each typing and ownership rule reports, which ship ON, what keeps them silent and which carry a risky autofix.

## How to run it

```text
drag-lint lint-all [--profile <name>] [--target-compiler <ver|auto>] [--db <file.sqlite>] [--project <.dproj>] [--build-config <name>] [--rule <id>[,<id>...]] [--disable id,...] [--output <report.txt>] [--json] [--labels] [--quiet] [--lint-third-party] [--no-preprocess] [--shared-db <db> ...] [--library-db none]
```

Full flag list: [lint-all in the CLI reference](../cli.md#lint-all).

```text
drag-lint lint <path> [--profile <name>] [--target-compiler <ver|auto>] [--rule <id>|help] [--disable id1,id2] [--rules-dir <dir>] [--json] [--labels] [--no-preprocess] [--library-db <lib.sqlite>] [--build-config <name>]
```

Full flag list: [lint in the CLI reference](../cli.md#lint).

## Where to click

No IDE surface: this feature runs from the CLI (see How to run it).

## Details

Five rules about class casts, interface reference counting during construction and who frees a field.
They read one unit's parse tree; `unrelated-class-cast` and `self-as-interface-in-constructor` also use
the project and library index when one is given (`--db`), so they can follow a class tree that leaves the
unit. Run them with `drag-lint lint <file> [--db <project.sqlite>]` or
`drag-lint lint-all --db <project.sqlite> --rule <id>`. A rule that ships OFF is switched on with
`--rule <id>` or `"enabled"` in the config.

| Rule | Default | Severity | Reports |
|---|---|---|---|
| `unrelated-class-cast` | ON | warning | A hard cast `T(x)` where the static class of `x` and `T` are on different branches of the class tree, so the object is read with a foreign layout |
| `self-as-interface-in-constructor` | ON | warning | `Self` handed out as an interface while reference counting can still free the half-built object |
| `destructor-not-nil-safe` | ON | warning | The destructor dereferences a field that a constructor creates only after a call that can raise, or only on some paths |
| `field-free-without-nil` | ON | warning | `FField.Free` outside the destructor, with a path to the end of the method that leaves the dangling reference in the field |
| `field-ownership-unclear` | OFF | hint | A field the constructor creates and no method of the class frees, but that the class hands out -- whether it still owns the object is unclear |

### unrelated-class-cast

`TButton(Obj)` checks nothing at run time. When the static type of `Obj` is a class that neither descends
from `TButton` nor is an ancestor of it (an `TEdit`, say), every member access reads memory laid out for a
different class.

Fires only when both types are known to be classes and both class trees are known completely: from the
unit's own declarations, or from the index (`type_ancestors`, and `ref_types` for the operand's type).
Stays silent for: `TObject` operands, interfaces, pointers, records and numbers, an upcast or a downcast
(the `unsafe-typecast-without-is` rule covers unchecked downcasts), an operand whose type is unknown, and
the accessor-class idiom -- `THack = class(TControl)` with no fields and no virtual methods has the same
layout as the class it is cast from. Fix: `(Obj as TButton)` checks the type, or correct the variable's type.

### self-as-interface-in-constructor

Two cases, both of which free the object before construction ends:

1. A class that counts its own references (its `_Release` frees the object, no class in the chain
   overrides `NewInstance`, the chain is declared in the unit) passes `Self` as an interface in a
   constructor or in `AfterConstruction`: the count goes from 0 to 1 and back to 0.
2. A `TInterfacedObject` descendant passes `Self` as an interface in `AfterConstruction` after
   `inherited`: `TInterfacedObject.AfterConstruction` has already dropped the protective count that
   `NewInstance` set. In the constructor itself that count protects the object, so the rule is silent there.

"Passing as an interface" is `Self as IX`, `IX(Self)`, an assignment of `Self` to an interface variable or
field, or `Self` as an argument where every known declaration of the callee takes an interface at that
position. Fix for case 2: move the statement before `inherited`.

### destructor-not-nil-safe

When a constructor raises, Delphi calls the destructor at once on the half-built object. A field created
after a call that can raise -- or only inside an `if` / loop / `except` -- may still be nil there, and
`FLines.Clear` in the destructor then raises an access violation that hides the original exception.

Counted as raising: any call except `inherited`, `Assigned`, `Supports` and similar RTL routines, type
casts, and the creation of RTL classes that raise only `EOutOfMemory` (`TStringList`, `TList<T>`,
`TObjectList<T>`, `TDictionary<K,V>`, `TMemoryStream` ...). Nil-safe in the destructor: `Free`,
`FreeAndNil`, `DisposeOf`, and accesses under `if Assigned(F)` / `F <> nil` (also `Assigned(F) and F.X`
and an earlier `if F = nil then Exit`). Private methods called only from the destructor are checked too.
Interface fields are never reported.

Autofix (risky, opt-in with `--fix-rule destructor-not-nil-safe`): puts `if Assigned(F) then` in front of a
one-line statement. A correct run behaves as before; in the failing case the statement is skipped instead
of raising. Declined inside an unbraced `then` / `else` / `do` branch.

### field-free-without-nil

`FCache.Free` in a method that is not the destructor leaves a dangling reference in the field; a later
access or a second `Free` hits freed memory. Silent when every path from the `Free` to the end of the
method sets the field again: an assignment, `FreeAndNil`, or a call of a method of the class that assigns
the field. An `Exit` or `raise` before that is a path that does not.

Exempt: destructors, `BeforeDestruction`, methods whose name ends in `Destroy` (`FormDestroy`), tear-down
methods (`[TearDown]`, `[TearDownFixture]`), close handlers that set `Action := caFree`, and methods
called only from these.

Autofix (risky, opt-in with `--fix-rule field-free-without-nil`): `F.Free;` becomes `FreeAndNil(F);` and
`System.SysUtils` is added to the implementation uses when missing. The same object is freed; only a later
read of the field can see the difference (nil instead of a dangling reference).

### field-ownership-unclear (OFF)

A companion of `field-created-not-freed`: that rule stays silent when a created field is handed on,
because the receiver may own it now. This hint reports exactly those fields when the class never frees
them and hands them out: returned (`Result := F`, `Exit(F)`), stored in another object (`X.Y := F`), or
passed to an `Add...`, `Insert...`, `Register...`, `Attach...`, `Push...`, `Enqueue...` or `Append...`
call. Silent when the receiver is an owning container field of the class (`TObjectList`, `TObjectStack`,
`TObjectQueue`, `TComponentList`, `TObjectDictionary` not created with `False`), for components created
with an owner, and for interface and dynamic-array fields. It ships OFF because the answer is a decision
for the developer, not a defect; there is no autofix.

---

[All features](../index.md) | [CLI reference](../cli.md) | [IDE menus](../ide.md)
