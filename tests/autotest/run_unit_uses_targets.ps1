<#
  run_unit_uses_targets.ps1 -- INDEX-TIME repair of unit_uses.target_file_id
  (design doc 2026-07-29-proptree-ancestor-scope-design.md section 3.2,
  acceptance criterion 12: "AFTER a re-index, unit_uses.target_file_id SHALL be
  populated for a unit whose `uses` name matches an indexed file").

  THE BUG. UnitNameNorm() stores a used unit's LAST DOTTED SEGMENT
  ('Vcl.Controls' -> 'controls'), and ResolveUnitUseTargets compared that
  against a file's FULL basename stem ('vcl.controls'). For a dotted unit name
  those two can never be equal, so every dotted `uses` row stayed NULL.
  Measured on library-Win64.sqlite before the fix: 122 of 38512 dotted rows
  resolved -- and those 122 were WRONG, dotted names that had landed on an
  unrelated file named after their last segment ('uses Fmx.Editor.MaskEdit'
  matching FMX.MaskEdit.pas). Overall 41.8% of rows resolved; after, 91.0%.

  THE RULES NOW, in order (first hit wins; no hit leaves the row NULL):
    A. EXACT -- the lowercased used-unit name equals a file's lowercased
       basename stem. A name equality, not an inference. Applies to dotted and
       bare names alike, and is NOT restricted by the GUI rule below.
    B. UNIT SCOPE NAMES -- a used name may match a DOTTED stem by that stem's
       last segment ('uses Beta' -> Ns.Beta.pas). An INFERENCE, so it carries
       three restrictions, each independently pinned below:
         * BARE NAMES ONLY   (case E)
         * exactly ONE distinct stem carries the segment   (case D)
         * the target stem is NOT in a GUI framework namespace   (case G)
       This is Delphi's own unit-scope-names resolution, in the only direction
       Delphi performs it.
  The pass RECOMPUTES rather than tops up -- it clears target_file_id and
  refills, in one transaction -- so it can REPAIR a wrong value rather than
  preserve it (the 'repair:' checks at the end).

  EACH CASE IS INDEPENDENTLY RED-ABLE against a specific line of the fix:
    A  dotted exact      -- RED if the norm-vs-stem comparison comes back
    B  bare exact        -- RED if rule A is dropped (also the pre-fix regression guard)
    C  bare -> dotted    -- RED if rule B is dropped
    D  ambiguous segment -- RED if rule B stops requiring a UNIQUE stem
    E  dotted -> other   -- RED if rule B stops being bare-only
    F  no such unit      -- RED if anything resolves a name with no candidate
    G  bare -> GUI stem  -- RED if the IsGuiFrameworkPrefix refusal is dropped
    H  dotted -> GUI stem-- RED if that refusal is applied to rule A as well
    repair (x2)          -- RED if the pass goes back to filling only NULL rows

  CASE E's RED-ABILITY IS FRAGILE, and was silently lost once: it needs its
  segment ('alpha') to stay UNIQUE across the fixture. A second file whose stem
  ends in '.alpha' makes rule B decline on AMBIGUITY instead, so case E then
  passes with or without the bare-only restriction and stops testing anything.
  That is exactly what adding a 'Vcl.Alpha.pas' for case H did. Case H uses the
  unshared segment 'delta' precisely so it cannot recur -- do not give any new
  fixture file a stem ending in '.alpha'.

  NOT covered here, deliberately: ancestor resolution. ResolveAncestry does not
  read this column at all (it scopes candidates textually), which is why an
  index built before this fix is not wrong about ancestry and needs no
  re-index. run_proptree_ancestry_bridge.ps1 is where that is pinned.
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\drag-lint-unit-uses-targets"
)
$ErrorActionPreference = 'Stop'
$script:Failed = $false
function Check($n, $ok, $d = '') {
  $s = if ($ok) { 'PASS' } else { 'FAIL' }
  $c = if ($ok) { 'Green' } else { 'Red' }
  Write-Host ("  [{0}] {1} {2}" -f $s, $n, $d) -ForegroundColor $c
  if (-not $ok) { $script:Failed = $true }
}

if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
$Exe = (Resolve-Path $Exe).Path
if (Test-Path $WorkDir) { Remove-Item -Recurse -Force $WorkDir }
New-Item -ItemType Directory $WorkDir | Out-Null
$work = Join-Path $WorkDir 'fixture'
New-Item -ItemType Directory $work | Out-Null

