<#
  run_purity_storage.ps1 -- the three purity columns exist on symbol_facts
  after Migrate, start NULL, survive a second index run, and PutSymbolFacts
  never writes them (per-file reindex leaves them NULL for the stage to fill).

  POSITIVE CONTROL: check 4 asserts the columns are ABSENT from the prepared
  INSERT OR REPLACE column list by reading the engine's own source -- if a
  later edit adds them to FQPutSymbolFacts, this fails, because a per-file
  reindex would then silently reset a verdict the stage had written.
  Run from a NEUTRAL CWD (C:\TEMP), pwsh 7.
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\draglint_purity_storage"
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
$Exe  = (Resolve-Path $Exe).Path
$repo = (Resolve-Path "$PSScriptRoot\..\..").Path
if (Test-Path $WorkDir) { [System.IO.Directory]::Delete($WorkDir, $true) }
New-Item -ItemType Directory $WorkDir | Out-Null
$src = Join-Path $WorkDir 'src'
New-Item -ItemType Directory $src | Out-Null
function Emit([string]$name, [string]$text) {
  [System.IO.File]::WriteAllText((Join-Path $src $name),
    (($text -replace "`r`n", "`n") -replace "`n", "`r`n"), [System.Text.Encoding]::ASCII)
}
Emit 'uOne.pas' @'
unit uOne;
interface
function AddUp(A, B: Integer): Integer;
implementation
function AddUp(A, B: Integer): Integer;
begin
  Result := A + B;
