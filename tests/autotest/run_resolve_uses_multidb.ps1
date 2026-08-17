<#
  run_resolve_uses_multidb.ps1 -- resolve-uses reads EVERY --db, and its
  "already in uses" detection works when the target file lives in a DIFFERENT
  index from the symbol.

  THE BUG. DoResolveUses opened AArgs.DbPath -- the LAST --db -- and used that
  one store for everything, while ParseArgs accepted every earlier --db and
  appended it to DbPaths. Same defect find-unit had (fixed in 16456a2), in the
  verb AI-USAGE names as THE way to ask "which unit do I add to my uses clause?".

  IT MATTERS MORE HERE THAN THE ORDER-DEPENDENCE SUGGESTS. The already-imported
  set is built from the --in file's own uses rows, which only exist in the store
  that INDEXES that file. Ask a library-only index and InFileId is 0, the set
  stays EMPTY, and every candidate silently collects the "not already used"
  +1000 bonus -- so a unit the caller ALREADY imports is ranked and suggested as
  a fresh add. That failure looks like a plausible answer rather than an error,
  which is why it survived: the pre-existing fixture (tests\fixtures\
  T_resolve_uses.bat, a .bat that the battery does not run and that points at
  the retired Win32 exe path) puts BOTH units in ONE db, which is exactly the
  configuration where the bug cannot appear.

  WHY THE ASSERTIONS ARE SHAPED THIS WAY.

  * THE POSITIVE CONTROL IS "<already in uses>" ACROSS TWO DATABASES, and it is
    unsatisfiable by any single-store implementation: it needs the LIBRARY store
    (to know ProviderUnit declares MAGIC_CONST) and the PROJECT store (to know
    ConsumerUnit already uses ProviderUnit) in one call. A test that only
    asserted "ProviderUnit is found" would pass with the already-imported set
    still empty -- i.e. with the bug fully present.

  * THE DE-VACUATOR is a second consumer that does NOT import ProviderUnit. It
    must still be offered the suggestion. Without it, a fix that marked
    everything "already used" would turn the assertion above green.

  Usage: pwsh -File tests/autotest/run_resolve_uses_multidb.ps1 [-Exe <path>]
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\drag-lint-resolve-uses-multidb"
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

function Write-Ascii([string]$Path, [string]$Body) {
  $norm = $Body -replace "`r`n", "`n" -replace "`n", "`r`n"
  [System.IO.File]::WriteAllText($Path, $norm, [System.Text.Encoding]::ASCII)
}
function NewDir([string]$Name) {
  $p = Join-Path $WorkDir $Name
  New-Item -ItemType Directory $p | Out-Null
  return $p
}

# --- The LIBRARY side: declares the symbol, knows nothing about any consumer. ----
$libSrc = NewDir 'libsrc'
Write-Ascii (Join-Path $libSrc 'ProviderUnit.pas') @'
unit ProviderUnit;

interface

const
  MAGIC_CONST = 42;

implementation

end.
'@

# --- The PROJECT side: two consumers, one importing ProviderUnit and one not. ----
$projSrc = NewDir 'projsrc'
Write-Ascii (Join-Path $projSrc 'ConsumerUnit.pas') @'
unit ConsumerUnit;

interface

uses ProviderUnit;

implementation

end.
'@
Write-Ascii (Join-Path $projSrc 'StrangerUnit.pas') @'
unit StrangerUnit;

interface

implementation

end.
'@

$libDb  = Join-Path $WorkDir 'library-Test.sqlite'
$projDb = Join-Path $WorkDir 'proj.sqlite'

Write-Host 'Indexing fixtures' -ForegroundColor Cyan
foreach ($pair in @(@($libSrc, $libDb), @($projSrc, $projDb))) {
  $out = & $Exe index $pair[0] --db $pair[1] --quiet 2>&1
  Check ("index {0}" -f (Split-Path $pair[1] -Leaf)) ($LASTEXITCODE -eq 0) "exit=$LASTEXITCODE; $($out -join ' | ')"
}

$consumer = Join-Path $projSrc 'ConsumerUnit.pas'
$stranger = Join-Path $projSrc 'StrangerUnit.pas'

function ResolveUses([string]$InFile, [string[]]$Dbs) {
  $dbArgs = @()
  foreach ($d in $Dbs) { $dbArgs += '--db'; $dbArgs += $d }
  $out = @(& $Exe resolve-uses --name MAGIC_CONST --in $InFile @dbArgs --quiet 2>&1) | ForEach-Object { "$_" }
  $script:LastExit = $LASTEXITCODE
  return ($out -join "`n")
}

# --- 1. The order that used to lose the library entirely. ----------------------------
Write-Host ''
Write-Host 'library FIRST, project second -- the documented order' -ForegroundColor Cyan

$r = ResolveUses $consumer @($libDb, $projDb)
Check 'ASSERT: ProviderUnit is found at all' (($r -match 'ProviderUnit') -and ($script:LastExit -eq 0)) `
  "exit=$script:LastExit; $r -- with only the LAST --db read, the project index has no MAGIC_CONST and this reported nothing"

# --- 2. THE POSITIVE CONTROL. Needs BOTH stores in one call. -------------------------
Write-Host ''
Write-Host 'positive control -- "already in uses" spans two databases' -ForegroundColor Cyan

Check 'ASSERT: ProviderUnit is reported as ALREADY in ConsumerUnit''s uses' `
  ($r -match 'already in uses') `
  "$r -- the LIBRARY store declares MAGIC_CONST, the PROJECT store knows ConsumerUnit uses ProviderUnit; neither alone can say this"
Check 'ASSERT: and it is therefore NOT suggested as an add' `
  ($r -notmatch 'Suggestion:') `
  "$r -- suggesting a unit the caller already imports is the user-visible symptom of the empty already-imported set"

# --- 3. THE DE-VACUATOR. A consumer that does NOT import it must still be told. -------
Write-Host ''
Write-Host 'de-vacuator -- a file that does NOT import ProviderUnit still gets the suggestion' -ForegroundColor Cyan

$rStranger = ResolveUses $stranger @($libDb, $projDb)
Check 'ASSERT: StrangerUnit IS offered the suggestion' `
  (($rStranger -match 'Suggestion:') -and ($rStranger -match 'ProviderUnit')) `
  "$rStranger -- if this fails, everything is being marked already-used and the check above proves nothing"
Check 'ASSERT: and StrangerUnit is NOT told it already uses it' `
  ($rStranger -notmatch 'already in uses') "$rStranger"

# --- 4. Order independence. ----------------------------------------------------------
Write-Host ''
Write-Host 'the two --db orders must agree' -ForegroundColor Cyan

$rSwap = ResolveUses $consumer @($projDb, $libDb)
Check 'ASSERT: swapping --db order gives the same answer' ($rSwap -eq $r) "swapped=$rSwap`n---`noriginal=$r"

# --- 5. Control. ---------------------------------------------------------------------
Write-Host ''
Write-Host 'control' -ForegroundColor Cyan

$dbArgs = @('--db', $libDb, '--db', $projDb)
$rNone = @(& $Exe resolve-uses --name ZZZ_NoSuchSymbol @dbArgs --quiet 2>&1) | ForEach-Object { "$_" }
$noneExit = $LASTEXITCODE
Check 'control: an absent symbol still reports "No unit" and exits 1' `
  ((($rNone -join "`n") -match 'No unit') -and ($noneExit -eq 1)) "exit=$noneExit; $($rNone -join "`n")"

Write-Host ''
if ($script:Failed) { Write-Host 'RESULT: FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'RESULT: PASS' -ForegroundColor Green
exit 0
