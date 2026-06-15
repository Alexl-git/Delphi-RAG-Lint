$Exe = . "$PSScriptRoot\_manifest_common.ps1"
$fx  = "$PSScriptRoot\..\fixtures\manifest"
$plan = & $Exe index --all --dry-run --json --config "$fx\global.drag-lint.json" 2>&1 | Out-String
Check 'dry-run exits 0' ($LASTEXITCODE -eq 0)
Check 'plan is json'    ($plan.TrimStart().StartsWith('{') -or $plan.TrimStart().StartsWith('['))
Check 'section Proj'     ($plan -match '"name"\s*:\s*"Proj"')
Check 'section SQL'      ($plan -match '"name"\s*:\s*"SQL"')
Check 'settings parsed'  ($plan -match '"currentProjectsIndexing"\s*:\s*"perProject"')
$m = & $Exe selftest manifest-merge 2>&1 | Out-String
Check 'manifest-merge keeps global currentProjectsIndexing' ($m -match 'MERGE-OK')
Write-Host ''
$g = & $Exe selftest glob 2>&1 | Out-String
Check 'glob selftest' ($g -match 'GLOB-OK')
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
