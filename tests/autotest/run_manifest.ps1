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
Write-Host ''
$ig = & $Exe selftest ignore --dir "$fx\proj" 2>&1 | Out-String
Check 'ignore-files selftest' ($ig -match 'IGNORE-OK')
$proj = "$fx\proj"; $out = "$fx\OUT"
if (Test-Path $out) { Remove-Item -Recurse -Force $out }
New-Item -ItemType Directory $out | Out-Null
& $Exe index $proj --db "$out\Proj.sqlite" --use-ignore --exclude "*_OLD*.pas" 2>&1 | Out-Null
$pf = & $Exe selftest files --db "$out\Proj.sqlite" 2>&1 | Out-String
Check 'proj keep.pas indexed'      ($pf -match 'keep\.pas')
Check 'proj drop.log NOT indexed'  (-not ($pf -match 'drop\.log'))
Check 'proj build/ pruned'         (-not ($pf -match '[\\/]build[\\/]'))
Check 'proj sub/a.tmp ignored'     (-not ($pf -match 'a\.tmp'))
Check 'proj sub/keep.tmp kept'     ($pf -match 'keep\.tmp')
Check 'proj Unit_OLD excluded'     (-not ($pf -match '_OLD'))
Check 'proj sub/b.pas indexed'    ($pf -match 'b\.pas')
& $Exe index "$fx\sql" --db "$out\SQL.sqlite" --include-only "MS*.SQL" 2>&1 | Out-Null
$sf = & $Exe selftest files --db "$out\SQL.sqlite" 2>&1 | Out-String
Check 'sql keeps MS*.SQL'          ($sf -match 'MSData\.SQL')
Check 'sql drops .pas'             (-not ($sf -match 'scratch\.pas'))
Check 'sql drops non-MS .SQL'      (-not ($sf -match 'notes\.SQL'))
$ap = "$fx\app"
$cl = & $Exe selftest closure --project "$ap\App.dpr" --exclude "uStale*.pas" 2>&1 | Out-String
Check 'closure has uAlpha'              ($cl -match 'uAlpha\.pas')
Check 'closure has uBeta'              ($cl -match 'uBeta\.pas')
Check 'closure has uGamma (transitive)' ($cl -match 'uGamma\.pas')
Check 'closure has inc'                ($cl -match 'uAlpha\.inc')
Check 'closure has uStale (referenced)' ($cl -match 'uStale\.pas')
Check 'orphan excluded'                (-not ($cl -match 'uOrphan\.pas'))
Check 'stale match warned'             ($cl -match 'WARN.*uStale\.pas')
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
