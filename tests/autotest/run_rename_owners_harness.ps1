<#
  run_rename_owners_harness.ps1 -- pins tri-state DB membership and rename-owner
  discovery by FULL PATH (spec 2026-10-13-multi-project-rename, criteria 8a-8d).

  WHAT IT PINS
    * DbMembership answers member / notmember / unknown, and a DB it cannot
      open (garbage bytes, or no file at all) is UNKNOWN -- never "not an
      owner" (8c). The old Boolean DbContainsFile folded both into False.
    * A DB holding a DIFFERENT file with the same unit name (twin\uShared.pas)
      is not an owner (8a); a differently-cased spelling of the right path is.
    * FindRenameOwners probes EVERY manifest DB for the platform (8b), returns
      owners in plan order with the preferred DB first, keeps a library owner
      with Kind=library so the caller can refuse it (8d), and lists the DBs it
      could not read instead of dropping them (8c).
    * RefreshOwner (criteria 3-5): a fresh owner is used as is; a stale one is
      reindexed through the caller's callback (here: the engine's incremental
      `index --project`) and re-checked; an unopenable DB, a failed or
      ineffective reindex, a DB without its completed-run stamp, and a folder DB
      (no project file -- never reindexed) are all UNVERIFIED, with a reason.
    * ChangedFilePaths returns the FULL changed list (5 of 5) where
      ProbeIndexFreshness keeps 3 examples, using the same comparison.
    * FindStaleEdit (fix round 1, ruling 8): a multi-project rename's edit set
      is stale as a WHOLE when any one edit's span no longer holds its
      ExpectText on disk (or its file is gone), so `lint --fix --apply` writes
      none of that rename rather than half of it.

  ISOLATION: every DB is built under $env:TEMP\draglint-owners-<guid> with an
  explicit --db; the manifest is parsed from text by the harness (no manifest
  discovery). The last check proves a real project DB was not touched.

  Exit code: 0 on full pass, 1 on any failure.
#>
[CmdletBinding()]
param(
  [string]$Exe        = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe",
  [string]$FixtureDir = "$PSScriptRoot\fixtures\renameowners",
  [string]$WorkDir    = "$env:TEMP\draglint-owners-$([guid]::NewGuid().ToString('N'))"
)
$ErrorActionPreference = 'Stop'
$script:Failed = $false
function Check($n, $ok, $d = '') {
  $s = if ($ok) { 'PASS' } else { 'FAIL' }
  $c = if ($ok) { 'Green' } else { 'Red' }
  Write-Host ("  [{0}] {1} {2}" -f $s, $n, $d) -ForegroundColor $c
  if (-not $ok) { $script:Failed = $true }
}
function WriteAscii($path, $lines) {
  [System.IO.File]::WriteAllText($path, (($lines -join "`r`n") + "`r`n"), [System.Text.Encoding]::ASCII)
}

$RealDb = 'C:\Projects\DB\ORM3\CLIENT\_D-RAG\Micronite2027.sqlite'
$realBefore = if (Test-Path $RealDb) { $i = Get-Item $RealDb; "$($i.Length)|$($i.LastWriteTimeUtc.Ticks)" } else { 'absent' }

Write-Host '== Rename owners: tri-state membership + discovery by full path ==' -ForegroundColor Cyan
$Exe = (Resolve-Path $Exe).Path
New-Item -ItemType Directory $WorkDir | Out-Null
foreach ($d in 'shared', 'twin', 'A', 'T', 'many') { New-Item -ItemType Directory "$WorkDir\$d" | Out-Null }

