<#
  run_index_facts_use_preprocessed_parse.ps1 -- during `index`, symbol_facts is
  computed from the SAME preprocessed parse the symbols come from.

  THE PROBLEM (found 2026-09-28 while measuring index throughput). The facts
  analyzer takes its tree from TAstParseCache, and only lint / lint-all ever
  handed that cache the define profile. So under `index` every symbol came from
  the preprocessed parse while every symbol_facts row next to it came from a
  RAW re-parse -- in which the grammar keeps the FIRST branch of an IFDEF. A
  routine whose inactive first branch holds the logic got that branch's
  cyclomatic complexity, reads/writes and SQL, and its active branch's none.

  THE FIX (extractor 1.20.0-alpha). TIndexer.SetPreprocess hands the same switch
  and profile to TAstParseCache.

  Usage: pwsh -File tests/autotest/run_index_facts_use_preprocessed_parse.ps1 [-Exe <path>]
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\drag-lint-facts-pp-$PID"
)
try {
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
New-Item -ItemType Directory (Join-Path $WorkDir 'src') | Out-Null

function Write-Ascii([string]$Path, [string]$Body) {
  $norm = $Body -replace "`r`n", "`n" -replace "`n", "`r`n"
  [System.IO.File]::WriteAllText($Path, $norm, [System.Text.Encoding]::ASCII)
}

# The first (inactive) branch carries three decisions; the taken ELSE carries none.
Write-Ascii (Join-Path $WorkDir 'src\uPP.pas') @'
unit uPP;

interface

procedure Branchy(A, B, C: Boolean; var X: Integer);

implementation

procedure Branchy(A, B, C: Boolean; var X: Integer);
begin
{$IFDEF DRAGLINT_NEVER_DEFINED}
  if A then X := 1;
  if B then X := 2;
  if C then X := 3;
{$ELSE}
  X := 0;
{$ENDIF}
end;

end.
'@

$db = Join-Path $WorkDir 'pp.sqlite'
& $Exe index (Join-Path $WorkDir 'src') --db $db --quiet 2>&1 | Out-Null
Check 'precondition: index exits 0' ($LASTEXITCODE -eq 0) "exit=$LASTEXITCODE"

$py = Join-Path $WorkDir 'cyc.py'
Write-Ascii $py @'
import sqlite3, sys
c = sqlite3.connect(sys.argv[1])
r = c.execute("""select f.cyclomatic from symbol_facts f join symbols s on s.id = f.symbol_id
  where s.qualified_name = 'uPP.Branchy' and ifnull(f.body_loc, 0) > 0""").fetchall()
print(r[0][0] if r else '')
'@
$cyc = ((python $py $db) -join '').Trim()
Check 'precondition: Branchy has a facts row' ($cyc -ne '') "cyclomatic='$cyc'"
Check 'ASSERT: cyclomatic comes from the TAKEN branch (1), not the inactive first one (4)' ($cyc -eq '1') "cyclomatic=$cyc"

Write-Host ''
if ($script:Failed) { Write-Host 'RESULT: FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'RESULT: PASS' -ForegroundColor Green
exit 0
} finally {
  foreach ($d in @("$env:TEMP\drag-lint-facts-pp-$PID")) { if (Test-Path -LiteralPath $d) { Remove-Item -LiteralPath $d -Recurse -Force -ErrorAction SilentlyContinue } }
}
