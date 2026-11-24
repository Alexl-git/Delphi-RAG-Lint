# Form file rules: tab order, accelerators, shortcuts, actions, hints (lane DFM, 1.54)

Seven checks over the text form file (.dfm) of a unit, and a shipped default for `disallowed-dfm-property`. They run in `lint`
(on the unit, with its sibling .dfm) and in `lint-all`, in the IDE and in VS Code. A binary form file keeps every check silent.

```
drag-lint lint <unit.pas> --rule dfm-duplicate-tab-order
drag-lint lint-all --db <project.sqlite> --rule dfm-conflicting-shortcut
```

Turn one off with `"disabled": ["dfm-hint-inactive"]` in the lint config, turn an OFF one on with `"enabled": ["db-component-on-form"]`.
A finding is placed on the line of the property or object in the .dfm.

| Rule | Default | Severity | What it says |
|---|---|---|---|
| `dfm-duplicate-tab-order` | ON | info | Two siblings store the same `TabOrder`. |
| `dfm-conflicting-accelerator` | ON | info | Two siblings (or two items of one menu level) use the same Alt letter. |
| `dfm-conflicting-shortcut` | ON | warning | Two actions of one list, two items of one menu or two bar buttons of one manager share a `ShortCut`. |
| `dfm-action-and-onclick` | ON | warning | A control has `Action` and its own `OnClick` that does not call the action. |
| `db-component-on-form` | OFF | hint | A connection, query, table or stored procedure sits on a form instead of a data module. |
| `dfm-default-component-name` | OFF | hint | A component still named `Button1` / `Label7` that the unit refers to. |
| `dfm-hint-inactive` | OFF | hint | A control stores a `Hint` that can never show. |
| `disallowed-dfm-property` | ON (existing) | warning | New shipped default: `Connected = True` on a connection, `Active = True` on a query or table. |

## Where each one stays silent

* **dfm-duplicate-tab-order**: scope is one parent. Hidden (`Visible = False`) and `TabStop = False` controls are skipped. The
  children of a splitter (`TRzSplitter` and any class with `Splitter` in its name) and of a layout container (`Layout` in the
  class name) are skipped: their panes number their own children, so every second pane repeats `TabOrder = 0`.
* **dfm-conflicting-accelerator**: scope is one parent (a tab sheet, a panel, a menu level), so the same letter on two tab sheets
  is fine. `&&` is a literal ampersand. Hidden controls and `ShowAccelChar = False` are skipped. Captions set in code are not seen.
  Classes: buttons, check boxes, radio buttons, labels, group boxes, tab sheets, menu items.
* **dfm-conflicting-shortcut**: scope is one action list, one menu (all levels of a main or popup menu) or one bar manager. An item
  with an `Action` (its shortcut comes from the action), a disabled or hidden one (`Enabled = False`, `Visible = False`,
  `Visible = ivNever`) and `ShortCut = 0` are skipped.
* **dfm-action-and-onclick**: silent when `OnClick` is the action's own `OnExecute` handler, when the handler's body (in the unit)
  calls `Execute`, mentions the action or calls the action's handler, and when the handler is not in the unit.
* **db-component-on-form**: silent on a data module (a root class named `*DataModule*`, `TDM*`, or declared `class(TDataModule)` /
  `class(T...DM)` in the unit). Data sources, in-memory tables and client datasets are not reported. One finding per component, each
  saying how many database components the form has.
* **dfm-default-component-name**: the name is the class name without its `T` plus a number (`cxButton1` of `TcxButton`), and the
  unit must use it in code (a whole word outside its field declaration and `//` lines). The form's own `Form1` is never reported.
* **dfm-hint-inactive**: a `Hint` that is not empty, on a control whose own or an ancestor's `ParentShowHint = False` has no
  `ShowHint = True`. Silent when the unit writes `ShowHint :=` or installs `OnHint` / `OnShowHint`, and for menu items, actions and fields.
* **disallowed-dfm-property default**: in-memory tables, client datasets and grid views are skipped. When the project's own
  `dfm:` table already names the property (`Connected` or `Active`), the project entry decides and the default adds nothing.

## Measured

Corpora (copies of the project indexes, 2026-11-24): M2022 (Micronite), TableTools, YADF; one rule at a time with `lint-all --rule`.

| Rule | M2022 | TableTools | YADF | Verdict |
|---|---|---|---|---|
| dfm-duplicate-tab-order | 61 first run, all 61 false (children of `TRzSplitter`); 0 after the splitter exemption | 0 | 0 | ON, not measured in the field after the fix; the splitter shape is a negative fixture |
| dfm-conflicting-accelerator | 0 | 0 | 0 | ON, not measured in the field |
| dfm-conflicting-shortcut | 5 findings, 5 true (F10 on two bar buttons, Ctrl+A on two actions, F9, F6) | 0 | 0 | ON |
| dfm-action-and-onclick | 0 | 0 | 0 | ON, not measured in the field |
| db-component-on-form | 593 in 106 forms (true: legacy BDE forms) | 0 | 0 | OFF: a work list, over 200 on one corpus |
| dfm-default-component-name | 568 in 101 forms | 4 | 0 | OFF: over 200 on one corpus |
| dfm-hint-inactive | 0 | 0 | 0 | OFF (plan default), not measured in the field |
| disallowed-dfm-property default | 0 | 2, both true (`Connected = True`) | 0 | ON |

Tests: `tests\autotest\run_v154_DFM.ps1` on `tests\fixtures\v154\DFM`: each rule is compared as an exact set of
`form:line`, firing controls and silent neighbours in the same file; also the defaults and the project policy taking over a default.
