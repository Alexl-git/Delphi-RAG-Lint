<#
  run_dpr_own_calls.ps1 -- wave 150 lane X4 (found by X1): calls to routines DECLARED IN A .dpr resolve,
  and a program / library root is never dead-code.

  Fixture tests\fixtures\x4-dpr-calls-150 (folder index into a temp DB; `sql --json` rows are POSITIONAL):
    A1  X4Prog.dpr main block `X4ProgHelper(...)` (line 25)  -> bound to X4Prog.X4ProgHelper.
    A2  X4Lib.dpr  main block `X4LibAdd(1, 2)`    (line 23)  -> bound to X4Lib.X4LibAdd.
    A3  X4Lib.dpr  exports    `X4LibAdd name ...` (line 20)  -> bound to X4Lib.X4LibAdd.
    A4  find-callers X4ProgHelper is an EXACT caller at X4Prog.dpr:25 (was [name-only]).
    B1  find-deadcode does not list the roots `X4Prog [program]` / `X4Lib [program]`.
    B2  find-deadcode does not list a routine the root calls (X4ProgHelper, X4ProgLocal, X4LibAdd).
  RED on the lane base (75f3ec6fb): A1-A4 unbound / name-only; B1 lists both roots.
  POSITIVE CONTROLS: X4ProgDead / X4LibDead (declared in the .dpr, never called) are STILL listed by
  find-deadcode and have no call edge; the in-routine call X4ProgLocal (line 16) and the cross-unit
  call X4UnitTwice (line 25) stay bound to the same targets as before.
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\drag-lint-x4-dpr-calls-$PID"
)
$ErrorActionPreference = 'Stop'
$script:Failed = 0; $script:Passed = 0
function Check($n, $ok, $d = '') {
  $s = if ($ok) { 'PASS' } else { 'FAIL' }; $c = if ($ok) { 'Green' } else { 'Red' }
  Write-Host ("  [{0}] {1}" -f $s, $n) -ForegroundColor $c
  if ($ok) { $script:Passed++ } else { $script:Failed++; if ($d) { Write-Host "      $d" -ForegroundColor DarkGray } }
}
if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
$Exe = (Resolve-Path $Exe).Path
$Fx  = (Resolve-Path (Join-Path $PSScriptRoot '..\fixtures\x4-dpr-calls-150')).Path
New-Item -ItemType Directory -Force $WorkDir | Out-Null
$Db = Join-Path $WorkDir 'dprcalls.sqlite'
if (Test-Path $Db) { [IO.File]::Delete($Db) }

$null = & $Exe index $Fx --db $Db 2>&1
if ($LASTEXITCODE -ne 0) { Write-Host "FATAL: index exit $LASTEXITCODE" -ForegroundColor Red; exit 2 }

function Rows([string]$q) {
  $raw = & $Exe sql --db $Db --query $q --json --limit 500 2>$null
  if ($LASTEXITCODE -ne 0) { return ,@() }
  $j = ($raw | Where-Object { $_ -notmatch '^\(loaded' }) -join "`n" | ConvertFrom-Json
  return ,@($j.rows)
}
# The qualified name the call ref at <file>:<line> named <name> is bound to (call_edges), or '' when unbound.
function Target([string]$file, [int]$line, [string]$name) {
  $r = Rows ("SELECT (SELECT s.qualified_name FROM call_edges ce JOIN symbols s ON s.id=ce.target_symbol_id WHERE ce.ref_id=r.id) " +
             "FROM refs r JOIN files f ON f.id=r.file_id WHERE f.path LIKE '%\$file' AND r.start_line=$line " +
             "AND r.name_text='$name' AND r.kind='call'")
  if ($r.Count -ne 1) { return "<$($r.Count) refs>" }
  return [string]$r[0][0]
}

Write-Host "== X4 .dpr own-routine calls + root liveness ($Exe)"

$t = Target 'X4Prog.dpr' 25 'X4ProgHelper'; Check 'A1 program main-block call bound to X4Prog.X4ProgHelper' ($t -eq 'X4Prog.X4ProgHelper') "target=$t"
$t = Target 'X4Lib.dpr'  23 'X4LibAdd';     Check 'A2 library main-block call bound to X4Lib.X4LibAdd'     ($t -eq 'X4Lib.X4LibAdd') "target=$t"
$t = Target 'X4Lib.dpr'  20 'X4LibAdd';     Check 'A3 library exports entry bound to X4Lib.X4LibAdd'       ($t -eq 'X4Lib.X4LibAdd') "target=$t"
$fc = (& $Exe query find-callers --name X4ProgHelper --db $Db 2>$null) -join "`n"
Check 'A4 find-callers X4ProgHelper: exact caller at X4Prog.dpr:25' (($fc -match 'X4Prog\.dpr:25:') -and ($fc -match '1 caller\(s\) \(1 exact\)')) ($fc -split "`n" | Select-Object -Last 1)

$t = Target 'X4Prog.dpr' 16 'X4ProgLocal'; Check 'CONTROL in-routine call still bound to X4Prog.X4ProgLocal' ($t -eq 'X4Prog.X4ProgLocal') "target=$t"
$t = Target 'X4Prog.dpr' 25 'X4UnitTwice'; Check 'CONTROL cross-unit call still bound to uX4Unit.X4UnitTwice' ($t -eq 'uX4Unit.X4UnitTwice') "target=$t"
$d = Rows "SELECT COUNT(*) FROM call_edges ce JOIN symbols s ON s.id=ce.target_symbol_id WHERE s.name IN ('X4ProgDead','X4LibDead')"
Check 'CONTROL no call edge targets X4ProgDead / X4LibDead' ($d.Count -eq 1 -and $d[0][0] -eq 0)

# find-deadcode prints `<qname>  [<kind>]  <path>:<line>` per candidate (no --json).
$dead = @(& $Exe find-deadcode --db $Db 2>$null | Where-Object { $_ -match '\s\[\w+\]\s' } | ForEach-Object { ($_ -split '\s+')[0] })
Check 'B1 find-deadcode does not list the program root X4Prog' ($dead -notcontains 'X4Prog') ($dead -join ', ')
Check 'B1 find-deadcode does not list the library root X4Lib'  ($dead -notcontains 'X4Lib')  ($dead -join ', ')
$live = @($dead | Where-Object { $_ -in 'X4Prog.X4ProgHelper','X4Prog.X4ProgLocal','X4Lib.X4LibAdd' })
Check 'B2 find-deadcode does not list a routine the root calls / exports' ($live.Count -eq 0) ($live -join ', ')
Check 'CONTROL find-deadcode still lists X4Prog.X4ProgDead' ($dead -contains 'X4Prog.X4ProgDead') ($dead -join ', ')
Check 'CONTROL find-deadcode still lists X4Lib.X4LibDead'   ($dead -contains 'X4Lib.X4LibDead')   ($dead -join ', ')

Write-Host ("== {0} passed, {1} failed" -f $script:Passed, $script:Failed)
if ($script:Failed -gt 0) { exit 1 } else { exit 0 }
