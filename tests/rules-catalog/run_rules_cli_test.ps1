# End-to-end test of `drag-lint rules` (text + --json) against the repo rules/.
param([string]$Exe = "third_party\dll-win64\drag-lint.exe")
$ErrorActionPreference = "Stop"
$repo = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
Set-Location $repo
$exe = (Resolve-Path $Exe).Path
$fail = 0
function Assert($name, $cond) {
  if ($cond) { Write-Host "PASS  $name" } else { Write-Host "FAIL  $name" -ForegroundColor Red; $script:fail++ }
}

# --json
$json = & $exe rules --json --rules-dir rules 2>$null | ConvertFrom-Json
Assert "json has rules array" ($null -ne $json.rules)
Assert "json rule count >= 100" ($json.rules.Count -ge 100)
$tmp = $json.rules | Where-Object { $_.id -eq 'too-many-parameters' }
Assert "too-many-parameters present" ($null -ne $tmp)
Assert "too-many-parameters category complexity" ($tmp.category -eq 'complexity')
Assert "too-many-parameters source builtin" ($tmp.source -eq 'builtin')
Assert "too-many-parameters has threshold=7" ($tmp.params.Count -eq 1 -and $tmp.params[0].name -eq 'threshold' -and "$($tmp.params[0].default)" -eq '7')
$goto = $json.rules | Where-Object { $_.id -eq 'goto-statement' }
Assert "goto-statement present + scm" ($null -ne $goto -and $goto.source -eq 'scm')
Assert "summary total > 0" ($json.summary.total -ge 100)
Assert "summary has per-category" ($json.summary.per_category.Count -ge 8)

# text mode: header line with counts + category filter
$txt = & $exe rules --rules-dir rules 2>$null
Assert "text mode has a counts header" (($txt -join "`n") -match 'rules across \d+ categories')
$ntxt = & $exe rules --category naming --rules-dir rules 2>$null
Assert "category filter naming mentions reserved-word-casing" (($ntxt -join "`n") -match 'reserved-word-casing')

Write-Host ""
if ($fail -gt 0) { Write-Host "rules-cli: $fail FAIL"; exit 1 } else { Write-Host "rules-cli: all pass"; exit 0 }
