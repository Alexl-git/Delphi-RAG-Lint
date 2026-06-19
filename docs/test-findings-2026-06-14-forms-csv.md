# forms-csv ORM3 Smoke Findings -- 2026-06-14

## Summary

Task 7 (real ORM3 run) surfaced two bugs in the `forms-csv` engine. Task 7b
implemented fixes for both. This document records the before/after numbers
and explains the residual `(no path from MAIN)` issue.

---

## Bug 1: Wrong root detection

**Root before fix:** `dlgOperatorList` (blank Navigation)
**Root after fix:** `frmMAIN` (blank Navigation -- correct)

**Cause.** `DetectRoot` scanned the `.dpr` lines in order and returned the
FIRST `Application.CreateForm(Tclass)` whose class was a form node. The
ORM3 `.dpr` (`Micronite2027.dpr`) has a bootstrap procedure
`RunAdminBootstrap` at line 585 that calls
`Application.CreateForm(TdlgOperatorList, dlgOperatorList)` -- textually
before the real main block at line 641:

```
else begin Application.CreateForm(TdmStyles, dmStyles); Application.CreateForm(TfrmMAIN , frmMAIN ); Application.Run; end;
```

The old algorithm exited on the first match (dlgOperatorList). The new
algorithm remembers the **last** form-node CreateForm **at or before the
first `Application.Run` on the same line**, yielding `TfrmMAIN`.

A secondary complication: `Application.Run` and two `Application.CreateForm`
calls are all on the same one-liner (line 641). The fix scans all CreateForm
occurrences on the same line up to the position of `Application.Run`, then
stops -- so `TfrmMAIN` is picked correctly even though the whole main block
is one line.

---

## Bug 2: Backup-file noise

**Before fix:** 2 duplicate rows (`Blueprint4 - Copy`, `uSetupDefaultsFrm - Copy`)
**After fix:** 0 duplicate rows

**Cause.** The index covered the fixture directory including `*- Copy.pas/dfm`
backup files. Two new defences:

- `IsBackupPath`: case-insensitive contains ` - copy` or `-copy`; or ends
  `.bak`/`.bck`/`.old`/`.orig`. Applied to DFM path, PAS path, and UnitName.
- `LoadProjectUnits`: reads the sibling `.dpr`'s uses clause and returns
  lowercased unit basenames. `LoadInventory` skips any form whose UnitName is
  not in this list (when the list is non-empty). Eliminates all out-of-project
  forms -- backup copies, stale generated units, etc.

---

## Before / After Numbers (ORM3 real project)

| Metric                      | Before fix | After fix |
|-----------------------------|-----------|-----------|
| Total form rows             | 54        | 47        |
| `- Copy` duplicate rows     | 2         | 0         |
| Root form                   | dlgOperatorList (wrong) | frmMAIN (correct) |
| `(no path from MAIN)` rows  | 53        | 46        |
| Forms with real Navigation  | 0         | 1 (frmMAIN itself, blank = root) |
| Forms with Called From data | ~0        | 6         |
| `(via ...)` captions        | 0         | 0         |

The 7 removed rows: 2 backup copies + 5 forms whose units are not in
`Micronite2027.dpr` uses clause (some from other client sub-projects or
generated stubs in the indexed directory).

---

## Residual (no path from MAIN): index is stale

**46 of 47 forms** still show `(no path from MAIN)`. This is NOT a bug in
the engine -- it is an **indexing staleness problem**.

**Root cause.** The engine builds edges by querying `refs` for form class
name occurrences in `.pas` files, then checking the actual source line to
confirm it is a launch call (e.g. `TfrmJobList.Create(...)`). The ORM3 index
was built with an older version of drag-lint and the construction-site refs do
not match current file line numbers. Examples:

- `TfrmBlueprint4` ref is recorded at `uJobList.pas:1771`, but the file
  only has 1682 lines (file was shorter when indexed). `IsLaunchLine` returns
  false for the out-of-range line.
- `TfrmJobList` ref is recorded at `uMain.pas:689` (near a comment), not at
  the actual construction site `uMain.pas:660` (`TfrmJobList.Create(Application)`).

The 6 rows that DO have Called From data work because Blueprint4 happens to
have refs with line numbers that still match `TFormClass.Create` lines.

**Recommendation: re-index ORM3 with current drag-lint.**

```
drag-lint.exe index --project C:\Projects\DB\ORM3\CLIENT\Micronite2027.dproj --db C:\Projects\DB\ORM3\drag-lint.sqlite
```

