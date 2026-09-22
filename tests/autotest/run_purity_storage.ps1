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
  Check '3. a second index run keeps the columns (Migrate is idempotent)' ($cols2 -match '\beffect_witness\b') ''
} finally { Pop-Location }
# POSITIVE CONTROL against the source: the prepared UPSERT must not name them.
$sqlite = [System.IO.File]::ReadAllText((Join-Path $repo 'src\storage\DRagLint.Storage.SQLite.pas'))
$upsert = [regex]::Match($sqlite, "FQPutSymbolFacts:= NewQuery\((.*?)\);", 'Singleline').Groups[1].Value
Check '4. FQPutSymbolFacts does NOT write the three columns' `
  (($upsert -ne '') -and ($upsert -notmatch 'effect_free') -and ($upsert -notmatch 'effect_summary') -and ($upsert -notmatch 'effect_witness')) ''
Write-Host ''
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