function Write-Ascii([string]$Path, [string]$Body) {
  $norm = $Body -replace "`r`n", "`n" -replace "`n", "`r`n"
  [System.IO.File]::WriteAllText($Path, $norm, [System.Text.Encoding]::ASCII)
}

# --- The indexed units the uses clause below will (or must not) resolve to. ------
Write-Ascii (Join-Path $work 'Ns.Alpha.pas') @'
unit Ns.Alpha;

// Stem 'ns.alpha', last segment 'alpha' -- and NO other indexed stem in this
// fixture ends in '.alpha', so 'alpha' is a UNIQUE segment. Target of case A
// (by its full name) and the thing case E must NOT be allowed to seize.
//
// THAT UNIQUENESS IS LOAD-BEARING FOR CASE E, and it is not obvious. Case E
// proves rule B refuses a DOTTED name. If some other file's stem also ended in
// '.alpha', rule B would decline on AMBIGUITY first and case E would pass even
// with the bare-only restriction removed -- green, and testing nothing. Do not
// add a second '.alpha' stem here; see the suite header.

interface

implementation

end.
'@

Write-Ascii (Join-Path $work 'Ns.Beta.pas') @'
unit Ns.Beta;

// Stem 'ns.beta'. No file is named 'Beta.pas', so a bare 'uses Beta' can only
// reach this unit through rule B (unit scope names). Target of case C.

interface

implementation

end.
'@

Write-Ascii (Join-Path $work 'Plain.pas') @'
unit Plain;

// An UNDOTTED unit, the shape that already resolved before the fix. Case B
// exists so the repair cannot quietly drop what used to work.

interface

implementation

end.
'@

Write-Ascii (Join-Path $work 'Ns.Gamma.pas') @'
unit Ns.Gamma;

// One of TWO stems whose last segment is 'gamma' (see Zed.Gamma.pas). A bare
// 'uses Gamma' is therefore ambiguous and rule B must DECLINE -- the same
// shape as the real 'controls'/'graphics'/'forms' names that both Vcl.* and
// FMX.* declare, which is exactly why the uniqueness requirement is what keeps
// rule B from crossing frameworks. Case D.

interface

implementation

end.
'@

Write-Ascii (Join-Path $work 'Zed.Gamma.pas') @'
unit Zed.Gamma;

// The second 'gamma' stem. See Ns.Gamma.pas.

interface

implementation

end.
'@

Write-Ascii (Join-Path $work 'Vcl.Widgets9.pas') @'
unit Vcl.Widgets9;

// The ONLY stem carrying the last segment 'widgets9', and it sits in a GUI
// framework namespace. Rule B's uniqueness test alone would therefore hand it
// to a bare `uses Widgets9` -- which is exactly the criterion-5 hazard that
// uniqueness CANNOT cover, because uniqueness is a property of what happens to
// be INDEXED, not a property of the rule. Case G pins the structural refusal.

interface

implementation

end.
'@

Write-Ascii (Join-Path $work 'Vcl.Delta.pas') @'
unit Vcl.Delta;

// Exists so that the GUI-namespace refusal is shown to apply to rule B ONLY:
// 'uses Vcl.Delta' NAMES this file outright and must resolve, GUI or not.
// Rule A is a name equality the unit itself stated; only the rule B INFERENCE
// is refused a GUI target. Case H -- without it, case G would also pass under
// a blanket "never resolve into Vcl.*" that broke criterion 12 for VCL units.
//
// THE SEGMENT 'delta' IS DELIBERATELY UNSHARED. The first cut of this case used
// 'Vcl.Alpha.pas', which collided with Ns.Alpha.pas on the segment 'alpha' and
// silently destroyed case E's RED-ability -- rule B then declined on ambiguity
// rather than on the bare-only restriction case E exists to pin. Any file added
// here must carry a segment no other fixture file carries.

interface

implementation

end.
'@

Write-Ascii (Join-Path $work 'Consumer.pas') @'
unit Consumer;

interface

uses
  Ns.Alpha,      // A: dotted, exact stem match      -> Ns.Alpha.pas
  Plain,         // B: bare, exact stem match        -> Plain.pas
  Beta,          // C: bare, unique last segment     -> Ns.Beta.pas
  Gamma,         // D: bare, TWO stems carry it      -> must stay NULL
  Zed.Alpha,     // E: dotted, no such stem          -> must stay NULL
  NoSuchUnit9,   // F: nothing of the sort indexed   -> must stay NULL
  Widgets9,      // G: bare, unique -- but GUI stem  -> must stay NULL
  Vcl.Delta;     // H: dotted exact, GUI stem        -> Vcl.Delta.pas (rule A)

