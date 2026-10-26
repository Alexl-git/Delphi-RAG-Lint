---
id: convrules-qualify-fix
title: "Qualify #convert quick fix"
summary: "ConvRulesEditor Convert tab: one click writes the engine's qualified #convert line (apply/1 qualify_fixes) into the open book"
product: DL
group: component-conversion
order: 60008
since: 1.31.5-alpha
status: shipped
updated: 1.35.0-alpha
---

# Qualify #convert quick fix

ConvRulesEditor Convert tab: one click writes the engine's qualified #convert line (apply/1 qualify_fixes) into the open book.

Fix an ambiguous bare #convert class the way the engine suggests, without retyping the line.

## Details

When a `#convert` line names a class by its bare name and that name is ambiguous in
the unit's scope (`#convert TLabel -> TSolo` where two units declare `TSolo`, or a
`TLabel` the unit never imports), convert-apply refuses the unit or warns, and
lists the qualified line(s) that would fix it in the apply/1 answer
(`qualify_fixes[]`). ConvRulesEditor turns that list into one click: it writes the
qualified class name into the open rule book, so you do not retype the line.

### Where it shows
On the Convert tab, for every run row that carries fixes -- a refused row AND a
converted one:

* the row's Note ends with `; N #convert side(s) to qualify`;
* the **Qualify #convert...** button (right of Cancel) is enabled when such a row is
  selected; double-clicking the row does the same;
* the run report (`convert-run-*.txt`) holds one `qualify` line per fix, naming the
  line, the side, the engine's reason and the exact replacement line(s) -- the text
  alternative (`#use LibA`, or a uses change) follows `; or:`.

### What one click changes
The dialog lists one row per fix (`line 1  from  TLabel  inferred -> Vcl.StdCtrls.TLabel`
/ `line 1  to  TSolo  refused`) and, for the selected fix, its candidates with the
engine's reason. An `inferred` fix starts with the engine's choice picked; a `refused`
fix (several candidates, none preferred) starts with none -- pick one, or the fix is
skipped. A preview shows the line as it will read. **Apply** edits the book open in
the editor (it is opened first when it is another book -- Save / Don't Save / Cancel
as for File > Open):

| before | pick | after |
|---|---|---|
| `#convert TLabel -> TSolo` | from = `Vcl.StdCtrls.TLabel` | `#convert Vcl.StdCtrls.TLabel -> TSolo` |
| `#convert Vcl.StdCtrls.TLabel -> TSolo` | to = `LibA.TSolo` | `#convert Vcl.StdCtrls.TLabel -> LibA.TSolo` |
| `#convert TLabel -> Vcl.StdCtrls.TStaticText, Vcl.StdCtrls` | from = `Vcl.StdCtrls.TLabel` | `#convert Vcl.StdCtrls.TLabel -> Vcl.StdCtrls.TStaticText, Vcl.StdCtrls` |

Only the named side changes; the other side, the `, Unit` list and every other line
stay. The edit is **not saved**: the status bar says `Qualified 2 #convert side(s) in
Fix.rules (line 1) -- not saved: File > Save, then Convert again`, and File > Exit /
New / Open ask to save as for any edit. Save, then Convert again: the row no longer
carries the qualify note and the refused unit converts.

### When a fix does not apply
Each is reported in the status line (`; K skipped: ...`), never raised:

* **stale** -- `line N no longer reads "..." -- the book changed since the run; run
  Convert again` (the book was edited or reordered after the run);
* **already qualified** -- `line N already qualified: ...` (done earlier, or from
  another results row of the same book);
* **ambiguous** -- the same header is written more than once; the lines are named, fix
  by hand;
* **no pick** -- `pick a candidate for line N <side> <name>`.

A header moved by a `#depth` or unit insert is found again by its text.

### What it needs
An engine that reports `convert_qualify_fix` in `info --json` (drag-lint 1.28.3 and
later). Without it the button stays hidden and the Note/report are as before.

### The `#use` alternative (to side)
Under the candidates the dialog shows the engine's alternative (`or: #use LibA`). For a
**to** side that alternative is clickable: **Add #use LibA** (the button right of the text)
turns the fix into a `#use` pick -- the candidate is dropped, the `#convert` line stays as
it is, and the preview says `will add to the book: #use LibA (the #convert line stays as
it is)`. Pressing it again (`Remove #use LibA`) or picking a candidate takes it back. The
alternative follows the candidate highlighted (`#use LibA` / `#use LibB`).

**Apply** inserts `#use LibA` ahead of the first `#convert` (the book's file-level section),
Unsaved like any edit; the status line ends `; added #use LibA` (or reads `Added #use LibA to
Fix.rules -- not saved: ...` when only `#use` picks were made). The line numbers it
names are the numbers AFTER the insert. A unit the book already has is not added twice
(`line N already has #use LibA`). A **from** side's alternative (`add Vcl.StdCtrls to the
unit's uses`) is a `.pas` edit the editor cannot make: shown as text, button disabled.
`#use` is a book-wide decision -- every `#convert` of the book then sees that unit.

### Qualify all
**Qualify all...** (right of Qualify #convert..., enabled whenever any row of the run
carries fixes, no row selection needed) fixes every row of the run, book by book. The
fixes are grouped per book (path compared case-insensitively, first-seen order); a fix
that several units' rows repeat (same line, header text, side and class name) is listed
once -- the first row's candidates are the ones shown. For each book the same dialog
opens (its title names the book), **Apply** edits it exactly as a single Qualify does,
and the loop moves on. A book other than the open one is opened first through the same
unsaved-changes guard as File > Open: after the first book's edit the open book is
unsaved, so the next book asks Save / Don't Save / Cancel. The loop **stops** (the books
already done stay edited, unsaved) when a dialog is cancelled, when that prompt is
cancelled, or when a book cannot be opened. The status line ends
`Qualify all (K of N book(s)[, stopped]): <one status per book, ' | '>`.

### Limits
A from-side alternative (a uses change) is shown, not applied. One click on
**Qualify #convert...** fixes one results row's book; **Qualify all...** covers the run
but one dialog and one save decision per book. No undo beyond Don't Save. A comment on the `#convert` line itself is dropped when the line is
rewritten (as for any header edit in the editor).

---

[All features](../index.md) | [CLI reference](../cli.md) | [IDE menus](../ide.md)
