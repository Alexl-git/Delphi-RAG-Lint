param([string]$Exe = "third_party\dll-win64\drag-lint.exe")
$ErrorActionPreference = "Stop"
$repo = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
Set-Location $repo
$exe = (Resolve-Path $Exe).Path
$dir = Join-Path $PSScriptRoot "rename"
$db  = Join-Path $env:TEMP "refactor_rename.sqlite"
if (Test-Path $db) { Remove-Item $db -Force }
& $exe index $dir --db $db | Out-Null
$fail = 0
function Assert($n,$c){ if($c){Write-Host "PASS  $n"}else{Write-Host "FAIL  $n" -ForegroundColor Red;$script:fail++} }

# dry-run (default): prints the edit plan, writes nothing
$dry = (& $exe rename --kind symbol --name Subject.TSubject.Foo --to Bar --db $db 2>$null) -join "`n"
Assert "dry-run shows decl rename Foo->Bar" ($dry -match 'Foo -> Bar')
Assert "dry-run shows the caller site"      (([regex]::Matches($dry,'Foo -> Bar')).Count -ge 2)

# --json edit set
$json = & $exe rename --kind symbol --name Subject.TSubject.Foo --to Bar --json --db $db 2>$null | ConvertFrom-Json
Assert "json edit set non-empty" ($json.Count -ge 2)
Assert "json edit has line/col/old/new" ($null -ne $json[0].line -and $json[0].old -eq 'Foo' -and $json[0].new -eq 'Bar')

# conflict: refuse a reserved word
$kw = (& $exe rename --kind symbol --name Subject.TSubject.Foo --to begin --db $db 2>&1) -join "`n"
Assert "refuses reserved-word target" ($kw -match 'reserved word')

Write-Host ""
if ($fail -gt 0) { Write-Host "rename-symbol: $fail FAIL"; exit 1 } else { Write-Host "rename-symbol: all pass"; exit 0 }
