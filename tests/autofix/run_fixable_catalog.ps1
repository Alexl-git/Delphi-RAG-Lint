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
  # Batch C / Task 7: naming re-casing rules -- store-backed like doc-drift/
  # missing-doc (no BuildAutofixEdits branch; edits come from BuildNamingFixEdits
  # via the FinalizeAndOutput store-backed append), but still registered fixable
  # in FIXABLE_RULE_IDS so `rules --json`.fixable and the IDE "Fix it" menu agree.
  Check 'method-pascalcase fixable=true'       ($byId['method-pascalcase'].fixable -eq $true)
  Check 'local-var-casing fixable=true'        ($byId['local-var-casing'].fixable -eq $true)
  Check 'const-casing fixable=true'            ($byId['const-casing'].fixable -eq $true)
  # Batch D / Task 3: naming PREFIX-ADDING rules -- same store-backed pattern
  # (BuildNamingFixEdits, extended with SynthesizePrefixedName), no
  # BuildAutofixEdits branch of their own either.
  Check 'field-name-prefix fixable=true'       ($byId['field-name-prefix'].fixable -eq $true)
  Check 'param-name-prefix fixable=true'       ($byId['param-name-prefix'].fixable -eq $true)
  Check 'type-name-prefix fixable=true'        ($byId['type-name-prefix'].fixable -eq $true)
  # a rule with no fix must be false (pick a stable always-present rule):
  Check 'cyclomatic-complexity fixable=false' ($byId['cyclomatic-complexity'].fixable -eq $false)
  $fixableCount = ($obj.rules | Where-Object { $_.fixable -eq $true }).Count
  Check 'exactly 17 fixable rules' ($fixableCount -eq 17)
} finally { Pop-Location }
if($fail){ Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
