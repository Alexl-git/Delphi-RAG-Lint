<#
  run_generic_constraint_typeuse.ps1 -- wave 151 lane RB-A item 2 (150 RB2-d residual): the last
  unbound IMicObject type_use on ORM3 CLIENT, uMicObjectBase.pas:32
  `TMicObjectBase<I: IMicObject> = class(TComponent, IMicObject)`.

  Cause: LookupTypeName's scope walk asks NamesGenericParam whether the scope's generic
  parameter list names the type; it split the WHOLE list text ('I: IMicObject') into tokens,
  so the CONSTRAINT matched and the heritage use was declined 'generic'.

  Fixture tests\fixtures\rba-generic-constraint-typeuse (folder index into a temp DB):
    G1  uMicXBase.pas:20 heritage IMicX of the generic class -> bound, to the SAME symbol as G2
    G2  uMicXBase.pas:23 heritage IMicX of a plain class      -> bound (CONTROL, green on the base)
  POSITIVE CONTROL (fails if parameter names stop shadowing):
    C1  uMicXBase.pas:27 `function Get: TItem` inside TBox<TItem: IMicX> -> unbound (a parameter)
    C2  uMicXBase.pas:32 the implementation header's `: TItem`            -> unbound (a parameter)
  RED on the 151 base engine (1.49.0-alpha): G1 unbound.
  `sql --json` rows are POSITIONAL arrays.
  Usage: pwsh -File tests\callresolve\run_generic_constraint_typeuse.ps1 [-Exe <drag-lint.exe>]
#>
[CmdletBinding()]
param(
  [string]$Exe     = '',
  [string]$WorkDir = "$env:TEMP\drag-lint-gencons-$PID"
)
# Defaults that need the script path are resolved HERE, not in param(): Windows PowerShell 5 run with
# -File leaves $PSScriptRoot/$MyInvocation empty inside an advanced script's param block (Repo became C:\).
if (-not $Exe) { $Exe = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe" }
$ErrorActionPreference = 'Stop'
$script:Failed = 0; $script:Passed = 0
function Check($n, $ok, $d = '') {
  $s = if ($ok) { 'PASS' } else { 'FAIL' }; $c = if ($ok) { 'Green' } else { 'Red' }
  Write-Host ("  [{0}] {1} {2}" -f $s, $n, $d) -ForegroundColor $c
  if ($ok) { $script:Passed++ } else { $script:Failed++ }
}
if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
$Exe = (Resolve-Path $Exe).Path
$Fx  = (Resolve-Path (Join-Path $PSScriptRoot '..\fixtures\rba-generic-constraint-typeuse')).Path
New-Item -ItemType Directory -Force $WorkDir | Out-Null
$Db = Join-Path $WorkDir 'gencons.sqlite'
if (Test-Path $Db) { [IO.File]::Delete($Db) }
$null = & $Exe index $Fx --db $Db 2>&1
if ($LASTEXITCODE -ne 0) { Write-Host "FATAL: index exit $LASTEXITCODE" -ForegroundColor Red; exit 2 }

# symbol id ('-' = NULL) of the one type_use <name> at uMicXBase.pas:<line>, or '<n refs>'.
function Bound([int]$line, [string]$name, [int]$minCol = 0) {
  $q = "SELECT COALESCE(r.symbol_id,'-') FROM refs r JOIN files f ON f.id=r.file_id " +
       "WHERE f.path LIKE '%\uMicXBase.pas' AND r.start_line=$line AND r.name_text='$name' AND r.kind='type_use' AND r.start_col>=$minCol"
  $raw = & $Exe sql --db $Db --query $q --json --limit 50 2>$null
  if ($LASTEXITCODE -ne 0) { return '<sql failed>' }
  $j = ($raw | Where-Object { $_ -notmatch '^\(loaded' }) -join "`n" | ConvertFrom-Json
  $rows = @($j.rows)
  if ($rows.Count -ne 1) { return "<$($rows.Count) refs>" }
  return [string]$rows[0][0]
}

Write-Host "== generic constraint is not a parameter name ($Exe)"
$g2 = Bound 23 'IMicX'
Check 'G2 CONTROL plain-class heritage IMicX bound' ($g2 -match '^\d+$') "symbol=$g2"
# v1511 EXT B26 (b9bd649d7) also emits the CONSTRAINT <I: IMicX> (col 16) as a type_use, so line 20
# holds two IMicX refs: G1 reads the HERITAGE one (col >= 30, after 'class(TComponent, ').
$g1 = Bound 20 'IMicX' 30
Check 'G1 generic-class heritage IMicX bound to the same symbol as G2' (($g1 -match '^\d+$') -and ($g1 -eq $g2)) "symbol=$g1"
$g3 = Bound 20 'IMicX'
Check 'G3 line 20 carries exactly the constraint + heritage IMicX refs (EXT B26)' ($g3 -eq '<2 refs>') "got=$g3"
$c1 = Bound 27 'TItem'; Check 'C1 CONTROL TItem in TBox<TItem: IMicX> stays a parameter (unbound)' ($c1 -eq '-') "symbol=$c1"
$c2 = Bound 32 'TItem'; Check 'C2 CONTROL implementation header TItem stays a parameter (unbound)' ($c2 -eq '-') "symbol=$c2"

Write-Host ("== {0} passed, {1} failed" -f $script:Passed, $script:Failed)
try { [IO.Directory]::Delete($WorkDir, $true) } catch { }
if ($script:Failed -gt 0) { exit 1 } else { exit 0 }