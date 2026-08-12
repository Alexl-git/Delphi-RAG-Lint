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

    # 2c. TManifestIO.Save must be atomic (review round 2): migrate-dbs now
    # calls it up to once per section -- up to 27 times in one unattended run
    # -- against the user's real, hand-maintained manifest. Forcing a genuine
    # mid-write crash from OUTSIDE this process is not something a black-box
    # script can do deterministically, so this is covered by an in-process
    # selftest instead: it forces the atomic swap itself to fail (a read-only
    # target) and asserts the original content survives completely untouched.
    $saveAtomic = & $Exe selftest manifest-save-atomic 2>&1 | Out-String
    Check 'TManifestIO.Save is atomic' ($saveAtomic -match 'SAVEATOMIC-OK')

    # 2d. Save must write plain UTF-8, no BOM, and must not silently rewrite
    # CRLF to LF (review round 3 -- found on the real 27-database migration:
    # the real drag-lint.json came back with EF BB BF at byte 0, which a
    # strict JSON parser -- Python's json.load, jq -- rejects outright, even
    # though drag-lint itself never noticed because TFile.ReadAllText skips a
    # BOM on read). Read the RAW BYTES, not via ConvertFrom-Json or
    # Get-Content -Raw (text mode): a BOM-tolerant reader would hide the very
    # thing being tested.
    $cfgBytes = [System.IO.File]::ReadAllBytes($cfg)
    $hasBom   = ($cfgBytes.Length -ge 3 -and $cfgBytes[0] -eq 0xEF -and $cfgBytes[1] -eq 0xBB -and $cfgBytes[2] -eq 0xBF)
    Check 'Save does not write a UTF-8 BOM' (-not $hasBom)

    $loneLf = $false
    for ($bi = 0; $bi -lt $cfgBytes.Length; $bi++) {
        if ($cfgBytes[$bi] -eq 0x0A -and ($bi -eq 0 -or $cfgBytes[$bi - 1] -ne 0x0D)) { $loneLf = $true; break }
    }
    Check 'Save writes CRLF line endings (no lone LF)' (-not $loneLf)

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

    # 8. Review finding 1b: the reconciliation branch must not launder a
    # database that fails an integrity check. A manifest entry whose source
    # is gone but whose derived destination holds an UNHEALTHY file (here:
    # not a database at all) must be REFUSED, not silently accepted just
    # because something is sitting at that path.
    $work3 = Join-Path $env:TEMP ('draglint_migrate3_' + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory $work3 | Out-Null
    try {
        $projC = Join-Path $work3 'C'; New-Item -ItemType Directory $projC | Out-Null
        Set-Content -LiteralPath (Join-Path $projC 'C.dproj') -Value '<Project/>' -NoNewline
        Set-Content -LiteralPath (Join-Path $projC 'C.pas')   -Value "unit C;`r`ninterface`r`nimplementation`r`nend."

        $cdst = Join-Path $projC '_D-RAG\C.sqlite'
        New-Item -ItemType Directory (Split-Path $cdst) -Force | Out-Null
        Set-Content -LiteralPath $cdst -Value 'not a sqlite file' -NoNewline

        $cfgC = Join-Path $work3 'drag-lint.json'
        $jC = @{ indexes = @{ outDir = (Join-Path $work3 'out'); sections = @(
                  @{ name = 'C'; db = (Join-Path $work3 'out\gone-C.sqlite'); include = @((Join-Path $projC 'C.dproj')) }
              ) } }
        Set-Content -LiteralPath $cfgC -Value ($jC | ConvertTo-Json -Depth 8)

        $badRecon = & $Exe migrate-dbs --config $cfgC --apply 2>&1 | Out-String
        Check 'unhealthy reconcile: refused, exit 1'        ($LASTEXITCODE -eq 1)
        # -match is case-insensitive, and the refusal message itself says
        # "NOT reconciling" -- match the exact success marker (with the
        # colon) so that phrase cannot false-positive this check.
        Check 'unhealthy reconcile: not claimed RECONCILED' ($badRecon -notmatch 'RECONCILED:')
        Check 'unhealthy reconcile: reports the integrity failure' ($badRecon -match 'integrity check')

        # Refusing to reconcile means not touching the manifest AT ALL.
        $savedC = (Get-Content -LiteralPath $cfgC -Raw | ConvertFrom-Json).indexes.sections | Where-Object { $_.name -eq 'C' }
        Check 'unhealthy reconcile: manifest entry left alone' ($savedC.db -match 'gone-C\.sqlite')

        # A GENUINELY healthy database at the same path must still reconcile.
        Remove-Item -LiteralPath $cdst -Force
        & $Exe index $projC --db $cdst | Out-Null
        $goodRecon = & $Exe migrate-dbs --config $cfgC --apply 2>&1 | Out-String
        Check 'healthy reconcile: exits 0'    ($LASTEXITCODE -eq 0)
        Check 'healthy reconcile: RECONCILED' ($goodRecon -match 'RECONCIL')
    } finally {
        Remove-Item -Recurse -Force $work3 -ErrorAction SilentlyContinue
    }

    # 9. Review finding 1 (residual): an exception raised strictly AFTER a
    # successful physical move -- unlike block 6's section B, which fails
    # during the pre-move checkpoint -- must still leave the on-disk manifest
    # naming the destination. Forced here by pre-creating "_D-RAG\.gitignore"
    # as a DIRECTORY, so the .gitignore write (which runs after the move)
    # throws; a genuine post-move ROW-COUNT mismatch could not be constructed
    # deterministically from outside the process without either racing the
    # live child process or adding test-only fault-injection hooks to
    # production code (see the fix report) -- this exercises the identical
    # code path instead: an exception after MoveDbSet returns, caught by the
    # same except handler, Exit(1)ing the same way.
    $work4 = Join-Path $env:TEMP ('draglint_migrate4_' + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory $work4 | Out-Null
    try {
        $projD = Join-Path $work4 'D';   New-Item -ItemType Directory $projD | Out-Null
        $outD  = Join-Path $work4 'out'; New-Item -ItemType Directory $outD  | Out-Null
        Set-Content -LiteralPath (Join-Path $projD 'D.dproj') -Value '<Project/>' -NoNewline
        Set-Content -LiteralPath (Join-Path $projD 'D.pas')   -Value "unit D;`r`ninterface`r`nimplementation`r`nend."
        $ddb = Join-Path $outD 'D.sqlite'
        & $Exe index $projD --db $ddb | Out-Null

        $ddst = Join-Path $projD '_D-RAG\D.sqlite'
        New-Item -ItemType Directory (Join-Path $projD '_D-RAG\.gitignore') -Force | Out-Null

        $cfgD = Join-Path $work4 'drag-lint.json'
        $jD = @{ indexes = @{ outDir = $outD; sections = @(
                  @{ name = 'D'; db = 'D.sqlite'; include = @((Join-Path $projD 'D.dproj')) }
              ) } }
        Set-Content -LiteralPath $cfgD -Value ($jD | ConvertTo-Json -Depth 8)

        $postMove = & $Exe migrate-dbs --config $cfgD --apply 2>&1 | Out-String
        Check 'post-move failure: overall exit is 1'            ($LASTEXITCODE -eq 1)
        Check 'post-move failure: file physically moved anyway' ((Test-Path $ddst) -and -not (Test-Path $ddb))

        # Fix 3 (2026-08-11 review): MoveDbSet already relocated the .sqlite by
        # the time the .gitignore write throws, so the bare "ERROR: <class>:
        # <message>" used to read as "the move failed" when the file was, in
        # fact, already sitting at $ddst. The handler must now say so.
        Check 'post-move failure: message names the destination' ($postMove -match [regex]::Escape($ddst))
        Check 'post-move failure: message says it already moved' ($postMove -match 'ALREADY MOVED')

        $savedD = (Get-Content -LiteralPath $cfgD -Raw | ConvertFrom-Json).indexes.sections | Where-Object { $_.name -eq 'D' }
        Check 'post-move failure: manifest already names the destination, not the vanished source' ([string]::IsNullOrEmpty($savedD.db))

        # A retry must not silently declare the section healthy: the entry is
        # already correct, so the section is "already home" with nothing left
        # to do -- it must NOT print a false RECONCILED/OK claim for a
        # database whose .gitignore write never actually completed.
        $retryD = & $Exe migrate-dbs --config $cfgD --apply 2>&1 | Out-String
        Check 'post-move failure retry: exits 0 (nothing left to move)' ($LASTEXITCODE -eq 0)
        Check 'post-move failure retry: no false health claim' (($retryD -notmatch 'RECONCIL') -and ($retryD -notmatch 'OK \('))
    } finally {
        Remove-Item -Recurse -Force $work4 -ErrorAction SilentlyContinue
    }

    # 10. Fix 2 (2026-08-11 review): --config resolving to a "...\dll-win64\
    # drag-lint.json" path must mirror the SAME save onto its "...\dll-win32\
    # drag-lint.json" sibling -- the 32-bit IDE design-time BPL and the 64-bit
    # CLI each resolve and read their OWN copy (run_manifest_parity.ps1's
    # header explains the mechanism), and nothing else in the product keeps
    # the pair in sync. A real migration once desynced them silently and had
    # to be repaired by hand; this proves the next --apply cannot do it
    # again. Two sub-cases, in one hermetic tree (never touches the real
    # third_party\dll-win32\ or dll-win64\ pair):
    #   10a. no win32 sibling present -- must not fabricate one, must not error.
    #   10b. a STALE win32 sibling present -- must become byte-identical, and
    #        say so, naming the mirrored path.
    $work5 = Join-Path $env:TEMP ('draglint_migrate_pair_' + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory $work5 | Out-Null
    try {
        $dll64 = Join-Path $work5 'dll-win64'; New-Item -ItemType Directory $dll64 | Out-Null
        $dll32 = Join-Path $work5 'dll-win32'; New-Item -ItemType Directory $dll32 | Out-Null

        $projE = Join-Path $work5 'E';   New-Item -ItemType Directory $projE | Out-Null
        $outE  = Join-Path $work5 'out'; New-Item -ItemType Directory $outE  | Out-Null
        Set-Content -LiteralPath (Join-Path $projE 'E.dproj') -Value '<Project/>' -NoNewline
        Set-Content -LiteralPath (Join-Path $projE 'E.pas')   -Value "unit E;`r`ninterface`r`nimplementation`r`nend."
        & $Exe index $projE --db (Join-Path $outE 'E.sqlite') | Out-Null

        $cfg64 = Join-Path $dll64 'drag-lint.json'
        $cfg32 = Join-Path $dll32 'drag-lint.json'
        $jE = @{ indexes = @{ outDir = $outE; sections = @(
                  @{ name = 'E'; db = 'E.sqlite'; include = @((Join-Path $projE 'E.dproj')) }
              ) } }
        Set-Content -LiteralPath $cfg64 -Value ($jE | ConvertTo-Json -Depth 8)

        # 10a. No sibling file yet -- migrating E must not fabricate one.
        $noSib = & $Exe migrate-dbs --config $cfg64 --apply 2>&1 | Out-String
        Check 'pair 10a: apply exits 0'                ($LASTEXITCODE -eq 0)
        Check 'pair 10a: no sibling -- none fabricated' (-not (Test-Path $cfg32))

        # 10b. Add a STALE win32 sibling, then migrate a SECOND section (F) --
        # E is already home, so only F's move triggers a fresh Save, which is
        # what must trigger the mirror.
        Set-Content -LiteralPath $cfg32 -Value '{ "note": "STALE-DOES-NOT-MATCH" }' -NoNewline

        $projF = Join-Path $work5 'F'; New-Item -ItemType Directory $projF | Out-Null
        Set-Content -LiteralPath (Join-Path $projF 'F.dproj') -Value '<Project/>' -NoNewline
        Set-Content -LiteralPath (Join-Path $projF 'F.pas')   -Value "unit F;`r`ninterface`r`nimplementation`r`nend."
        & $Exe index $projF --db (Join-Path $outE 'F.sqlite') | Out-Null

        $doc64 = Get-Content -LiteralPath $cfg64 -Raw | ConvertFrom-Json
        $doc64.indexes.sections = @($doc64.indexes.sections) + @(
            @{ name = 'F'; db = 'F.sqlite'; include = @((Join-Path $projF 'F.dproj')) })
        Set-Content -LiteralPath $cfg64 -Value ($doc64 | ConvertTo-Json -Depth 10)

        $mirrorOut = & $Exe migrate-dbs --config $cfg64 --apply 2>&1 | Out-String
        Check 'pair 10b: apply exits 0' ($LASTEXITCODE -eq 0)

        $bytes64 = [System.IO.File]::ReadAllBytes($cfg64)
        $bytes32 = [System.IO.File]::ReadAllBytes($cfg32)
        $identical = ($bytes64.Length -eq $bytes32.Length) -and (-not (Compare-Object $bytes64 $bytes32))
        Check 'pair 10b: win32 sibling mirrored to byte-identical' $identical
        Check 'pair 10b: output names the mirrored sibling' ($mirrorOut -match [regex]::Escape($cfg32))
    } finally {
        Remove-Item -Recurse -Force $work5 -ErrorAction SilentlyContinue
    }
} finally {
    Remove-Item -Recurse -Force $work -ErrorAction SilentlyContinue
}
if ($script:Failed) { exit 1 } else { exit 0 }
