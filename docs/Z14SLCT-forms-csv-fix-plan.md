# Z14SLCT forms-csv "DEAD FORM" False-Positive -- Fix Plan

Date: 2026-06-26
Project: drag-lint (DRagLint.FormsMap.pas + DRagLint.CLI.pas)
Symptom: Micronite2027-forms.csv line 51 reports Z14SLCT as "DEAD FORM -- no callers found"
Status: Root cause identified. Fix approach: use the full project-covering DB (all units
  from .dpr/.dproj, including COMMON/OBJECTS), not a CLIENT-only DB.
  Another agent is currently modifying DRagLint.FormsMap.pas (+232/-42 lines as of
  2026-06-26) -- coordinate before touching that file.

## Root Cause

GenerateFormsCsv opens a single SQLite DB (ADbPath). When run with the CLIENT-only DB:

  ADbPath = C:\Projects\DB\ORM3\CLIENT\Micronite2027.sqlite  (CLIENT units only)

BuildEdges queries the `refs` table from this DB. The actual caller of TZ14slctFrm is
TANSIZ14Plan.EditForm at uPLANLIST.PAS:2529. That file lives in COMMON\OBJECTS -- it is
indexed in the full ORM3 DB but NOT in the CLIENT-only DB. Result: no refs found -> "DEAD FORM".

## Verified Caller

File: C:\Projects\DB\ORM3\COMMON\OBJECTS\uPLANLIST.PAS
  Line 1024: , Z14Slct  (implementation-section uses)
  Lines 2525-2558: TANSIZ14Plan.EditForm -- creates TZ14slctFrm, ShowModal, Free

The form IS reachable: CP2 Plan button -> TANSIZ14Plan.EditForm -> TZ14slctFrm.

Same root cause explains z19Slct, TrpsSlct, uCPSched as DEAD -- all have callers in
COMMON/OBJECTS. The fix below resolves them all.

## Fix Approach (user-directed 2026-06-26)

"We need to have all units mentioned in the dpr and dproj files to the database,
same for the server as well."

The correct fix is to pass a DB that covers ALL units referenced by the project
(both CLIENT and COMMON/OBJECTS), not a CLIENT-only DB.

### Option A -- Use full ORM3 DB (immediate, no code change)

Run forms-csv with the full ORM3 DB:

  drag-lint forms-csv ^
    --project "C:\Projects\DB\ORM3\CLIENT\Micronite2027.dproj" ^
    --db "C:\Projects\DB\ORM3\drag-lint.sqlite" ^
    --out "C:\Projects\DB\ORM3\CLIENT\docs\debug\Micronite2027-forms.csv"

LoadInventory already has a project-unit filter: it reads the .dpr and only includes
forms whose unit appears there. So the report stays scoped to CLIENT forms; refs come
from the full ORM3 tree. No code change needed.

Verification: check that the .dpr lists only CLIENT-side units (not COMMON ones by name).
If the .dpr does NOT list a form unit it would be excluded from the report -- that is
correct behaviour (it's not part of this build).

### Option B -- Expand the CLIENT DB to include all project units (requires indexer change)

Alternatively, update the drag-lint.json manifest so the CLIENT project DB indexes
not only the CLIENT directory but also all unit search paths declared in Micronite2027.dproj.
This is a bigger indexer change (parse .dproj SearchPath, add those dirs to the index
walk) but would make the CLIENT DB self-contained for all callers.

The manifest entry for Micronite2027 in drag-lint.json would need to include the
COMMON\OBJECTS folder as an additional indexed path.

### Recommended: Option A first, then decide on Option B

Option A is zero-code and immediately verifiable. Option B is more principled long-term
(each DB is self-contained for its project) but requires parser work.

## Server DB

Same issue applies to the server project DB. When running forms-csv for the server:

  drag-lint forms-csv ^
    --project "C:\Projects\DB\ORM3\SERVER\MicroniteMW1Service.dproj" ^
    --db "C:\Projects\DB\ORM3\drag-lint.sqlite" ^
    --out "C:\Projects\DB\ORM3\SERVER\docs\debug\MicroniteMW1-forms.csv"

(Using the full ORM3 DB so SERVER + COMMON callers are both found.)

## Affected Files (if code change is needed for Option B)

  src/cli/DRagLint.CLI.pas or drag-lint.json  -- extend index walk to include .dproj search paths
  src/forms/DRagLint.FormsMap.pas             -- no change needed for Option A

CAUTION: Another agent has +232/-42 lines of changes on DRagLint.FormsMap.pas (2026-06-26).
Inspect their diff carefully before any merge.

## Expected Output After Fix

Z14SLCT should show in Called From column: something like "frmCP2 (via EditForm)" or the
TANSIZ14Plan ancestor chain. The "DEAD FORM" note should disappear.
