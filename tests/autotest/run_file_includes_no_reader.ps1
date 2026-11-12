<#
  152b ST / O16c: file_includes has no engine reader. ISymbolStore.GetFileIncludes
  (149 EX2) had 0 callers in src\ and tests\ (drag-lint find-callers / usages
  2026-11-11), so the reader is removed from ISymbolStore and TSQLiteSymbolStore;
  the TABLE stays -- the indexer still writes it (PutFileFacts) and it is
  SQL-facing (`drag-lint sql`, `schema`), documented in Storage.Schema.pas.

  R1  DRagLint.Core.Interfaces.pas declares no GetFileIncludes.
  R2  DRagLint.Storage.SQLite.pas declares / implements no GetFileIncludes.
  K1  the table is still created (CREATE TABLE IF NOT EXISTS file_includes).
  K2  the indexer still writes it (INSERT INTO file_includes in PutFileFacts).
  K3  Storage.Schema.pas says the table is SQL-facing with no engine reader.
  K4  (with -Exe) an index of tests\fixtures\file-facts-149\facts still FILLS
      file_includes (rows > 0) -- the write path is untouched.

  RED on the 1.50.0-alpha base (aa372fdb0): R1, R2 and K3 fail.
  Usage: pwsh -File tests/autotest/run_file_includes_no_reader.ps1 [-Exe <drag-lint.exe>]
#>
[CmdletBinding()]
param(
  [string] $Exe     = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
  [string] $WorkDir = "$env:TEMP\drag-lint-fincnoreader-$PID"
)
$ErrorActionPreference = 'Stop'
$script:Failed = 0
$script:Passed = 0
function Check([string]$Name, [bool]$Ok, [string]$Detail = '') {
  if ($Ok) { $script:Passed++; Write-Host "  [PASS] $Name" -ForegroundColor Green }
  else     { $script:Failed++; Write-Host "  [FAIL] $Name $Detail" -ForegroundColor Red }
}
$repo = (Resolve-Path "$PSScriptRoot\..\..").Path
$intf   = [IO.File]::ReadAllText((Join-Path $repo 'src\core\DRagLint.Core.Interfaces.pas'))
$store  = [IO.File]::ReadAllText((Join-Path $repo 'src\storage\DRagLint.Storage.SQLite.pas'))
$schema = [IO.File]::ReadAllText((Join-Path $repo 'src\storage\DRagLint.Storage.Schema.pas'))

Check 'R1 ISymbolStore declares no GetFileIncludes' (-not ($intf -match '(?m)^\s*function\s+GetFileIncludes\b'))
Check 'R2 TSQLiteSymbolStore has no GetFileIncludes' (-not ($store -match '(?m)^\s*function\s+(TSQLiteSymbolStore\.)?GetFileIncludes\b'))
Check 'K1 file_includes table still created' ($store -match 'CREATE TABLE IF NOT EXISTS file_includes')
Check 'K2 file_includes still written' ($store -match 'INSERT INTO file_includes\(')
Check 'K3 Schema.pas documents file_includes as SQL-facing, no engine reader' ($schema -match 'file_includes has no engine reader')

if (Test-Path $Exe) {
  $fix = Join-Path $repo 'tests\fixtures\file-facts-149\facts'
  if (Test-Path $WorkDir) { [IO.Directory]::Delete($WorkDir, $true) }
  New-Item -ItemType Directory $WorkDir | Out-Null
  try {
    $db = Join-Path $WorkDir 'ff.sqlite'
    & $Exe index $fix --db $db 2>&1 | Out-Null
    $raw = & $Exe sql --db $db --query 'SELECT count(*) FROM file_includes' --json 2>$null
    $n = -1
    if ($LASTEXITCODE -eq 0) { $n = [int](($raw -join "`n") | ConvertFrom-Json).rows[0][0] }
    Check 'K4 index still fills file_includes' ($n -gt 0) "rows=$n"
  }
  finally { if (Test-Path $WorkDir) { [IO.Directory]::Delete($WorkDir, $true) } }
}
else { Write-Host "  [SKIP] K4 (no exe at $Exe)" }

Write-Host ("run_file_includes_no_reader: {0} passed, {1} failed" -f $script:Passed, $script:Failed)
if ($script:Failed -gt 0) { exit 1 }
exit 0
