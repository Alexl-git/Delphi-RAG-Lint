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
