try {
$Exe = . "$PSScriptRoot\_manifest_common.ps1"
$fx  = "$PSScriptRoot\..\fixtures\manifest"
# STDOUT ONLY for every JSON-SHAPE assertion below (the ones that look at the
# FIRST character). The engine writes '(loaded defaults from ...)' and the FTS5
# probe line to *stderr*; folding them in with 2>&1 leaves the interleaving
# order up to how PowerShell drains the two OS pipes, and it does not always
# come out stdout-first. Measured from a repo-root CWD (where the walk-up finds
# C:\Projects\.drag-lint.json and the preamble line is emitted at all):
# 4 of 40 merged captures started with the stderr line, so StartsWith('[')
# failed roughly 1 run in 10. Checks that assert stderr CONTENT (WARN/SKIP/size
# guard) deliberately keep 2>&1 -- those are -match, order-insensitive.
$plan = & $Exe index --all --dry-run --json --config "$fx\global.drag-lint.json" 2>$null | Out-String
Check 'dry-run exits 0' ($LASTEXITCODE -eq 0)
Check 'plan is json'    ($plan.TrimStart().StartsWith('{') -or $plan.TrimStart().StartsWith('['))
Check 'section Proj'     ($plan -match '"name"\s*:\s*"Proj"')
Check 'section SQL'      ($plan -match '"name"\s*:\s*"SQL"')
Check 'settings parsed'  ($plan -match '"currentProjectsIndexing"\s*:\s*"perProject"')
$m = & $Exe selftest manifest-merge 2>&1 | Out-String
Check 'manifest-merge keeps global currentProjectsIndexing' ($m -match 'MERGE-OK')
Write-Host ''
$sdb = & $Exe selftest section-db 2>&1 | Out-String
Check 'section-db selftest (derived _D-RAG path)' ($sdb -match 'SECTIONDB-OK')
Write-Host ''
$g = & $Exe selftest glob 2>&1 | Out-String
Check 'glob selftest' ($g -match 'GLOB-OK')
Write-Host ''
$ig = & $Exe selftest ignore --dir "$fx\proj" 2>&1 | Out-String
Check 'ignore-files selftest' ($ig -match 'IGNORE-OK')
# Regression (v0.46): ignore-walk must COMPLETE quickly on real-world ignore
# content -- a .hgignore mirroring Loader2019 (regexp-default lines, '/'-bearing
# patterns, late 'syntax: glob', '- Copy', '~', 'OLD/') plus a .gitignore with
# the flutter/fluentui catastrophic-shape globs ('**/ios/**/*.mode1v3', etc.).
# Before the linear matcher this hung (exit 124) or crashed (139). Guard with a
# hard wall-clock timeout so a regression fails the suite instead of hanging it.
Write-Host ''
$stress = "$PSScriptRoot\..\fixtures\ignore-stress"
$sdb    = Join-Path $env:TEMP "draglint_ignore_stress_$PID.sqlite"
if (Test-Path $sdb) { Remove-Item -Force $sdb }
$proc = Start-Process -FilePath $Exe `
    -ArgumentList @('index', $stress, '--db', $sdb, '--use-ignore') `
    -NoNewWindow -PassThru -RedirectStandardOutput "$env:TEMP\draglint_stress_$PID.out" `
    -RedirectStandardError "$env:TEMP\draglint_stress_$PID.err"
$done = $proc.WaitForExit(30000)   # 30s hard cap; pathological behaviour would blow this
if (-not $done) {
    try { $proc.Kill() } catch {}
    Check 'ignore-stress completes (no hang/segfault)' $false 'TIMED OUT (>30s)'
} else {
    Check 'ignore-stress completes (no hang/segfault)' ($proc.ExitCode -eq 0) "exit=$($proc.ExitCode)"
    $sf3 = & $Exe selftest files --db $sdb 2>&1 | Out-String
    Check 'ignore-stress indexed deep ios/sub file' ($sf3 -match 'uDeep\.pas')
    Check 'ignore-stress dropped "* - Copy*" file'   (-not ($sf3 -match 'Foo - Copy'))
    Check 'ignore-stress kept hg-regexp-line file'   ($sf3 -match 'uMSCLIST_OLD')
}
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
$plan2 = & $Exe index --all --dry-run --json --config "$fx\global.drag-lint.json" 2>$null | Out-String
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
# Task 10: resolve-dbs command.
Write-Host ''
Write-Host 'Task 10: resolve-dbs command...'
$rd = & $Exe resolve-dbs --platform Win64 --config "$fx\global.drag-lint.json" 2>&1 | Out-String
Check 'resolve-dbs lists Proj' ($rd -match 'Proj\.sqlite')
$rdj = & $Exe resolve-dbs --platform Win64 --config "$fx\global.drag-lint.json" --json 2>$null | Out-String
Check 'resolve-dbs --json is array' ($rdj.TrimStart().StartsWith('['))
# v0.46: file-size guard regression.
# Huge.inc is ~8 KB; --max-file-kb 1 sets the limit to 1 KB so the guard
# fires. After indexing, selftest files must NOT list Huge.inc (it was skipped).
Write-Host ''
Write-Host 'v0.46: file-size guard (--max-file-kb 1 skips Huge.inc)...'
$bigDir = "$PSScriptRoot\..\fixtures\manifest\big"
$bigDb  = Join-Path $env:TEMP "draglint_sizetest_$PID.sqlite"
if (Test-Path $bigDb) { Remove-Item -Force $bigDb }
$bigOut = & $Exe index $bigDir --db $bigDb --max-file-kb 1 2>&1 | Out-String
Check 'size-guard index exits 0'          ($LASTEXITCODE -eq 0)
Check 'size-guard prints SKIP for Huge.inc' ($bigOut -match 'SKIP.*Huge\.inc')
$bgf = & $Exe selftest files --db $bigDb 2>&1 | Out-String
Check 'size-guard: Huge.inc NOT in index' (-not ($bgf -match 'Huge\.inc'))

# 1.20.4 Task 4 (spec docs\superpowers\specs\2026-09-29-filed-defects-map.md s4):
# A MALFORMED MANIFEST NAMES THE BAD KEY, AND A WRITE VERB REFUSES IT.
# Before: every wrong-typed key read "Invalid class typecast" (no key), and a bad
# LOCAL .drag-lint.json printed a WARNING and then ran the GLOBAL plan, exit 0.
# Only STDERR is asserted for the message, so a banner on stdout cannot pass it.
function Invoke-Split([string[]]$ArgList) {
  $all = & $Exe @ArgList 2>&1
  $code = $LASTEXITCODE
  $err = ($all | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] } | ForEach-Object { $_.ToString() }) -join "`n"
  $out = ($all | Where-Object { $_ -isnot [System.Management.Automation.ErrorRecord] } | ForEach-Object { "$_" }) -join "`n"
  [pscustomobject]@{ Code = $code; Err = $err; Out = $out }
}
Write-Host ''
Write-Host '1.20.4 T4: malformed manifest via --config (no write reachable: dry run of a parse failure)...'
$r = Invoke-Split @('index', '--all', '--dry-run', '--config', "$fx\bad-indexes-array.json")
Check 'bad indexes: exit non-zero'                  ($r.Code -ne 0) "exit=$($r.Code)"
Check 'bad indexes: stderr names the key and types' ($r.Err -match 'indexes: expected object, got array') $r.Err
Check 'bad indexes: no class-typecast text'         (-not ($r.Err -match 'Invalid class typecast'))
$r = Invoke-Split @('index', '--all', '--dry-run', '--config', "$fx\bad-bool-type.json")
Check 'bad bool: exit non-zero'                     ($r.Code -ne 0) "exit=$($r.Code)"
Check 'bad bool: stderr names the key PATH'         ($r.Err -match 'indexes\.sections\[1\]\.sqlOnlyMS: expected boolean, got string') $r.Err
$r = Invoke-Split @('index', '--all', '--dry-run', '--config', "$fx\bad-syntax.json")
Check 'bad syntax: exit non-zero'                   ($r.Code -ne 0) "exit=$($r.Code)"
Check 'bad syntax: stderr says it is not valid JSON' ($r.Err -match 'not valid JSON') $r.Err

