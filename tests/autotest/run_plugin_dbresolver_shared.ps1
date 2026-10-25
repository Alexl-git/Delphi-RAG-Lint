<#
  run_plugin_dbresolver_shared.ps1 -- pins the live lint's --db choice for a
  unit shared by several projects (T-05, plan
  docs\superpowers\plans\2026-10-23-engine-backlog-verified.md).

  WHAT IT PINS (DragLint.Plugin.LiveDbChoice)
    ChooseLiveLintDbs: single candidate -> it; active project's DB among the
      candidates -> it; else the declared (folder) owner -> it; else ALL
      candidates (never none when any index contains the file).
    ParseResolveDbsJson: the array survives stderr notes merged into the capture.

  Builds tests\autotest\fixtures\livedbchoice\LiveDbChoiceHarness.dpr with dcc64
  into a per-run scratch folder. Exit 0 on full pass, 1 on any failure.
#>
[CmdletBinding()]
param(
  [string]$WorkDir = "$env:TEMP\drag-lint-livedbchoice-$PID",
  [string]$Rsvars  = 'C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\rsvars.bat'
)
$ErrorActionPreference = 'Stop'
$script:Failed = $false
function Check($n, $ok, $d = '') {
  $s = if ($ok) { 'PASS' } else { 'FAIL' }
  $c = if ($ok) { 'Green' } else { 'Red' }
  Write-Host ("  [{0}] {1}" -f $s, $n) -ForegroundColor $c
  if (-not $ok) { if ($d) { Write-Host "      $d" -ForegroundColor DarkGray }; $script:Failed = $true }
}
if (-not (Test-Path $Rsvars)) { Write-Host "SKIP: no rsvars.bat ($Rsvars)" -ForegroundColor Yellow; exit 0 }

$harnessDir = "$PSScriptRoot\fixtures\livedbchoice"
$expected   = 10   # cases in LiveDbChoiceHarness.dpr; a missing case is a failure

Write-Host '== live lint --db choice for shared units (T-05) ==' -ForegroundColor Cyan
try {
  if (Test-Path $WorkDir) { [IO.Directory]::Delete($WorkDir, $true) }
  New-Item -ItemType Directory $WorkDir | Out-Null

  $batPath = "$WorkDir\build_harness.bat"
  $logPath = "$WorkDir\build_harness.log"
  $batBody = (@(
    '@echo off'
    "call `"$Rsvars`""
    "cd /d `"$harnessDir`""
    "dcc64 -CC -E`"$WorkDir`" -N0`"$WorkDir`" LiveDbChoiceHarness.dpr"
    'echo BUILD_EXITCODE=%ERRORLEVEL%'
  ) -join "`r`n")
  [IO.File]::WriteAllText($batPath, $batBody, [Text.Encoding]::ASCII)
  $null = Start-Process cmd.exe -ArgumentList '/c', "`"$batPath`"" `
            -RedirectStandardOutput $logPath -RedirectStandardError "$logPath.err" -NoNewWindow -Wait -PassThru
  $log = Get-Content $logPath -Raw -ErrorAction SilentlyContinue
  $buildOk = ($log -match 'BUILD_EXITCODE=0') -and ($log -notmatch 'Error:')
  Check 'LiveDbChoiceHarness.dpr builds (Win64)' $buildOk ((($log -split "`r?`n") | Where-Object { $_ -match 'Error|Fatal' } | Select-Object -First 4) -join ' | ')
  $exe = "$WorkDir\LiveDbChoiceHarness.exe"
  if (-not $buildOk -or -not (Test-Path $exe)) { throw 'harness did not build' }

  $lines = @(& $exe 2>&1 | ForEach-Object { "$_" })
  $code  = $LASTEXITCODE
  $pass  = @($lines | Where-Object { $_ -like 'PASS *' })
  foreach ($l in $lines) {
    if ($l -like 'PASS *') { Check $l.Substring(5) $true }
    elseif ($l -like 'FAIL *') { Check $l.Substring(5) $false }
  }
  Check "all $expected cases ran and passed (got $($pass.Count))" ($pass.Count -eq $expected)
  Check 'harness exit code 0' ($code -eq 0) "exit=$code"
}
catch {
  Check 'harness run' $false $_.Exception.Message
}
finally {
  if (Test-Path $WorkDir) { try { [IO.Directory]::Delete($WorkDir, $true) } catch { } }
}
if ($script:Failed) { exit 1 } else { Write-Host 'ALL PASS' -ForegroundColor Green; exit 0 }
