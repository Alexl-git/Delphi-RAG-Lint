<#
  run_stale_compile_error_guard.ps1 -- a compile ERROR that no longer exists
  must disappear from the Diagnostics list.

  THE DEFECT THIS PINS (owner, live IDE, 2026-08-19):

    "While doing search I typed by mistake into uses unit name and then
     corrected it back, but the error of missing unit it still there in the
     list"

      [E] (14:1) Unit 'System.Actitimerons' not found.  [F2613]

    Line 14 of uMainZeissCopy.pas reads `, System.Actions` -- grep confirmed the
    mangled name appears NOWHERE in the file. The error outlived its cause.

  ROOT CAUSE, and it was written down in the code all along.
  ParseAndPushCompileOutput pushes the overlay like this:

      for Pair in ByFile do Cache.SetCompilerFindings(Pair.Key, ...)

    with a comment explaining that a file which "recompiled clean and reported
    nothing is not in ByFile and keeps its prior overlay". That is deliberate --
    it stops an incremental build from erasing findings for units it never
    looked at -- but it conflates two different files:

      * a unit the build NEVER LOOKED AT      -> keep its overlay  (correct)
      * a unit the build looked at and found  -> keep its overlay  (THE BUG)
        CLEAN

    The overlay can never learn "this is fixed", because being fixed produces
    silence, and silence is what the rule preserves.

  THE FIX, and its deliberate limit: a build reporting ZERO errors PROVES no
  unit has a compile error, so error-severity findings are dropped everywhere.
  Warnings and hints are KEPT -- an incremental build says nothing about units
  it skipped as up to date, and dropping those would erase findings nothing has
  disproved. A zero-error build disproves errors and nothing else.

  THE CONTROLS:
    * OLD is replayed alongside NEW, so this guard proves it DISCRIMINATES: a
      test asserting only "no error remains" would pass against a cache that
      dropped everything.
    * uOther's WARNING must survive. That is the case the original comment was
      protecting, and the naive fix (ClearAllCompilerFindings) destroys it.
    * live-lint findings must be untouched -- they come from a different
      producer, and a clean build says nothing about them.
#>
[CmdletBinding()]
param(
  [string]$FixtureDir = "$PSScriptRoot\fixtures\stalecompile",
  [string]$WorkDir    = "$env:TEMP\drag-lint-stalecompile-guard"
)
$ErrorActionPreference = 'Stop'
$script:Failed = $false
function Check($n, $ok, $d = '') {
  $s = if ($ok) { 'PASS' } else { 'FAIL' }
  $c = if ($ok) { 'Green' } else { 'Red' }
  Write-Host ("  [{0}] {1} {2}" -f $s, $n, $d) -ForegroundColor $c
  if (-not $ok) { $script:Failed = $true }
}

if (Test-Path $WorkDir) { [System.IO.Directory]::Delete($WorkDir, $true) }
New-Item -ItemType Directory $WorkDir | Out-Null

$rsvars    = 'C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\rsvars.bat'
$pluginDir = "$PSScriptRoot\..\..\src\delphi-plugin"
$outDir    = "$FixtureDir\Win64\Debug"
New-Item -ItemType Directory -Force $outDir | Out-Null
$batPath = "$WorkDir\build_harness.bat"
$logPath = "$WorkDir\build_harness.log"
$batBody = (@(
  '@echo off'
  "call `"$rsvars`""
  "cd /d `"$FixtureDir`""
  "dcc64 -CC -U`"$pluginDir`" -E`"$outDir`" -N0`"$outDir`" StaleCompileHarness.dpr"
  'echo BUILD_EXITCODE=%ERRORLEVEL%'
) -join "`r`n")
[System.IO.File]::WriteAllText($batPath, $batBody, [System.Text.Encoding]::ASCII)

$null = Start-Process cmd.exe -ArgumentList "/c", "`"$batPath`"" `
          -RedirectStandardOutput $logPath -RedirectStandardError "$logPath.err" `
          -NoNewWindow -Wait -PassThru
$log = Get-Content $logPath -Raw -ErrorAction SilentlyContinue
$buildOk = ($log -match 'BUILD_EXITCODE=0') -and ($log -notmatch 'Error:')
Check 'StaleCompileHarness.dpr builds (Win64 Debug)' $buildOk `
  (($log -split "`r?`n" | Select-Object -Last 6) -join ' | ')

$exe = "$outDir\StaleCompileHarness.exe"
if (-not $buildOk -or -not (Test-Path $exe)) {
  Write-Host "FATAL: harness exe not found at $exe -- see $logPath" -ForegroundColor Red
  Write-Host 'FAIL' -ForegroundColor Red
  exit 1
}

$out = & $exe 2>&1 | Out-String
$kv = @{}
foreach ($line in ($out -split "`r?`n")) {
  if ($line -match '^\s*([A-Za-z0-9_.]+)=(.*)$') { $kv[$matches[1]] = $matches[2].Trim() }
}
Check 'harness ran to completion' ($out -match 'DONE') $(($out -split "`r?`n" | Select-Object -First 3) -join ' | ')

Write-Host ''
Write-Host 'THE DEFECT: a fixed error must not survive a clean build' -ForegroundColor Cyan
Check 'the error was really seeded' ($kv['OLD.seeded.err'] -eq '1') "got '$($kv['OLD.seeded.err'])'"
Check 'OLD: the stale F2613 SURVIVED (the guard discriminates)' ($kv['OLD.afterCleanBuild.err'] -eq '1') `
  "got '$($kv['OLD.afterCleanBuild.err'])'"
Check 'NEW: the stale F2613 is GONE after a zero-error build' ($kv['NEW.afterCleanBuild.err'] -eq '0') `
  "got '$($kv['NEW.afterCleanBuild.err'])'"

Write-Host ''
Write-Host 'CONTROLS: the drop must be narrow' -ForegroundColor Cyan
Check 'CONTROL: another file WARNING survives the drop' ($kv['NEW.afterCleanBuild.warn'] -eq '1') `
  "got '$($kv['NEW.afterCleanBuild.warn'])' -- a naive ClearAllCompilerFindings would make this 0"
Check 'CONTROL: OLD kept that warning too (so the case is comparable)' ($kv['OLD.afterCleanBuild.warn'] -eq '1') `
  "got '$($kv['OLD.afterCleanBuild.warn'])'"
Check 'CONTROL: live-lint findings are untouched' ($kv['NEW.lintUntouched'] -eq '0') `
  "got '$($kv['NEW.lintUntouched'])'"

Write-Host ''
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'PASS' -ForegroundColor Green
exit 0
