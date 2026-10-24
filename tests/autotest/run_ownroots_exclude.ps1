# T-01 (docs\INBOX-ownroots-cannot-exclude-vendor.md): "excludeRoots" in
# <project>\_D-RAG\drag-lint-project.json carves a vendored subfolder out of an
# owned root. End-to-end through lint-all, on a TEMP COPY of
# tests\fixtures\own-roots-exclude (the selftest own-roots covers the path math).
try {
$Exe = . "$PSScriptRoot\_manifest_common.ps1"
$src  = "$PSScriptRoot\..\fixtures\own-roots-exclude\proj"
$work = Join-Path $env:TEMP ('draglint_ownroots_exclude_' + [guid]::NewGuid().ToString('N'))
Copy-Item -Recurse $src $work
$db  = Join-Path $work '_D-RAG\App.sqlite'
$rep = Join-Path $work 'report.txt'
& $Exe index $work --db $db 2>&1 | Out-Null
Check 'fixture indexed' (Test-Path $db)

# 1. Declared exclusion: vendor\ is skipped AND named; vendorX\ (prefix) stays ours.
$bare = & $Exe lint-all --db $db --output $rep --quiet 2>&1 | Out-String
$repText = Get-Content $rep -Raw
$anchored = @($repText -split "`r?`n" | Where-Object { $_ -match '\\vendor\\[^:]+:\d+:\d+' })
Check 'no finding anchored under the excluded root' ($anchored.Count -eq 0) $(if ($anchored.Count) { $anchored[0] })
Check 'skip line present'          ($bare -match "outside the project's own roots skipped")
Check 'skip block names vendor'    ($bare -match '(?m)^\s+1\s+\S+\\vendor\s*$')
Check 'POSITIVE CONTROL: own file still reported' ($repText -match 'Own\.pas.*unused-public-symbol')

# 2. --lint-third-party brings the excluded root back (proves the finding exists).
& $Exe lint-all --db $db --output $rep --quiet --lint-third-party 2>&1 | Out-Null
Check 'POSITIVE CONTROL: vendor finding exists when included' ((Get-Content $rep -Raw) -match 'Vend\.pas.*unused-public-symbol')

# 3. Without the key the vendor file is ours again (the key, not the layout, excludes it).
$decl = Join-Path $work '_D-RAG\drag-lint-project.json'
Set-Content -LiteralPath $decl -Value '{ "ownRoots": ["."] }' -NoNewline
& $Exe lint-all --db $db --output $rep --quiet 2>&1 | Out-Null
Check 'no excludeRoots -> vendor linted' ((Get-Content $rep -Raw) -match 'Vend\.pas.*unused-public-symbol')

# 4. Unusable declarations refuse (exit 2) instead of linting the wrong set.
Set-Content -LiteralPath $decl -Value '{ "ownRoots": ["."], "excludeRoots": "vendor" }' -NoNewline
$bad = & $Exe lint-all --db $db --output $rep --quiet 2>&1 | Out-String
Check 'non-array excludeRoots exits 2' ($LASTEXITCODE -eq 2)
Check 'non-array excludeRoots explains' ($bad -match 'excludeRoots')
Set-Content -LiteralPath $decl -Value '{ "excludeRoots": ["."] }' -NoNewline
$bad = & $Exe lint-all --db $db --output $rep --quiet 2>&1 | Out-String
Check 'excluding every own root exits 2' ($LASTEXITCODE -eq 2)

if ($script:Failed) { exit 1 } else { exit 0 }
} finally {
  if ($work -and (Test-Path -LiteralPath $work)) { Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue }
}