end;
end.
'@
$db = Join-Path $WorkDir 's.sqlite'
# `drag-lint sql` refuses PRAGMA (incl. pragma_table_info), so the column list
# is read from sqlite_master: SQLite rewrites the stored CREATE TABLE text on
# every ALTER TABLE ... ADD COLUMN, so Migrate's retrofitted columns show here.
$colSql = "SELECT sql FROM sqlite_master WHERE type = 'table' AND name = 'symbol_facts'"
Push-Location C:\TEMP
try {
  $null = & $Exe index $src --db $db 2>&1
  Check '1. fixture indexed' (Test-Path $db) $db
  $cols = (& $Exe sql --db $db --format text --query $colSql 2>&1) -join "`n"
  Check '2. effect_free / effect_summary / effect_witness columns exist' `
    (($cols -match '\beffect_free\b') -and ($cols -match '\beffect_summary\b') -and ($cols -match '\beffect_witness\b')) ($cols -replace '\s+', ' ')
  # Nothing in the index run writes them: every routine row (body_loc > 0)
  # starts with all three NULL -- the shape the purity stage's gate looks for.
  $nulls = (& $Exe sql --db $db --format text --query "SELECT count(*) FROM symbol_facts WHERE ifnull(body_loc, 0) > 0 AND effect_free IS NULL AND effect_summary IS NULL AND effect_witness IS NULL" 2>&1) -join "`n"
  $rows  = (& $Exe sql --db $db --format text --query "SELECT count(*) FROM symbol_facts WHERE ifnull(body_loc, 0) > 0" 2>&1) -join "`n"
  $nNull = [int]([regex]::Match($nulls, '^\s*(\d+)\s*$', 'Multiline').Groups[1].Value)
  $nRows = [int]([regex]::Match($rows,  '^\s*(\d+)\s*$', 'Multiline').Groups[1].Value)
  Check '2b. the columns start NULL on every routine row (index never writes them)' `
    (($nRows -ge 1) -and ($nNull -eq $nRows)) "rows=$nRows null=$nNull"
  $null = & $Exe index $src --db $db 2>&1
  $cols2 = (& $Exe sql --db $db --format text --query $colSql 2>&1) -join "`n"
  $nulls2 = (& $Exe sql --db $db --format text --query "SELECT count(*) FROM symbol_facts WHERE ifnull(body_loc, 0) > 0 AND effect_free IS NULL AND effect_summary IS NULL AND effect_witness IS NULL" 2>&1) -join "`n"
  $nNull2 = [int]([regex]::Match($nulls2, '^\s*(\d+)\s*$', 'Multiline').Groups[1].Value)
  Check '3. a second index run keeps the columns AND leaves them NULL (Migrate is idempotent, PutSymbolFacts does not touch them)' `
    (($cols2 -match '\beffect_witness\b') -and ($nNull2 -eq $nRows)) "null=$nNull2 rows=$nRows"

  # 5. A schema-23 DB indexed BEFORE purity v2 has no effect_* columns, still
  #    reads as schema-current, and a READ-ONLY open never runs Migrate -- so
  #    every reader must tolerate the columns being ABSENT, not only NULL.
  #    Fixture: index a second DB with THIS engine, then DROP the three columns
  #    through python's sqlite3 (drag-lint sql is read-only by design). The
  #    precondition (5a) proves the fixture really lacks them, so 5b cannot
  #    pass vacuously against a DB that still has the columns.
  $db2 = Join-Path $WorkDir 'legacy.sqlite'
  $null = & $Exe index $src --db $db2 2>&1
  $py = Get-Command python -ErrorAction SilentlyContinue
  if ($null -eq $py) {
    Check '5a. legacy fixture: python (sqlite3) available to drop the columns' $false 'python not on PATH -- cannot build the column-less fixture'
  } else {
    $drop = "import sqlite3; c = sqlite3.connect(r'$db2'); [c.execute('ALTER TABLE symbol_facts DROP COLUMN ' + n) for n in ('effect_free', 'effect_summary', 'effect_witness')]; c.commit(); c.close()"
    $pyOut = (& python -c $drop 2>&1) -join "`n"
    $cols5 = (& $Exe sql --db $db2 --format text --query $colSql 2>&1) -join "`n"
    Check '5a. legacy fixture lacks the three columns (precondition for 5b)' `
      (($cols5 -match '\bwiring\b') -and ($cols5 -notmatch 'effect_free') -and ($cols5 -notmatch 'effect_summary') -and ($cols5 -notmatch 'effect_witness')) $pyOut
    # document --unit WITHOUT --apply is a preview: read-only open, reaches
    # GetSymbolFacts for every public decl (Doc.Facts), writes nothing.
    $docOut = (& $Exe document --unit (Join-Path $src 'uOne.pas') --db $db2 --json 2>&1) -join "`n"
    $docExit = $LASTEXITCODE
    Check '5b. read-only verb on the column-less DB: exit 0, no "no such column"' `
      (($docExit -eq 0) -and ($docOut -notmatch 'no such column')) ("exit=$docExit " + (($docOut -split "`n" | Where-Object { $_ -match 'FATAL|no such column|error' } | Select-Object -First 1)))
    # A WRITABLE open migrates the columns back in (the path that lets the
    # purity stage fill them on the next index run).
    $null = & $Exe index $src --db $db2 2>&1
    $cols5c = (& $Exe sql --db $db2 --format text --query $colSql 2>&1) -join "`n"
    Check '5c. a writable index run on the legacy DB adds the columns (Migrate ALTER)' ($cols5c -match '\beffect_witness\b') ''
  }
} finally { Pop-Location }
# POSITIVE CONTROL against the source: the prepared UPSERT must not name them.
# The capture must be the REAL column list -- it names the table and a known
# stored column -- so a refactor that moved the list into a const (leaving the
# NewQuery(...) argument free of column names) fails here instead of passing
# vacuously.
$sqlite = [System.IO.File]::ReadAllText((Join-Path $repo 'src\storage\DRagLint.Storage.SQLite.pas'))
$upsert = [regex]::Match($sqlite, "FQPutSymbolFacts:= NewQuery\((.*?)\);", 'Singleline').Groups[1].Value
Check '4. FQPutSymbolFacts does NOT write the three columns' `
  (($upsert -match 'INSERT OR REPLACE INTO symbol_facts') -and ($upsert -match '\bwiring\b') -and ($upsert -notmatch 'effect_free') -and ($upsert -notmatch 'effect_summary') -and ($upsert -notmatch 'effect_witness')) ''
Write-Host ''
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
