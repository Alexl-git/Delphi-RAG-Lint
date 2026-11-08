<#
  run_bookmarks_core.ps1 -- build and run BookmarksCoreTests.dpr (E-BOOKMARKS, IDE half).

  The pure core of drag-lint > Bookmarks (E-BOOKMARKS IDE half): verb command lines and the
  readers of the bookmarks / bookmarks-strip / bookmarks-restore --json answers (real answers
  captured from lane/147-G2's build are the fixtures).

  RED, measured 2026-11-08 on base b036f2cb: F1026 DragLint.Plugin.BookmarksCore.pas not found.
  GREEN: 20 passed, 0 failed.

  Usage: pwsh -File tests\plugin\run_bookmarks_core.ps1
#>
[CmdletBinding()]
param(
  [string]$Dpr     = "$PSScriptRoot\..\BookmarksCoreTests.dpr",
  [string]$WorkDir = "$env:TEMP\drag-lint-bookmarks-core-build-$PID"
)
$ErrorActionPreference = 'Stop'

if (-not (Test-Path $Dpr)) { Write-Host "FATAL: dpr not found: $Dpr" -ForegroundColor Red; exit 2 }
$Dpr     = (Resolve-Path $Dpr).Path
$DprDir  = Split-Path $Dpr -Parent
$DprName = Split-Path $Dpr -Leaf

$rs = 'C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\rsvars.bat'
if (-not (Test-Path $rs)) { Write-Host "FATAL: rsvars not found: $rs" -ForegroundColor Red; exit 2 }

$DcuDir = Join-Path $WorkDir 'dcu'
[System.IO.Directory]::CreateDirectory($DcuDir) | Out-Null

$bat = Join-Path $WorkDir 'build.bat'
$lines = @(
  '@echo off',
  ('call "{0}"' -f $rs),
  ('cd /d "{0}"' -f $DprDir),
  ('dcc64 -B -E"{0}" -N0"{1}" {2}' -f $WorkDir, $DcuDir, $DprName),
  'echo BUILD_EXITCODE=%ERRORLEVEL%'
)
[System.IO.File]::WriteAllText($bat, (($lines -join "`r`n") + "`r`n"), [System.Text.Encoding]::ASCII)

$buildLog = Join-Path $WorkDir 'build.log'
Start-Process cmd.exe -ArgumentList "/c","`"$bat`"" `
  -RedirectStandardOutput $buildLog -RedirectStandardError "$buildLog.err" `
  -NoNewWindow -Wait | Out-Null
$buildOut = Get-Content $buildLog -Raw
if ($buildOut -notmatch 'BUILD_EXITCODE=0') {
  Write-Host 'FATAL: compile failed' -ForegroundColor Red
  ($buildOut -split "`r?`n") | Where-Object { $_ -match 'Error|Fatal|BUILD_EXITCODE' } | ForEach-Object { Write-Host $_ }
  exit 2
}

$exe = Join-Path $WorkDir ([System.IO.Path]::GetFileNameWithoutExtension($DprName) + '.exe')
if (-not (Test-Path $exe)) { Write-Host "FATAL: exe not produced: $exe" -ForegroundColor Red; exit 2 }

$out = & $exe 2>&1 | Out-String
$rc  = $LASTEXITCODE
Write-Host $out.TrimEnd()

try { [System.IO.Directory]::Delete($WorkDir, $true) } catch { }

if ($rc -ne 0) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 }
if ($out -notmatch '(\d+) passed, 0 failed') {
  Write-Host 'FAIL: no pass/fail summary in output' -ForegroundColor Red; exit 1
}
Write-Host 'PASS' -ForegroundColor Green
exit 0