implementation

end.
'@

$db = Join-Path $WorkDir 'uses.sqlite'
Write-Host 'Indexing fixture' -ForegroundColor Cyan
$indexOut = & $Exe index $work --db $db 2>&1
Check 'index exits 0' ($LASTEXITCODE -eq 0) "exit=$LASTEXITCODE; $($indexOut -join ' | ')"

# --- Probe: for one used unit name, what file (if any) did the index resolve? ----
$script:PyUse = Join-Path $WorkDir 'read_use.py'
Write-Ascii $script:PyUse @'
import sqlite3, sys, os
con = sqlite3.connect(f"file:{sys.argv[1]}?mode=ro", uri=True); c = con.cursor()
r = c.execute(
    "SELECT u.unit_name, u.unit_name_norm, u.target_file_id, f.path "
    "FROM unit_uses u "
    "LEFT JOIN files f ON f.id = u.target_file_id "
    "WHERE LOWER(u.unit_name) = LOWER(?) LIMIT 1", (sys.argv[2],)).fetchone()
if r is None:
    print('NOROW')
else:
    print("%s|%s|%s|%s" % (r[0], r[1], 'NULL' if r[2] is None else 'SET',
                           os.path.basename(r[3]) if r[3] else 'NULL'))
con.close()
'@
function Get-Use([string]$Name) { return (python $script:PyUse $db $Name).Trim() }

Write-Host ''
Write-Host 'unit_uses.target_file_id after a fresh index' -ForegroundColor Cyan

$script:AllNames = @('Ns.Alpha','Plain','Beta','Gamma','Zed.Alpha','NoSuchUnit9','Widgets9','Vcl.Delta')

# Fixture sanity: every uses entry produced a row at all.
foreach ($n in $script:AllNames) {
  Check "fixture sanity: Consumer's 'uses $n' produced a unit_uses row" ((Get-Use $n) -ne 'NOROW') "row=$(Get-Use $n)"
}

# --- A. CRITERION 12 ITSELF: a DOTTED uses name resolves to the file it names. ---
$a = Get-Use 'Ns.Alpha'
Check "A: dotted 'uses Ns.Alpha' RESOLVES (criterion 12 -- was NULL for every dotted name)" `
  ($a -like '*|SET|Ns.Alpha.pas') `
  "row=$a -- unit_name_norm is 'alpha' while the file stem is 'ns.alpha'; comparing those two was the bug"

# --- B. Regression guard: a BARE name that exactly matches a stem still works. ---
$b = Get-Use 'Plain'
Check "B: bare 'uses Plain' still resolves to Plain.pas (nothing that worked was lost)" `
  ($b -like '*|SET|Plain.pas') "row=$b"

# --- C. Unit scope names, the only direction Delphi resolves them. ---------------
$c = Get-Use 'Beta'
Check "C: bare 'uses Beta' resolves to Ns.Beta.pas via its UNIQUE last segment" `
  ($c -like '*|SET|Ns.Beta.pas') "row=$c"

# --- D. Two stems share the segment -- decline, do not pick one. -----------------
$d = Get-Use 'Gamma'
Check "D: bare 'uses Gamma' stays NULL -- 'gamma' is carried by TWO stems (declining is the point)" `
  ($d -like '*|NULL|NULL') `
  "row=$d -- picking either Ns.Gamma or Zed.Gamma here is exactly the guess that would let a legacy unit cross into the wrong namespace"

# --- E. A DOTTED name must never fall back to another namespace's file. ----------
$e = Get-Use 'Zed.Alpha'
Check "E: dotted 'uses Zed.Alpha' stays NULL -- it must NOT seize Ns.Alpha.pas" `
  ($e -like '*|NULL|NULL') `
  "row=$e -- 'alpha' IS a unique segment, so only the bare-only restriction on rule B stops this; the pre-fix code made exactly this mistake on the real library"

# --- F. Nothing indexed by that name at all. -------------------------------------
$f = Get-Use 'NoSuchUnit9'
Check "F: 'uses NoSuchUnit9' stays NULL (no candidate file exists)" ($f -like '*|NULL|NULL') "row=$f"