# --- fixture sources: one unit name, two different files ---
$unit = @('unit uShared;', '', 'interface', '', 'const', '  My_Const = 1;', '', 'implementation', '', 'end.')
WriteAscii "$WorkDir\shared\uShared.pas" $unit
WriteAscii "$WorkDir\twin\uShared.pas"   $unit
WriteAscii "$WorkDir\A\A.dpr" @('program A;', '', 'uses', "  uShared in '..\shared\uShared.pas';", '', 'begin', 'end.')
foreach ($n in 1..5) { WriteAscii "$WorkDir\many\uMany$n.pas" @("unit uMany$n;", '', 'interface', '', 'implementation', '', 'end.') }
WriteAscii "$WorkDir\T\T.dpr" @('program T;', '', 'uses', "  uShared in '..\twin\uShared.pas';", '', 'begin', 'end.')

# --- fixture DBs, each with an explicit --db, cwd inside the work folder ---
Push-Location $WorkDir
try {
  $null = & $Exe index --project "$WorkDir\A\A.dpr" --db "$WorkDir\A.sqlite" 2>&1
  Check 'F1 indexed A.dpr' ($LASTEXITCODE -eq 0 -and (Test-Path "$WorkDir\A.sqlite")) "exit=$LASTEXITCODE"
  $null = & $Exe index --project "$WorkDir\T\T.dpr" --db "$WorkDir\T.sqlite" 2>&1
  Check 'F2 indexed T.dpr' ($LASTEXITCODE -eq 0 -and (Test-Path "$WorkDir\T.sqlite")) "exit=$LASTEXITCODE"
  # a LIBRARY-type DB: a folder target is valid for a library DB (never for a project DB)
  $null = & $Exe index "$WorkDir\shared" --db "$WorkDir\LIB.sqlite" 2>&1
  Check 'F3 indexed shared\ as a library DB' ($LASTEXITCODE -eq 0 -and (Test-Path "$WorkDir\LIB.sqlite")) "exit=$LASTEXITCODE"
  $null = & $Exe index "$WorkDir\many" --db "$WorkDir\many.sqlite" 2>&1
  Check 'F4 indexed many\ (5 units) as a library DB' ($LASTEXITCODE -eq 0 -and (Test-Path "$WorkDir\many.sqlite")) "exit=$LASTEXITCODE"
} finally { Pop-Location }
# fresh copies of A for the callback-double cases (RefreshOwner never sees the original)
foreach ($c in 'A_nostamp', 'A_fail', 'A_noop', 'A_preview') { Copy-Item "$WorkDir\A.sqlite" "$WorkDir\$c.sqlite" }
[System.IO.File]::WriteAllBytes("$WorkDir\bad.sqlite", [byte[]](,0xFF * 64))

# --- manifests, parsed from text by the harness ---
$j = ($WorkDir -replace '\\', '\\')
WriteAscii "$WorkDir\owners.json" @(
  '{ "indexes": { "sections": ['
  "  { `"name`": `"A`",   `"include`": [`"$j\\A\\A.dpr`"], `"db`": `"$j\\A.sqlite`" },"
  "  { `"name`": `"T`",   `"include`": [`"$j\\T\\T.dpr`"], `"db`": `"$j\\T.sqlite`" },"
  "  { `"name`": `"LIB`", `"source`": `"registry-libraries`", `"platforms`": [`"Win64`"], `"db`": `"$j\\LIB.sqlite`" }"
  ']}}')
WriteAscii "$WorkDir\unknown.json" @(
  '{ "indexes": { "sections": ['
  "  { `"name`": `"A`",   `"include`": [`"$j\\A\\A.dpr`"], `"db`": `"$j\\A.sqlite`" },"
  "  { `"name`": `"A2`",  `"include`": [`"$j\\A\\A.dpr`"], `"db`": `"$($j.ToUpper())\\A.SQLITE`" },"
  "  { `"name`": `"BAD`", `"include`": [`"$j\\T\\T.dpr`"], `"db`": `"$j\\bad.sqlite`" },"
  "  { `"name`": `"MISS`", `"include`": [`"$j\\T\\T.dpr`"], `"db`": `"$j\\never-built.sqlite`" }"
  ']}}')

