# repo write-dfm, second round (lane DFMWRITE2, 1.55)

Owner rulings 2026-11-26 on the questions of lane DFMWRITE (1.54). Base: `2026-11-22-field-repository-v2-design.md`
sections 3, 4.4, 9 and the 1.54 page `docs\wiki\repo-write-dfm.md`. Engine: `src\sql\DRagLint.FieldRepo.DfmWritePlan.pas`
(planner + applier) and `src\sql\DRagLint.FieldRepo.DfmWrite.pas` (byte-exact DFM and unit editors).

## Q1 A -- a field event the repository holds and the form lacks is created

**What changes.** For every field of the planned dataset -- an existing persistent field and a field the selection adds
("a field added to the dataset brings all its events with it") -- and every TField event column of `DL_FIELDS_INFO`
(`ONGETTEXT_BODY`, `ONSETTEXT_BODY`, `ONVALIDATE_BODY`, `ONCHANGE_BODY`, the list `FR_EVENT_COLUMNS` without the grid
ones): when the body is not empty and the DFM assigns no handler for that event, one change creates the handler:

* DFM: `OnGetText = <Dataset><Field>GetText` on the field (the handler name is the dataset component name, the
  FIELD_NAME and the event without `On`; characters that are no identifier characters are dropped), at its streaming place;
* unit: `procedure <Name>(<the event's parameters>);` in the form class, after the component declarations (fields
  before methods, as Delphi requires), and the method before `initialization` / `finalization` / the final `end.`:
  `begin`, a DLFR region `<Component>.<Event>` holding the body with its macros expanded exactly as `repo handlers`
  does it (`EventRegionContent`), `end;`. A later `repo handlers` run finds the region current.

**Change-set shape.** op `insert`, target `<form>.dfm <Component>`, prop `<Event>`, new value = the handler name.
Always **unchecked** (code is written). The change of a field that is added `Requires` that insert. The DFM part is
applied in a second pass over the rendered bytes, so a new field gets its event too, and the declaration goes after
every new field declaration.

**Refusals (BLOCKED).** no unit beside the DFM; the unit does not declare the form class; the name is already a token of
the unit (a method or anything else of that name); the body has a macro the dataset cannot resolve (the reason of
`ExpandBody`); no line-structured place for the declaration or the method (a conditional, other code on the line).
A handler the DFM already assigns is never touched here: its body is `repo handlers`' job.

**Tests.** `run_v155_DFMWRITE2.ps1` E1-E5: dry run lists the event change unchecked, only for a field with a body;
`--apply` does not write it; `--select` writes DFM + declaration + method and nothing else, the form compiles and loads
and the handler runs (`gettext=TRUE|Q5`), a second plan has no event change (the handler is assigned now), and
`repo gen-handlers` reports the region `unchanged`; a new field selected with its event: the event `Requires` the insert
(`--select` of the event alone exits 2), both written, the form loads; a clash with an existing name is BLOCKED.

## Q3(1) NO -- grid columns that are not fields are written (lane GRIDCOL)

**What changes.** A graphical row (FIELD_KIND 10) of the dataset's table whose column the form lacks becomes a grid
column: `object <COLUMN_NAME>: TcxGridDBColumn` in the view `DL_GRID_COLUMNS` names for this form and that table and
field (else the only `TcxGridDBTableView` whose `DataController.DataSource` is a data source of the dataset, named
`<View><FIELD_NAME>`, after the last column), at its stored `COLUMN_INDEX`, with `Caption = DISPLAY_LABEL` (when stored)
and `DataBinding.FieldName = '<FIELD_NAME>'` -- the dataset has no such field, so the column is unbound, and `repo
read-dfm` finds the row again (TABLE_NAME / FIELD_NAME of its DL_GRID_COLUMNS row, the column events stored on it).
Declared in the unit after its neighbour (the column before it, else the view). `GRID_DISPLAYTEXT_BODY` /
`GRID_DRAWCELL_BODY` become `OnGetDisplayText = <Column>GetDisplayText(Sender: TcxCustomGridTableItem; ARecord:
TcxCustomGridRecord; var AText: string)` / `OnCustomDrawCell = <Column>CustomDrawCell(Sender: TcxCustomGridTableView;
ACanvas: TcxCanvas; AViewInfo: TcxGridTableDataCellViewInfo; var ADone: Boolean)`, made as in Q1 (DLFR region `<Column>.<Event>`,
`{{FIELD}}` = the field component).