# The LOCAL-override case needs the engine to read a manifest BESIDE THE EXE and
# walk the CWD up. ISOLATION: an ENGINE COPY in %TEMP% with its OWN drag-lint.json,
# run from a CWD under %TEMP%, so the shared engine manifest (which names real
# project DBs) is never consulted -- a dry run alone is not isolation.
Write-Host ''
Write-Host '1.20.4 T4: malformed LOCAL .drag-lint.json (isolated engine copy)...'
$iso = Join-Path $env:TEMP "drag-lint-manifest-err-$PID"
if (Test-Path $iso) { Remove-Item -Recurse -Force $iso }
$isoEng = "$iso\eng"; $isoSrc = "$iso\src"; $isoCwd = "$iso\work"; $isoOut = "$iso\out"
New-Item -ItemType Directory $isoEng, $isoSrc, $isoCwd, $isoOut | Out-Null
Copy-Item $Exe "$isoEng\drag-lint.exe" -Force
Get-ChildItem -Path (Split-Path $Exe) -Filter '*.dll' | ForEach-Object { Copy-Item $_.FullName (Join-Path $isoEng $_.Name) -Force }
if (Test-Path "$(Split-Path $Exe)\rules") { Copy-Item "$(Split-Path $Exe)\rules" "$isoEng\rules" -Recurse -Force }
function Write-IsoAscii([string]$Path, [string]$Body) {
  [System.IO.File]::WriteAllText($Path, (($Body -replace "`r`n", "`n") -replace "`n", "`r`n"), [System.Text.Encoding]::ASCII)
}
$isoOwnerDb = "$iso\owner\IsoOwner.sqlite"
Write-IsoAscii "$isoEng\drag-lint.json" (@{
  settings = @{ defaultPlatform = 'Win64'; maxJobs = 1 }
  indexes  = @{ outDir = $isoOut; sections = @(
    @{ name = 'IsoSrc';   include = @($isoSrc) },
    @{ name = 'IsoOwner'; include = @("$isoSrc\Iso.dpr"); db = $isoOwnerDb }) }
} | ConvertTo-Json -Depth 6)
Write-IsoAscii "$isoSrc\UIso.pas" "unit UIso;`ninterface`nprocedure IsoProc;`nimplementation`nprocedure IsoProc;`nbegin`nend;`nend."
Write-IsoAscii "$isoSrc\Iso.dpr"  "program Iso;`nuses UIso in 'UIso.pas';`nbegin`nend."
function Get-FileStamp([string]$Path) {
  if (-not (Test-Path $Path)) { return 'absent' }
  $i = Get-Item $Path
  '{0}|{1}|{2}' -f $i.Length, $i.LastWriteTimeUtc.Ticks, (Get-FileHash $Path -Algorithm SHA256).Hash
}
$ExeSaved = $Exe; $Exe = "$isoEng\drag-lint.exe"
Push-Location $isoCwd
try {
  # SETUP, while NO local file exists yet: the owner's DB (through the manifest)
  # and a second DB for the explicit --db cases below.
  $r = Invoke-Split @('index', '--project', "$isoSrc\Iso.dpr")
  Check 'setup: index --project builds the owner DB'  (($r.Code -eq 0) -and (Test-Path $isoOwnerDb)) "exit=$($r.Code) $($r.Err)"
  $r = Invoke-Split @('index', '--project', "$isoSrc\Iso.dpr", '--db', "$iso\y\Iso.sqlite")
  Check 'setup: index --project --db builds DB y'     (($r.Code -eq 0) -and (Test-Path "$iso\y\Iso.sqlite")) "exit=$($r.Code) $($r.Err)"

  # The bad local file sits ABOVE both the CWD and the index target, so both
  # manifest walks (CWD, and the target being indexed) find it.
  Copy-Item "$fx\bad-indexes-array.json" "$iso\.drag-lint.json" -Force

  # Proof of isolation first: the engine copy sees ONLY its own sections.
  $r = Invoke-Split @('resolve-dbs', '--platform', 'Win64')
  Check 'isolation: resolve-dbs names only the scratch section' (($r.Out -match 'IsoSrc') -and -not ($r.Out -match 'Micronite|ORM3')) $r.Out
  # A READ verb keeps working, and its warning now names the key.
  Check 'read verb (resolve-dbs) still runs: exit 0'  ($r.Code -eq 0) "exit=$($r.Code)"
  Check 'read verb warns, naming the key'             ($r.Err -match 'WARNING: could not parse config at .*\.drag-lint\.json: indexes: expected object, got array') $r.Err

  $r = Invoke-Split @('index', '--all', '--dry-run')
  Check 'local bad: index --all REFUSES (exit 2)'     ($r.Code -eq 2) "exit=$($r.Code)"
  Check 'local bad: index --all names the key'        ($r.Err -match 'indexes: expected object, got array') $r.Err
  Check 'local bad: the GLOBAL plan did not run'      (-not ($r.Out -match 'IsoSrc')) $r.Out

  $r = Invoke-Split @('index', $isoSrc)
  Check 'local bad: index <folder> (no --db) REFUSES' ($r.Code -eq 2) "exit=$($r.Code)"
  Check 'local bad: index <folder> names the key'     ($r.Err -match 'indexes: expected object, got array') $r.Err
  Check 'local bad: index <folder> wrote no DB'       (-not (Test-Path "$isoOut\IsoSrc.sqlite") -and -not (Test-Path "$isoSrc\_D-RAG"))
  # ONE warning per bad file, however many times the verb loads the manifest.
  $warns = ([regex]::Matches($r.Err, 'WARNING: could not parse config at')).Count
  Check 'local bad: index <folder> warns ONCE'        ($warns -eq 1) "warnings=$warns"

  $ownerBefore = Get-FileStamp $isoOwnerDb
  $r = Invoke-Split @('index', '--project', "$isoSrc\Iso.dpr")
  Check 'local bad: index --project (no --db) REFUSES' ($r.Code -eq 2) "exit=$($r.Code)"
  Check 'local bad: index --project names the key'     ($r.Err -match 'indexes: expected object, got array') $r.Err
  Check 'local bad: index --project wrote no DB'       ((-not (Test-Path "$isoSrc\_D-RAG")) -and ((Get-FileStamp $isoOwnerDb) -eq $ownerBefore))
  $warns = ([regex]::Matches($r.Err, 'WARNING: could not parse config at')).Count
  Check 'local bad: index --project warns ONCE'        ($warns -eq 1) "warnings=$warns"

  # BOTH SIDES OF THE EXPLICIT --db RULE. index still reads the manifest (the
  # size guard), so it refuses even with --db; refresh-findings with --db never
  # consults the manifest for its DB, so it goes ahead.
  $r = Invoke-Split @('index', '--project', "$isoSrc\Iso.dpr", '--db', "$iso\explicit\Iso.sqlite")
  Check 'local bad: index --project --db REFUSES too'  ($r.Code -eq 2) "exit=$($r.Code)"
  Check 'local bad: index --project --db wrote no DB'  (-not (Test-Path "$iso\explicit\Iso.sqlite"))
  $r = Invoke-Split @('refresh-findings', '--project', "$isoSrc\Iso.dpr", '--db', "$iso\y\Iso.sqlite")
  Check 'local bad: refresh-findings --db PROCEEDS'    ((-not ($r.Err -match 'refusing to write')) -and ($r.Code -ne 2)) "exit=$($r.Code) $($r.Err)"

  $r = Invoke-Split @('refresh-findings', '--project', "$isoSrc\Iso.dpr")
  Check 'local bad: refresh-findings (no --db) REFUSES' ($r.Code -eq 2) "exit=$($r.Code)"
  Check 'local bad: refresh-findings names the key'     ($r.Err -match 'indexes: expected object, got array') $r.Err

  # compile-check COMPUTES but does not CACHE: the half-parsed manifest (the
  # global alone) names IsoOwner as the unique owner, which is exactly the
  # write the refusal exists to stop.
  $ownerBefore = Get-FileStamp $isoOwnerDb
  $r = Invoke-Split @('compile-check', "$isoSrc\Iso.dpr")
  Check 'local bad: compile-check says it will not cache' ($r.Err -match 'manifest could not be parsed .*indexes: expected object, got array.*will not be cached') $r.Err
  Check 'local bad: compile-check left the owner DB untouched' ((Get-FileStamp $isoOwnerDb) -eq $ownerBefore)

  # THE .drag-lint.json DEFAULTS KEYS (LoadConfigDefaults reads the same file).
  Write-IsoAscii "$iso\.drag-lint.json" '{ "docs": { "captureLooseComments": "yes" } }'
  $r = Invoke-Split @('resolve-dbs', '--platform', 'Win64')
  Check 'defaults bad bool: a reader still runs (exit 0)' ($r.Code -eq 0) "exit=$($r.Code) $($r.Err)"
  Check 'defaults bad bool: the warning names the key'    ($r.Err -match 'WARNING: could not parse config at .*\.drag-lint\.json: docs\.captureLooseComments: expected boolean, got string') $r.Err
  $r = Invoke-Split @('index', '--all', '--dry-run')
  Check 'defaults bad bool: a writer REFUSES (exit 2)'    ($r.Code -eq 2) "exit=$($r.Code)"
  Check 'defaults bad bool: the refusal names the key'    ($r.Err -match 'refusing to write -- the manifest could not be parsed: .*docs\.captureLooseComments: expected boolean, got string') $r.Err
  Write-IsoAscii "$iso\.drag-lint.json" '{ "watch": { "interval": "fast" } }'
  $r = Invoke-Split @('resolve-dbs', '--platform', 'Win64')
  Check 'defaults bad number: a reader still runs (exit 0)' ($r.Code -eq 0) "exit=$($r.Code) $($r.Err)"
  Check 'defaults bad number: the warning names the key'    ($r.Err -match 'watch\.interval: expected number, got string') $r.Err

  # POSITIVE CONTROL: the same runs with a well-formed local file go ahead, so the
  # refusals above are about the malformed file and nothing else.
  Write-IsoAscii "$iso\.drag-lint.json" '{ "settings": { "defaultPlatform": "Win64" } }'
  $r = Invoke-Split @('index', '--all', '--dry-run')
  Check 'control: good local -> index --all --dry-run exit 0'  ($r.Code -eq 0) "exit=$($r.Code) $($r.Err)"
  Check 'control: good local -> the plan names IsoSrc'         ($r.Out -match 'IsoSrc')
  Check 'control: good local -> no WARNING'                    (-not ($r.Err -match 'could not parse config'))
} finally {
  Pop-Location
  $Exe = $ExeSaved
}