After re-indexing, re-run `forms-csv`. Expected result: the navigation
graph will be populated from fresh construction-site refs, and the `(no path
from MAIN)` count should drop substantially (forms reachable from `frmMAIN`
via button clicks / MDI launches will get correct paths).

Caption resolution (`(via RoutineName)` vs real caption) also depends on the
index having DFM `event-binding` refs with correct line numbers so
`CaptionForHandler` can locate the bound control. The event-binding refs in
the current ORM3 index appear correctly indexed (e.g. `uMain.dfm:461
OnClick = btnJobListClick`) so captions should resolve once construction refs
are fresh.

---

## VALIDATED: fresh-index re-run (staleness confirmed, engine correct)

The staleness theory was confirmed and the engine proven on real data. The ORM3
`CLIENT` tree was re-indexed into a temp db (`drag-lint index C:\Projects\DB\ORM3\CLIENT
--db <temp>`, 307 files / 102,362 refs / 17.8s) and `forms-csv --project
Micronite2027.dproj --db <temp>` was re-run. The user's working index was left
untouched.

Confirmation of staleness: the old index records `TfrmBlueprint4` refs at
`uJobList.pas:1771` and `:1789`, but that file is only 1682 lines -- past EOF, so
`IsLaunchLine` correctly read nothing and built no edge.

| Metric                      | Stale index | Fresh index |
|-----------------------------|-------------|-------------|
| Form rows (excl header)     | 46          | 46          |
| `(no path from MAIN)` rows  | 46          | 16          |
| Forms with a real captioned path | 0      | 29          |
| Root                        | frmMAIN     | frmMAIN     |

Real navigation chains now resolve exactly as designed, e.g.:

```
frmBlueprint4 (MDI)   frmMAIN -> 'Job List' -> 'Open Folder'
frmConfirmorCancel    frmMAIN -> 'Job List' -> 'Open Folder' -> 'Delete Operation'
frmControlPlanningPresets  frmMAIN -> 'Default Settings ...' -> 'Control Planning Presets'
dlgOperatorList       frmMAIN -> 'Personnel List'
```

Called From is populated too (e.g. frmBlueprint4 <- `frmCPSched (Exit to Blueprint4);
frmJobList (Open Folder)`). A small number of hops render `(via Routine)` where the
launching routine has no captioned binder (keep-the-gap, by design).

The remaining 16 `(no path from MAIN)` are forms opened through generic ViewModel /
factory indirection (no form-class token at the call site) -- the documented limitation.
These are candidates for the optional auto-derivation follow-up or manual Notes entry.

**Net:** the feature works on the real project. The only operational requirement is that
the project index be current (re-index if forms-csv shows mostly `(no path)`). NOTE: the
user's daily index `C:\Projects\DB\ORM3\drag-lint.sqlite` is stale and would benefit from
a re-index (this affects all drag-lint features, not just forms-csv) -- left to the user.

---

## Fixture smoke (all 23 checks pass)

```
[PASS] index fixture exits 0
[PASS] forms-csv exits 0
[PASS] csv exists
[PASS] header present
[PASS] frmMain row present
[PASS] frmList row present
[PASS] frmEdit row present
[PASS] data module excluded
[PASS] pas line count for frmEdit
[PASS] row count is 7 forms + header
[PASS] frmMain is root (blank nav)
[PASS] frmList nav via Lists
[PASS] frmEdit nav via Lists>Edit
[PASS] frmChild nav via named ctor
[PASS] action-bound caption (Reports)
[PASS] keep-the-gap via routine
[PASS] unreachable form
[PASS] called-from for frmEdit
[PASS] no hang (script completed)
[PASS] root regression: frmMain root (blank nav)
[PASS] root regression: frmEdit still reachable
[PASS] backup copy excluded
[PASS] no duplicate frmEdit
```

The root regression test (Task 7b fixture): `Demo.dpr` was extended with a
`procedure RunAdminBootstrap` above `begin` that calls
`Application.CreateForm(TfrmEdit, frmEdit)`. The new `DetectRoot` correctly
ignores it and still picks `TfrmMain` (last form-node CreateForm before
`Application.Run`).

---

## Files changed (Task 7b)

- `src/forms/DRagLint.FormsMap.pas` -- `DetectRoot` rework + `LoadProjectUnits`
  + `LoadInventory` backup/project filter + `IsBackupPath` helper
- `tests/fixtures/formsmap/Demo.dpr` -- bootstrap procedure added
- `tests/fixtures/formsmap/uDemoEdit - Copy.pas` -- backup fixture
- `tests/fixtures/formsmap/uDemoEdit - Copy.dfm` -- backup fixture
- `tests/autotest/run_formsmap.ps1` -- 4 new Task 7b assertions
