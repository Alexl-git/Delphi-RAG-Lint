# Copy Selected Diagnostics

Copies just the Diagnostics rows you selected in the Structure form to the
clipboard -- one finding, or several. Reach for it when you want to paste one
or two findings (into a chat, an issue, a review) rather than the whole list.

## Reaching it in the IDE

This is a RIGHT-CLICK action, not a main-menu item. Menu path: "Structure
form (right-click a tree node)".

1. Open the Structure form (drag-lint > Show Structure).
2. Click a Diagnostics row; Ctrl+click or Shift+click to add more rows.
3. Right-click inside the selection and choose "Copy", or press Ctrl+C.

A right-click on a row that is already selected keeps the whole selection.
With only the "Diagnostics (N)" root selected, "Copy" copies every finding,
exactly like [Copy All Diagnostics](Copy-All-Diagnostics).

## What lands on the clipboard

One line per selected finding, in panel order (by line, then column), with
no file header:

```
[W] (10:5) Unit 'Winapi.ShellAPI' is listed in the uses clause but ...  [unused-unit-in-uses]
```

## Running it from the CLI

There is no CLI equivalent of a selection; `drag-lint lint <path>` prints
every finding of a file (see [Copy All Diagnostics](Copy-All-Diagnostics)).

## What it needs

Nothing beyond the findings already shown in the panel.