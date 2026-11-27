<#
  run_v156_FPINJ.ps1 -- 1.56 lane FP-INJ: unused-private-member must not flag a private member
  decorated with a DI-injection attribute ([Inject], [Spring.Container.Common.Inject],
  [Inject('x')]) -- the container writes it by RTTI.
  Checks (fixture tests\fixtures\v156-fpinj\uFpInj.pas):
    I1 FInjBare, FInjQual, FInjNamed, SetDep are NOT reported.
    P1 positive controls: FWeakUnused (unrelated attribute) and FPlainUnused (none) ARE reported.
    P2 FUsed is not reported (used field, as before).
  On the base engine I1 FAILS (the injected members are reported); P1/P2 pass.
  Run from a NEUTRAL CWD (C:\TEMP), pwsh 7.
#>
[CmdletBinding()]
param([string]$Exe = '')
$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path "$PSScriptRoot\..\..").Path
if ($Exe -eq '') { $Exe = Join-Path $repo 'src\cli\Win64\Debug\drag-lint.exe' }
if (-not (Test-Path $Exe)) { Write-Host "run_v156_FPINJ: no engine at $Exe" -ForegroundColor Red; exit 2 }
$work = Join-Path $env:TEMP ('dl-v156-fpinj-' + [Guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Force $work | Out-Null
$script:fail = 0
function Check([string]$Name, [bool]$Ok, [string]$Detail = '') {
  if ($Ok) { Write-Host "  PASS  $Name  $Detail" -ForegroundColor Green }
  else { $script:fail++; Write-Host "  FAIL  $Name  $Detail" -ForegroundColor Red }
}
try {
  $src = Join-Path $work 'src'
  Copy-Item (Join-Path $repo 'tests\fixtures\v156-fpinj') $src -Recurse
  $db = Join-Path $work 'a.sqlite'
  & { $ErrorActionPreference = 'Continue'; & $Exe index $src --db $db *> $null }
  $raw = & { $ErrorActionPreference = 'Continue'; & $Exe lint-all --db $db --rule unused-private-member --json 2>$null }
  $j = @(($raw -join "`n") | ConvertFrom-Json | ForEach-Object { $_ })
  $hit = @($j | ForEach-Object { $_.symbol_name; $_.message } | Where-Object { $_ })
  $txt = ($hit -join '|')
  Write-Host "  findings: $($j.Count)"
  foreach ($n in 'FInjBare', 'FInjQual', 'FInjNamed', 'SetDep') { Check "I1 $n silent" ($txt -notmatch "\b$n\b") }
  foreach ($n in 'FWeakUnused', 'FPlainUnused') { Check "P1 $n reported (positive control)" ($txt -match "\b$n\b") }
  Check 'P2 FUsed silent' ($txt -notmatch '\bFUsed\b')
} finally { [IO.Directory]::Delete($work, $true) }
if ($script:fail -gt 0) { Write-Host "run_v156_FPINJ: $script:fail FAIL" -ForegroundColor Red; exit 1 }
Write-Host 'run_v156_FPINJ: all PASS' -ForegroundColor Green