<#
  run_v1511_CLI_r9_rules_filter.ps1 -- lane v1511 CLI, item R9.
  `rules --rule <id>` ignored its filter and printed the whole catalog. Now: --rule <id>
  lists that one rule (text and --json, summary counts the filtered set), --rule a,b lists
  both, an unknown id is exit 2 (as lint / lint-all refuse it). Positive control: a plain
  `rules --json` still lists the whole catalog.
  Usage: pwsh -File tests\autotest\run_v1511_CLI_r9_rules_filter.ps1 [-Exe <drag-lint.exe>]
#>
param([string]$Exe = '')
# Defaults that need the script path are resolved HERE, not in param(): Windows PowerShell 5 run with
# -File leaves $PSScriptRoot/$MyInvocation empty inside an advanced script's param block (Repo became C:\).
if (-not $Exe) { $Exe = (Join-Path $PSScriptRoot '..\..\src\cli\Win64\Debug\drag-lint.exe') }
$ErrorActionPreference = 'Stop'
$exePath = (Resolve-Path $Exe).Path
$fail = 0
function Check([string]$Name, [bool]$Ok, [string]$Detail = '') {
  if ($Ok) { Write-Host "PASS $Name" } else { Write-Host "FAIL $Name $Detail" -ForegroundColor Red; $script:fail++ }
}
$all = (& { $ErrorActionPreference = 'Continue'; & $exePath rules --json 2>$null } | Out-String | ConvertFrom-Json)
Check 'control: rules --json lists more than 100 rules' (@($all.rules).Count -gt 100) "$(@($all.rules).Count)"

$one = (& { $ErrorActionPreference = 'Continue'; & $exePath rules --rule threadvar-managed --json 2>$null } | Out-String | ConvertFrom-Json)
Check 'rules --rule <id> --json: exactly that rule' ((@($one.rules).Count -eq 1) -and ($one.rules[0].id -eq 'threadvar-managed')) "$(@($one.rules).Count)"
Check 'rules --rule <id> --json: summary.total = 1' ($one.summary.total -eq 1) "$($one.summary.total)"

$txt = (& { $ErrorActionPreference = 'Continue'; & $exePath rules --rule threadvar-managed 2>&1 | ForEach-Object { "$_" } } | Out-String)
Check 'rules --rule <id> text: 1 rule, the id is listed' (($txt -match '(?m)^1 rules across 1 categories') -and ($txt -match '(?m)^\s+threadvar-managed\s')) $txt

$two = (& { $ErrorActionPreference = 'Continue'; & $exePath rules --rule 'dictionary-get-without-check,threadvar-managed' --json 2>$null } | Out-String | ConvertFrom-Json)
$ids = @($two.rules | ForEach-Object { $_.id } | Sort-Object)
Check 'rules --rule a,b --json: both, nothing else' (($ids -join ',') -eq 'dictionary-get-without-check,threadvar-managed') ($ids -join ',')

& { $ErrorActionPreference = 'Continue'; & $exePath rules --rule no-such-rule-xyz 2>&1 | ForEach-Object { "$_" } } | Out-Null
Check 'rules --rule <unknown>: exit 2' ($LASTEXITCODE -eq 2) "exit=$LASTEXITCODE"

if ($fail -gt 0) { Write-Host "FAIL ($fail)" -ForegroundColor Red; exit 1 }
Write-Host 'PASS' -ForegroundColor Green; exit 0
