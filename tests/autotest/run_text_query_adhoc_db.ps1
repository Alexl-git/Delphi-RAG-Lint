<#
  run_text_query_adhoc_db.ps1 -- a DB built by an ad-hoc `index <dir> --db <f>`
  supports `query --text`, exactly like a manifest-built one.

  WHAT THIS CLOSES:
    converter-editor-phase-g finding 2.7 claimed an ad-hoc DB carries no FTS
    tables, so text search silently returns nothing on it. Re-reading the code in
    session 23 said that should be impossible: the literal harvest is
    unconditional (DRagLint.Core.Indexer.pas:952-960) and the FTS5 DDL is part of
    the ordinary migration every writable open runs (DRagLint.Storage.Schema.pas:
    288-302) -- both since schema v10, which PREDATES the 2026-08-02 measurement.
    The likely explanation is that the measurement hit a pre-v10 DB kept alive by
    the fingerprint-less skip that has since been fixed.

    "Likely" is not "verified", which is why this exists rather than a note saying
    the finding was probably stale. If it ever regresses, start at DoQueryText
    (DRagLint.CLI.pas:3527-3561) and SearchText (Storage.SQLite.pas:4878).

  THE NEGATIVE CONTROL IS LOAD-BEARING:
    A text search that matched EVERYTHING would satisfy "the distinctive phrase
    was found" just as well as a correct one. So a phrase that appears nowhere
    must report no hits and exit 1. Without that, this suite would pass against a
    match-everything bug -- the same failure shape as a suppression test with no
    positive control.
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\drag-lint-text-adhoc"
)
$ErrorActionPreference = 'Stop'
$script:Failed = $false
function Check($n, $ok, $d = '') {
  $s = if ($ok) { 'PASS' } else { 'FAIL' }
  $c = if ($ok) { 'Green' } else { 'Red' }
  Write-Host ("  [{0}] {1} {2}" -f $s, $n, $d) -ForegroundColor $c
  if (-not $ok) { $script:Failed = $true }
}

if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
$Exe = (Resolve-Path $Exe).Path
if (Test-Path $WorkDir) { Remove-Item -Recurse -Force $WorkDir }
New-Item -ItemType Directory $WorkDir | Out-Null
$SrcDir = Join-Path $WorkDir 'src'
New-Item -ItemType Directory $SrcDir | Out-Null

# The phrase is deliberately unlike anything else in any index, so a hit cannot
# come from a stray match against another DB the CLI might auto-resolve.
$Phrase = 'Quokka manifold refused the ledger'

$FixtureBody = @'
unit uTextAdhoc;

interface

resourcestring
  SRefusal = 'Quokka manifold refused the ledger';

procedure Explode;

implementation

uses System.SysUtils;

procedure Explode;
begin
  raise Exception.Create('Quokka manifold refused the ledger, code 7');
end;

end.
'@
$file = Join-Path $SrcDir 'uTextAdhoc.pas'
$norm = ($FixtureBody -replace "`r`n", "`n") -replace "`n", "`r`n"
[System.IO.File]::WriteAllText($file, $norm, [System.Text.Encoding]::ASCII)

$Db = Join-Path $WorkDir 'adhoc.sqlite'
$idx = & $Exe index $SrcDir --db $Db 2>&1 | Out-String
if (-not (Test-Path $Db)) {
  Write-Host "FATAL: ad-hoc index produced no DB" -ForegroundColor Red
  Write-Host $idx
  exit 2
}
Write-Host ("  indexed -> {0}" -f $Db) -ForegroundColor DarkGray

# The FTS tables must actually be present in an ad-hoc DB -- that is the literal
# claim 2.7 made. `schema` reports the live table list.
$schema = & $Exe schema --db $Db 2>&1 | Out-String
$hasFts = $schema -match 'text_index|fts'

$hit  = & $Exe query --text $Phrase --substring --db $Db 2>&1 | Out-String
$hitRc = $LASTEXITCODE
$miss = & $Exe query --text 'Zzyzx nonexistent phrase Qqq' --substring --db $Db 2>&1 | Out-String
$missRc = $LASTEXITCODE

Write-Host ''
Write-Host 'An ad-hoc DB carries the text index' -ForegroundColor Cyan
Check 'schema lists an FTS/text table' $hasFts
Check 'the distinctive phrase is found'  ($hit -match 'uTextAdhoc\.pas') "rc=$hitRc"
Check 'a hit exits 0'                    ($hitRc -eq 0)                  "rc=$hitRc"

Write-Host ''
Write-Host 'CONTROL: text search is not matching everything' -ForegroundColor Cyan
Check 'a phrase that appears nowhere is NOT reported' (-not ($miss -match 'uTextAdhoc\.pas')) "rc=$missRc"
Check 'zero hits exits 1'                             ($missRc -eq 1)                        "rc=$missRc"
if ($miss -match 'uTextAdhoc\.pas') {
  Write-Host '  !! The control failed: a nonsense phrase matched, so the hit above' -ForegroundColor Yellow
  Write-Host '  !! proves nothing about the text index.' -ForegroundColor Yellow
}

Write-Host ''
if ($script:Failed) {
  Write-Host '--- index output ---' -ForegroundColor DarkGray; Write-Host $idx
  Write-Host '--- schema ---'       -ForegroundColor DarkGray; Write-Host $schema
  Write-Host 'FAIL' -ForegroundColor Red; exit 1
} else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
