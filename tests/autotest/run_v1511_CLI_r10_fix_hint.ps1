<#
  run_v1511_CLI_r10_fix_hint.ps1 -- lane v1511 CLI, item R10.
  A single-file `lint <file> --fix` was silent that some rules are judged only by lint-all
  (cross-file duplicate-code, interface-reference-cycle, the project rules without an
  index ...), so neither their findings nor review-marker-unused for a dl:ok naming them
  can be fixed by that run. Now --fix prints one stderr note naming them and lint-all --fix.
  Control: the same run without --fix prints no such note; --json stdout stays parseable.
  Usage: pwsh -File tests\autotest\run_v1511_CLI_r10_fix_hint.ps1 [-Exe <drag-lint.exe>]
#>
param([string]$Exe = '')
# Defaults that need the script path are resolved HERE, not in param(): Windows PowerShell 5 run with
# -File leaves $PSScriptRoot/$MyInvocation empty inside an advanced script's param block (Repo became C:\).
if (-not $Exe) { $Exe = (Join-Path $PSScriptRoot '..\..\src\cli\Win64\Debug\drag-lint.exe') }
$ErrorActionPreference = 'Stop'
$exePath = (Resolve-Path $Exe).Path
$scratch = Join-Path $env:TEMP ("v1511_cli_r10_" + $PID)
New-Item -ItemType Directory -Path $scratch -Force | Out-Null
$fail = 0
function Check([string]$Name, [bool]$Ok, [string]$Detail = '') {
  if ($Ok) { Write-Host "PASS $Name" } else { Write-Host "FAIL $Name $Detail" -ForegroundColor Red; $script:fail++ }
}
try {
  $u = Join-Path $scratch 'uFixHint.pas'
  [IO.File]::WriteAllText($u, "unit uFixHint;`r`n`r`ninterface`r`n`r`nprocedure P;`r`n`r`nimplementation`r`n`r`nprocedure P;`r`nbegin`r`nend;`r`n`r`nend.`r`n")
  $errFix = Join-Path $scratch 'fix.err'
  & $exePath lint $u --fix 1> (Join-Path $scratch 'fix.out') 2> $errFix
  $e = [IO.File]::ReadAllText($errFix)
  Check 'lint --fix: stderr names lint-all --fix' ($e -match 'lint-all --fix') $e
  Check 'lint --fix: stderr names review-marker-unused' ($e -match 'review-marker-unused') $e
  Check 'lint --fix: stderr names a lint-all-only rule (duplicate-code)' ($e -match 'duplicate-code') $e

  $errNo = Join-Path $scratch 'nofix.err'
  & $exePath lint $u 1> (Join-Path $scratch 'nofix.out') 2> $errNo
  Check 'control: lint without --fix has no lint-all --fix note' (-not ([IO.File]::ReadAllText($errNo) -match 'lint-all --fix')) ([IO.File]::ReadAllText($errNo))

  $js = (& $exePath lint $u --fix --json 2>$null | Out-String)
  $ok = $true; try { $null = $js | ConvertFrom-Json } catch { $ok = $false }
  Check 'lint --fix --json: stdout is still JSON' $ok $js
} finally {
  if (Test-Path -LiteralPath $scratch) { [IO.Directory]::Delete($scratch, $true) }
}
if ($fail -gt 0) { Write-Host "FAIL ($fail)" -ForegroundColor Red; exit 1 }
Write-Host 'PASS' -ForegroundColor Green; exit 0