# --- G. CRITERION 5, STRUCTURALLY: rule B must never infer a GUI-namespaced -------
#        target, even when it is the UNIQUE holder of the segment. Uniqueness is
#        a property of what happens to be indexed; this must be a property of the
#        rule. Here Vcl.Widgets9.pas is the only 'widgets9' stem in the tree, so
#        uniqueness alone WOULD hand it over.
$g = Get-Use 'Widgets9'
Check "G: bare 'uses Widgets9' stays NULL -- rule B never infers a GUI-namespace target (criterion 5)" `
  ($g -like '*|NULL|NULL') `
  "row=$g -- Vcl.Widgets9.pas is the UNIQUE 'widgets9' stem, so the uniqueness test passes and only the IsGuiFrameworkPrefix refusal stops it; without it, an index carrying FMX.Types.pas but not System.Types.pas would give a legacy VCL unit FireMonkey types"

# --- H. ...and that refusal applies to rule B ONLY. Rule A is a name equality -----
#        the unit stated outright, so a DOTTED uses naming a Vcl.* file must
#        still resolve -- otherwise criterion 12 would be broken for all of VCL.
$h = Get-Use 'Vcl.Delta'
Check "H: dotted 'uses Vcl.Delta' RESOLVES -- the GUI refusal binds rule B, never rule A" `
  ($h -like '*|SET|Vcl.Delta.pas') `
  "row=$h -- if this is NULL the guard was applied too broadly and criterion 12 is broken for every Vcl.*/FMX.* unit"

# --- Idempotency: re-running the resolve pass must not change any answer. ---------
Write-Host ''
Write-Host 'idempotency: a second index pass over the same tree' -ForegroundColor Cyan
$before = @($script:AllNames | ForEach-Object { Get-Use $_ })
$null = & $Exe index $work --db $db 2>&1
$after  = @($script:AllNames | ForEach-Object { Get-Use $_ })
Check "re-indexing leaves every target_file_id unchanged" (($before -join ';') -eq ($after -join ';')) `
  "before=$($before -join ' ; ') after=$($after -join ' ; ')"

# --- Finding 4: the pass RECOMPUTES, so it can REPAIR a wrong value. A row -------
#     poisoned behind the indexer's back (simulating the 122 measured wrong
#     dotted targets left by the old rule in a file that is never re-parsed)
#     must be corrected by the next pass, not preserved because it is non-NULL.
Write-Host ''
Write-Host 'repair: a pre-existing WRONG target_file_id is corrected, not kept' -ForegroundColor Cyan
$script:PyPoison = Join-Path $WorkDir 'poison.py'
Write-Ascii $script:PyPoison @'
import sqlite3, sys
con = sqlite3.connect(sys.argv[1]); c = con.cursor()
# point 'uses Ns.Alpha' at the WRONG file, and invent a target for a name that
# must have none -- exactly the two shapes the old fill-only pass could not fix.
wrong = c.execute("SELECT id FROM files WHERE path LIKE '%Plain.pas'").fetchone()[0]
c.execute("UPDATE unit_uses SET target_file_id=? WHERE LOWER(unit_name)='ns.alpha'", (wrong,))
c.execute("UPDATE unit_uses SET target_file_id=? WHERE LOWER(unit_name)='gamma'", (wrong,))
con.commit(); con.close()
print('poisoned')
'@
$null = python $script:PyPoison $db
Check "fixture sanity: the poison took (Ns.Alpha now points at Plain.pas)" ((Get-Use 'Ns.Alpha') -like '*|SET|Plain.pas') "row=$(Get-Use 'Ns.Alpha')"
Check "fixture sanity: the poison took (Gamma now has a target at all)"    ((Get-Use 'Gamma')    -like '*|SET|Plain.pas') "row=$(Get-Use 'Gamma')"
$null = & $Exe index $work --db $db 2>&1
$r1 = Get-Use 'Ns.Alpha'
$r2 = Get-Use 'Gamma'
Check "repair: a WRONG target is corrected by the next pass" ($r1 -like '*|SET|Ns.Alpha.pas') `
  "row=$r1 -- RED if the pass only fills NULL rows; the 122 measured wrong dotted targets would then survive this fix forever"
Check "repair: a target that should not exist is cleared back to NULL" ($r2 -like '*|NULL|NULL') "row=$r2"

Write-Host ''
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
