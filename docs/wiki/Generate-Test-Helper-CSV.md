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
| `Modal` | `Yes` (ShowModal), `No` (Show), `?` when the launching code does not say. |
| `Before you start` | A precondition, ONLY when it can be derived honestly: the handler reads a selection or a dataset field of a component on the launching form (`frmJobList: select a row in grdJobs first (the handler reads grdJobs.DataController)`). Blank otherwise -- blank does not mean "no precondition". |
| `Other ways in` | How many other controls or handlers also open this form; up to three are listed in `Notes` after `also:`. |
| `Confidence` | `traced` -- every hop ends at a control a tester can press; `handler-only` -- the opening routine is known but nothing on screen fires it (assigned in code, a timer, an action no control shows); `unresolved` -- no path from the main form. |
| `Tester result` | Left blank for the tester. |
| `Notes` | `found by: index` (resolved call graph + `.dfm`) or `found by: text scan` (the fallback for chains the call graph cannot follow, e.g. interface dispatch or proc-variable hooks), plus any `also:` list and explanations. |

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
3,"frmGroups6","uGroups6","Main menu: Setup > Groups > Assign Groups","Assign Groups","TMenuItem","TfrmMain6.mnuAssignGroupsClick","uHelpers6.OpenAssignGroups","Yes",,0,"traced",,"found by: index"
7,"frmNag6","uNag6","(no control: TfrmMain6.DoNagTimer)",,,"TfrmMain6.DoNagTimer","TfrmMain6.DoNagTimer","Yes",,0,"handler-only",,"found by: index; DoNagTimer is not bound to any control in uMain6.dfm (assigned in code?)"
8,"frmReports6","uReports6","Tab 'Reports' > Run Reports","Run Reports","TButton","TfrmMain6.actReportsExecute","TfrmMain6.actReportsExecute","No",,0,"traced",,"found by: index"
```
