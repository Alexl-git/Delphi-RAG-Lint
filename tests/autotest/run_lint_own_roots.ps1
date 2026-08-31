$Exe = . "$PSScriptRoot\_manifest_common.ps1"
$fx  = "$PSScriptRoot\..\fixtures\own-roots"

$ur = & $Exe selftest own-roots --dir $fx 2>&1 | Out-String
Check 'own-roots selftest' ($ur -match 'OWNROOTS-OK')

# Index the fixture project INTO its _D-RAG home, the way the real layout works.
$db = Join-Path $fx 'proj\_D-RAG\App.sqlite'
if (Test-Path $db) { Remove-Item -Force $db }
& $Exe index $fx --db $db | Out-Null
Check 'fixture indexed' (Test-Path $db)

$rep = Join-Path $env:TEMP 'draglint_ownroots_report.txt'

# 1. Bare run: vendor\ is outside the declared roots, so it is skipped and named.
$bare = & $Exe lint-all --db $db --output $rep --quiet 2>&1 | Out-String
# ANCHORED, not MENTIONED. This asserted `-notmatch 'Vendor\.pas'` until
# 2026-08-31, which conflated two different things: ownRoots governs which files
# are REPORTED ON, never which files a message may name.
#
# duplicate-global-decl was widened past ('const','var') that day and now sees
# `RunReport`, declared in both proj\App.pas and vendor\Vendor.pas. The finding
# is anchored in App.pas -- owned code, correctly reported -- and its message
# names the vendor path because a duplicate-declaration finding that will not
# say WHERE the other declaration lives is useless. Suppressing it would make
# the message read "declared in 2 units" and name only one of them.
#
# So the check now asserts the property it always meant: no finding is ANCHORED
# in a skipped root. A finding line begins `<path>:<line>:<col>`, so anchoring
# is testable exactly rather than by substring.
$anchoredInVendor = @($bare -split "`r?`n" | Where-Object { $_ -match '^[^\s]*\\vendor\\[^:]+:\d+:\d+' })
Check 'scan excludes vendor'   ($anchoredInVendor.Count -eq 0) `
  ($(if ($anchoredInVendor.Count) { $anchoredInVendor[0] } else { 'no finding anchored under vendor\' }))
Check 'POSITIVE CONTROL: the bare run produced findings at all' `
  ($bare -match '^[^\s]+:\d+:\d+' -or (Test-Path $rep)) `
  'a silent run would satisfy the exclusion check for the wrong reason'
Check 'skip line present'      ($bare -match "outside the project's own roots skipped")
Check 'skip NAMES the root'    ($bare -match 'vendor')
Check 'declared root included' ((Get-Content $rep -Raw) -match 'Shared\.pas|App\.pas')

# 1b. Fix 1 (2026-08-11 review): spec 4.5 says "the report file gets the same
#     block" -- the skip lines used to reach only the console (EmitStatusLine)
#     and never the report file, so an archived report looked clean even when
#     most of the project was silently out of scope. Assert on the REPORT
#     FILE, not stdout -- this is the assertion the old test was missing.
$repText = Get-Content $rep -Raw
Check 'skip line present in REPORT FILE' ($repText -match "outside the project's own roots skipped")
Check 'skip block in REPORT FILE names the root' ($repText -match 'vendor')

# 2. A project-wide rule must not pair our code with vendored code.
#    App.pas and Vendor.pas are exact clones; duplicate-code must stay silent.
#    CAUTION: TCloneChecker.CheckProject is handed the already-narrowed
#    FilePaths array (DRagLint.Diagnostics.CloneChecks.pas:457), so THIS
#    assertion alone is satisfied by the per-file SCAN filter and proves
#    nothing about the second (Findings-level) filter below -- deleting that
#    block still leaves this Check green. See 2b for the assertion that
#    actually pins it.
Check 'no clone across the boundary' ((Get-Content $rep -Raw) -notmatch 'duplicate-code')

# 2b. A STORE-BASED rule -- TProjectLintRules.Run (DRagLint.Lint.ProjectRules.pas:673)
#     walks AStore.GetAllFileIds directly, not FilePaths, so it evaluates
#     Vendor.pas regardless of the scan filter. unused-public-symbol (ON by
#     default) fires on Vendor.pas's exported RunReport -- verified empirically
#     against this fixture: with --lint-third-party the report carries
#     "Vendor.pas:5:1  [info] unused-public-symbol: ...", so its absence on the
#     bare run can ONLY be the second (Findings-level) filter doing its job.
Check 'store rule fires on our own dead export'  ((Get-Content $rep -Raw) -match 'App\.pas.*unused-public-symbol')
Check 'store rule silent on vendor dead export'  ((Get-Content $rep -Raw) -notmatch 'Vendor\.pas.*unused-public-symbol')

# 3. --lint-third-party restores the old behaviour.
$all = & $Exe lint-all --db $db --output $rep --quiet --lint-third-party 2>&1 | Out-String
Check 'third-party flag re-includes' ((Get-Content $rep -Raw) -match 'Vendor\.pas')
Check 'clone found when included'    ((Get-Content $rep -Raw) -match 'duplicate-code')
Check 'store rule fires on vendor when included' ((Get-Content $rep -Raw) -match 'Vendor\.pas.*unused-public-symbol')

# 4. An empty ownRoots is a usage error, not "own nothing".
$decl = Join-Path $fx 'proj\_D-RAG\drag-lint-project.json'
$keep = Get-Content $decl -Raw
try {
    Set-Content -LiteralPath $decl -Value '{ "ownRoots": [] }' -NoNewline
    $bad = & $Exe lint-all --db $db --output $rep --quiet 2>&1 | Out-String
    Check 'empty ownRoots exits 2'   ($LASTEXITCODE -eq 2)
    Check 'empty ownRoots explains'  ($bad -match 'ownRoots')
} finally { Set-Content -LiteralPath $decl -Value $keep -NoNewline }

# 5. LintAnchorDir's THIRD resolution path: no --project, and the DB is not
#    inside a _D-RAG folder at all -- the explicit-"db" escape hatch for a
#    read-only/network-share source tree (DRagLint.Index.Manifest.pas:1287-99,
#    "An explicit Db still wins"). Anchoring must fall through to the manifest
#    SECTION that pins this exact db path, resolving the owner to that
#    section's project folder. Proven the same way as 2b: a sibling "vendor"
#    folder OUTSIDE the resolved project folder must be skipped in the bare
#    run and restored under --lint-third-party -- that only happens if the
#    manifest fallback actually ran, since with no anchor at all (LintAnchorDir
#    returning '') TOwnRoots.Load('') is inactive and skips nothing.
$work5 = Join-Path $env:TEMP ('draglint_ownroots_manifest_' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory $work5 | Out-Null
try {
    $projM = Join-Path $work5 'projM'; New-Item -ItemType Directory $projM | Out-Null
    $venM  = Join-Path $work5 'vendorM'; New-Item -ItemType Directory $venM | Out-Null
    $outM  = Join-Path $work5 'out'; New-Item -ItemType Directory $outM | Out-Null
    Set-Content -LiteralPath (Join-Path $projM 'AppM.dproj') -Value '<Project/>' -NoNewline
    Set-Content -LiteralPath (Join-Path $projM 'AppM.pas')   -Value "unit AppM;`r`ninterface`r`nimplementation`r`nend."
    Set-Content -LiteralPath (Join-Path $venM  'VendorM.pas') -Value "unit VendorM;`r`ninterface`r`nimplementation`r`nend."

    # Explicit db, deliberately OUTSIDE any _D-RAG folder.
    $dbM = Join-Path $outM 'ExplicitM.sqlite'
    & $Exe index $projM --db $dbM | Out-Null
    & $Exe index $venM  --db $dbM | Out-Null
    Check 'manifest-fallback fixture indexed' (Test-Path $dbM)

    # LOCAL manifest (leading dot -- TManifestIO.Load walks UP from CWD to find
    # it, DRagLint.Index.Manifest.pas:940-954), placed in $work5 so the run
    # below (CWD = $work5) discovers it and merges it onto the real dev
    # manifest beside the exe -- a uniquely-named section, so nothing real
    # collides.
    $cfgM = Join-Path $work5 '.drag-lint.json'
    $jM = @{ indexes = @{ sections = @(
              @{ name = 'OwnRootsManifestFallbackTest'
                 include = @((Join-Path $projM 'AppM.dproj'))
                 db      = $dbM } ) } }
    Set-Content -LiteralPath $cfgM -Value ($jM | ConvertTo-Json -Depth 8)

    $repM = Join-Path $work5 'reportM.txt'
    Push-Location $work5
    try {
        $bareM = & $Exe lint-all --db $dbM --output $repM --quiet 2>&1 | Out-String
        Check 'manifest fallback: vendor sibling skipped' ($bareM -notmatch 'VendorM\.pas')
        Check 'manifest fallback: skip line present' ($bareM -match "outside the project's own roots skipped")

        $allM = & $Exe lint-all --db $dbM --output $repM --quiet --lint-third-party 2>&1 | Out-String
        Check 'manifest fallback: --lint-third-party restores vendor sibling' ((Get-Content $repM -Raw) -match 'VendorM\.pas')
    } finally { Pop-Location }
} finally {
    Remove-Item -Recurse -Force $work5 -ErrorAction SilentlyContinue
}

if ($script:Failed) { exit 1 } else { exit 0 }
