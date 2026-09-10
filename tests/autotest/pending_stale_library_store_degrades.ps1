<#
  pending_stale_library_store_degrades.ps1 -- a lint run whose LIBRARY index is at
  an older schema must DEGRADE with a warning, never crash.

  NAMED pending_* ON PURPOSE, so the battery's run_*.ps1 discovery does NOT pick
  it up. This guard is DRAFTED BUT NOT VALIDATED: as written it would pass
  VACUOUSLY, because ResolveLibraryDb ignores --config -- it loads the manifest
  from the ENGINE's own directory and the CWD, and accepts only a resolved path
  whose file name starts with 'library-'. So the scratch manifest below redirects
  nothing, the library store is never opened, and the stale branch this exists to
  cover is never reached.
  RENAME TO run_* ONLY when it has been shown RED against the pre-fix engine
  (snapshotted read-only at <scratch>\engine-preA, extractor 1.14.0-alpha,
  sha256 C4751074...). See docs\INBOX-stale-library-store-crashes-lint.md for the
  two workable routes and the trap in each.

  THE BUG THIS PINS (2026-09-09, found by the SCHEMA_VERSION 21 -> 22 bump).
  TSQLiteSymbolStore.Create calls PrepareStatements only when IsSchemaCurrent.
  The lint entry points open the platform library index with a deliberate
  NEVER-MIGRATE policy -- correct, since migrating someone else's multi-gigabyte
  index as a side effect of linting would take a write lock. But Create does not
  RAISE on a stale schema: it returns a store whose every prepared FQ* query is
  nil. The call sites' `except -> nil; warn` therefore never fired, and the first
  read dereferenced a nil TFDQuery -- an access violation inside
  Data.DB.TDataSet.GetActive, surfacing as `lint-all: skip <file>` with 0
  findings and no mention of the library index.

  WHY IT HAD NEVER FIRED, which is the whole reason this guard exists: the
  library index was always CURRENT, so the stale branch was unreachable. Every
  schema bump makes it reachable for exactly as long as the re-parse takes --
  hours -- and during that window every lint run crashed. The next bump will
  reopen that window, and this guard is what stands in it.

  METHOD. Build a normal index, then hand-edit its stored schema_version DOWN and
  point a lint run at it as the library store. That is a real stale index, not a
  mock: the file is a genuine database that a previous engine could have written.

  CASES
    A  lint-all against a project DB whose LIBRARY index is stale exits without
       an access violation, and still reports findings.
    B  it says so -- the warning names the library index and its schema. Silence
       would leave a user wondering why ancestry resolution got weaker.
    C  CONTROL: with a CURRENT library index the same run reports findings and
       emits NO such warning, so case B cannot pass by always warning.
    D  CONTROL: the stale run's finding count matches the current run's for
       project-local rules -- degrading must cost only library-dependent
       resolution, not findings generally.
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\drag-lint-stale-libstore"
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
  $dir = Split-Path -Parent $Path
  if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Force $dir | Out-Null }
  [System.IO.File]::WriteAllText($Path, $norm, [System.Text.Encoding]::ASCII)
}

# --- a project fixture with something for the linter to find -----------------
$proj = Join-Path $WorkDir 'proj'
Write-Ascii (Join-Path $proj 'uThing.pas') @'
unit uThing;

interface

type
  TThing = class(TObject)
  public
    procedure DoIt;
  end;

implementation

procedure TThing.DoIt;
begin
end;

end.
'@

# --- a separate "library" index ----------------------------------------------
$lib = Join-Path $WorkDir 'lib'
Write-Ascii (Join-Path $lib 'uLibKit.pas') @'
unit uLibKit;

interface

type
  TLibBase = class(TObject)
  end;

implementation

end.
'@

$projDb = Join-Path $WorkDir 'proj.sqlite'
$libDb  = Join-Path $WorkDir 'lib.sqlite'
$null = & $Exe index $proj --db $projDb 2>$null
Check 'project index exits 0' ($LASTEXITCODE -eq 0) "exit=$LASTEXITCODE"
$null = & $Exe index $lib --db $libDb 2>$null
Check 'library index exits 0' ($LASTEXITCODE -eq 0) "exit=$LASTEXITCODE"

# The manifest is what makes the engine open a library store at all.
function New-Manifest([string]$LibPath) {
  $m = @{
    settings = @{ defaultPlatform = 'Win32' }
    indexes  = @{ sections = @(
      @{ name = 'StaleLibGuard'; include = @($lib); db = $LibPath; platforms = @('Win32') }
    ) }
  }
  $p = Join-Path $WorkDir 'drag-lint.json'
  [System.IO.File]::WriteAllText($p, ($m | ConvertTo-Json -Depth 8), (New-Object System.Text.ASCIIEncoding))
  return $p
}

function Run-Lint([string]$Config) {
  $out = & $Exe lint-all --db $projDb --config $Config 2>&1
  return ,@($out)
}

function Count-Findings($lines) {
  return @($lines | Where-Object { $_ -match '\[(error|warning|info|hint)\]' }).Count
}

# --- CONTROL first: a CURRENT library index ----------------------------------
Write-Host ''
Write-Host 'CONTROL: a CURRENT library index -- findings, no stale warning' -ForegroundColor Cyan
$cfg = New-Manifest $libDb
$okRun   = Run-Lint $cfg
$okCount = Count-Findings $okRun
$okWarn  = @($okRun | Where-Object { $_ -match 'is schema v\d+, this build needs v\d+' }).Count
Check 'current library: no access violation' (@($okRun | Where-Object { $_ -match 'AccessViolation' }).Count -eq 0)
Check 'current library: findings are reported' ($okCount -ge 1) "findings=$okCount"
Check 'current library: NO stale-schema warning (so the warning cannot be unconditional)' ($okWarn -eq 0) "warnings=$okWarn"

# --- now make the library index stale ----------------------------------------
Write-Host ''
Write-Host 'STALE: hand-edit the library index schema_version DOWN' -ForegroundColor Cyan
$sqlite = Join-Path (Split-Path $Exe -Parent) 'sqlite3.exe'
$lowered = $false
try {
  # No sqlite3.exe dependency: the engine's own sql verb can write.
  $null = & $Exe sql --query "UPDATE meta SET value='1' WHERE key='schema_version'" --db $libDb 2>&1
  $chk = (& $Exe sql --query "SELECT value FROM meta WHERE key='schema_version'" --db $libDb --json 2>$null) -join "`n"
  $lowered = $chk -match '"1"|: *1\b'
} catch { $lowered = $false }
Check 'the library index really is stale now (precondition)' $lowered "if this fails the case below is vacuous, not passing"

if ($lowered) {
  $staleRun   = Run-Lint $cfg
  $staleCount = Count-Findings $staleRun
  $staleWarn  = @($staleRun | Where-Object { $_ -match 'is schema v\d+, this build needs v\d+' }).Count
  $av         = @($staleRun | Where-Object { $_ -match 'AccessViolation' }).Count

  Write-Host ''
  Write-Host 'CASE A/B: degrade, do not crash -- and say so' -ForegroundColor Cyan
  Check 'CASE A: NO access violation' ($av -eq 0) "AV lines=$av"
  Check 'CASE A: findings are still reported' ($staleCount -ge 1) "findings=$staleCount"
  Check 'CASE B: the run WARNS, naming the schema mismatch' ($staleWarn -ge 1) "warnings=$staleWarn"
  Check 'CASE D: project-local findings are unchanged by the degradation' ($staleCount -eq $okCount) "stale=$staleCount current=$okCount"
}

Write-Host ''
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
