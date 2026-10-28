<#
  run_fix_declines.ps1 -- the NEGATIVE half of the autofix proof (autofix wave lane A3).

  run_fix_fixtures.ps1 proves a fix writes the right bytes. This proves a fixer
  DECLINES the shapes it cannot rewrite safely (a goto label in dead code, a call
  in a condition that would be dropped, a dangling else, a handler body that
  differs ...): the rule fires, `--fix --apply` runs, and the file is untouched.

  Layout (additive, one directory per rule id):
    tests\autofix\declines\<rule-id>\<case>.pas           every finding in it must be declined
    tests\autofix\declines\<rule-id>\<case>.config.json   optional: passed as --config

  Per case, against a scratch copy named <case>.pas:
    1. lint --file <copy> --rule <id> --json        -> >= 1 row (positive control: the
       rule fires, so "unchanged" below is a decline, not a rule that never ran)
    2. lint --file <copy> --fix --fix-rule <id> --apply --no-backup -> bytes unchanged
    3. the rule still fires (the finding was declined, not silently resolved)

  Usage:
    run_fix_declines.ps1 -Exe <drag-lint.exe> [-Filter <id-wildcard>]
  Exit 0 = every case passed.
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
  [string]$Filter  = '*',
  [string]$WorkDir = "$env:TEMP\drag-lint-fix-declines-$PID"
)
$ErrorActionPreference = 'Stop'
$script:pass = 0; $script:fail = 0
function Check([string]$Name, [bool]$Ok, [string]$Detail = '') {
  if ($Ok) { $script:pass++; Write-Host "[PASS] $Name" -ForegroundColor Green }
  else {
    $script:fail++; Write-Host "[FAIL] $Name" -ForegroundColor Red
    if ($Detail) { Write-Host ("       " + $Detail) }
  }
}
function RuleRows([string]$ExePath, [string]$File, [string]$Id, [string[]]$Extra) {
  $raw = & $ExePath lint --file $File --rule $Id --json @Extra 2>$null | Out-String
  try { return @(@($raw | ConvertFrom-Json) | Where-Object { $_.rule -eq $Id }).Count } catch { return -1 }
}

$exePath = (Resolve-Path $Exe).Path
$root    = Join-Path $PSScriptRoot 'declines'
$dirs    = @(Get-ChildItem $root -Directory | Where-Object { $_.Name -like $Filter } | Sort-Object Name)
if (Test-Path $WorkDir) { [IO.Directory]::Delete($WorkDir, $true) }
New-Item -ItemType Directory -Force $WorkDir | Out-Null
$cases = 0
try {
  foreach ($dir in $dirs) {
    $id = $dir.Name
    foreach ($src in @(Get-ChildItem $dir.FullName -Filter '*.pas' | Sort-Object Name)) {
      $cases++
      $case = [IO.Path]::GetFileNameWithoutExtension($src.Name)
      $tag  = "$id/$case"
      $scr  = Join-Path $WorkDir "$id\$case"
      New-Item -ItemType Directory -Force $scr | Out-Null
      $copy = Join-Path $scr "$case.pas"
      Copy-Item $src.FullName $copy -Force
      $extra = @()
      $cfg = Join-Path $dir.FullName "$case.config.json"
      if (Test-Path $cfg) { $extra += @('--config', $cfg) }
      Push-Location $scr
      try {
        $n = RuleRows $exePath $copy $id $extra
        Check "${tag}: '$id' fires (positive control, got $n)" ($n -ge 1)
        $before = [IO.File]::ReadAllBytes($copy)
        $txt = & $exePath lint --file $copy --fix --fix-rule $id --apply --no-backup @extra 2>&1 | Out-String
        $after = [IO.File]::ReadAllBytes($copy)
        $same = ($before.Length -eq $after.Length) -and (-not (Compare-Object $before $after -SyncWindow 0))
        Check "${tag}: --fix --apply left the file unchanged (declined)" $same $txt.Trim()
        $n2 = RuleRows $exePath $copy $id $extra
        Check "${tag}: '$id' still fires after the declined fix (got $n2)" ($n2 -eq $n)
      } finally { Pop-Location }
    }
  }
} finally {
  if (Test-Path $WorkDir) { try { [IO.Directory]::Delete($WorkDir, $true) } catch { } }
}
if ($cases -eq 0) { Check "filter '$Filter' matched at least one case" $false }
Write-Host ("fix-declines: {0} case(s), {1} pass / {2} fail" -f $cases, $script:pass, $script:fail)
if ($script:fail -gt 0) { exit 1 } else { exit 0 }
