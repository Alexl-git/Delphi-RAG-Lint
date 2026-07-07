[CmdletBinding()]
param([string]$Exe = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe")
$ErrorActionPreference = 'Stop'; $fail = $false
function Check($n,$ok){ Write-Host ("[{0}] {1}" -f (@('FAIL','PASS')[[int]$ok]),$n) -ForegroundColor (@('Red','Green')[[int]$ok]); if(-not $ok){$script:fail=$true} }
Push-Location C:\TEMP
try {
  $json = & $Exe rules --json 2>$null | Out-String
  $obj  = $json | ConvertFrom-Json
  $byId = @{}; foreach($r in $obj.rules){ $byId[$r.id] = $r }
  Check 'self-assignment fixable=true'        ($byId['self-assignment'].fixable -eq $true)
  Check 'redundant-parentheses fixable=true'  ($byId['redundant-parentheses'].fixable -eq $true)
  Check 'redundant-cast fixable=true'         ($byId['redundant-cast'].fixable -eq $true)
  Check 'redundant-not-not fixable=true'       ($byId['redundant-not-not'].fixable -eq $true)
  Check 'redundant-as-tobject fixable=true'    ($byId['redundant-as-tobject'].fixable -eq $true)
  Check 'boolean-comparison-true fixable=true' ($byId['boolean-comparison-true'].fixable -eq $true)
  Check 'reserved-word-casing fixable=true'    ($byId['reserved-word-casing'].fixable -eq $true)
  Check 'redundant-assigned-free fixable=true' ($byId['redundant-assigned-free'].fixable -eq $true)
  Check 'off-by-one-count fixable=true'        ($byId['off-by-one-count'].fixable -eq $true)
  Check 'doc-drift fixable=true'               ($byId['doc-drift'].fixable -eq $true)
  Check 'missing-doc fixable=true'             ($byId['missing-doc'].fixable -eq $true)
  # a rule with no fix must be false (pick a stable always-present rule):
  Check 'cyclomatic-complexity fixable=false' ($byId['cyclomatic-complexity'].fixable -eq $false)
  $fixableCount = ($obj.rules | Where-Object { $_.fixable -eq $true }).Count
  Check 'exactly 11 fixable rules' ($fixableCount -eq 11)
} finally { Pop-Location }
if($fail){ Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
