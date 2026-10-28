<#
  run_query_text_near.ps1 -- XERJ item 4: `query --text P --near <QName> --hops N`.

  Restricts a text hit to routines within N hops of a seed symbol on the call graph
  (callers and callees, both directions). --hops default 2, max 3. --hops-uses adds
  unit-uses edges; --near-boost keeps every row and puts neighbourhood rows first.

  Fixture (unit nearx): Seed <- A <- B <- D (each calls the previous), C unrelated; every
  routine holds the phrase xjphrase. Unit nearu uses nearx, holds the phrase in U, calls nothing.

  Asserts (positive control = the run without --near returns every row):
    1. no --near: all 6 rows.
    2. --hops 1: Seed + A only (hit outside N hops excluded, inside kept).
    3. --hops 2: Seed, A, B.   --hops 3: Seed, A, B, D (never C, never U).
    4. default hops = 2.
    5. --hops 4 exits 2 with the refusal text; --near Missing exits 2 with a clear error.
    6. --hops-uses --hops 1 adds U (unit-uses edge).
    7. --near-boost --hops 1: all 6 rows, Seed and A first, hop= printed.
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\drag-lint-query-text-near-$PID"
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
function Write-Ascii([string]$Path, [string]$Body) {
  $norm = $Body -replace "`r`n", "`n" -replace "`n", "`r`n"
  [System.IO.File]::WriteAllText($Path, $norm, [System.Text.Encoding]::ASCII)
}
# Returns the routine tags (the word after 'xjphrase ') of every literal row, in output order.
function Tags([string[]]$QArgs) {
  $out = & $Exe query --text xjphrase --kind literal @QArgs --db $db 2>$null
  return @($out | Where-Object { $_ -match '\[pas/literal\]' } | ForEach-Object { if ($_ -match 'xjphrase (\w+)') { $Matches[1] } })
}
function Same($a, $b) { return ((($a | Sort-Object) -join ',') -eq (($b | Sort-Object) -join ',')) }

if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
$Exe = (Resolve-Path $Exe).Path
if (Test-Path $WorkDir) { [IO.Directory]::Delete($WorkDir, $true) }
$dir = Join-Path $WorkDir 'fx'
New-Item -ItemType Directory $dir | Out-Null

Write-Ascii (Join-Path $dir 'nearx.pas') @'
unit nearx;
interface
procedure Seed;
procedure A;
procedure B;
procedure C;
procedure D;
implementation
procedure Seed;
begin
  WriteLn('xjphrase Seed');
end;
procedure A;
begin
  Seed;
  WriteLn('xjphrase A');
end;
procedure B;
begin
  A;
  WriteLn('xjphrase B');
end;
procedure C;
begin
  WriteLn('xjphrase C');
end;
procedure D;
begin
  B;
  WriteLn('xjphrase D');
end;
end.
'@
Write-Ascii (Join-Path $dir 'nearu.pas') @'
unit nearu;
interface
procedure U;
implementation
uses nearx;
procedure U;
begin
  WriteLn('xjphrase U');
end;
end.
'@
$db = Join-Path $dir 'fx.sqlite'
& $Exe index $dir --db $db 2>&1 | Out-Null

Write-Host 'Positive control' -ForegroundColor Cyan
$r = Tags @()
Check 'no --near: all 6 rows' (Same $r @('Seed','A','B','C','D','U')) ($r -join ',')

Write-Host 'Hop restriction' -ForegroundColor Cyan
$r = Tags @('--near', 'nearx.Seed', '--hops', '1')
Check '--hops 1: Seed + A' (Same $r @('Seed','A')) ($r -join ',')
$r = Tags @('--near', 'nearx.Seed', '--hops', '2')
Check '--hops 2: Seed, A, B' (Same $r @('Seed','A','B')) ($r -join ',')
$r = Tags @('--near', 'nearx.Seed', '--hops', '3')
Check '--hops 3: Seed, A, B, D' (Same $r @('Seed','A','B','D')) ($r -join ',')
$r = Tags @('--near', 'nearx.Seed')
Check 'default hops is 2' (Same $r @('Seed','A','B')) ($r -join ',')
$r = Tags @('--near', 'nearx.D', '--hops', '1')
Check 'callees direction too: seed D --hops 1 = D + B' (Same $r @('D','B')) ($r -join ',')

Write-Host 'Refusals' -ForegroundColor Cyan
$out = & $Exe query --text xjphrase --near nearx.Seed --hops 4 --db $db 2>&1
Check '--hops 4 exits 2' ($LASTEXITCODE -eq 2) "exit=$LASTEXITCODE"
Check '--hops 4 refusal text' (($out -join ' ') -match '3 hops max; use impact --depth for wider') ($out -join ' | ')
$out = & $Exe query --text xjphrase --near nearx.Missing --db $db 2>&1
Check '--near Missing exits 2' ($LASTEXITCODE -eq 2) "exit=$LASTEXITCODE"
Check '--near Missing names the symbol' (($out -join ' ') -match 'nearx\.Missing') ($out -join ' | ')

Write-Host 'Uses edges and boost' -ForegroundColor Cyan
$r = Tags @('--near', 'nearx.Seed', '--hops', '1', '--hops-uses')
Check '--hops-uses adds U' (($r -contains 'U') -and ($r -contains 'Seed') -and ($r -contains 'A') -and ($r -notcontains 'C')) ($r -join ',')
$r = Tags @('--near', 'nearx.Seed', '--hops', '1', '--near-boost')
Check '--near-boost keeps all 6' (Same $r @('Seed','A','B','C','D','U')) ($r -join ',')
Check '--near-boost puts Seed, A first' ((@(@($r)[0..1]) | Sort-Object) -join ',' -eq 'A,Seed') ($r -join ',')
$out = & $Exe query --text xjphrase --kind literal --near nearx.Seed --hops 1 --near-boost --db $db 2>$null
Check '--near-boost prints hop=' ((@($out | Where-Object { $_ -match 'hop=1' }).Count -ge 1)) ''

Write-Host ''
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
} finally {
  foreach ($d in @("$env:TEMP\drag-lint-query-text-near-$PID")) { if (Test-Path -LiteralPath $d) { [IO.Directory]::Delete($d, $true) } }
}
