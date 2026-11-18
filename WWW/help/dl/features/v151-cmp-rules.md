---
id: v151-cmp-rules
title: Component-authoring lint rules
summary: "Lint rules for component and IDE-expert code: FreeNotification, property defaults, palette bitmaps, repainting setters, DPI, OTA notifiers"
product: DL
group: linting
order: 30048
since: 1.51.0-alpha
status: shipped
updated: 1.51.1-alpha
---

# Component-authoring lint rules

Lint rules for component and IDE-expert code: FreeNotification, property defaults, palette bitmaps, repainting setters, DPI, OTA notifiers.

Read this to see what each component-authoring rule reports, which ship ON or OFF, and how the index helps them decide whether a type is a component or a control.

## How to run it

```text
drag-lint lint <path> [--profile <name>] [--target-compiler <ver|auto>] [--rule <id>|help] [--disable id1,id2] [--rules-dir <dir>] [--json] [--labels] [--no-preprocess] [--library-db <lib.sqlite>] [--build-config <name>] [--no-budget]
```

Example:

```text
drag-lint lint <unit.pas> --rule component-missing-free-notification
```

Full flag list: [lint in the CLI reference](../cli.md#lint).

```text
drag-lint lint-all [--profile <name>] [--target-compiler <ver|auto>] [--db <file.sqlite>] [--project <.dproj>] [--build-config <name>] [--rule <id>[,<id>...]] [--disable id,...] [--output|--report <report.txt>] [--json] [--labels] [--quiet] [--lint-third-party] [--no-preprocess] [--shared-db <db> ...] [--library-db none] [--no-budget]
```

Example:

```text
drag-lint lint-all --db <project.sqlite> --rule ota-notifier-not-removed
```

Full flag list: [lint-all in the CLI reference](../cli.md#lint-all).

## Where to click

No IDE surface: this feature runs from the CLI (see How to run it).

## Details

Rules for code that WRITES components and IDE experts: custom controls, their
published properties, palette registration and Open Tools API notifiers. All of
them run per unit in `lint` and `lint-all`; the index is used only to answer
"does this type descend from TComponent / TControl" and "what is the static type
of this expression", so a unit outside any index still gets the checks that its
own declarations and the well-known VCL class names can decide.

| Rule | Default | Severity | Fires on |
|---|---|---|---|
| `component-missing-free-notification` | ON | warning | a component-typed property setter that stores the linked component without `FreeNotification`, or a published component-typed property written straight to its field |
| `component-default-mismatch` | ON | warning | a property `default` that differs from the literal the constructor sets, or a non-zero / True default on a field nothing ever sets |
| `component-palette-icon` | ON | hint | a class passed to `RegisterComponents` with no bitmap of its name in the .dcr / .res the unit (or its package) includes |
| `component-setter-without-invalidate` | ON | hint | a setter that changes a field `Paint` reads and repaints by no route |
| `ota-notifier-not-removed` | ON | warning | an Open Tools API registration (`AddNotifier`, `AddWizard`, `AddKeyboardBinding`, `AddPluginInfo`, `RegisterAddInOptions`, ...) whose index is thrown away or never reaches the matching remove call |
| `component-fixed-pixels` | OFF | hint | a drawing call in a Paint / Draw / Resize routine with a fixed pixel literal (2 or more) |
| `component-hardcoded-color` | OFF | hint | `RGB(..)`, `TColor(<number>)` or a numeric colour in a Paint / Draw routine |
| `control-fixed-bounds` | OFF | hint | `Width` / `Height` / `Left` / `Top` / `SetBounds` of a control set to a fixed non-zero pixel value in a VCL unit |
| `write-only-property` | OFF | hint | a typed property with `write` and no `read` |

The OFF rules are style: opt in with `--rule <id>` or `"enabled"` in the config.
Defaults were set from a false-positive sample on four real project indexes; the
counts are in the v151 lane CMP report.

### Widened: interface-holder-of-non-refcounted

The existing rule now also sees two more shapes:

* `Supports(X, IFoo, Intf)` where the static type of `X` descends from TComponent
  (needs the index): `Intf` keeps nothing alive, exactly as `Intf := X as IFoo`.
* a component freed (`Free`, `DisposeOf`, `FreeAndNil`) while a LOCAL interface
  variable still holds it: the variable is released at the end of the routine and
  touches the freed object. Clear the variable (`Intf := nil`) before the free.

### hides-ancestor-virtual and the component constructor

`constructor Create(AOwner: TComponent);` without `override` in a component
descendant is reported by `hides-ancestor-virtual` (and by the compiler as W1010);
no separate rule is needed. The fixtures `tests\lint\hides-ancestor-virtual-component-ctor.pas`
and `tests\autotest\run_v151_CMP_store_rules.ps1` (ancestor in another unit) pin it.

### Examples

```pascal
procedure TLinker.SetLink(const Value: TControl);
begin
  FLink := Value;            // component-missing-free-notification
end;

property Size: Integer read FSize write FSize default 5;   // constructor sets FSize := 10
                                                            // -> component-default-mismatch

GIdx := (BorlandIDEServices as IOTAServices).AddNotifier(TMyNotifier.Create);
// no RemoveNotifier(GIdx) anywhere in the unit -> ota-notifier-not-removed
```

No autofix: each repair changes behaviour in the defect case (which values a form
stores, when a control repaints, what the IDE calls), so the message carries the
suggestion instead.

---

[All features](../index.md) | [CLI reference](../cli.md) | [IDE menus](../ide.md)
