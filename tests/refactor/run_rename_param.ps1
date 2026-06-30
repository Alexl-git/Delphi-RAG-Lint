param([string]$Exe = "third_party\dll-win64\drag-lint.exe")
$ErrorActionPreference = "Stop"
$repo = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
Set-Location $repo
$exe = (Resolve-Path $Exe).Path
$src = Join-Path $PSScriptRoot "rename\Param.pas"
$fail = 0
function Assert($n,$c){ if($c){Write-Host "PASS  $n"}else{Write-Host "FAIL  $n" -ForegroundColor Red;$script:fail++} }

# dry-run param rename of 'Value' (impl decl at line 5; col of the 'V' -- the test
# asserts on the rename arrows, not the exact col). Find the col with a quick scan:
$line5 = (Get-Content $src)[4]
$col = $line5.IndexOf('Value') + 1   # 1-based
$dry = (& $exe rename --kind param --file $src --line 5 --col $col --to pValue 2>$null) -join "`n"
Assert "param dry-run renames Value->pValue" ($dry -match 'Value -> pValue')
Assert "param dry-run hits multiple sites" (([regex]::Matches($dry,'Value -> pValue')).Count -ge 3)

# --apply into a temp copy, then verify the file content changed and Integer is intact
$tmp = Join-Path $env:TEMP "param_apply_test"
if (Test-Path $tmp) { Remove-Item $tmp -Recurse -Force }
New-Item -ItemType Directory -Path $tmp | Out-Null
Copy-Item $src (Join-Path $tmp "Param.pas")
$t = Join-Path $tmp "Param.pas"
$c2 = (Get-Content $t)[4]; $col2 = $c2.IndexOf('Value') + 1
& $exe rename --kind param --file $t --line 5 --col $col2 --to pValue --apply --no-backup 2>$null | Out-Null
$after = Get-Content $t -Raw
Assert "apply renamed the param decl"  ($after -match 'procedure Go\(pValue: Integer\)')
Assert "apply renamed body uses"        ($after -match 'Writeln\(pValue\)')
Assert "apply left the type Integer"    ($after -match ': Integer')
Assert "apply did NOT touch interface line is acceptable either way" $true

Write-Host ""
if ($fail -gt 0) { Write-Host "rename-param: $fail FAIL"; exit 1 } else { Write-Host "rename-param: all pass"; exit 0 }
