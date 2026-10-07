# Generate Test Helper CSV

Produces a spreadsheet-style CSV of a project's forms, one row per form,
telling a human tester how to reach each form from the main form: the menu,
ribbon, toolbar or tab path, the control to click, the handler it runs, the
routine that opens the form, whether it opens modally, and how sure the tool
is. Open it in Excel, fill in the **Tester result** column, and hand it back.

## Running it from the CLI
```
drag-lint forms-csv --project <X.dproj> --db <file.sqlite> [--output <f.csv>] [--root <TfrmMAIN>]
```
`--project` is the `.dproj` to enumerate forms for; `--db` is the
project's index database (repeat `--db` to add an index that holds launch
code living outside the project, e.g. COMMON); `--output` sets the output CSV
path (without it the CSV goes to stdout); `--root` sets the root form to start
from (default: the last form the `.dpr` creates before `Application.Run`).

## Reaching it in the IDE
drag-lint > Reports > Forms for testers (CSV)... (it was a stand-alone item on the drag-lint menu before 2026-10-05)

## What it needs
An index IS required. The project's DB lives at
`<project folder>\_D-RAG\<project file>.sqlite`; run
`drag-lint resolve-dbs --project <X.dproj>` if unsure. The form `.dfm` files
are also read directly (text `.dfm` only) to work out menu and tab paths.

## Columns (algorithm v6)

