# Single-precision Math calls and form-file smells (lanes G32 and DFM-R, 1.56)

Three rules, all OFF by default: name them with `--rule` or enable them in the lint config.

```
drag-lint lint <unit.pas> --rule math-single-overload
drag-lint lint <form.dfm> --rule dfm-god-handler
drag-lint lint <form.dfm> --rule dfm-control-overlap
```

## math-single-overload (G-32, warning, bug-patterns, OFF)

`Max`, `Min` or `Power` called with Single arguments or float literals (so the Single overload is chosen and the
arithmetic runs in single precision), when the result is assigned to a Double, Extended or Real variable. Reported at the call.

Silent when any argument is a Double or Extended, when the result goes to a Single, when the argument type cannot be
resolved, after an explicit `Double(...)` cast, for an integer literal and for a user routine of the same name.

## dfm-god-handler (G-35, hint, structure, OFF)

One event handler wired to `threshold` or more events (default 5) of at least two different event kinds in one form file.
Reported once, at its first binding. One `OnClick` shared by a row of buttons is a single kind and is NOT reported.
Set the limit in the lint config: `thresholds."dfm-god-handler"`.

## dfm-control-overlap (G-36, info, bug-patterns, OFF)

A visible control with stored Left, Top, Width and Height that covers an earlier sibling by more than 1 px in both
directions.

Silent for `Align` other than `alNone`, Anchors with `akRight` or `akBottom`, `Visible = False`, splitters, stacking
parents (page control, notebook, card, grid, flow and stack panel, layout controls, tool bar), and when a backdrop class
(bevel, shape, group box, panel, image, box) contains the other control.