# Qualify #convert quick fix

When a `#convert` line names a class by its bare name and that name is ambiguous in
the unit's scope (`#convert TLabel -> TSolo` where two units declare `TSolo`, or a
`TLabel` the unit never imports), convert-apply refuses the unit or warns, and
lists the qualified line(s) that would fix it in the apply/1 answer
(`qualify_fixes[]`). ConvRulesEditor turns that list into one click: it writes the
qualified class name into the open rule book, so you do not retype the line.

## Where it shows
On the Convert tab, for every run row that carries fixes -- a refused row AND a
converted one:

* the row's Note ends with `; N #convert side(s) to qualify`;
* the **Qualify #convert...** button (right of Cancel) is enabled when such a row is
  selected; double-clicking the row does the same;
* the run report (`convert-run-*.txt`) holds one `qualify` line per fix, naming the
  line, the side, the engine's reason and the exact replacement line(s) -- the text
  alternative (`#use LibA`, or a uses change) follows `; or:`.

## What one click changes
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

## When a fix does not apply
Each is reported in the status line (`; K skipped: ...`), never raised:

* **stale** -- `line N no longer reads "..." -- the book changed since the run; run
  Convert again` (the book was edited or reordered after the run);
* **already qualified** -- `line N already qualified: ...` (done earlier, or from
  another results row of the same book);
* **ambiguous** -- the same header is written more than once; the lines are named, fix
  by hand;
* **no pick** -- `pick a candidate for line N <side> <name>`.

A header moved by a `#depth` or unit insert is found again by its text.

## What it needs
An engine that reports `convert_qualify_fix` in `info --json` (drag-lint 1.28.3 and
later). Without it the button stays hidden and the Note/report are as before.

## Limits
The text alternative (`#use <Unit>`, a uses change) is shown, not applied. One click
fixes one results row's book; there is no "fix everything in the run" and no undo
beyond Don't Save. A comment on the `#convert` line itself is dropped when the line is
rewritten (as for any header edit in the editor).
