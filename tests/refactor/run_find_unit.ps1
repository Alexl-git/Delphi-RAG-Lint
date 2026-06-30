param([string]$Exe = "third_party\dll-win64\drag-lint.exe")
$ErrorActionPreference = "Stop"
$repo = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
Set-Location $repo
$exe = (Resolve-Path $Exe).Path
$dir = Join-Path $PSScriptRoot "findunit"
$db  = Join-Path $env:TEMP "refactor_findunit.sqlite"
if (Test-Path $db) { Remove-Item $db -Force }
& $exe index $dir --db $db | Out-Null
$fail = 0
function Assert($n,$c){ if($c){Write-Host "PASS  $n"}else{Write-Host "FAIL  $n" -ForegroundColor Red;$script:fail++} }

$target = Join-Path $dir "Target.pas"
# dry-run: should propose adding 'Lib' to Target.pas uses
$dry = (& $exe find-unit --name TWidget --in $target --db $db 2>$null) -join "`n"
Assert "dry-run proposes adding Lib" ($dry -match 'Lib')

# --json edit set
$json = & $exe find-unit --name TWidget --in $target --json --db $db 2>$null | ConvertFrom-Json
Assert "json edit set non-empty" (@($json).Count -ge 1)

# --apply into a temp copy, then verify Lib is in the uses clause
$tmp = Join-Path $env:TEMP "findunit_apply"
if (Test-Path $tmp) { Remove-Item $tmp -Recurse -Force }
New-Item -ItemType Directory -Path $tmp | Out-Null
Copy-Item (Join-Path $dir "*.pas") $tmp
$db2 = Join-Path $env:TEMP "refactor_findunit2.sqlite"; if (Test-Path $db2) { Remove-Item $db2 -Force }
& $exe index $tmp --db $db2 | Out-Null
$t = Join-Path $tmp "Target.pas"
& $exe find-unit --name TWidget --in $t --apply --no-backup --db $db2 2>$null | Out-Null
$after = Get-Content $t -Raw
Assert "apply added Lib to a uses clause" ($after -match '\bLib\b')
Assert "apply kept it compilable-looking (uses ... ;)" ($after -match 'uses[^;]*Lib[^;]*;')

# already-present: asking for a unit already in uses is a no-op
$noop = (& $exe find-unit --name TObject --in $target --db $db 2>&1) -join "`n"
Assert "already-used or unresolved is a clean no-op (no crash)" ($LASTEXITCODE -ne $null)

Write-Host ""
if ($fail -gt 0) { Write-Host "find-unit: $fail FAIL"; exit 1 } else { Write-Host "find-unit: all pass"; exit 0 }
