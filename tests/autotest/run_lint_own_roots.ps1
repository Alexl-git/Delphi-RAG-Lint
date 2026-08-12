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
Check 'scan excludes vendor'   ($bare -notmatch 'Vendor\.pas')
Check 'skip line present'      ($bare -match "outside the project's own roots skipped")
Check 'skip NAMES the root'    ($bare -match 'vendor')
Check 'declared root included' ((Get-Content $rep -Raw) -match 'Shared\.pas|App\.pas')

# 2. A project-wide rule must not pair our code with vendored code.
#    App.pas and Vendor.pas are exact clones; duplicate-code must stay silent.
Check 'no clone across the boundary' ((Get-Content $rep -Raw) -notmatch 'duplicate-code')

# 3. --lint-third-party restores the old behaviour.
$all = & $Exe lint-all --db $db --output $rep --quiet --lint-third-party 2>&1 | Out-String
Check 'third-party flag re-includes' ((Get-Content $rep -Raw) -match 'Vendor\.pas')
Check 'clone found when included'    ((Get-Content $rep -Raw) -match 'duplicate-code')

# 4. An empty ownRoots is a usage error, not "own nothing".
$decl = Join-Path $fx 'proj\_D-RAG\drag-lint-project.json'
$keep = Get-Content $decl -Raw
try {
    Set-Content -LiteralPath $decl -Value '{ "ownRoots": [] }' -NoNewline
    $bad = & $Exe lint-all --db $db --output $rep --quiet 2>&1 | Out-String
    Check 'empty ownRoots exits 2'   ($LASTEXITCODE -eq 2)
    Check 'empty ownRoots explains'  ($bad -match 'ownRoots')
} finally { Set-Content -LiteralPath $decl -Value $keep -NoNewline }

if ($script:Failed) { exit 1 } else { exit 0 }
