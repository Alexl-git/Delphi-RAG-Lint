<#
  run_v152_REPPROG.ps1 -- 1.52 lane REPPROG (owner ruling 2026-11-18).

  The IDE Reports questions get a progress window with Cancel. This runner
  builds tests\ReportProgressTests.dpr (Win32 and Win64, dcc from rsvars) and
  runs it: Start never waits, progress fires at Start and per Tick, Cancel
  returns within 1 s and the child process is gone BY PID, nothing is
  delivered after a cancel, the window is a marquee with elapsed seconds.

  Then a source guard on DragLint.Plugin.Reports: every Reports question goes
  through the progress window (the wiring needs the IDE, so it is checked as
  source, the same argument run_plugin_refresh_findings_queued.ps1 makes).

  Runs from anywhere, pwsh 7.
#>
[CmdletBinding()]
param(
  [string]$WorkDir = "$env:TEMP\drag-lint-v152-repprog-$PID",
  [string]$Rsvars  = 'C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\rsvars.bat'
)
$ErrorActionPreference = 'Continue'
$script:Pass = 0
$script:Fail = 0
function Check($n, $ok, $d = '') {
  if ($ok) { $script:Pass++; Write-Host "  [PASS] $n" -ForegroundColor Green }
  else { $script:Fail++; Write-Host "  [FAIL] $n" -ForegroundColor Red; if ($d) { Write-Host "      $d" -ForegroundColor DarkGray } }
}
if (-not (Test-Path $Rsvars)) { Write-Host "SKIP: no rsvars.bat ($Rsvars)" -ForegroundColor Yellow; exit 0 }

$testsDir  = (Resolve-Path "$PSScriptRoot\..").Path
$pluginDir = (Resolve-Path "$PSScriptRoot\..\..\src\delphi-plugin").Path

Write-Host '== REPPROG: Reports progress window with Cancel ==' -ForegroundColor Cyan
if (Test-Path $WorkDir) { [IO.Directory]::Delete($WorkDir, $true) }
New-Item -ItemType Directory $WorkDir | Out-Null

foreach ($dcc in 'dcc32', 'dcc64') {
  $out = "$WorkDir\$dcc"
  New-Item -ItemType Directory $out | Out-Null
  $bat = "$out\build.bat"
  $log = "$out\build.log"
  $body = (@(
    '@echo off'
    "call `"$Rsvars`""
    "cd /d `"$testsDir`""
    "$dcc -CC -B -NSSystem;Winapi;Vcl -E`"$out`" -N0`"$out`" ReportProgressTests.dpr"
    'echo BUILD_EXITCODE=%ERRORLEVEL%'
  ) -join "`r`n")
  [IO.File]::WriteAllText($bat, $body, [Text.Encoding]::ASCII)
  $null = Start-Process cmd.exe -ArgumentList '/c', "`"$bat`"" -RedirectStandardOutput $log `
            -RedirectStandardError "$log.err" -NoNewWindow -Wait -PassThru; $null = $null.Handle
  $text = Get-Content $log -Raw -ErrorAction SilentlyContinue
  $ok = ($text -match 'BUILD_EXITCODE=0') -and ($text -notmatch 'Error:')
  Check "ReportProgressTests builds ($dcc)" $ok ((($text -split "`r?`n") | Select-String 'Error|Fatal' | Select-Object -First 4) -join ' | ')
  $exe = "$out\ReportProgressTests.exe"
  if (-not $ok -or -not (Test-Path $exe)) { continue }
  $run = & { $ErrorActionPreference = 'Continue'; & $exe 2>&1 | ForEach-Object { "$_" } } | Out-String
  $summary = [regex]::Match($run, '(\d+) passed, (\d+) failed')
  foreach ($line in ($run -split "`r?`n" | Where-Object { $_ -match '^FAIL' })) { Write-Host "      $line" -ForegroundColor DarkGray }
  Check "ReportProgressTests ($dcc): $($summary.Value)" ($summary.Success -and $summary.Groups[2].Value -eq '0' -and $LASTEXITCODE -eq 0)
}

Write-Host '-- source guard: Reports questions run through the progress window' -ForegroundColor Cyan
$src = [IO.File]::ReadAllText("$pluginDir\DragLint.Plugin.Reports.pas")
$start = $src.IndexOf('procedure StartReport(')
$body = if ($start -ge 0) { $src.Substring($start, [Math]::Max(0, $src.IndexOf("`nend;", $start) - $start)) } else { '' }
Check 'StartReport exists (the guard is anchored to something real)' ($body -ne '')
Check 'StartReport opens TDragLintReportProgressForm' ($body.Contains('TDragLintReportProgressForm.CreateRun'))
Check 'StartReport does not enqueue the report on the job queue' (-not $body.Contains('JobQueue.Enqueue'))
Check 'StartReport holds the report DB for the run (no reindex starts under it)' ($body.Contains('HoldDb') -and $body.Contains('ReleaseDb'))
Check 'InvokeReportQuestion calls StartReport' ($src -match 'StartReport\(Q\.Id')
Check 'EnqueueReport is gone' (-not $src.Contains('EnqueueReport'))
$dpk = [IO.File]::ReadAllText("$pluginDir\dclDragLintWizard.dpk")
$dproj = [IO.File]::ReadAllText("$pluginDir\dclDragLintWizard.dproj")
Check 'the package contains DragLint.Plugin.ReportProgress (.dpk and .dproj)' `
  ($dpk.Contains("DragLint.Plugin.ReportProgress in 'DragLint.Plugin.ReportProgress.pas'") -and $dproj.Contains('DragLint.Plugin.ReportProgress.pas'))

try { [IO.Directory]::Delete($WorkDir, $true) } catch { Write-Host "note: $WorkDir not removed" }
Write-Host ("REPPROG: {0} passed, {1} failed" -f $script:Pass, $script:Fail)
if ($script:Fail -gt 0) { exit 1 }
exit 0
