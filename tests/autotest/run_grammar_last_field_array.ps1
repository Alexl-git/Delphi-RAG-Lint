<#
  run_grammar_last_field_array.ps1 -- GRAMMAR-LASTFIELD (1.42): the LAST record field of an
  ARRAY type with no ';' before 'end' parses (docs\INBOX-grammar-last-field-array-no-semi.md),
  fixed in grammar tree-sitter-delphi13 v1.4.1 (declFieldNoSemi gains a constrained
  _declArrayNoSemi whose element excludes string types).

  CASES (one unit each):
    lastArr        `B: array [0..3] of Byte` + end            (FireDAC.Phys.MongoDBCli:140 shape)  RED on v1.4.0
    lastPackedArr  `B: packed array [0..MAX_PATH-1] of Char` + end (Winapi.ShlObj:11068 shape)     RED on v1.4.0
    lastArrOnly    the array field is the ONLY field, no ';'                                         RED on v1.4.0
  REGRESSION CONTROLS (parse on v1.4.0 and must stay clean):
    shortStrArr    `B: array [0..4] of String[1];` last WITH ';', and not last (ORM3 Z19b5 / OoMisc)
    shortStr       `S: string[255];` last WITH ';'
    plainNoSemi    `B: Integer` + end (the plain no-semi form)
    platformFirst  a record whose FIRST field is named Platform (ContextFile:43/47, grammar v1.4.0)
  ASSERTS: zero parser-error / syntax-error findings over the set, and every field is a symbol.
  POSITIVE CONTROL: a broken twin (missing ':') raises a finding, so the zero is a real zero.

  Usage: pwsh -File tests/autotest/run_grammar_last_field_array.ps1 [-Exe <path>]
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
  [string]$WorkDir = "C:\TEMP\drag-lint-lastfield-$PID"
)
$ErrorActionPreference = 'Continue'
$script:Failed = $false
function Check($n, $ok, $d = '') {
  $s = if ($ok) { 'PASS' } else { 'FAIL' }; $c = if ($ok) { 'Green' } else { 'Red' }
  Write-Host ("  [{0}] {1} {2}" -f $s, $n, $d) -ForegroundColor $c
  if (-not $ok) { $script:Failed = $true }
}
if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
$Exe = (Resolve-Path $Exe).Path

# name -> @(interface text, expected field names)
$cases = [ordered]@{
  lastArr       = @("type`n  TA = record`n    A: Integer;`n    B: array [0..3] of Byte`n  end;", @('A', 'B'))
  lastPackedArr = @("const`n  MAX_PATH = 260;`ntype`n  TB = record`n    A: Integer;`n    B: packed array [0..MAX_PATH-1] of Char`n  end;", @('A', 'B'))
  lastArrOnly   = @("type`n  TC = record`n    Pad: array [0 .. 83] of Byte`n  end;", @('Pad'))
  shortStrArr   = @("type`n  TD = record`n    A: Integer;`n    B: array [0..4] of String[1];`n  end;`n  TE = record`n    B2: Array[0..4] of String[1];`n    C2: Integer;`n  end;", @('A', 'B', 'B2', 'C2'))
  shortStr      = @("type`n  TF = record`n    A: Integer;`n    S: string[255];`n  end;", @('A', 'S'))
  plainNoSemi   = @("type`n  TG = record`n    A: Integer;`n    B: Integer`n  end;", @('A', 'B'))
  platformFirst = @("type`n  TH = record`n    Platform: string;`n    Config: string;`n  end;`n  TI = record`n    Platform, Config: string;`n  end;", @('Platform', 'Config'))
}

function Write-Unit([string]$Dir, [string]$Name, [string]$Intf) {
  $t = "unit $Name;`n`ninterface`n`n$Intf`n`nimplementation`n`nend.`n"
  [IO.File]::WriteAllText((Join-Path $Dir "$Name.pas"), ($t -replace "`r?`n", "`r`n"), [Text.Encoding]::ASCII)
}

function Get-ParseFindings([string]$Dir, [string]$Db) {
  $all = @()
  Push-Location $Dir
  try {
    foreach ($r in 'parser-error', 'syntax-error') {
      $raw = & $Exe lint $Dir --db $Db --rule $r --json 2>$null | Out-String
      try { $all += @($raw | ConvertFrom-Json) } catch {}
    }
  } finally { Pop-Location }
  return @($all | Where-Object { $_.rule -in 'parser-error', 'syntax-error' })
}

function Build-Db([string]$Dir, [string]$Db) {
  Push-Location $Dir
  try { $null = & $Exe index $Dir --db $Db --library-db none --rule-cache-warm off 2>&1 } finally { Pop-Location }
  return $LASTEXITCODE
}

try {
  if (Test-Path $WorkDir) { [IO.Directory]::Delete($WorkDir, $true) }
  $good = Join-Path $WorkDir 'good'; $bad = Join-Path $WorkDir 'bad'
  [void][IO.Directory]::CreateDirectory($good); [void][IO.Directory]::CreateDirectory($bad)
  foreach ($k in $cases.Keys) { Write-Unit $good $k $cases[$k][0] }
  # POSITIVE CONTROL twin: the plain record with a missing ':' -- a real syntax error.
  Write-Unit $bad 'plainNoSemi' ($cases['plainNoSemi'][0] -replace 'A: Integer;', 'A Integer;')

  $gdb = Join-Path $good 'g.sqlite'; $bdb = Join-Path $bad 'b.sqlite'
  Check 'index exits 0 (good)' ((Build-Db $good $gdb) -eq 0)
  Check 'index exits 0 (bad)' ((Build-Db $bad $bdb) -eq 0)

  $badHits = Get-ParseFindings $bad $bdb
  Check 'CONTROL broken twin raises parser-error/syntax-error' ($badHits.Count -gt 0) "count=$($badHits.Count)"

  $hits = Get-ParseFindings $good $gdb
  Check 'ASSERT zero parser-error/syntax-error over the last-field set' ($hits.Count -eq 0) `
    ("count={0} {1}" -f $hits.Count, (($hits | ForEach-Object { '{0}:L{1}' -f [IO.Path]::GetFileNameWithoutExtension($_.file_path), $_.start_line }) -join ','))

  Push-Location $good
  try {
    $j = & $Exe sql --db $gdb --query "SELECT f.path, s.name FROM symbols s JOIN files f ON f.id = s.file_id" --json 2>$null | Out-String
  } finally { Pop-Location }
  $rows = @()
  try { $rows = @(($j | ConvertFrom-Json).rows) } catch {}
  foreach ($k in $cases.Keys) {
    $mine = @($rows | Where-Object { [IO.Path]::GetFileNameWithoutExtension([string]$_[0]) -eq $k } | ForEach-Object { [string]$_[1] })
    $missing = @($cases[$k][1] | Where-Object { $n = $_; -not ($mine | Where-Object { $_ -ceq $n }) })
    Check "ASSERT ${k}: every field is a symbol" ($missing.Count -eq 0) ("missing=" + ($missing -join ','))
  }
} finally {
  if (Test-Path $WorkDir) { try { [IO.Directory]::Delete($WorkDir, $true) } catch {} }
}
Write-Host ''
if ($script:Failed) { Write-Host 'RESULT: FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'RESULT: PASS' -ForegroundColor Green
exit 0
