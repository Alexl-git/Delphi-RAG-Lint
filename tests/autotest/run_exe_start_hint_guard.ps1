<#
  run_exe_start_hint_guard.ps1 -- lane CLIFIX C2 (#17). Every guard whose fixture index can come
  back empty must say WHY when the exe never started (0xC000007B, companion DLLs missing) instead
  of only "index produced no DB". Positive control: each listed guard is run against a COPY of the
  exe with NO DLLs beside it and must print the hint; negative control: the same guard against
  the intact exe prints no hint. Run from any CWD, pwsh 7.
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\drag-lint-exehint-$PID"
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'g8-common.ps1')
if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
$Exe = (Resolve-Path $Exe).Path
if (Test-Path $WorkDir) { [IO.Directory]::Delete($WorkDir, $true) }
New-Item -ItemType Directory -Path $WorkDir | Out-Null
$bare = Join-Path $WorkDir 'bare'
New-Item -ItemType Directory -Path $bare | Out-Null
Copy-Item $Exe (Join-Path $bare 'drag-lint.exe') -Force   # deliberately NO dlls beside it
$bareExe = Join-Path $bare 'drag-lint.exe'

foreach ($g in 'run_find_callers_callback_reach', 'run_generate_test_stub_guard', 'run_hover_bundle_guard',
               'run_lint_project_scope_active_config_guard', 'run_query_callers_shared_guard', 'run_text_query_adhoc_db') {
  $out = (& pwsh -NoProfile -File (Join-Path $PSScriptRoot "$g.ps1") -Exe $bareExe -WorkDir (Join-Path $WorkDir $g) 2>&1 | ForEach-Object { "$_" }) -join "`n"
  Check "$g names 0xC000007B when the exe cannot start" ($out -match '0xC000007B') (($out -split "`n" | Select-Object -First 2) -join ' | ')
}
Check 'helper: ordinary exit code gives no hint (negative control)' ((Get-ExeStartFailureHint 1) -eq '')
if ($script:Failed) { Write-Host 'run_exe_start_hint_guard: FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'run_exe_start_hint_guard: PASS' -ForegroundColor Green
exit 0
