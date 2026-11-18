---
id: v152-unconn-rules
title: Lint rules unconnected-control and hanging-handler
summary: Warns on a form control that nothing wires and on an event-handler-shaped method that no form binds and no code assigns or calls
product: DL
group: linting
order: 30075
since: 1.52.0-alpha
status: shipped
updated: 1.52.0-alpha
---

# Lint rules unconnected-control and hanging-handler

Warns on a form control that nothing wires and on an event-handler-shaped method that no form binds and no code assigns or calls.

Read this to see which controls and handlers the two form rules report, what counts as a connection, and how the index widens the evidence beyond the unit.

## How to run it

```text
drag-lint lint <path> [--profile <name>] [--target-compiler <ver|auto>] [--rule <id>|help] [--disable id1,id2] [--rules-dir <dir>] [--json] [--labels] [--no-preprocess] [--library-db <lib.sqlite>] [--build-config <name>] [--no-budget]
```

Example:

```text
drag-lint lint <file.pas> --rule unconnected-control,hanging-handler --db <index.sqlite>
```

Full flag list: [lint in the CLI reference](../cli.md#lint).

## Where to click

No IDE surface: this feature runs from the CLI (see How to run it).

## Details

Two halves of the same mistake in a form: a control that was dropped on the form and never
wired, and a handler that was written and never bound (or lost its binding when a control was
deleted or renamed). Neither breaks the build; both mislead the next reader, and a button that
does nothing reaches the user.

Both rules are default **ON**, category `dead-code`, severity `warning`. They run on every
`.pas` that has a sibling `.dfm` (`lint`, `lint-all`, the IDE and VS Code). Run only them with
`drag-lint lint <file> --rule unconnected-control,hanging-handler --db <index>`; turn one off
with `"disabled": ["unconnected-control"]` in the lint config, or approve one line with a
`dl:ok` marker.

### unconnected-control

Reports a control of a class with a default event -- buttons (TButton, TBitBtn, TSpeedButton,
TToolButton, TcxButton), menu and bar items (TMenuItem, TdxBarButton, TdxBarLargeButton,
TdxBarCombo, TdxBarEdit), check and radio boxes and groups, edits, memos, combos, list boxes,
spin edits, track bars, date pickers and their DevExpress `Tcx*` counterparts -- that has

* no event bound in the form file (no `On... = Handler` line on the control),
* no `Action`, no `DataSource` / `DataField` / `DataBinding.*`, no `DropdownMenu` / `MenuItem`,
* no `ModalResult` (other than `mrNone`) and, for a TBitBtn, no `Kind`,
* no LiveBindings link naming it (`Control =`, `Component =`, `SourceComponent =`,
  `ControlComponent =` on another component),
* and no reference in code: its name occurs nowhere in the unit beyond the field declaration
  (strings count, so `FindComponent('btnOk')` is a use) and, with an index, no reference of that
  name exists in any indexed file. Reading a control's state (`chkAll.Checked`, `btnBold.Down`)
  is a reference, so such a control is connected.

The finding sits on the control's field declaration in the `.pas` (on the `.dfm` object line
when the form class has no field for it). Never reported: labels, panels, bevels, layout items
and every other passive class; a menu item with sub-items; a separator (`Caption = '-'`, tool
button `Style = tbsSeparator / tbsDivider`); an `inherited` control in a descendant form (the
ancestor owns it); controls inside an embedded frame instance.

### hanging-handler

Reports a method of the form's class that is shaped like an event handler -- it has a
`Sender: TObject` parameter, which every VCL notify, key, mouse and close event has -- when

* no `On... = <Method>` line of the unit's own form file binds it,
* its name occurs nowhere in the unit beyond its declaration and implementation header
  (a call, an assignment `X.OnClick := Method`, passing it as an argument all count),
* and, with an index, no reference of that name exists in any indexed file -- including the
  `event-binding` rows the indexer writes for every `On... =` line of every form file, so a
  handler of a base form bound only in a descendant's `.dfm` is connected.

The finding sits on the method's implementation header. A method called directly is NOT
reported: it is live code, even when its name suggests an event.

### Evidence and its limits

The index lookup is by NAME across the whole project (one indexed query per form), not by
resolved symbol: a homonym anywhere counts as a use. This errs toward silence -- a dead
`Button1` in one form is hidden when another form uses its own `Button1`. Without an index (a
file outside every index, the fixture runs) only the unit's own text and form file are
evidence, and a control used only from another unit is reported; pass `--db` for parity with
`lint-all`.

### Fixing

No autofix: whether a dead control should be wired or deleted is a design decision. Delete the
control and its field, bind an event or an Action, or approve the line with a `dl:ok` marker
naming why (for example, a control the code finds by RTTI).

### Tests

* `tests\lint\unconnected-control.*`, `tests\lint\hanging-handler.*` (run_lint_tests): every hit
  has a silent twin.
* `tests\autotest\run_v152_UNCONN.ps1`: the catalog rows, both fixtures, and a cross-unit
  fixture (`tests\lint\unconnected-control.xunit`) indexed into a scratch DB -- a control used
  only from another unit, a handler bound only in a descendant form file and a handler assigned
  only in another unit are silent with the index and reported without it (positive control).

---

[All features](../index.md) | [CLI reference](../cli.md) | [IDE menus](../ide.md)