# register-project WRITES the manifest. Asked of a manifest Load had to SKIP,
# ownership misses the section that already claims the project, and --apply
# adds a SECOND claimant -- after which every index of it refuses as ambiguous.
# Its own isolated root: the local walk from the project must find nothing, and
# FindManifestCopies looks at the engine dir's SIBLINGS, which here are ours.
Write-Host ''
Write-Host '1.20.4 T4: register-project against a manifest with a wrong-typed leaf...'
$reg = Join-Path $env:TEMP "drag-lint-manifest-reg-$PID"
if (Test-Path $reg) { Remove-Item -Recurse -Force $reg }
New-Item -ItemType Directory "$reg\eng", "$reg\src", "$reg\work" | Out-Null
Copy-Item "$isoEng\drag-lint.exe" "$reg\eng\drag-lint.exe" -Force
Get-ChildItem -Path $isoEng -Filter '*.dll' | ForEach-Object { Copy-Item $_.FullName (Join-Path "$reg\eng" $_.Name) -Force }
Write-IsoAscii "$reg\src\UIso.pas" "unit UIso;`ninterface`nimplementation`nend."
Write-IsoAscii "$reg\src\Iso.dpr"  "program Iso;`nuses UIso in 'UIso.pas';`nbegin`nend."
Write-IsoAscii "$reg\eng\drag-lint.json" (@{
  settings = @{ defaultPlatform = 'Win64' }
  indexes  = @{ sections = @(
    @{ name = 'IsoOwner'; include = @("$reg\src\Iso.dpr") },
    @{ name = 'Other';    include = @("$reg\src"); sqlOnlyMS = 'yes' }) }
} | ConvertTo-Json -Depth 6)
$manBefore = Get-FileStamp "$reg\eng\drag-lint.json"
$ExeSaved = $Exe; $Exe = "$reg\eng\drag-lint.exe"
Push-Location "$reg\work"
try {
  $r = Invoke-Split @('register-project', "$reg\src\Iso.dpr", '--apply')
  Check 'register-project --apply REFUSES (exit 2)'         ($r.Code -eq 2) "exit=$($r.Code) $($r.Out)"
  Check 'register-project names the key path'               ($r.Err -match 'indexes\.sections\[1\]\.sqlOnlyMS: expected boolean, got string') $r.Err
  Check 'register-project left the manifest byte-identical' ((Get-FileStamp "$reg\eng\drag-lint.json") -eq $manBefore)
} finally {
  Pop-Location
  $Exe = $ExeSaved
}
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
} finally {
  # D23: this run's scratch is $PID-suffixed; remove it so per-run folders do not pile up in TEMP.
  foreach ($d23 in @((Join-Path $env:TEMP "draglint_ignore_stress_$PID.sqlite"), "$env:TEMP\draglint_stress_$PID.out", "$env:TEMP\draglint_stress_$PID.err", (Join-Path $env:TEMP "draglint_sizetest_$PID.sqlite"), (Join-Path $env:TEMP "drag-lint-manifest-err-$PID"), (Join-Path $env:TEMP "drag-lint-manifest-reg-$PID"))) { if (Test-Path -LiteralPath $d23) { Remove-Item -LiteralPath $d23 -Recurse -Force -ErrorAction SilentlyContinue } }
}