# --- build the harness (bare .dpr: dcc64 with the CLI dproj's search path) ---
$rsvars = 'C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\rsvars.bat'
. (Join-Path $PSScriptRoot 'lib\CliBuildPaths.ps1')
$uArgs  = (Get-CliDcc64Args).Args
$outDir = "$FixtureDir\Win64\Debug"
New-Item -ItemType Directory -Force $outDir | Out-Null
$batPath = "$WorkDir\build_harness.bat"
$logPath = "$WorkDir\build_harness.log"
WriteAscii $batPath @(
  '@echo off'
  "call `"$rsvars`""
  "cd /d `"$FixtureDir`""
  "dcc64 -CC $uArgs -E`"$outDir`" -N0`"$outDir`" RenameOwnersHarness.dpr"
  'echo BUILD_EXITCODE=%ERRORLEVEL%')
$null = Start-Process cmd.exe -ArgumentList "/c", "`"$batPath`"" `
          -RedirectStandardOutput $logPath -RedirectStandardError "$logPath.err" -NoNewWindow -Wait -PassThru
$log = Get-Content $logPath -Raw -ErrorAction SilentlyContinue
$buildOk = ($log -match 'BUILD_EXITCODE=0') -and ($log -notmatch 'Error:')
$errLines = ($log -split "`r?`n" | Where-Object { $_ -match 'Error|Fatal' } | Select-Object -First 4) -join ' | '
Check 'B1 RenameOwnersHarness.dpr builds (Win64 Debug)' $buildOk $errLines
Copy-TreeSitterDlls -Dest $outDir | Out-Null
$hx = "$outDir\RenameOwnersHarness.exe"
if (-not $buildOk -or -not (Test-Path $hx)) { [System.IO.Directory]::Delete($WorkDir, $true); Write-Host 'FAIL' -ForegroundColor Red; exit 1 }

$out = & $hx $WorkDir $Exe 2>&1 | Out-String
$kv = @{}
foreach ($line in ($out -split "`r?`n")) { if ($line -match '^([A-Za-z0-9_.]+)=(.*)$') { $kv[$matches[1]] = $matches[2] } }
Check 'H1 harness ran to completion' ($out -match '(?m)^DONE') ($kv['EXCEPTION'])

Write-Host '-- DbMembership (8a, 8c)' -ForegroundColor Cyan
Check 'M1 the DB whose closure holds the file is a member'           ($kv['A'] -eq 'member')          "got: $($kv['A']) $($kv['A.reason'])"
Check 'M2 ... also when the caller spells the path in another case' ($kv['A_upper'] -eq 'member')    "got: $($kv['A_upper'])"
Check 'M3 same unit NAME at another path is not a member'           ($kv['T'] -eq 'notmember')       "got: $($kv['T'])"
Check 'M4 an unopenable DB is unknown, not notmember'               ($kv['bad'] -eq 'unknown')       "got: $($kv['bad'])"
Check 'M5 ... and says why'                                        ($kv['bad.reason'] -ne '')        "got: $($kv['bad.reason'])"
Check 'M6 a DB file that does not exist is unknown'                ($kv['missing'] -eq 'unknown')   "got: $($kv['missing'])"
Check 'M7 ... with reason "db file not found"'                     ($kv['missing.reason'] -eq 'db file not found') "got: $($kv['missing.reason'])"
Check 'M8 a definite answer carries no reason'                     (($kv['A.reason'] -eq '') -and ($kv['T.reason'] -eq '')) ''

