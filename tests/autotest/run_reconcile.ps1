$Exe = . "$PSScriptRoot\_manifest_common.ps1"
$fx = "$PSScriptRoot\..\fixtures\reconcile"
$rep = & $Exe reconcile-project "$fx\App.dpr" 2>&1 | Out-String
Check 'reconcile exits 0'        ($LASTEXITCODE -eq 0)
Check 'missing uHelper'          ($rep -match 'MISSING[\s\S]*uHelper')
Check 'missing uFoo_OLD'         ($rep -match 'MISSING[\s\S]*uFoo_OLD_20230828')
Check 'extra uOrphan'            ($rep -match 'EXTRA[\s\S]*uOrphan')
Check 'stale uFoo_OLD'           ($rep -match 'STALE[\s\S]*uFoo_OLD_20230828')
Check 'stale names using unit'   ($rep -match 'uFoo_OLD_20230828.*uHelper')
Check 'dry-run wrote nothing'    (-not (Test-Path "$fx\App.dpr.bak"))

# Task 2: --apply assertions (work in a temp copy so the repo fixture stays clean)
$work = "$env:TEMP\drag-lint-reconcile"
if (Test-Path $work) { Remove-Item -Recurse -Force $work }
Copy-Item -Recurse $fx $work
& $Exe reconcile-project "$work\App.dpr" --apply 2>&1 | Out-Null
Check 'apply exits 0'         ($LASTEXITCODE -eq 0)
Check 'dpr backup made'       (Test-Path "$work\App.dpr.bak")
Check 'dproj backup made'     (Test-Path "$work\App.dproj.bak")
$dpr = Get-Content "$work\App.dpr" -Raw
Check 'dpr now has uHelper'   ($dpr -match 'uHelper\s+in\s+''uHelper\.pas''')
Check 'dpr now has uFoo_OLD'  ($dpr -match 'uFoo_OLD_20230828\s+in\s+''uFoo_OLD_20230828\.pas''')
$dproj = Get-Content "$work\App.dproj" -Raw
Check 'dproj has uHelper ref' ($dproj -match 'DCCReference Include="uHelper\.pas"')
$rep2 = & $Exe reconcile-project "$work\App.dpr" 2>&1 | Out-String
Check 'reapply 0 missing'     ($rep2 -match 'MISSING \(0\)')
Check 'uOrphan untouched'     ($rep2 -match 'EXTRA[\s\S]*uOrphan')

Write-Host ''
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
