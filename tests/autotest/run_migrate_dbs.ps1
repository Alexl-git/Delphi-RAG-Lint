$Exe = . "$PSScriptRoot\_manifest_common.ps1"
$work = Join-Path $env:TEMP ('draglint_migrate_' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory $work | Out-Null
try {
    # A project tree + an out-of-tree DB dir, mirroring today's layout.
    $proj = Join-Path $work 'proj';  New-Item -ItemType Directory $proj | Out-Null
    $out  = Join-Path $work 'out' ;  New-Item -ItemType Directory $out  | Out-Null
    Set-Content -LiteralPath (Join-Path $proj 'App.dproj') -Value '<Project/>' -NoNewline
    Set-Content -LiteralPath (Join-Path $proj 'App.pas')   -Value "unit App;`r`ninterface`r`nimplementation`r`nend."

    # Build a real index at the OLD location so there is something to move.
    $olddb = Join-Path $out 'Old-App.sqlite'
    & $Exe index $proj --db $olddb | Out-Null
    Check 'fixture index built' (Test-Path $olddb)
    $before = & $Exe query --db $olddb --name App --json 2>$null | Out-String

    # A second, untouched folder-scan section -- purely so "dedupAgainst"
    # below names a section that actually exists (index --all's Validate
    # rejects a dangling reference); migrate-dbs itself skips it (no project
    # file), so it has no bearing on anything else in this script.
    $otherlib = Join-Path $work 'otherlib'; New-Item -ItemType Directory $otherlib | Out-Null

    # The section also carries every OTHER per-section field the real
    # manifest uses, so the Save round-trip check below (block 2) proves
    # TManifestIO.Save -- never called from any code path before this verb --
    # does not drop or mangle a sibling field while it rewrites "db".
    $cfg = Join-Path $work 'drag-lint.json'
    $j = @{ indexes = @{ outDir = $out; sections = @(
              @{ name = 'Old-App'; db = 'Old-App.sqlite'; include = @((Join-Path $proj 'App.dproj'));
                 exclude = @('*.bak'); includeOnly = @('*.pas','*.dfm'); useIgnoreFiles = $false;
                 platforms = @('Win64'); dedupAgainst = @('OtherLib') },
              @{ name = 'OtherLib'; include = @($otherlib) }
          ) } }
    Set-Content -LiteralPath $cfg -Value ($j | ConvertTo-Json -Depth 8)

    $newdb = Join-Path $proj '_D-RAG\App.sqlite'

    # 1. Dry run must NOT touch disk.
    $dry = & $Exe migrate-dbs --config $cfg 2>&1 | Out-String
    Check 'dry-run exits 0'          ($LASTEXITCODE -eq 0)
    Check 'dry-run names the target' ($dry -match [regex]::Escape($newdb))
    Check 'dry-run moved nothing'    ((Test-Path $olddb) -and -not (Test-Path $newdb))

    # 2. Apply moves the DB and its WAL siblings.
    $app = & $Exe migrate-dbs --config $cfg --apply 2>&1 | Out-String
    Check 'apply exits 0'        ($LASTEXITCODE -eq 0)
    Check 'db moved'             ((Test-Path $newdb) -and -not (Test-Path $olddb))
    Check 'no -wal left behind'  (-not (Test-Path "$olddb-wal"))
    Check 'gitignore written'    (Test-Path (Join-Path $proj '_D-RAG\.gitignore'))
    Check 'gitignore ignores all' ((Get-Content (Join-Path $proj '_D-RAG\.gitignore') -Raw).Trim() -eq '*')

    # 2b. Save round-trip: every OTHER per-section field must survive a save
    # that only changes "db" -- this is the very first code path that ever
    # calls TManifestIO.Save, and Task 3 is about to point it at the real,
    # hand-maintained manifest.
    $savedJson = Get-Content -LiteralPath $cfg -Raw | ConvertFrom-Json
    $savedSec  = $savedJson.indexes.sections | Where-Object { $_.name -eq 'Old-App' }
    Check 'Save round-trip: db cleared (now derivable)' ([string]::IsNullOrEmpty($savedSec.db))
    Check 'Save round-trip: exclude survives'        ((@($savedSec.exclude)      -join ',') -eq '*.bak')
    Check 'Save round-trip: includeOnly survives'    ((@($savedSec.includeOnly) -join ',') -eq '*.pas,*.dfm')
    Check 'Save round-trip: useIgnoreFiles survives' ($savedSec.useIgnoreFiles -eq $false)
    Check 'Save round-trip: platforms survives'      ((@($savedSec.platforms)   -join ',') -eq 'Win64')
    Check 'Save round-trip: dedupAgainst survives'   ((@($savedSec.dedupAgainst) -join ',') -eq 'OtherLib')

    # 3. The moved index still answers, and the manifest now derives the path.
    $after = & $Exe query --db $newdb --name App --json 2>$null | Out-String
    Check 'moved index still answers' ($after.Trim() -eq $before.Trim())
    $plan = & $Exe index --all --dry-run --json --config $cfg 2>$null | Out-String
    Check 'manifest points at _D-RAG' ($plan -match '_D-RAG')

    # 4. Re-running is a no-op, not an error.
    & $Exe migrate-dbs --config $cfg --apply 2>&1 | Out-Null
    Check 'second apply is a no-op' ($LASTEXITCODE -eq 0)

    # 5. A locked DB aborts with exit 2 and names the file.
    $newdb2 = Join-Path $proj '_D-RAG\App.sqlite'
    $fs = [IO.File]::Open($newdb2, 'Open', 'ReadWrite', 'None')
    try {
        $j2 = @{ indexes = @{ outDir = $out; sections = @(
                  @{ name = 'Old-App'; db = $newdb2; include = @((Join-Path $proj 'App.dproj')) } ) } }
        $cfg2 = Join-Path $work 'locked.json'
        Set-Content -LiteralPath $cfg2 -Value ($j2 | ConvertTo-Json -Depth 8)
        $lock = & $Exe migrate-dbs --config $cfg2 --apply 2>&1 | Out-String
        Check 'locked db aborts with 2' ($LASTEXITCODE -eq 2)
        Check 'lock error names the file' ($lock -match 'App.sqlite')

        # A DRY RUN must always be safe, even while the same db is locked --
        # it only prints the plan, so the lock probe must not even run.
        & $Exe migrate-dbs --config $cfg2 2>&1 | Out-Null
        Check 'dry-run is safe while a db is locked' ($LASTEXITCODE -eq 0)
    } finally { $fs.Close() }

    # 6. Multi-section batch: section A succeeds, section B fails (its "db" is
    # a corrupt, non-SQLite file that passes the exclusive-open lock probe --
    # it is not LOCKED, just not a database -- so it fails during the move
    # itself). Section A's manifest entry must already describe reality: this
    # is the exact scenario review finding 1 named (14 successes before a
    # 15th failure must not leave 14 stale entries).
    $work2 = Join-Path $env:TEMP ('draglint_migrate2_' + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory $work2 | Out-Null
    try {
        $projA = Join-Path $work2 'A';   New-Item -ItemType Directory $projA | Out-Null
        $projB = Join-Path $work2 'B';   New-Item -ItemType Directory $projB | Out-Null
        $out2  = Join-Path $work2 'out'; New-Item -ItemType Directory $out2  | Out-Null
        Set-Content -LiteralPath (Join-Path $projA 'A.dproj') -Value '<Project/>' -NoNewline
        Set-Content -LiteralPath (Join-Path $projA 'A.pas')   -Value "unit A;`r`ninterface`r`nimplementation`r`nend."
        Set-Content -LiteralPath (Join-Path $projB 'B.dproj') -Value '<Project/>' -NoNewline
        Set-Content -LiteralPath (Join-Path $projB 'B.pas')   -Value "unit B;`r`ninterface`r`nimplementation`r`nend."

        $adb = Join-Path $out2 'A.sqlite'
        $bdb = Join-Path $out2 'B.sqlite'
        & $Exe index $projA --db $adb | Out-Null
        # Not a real database -- opens fine (so the lock probe passes) but
        # throws on the checkpoint/count step, well before any move happens.
        Set-Content -LiteralPath $bdb -Value 'not a sqlite file' -NoNewline

        $cfg3 = Join-Path $work2 'drag-lint.json'
        $j3 = @{ indexes = @{ outDir = $out2; sections = @(
                  @{ name = 'A'; db = 'A.sqlite'; include = @((Join-Path $projA 'A.dproj')) },
                  @{ name = 'B'; db = 'B.sqlite'; include = @((Join-Path $projB 'B.dproj')) }
              ) } }
        Set-Content -LiteralPath $cfg3 -Value ($j3 | ConvertTo-Json -Depth 8)

        $adst = Join-Path $projA '_D-RAG\A.sqlite'
        $bdst = Join-Path $projB '_D-RAG\B.sqlite'

        & $Exe migrate-dbs --config $cfg3 --apply 2>&1 | Out-Null
        Check 'batch: overall exit is 1 (a move failed)' ($LASTEXITCODE -eq 1)
        Check 'batch: first section physically moved'    ((Test-Path $adst) -and -not (Test-Path $adb))
        Check 'batch: second section did NOT move'        (Test-Path $bdb)

        # The manifest ON DISK, not just in memory, must already reflect A.
        $savedAfterBatch = Get-Content -LiteralPath $cfg3 -Raw | ConvertFrom-Json
        $savedA = $savedAfterBatch.indexes.sections | Where-Object { $_.name -eq 'A' }
        $savedB = $savedAfterBatch.indexes.sections | Where-Object { $_.name -eq 'B' }
        Check 'batch: A on-disk manifest entry has no stale db' ([string]::IsNullOrEmpty($savedA.db))
        Check 'batch: B on-disk manifest entry unchanged (still explicit)' ($savedB.db -eq 'B.sqlite')

        $planAfterBatch = & $Exe index --all --dry-run --json --config $cfg3 2>$null | Out-String
        $planObj  = $planAfterBatch | ConvertFrom-Json
        $aSection = $planObj.sections | Where-Object { $_.name -eq 'A' }
        Check 'batch: index --all resolves A at its new home' ($aSection.db -eq $adst)

        # 7. Retry after fixing B up front (as a real second index run would):
        # its db now sits AT its derived _D-RAG home while the manifest STILL
        # carries the old, now-nonexistent explicit "db" -- exactly the state
        # a partial-failure retry leaves. Must reconcile, not "never built".
        Remove-Item -LiteralPath $bdb -Force -ErrorAction SilentlyContinue
        New-Item -ItemType Directory (Split-Path $bdst) -Force | Out-Null
        & $Exe index $projB --db $bdst | Out-Null

        $retry = & $Exe migrate-dbs --config $cfg3 --apply 2>&1 | Out-String
        Check 'retry: exits 0'                          ($LASTEXITCODE -eq 0)
        Check 'retry: reconciles B, not "never built"'  (($retry -match 'RECONCIL') -and ($retry -notmatch 'never built'))

        $planAfterRetry = & $Exe index --all --dry-run --json --config $cfg3 2>$null | Out-String
        $planObj2 = $planAfterRetry | ConvertFrom-Json
        $bSection = $planObj2.sections | Where-Object { $_.name -eq 'B' }
        Check 'retry: index --all resolves B at its new home' ($bSection.db -eq $bdst)
    } finally {
        Remove-Item -Recurse -Force $work2 -ErrorAction SilentlyContinue
    }
} finally {
    Remove-Item -Recurse -Force $work -ErrorAction SilentlyContinue
}
if ($script:Failed) { exit 1 } else { exit 0 }
