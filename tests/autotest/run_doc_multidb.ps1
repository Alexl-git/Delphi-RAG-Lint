<#
  run_doc_multidb.ps1 -- AutoDoc multi-DB (Task 6): a symbol's callers that live
  in a SECOND index db appear in the generated doc-comment when `document --unit`
  is given more than one --db.

  Fixture: lib\uLib.pas declares `function Compute(const A: Integer): Integer;`
  (interface + impl). app\uApp.pas `uses uLib;` and calls Compute(21) from a
  procedure Run -- a caller of Compute, indexed into a SEPARATE db.

  `document --unit` opens its PRIMARY store from the LAST --db flag (CLI.pas
  ParseArgs: every --db appends to DbPaths, and DbPath is left holding the last
  one), and treats every OTHER resolved --db as an extra store (OpenExtraStores /
  ResolveConsumerDbs). So the target unit's own db must be passed LAST; any
  earlier --db is an extra store searched (name-only) for callers/used-in.

  SCENARIO A (single-db): document a FRESH copy of uLib.pas against ONLY its own
  db (appA.sqlite). No caller db is passed -> the applied file must NOT mention
  uApp anywhere.

  SCENARIO B (multi-db): document a DIFFERENT fresh copy of uLib.pas, passing
  BOTH the caller db (app.sqlite, --db #1) and its own db LAST (appB.sqlite,
  --db #2, so it is the primary AArgs.DbPath). The name-based Called-from bucket
  then searches app.sqlite too and should surface `Called from: uApp.Run` in the
  merged doc-comment written by --apply.

  --apply is IDEMPOTENT: once a unit carries the managed drag-lint:auto block, a
  second apply is a no-op. So EACH scenario applies to its OWN fresh copy of
  uLib.pas (applyA\uLib.pas, applyB\uLib.pas) -- never re-applies to an
  already-documented file.

  Run from a NEUTRAL CWD (defaults to $env:TEMP\drag-lint-doc-multidb).
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\drag-lint-doc-multidb"
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

if (Test-Path $WorkDir) { Remove-Item -Recurse -Force $WorkDir }
New-Item -ItemType Directory $WorkDir | Out-Null

# --- Fixture: lib (Compute) + app (a caller of Compute) ---
$libDir = Join-Path $WorkDir 'lib'
New-Item -ItemType Directory $libDir | Out-Null
$libSrc = @'
unit uLib;

interface

function Compute(const A: Integer): Integer;

implementation

function Compute(const A: Integer): Integer;
begin
  Result := A * 2;
end;

end.
'@
Set-Content (Join-Path $libDir 'uLib.pas') -Value $libSrc -Encoding ascii -NoNewline

$appDir = Join-Path $WorkDir 'app'
New-Item -ItemType Directory $appDir | Out-Null
$appSrc = @'
unit uApp;

interface

uses uLib;

procedure Run;

implementation

procedure Run;
begin
  Compute(21);
end;

end.
'@
Set-Content (Join-Path $appDir 'uApp.pas') -Value $appSrc -Encoding ascii -NoNewline

$libDb = Join-Path $WorkDir 'lib.sqlite'
$appDb = Join-Path $WorkDir 'app.sqlite'
& $Exe index $libDir --db $libDb | Out-Null
& $Exe index $appDir --db $appDb | Out-Null
Check 'lib db built' (Test-Path $libDb)
Check 'app db built' (Test-Path $appDb)

# --- SCENARIO A: single-db. Fresh copy of uLib.pas, indexed into its OWN db,
#     documented with ONLY that db passed. No caller db in play -> no uApp. ---
$applyADir = Join-Path $WorkDir 'applyA'
New-Item -ItemType Directory $applyADir | Out-Null
$applyAFile = Join-Path $applyADir 'uLib.pas'
Copy-Item (Join-Path $libDir 'uLib.pas') $applyAFile -Force
$appADb = Join-Path $WorkDir 'appA.sqlite'
& $Exe index $applyADir --db $appADb | Out-Null
Check 'appA db built' (Test-Path $appADb)

& $Exe document --unit $applyAFile --db $appADb --apply --no-backup | Out-Null
$ecA = $LASTEXITCODE
Check 'scenario A: apply exit 0' ($ecA -eq 0)

$srcA = [IO.File]::ReadAllText($applyAFile)
Check 'scenario A: single-db has no uApp caller' (-not ($srcA -match 'uApp')) $srcA

# --- SCENARIO B: multi-db. A DIFFERENT fresh copy of uLib.pas, indexed into its
#     OWN db (appB.sqlite), documented with the caller db (app.sqlite) passed
#     FIRST and its own db (appB.sqlite) passed LAST -- LAST is the primary
#     AArgs.DbPath per ParseArgs, so appB.sqlite (which has the target unit) is
#     primary and app.sqlite (which has the caller uApp.Run) is the extra store. ---
$applyBDir = Join-Path $WorkDir 'applyB'
New-Item -ItemType Directory $applyBDir | Out-Null
$applyBFile = Join-Path $applyBDir 'uLib.pas'
Copy-Item (Join-Path $libDir 'uLib.pas') $applyBFile -Force
$appBDb = Join-Path $WorkDir 'appB.sqlite'
& $Exe index $applyBDir --db $appBDb | Out-Null
Check 'appB db built' (Test-Path $appBDb)

& $Exe document --unit $applyBFile --db $appDb --db $appBDb --apply --no-backup | Out-Null
$ecB = $LASTEXITCODE
Check 'scenario B: apply exit 0' ($ecB -eq 0)

$srcB = [IO.File]::ReadAllText($applyBFile)
Check 'scenario B: has a Called from: line' ($srcB -match 'Called from:') $srcB
Check 'scenario B: multi-db surfaces uApp caller' ($srcB -match 'Called from:[^\r\n]*uApp') $srcB

Write-Host ''
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
