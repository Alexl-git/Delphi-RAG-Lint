<#
  run_rename_missing_db_exit.ps1 -- `rename` reports a missing database with
  exit 2 on BOTH of its paths.

  THE DEFECT (BACKLOG-TRIAGE-2026-09-28 TH-4). The legacy `rename --qname ...
  --to ...` path returned 1 for a missing --db, while every other verb's
  missing-DB check -- including rename's own `--kind symbol` path -- returns 2.
  Exit 1 is this CLI's "ran, and found something / failed" code, so a script
  could not tell "no database" from a rename that ran.

  CASES
    T1 legacy --qname path, missing DB  -> exit 2, and says "Database not found"
    C1 --kind symbol path, missing DB   -> exit 2 (the control: the sibling path
       the legacy one now matches)

  Run from any CWD, pwsh 7. Touches no index: the DB path is deliberately absent.
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe",
  [string]$WorkDir = "C:\TEMP\draglint_rename_missing_db_$PID"
)
try {
$ErrorActionPreference = 'Stop'
$script:fail = $false
function Check($n,$ok,$d){
  Write-Host ("[{0}] {1}" -f (@('FAIL','PASS')[[int][bool]$ok]),$n) -ForegroundColor (@('Red','Green')[[int][bool]$ok])
  if(-not $ok){ if($d){ Write-Host "      $d" -ForegroundColor DarkGray }; $script:fail=$true }
}
$exePath = (Resolve-Path $Exe).Path
if (Test-Path $WorkDir) { [IO.Directory]::Delete($WorkDir, $true) }
New-Item -ItemType Directory -Path $WorkDir | Out-Null
$missing = Join-Path $WorkDir 'no-such.sqlite'

$o = ((& $exePath rename --qname U.TFoo.Bar --to Baz --db $missing 2>&1 | ForEach-Object { "$_" }) -join "`n")
$rc = $LASTEXITCODE
Check "T1 legacy --qname path: a missing DB exits 2 (got $rc)" ($rc -eq 2) $o
Check 'T1b and says Database not found' ($o -match 'Database not found') $o
Check 'V the missing DB was not created' (-not (Test-Path $missing)) $missing

$o = ((& $exePath rename --kind symbol --name U.TFoo.Bar --to Baz --db $missing 2>&1 | ForEach-Object { "$_" }) -join "`n")
$rc = $LASTEXITCODE
Check "C1 CONTROL --kind symbol path: a missing DB exits 2 (got $rc)" ($rc -eq 2) $o

Write-Host ''
if ($script:fail) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'PASS' -ForegroundColor Green; exit 0
} finally {
  # D23: this run's scratch is $PID-suffixed; remove it so per-run folders do not pile up in TEMP.
  foreach ($d23 in @("C:\TEMP\draglint_rename_missing_db_$PID")) { if (Test-Path -LiteralPath $d23) { Remove-Item -LiteralPath $d23 -Recurse -Force -ErrorAction SilentlyContinue } }
}
