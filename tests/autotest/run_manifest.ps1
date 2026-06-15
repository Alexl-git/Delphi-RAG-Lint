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
$plan2 = & $Exe index --all --dry-run --json --config "$fx\global.drag-lint.json" 2>&1 | Out-String
Check 'plan lib expands Win32'     ($plan2 -match 'library-Win32\.sqlite')
Check 'plan lib expands Win64'     ($plan2 -match 'library-Win64\.sqlite')
Check 'plan Proj mode folderTree'  ($plan2 -match '"name"\s*:\s*"Proj"[\s\S]*?"mode"\s*:\s*"folderTree"')
Check 'plan All dedups proj root'  ($plan2 -match '"name"\s*:\s*"All"[\s\S]*?"dedupExcludeRoots"[\s\S]*?proj')
# Task 7: Build via the manifest (folder-tree + dedup), NEVER the Library section.
Write-Host ''
Write-Host 'Task 7: manifest build (--only Proj,SQL,All)...'
& $Exe index --all --only Proj,SQL,All --config "$fx\global.drag-lint.json" 2>&1 | Out-Null
Check 'index --only exits 0' ($LASTEXITCODE -eq 0)
Check 'manifest built Proj.sqlite' (Test-Path "$fx\OUT\Proj.sqlite")
Check 'manifest built SQL.sqlite'  (Test-Path "$fx\OUT\SQL.sqlite")
Check 'manifest built All.sqlite'  (Test-Path "$fx\OUT\All.sqlite")
$pf2 = & $Exe selftest files --db "$fx\OUT\Proj.sqlite" 2>&1 | Out-String
Check 'manifest Proj keep.pas'     ($pf2 -match 'keep\.pas')
$sf2 = & $Exe selftest files --db "$fx\OUT\SQL.sqlite" 2>&1 | Out-String
Check 'manifest SQL MS only'       ($sf2 -match 'MSData\.SQL')
# Confirm --only filters correctly when only one section given.
Write-Host ''
Write-Host 'Task 7: --only Proj (single-section filter)...'
& $Exe index --all --only Proj --config "$fx\global.drag-lint.json" 2>&1 | Out-Null
Check 'index --only Proj exits 0'  ($LASTEXITCODE -eq 0)
# Task 8: parallel --jobs (Proj + SQL + All built in parallel, never Library).
Write-Host ''
Write-Host 'Task 8: parallel --jobs 3 (--only Proj,SQL,All)...'
Remove-Item "$fx\OUT\*.sqlite" -Force -ErrorAction SilentlyContinue
& $Exe index --all --jobs 3 --only Proj,SQL,All --config "$fx\global.drag-lint.json" 2>&1 | Out-Null
Check 'parallel build exits 0' ($LASTEXITCODE -eq 0)
Check 'parallel built Proj' (Test-Path "$fx\OUT\Proj.sqlite")
Check 'parallel built SQL'  (Test-Path "$fx\OUT\SQL.sqlite")
Check 'parallel built All'  (Test-Path "$fx\OUT\All.sqlite")
$ppf = & $Exe selftest files --db "$fx\OUT\Proj.sqlite" 2>&1 | Out-String
Check 'parallel Proj has keep.pas' ($ppf -match 'keep\.pas')
# Task 9: manifest-driven DB selection + 32-bit size guard.
Write-Host ''
Write-Host 'Task 9: dbselect + size guard...'
$sel = & $Exe selftest dbselect --platform Win64 --config "$fx\global.drag-lint.json" 2>&1 | Out-String
Check 'dbselect includes Proj'          ($sel -match 'Proj\.sqlite')
Check 'dbselect includes library-Win64' ($sel -match 'library-Win64\.sqlite')
Check 'dbselect excludes library-Win32' (-not ($sel -match 'library-Win32\.sqlite'))
# size guard: force 32-bit branch + threshold 0 (warn for any non-empty file)
# against a DB that was built earlier in this test run (Proj.sqlite).
$g = & $Exe query --name X --db "$fx\OUT\Proj.sqlite" --force32 --size-guard-mb 0 2>&1 | Out-String
Check 'size guard warns' ($g -match 'WARNING.*Win64|size guard|may run out of memory')
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