**The second confirmation.** Change shape: op `insert`, target `<form>.dfm <Column>`, new value
`TcxGridDBColumn; <View> index <n>; <the block's properties>`; each handler an `insert` of `<Column> <Event>` that
`Requires` the column. All **unchecked**, always: `--apply` never writes them; the dry run shows them, and only their ids
in a `--select` file (with the plan line of that dry run) write them. A handler selected without its column exits 2. No
new flag: the select file IS the confirmation, as for Q1 handlers and Q3(2) removals. (`--select all` still selects
them, as it selects every unblocked change.)

**Not written / refused.** A column the view already has (a column bound to FIELD_NAME, or one with the planned name):
nothing. Two views of the dataset and no DL_GRID_COLUMNS row, or a DL_GRID_COLUMNS view that is no table view of the
dataset: a warning, nothing planned. BLOCKED: a name another component or the unit already has, an inherited view, a
unit that does not use `cxGridDBTableView` (column), `cxGridCustomTableView` (handlers), `cxGraphics`
(`OnCustomDrawCell`). The editor properties of an image / check-box / button column (`PropertiesClassName`, ...) are not
in the repository and not written. Banded, card and layout views and tree lists: not written (DBTable first, Q18 A).
The 1.54 warning "graphical columns are grid columns, not written" is gone (W1e of run_fieldrepo_dfmwrite changes by
this ruling). The plan id covers DL_GRID_COLUMNS.

**Tests.** `run_v155_GRIDCOL.ps1` G1-G7: dry run (both places, both handlers, unchecked; STATUS, whose column the form
has, plans nothing); `--apply` leaves them out; a handler without its column exits 2; `--select` writes block,
declarations and methods and nothing else; the form compiles and loads (`columns=4,2`, the new column at index 3, its
OnGetDisplayText gives `P5`, colPic at index 0); a second plan is empty for them and read-dfm stores no other code;
refusals (taken name, missing cxGraphics, two views).
## Q3(2) NO -- removing a field takes its grid / layout items with it

**What changes.** A planned removal of field F (FieldName N) of dataset D looks for the grid and layout items bound to
it: objects of class `Tcx*` whose `DataBinding.FieldName` is N and one of whose enclosing objects has
`DataController.DataSource` = a data source whose `DataSet` is D (cxGrid table / banded / card / layout views, their
columns, rows and items; a cxDBTreeList and its columns). Each becomes a change of its own, planned before the field:
op `delete`, target `<form>.dfm <item>`, old value `<class>; DataBinding.FieldName = 'N'`, **unchecked**. The removal of
the field `Requires` all of them (`--select` refuses the field without its items) and is no longer blocked by their
`DataBinding.FieldName`. Removing an item alone is allowed. The item's declaration leaves the unit as a field's does;
an event handler of the item stays (an unused method compiles).

**Refusals.** An item another property of the DFM names (a summary item's `Column`, a band, `SortedColumn`) or that the
code of the unit uses is BLOCKED with that reason, and then so is the field ("its grid item X cannot be removed: ...").
Every other binding (a `TDBEdit.DataField`, a VCL `TDBGrid` column, a summary item's `FieldName`, `KeyField`, a SQL
parameter) still blocks the field as in 1.54.

**Tests.** E7-E10: the tree-list column of NOTE is a linked unchecked delete; the field `Requires` it; `--select` of the
field alone is refused (exit 2); field + item written, the form loads; the grid column of QTY is BLOCKED by the footer
summary's `Column` and so is QTY. The 1.54 check W13a (NOTE blocked by TreeNOTE) changes by this ruling.

## Q3(3) YES -- BDE datasets stay read-only

No change: a new column field in a BDE dataset stays BLOCKED, `Size` of a BDE string column is not written. Q1 and Q3(2)
follow the same rule: an event or a removal on a BDE dataset is planned like on any other (it writes no column).

## Q3(4) -- aggregates the repository does not hold

No change: an aggregate field with no row changes nothing and is reported as 1.54 does.
