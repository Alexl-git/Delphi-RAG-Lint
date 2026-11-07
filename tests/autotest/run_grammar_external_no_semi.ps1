<#
  run_grammar_external_no_semi.ps1 -- E-SHLOBJ-PARSE (1.46): a final `external L name '<string>'`
  without ';' parses before the next routine and before `end.`
  (docs\INBOX-d5-shlobj-parse-error.md; Delphi 5 shlobj.pas shipped five such lines), fixed in
  grammar tree-sitter-delphi13 branch lane/146-b2 (procExternal gains `kName literalString`).

  CASES (one unit each):
    shlobj      the five D5 lines, implementation section, then `end.`    RED on grammar v1.4.2
    intfForm    `function A: Integer; stdcall; external 'k32' name 'GetA'` in the interface  RED
    beforeAttr  no ';', then `[Attr]` on the next declaration             RED on grammar v1.4.2
  REGRESSION CONTROLS (parse on v1.4.2 and must stay clean):
    withSemi    the same declarations WITH ';', a string library, an index and a dependency
  ASSERTS: zero parser-error / syntax-error findings over the set, every routine is a symbol.
  POSITIVE CONTROL: `external lib` with neither ';' nor `name` stays a finding: only the name
  form was widened, and the zero is a real zero.

  Usage: pwsh -File tests/autotest/run_grammar_external_no_semi.ps1 [-Exe <path>]
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
  [string]$WorkDir = "C:\TEMP\drag-lint-extnosemi-$PID"
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

$libConst = "const`n  lib = 'lib.dll';`n"
# name -> @(interface text, implementation text, expected routine names)
$cases = [ordered]@{
  shlobj = @(
    ($libConst + "function A: Integer;`nfunction B: Integer;`nfunction C: Integer;`nprocedure D;`nfunction E: Integer;`nfunction F: Integer;"),
    ("function A; external lib name 'A1';`nfunction B; external lib name 'B1'`nfunction C; external lib name 'C1'`nfunction D2; external lib name 'C2'`nprocedure D; external lib name 'D1'`nfunction E; external lib name 'E1'`n"),
    @('A', 'B', 'C', 'D2', 'D', 'E'))
  intfForm = @(
    "function A: Integer; stdcall; external 'k32' name 'GetA'`nprocedure B; external 'k32' name 'GetB';",
    '',
    @('A', 'B'))
  beforeAttr = @(
    ($libConst + "procedure A; external lib name 'A1'`n[Attr]`nprocedure B;"),
    '',
    @('A', 'B'))
  withSemi = @(
    ($libConst + "function A: Integer; external lib name 'A1';`nfunction B: Integer; stdcall; external 'k32' name 'GetB';`nprocedure C; external lib index 5;`nprocedure D; external lib;`nprocedure E; cdecl; external lib name 'E1' dependency 'c++abi';"),
    '',
    @('A', 'B', 'C', 'D', 'E'))
}

function Write-Unit([string]$Dir, [string]$Name, [string]$Intf, [string]$Impl) {
  $t = "unit $Name;`n`ninterface`n`n$Intf`n`nimplementation`n`n$Impl`nend.`n"
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
  foreach ($k in $cases.Keys) { Write-Unit $good $k $cases[$k][0] $cases[$k][1] }
  # POSITIVE CONTROL: no ';' and no `name`: outside the widened form, a real syntax error.
  Write-Unit $bad 'libOnly' ($libConst + "function A: Integer; external lib`nfunction B: Integer; external lib;") ''

  $gdb = Join-Path $good 'g.sqlite'; $bdb = Join-Path $bad 'b.sqlite'
  Check 'index exits 0 (good)' ((Build-Db $good $gdb) -eq 0)
  Check 'index exits 0 (bad)' ((Build-Db $bad $bdb) -eq 0)

  $badHits = Get-ParseFindings $bad $bdb
  Check 'CONTROL `external lib` without ; or name raises a finding' ($badHits.Count -gt 0) "count=$($badHits.Count)"

  $hits = Get-ParseFindings $good $gdb
  Check 'ASSERT zero parser-error/syntax-error over the set' ($hits.Count -eq 0) `
    ("count={0} {1}" -f $hits.Count, (($hits | ForEach-Object { '{0}:L{1}' -f [IO.Path]::GetFileNameWithoutExtension($_.file_path), $_.start_line }) -join ','))

  Push-Location $good
  try {
    $j = & $Exe sql --db $gdb --query "SELECT f.path, s.name FROM symbols s JOIN files f ON f.id = s.file_id" --json 2>$null | Out-String
  } finally { Pop-Location }
  $rows = @()
  try { $rows = @(($j | ConvertFrom-Json).rows) } catch {}
  Check 'CONTROL symbols query returned rows' ($rows.Count -gt 0) "rows=$($rows.Count)"
  foreach ($k in $cases.Keys) {
    $mine = @($rows | Where-Object { [IO.Path]::GetFileNameWithoutExtension([string]$_[0]) -eq $k } | ForEach-Object { [string]$_[1] })
    $missing = @($cases[$k][2] | Where-Object { $n = $_; -not ($mine | Where-Object { $_ -ceq $n }) })
    Check "ASSERT ${k}: every routine is a symbol" ($missing.Count -eq 0) ("missing=" + ($missing -join ','))
  }
} finally {
  if (Test-Path $WorkDir) { try { [IO.Directory]::Delete($WorkDir, $true) } catch {} }
}
Write-Host ''
if ($script:Failed) { Write-Host 'RESULT: FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'RESULT: PASS' -ForegroundColor Green
exit 0
