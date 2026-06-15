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
Write-Host ''
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
