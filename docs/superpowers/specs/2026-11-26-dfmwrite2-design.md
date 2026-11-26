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

## Q3(1) NO -- grid columns that are not fields are written

**What changes (designed, NOT built in this lane).** A graphical row (FIELD_KIND 10) of the dataset's table becomes a
grid column: `object <COLUMN_NAME>: TcxGridDBColumn` in the view `DL_GRID_COLUMNS` names for this form (else the only
`TcxGridDBTableView` whose `DataController.DataSource` is a data source of the dataset), at its stored `COLUMN_INDEX`,
declared in the unit, with `OnGetDisplayText` / `OnCustomDrawCell` handlers made as in Q1 from `GRID_DISPLAYTEXT_BODY` /
`GRID_DRAWCELL_BODY`. Change shape: op `insert`, unchecked (the owner's "second confirmation"), each handler a further
unchecked change that `Requires` the column.

**Why not now.** It needs a view resolver, the cx event signatures and macros for column events (GRID_* bodies are
stored, never generated yet -- rulings 2026-11-23 item 9), and a load fixture with drawn columns: more than a day. The
1.54 warning "graphical columns are grid columns, not written" stays until then.

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
