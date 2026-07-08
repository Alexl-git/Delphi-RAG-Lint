<#
  run_schema.ps1 -- Track 5.2 Task 4: `drag-lint schema --db PATH [--format json]`
  self-documenting LIVE index-schema dump (schema_version + tables + columns +
  row counts), READ-ONLY (never calls Migrate, never writes to the inspected DB).

  Indexes a tiny 2-unit fixture into a temp DB, then exercises the schema verb
  in both JSON and text form:

  (a) `schema --db $db --format json` parses as JSON; schema_version is present
      and > 0 (the index was just built by `index`, so Migrate has run and
      stamped a current schema_version).
  (b) The core tables are all present in the "tables" array: files, symbols,
      refs, unit_uses, schema_meta, type_ancestors, type_helpers.
  (c) Each table entry carries a "row_count" (Integer) and a "columns" array
      of {name,type} objects (spot-checked on "files").
  (d) A plain text `schema --db $db` (no --format) run exits 0 and prints a
      table list with row counts (schema_version line + at least one
      "<table> (<N> rows):" line per core table).

  Run vs a version of the exe that lacks the `schema` verb at all -> RED
  (verb not recognized, e.g. non-zero exit / usage-command-not-found style
  output) -- this file is written BEFORE DoSchema exists, per TDD.
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\drag-lint-schema"
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
# Absolutize -Exe up front (no Push-Location in this test, but matches the
# established convention across the autotest suite so -Exe always survives
# a relative invocation regardless of caller CWD).
$Exe = (Resolve-Path $Exe).Path
if (Test-Path $WorkDir) { Remove-Item -Recurse -Force $WorkDir }
New-Item -ItemType Directory $WorkDir | Out-Null

# Tiny 2-unit fixture: just enough for `index` to populate files/symbols/refs/
# unit_uses with at least one row each. Content doesn't matter beyond that --
# this test is about the schema DUMP, not about indexing correctness.
$UnitA = @'
unit uSchemaA;
interface
uses uSchemaB;
function Foo(const AWidth: Integer): Boolean;
implementation
function Foo(const AWidth: Integer): Boolean;
begin
  Result := AWidth > 0;
end;
end.
'@
$UnitB = @'
unit uSchemaB;
interface
function Bar: Integer;
implementation
function Bar: Integer;
begin
  Result := 42;
end;
end.
'@
function Write-Fixture([string]$Path, [string]$Body) {
  $norm = $Body -replace "`r`n", "`n" -replace "`n", "`r`n"
  [System.IO.File]::WriteAllText($Path, $norm, [System.Text.Encoding]::ASCII)
}

Write-Fixture (Join-Path $WorkDir 'uSchemaA.pas') $UnitA
Write-Fixture (Join-Path $WorkDir 'uSchemaB.pas') $UnitB
$db = Join-Path $WorkDir 'schema.sqlite'
& $Exe index $WorkDir --db $db 2>&1 | Out-Null
if (-not (Test-Path $db)) { Write-Host "FATAL: index did not produce a db at $db" -ForegroundColor Red; exit 2 }

Write-Host 'schema --format json' -ForegroundColor Cyan
# NOTE: stdout only -- the exe may emit diagnostic lines (e.g. manifest-load
# notices, FTS5 probe) on STDERR, which would corrupt JSON parsing if merged
# in via 2>&1. Capture stdout and stderr into separate files so the JSON
# payload stays pure.
$jsonStdout = Join-Path $WorkDir 'schema.json.out'
$jsonStderr = Join-Path $WorkDir 'schema.json.err'
$pj = Start-Process -FilePath $Exe -ArgumentList @('schema', '--db', $db, '--format', 'json') -NoNewWindow -Wait -PassThru `
  -RedirectStandardOutput $jsonStdout -RedirectStandardError $jsonStderr
$jsonOut = Get-Content $jsonStdout -Raw
$parsed = $null
$parseOk = $true
try { $parsed = $jsonOut | ConvertFrom-Json } catch { $parseOk = $false }
Check '--format json: output parses as JSON' $parseOk $jsonOut

if ($parseOk) {
  Check 'schema_version present and > 0' `
    (($null -ne $parsed.schema_version) -and ([int]$parsed.schema_version -gt 0)) `
    "schema_version=$($parsed.schema_version)"

  $tableNames = @($parsed.tables | ForEach-Object { $_.name })
  $coreTables = @('files', 'symbols', 'refs', 'unit_uses', 'schema_meta', 'type_ancestors', 'type_helpers')
  foreach ($t in $coreTables) {
    Check "core table present: $t" ($tableNames -contains $t) "tables=$($tableNames -join ',')"
  }

  $filesEntry = $parsed.tables | Where-Object { $_.name -eq 'files' } | Select-Object -First 1
  if ($null -ne $filesEntry) {
    Check 'files: row_count is present' ($null -ne $filesEntry.row_count) "row_count=$($filesEntry.row_count)"
    Check 'files: row_count > 0 (2 fixture units indexed)' ([int]$filesEntry.row_count -gt 0) "row_count=$($filesEntry.row_count)"
    $cols = @($filesEntry.columns | ForEach-Object { $_.name })
    Check 'files: columns array present and non-empty' ($cols.Count -gt 0) "columns=$($cols -join ',')"
    Check 'files: columns carry a type field' `
      ($null -ne ($filesEntry.columns | Select-Object -First 1).type) `
      ($filesEntry.columns | ConvertTo-Json -Compress)
  } else {
    Check 'files: table entry found in dump' $false
  }
}

Write-Host ''
Write-Host 'schema (text, default format)' -ForegroundColor Cyan
$p = Start-Process -FilePath $Exe -ArgumentList @('schema', '--db', $db) -NoNewWindow -Wait -PassThru `
  -RedirectStandardOutput (Join-Path $WorkDir 'text.out') -RedirectStandardError (Join-Path $WorkDir 'text.err')
$textOut = Get-Content (Join-Path $WorkDir 'text.out') -Raw
Check 'text mode: exit code 0' ($p.ExitCode -eq 0) "exit=$($p.ExitCode)"
Check 'text mode: prints schema_version line' ($textOut -match 'schema_version:\s*\d+') $textOut
foreach ($t in @('files', 'symbols', 'refs', 'unit_uses', 'schema_meta')) {
  Check "text mode: table line for $t with row count" ($textOut -match [regex]::Escape($t) + '\s*\(\d+\s*rows\)') $textOut
}

Write-Host ''
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
