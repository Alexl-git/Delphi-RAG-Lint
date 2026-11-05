<#
  run_reconcile_backup_name.ps1 -- reconcile-project must not call a LIVE unit stale because
  its NAME contains "backup" (RECONCILE-BACKUP-NAME-FP: DRagLint.Convert.Backup).
  A backup-shaped name (uCache_BACKUP) must still be stale: that is the positive control.
  Run from a NEUTRAL CWD (C:\TEMP), pwsh 7.
#>
param([string]$Exe = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe")
$ErrorActionPreference = 'Stop'
$fail = $false
function Check($n, $ok) { Write-Host ("  [{0}] {1}" -f $(if ($ok) {'PASS'} else {'FAIL'}), $n) -ForegroundColor $(if ($ok) {'Green'} else {'Red'}); if (-not $ok) { $script:fail = $true } }
$exeSrc = (Resolve-Path $Exe).Path; $exeSrcDir = Split-Path -Parent $exeSrc
$w = "$env:TEMP\draglint_recon_nm_$PID"
[IO.Directory]::CreateDirectory($w) | Out-Null
# Hermetic engine copy with NO drag-lint.json (the copy has none): the deployed drag-lint.json carries "*BACKUP*" in
# indexes.exclude, and reconcile-project feeds indexes.exclude in as extra stale globs (a second,
# separate source of the same false positive; see the lane report). This test pins the BUILT-IN glob.
$eng = "$w\eng"; [IO.Directory]::CreateDirectory($eng) | Out-Null
Copy-Item $exeSrc "$eng\drag-lint.exe" -Force
Get-ChildItem $exeSrcDir -Filter '*.dll' | ForEach-Object { Copy-Item $_.FullName "$eng\$($_.Name)" -Force }
if (Test-Path "$exeSrcDir\rules") { Copy-Item "$exeSrcDir\rules" "$eng\rules" -Recurse -Force }
$Exe = "$eng\drag-lint.exe"
function Put($n, $t) { [IO.File]::WriteAllText("$w\$n", ($t -replace "`r?`n","`r`n"), [Text.Encoding]::ASCII) }
Put 'App.dpr' "program App;`nuses`n  uMain in 'uMain.pas';`nbegin`nend.`n"
Put 'App.dproj' "<?xml version=`"1.0`" encoding=`"utf-8`"?>`n<Project xmlns=`"http://schemas.microsoft.com/developer/msbuild/2003`">`n  <ItemGroup>`n    <DCCReference Include=`"uMain.pas`"/>`n  </ItemGroup>`n</Project>`n"
Put 'uMain.pas' "unit uMain;`ninterface`nuses Conv.Backup, uCache_BACKUP;`nimplementation`nend.`n"
Put 'Conv.Backup.pas' "unit Conv.Backup;`ninterface`nimplementation`nend.`n"
Put 'uCache_BACKUP.pas' "unit uCache_BACKUP;`ninterface`nimplementation`nend.`n"
Push-Location C:\TEMP
try {
  $rep = & $Exe reconcile-project "$w\App.dpr" 2>&1 | Out-String
  Check 'both units reach the report as MISSING (scenario fires)' (($rep -match 'MISSING[\s\S]*Conv\.Backup') -and ($rep -match 'MISSING[\s\S]*uCache_BACKUP'))
  $stale = if ($rep -match '(?s)STALE.*?(?=SUGGESTED|\z)') { $Matches[0] } else { '' }
  Check 'a backup-shaped name stays STALE (positive control)' ($stale -match 'uCache_BACKUP')
  Check 'a live unit whose name merely contains Backup is NOT stale' (($stale -ne '') -and -not ($stale -match 'Conv\.Backup'))
} finally { Pop-Location; [IO.Directory]::Delete($w, $true) }
if ($fail) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }