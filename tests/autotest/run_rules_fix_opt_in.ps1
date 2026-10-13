<#
  run_rules_fix_opt_in.ps1 -- `rules --json` marks the naming fixes
  `fix_opt_in`, and only them.

  THE DEFECT THIS PINS (owner report 2026-10-13, ORM3 COMMON\BASICS.PAS):
  the IDE built its "Fix all in unit (N)" count from `"fixable": true` alone.
  76 const-casing + 2 type-name-prefix findings made N = 78, and the run then
  reported "no fixable findings": the naming fixes rename a symbol everywhere
  it is used, so `lint --fix` applies them only when "autofix": [...] in
  drag-lint-lint.json opts them in. The catalog now says so per rule, from the
  same list the fixer reads (OPT_IN_FIX_RULE_IDS).

  Exit code: 0 on full pass, 1 on any failure.
#>
[CmdletBinding()]
param([string]$Exe = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe")
$ErrorActionPreference = 'Stop'
$script:fail = $false
function Check($n, $ok, $d = '') {
  Write-Host ("  [{0}] {1} {2}" -f (@('FAIL','PASS')[[int][bool]$ok]), $n, $d) -ForegroundColor (@('Red','Green')[[int][bool]$ok])
  if (-not $ok) { $script:fail = $true }
}
Write-Host '== rules --json: fix_opt_in marks the naming fixes ==' -ForegroundColor Cyan
$rules = @((& (Resolve-Path $Exe).Path rules --json 2>$null | ConvertFrom-Json).rules)
Check 'catalog read' ($rules.Count -gt 100) "rules=$($rules.Count)"

$naming = @('const-casing','field-name-prefix','local-field-prefix','local-var-casing','method-pascalcase','param-name-prefix','type-name-prefix')
$optIn  = @($rules | Where-Object { $_.fix_opt_in -eq $true } | ForEach-Object { $_.id } | Sort-Object)
Check 'O1 every rule carries the field' (@($rules | Where-Object { $null -eq $_.PSObject.Properties['fix_opt_in'] }).Count -eq 0) ''
Check 'O2 exactly the seven naming fixes are opt-in' ((Compare-Object $optIn $naming) -eq $null) "got: $($optIn -join ',')"
Check 'O3 every opt-in rule is also fixable' (@($rules | Where-Object { $_.fix_opt_in -and -not $_.fixable }).Count -eq 0) ''
# CONTROL: the field must not swallow the ordinary fixes, or "Fix all" would be dead.
$plain = @($rules | Where-Object { $_.fixable -and -not $_.fix_opt_in } | ForEach-Object { $_.id })
Check 'C1 CONTROL: ordinary fixes stay plain (unused-local, redundant-parentheses)' `
  (($plain -contains 'unused-local') -and ($plain -contains 'redundant-parentheses')) "plain=$($plain.Count)"

Write-Host ''
if ($script:fail) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