Write-Host '-- FindRenameOwners (8a, 8b, 8c, 8d)' -ForegroundColor Cyan
Check 'O1 every manifest DB for the platform is probed'             ($kv['probed'] -eq '3')                  "got: $($kv['probed'])"
Check 'O2 owners by full path, plan order (twin T excluded)'        ($kv['owners'] -eq 'A,LIB')              "got: $($kv['owners'])"
Check 'O3 a library owner is kept and marked library'               ($kv['owner_kinds'] -eq 'project,library') "got: $($kv['owner_kinds'])"
Check 'O4 the project owner carries its project file'               ($kv['owner_projfile.0'] -eq "$WorkDir\A\A.dpr") "got: $($kv['owner_projfile.0'])"
Check 'O5 a library owner has no project file'                      ($kv['owner_projfile.1'] -eq '')         "got: $($kv['owner_projfile.1'])"
Check 'O6 nothing unknown when every DB opened'                     ($kv['unknown_count'] -eq '0')           "got: $($kv['unknown_count'])"
Check 'O7 the preferred DB is listed first'                         ($kv['owners_pref'] -eq 'LIB,A')         "got: $($kv['owners_pref'])"
Check 'O8 the same DB under two spellings is probed once'           ($kv['u.probed'] -eq '2')                "got: $($kv['u.probed'])"
Check 'O9 ... and owns once'                                        ($kv['u.owners'] -eq 'A')                "got: $($kv['u.owners'])"
Check 'O10 an unreadable DB is reported unknown, not dropped'       ($kv['u.unknown_count'] -eq '1')         "got: $($kv['u.unknown_count'])"
Check 'O11 ... as "dbpath: reason"' ($kv['u.unknown.0'] -like "$WorkDir\bad.sqlite: ?*") "got: $($kv['u.unknown.0'])"
Check 'O12 a configured DB whose file does not exist is NOT unknown (Ruling 14)' (($kv['u.unknown_count'] -eq '1') -and ($kv['u.probed'] -eq '2')) "got: unknown=$($kv['u.unknown_count']) probed=$($kv['u.probed'])"
Check 'O13 ... it is listed unindexed as "section (dbpath)"' (($kv['u.unindexed_count'] -eq '1') -and ($kv['u.unindexed.0'] -eq "MISS ($WorkDir\never-built.sqlite)")) "got: $($kv['u.unindexed_count']) '$($kv['u.unindexed.0'])'"
Check 'O14 ... and the probe did not create it' (-not (Test-Path "$WorkDir\never-built.sqlite")) ''
Check 'O15 every DB present -> nothing unindexed' ($kv['unindexed_count'] -eq '0') "got: $($kv['unindexed_count'])"

