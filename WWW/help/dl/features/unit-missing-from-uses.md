---
id: unit-missing-from-uses
title: Missing unit in uses (unit-missing-from-uses)
summary: "Lint rule: names the unit that declares an undeclared identifier and adds it to the interface or implementation uses clause, cycle-checked"
product: DL
group: uses-dependencies
order: 130002
since: 1.38.0-alpha
status: shipped
updated: 1.38.0-alpha
---

# Missing unit in uses (unit-missing-from-uses)

Lint rule: names the unit that declares an undeclared identifier and adds it to the interface or implementation uses clause, cycle-checked.

Read this when the IDE says Undeclared identifier for a name another unit declares (CodeSite without CodeSiteLogging in uses). The rule names the unit and the clause -- interface when the name is used there, else implementation -- checks the new uses edge for a circular unit reference first, and fixes it from Ctrl+Alt+U, the LSP light bulb or lint --fix --apply.

## How to run it

```text
drag-lint lint <path> [--profile <name>] [--target-compiler <ver|auto>] [--rule <id>] [--disable id1,id2] [--rules-dir <dir>] [--json] [--labels] [--no-preprocess] [--library-db <lib.sqlite>] [--build-config <name>]
```

Example:

```text
drag-lint lint uMain.pas --db <db> --rule unit-missing-from-uses --fix --apply
```

Full flag list: [lint in the CLI reference](../cli.md#lint).

## Where to click

No IDE surface: this feature runs from the CLI (see How to run it).

## Details

You typed `CodeSite.Send('Loaded');` but `CodeSiteLogging` is not in the unit's
`uses` clause yet. The IDE only says *Undeclared identifier: 'CodeSite'*.
drag-lint says which unit declares it and where to add it:

```text
uMain.pas:120:3  [warning] unit-missing-from-uses: 'CodeSite' is declared in unit CodeSiteLogging -- add it to the implementation uses clause
```

### Where the unit goes

* **interface** uses clause -- when the name is used anywhere in the interface
  section (a field type, a parameter type, a constant of the class...);
* **implementation** uses clause -- otherwise.

The clause is created when the section has none, and an existing clause keeps
its own layout (one-line, one unit per line, or comma-first).

### Cycle check before the edit

Before offering the edit, drag-lint walks the project's uses graph for the new
edge:

* If adding the unit to the **interface** would close a circular unit
  reference (the compiler's E2047), the message recommends the
  **implementation** clause instead and names the cycle:
  `... -- add it to the implementation uses clause and move its interface use there (the interface uses clause would create a circular unit reference: uA -> uB -> uA)`.
  The interface edit is still offered as a second quick-fix, marked with the warning.
* If the recommended edit would still close a uses cycle (the kind
  `circular-uses` reports), the message ends with
  `(warning: this creates a uses cycle: ...)`.

### Fixing it

| Where | How |
|---|---|
| IDE | Put the caret on the flagged line and press **Ctrl+Alt+U**, or choose drag-lint > Uses & Dependencies > Quick-Fix: Add Unit for Undeclared at Cursor (Ctrl+Alt+U). The unit goes to the clause the message names; one undo reverts it. |
| VS Code / any LSP client | The light bulb on the diagnostic: *Add CodeSiteLogging to the implementation uses clause*. |
| Command line | `drag-lint lint <file> --db <db> --rule unit-missing-from-uses --fix` previews; add `--apply` to write. Every missing unit of the file is added in one edit per clause. |

### When it says nothing (on purpose)

The rule is built to be quiet rather than wrong. It reports nothing when:

* the unit is already in either uses clause (also as `SysUtils` for `System.SysUtils`);
* the file declares the name itself (a local, a field, a parameter, a generic
  parameter, an anonymous-method parameter);
* the name follows a dot (`Obj.CodeSite` is a member, not a unit-level name);
* inside a method, the name is also a member of some class (it may be
  inherited); inside a routine with `with`, a member of any type;
* the file uses a unit the index does not know, or no platform library is
  available -- either could declare the name;
* the code sits in an inactive `{$IFDEF}` branch;
* the index is older than the text at that position (save, let the IDE
  reindex, and it comes back).

When **several** units declare the name, they are listed and no fix is offered:
`'TBitmap' is declared in units Vcl.Graphics, FMX.Graphics -- add one of them to the uses clause`.
A VCL unit filters out FMX candidates and vice versa.

### Needs

A project index that contains the file, and the platform library index (both
resolve automatically from the manifest). Turn the rule off with
`"disabled": ["unit-missing-from-uses"]` in `drag-lint-lint.json`, or review a
single site with `// dl:ok unit-missing-from-uses -- why`.

Related: [find-unit](find-unit.md) (ask for one symbol), Add Missing Units
(whole unit), [circular-uses](circular-uses-report-cycles-fix-plan.md).

In VS Code the single-resolution fix also runs on save: see [Auto uses on save](auto-uses-on-save.md#auto-uses-on-save).

---

[All features](../index.md) | [CLI reference](../cli.md) | [IDE menus](../ide.md)
