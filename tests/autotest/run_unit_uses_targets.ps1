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
  matching FMX.MaskEdit.pas). Overall 41.8% of rows resolved; after, 91.8%.

  THE RULES NOW, in order (first hit wins; no hit leaves the row NULL):
    A. EXACT -- the lowercased used-unit name equals a file's lowercased
       basename stem. A name equality, not an inference. Applies to dotted and
       bare names alike.
    B. UNIT SCOPE NAMES, BARE NAMES ONLY -- a used name with no dot may match a
       DOTTED stem by that stem's last segment ('uses Beta' -> Ns.Beta.pas),
       but only when exactly ONE distinct stem carries that segment. This is
       Delphi's own unit-scope-names resolution, in the only direction Delphi
       performs it, and the uniqueness requirement is what keeps it honest.
    A DOTTED name NEVER falls back to rule B. That direction produced both
    measured wrong-namespace matches, and case E below is its RED-proof.

  EACH CASE IS INDEPENDENTLY RED-ABLE against a specific line of the fix:
    A  dotted exact      -- RED if the norm-vs-stem comparison comes back
    B  bare exact        -- RED if rule A is dropped (also the pre-fix regression guard)
    C  bare -> dotted    -- RED if rule B is dropped
    D  ambiguous segment -- RED if rule B stops requiring a UNIQUE stem
    E  dotted -> other   -- RED if rule B stops being bare-only
    F  no such unit      -- RED if anything resolves a name with no candidate

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

// Stem 'ns.alpha', last segment 'alpha' -- and NO other indexed stem ends in
// '.alpha', so 'alpha' is a UNIQUE segment. Target of case A (by its full
// name) and the thing case E must NOT be allowed to seize.

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

Write-Ascii (Join-Path $work 'Consumer.pas') @'
unit Consumer;

interface

uses
  Ns.Alpha,      // A: dotted, exact stem match      -> Ns.Alpha.pas
  Plain,         // B: bare, exact stem match        -> Plain.pas
  Beta,          // C: bare, unique last segment     -> Ns.Beta.pas
  Gamma,         // D: bare, TWO stems carry it      -> must stay NULL
  Zed.Alpha,     // E: dotted, no such stem          -> must stay NULL
  NoSuchUnit9;   // F: nothing of the sort indexed   -> must stay NULL

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

# Fixture sanity: every uses entry produced a row at all.
foreach ($n in 'Ns.Alpha','Plain','Beta','Gamma','Zed.Alpha','NoSuchUnit9') {
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

# --- Idempotency: re-running the resolve pass must not change any answer. ---------
Write-Host ''
Write-Host 'idempotency: a second index pass over the same tree' -ForegroundColor Cyan
$before = @('Ns.Alpha','Plain','Beta','Gamma','Zed.Alpha','NoSuchUnit9' | ForEach-Object { Get-Use $_ })
$null = & $Exe index $work --db $db 2>&1
$after  = @('Ns.Alpha','Plain','Beta','Gamma','Zed.Alpha','NoSuchUnit9' | ForEach-Object { Get-Use $_ })
Check "re-indexing leaves every target_file_id unchanged" (($before -join ';') -eq ($after -join ';')) `
  "before=$($before -join ' ; ') after=$($after -join ' ; ')"

Write-Host ''
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
