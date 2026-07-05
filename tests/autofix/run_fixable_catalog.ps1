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
  # a rule with no fix must be false (pick a stable always-present rule):
  Check 'cyclomatic-complexity fixable=false' ($byId['cyclomatic-complexity'].fixable -eq $false)
} finally { Pop-Location }
if($fail){ Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
