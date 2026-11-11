<#
  run_x4r_dpr_receiver.ps1 -- wave 151 lane RB-A item X4-r (found by 150 X4, Found 2):
  a BARE call inside a routine that is not a method has NO receiver type.

  The implicit-Self rung of TypeReceiverCore (kind 1) answers the enclosing
  routine's parent. For a method that is its class (right); for a free routine
  in a .dpr it is the PROGRAM symbol, in a unit the UNIT symbol -- neither is a
  receiver the source wrote. The call still binds (same target); only
  call_edges.receiver_type_symbol_id must be NULL.

  Fixture tests\fixtures\x4r-dpr-receiver (folder index into a temp DB):
    R1  X4RProg.dpr   X4RDoIt  bare `X4RLocal`    -> receiver NULL, target X4RProg.X4RLocal
    R2  uX4RUnit.pas  X4RUnitPub bare `X4RUnitPriv` -> receiver NULL, target uX4RUnit.X4RUnitPriv
  POSITIVE CONTROLS (fail if the fix clears too much):
    C1  X4RProg.dpr   TX4RFoo.Baz bare `Bar` -> receiver class X4RProg.TX4RFoo
    C2  X4RProg.dpr   X4RDoIt `F.Bar`        -> receiver class X4RProg.TX4RFoo
  RED on the 151 base engine (1.49.0-alpha): R1 receiver = program:X4RProg, R2 = unit:uX4RUnit.
  `sql --json` rows are POSITIONAL arrays.
  Usage: pwsh -File tests\callresolve\run_x4r_dpr_receiver.ps1 [-Exe <drag-lint.exe>]
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\drag-lint-x4r-$PID"
)
$ErrorActionPreference = 'Stop'
$script:Failed = 0; $script:Passed = 0
function Check($n, $ok, $d = '') {
  $s = if ($ok) { 'PASS' } else { 'FAIL' }; $c = if ($ok) { 'Green' } else { 'Red' }
  Write-Host ("  [{0}] {1} {2}" -f $s, $n, $d) -ForegroundColor $c
  if ($ok) { $script:Passed++ } else { $script:Failed++ }
}
if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
$Exe = (Resolve-Path $Exe).Path
$Fx  = (Resolve-Path (Join-Path $PSScriptRoot '..\fixtures\x4r-dpr-receiver')).Path
New-Item -ItemType Directory -Force $WorkDir | Out-Null
$Db = Join-Path $WorkDir 'x4r.sqlite'
if (Test-Path $Db) { [IO.File]::Delete($Db) }
$null = & $Exe index $Fx --db $Db 2>&1
if ($LASTEXITCODE -ne 0) { Write-Host "FATAL: index exit $LASTEXITCODE" -ForegroundColor Red; exit 2 }

# Returns 'receiver|target' for the one call ref <name> at <file>:<line> ('-' = NULL), or '<n refs>'.
function Edge([string]$file, [int]$line, [string]$name) {
  $q = "SELECT COALESCE((SELECT kind||':'||qualified_name FROM symbols WHERE id=ce.receiver_type_symbol_id),'-'), " +
       "COALESCE((SELECT qualified_name FROM symbols WHERE id=ce.target_symbol_id),'-') " +
       "FROM refs r JOIN files f ON f.id=r.file_id LEFT JOIN call_edges ce ON ce.ref_id=r.id " +
       "WHERE f.path LIKE '%\$file' AND r.start_line=$line AND r.name_text='$name' AND r.kind='call'"
  $raw = & $Exe sql --db $Db --query $q --json --limit 50 2>$null
  if ($LASTEXITCODE -ne 0) { return '<sql failed>' }
  $j = ($raw | Where-Object { $_ -notmatch '^\(loaded' }) -join "`n" | ConvertFrom-Json
  $rows = @($j.rows)
  if ($rows.Count -ne 1) { return "<$($rows.Count) refs>" }
  return ('{0}|{1}' -f $rows[0][0], $rows[0][1])
}

Write-Host "== X4-r bare call in a non-method routine has no receiver ($Exe)"
$e = Edge 'X4RProg.dpr' 31 'X4RLocal';     Check 'R1 .dpr routine bare call: receiver NULL, bound to X4RProg.X4RLocal' ($e -eq '-|X4RProg.X4RLocal') "edge=$e"
$e = Edge 'uX4RUnit.pas' 18 'X4RUnitPriv'; Check 'R2 unit free routine bare call: receiver NULL, bound to uX4RUnit.X4RUnitPriv' ($e -eq '-|uX4RUnit.X4RUnitPriv') "edge=$e"
$e = Edge 'X4RProg.dpr' 20 'Bar';          Check 'C1 CONTROL bare call in a method keeps class receiver' ($e -eq 'class:X4RProg.TX4RFoo|X4RProg.TX4RFoo.Bar') "edge=$e"
$e = Edge 'X4RProg.dpr' 33 'Bar';          Check 'C2 CONTROL F.Bar keeps class receiver' ($e -eq 'class:X4RProg.TX4RFoo|X4RProg.TX4RFoo.Bar') "edge=$e"

Write-Host ("== {0} passed, {1} failed" -f $script:Passed, $script:Failed)
try { [IO.Directory]::Delete($WorkDir, $true) } catch { }
if ($script:Failed -gt 0) { exit 1 } else { exit 0 }