<#
  152b ST / O5: the index stores string values AS WRITTEN -- trailing spaces
  included. FireDAC's FormatOptions.StrsTrim (default True) trimmed every string
  parameter on write and every string field on fetch, so Blueprint4.dfm:8842
  Caption = 'OGP  ' was stored as 'OGP' and menu-tree --with-dfm answered
  differently from the table (default) and from the .dfm text
  (DRAGLINT_NO_FILE_FACTS=1). Fixed in ConnectWriter / ConnectReadOnly
  (DRagLint.Storage.FileMembership).

  A  stored bytes (length() computed inside SQLite, so no fetch trimming can
     hide it): dfm_properties Hint 'tail ' = 5, dfm_nav_props Caption 'OGP  ' = 5
     and 'Trailing  ' = 10, string_literals const 'Pad  ' = 5.
  B  read path: `sql --json` returns 'tail ' with its space (fetch side).
  C  identity: menu-tree --with-dfm --format paths byte-identical between the
     table (default) and the .dfm text readers (DRAGLINT_NO_FILE_FACTS=1), and
     the text shows 'OGP  '.
  K  controls (unchanged by the fix): 'Plain' = 5, '  lead' = 6 (leading spaces
     were never trimmed), and the fixture really has the padded values.

  RED on the 1.50.0-alpha base engine: A, B and C fail (A 'tail' = 4, 'OGP' = 3).
  Usage: pwsh -File tests/autotest/run_store_trailing_space.ps1 -Exe <drag-lint.exe>
#>
[CmdletBinding()]
param(
  [string] $Exe     = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
  [string] $WorkDir = "$env:TEMP\drag-lint-trailspace-$PID"
)
$ErrorActionPreference = 'Stop'
$script:Failed = 0
$script:Passed = 0
function Check([string]$Name, [bool]$Ok, [string]$Detail = '') {
  if ($Ok) { $script:Passed++; Write-Host "  [PASS] $Name" -ForegroundColor Green }
  else     { $script:Failed++; Write-Host "  [FAIL] $Name $Detail" -ForegroundColor Red }
}
if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
$Exe = (Resolve-Path $Exe).Path
if (Test-Path $WorkDir) { [IO.Directory]::Delete($WorkDir, $true) }
New-Item -ItemType Directory $WorkDir | Out-Null
$fix  = (Resolve-Path "$PSScriptRoot\..\fixtures\dfm-trailing-space").Path
$proj = Join-Path $fix 'TS152.dproj'
$db   = Join-Path $WorkDir 'ts152.sqlite'

function SqlRows([string]$Query) {
  $raw = & $Exe sql --db $db --query $Query --json 2>$null
  if ($LASTEXITCODE -ne 0) { return ,@() }
  $j = ($raw -join "`n") | ConvertFrom-Json
  return ,@($j.rows)
}
function StoredLen([string]$Query) {
  $r = SqlRows $Query
  if ($r.Count -ne 1) { return -1 }
  return [int]$r[0][0]
}

try {
  # K0: the fixture carries the padded values (a guard over a trimmed fixture is vacuous)
  $dfmText = [IO.File]::ReadAllText((Join-Path $fix 'uTS152Main.dfm'))
  $pasText = [IO.File]::ReadAllText((Join-Path $fix 'uTS152Main.pas'))
  Check 'K0 fixture has padded values' ($dfmText.Contains("Caption = 'OGP  '") -and $dfmText.Contains("Hint = 'tail '") -and $pasText.Contains("'Pad  '"))

  & $Exe index --project $proj --db $db 2>&1 | Out-Null
  Check 'A0 index exits 0' ($LASTEXITCODE -eq 0) "exit $LASTEXITCODE"

  $n = StoredLen "SELECT count(*) FROM dfm_properties"
  Check 'A0 dfm_properties has rows' ($n -gt 0) "rows=$n"

  $l = StoredLen "SELECT length(value_text) FROM dfm_properties WHERE name='Hint'"
  Check 'A1 dfm_properties Hint stored as tail+space (5)' ($l -eq 5) "len=$l"
  $l = StoredLen "SELECT length(value) FROM dfm_nav_props WHERE name='Caption' AND value LIKE 'OGP%'"
  Check 'A2 dfm_nav_props Caption OGP+2 spaces (5)' ($l -eq 5) "len=$l"
  $l = StoredLen "SELECT length(value) FROM dfm_nav_props WHERE name='Caption' AND value LIKE 'Trailing%'"
  Check 'A3 dfm_nav_props form Caption Trailing+2 spaces (10)' ($l -eq 10) "len=$l"
  $l = StoredLen "SELECT length(text) FROM string_literals WHERE kind='const' AND text LIKE 'Pad%'"
  Check 'A4 string_literals const Pad+2 spaces (5)' ($l -eq 5) "len=$l"

  $l = StoredLen "SELECT length(value) FROM dfm_nav_props WHERE name='Caption' AND value LIKE 'Plain%'"
  Check 'K1 control Plain unchanged (5)' ($l -eq 5) "len=$l"
  $l = StoredLen "SELECT length(value) FROM dfm_nav_props WHERE name='Caption' AND value LIKE '%lead'"
  Check 'K2 control leading spaces kept (6)' ($l -eq 6) "len=$l"

  $r = SqlRows "SELECT value_text FROM dfm_properties WHERE name='Hint'"
  $v = if ($r.Count -eq 1) { [string]$r[0][0] } else { '<none>' }
  Check 'B1 sql --json fetches tail+space' ($v -ceq 'tail ') "got [$v]"

  $on = (& $Exe menu-tree --project $proj --db $db --with-dfm --format paths 2>$null) -join "`n"
  $env:DRAGLINT_NO_FILE_FACTS = '1'
  try { $off = (& $Exe menu-tree --project $proj --db $db --with-dfm --format paths 2>$null) -join "`n" }
  finally { $env:DRAGLINT_NO_FILE_FACTS = $null }
  Check 'C0 menu-tree text path shows OGP+2 spaces' ($off.Contains("Main menu > OGP  `t")) 'text readers lost the value'
  Check 'C1 menu-tree --with-dfm table == text' (($on.Length -gt 0) -and ($on -ceq $off)) "table:[$on] text:[$off]"
}
finally {
  if (Test-Path $WorkDir) { [IO.Directory]::Delete($WorkDir, $true) }
}
Write-Host ("run_store_trailing_space: {0} passed, {1} failed" -f $script:Passed, $script:Failed)
if ($script:Failed -gt 0) { exit 1 }
exit 0
