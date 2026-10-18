<#
  run_fresh_db_notes.ps1 -- a NEW database gets no stale-DB warnings (V-C, 1.31.5).

  WHAT WENT WRONG (clean VM, 2026-10-18): `index <Delphi 5 Source\Vcl> --db
  <new file>` (127 files) printed four notes that are false or alarming on a
  database this very run created:
    1. "This DB carries no resolver stamp (-> ...): re-deriving every edge."
    2. "NOTE: this database records no scan_type (it predates the stamp) ..."
    3. "... whole database because this run rewrote more than one file in three
        (1 changed, limit 0)" -- 127 files were NEW, not 1 changed.
    4. "... this is the expensive shape (~37 min on a 2 GB index) -- it is
        running, not hung" on a corpus that resolves in seconds.

  THE CASES
    A  NEW DB          -> none of the four; the reason names the new database
                          and the real file count.
    B  OLD DB (stamp + scan_type rows removed, files already indexed)
                       -> notes 1 and 2 STILL appear (positive control: the
                          fix must not silence the real warnings).
    C  OLD DB, every file rewritten -> the one-in-three reason still appears,
                          with real counts (new vs changed).
    D  the slow-pass line is gated by size, not removed: with the threshold
       lowered by DRAGLINT_WHOLEDB_SLOW_FILES=1 it prints again (positive
       control for note 4).

  Needs Python (stdlib sqlite3) for the write in case B -- the `sql` verb is
  read-only by design. Run from a NEUTRAL CWD (C:\TEMP), pwsh 7.
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\draglint_fresh_db_notes_$PID"
)
try {
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

$py = 'C:\Python314\python.exe'
if (-not (Test-Path $py)) {
  Write-Host '[SKIP] run_fresh_db_notes: Python not found at C:\Python314' -ForegroundColor Yellow
  exit 0
}

if (Test-Path $WorkDir) { [System.IO.Directory]::Delete($WorkDir, $true) }
New-Item -ItemType Directory $WorkDir | Out-Null
$src = Join-Path $WorkDir 'src'
New-Item -ItemType Directory $src | Out-Null

function Emit([string]$name, [string]$text) {
  [System.IO.File]::WriteAllText((Join-Path $src $name),
    (($text -replace "`r`n", "`n") -replace "`n", "`r`n"), [System.Text.Encoding]::ASCII)
}
function Emit-All([string]$extra) {
  Emit 'uCallee.pas' @"
unit uCallee;
interface
procedure Target;
implementation
procedure Target;
begin
$extra
end;
end.
"@
  Emit 'uCaller.pas' @"
unit uCaller;
interface
uses uCallee;
procedure Go;
implementation
procedure Go;
begin
  Target;
$extra
end;
end.
"@
  Emit 'uThird.pas' @"
unit uThird;
interface
uses uCaller;
procedure Run;
implementation
procedure Run;
begin
  Go;
$extra
end;
end.
"@
}
Emit-All ''

$db = Join-Path $WorkDir 'fresh.sqlite'

$pyDrop = Join-Path $WorkDir 'drop.py'
[System.IO.File]::WriteAllText($pyDrop, @"
import sqlite3, sys
c = sqlite3.connect(sys.argv[1])
c.execute("DELETE FROM schema_meta WHERE key IN ('resolver_fingerprint','scan_type')")
c.commit(); c.close()
"@, [System.Text.Encoding]::ASCII)

$rxStamp  = 'no resolver stamp'
$rxScan   = 'records no scan_type'
$rxShare  = 'rewrote more than one file in three'
$rxLimit0 = 'limit 0\)'
$rxSlow   = 'expensive shape'

Push-Location C:\TEMP
try {
  # ---------------------------------------------------------------- CASE A ---
  Write-Host ''
  Write-Host 'CASE A -- a NEW database prints none of the four notes' -ForegroundColor Cyan
  Check 'the DB does not exist before the run' (-not (Test-Path $db)) $db
  $a = & $Exe index $src --db $db 2>&1 | Out-String
  Check 'the fixture indexed' (Test-Path $db) $db
  Check 'A1 no "no resolver stamp" note'   (-not ($a -match $rxStamp)) ''
  Check 'A2 no "records no scan_type" note' (-not ($a -match $rxScan)) ''
  Check 'A3 no one-in-three reason / "limit 0"' (-not ($a -match $rxShare -or $a -match $rxLimit0)) ''
  Check 'A4 no "expensive shape" line on a 3-file DB' (-not ($a -match $rxSlow)) ''
  Check 'A5 the whole-DB reason names the new database' `
    ($a -match 'whole database because the database held no files before this run') `
    $(($a -split "`n" | Where-Object { $_ -match 'whole database because' }) -join ' ')
  Check 'A6 and gives the real file count (3 new)' ($a -match '\b3 file\(s\), all new') ''
  Check 'A7 the edges were still derived (calls pass ran)' ($a -match 'starting WHOLE-DB pass') ''

  # ---------------------------------------------------------------- CASE B ---
  Write-Host ''
  Write-Host 'CASE B -- an OLD database (stamps removed) still gets notes 1 and 2' -ForegroundColor Cyan
  & $py $pyDrop $db 2>&1 | Out-Null
  $env:DRAGLINT_WHOLEDB_SLOW_FILES = '1'
  try { $b = & $Exe index $src --db $db 2>&1 | Out-String }
  finally { [Environment]::SetEnvironmentVariable('DRAGLINT_WHOLEDB_SLOW_FILES', $null) }
  Check 'B1 "no resolver stamp" note appears'   ($b -match $rxStamp) ''
  Check 'B2 "records no scan_type" note appears' ($b -match $rxScan) ''

  # ---------------------------------------------------------------- CASE D ---
  Check 'D1 slow-pass line returns when the threshold is lowered' ($b -match $rxSlow) `
    'RED means note 4 was deleted rather than gated'

  # ---------------------------------------------------------------- CASE C ---
  Write-Host ''
  Write-Host 'CASE C -- an OLD database with every file rewritten keeps the share reason' -ForegroundColor Cyan
  Start-Sleep -Milliseconds 1100
  Emit-All '  ;'
  $c = & $Exe index $src --db $db 2>&1 | Out-String
  $why = ($c -split "`n" | Where-Object { $_ -match 'whole database because' }) -join ' '
  Check 'C1 the one-in-three reason appears' ($c -match $rxShare) $why
  Check 'C2 with real counts (3 written: 0 new, 3 changed)' ($c -match '3 written: 0 new, 3 changed') $why
  Check 'C3 and not the new-database reason' (-not ($c -match 'held no files before this run')) ''
  Check 'C4 no "expensive shape" line at default threshold' (-not ($c -match $rxSlow)) ''
}
finally { Pop-Location }

Write-Host ''
if ($script:Failed) { Write-Host 'run_fresh_db_notes: FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'run_fresh_db_notes: PASS' -ForegroundColor Green
exit 0
}
catch {
  Write-Host "run_fresh_db_notes: ERROR $_" -ForegroundColor Red
  exit 2
}
