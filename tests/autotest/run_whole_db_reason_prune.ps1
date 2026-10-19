<#
  run_whole_db_reason_prune.ps1 -- the whole-DB share reason does not call a
  PRUNED file "changed" (1.31.6 lane E, item 2).

  THE DEFECT (lane 2 follow-up, 1.31.5): NoteScopeRemoval serves both a
  rewrite (OpenFileTx) and a prune/eviction (DeleteFilesByIds) and counted
  every call as a write, so a run that only deleted files reported
  "(4 written: 0 new, 4 changed ...)" -- four files that were never written.

  THE CASES (nine units; the share limit is 9 div 3 = 3)
    R1  delete four files, change none -> the reason names 4 removed and
        0 written; it does not say "4 changed" -- RED before the fix.
    R2  POSITIVE CONTROL, mixed: rewrite one and delete three -> 1 written,
        1 changed, 3 removed (the rewrite is still counted as changed).
    R3  POSITIVE CONTROL, rewrites only: the pre-existing wording
        "rewrote more than one file in three (N written: 0 new, N changed"
        is unchanged (run_fresh_db_notes C2 pins the same text).
  Run from a NEUTRAL CWD (C:\TEMP), pwsh 7.
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\draglint_whole_db_reason_prune_$PID"
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

if (Test-Path $WorkDir) { [System.IO.Directory]::Delete($WorkDir, $true) }
New-Item -ItemType Directory $WorkDir | Out-Null
$src = Join-Path $WorkDir 'src'

function Emit-Unit([int]$i, [string]$extra = '') {
  $text = @"
unit uP$i;
interface
procedure P$i;
implementation
procedure P$i;
begin
$extra
end;
end.
"@
  [System.IO.File]::WriteAllText((Join-Path $src "uP$i.pas"),
    (($text -replace "`r`n", "`n") -replace "`n", "`r`n"), [System.Text.Encoding]::ASCII)
}
function Reset-Fixture([string]$db) {
  if (Test-Path $src) { [System.IO.Directory]::Delete($src, $true) }
  New-Item -ItemType Directory $src | Out-Null
  1..9 | ForEach-Object { Emit-Unit $_ }
  $null = & $Exe index $src --db $db 2>&1 | Out-String
}
function Get-Why([string]$out) { (($out -split "`n") | Where-Object { $_ -match 'whole database because' }) -join ' ' }

Push-Location C:\TEMP
try {
  Write-Host ''
  Write-Host 'R1 -- four files pruned, none written' -ForegroundColor Cyan
  $db1 = Join-Path $WorkDir 'r1.sqlite'
  Reset-Fixture $db1
  6..9 | ForEach-Object { [System.IO.File]::Delete((Join-Path $src "uP$_.pas")) }
  $o1 = & $Exe index $src --db $db1 2>&1 | Out-String
  $w1 = Get-Why $o1
  Check 'R1a the prune happened (4 files removed)' ($o1 -match 'removed 4 file') ''
  Check 'R1b the share reason fired' ($w1 -match 'more than one file in three') $w1
  Check 'R1c it names 4 removed' ($w1 -match '\b4 removed') $w1
  Check 'R1d it does not count them as written/changed' (($w1 -match '\b0 written: 0 new, 0 changed') -and -not ($w1 -match '\b4 changed')) $w1

  Write-Host ''
  Write-Host 'R2 -- one file rewritten, three pruned (positive control)' -ForegroundColor Cyan
  $db2 = Join-Path $WorkDir 'r2.sqlite'
  Reset-Fixture $db2
  Start-Sleep -Milliseconds 1100
  Emit-Unit 1 '  ;'
  7..9 | ForEach-Object { [System.IO.File]::Delete((Join-Path $src "uP$_.pas")) }
  $w2 = Get-Why (& $Exe index $src --db $db2 2>&1 | Out-String)
  Check 'R2 1 written: 0 new, 1 changed; 3 removed' ($w2 -match '\b1 written: 0 new, 1 changed; 3 removed') $w2

  Write-Host ''
  Write-Host 'R3 -- rewrites only keep the old wording (positive control)' -ForegroundColor Cyan
  $db3 = Join-Path $WorkDir 'r3.sqlite'
  Reset-Fixture $db3
  Start-Sleep -Milliseconds 1100
  1..4 | ForEach-Object { Emit-Unit $_ '  ;' }
  $w3 = Get-Why (& $Exe index $src --db $db3 2>&1 | Out-String)
  Check 'R3 rewrote more than one file in three (4 written: 0 new, 4 changed' `
    (($w3 -match 'rewrote more than one file in three \(4 written: 0 new, 4 changed, of 9') -and -not ($w3 -match 'removed')) $w3
}
finally { Pop-Location }

Write-Host ''
if ($script:Failed) { Write-Host 'run_whole_db_reason_prune: FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'run_whole_db_reason_prune: PASS' -ForegroundColor Green
exit 0
}
catch {
  Write-Host "run_whole_db_reason_prune: ERROR $_" -ForegroundColor Red
  exit 2
}
