param([string]$Exe = "third_party\dll-win64\drag-lint.exe")
$ErrorActionPreference = "Stop"
$repo = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
Set-Location $repo
$exe = (Resolve-Path $Exe).Path
$dir = Join-Path $PSScriptRoot "safedelete"
$db  = Join-Path $env:TEMP "refactor_safedelete.sqlite"
if (Test-Path $db) { Remove-Item $db -Force }
& $exe index $dir --db $db | Out-Null
$fail = 0
function Assert($n,$c){ if($c){Write-Host "PASS  $n"}else{Write-Host "FAIL  $n" -ForegroundColor Red;$script:fail++} }

# REFUSE: IsCalled has a caller -> must refuse, nonzero exit, no edits
$ref = (& $exe safe-delete --name Used.IsCalled --db $db 2>&1) -join "`n"
Assert "refuses delete of a referenced symbol" ($ref -match 'refuse|referenced|in use|cannot' -and $LASTEXITCODE -ne 0)

# SUCCESS dry-run: NeverCalled has zero callers -> proposes deletion
$dry = (& $exe safe-delete --name Dead.NeverCalled --db $db 2>$null) -join "`n"
Assert "dry-run proposes deleting NeverCalled" ($dry -match 'delete lines')

# --apply into a temp copy, verify NeverCalled is gone (decl + body)
$tmp = Join-Path $env:TEMP "safedelete_apply"
if (Test-Path $tmp) { Remove-Item $tmp -Recurse -Force }
New-Item -ItemType Directory -Path $tmp | Out-Null
Copy-Item (Join-Path $dir "Dead.pas") $tmp
$db2 = Join-Path $env:TEMP "refactor_safedelete2.sqlite"; if (Test-Path $db2) { Remove-Item $db2 -Force }
& $exe index $tmp --db $db2 | Out-Null
$t = Join-Path $tmp "Dead.pas"
& $exe safe-delete --name Dead.NeverCalled --apply --no-backup --db $db2 2>$null | Out-Null
$after = Get-Content $t -Raw
Assert "apply removed the NeverCalled implementation body" ($after -notmatch "Writeln\('dead'\)")

Write-Host ""
if ($fail -gt 0) { Write-Host "safe-delete: $fail FAIL"; exit 1 } else { Write-Host "safe-delete: all pass"; exit 0 }
