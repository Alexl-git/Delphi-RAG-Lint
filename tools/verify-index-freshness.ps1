<#
  verify-index-freshness.ps1 -- after a reindex, prove EVERY configured index is
  current, instead of eyeballing the log.

  WHY THIS EXISTS. `REINDEX_EXITCODE=0` says the RUN succeeded. It does not say
  every database is current: a section can be added to the manifest after the
  run reads it (that happened on 2026-09-08 -- two ConvRules sections were added
  2.5 min after the run started and were simply never visited), and a DB can be
  present, open cleanly, report a current schema and still answer for a
  different scope. Existence is not sufficiency.

  The standing rule in CLAUDE.md is "verify with info --json that every DB reads
  verdict=current -- do not eyeball the log". This is that check, mechanised.

  THE EXPECTED VERSION IS ASKED OF THE ENGINE, NEVER HARDCODED. A pinned literal
  becomes a stale baseline that silently passes after the next extractor bump --
  this repo has three recorded instances of a guard that could no longer fail.

  A field that cannot be PARSED is a FAILURE, not an unknown. A regex that stops
  matching would otherwise turn this into a check that always passes.

  Usage: pwsh -File tools\verify-index-freshness.ps1
         pwsh -File tools\verify-index-freshness.ps1 -Platforms Win64
  Exit 0 = every DB current. Exit 1 = at least one is not.
#>
[CmdletBinding()]
param(
    [string]   $Exe       = "$PSScriptRoot\..\third_party\dll-win64\drag-lint.exe",
    [string[]] $Platforms = @('Win32','Win64')
)
$ErrorActionPreference = 'Stop'
if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
$Exe = (Resolve-Path $Exe).Path

# The engine is the authority on what "current" means right now.
$engineRaw = (& $Exe info --json 2>&1) -join "`n"
if ($engineRaw -notmatch '"extractor_version":"([^"]+)"') {
    Write-Host "FATAL: could not read extractor_version from the engine -- cannot verify anything." -ForegroundColor Red
    exit 2
}
$expect = $matches[1]
Write-Host ("engine extractor_version = {0}" -f $expect) -ForegroundColor Cyan
Write-Host ''

# Union of every DB the manifest resolves for the given platforms.
$dbs = @()
foreach ($plat in $Platforms) {
    $dbs += (& $Exe resolve-dbs --platform $plat 2>&1) |
            Where-Object { $_ -match '\.sqlite\s*$' } |
            ForEach-Object { $_.Trim() }
}
$dbs = @($dbs | Sort-Object -Unique)
Write-Host ("resolved {0} database(s) across platform(s): {1}" -f $dbs.Count, ($Platforms -join ', '))
Write-Host ''

$bad = @()
foreach ($db in $dbs) {
    $raw = (& $Exe info --json --db $db 2>&1) -join "`n"

    # An unparseable field is a failure. Never default it to something benign.
    $verdict = if ($raw -match '"verdict":"([^"]+)"')            { $matches[1] } else { $null }
    $fp      = if ($raw -match '"indexer_fingerprint":"([^"]+)"'){ $matches[1] } else { $null }
    $present = if ($raw -match '"present":(true|false)')         { $matches[1] } else { $null }

    $name = Split-Path $db -Leaf
    $ok   = ($present -eq 'true') -and ($verdict -eq 'current') -and ($fp -and $fp.Contains("v=$expect"))

    if ($ok) {
        Write-Host ("  [OK]   {0}" -f $name) -ForegroundColor Green
    } else {
        $why = @()
        if ($null -eq $present)      { $why += 'present unparseable' }
        elseif ($present -ne 'true') { $why += 'NOT PRESENT' }
        if ($null -eq $verdict)      { $why += 'verdict unparseable' }
        elseif ($verdict -ne 'current') { $why += "verdict=$verdict" }
        if ($null -eq $fp)           { $why += 'fingerprint unparseable' }
        elseif (-not $fp.Contains("v=$expect")) { $why += "fingerprint=$fp" }
        Write-Host ("  [BAD]  {0} -- {1}" -f $name, ($why -join '; ')) -ForegroundColor Red
        Write-Host ("         {0}" -f $db) -ForegroundColor DarkGray
        $bad += $db
    }
}

Write-Host ''
if ($bad.Count -eq 0) {
    Write-Host ("ALL {0} INDEX(ES) CURRENT at v={1}" -f $dbs.Count, $expect) -ForegroundColor Green
    exit 0
}
Write-Host ("{0} of {1} INDEX(ES) NOT CURRENT:" -f $bad.Count, $dbs.Count) -ForegroundColor Red
foreach ($b in $bad) { Write-Host ("  {0}" -f $b) -ForegroundColor Red }
Write-Host ''
Write-Host 'Refresh a project index with:  drag-lint index --project <x.dproj> --db <db>' -ForegroundColor Yellow
Write-Host 'NEVER `index <dir> --db <projectDb>` -- that widens a project DB into a directory DB.' -ForegroundColor Yellow
exit 1
