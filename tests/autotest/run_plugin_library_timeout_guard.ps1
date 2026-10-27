<#
  run_plugin_library_timeout_guard.ps1 -- LSP C13 (follow-up of C12).

  C12 gave the LSP's --full-rules child 16 s for a platform-library unit; the
  IDE plugin's live runner (DragLint.Plugin.LiveDiagnostics) kept a hard 8 s
  CLiveLintTimeoutMs, so an RTL file opened in the IDE could still run out.
  C13 moves the budget into ONE shared pure unit, DRagLint.Core.LintBudget,
  compiled into the engine and the plugin package, and makes both callers ask
  it with the index that OWNS the file.

  The plugin cannot run headless, so this tests at the seam:
  H   LintBudgetHarness.dpr pins LintChildTimeoutMs (library -> 16000; project
      and '' -> 8000 as POSITIVE CONTROL; case and folder-name edge cases).
  S1  the plugin's live runner passes LintChildTimeoutMs(...) to its lint run
      and no longer declares its own CLiveLintTimeoutMs = 8000.
  S2  the LSP server asks LintChildTimeoutMs and declares no budget literal of
      its own (LSP_FULL_RULES_TIMEOUT_MS / LSP_FULL_RULES_LIBRARY_TIMEOUT_MS).
  S3  both packages list the shared unit (drag-lint.dpr and dclDragLintWizard.dpk).
#>
[CmdletBinding()]
param(
  [string]$Exe     = '',   # accepted for battery uniformity; this guard builds its own harness
  [string]$WorkDir = "C:\TEMP\drag-lint-lintbudget-$PID",
  [string]$Rsvars  = 'C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\rsvars.bat'
)
$ErrorActionPreference = 'Stop'
$script:Failed = $false
function Check($n, $ok, $d = '') {
  Write-Host ("  [{0}] {1}" -f $(if ($ok) { 'PASS' } else { 'FAIL' }), $n) -ForegroundColor $(if ($ok) { 'Green' } else { 'Red' })
  if (-not $ok) { if ($d) { Write-Host "      $d" -ForegroundColor DarkGray }; $script:Failed = $true }
}
if (-not (Test-Path $Rsvars)) { Write-Host "SKIP: no rsvars.bat ($Rsvars)" -ForegroundColor Yellow; exit 0 }
$root       = (Resolve-Path "$PSScriptRoot\..\..").Path
$harnessDir = "$PSScriptRoot\fixtures\lintbudget"
$expected   = 7   # cases in LintBudgetHarness.dpr; a missing case is a failure

Write-Host '== one lint-child budget for LSP and IDE plugin (C13) ==' -ForegroundColor Cyan
try {
  if (Test-Path $WorkDir) { [IO.Directory]::Delete($WorkDir, $true) }
  New-Item -ItemType Directory $WorkDir | Out-Null
  $batPath = "$WorkDir\build_harness.bat"
  $logPath = "$WorkDir\build_harness.log"
  $batBody = (@(
    '@echo off'
    "call `"$Rsvars`""
    "cd /d `"$harnessDir`""
    "dcc64 -CC -E`"$WorkDir`" -N0`"$WorkDir`" LintBudgetHarness.dpr"
    'echo BUILD_EXITCODE=%ERRORLEVEL%'
  ) -join "`r`n")
  [IO.File]::WriteAllText($batPath, $batBody, [Text.Encoding]::ASCII)
  $null = Start-Process cmd.exe -ArgumentList '/c', "`"$batPath`"" `
            -RedirectStandardOutput $logPath -RedirectStandardError "$logPath.err" -NoNewWindow -Wait -PassThru
  $log = Get-Content $logPath -Raw -ErrorAction SilentlyContinue
  $buildOk = ($log -match 'BUILD_EXITCODE=0') -and ($log -notmatch 'Error:')
  Check 'H   LintBudgetHarness.dpr builds (Win64)' $buildOk ((($log -split "`r?`n") | Where-Object { $_ -match 'Error|Fatal' } | Select-Object -First 4) -join ' | ')
  $exeH = "$WorkDir\LintBudgetHarness.exe"
  if ($buildOk -and (Test-Path $exeH)) {
    $lines = @(& $exeH 2>&1 | ForEach-Object { "$_" })
    $code  = $LASTEXITCODE
    $pass  = @($lines | Where-Object { $_ -like 'PASS *' })
    foreach ($l in $lines) {
      if ($l -like 'PASS *') { Check ('H   ' + $l.Substring(5)) $true }
      elseif ($l -like 'FAIL *') { Check ('H   ' + $l.Substring(5)) $false }
    }
    Check "H   all $expected cases ran and passed (got $($pass.Count))" ($pass.Count -eq $expected)
    Check 'H   harness exit code 0' ($code -eq 0) "exit=$code"
  }
}
catch {
  Check 'H   harness run' $false $_.Exception.Message
}
finally {
  if (Test-Path $WorkDir) { try { [IO.Directory]::Delete($WorkDir, $true) } catch { } }
}

$live = [IO.File]::ReadAllText("$root\src\delphi-plugin\DragLint.Plugin.LiveDiagnostics.pas")
$srv  = [IO.File]::ReadAllText("$root\src\lsp\DRagLint.LSP.Server.pas")
$dpr  = [IO.File]::ReadAllText("$root\src\cli\drag-lint.dpr")
$dpk  = [IO.File]::ReadAllText("$root\src\delphi-plugin\dclDragLintWizard.dpk")
Check 'S1  live runner: the lint run is given LintChildTimeoutMs(...)' ($live -match 'RunCaptureStdoutCancellable\(Cmd, Output, LintChildTimeoutMs\(')
Check 'S1b live runner: no private CLiveLintTimeoutMs budget left' ($live -notmatch 'CLiveLintTimeoutMs\s*=')
Check 'S2  LSP server: the --full-rules budget comes from LintChildTimeoutMs' ($srv -match 'LintChildTimeoutMs\(')
Check 'S2b LSP server: no budget literal of its own' ($srv -notmatch 'LSP_FULL_RULES_(LIBRARY_)?TIMEOUT_MS\s*=')
Check 'S3  drag-lint.dpr lists DRagLint.Core.LintBudget' ($dpr -match 'DRagLint\.Core\.LintBudget in')
Check 'S3b dclDragLintWizard.dpk contains DRagLint.Core.LintBudget' ($dpk -match 'DRagLint\.Core\.LintBudget in')

if ($script:Failed) { Write-Host 'RESULT: FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'RESULT: PASS' -ForegroundColor Green; exit 0 }
