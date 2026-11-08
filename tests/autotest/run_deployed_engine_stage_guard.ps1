<#
  run_deployed_engine_stage_guard.ps1 -- GD (wave 148, 1.39 #9): Initialize-DeployedEngineStage
  (lib\EngineCompanions.ps1, called by prepare_battery.ps1) makes a worktree battery runnable.

  Scratch tree only; the real third_party is never touched. Checks:
    A  no dll-win64 exe + a Debug build  -> staged: exe, a companion dll, rules\ and casts.castlib land in dll-win64
    B  CONTROL: a dll-win64 exe already present -> nothing is staged, its bytes are unchanged
    C  CONTROL: neither exe -> returns $false, dll-win64 not created
    D  prepare_battery.ps1 actually calls it (text check; without the call a worktree never gets staged)
  Run:  pwsh -File tests\autotest\run_deployed_engine_stage_guard.ps1
#>
[CmdletBinding()]
param([string]$Repo = (Resolve-Path "$PSScriptRoot\..\..").Path)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$script:Failed = $false
function Check([string]$Name, [bool]$Ok, [string]$Detail = '') {
  Write-Host ("  [{0}] {1} {2}" -f $(if ($Ok) { 'PASS' } else { 'FAIL' }), $Name, $Detail) -ForegroundColor $(if ($Ok) { 'Green' } else { 'Red' })
  if (-not $Ok) { $script:Failed = $true }
}
Write-Host '== deployed-engine stage guard ==' -ForegroundColor Cyan
. (Join-Path $PSScriptRoot 'lib\EngineCompanions.ps1')
if (-not (Get-Command Initialize-DeployedEngineStage -ErrorAction SilentlyContinue)) { Write-Host 'GUARD BROKEN: Initialize-DeployedEngineStage missing' -ForegroundColor Red; exit 1 }
$tmp = Join-Path $env:TEMP "dl-deployed-stage-$PID"
function New-Tree([string]$Name, [bool]$Built, [bool]$Deployed) {
  $r = Join-Path $tmp $Name
  if ($Built) {
    $d = Join-Path $r 'src\cli\Win64\Debug'; [void][IO.Directory]::CreateDirectory((Join-Path $d 'rules'))
    [IO.File]::WriteAllText((Join-Path $d 'drag-lint.exe'), 'built'); [IO.File]::WriteAllText((Join-Path $d 'sqlite3.dll'), 'dll')
    [IO.File]::WriteAllText((Join-Path $d 'casts.castlib'), 'cast'); [IO.File]::WriteAllText((Join-Path $d 'rules\a.scm'), 'r')
  }
  if ($Deployed) { $d = Join-Path $r 'third_party\dll-win64'; [void][IO.Directory]::CreateDirectory($d); [IO.File]::WriteAllText((Join-Path $d 'drag-lint.exe'), 'deployed') }
  return $r
}
try {
  $a = New-Tree 'a' $true $false
  $ra = Initialize-DeployedEngineStage -Repo $a
  $da = Join-Path $a 'third_party\dll-win64'
  Check 'A staged exe + dll + castlib + rules' ($ra -and ([IO.File]::ReadAllText((Join-Path $da 'drag-lint.exe')) -eq 'built') -and (Test-Path (Join-Path $da 'sqlite3.dll')) -and (Test-Path (Join-Path $da 'casts.castlib')) -and (Test-Path (Join-Path $da 'rules\a.scm')))
  $b = New-Tree 'b' $true $true
  $rb = Initialize-DeployedEngineStage -Repo $b
  Check 'B CONTROL: an existing deployed exe is left alone' ((-not $rb) -and ([IO.File]::ReadAllText((Join-Path $b 'third_party\dll-win64\drag-lint.exe')) -eq 'deployed') -and -not (Test-Path (Join-Path $b 'third_party\dll-win64\sqlite3.dll')))
  $c = New-Tree 'c' $false $false
  $rc = Initialize-DeployedEngineStage -Repo $c
  Check 'C CONTROL: no build, nothing staged' ((-not $rc) -and -not (Test-Path (Join-Path $c 'third_party\dll-win64')))
} finally {
  if (Test-Path -LiteralPath $tmp) { [IO.Directory]::Delete($tmp, $true) }
}
Check 'D prepare_battery.ps1 calls the stage' ([IO.File]::ReadAllText((Join-Path $PSScriptRoot 'prepare_battery.ps1')) -match 'Initialize-DeployedEngineStage')
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'PASS' -ForegroundColor Green
exit 0
