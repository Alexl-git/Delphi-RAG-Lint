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

# "category" sidecar key (clippy L0): a .scm sidecar may name its own category; without it
# ScmCategory decides ('other' for an unknown id). Positive control: both outcomes asserted.
$catDir = Join-Path ([IO.Path]::GetTempPath()) ("dl-cat-sidecar-$PID")
[void][IO.Directory]::CreateDirectory($catDir)
try {
  [IO.File]::WriteAllText((Join-Path $catDir 'zz-with-category.json'), '{"id":"zz-with-category","severity":"hint","message":"m","category":"modernize"}')
  [IO.File]::WriteAllText((Join-Path $catDir 'zz-no-category.json'), '{"id":"zz-no-category","severity":"hint","message":"m"}')
  $cj = & $exe rules --json --rules-dir $catDir 2>$null | ConvertFrom-Json
  $withCat = $cj.rules | Where-Object { $_.id -eq 'zz-with-category' }
  $noCat = $cj.rules | Where-Object { $_.id -eq 'zz-no-category' }
  Assert "sidecar category key is honoured (modernize)" ($null -ne $withCat -and $withCat.category -eq 'modernize')
  Assert "sidecar without category falls back to other" ($null -ne $noCat -and $noCat.category -eq 'other')
} finally { [IO.Directory]::Delete($catDir, $true) }

# "fix" sidecar key (autofix wave A0): a .scm sidecar with a "fix" key is fixable in
# `rules --json`; one without it is not (positive control in the same run).
$fixDir = Join-Path ([IO.Path]::GetTempPath()) ("dl-fix-sidecar-$PID")
[void][IO.Directory]::CreateDirectory($fixDir)
try {
  [IO.File]::WriteAllText((Join-Path $fixDir 'zz-with-fix.json'), '{"id":"zz-with-fix","severity":"hint","message":"m","fix":{"replace":"{x}"}}')
  [IO.File]::WriteAllText((Join-Path $fixDir 'zz-without-fix.json'), '{"id":"zz-without-fix","severity":"hint","message":"m"}')
  $fj = & $exe rules --json --rules-dir $fixDir 2>$null | ConvertFrom-Json
  $withFix = $fj.rules | Where-Object { $_.id -eq 'zz-with-fix' }
  $noFix = $fj.rules | Where-Object { $_.id -eq 'zz-without-fix' }
  Assert "sidecar fix key makes the rule fixable" ($null -ne $withFix -and $withFix.fixable -eq $true)
  Assert "sidecar without fix key is not fixable" ($null -ne $noFix -and $noFix.fixable -eq $false)
} finally { [IO.Directory]::Delete($fixDir, $true) }
$newIds = 'loop-condition-invariant','disallowed-method','index-loop-to-for-in','duplicate-unit-on-search-path'
foreach ($nid in $newIds) { Assert "clippy builtin $nid registered" (($json.rules | Where-Object { $_.id -eq $nid }).Count -eq 1) }
Assert "policy + modernize categories exist" ((@($json.rules | Where-Object { $_.category -eq 'policy' }).Count -eq 3) -and (@($json.rules | Where-Object { $_.category -eq 'modernize' }).Count -ge 1))
Write-Host ""
if ($fail -gt 0) { Write-Host "rules-cli: $fail FAIL"; exit 1 } else { Write-Host "rules-cli: all pass"; exit 0 }