| Column | Meaning |
|---|---|
| `#` | Row number. |
| `Form` | The form's design-time name, e.g. `frmAssignGroups`. |
| `Unit` | The unit that holds it. |
| `How to open` | Full path from the main form. Each hop after the first says which form it happens on: `Main menu: Setup > Groups > Assign Groups -> in frmGroups: Edit Group`. Locations read `Main menu: ...`, `Ribbon: <tab> > <group> > <item>`, `Toolbar '<bar>' > ...`, `File menu > ...` (ribbon backstage), `Right-click menu <name>: ...`, or `Tab '<sheet>' > <control>`. Menu accelerators (`&`) are stripped. |
| `Click` | Caption of the control on the last hop; `[name]` when it has no caption; a gesture in brackets when it is not a plain click, e.g. `[grid] (double-click)`. |
| `Control type` | Its class, e.g. `TMenuItem`, `TdxBarLargeButton`, `TButton`. |
| `Handler` | The event handler that control runs, `TfrmX.btnFooClick`. |
| `Opened by` | The routine that actually creates or shows the form (a helper, a view-model method, or the handler itself). |
| `Modal` | `Yes` (ShowModal) or `No` (Show), read from the launching routine after the line that creates the form: a `ShowModal`/`Show` on the variable it was created into (or its global instance, or bare INSIDE a `with F do` block -- `Self.ShowModal` there is the outer form's and does not count), or a method of the form called on that variable whose own body shows it (`F.Execute` -> `ShowModal`). A variable assigned again stops counting; a form shown both ways (`if A then F.ShowModal else F.Show`) is `?` with `modal unknown: shown both modally and modelessly`. When the code does not say, the form's `.dfm` can: `FormStyle = fsMDIChild` or `Visible = True` means it is shown as soon as it is created and can never be modal, so `No`, and `Notes` says `modal from <file>.dfm: <property>`. `?` only when neither answers, and then `Notes` always says why (`modal unknown: TfrmMain.btnCacheClick creates frmCache but does not show it there`) -- never a guess. Edges found by the text scan get the same treatment as index edges. |
| `Before you start` | What the tester must set up first, ONLY when it can be derived honestly, for EVERY hop of the path (in hop order, `; `-separated), each prefixed with the form the tester is on: a selection or dataset field of a component on that form the handler reads (`frmJobList: select a row in grdJobs first (the handler reads grdJobs.DataController)`), and a message the handler or the opening routine stops with before it opens the form -- a conditional `raise E.Create('...')`, or a `ShowMessage` literal (or an `mtError`/`mtWarning` `MessageDlg` not compared with an `mrXxx` result -- a confirmation question is not a precondition) followed by `Exit`; in a handler that calls another routine, only checks ABOVE that call count (`frmBlueprint: it refuses with "You have to enter Part Number ..." until that is set up`; at most three messages per hop). Blank otherwise -- blank does not mean "no precondition". |
| `Other ways in` | How many other controls or handlers also open this form; up to three are listed in `Notes` after `also:`. |
| `Confidence` | `traced` -- every hop ends at a control a tester can press; `handler-only` -- the opening routine is known but nothing on screen fires it (assigned in code, a timer, an action no control shows); `unresolved` -- no path from the main form. |
| `Tester result` | Left blank for the tester. |
| `Notes` | `found by: index` (resolved call graph + `.dfm`) or `found by: text scan` (the fallback for chains the call graph cannot follow, e.g. interface dispatch or proc-variable hooks), plus explanations, the `modal from ...` / `modal unknown: ...` note, and any `also:` list. An unresolved form shows `no caller found (index or text scan)`, or the note the project declares for it as a popup form (below). |

## Popup forms (project config)

Some forms are opened by a mechanism no index can trace -- a shared
right-click menu, a component's own popup. Declare them in the project's
`<project folder>\_D-RAG\drag-lint-project.json` (the same file that holds
`ownRoots`) under `popupForms`; an unresolved row for such a form prints the
note instead of `no caller found`:
```
{
  "ownRoots": [ ... ],
  "popupForms": [
    { "form": "frmGridLayout", "note": "popup via TGridMenuPopup (Save/Load Layout)" }
  ]
}
```
`form` is the form's design-time name (case-insensitive); `note` is optional
(default `opened as a popup (declared in drag-lint-project.json)`). A missing
file or key is normal; a malformed file is ignored with one line on stderr, and a bad entry (no `form`, or a `form` that is not a string) skips only that entry, with its own stderr line. The CSV is produced in every case.

`drag-lint-project.json` normally lives OUTSIDE version control (check your repository's ignore rules), so `popupForms` is a per-machine setting: a fresh clone or a new worktree does not have it, and each machine that runs `forms-csv` needs its own copy -- unless your repository deliberately tracks the file.
The engine carries no project's form names of its own.

The last line is a provenance footer in the `Notes` column:
`# forms-csv algorithm v6 | db: <path> | schema v<n> | <timestamp>`. The IDE
plugin warns about a stale engine when this version differs from what it
expects.

## Example
Illustrative only:
```
drag-lint forms-csv --project C:\Projects\MyApp\MyApp.dproj --db C:\Projects\MyApp\_D-RAG\MyApp.sqlite --output C:\Projects\MyApp\forms.csv --root TfrmMain
```
Example rows (from the test fixture `tests\fixtures\formsmap-v6`):
```
#,Form,Unit,How to open,Click,Control type,Handler,Opened by,Modal,Before you start,Other ways in,Confidence,Tester result,Notes
1,"frmCache6","uCache6","Tab 'More' > Cache","Cache","TButton","TfrmMain6.btnCacheClick","TfrmMain6.btnCacheClick","?",,0,"traced",,"found by: index; modal unknown: TfrmMain6.btnCacheClick creates frmCache6 but does not show it there"
4,"frmGroups6","uGroups6","Main menu: Setup > Groups > Assign Groups","Assign Groups","TMenuItem","TfrmMain6.mnuAssignGroupsClick","uHelpers6.OpenAssignGroups","Yes","frmMain6: select a row in qryItems first (the handler reads qryItems.FieldByName)",0,"traced",,"found by: index"
9,"frmMdi6","uMdi6","Tab 'More' > Open MDI","Open MDI","TButton","TfrmMain6.btnMdiClick","TfrmMain6.btnMdiClick","No",,0,"traced",,"found by: index; modal from uMdi6.dfm: FormStyle = fsMDIChild"
10,"frmNag6","uNag6","(no control: TfrmMain6.DoNagTimer)",,,"TfrmMain6.DoNagTimer","TfrmMain6.DoNagTimer","Yes",,0,"handler-only",,"found by: index; DoNagTimer is not bound to any control in uMain6.dfm (assigned in code?)"
14,"frmSerial6","uSerial6","Tab 'More' > Serials","Serials","TButton","TfrmMain6.btnSerialClick","TfrmMain6.btnSerialClick","Yes","frmMain6: it refuses with ""Add an item before defining serial numbers"" until that is set up",0,"traced",,"found by: index"
```