Write-Host '-- ChangedFilePaths + RefreshOwner (criteria 3-5)' -ForegroundColor Cyan
$sharedPath = "$WorkDir\shared\uShared.pas"
$aDpr = "$WorkDir\A\A.dpr"
Check 'C1 a just-built DB has no changed files'                     ($kv['r.changed_fresh'] -eq '0')         "got: $($kv['r.changed_fresh'])"
Check 'C2 after an edit, the edited file is listed'                 ($kv['r.changed_before'] -eq '1')        "got: $($kv['r.changed_before'])"
Check 'C3 ... by its full path'                                     ($kv['r.changed_before.0'] -eq $sharedPath) "got: $($kv['r.changed_before.0'])"
Check 'C4 the FULL list: 5 of 5 changed files'                      ($kv['m.changed'] -eq '5')               "got: $($kv['m.changed'])"
Check 'C5 ... same count as the probe, which keeps only 3 examples' (($kv['m.probe_changed'] -eq '5') -and ($kv['m.probe_examples'] -eq '3')) "got: $($kv['m.probe_changed'])/$($kv['m.probe_examples'])"
Check 'R1 a fresh owner is fresh'                                   ($kv['r.fresh'] -eq 'fresh')             "got: $($kv['r.fresh']) $($kv['r.fresh.reason'])"
Check 'R2 ... with no reason and no reindex'                        (($kv['r.fresh.reason'] -eq '') -and ($kv['r.fresh.reindex_calls'] -eq '0')) "got: '$($kv['r.fresh.reason'])' calls=$($kv['r.fresh.reindex_calls'])"
Check 'R3 a stale owner is reindexed (fresh_after=reindexed)'       ($kv['r.stale'] -eq 'reindexed')         "got: $($kv['r.stale']) $($kv['r.stale.reason'])"
Check 'R4 ... once, as index --project <projectFile> --db <db>'     (($kv['r.stale.reindex_calls'] -eq '1') -and ($kv['r.stale.args'] -eq "$aDpr|$WorkDir\A.sqlite")) "got: calls=$($kv['r.stale.reindex_calls']) args=$($kv['r.stale.args'])"
Check 'R5 ... and ChangedFilePaths is empty afterwards'             ($kv['r.changed_after'] -eq '0')         "got: $($kv['r.changed_after'])"
Check 'R6 an unopenable DB is unverified'                           ($kv['r.bad'] -eq 'unverified')          "got: $($kv['r.bad'])"
Check 'R7 ... with the error as reason, and is never reindexed'     (($kv['r.bad.reason'] -ne '') -and ($kv['r.bad.reindex_calls'] -eq '0')) "got: '$($kv['r.bad.reason'])' calls=$($kv['r.bad.reindex_calls'])"
Check 'R8 a DB file that does not exist is unverified, not created' (($kv['r.missing'] -eq 'unverified') -and ($kv['r.missing.reindex_calls'] -eq '0') -and -not (Test-Path "$WorkDir\missing.sqlite")) "got: $($kv['r.missing']) calls=$($kv['r.missing.reindex_calls'])"
Check 'R9 a folder DB (no project file) is unverified'              ($kv['r.folder'] -eq 'unverified')       "got: $($kv['r.folder'])"
Check 'R10 ... with the exact reason, and is never reindexed'       (($kv['r.folder.reason'] -eq 'no project file -- folder DBs are not reindexed by a rename') -and ($kv['r.folder.reindex_calls'] -eq '0')) "got: '$($kv['r.folder.reason'])' calls=$($kv['r.folder.reindex_calls'])"
Check 'R11 a reindex that reports failure leaves it unverified'     (($kv['r.fail'] -eq 'unverified') -and ($kv['r.fail.reason'] -eq "reindex failed: index --project $aDpr")) "got: $($kv['r.fail']) '$($kv['r.fail.reason'])'"
Check 'R12 a reindex that changes nothing: still stale, named, with the --rebuild hint (M5)'      (($kv['r.noop'] -eq 'unverified') -and ($kv['r.noop.reason'] -eq "still stale after reindex: $sharedPath -- if this DB was once widened by a folder index, rebuild it: drag-lint index --project $aDpr --db $WorkDir\A_noop.sqlite --rebuild")) "got: $($kv['r.noop']) '$($kv['r.noop.reason'])'"
Check 'R13 a DB without its completed-run stamp is stale, not fresh' (($kv['r.nostamp'] -eq 'unverified') -and ($kv['r.nostamp.reindex_calls'] -eq '1') -and ($kv['r.nostamp.reason'] -eq "still stale after reindex: index carries no indexed_at_unix stamp -- if this DB was once widened by a folder index, rebuild it: drag-lint index --project $aDpr --db $WorkDir\A_nostamp.sqlite --rebuild")) "got: $($kv['r.nostamp']) calls=$($kv['r.nostamp.reindex_calls']) '$($kv['r.nostamp.reason'])'"

Check 'R14 a PREVIEW (no reindex callback) reports a stale owner stale (Ruling 12)' ($kv['r.preview'] -eq 'stale') "got: $($kv['r.preview']) '$($kv['r.preview.reason'])'"
Check 'R15 ... with its changed-file count, and never reindexes' (($kv['r.preview.reason'] -eq '1 changed file(s)') -and ($kv['r.preview.reindex_calls'] -eq '0')) "got: '$($kv['r.preview.reason'])' calls=$($kv['r.preview.reindex_calls'])"
Check 'R16 ... and the owner DB size+mtime are unchanged' ($kv['r.preview.db_unchanged'] -eq 'TRUE') "got: $($kv['r.preview.db_unchanged'])"
Check 'R17 a stale folder DB in a preview is unverified, as on an apply' (($kv['r.previewfolder'] -eq 'unverified') -and ($kv['r.previewfolder.reason'] -eq 'no project file -- folder DBs are not reindexed by a rename')) "got: $($kv['r.previewfolder']) '$($kv['r.previewfolder.reason'])'"

