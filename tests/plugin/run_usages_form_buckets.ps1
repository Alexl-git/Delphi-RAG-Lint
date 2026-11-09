<#
  run_usages_form_buckets.ps1 -- 146 p1 tail (148 XP3 item 4a): the IDE Find Usages tree renders
  EVERY bucket `usages --json` returns.

  UsagesForm.ParseUsagesGrouped walked a fixed key list and never read `raises` / `handles`, so an
  exception class showed its type uses and none of its raise or except sites. This guard asks a
  real engine for the bucket names (every array-valued top-level key of `usages --json`) and checks
  each one is rendered by an AddRefGroup / AddDeclGroup / AddImpactGroup call in the form.

  Positive control: a bucket name the form does not render ('xp3-bogus-bucket') must be reported
  missing, or the matcher cannot fail.
  The tree itself is live proof owed (Ctrl+Alt+F on an exception class).

  RED BASELINE, measured 2026-11-08 (lane 148-XP3, engine 1.46.0-alpha, base 6fac00822): raises and
  handles reported missing.

  Usage: pwsh -File tests\plugin\run_usages_form_buckets.ps1 -Exe <engine> -IndexDb <index db> [-Name Exception]
#>
[CmdletBinding()]
param(
  [string]$Exe     = $(& "$PSScriptRoot\..\autotest\lib\DefaultEngineExe.ps1"),
  [string]$IndexDb = '',   # empty (the battery): a one-unit fixture that raises and handles EFix is indexed into a temp DB
  [string]$Name   = 'Exception',
  [string]$SrcDir = "$PSScriptRoot\..\..\src\delphi-plugin"
)
$ErrorActionPreference = 'Stop'
$script:Failed = $false
function Check($n, $ok, $d = '') {
  Write-Host ("  [{0}] {1} {2}" -f $(if ($ok) { 'PASS' } else { 'FAIL' }), $n, $d)
  if (-not $ok) { $script:Failed = $true }
}

if (-not $IndexDb) {
  # 148 INT: the battery runs every runner without arguments; Mandatory -Exe / -IndexDb made this a FAIL there.
  $fx = Join-Path $env:TEMP "dl-usages-buckets-$PID"
  [void][IO.Directory]::CreateDirectory($fx)
  [IO.File]::WriteAllText((Join-Path $fx 'uFix.pas'), "unit uFix;`r`ninterface`r`nuses System.SysUtils;`r`ntype`r`n  EFix = class(Exception);`r`nprocedure Run;`r`nimplementation`r`nprocedure Run;`r`nbegin`r`n  try`r`n    raise EFix.Create('x');`r`n  except`r`n    on E: EFix do ;`r`n  end;`r`nend;`r`nend.`r`n")
  $IndexDb = Join-Path $fx 'fix.sqlite'
  & $Exe index $fx --db $IndexDb --library-db none *> $null
  if ($Name -eq 'Exception') { $Name = 'EFix' }
}
$raw = & $Exe usages --name $Name --json --db $IndexDb 2>$null | Out-String
$doc = $raw | ConvertFrom-Json
$buckets = @($doc.PSObject.Properties | Where-Object { $_.Value -is [System.Array] } | ForEach-Object { $_.Name })
Check 'the engine answered with array buckets' ($buckets.Count -ge 5) ("buckets: " + ($buckets -join ','))

$form = [IO.File]::ReadAllText((Join-Path $SrcDir 'DragLint.Plugin.UsagesForm.pas'))
$m = [regex]::Match($form, '(?s)procedure TDragLintUsagesForm\.ParseUsagesGrouped.*?\nend; // begin')
Check 'ParseUsagesGrouped found' $m.Success
$body = $m.Value

function Get-Missing([string[]]$Names) {
  $Names | Where-Object {
    $k = [regex]::Escape($_)
    -not ($body -match "AddRefGroup\('$k'" -or $body -match "TryGetValue<TJSONArray>\('$k'")
  }
}

$missing = @(Get-Missing $buckets)
Check 'every bucket the engine returns is rendered' ($missing.Count -eq 0) ("missing: " + ($missing -join ','))
$control = @(Get-Missing ($buckets + 'xp3-bogus-bucket'))
Check 'positive control: an unrendered bucket is reported' ($control -contains 'xp3-bogus-bucket')

if ($script:Failed) { Write-Host 'RESULT: FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'RESULT: PASS' -ForegroundColor Green
exit 0
