. "$PSScriptRoot\_manifest_common.ps1"   # gives $Exe + Check (mirror run_manifest.ps1's dot-source+capture)
$rootA = "$PSScriptRoot\..\fixtures\reconcile"      # has .pas files
$rootB = "$PSScriptRoot\..\fixtures\manifest\proj"  # different folder, NOT indexed into the drift DB -- but HAS .pas files
$rootC = "$PSScriptRoot\..\fixtures\drift-nosrc"    # exists on disk, but contains NO .pas/.inc/.dfm -- not drift
$db = "$env:TEMP\drift.sqlite"
if (Test-Path $db) { Remove-Item -Force $db }
& $Exe index "$rootA" --db $db 2>&1 | Out-Null
Check 'index rootA exits 0' ($LASTEXITCODE -eq 0)
$d1 = & $Exe selftest drift --db $db --root "$rootA" --root "$rootB" 2>&1 | Out-String
Check 'rootB missing'   ($d1 -match 'MISSING.*proj')
Check 'rootA not missing'(-not ($d1 -match 'MISSING.*reconcile'))
Check 'drift count 1'   ($d1 -match 'DRIFT-MISSING 1')
$d2 = & $Exe selftest drift --db $db --root "$rootA" 2>&1 | Out-String
Check 'rootA clean'     ($d2 -match 'DRIFT-OK')
# rootC has no source on disk (.txt only) -- must NOT be flagged as drift
$d3 = & $Exe selftest drift --db $db --root "$rootB" --root "$rootC" 2>&1 | Out-String
Check 'rootB (has .pas) flagged'      ($d3 -match 'MISSING.*proj')
Check 'rootC (no source) NOT flagged' (-not ($d3 -match 'MISSING.*drift-nosrc'))
Write-Host ''
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