Write-Host '-- FindStaleEdit: the write-time all-or-nothing guard (fix round 1, ruling 8)' -ForegroundColor Cyan
Check 'G1 every edit still holds its expected text: not stale'      ($kv['wg.fresh'] -eq 'ok')        "got: $($kv['wg.fresh'])"
Check 'G2 ONE edit''s line moved on disk: the set is stale'         ($kv['wg.moved'] -eq 'stale')     "got: $($kv['wg.moved'])"
Check 'G3 ... and the stale edit is named (file:line)'              ($kv['wg.moved.at'] -eq 'wg2.pas:2') "got: $($kv['wg.moved.at'])"
Check 'G4 a file that no longer exists is stale'                    ($kv['wg.gone'] -eq 'stale')      "got: $($kv['wg.gone'])"

Write-Host '-- One file, two spellings (Ruling 13)' -ForegroundColor Cyan
Check 'P1 MergeEdits: the duplicate folds, the edit only B has survives' (($kv['wc.why'] -eq '[]') -and ($kv['wc.merged'] -eq '2')) "got: why=$($kv['wc.why']) merged=$($kv['wc.merged'])"
Check 'P2 ... and every merged edit carries ONE spelling (the --file one)' ($kv['wc.one_spelling'] -eq 'TRUE') "got: $($kv['wc.one_spelling'])"
Check 'P3 Apply: two spellings are one file group (1 file touched)' ($kv['wc.touched'] -eq '1') "got: $($kv['wc.touched'])"
Check 'P4 ... both edits written' ($kv['wc.text_ok'] -eq 'TRUE') "got: $($kv['wc.text_ok'])"
Check 'P5 ... and the .bak is the ORIGINAL bytes, written once' ($kv['wc.bak_is_original'] -eq 'TRUE') "got: $($kv['wc.bak_is_original'])"
Check 'P6 RefusalOf: overlapping deletes under two spellings are refused' ($kv['wc.overlap_refused'] -eq 'TRUE') "got: $($kv['wc.overlap_refused'])"

Write-Host '-- GuardPlansAtWrite: all-or-nothing per RUN in single mode (T5)' -ForegroundColor Cyan
# value: dropped|edits kept|notes|decision0 decision1 (0 = apply, 1 = dropped)
Check 'AW1 batch: only the stale plan is dropped, the other''s edits kept' ($kv['aw.batch'] -eq '1|1|1|01') "got: $($kv['aw.batch'])"
Check 'AW2 single fix: one stale plan drops EVERY plan of the run, no edit kept' ($kv['aw.single'] -eq '2|0|1|11') "got: $($kv['aw.single'])"
Check 'AW3 ... the collateral plan says why it was not written' ($kv['aw.single.reason0'] -like '*all-or-nothing*') "got: $($kv['aw.single.reason0'])"
Check 'AW4 ... and carries no edits' ($kv['aw.single.edits0'] -eq '0') "got: $($kv['aw.single.edits0'])"

$realAfter =if (Test-Path $RealDb) { $i = Get-Item $RealDb; "$($i.Length)|$($i.LastWriteTimeUtc.Ticks)" } else { 'absent' }
Check 'Z1 a real project DB was not touched (size+mtime)' ($realBefore -eq $realAfter) "$realBefore -> $realAfter"

[System.IO.Directory]::Delete($WorkDir, $true)
Write-Host ''
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
