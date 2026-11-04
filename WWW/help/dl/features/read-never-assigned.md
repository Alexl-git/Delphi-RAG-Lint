---
id: read-never-assigned
title: Read but never assigned (lint rule)
summary: "Project-wide lint rule: a field or global that is read but that nothing in the project assigns or creates"
product: DL
group: linting
order: 30026
since: 1.40.0-alpha
status: shipped
updated: 1.42.0-alpha
---

# Read but never assigned (lint rule)

Project-wide lint rule: a field or global that is read but that nothing in the project assigns or creates.

Read this to see what read-never-assigned reports and what it treats as an assignment. It runs in lint-all and lint-project over a project index; hard-cast writes, var / out arguments, property write accessors, DFM-streamed fields, absolute, initialisers and initialization sections all count.

## How to run it

Full flag list: [lint-all in the CLI reference](../cli.md#lint-all).

## Where to click

No IDE surface: this feature runs from the CLI (see How to run it).

## Details

A project-wide lint rule: a field or a global variable that something READS but that nothing anywhere in the project ever assigns or creates. Every read sees the default value (0, nil, an empty string), so the read is either dead or a missing assignment -- typically an object field that is used (`FList.Add(..)`) but never constructed.

The per-file `referenced-never-set` checks private fields inside one unit; this rule checks every class field and every global, across the whole project, so it runs only where the whole index is in scope.

### Running it from the CLI
```text
drag-lint lint-all --db <project.sqlite>                              (ON by default)
drag-lint lint-all --db <project.sqlite> --rule read-never-assigned   (only this rule)
drag-lint lint-project --db <project.sqlite> --rule read-never-assigned
drag-lint lint-all --db <project.sqlite> --disable read-never-assigned
```
`lint <file>` does not run it by default: one unit cannot prove "never".

### What counts as an assignment
Any one of these silences the symbol:
- `X := v`, `Self.X := v`, `O.X := v`, `with O do X := v`, a write in an `initialization` section;
- a hard cast `TFoo(P).X := v` (ref-gap G5);
- passing it where the callee takes it by `var` / `out` -- a project routine, a platform-library routine, an RTL intrinsic (`SetLength`, `Inc`, `Val`, `Read`, ...), or a callee neither index knows;
  when the resolver bound the call (`Show(X)`, `Obj.Show(X)`), only THAT routine's own declaration (its overload set) decides; a same-named routine elsewhere -- e.g. ShlObj's `IFileViewer.Show(var ...)` -- no longer silences it. Only an unbound call (a late-bound `Variant`, an unknown receiver type) falls back to every project and library routine of that bare name, and then any `var` / `out` among them counts (silence, never a false finding);
- taking its address (`@X`);
- a property naming it as its `write` accessor;
- a global declared with an initialiser (`G: Integer = 7`), declared `absolute`, or the target of an `absolute` alias;
- an unbound ref of the same name that writes by any of the shapes above.

### Never reported
Typed constants, record fields (a record is filled whole), published fields and the fields of a class's default-visibility section (the form loader streams them from the DFM).

### Reviewing a finding
`// dl:ok read-never-assigned -- <reason>` on the declaration line.

### What it needs
A project index (`index --project`); the platform library index sharpens the var / out answer for library callees.

---

[All features](../index.md) | [CLI reference](../cli.md) | [IDE menus](../ide.md)
