<#
  run_unused_unit_init_section.ps1 -- 145 lane lf: unused-unit-in-uses reads the used unit's
  initialization SECTION refs (F2) instead of treating every section as a hazard.

  RULE: a used unit with an initialization section stays INFO "VERIFY BEFORE REMOVING" unless the
  section's enclosed refs prove it idle (only the unit's own variables/constants) -> WARNING.
  A section that references anything else stays INFO and the message NAMES what it references.
  GATE: the library DB must carry the resolver that backfills section refs (1.20.0-alpha); an older
  DB has no section refs, so an empty section would be indistinguishable from a real one -> plain INFO.

  POSITIVE CONTROLS: the idle unit must turn WARNING (fails on the old rule); the active unit must
  name its callee (fails on the old rule); the finalization unit and the OLD-resolver library copy
  must stay INFO (a rule that downgraded everything would pass the first check alone).

  Usage: pwsh -File tests\autotest\run_unused_unit_init_section.ps1 [-Exe <new>] [-OldExe <older engine>]
#>
[CmdletBinding()]
param(
  [string]$Exe = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
  [string]$OldExe = '',
  [string]$WorkDir = "$env:TEMP\draglint_uu_initsec_$PID"
)
$ErrorActionPreference = 'Stop'
$script:Failed = $false
function Check([string]$n, [bool]$ok, [string]$d = '') {
  Write-Host ("  [{0}] {1} {2}" -f $(if ($ok) { 'PASS' } else { 'FAIL' }), $n, $d) -ForegroundColor $(if ($ok) { 'Green' } else { 'Red' })
  if (-not $ok) { $script:Failed = $true }
}
function Write-Ascii([string]$Path, [string]$Body) {
  [IO.File]::WriteAllText($Path, ($Body -replace "`r`n", "`n" -replace "`n", "`r`n"), [Text.Encoding]::ASCII)
}
$Exe = (Resolve-Path $Exe).Path
if (Test-Path $WorkDir) { [IO.Directory]::Delete($WorkDir, $true) }
$lib = Join-Path $WorkDir 'lib'; $prj = Join-Path $WorkDir 'prj'
[void][IO.Directory]::CreateDirectory($lib); [void][IO.Directory]::CreateDirectory($prj)

Write-Ascii (Join-Path $lib 'uIdleInit.pas') @'
unit uIdleInit;

interface

var
  GFlag: Boolean;

procedure IdleExport;

implementation

procedure IdleExport;
begin
end;

initialization
  GFlag := False;

end.
'@
Write-Ascii (Join-Path $lib 'uRegInit.pas') @'
unit uRegInit;

interface

procedure RegExport;

implementation

procedure RegisterThing;
begin
end;

procedure RegExport;
begin
end;

initialization
  RegisterThing;

end.
'@
Write-Ascii (Join-Path $lib 'uFinInit.pas') @'
unit uFinInit;

interface

var
  GFlag2: Boolean;

procedure FinExport;

implementation

procedure FinExport;
begin
end;

initialization
  GFlag2 := False;

finalization
  GFlag2 := True;

end.
'@
Write-Ascii (Join-Path $prj 'uHost.pas') @'
unit uHost;

interface

uses
  uIdleInit, uRegInit, uFinInit;

implementation

end.
'@

function Run-Lint([string]$Engine, [string]$LibDb, [string]$PrjDb, [string]$Tag) {
  $rep = Join-Path $WorkDir "rep-$Tag.txt"
  $dbs = @('--db', $PrjDb); if ($LibDb) { $dbs += @('--db', $LibDb) }
  & $Engine lint-all @dbs --output $rep 2>&1 | Out-Null
  $o = if (Test-Path $rep) { Get-Content $rep -Raw } else { '' }
  return @(($o -split "`n") | Where-Object { $_ -match 'unused-unit-in-uses' })
}
function Line([object[]]$Lines, [string]$Unit) { return (($Lines | Where-Object { $_ -match "'$Unit'" }) -join "`n") }

$libDb = Join-Path $WorkDir 'lib.sqlite'; $prjDb = Join-Path $WorkDir 'prj.sqlite'
& $Exe index $lib --db $libDb 2>&1 | Out-Null
& $Exe index $prj --db $prjDb 2>&1 | Out-Null
$new = Run-Lint $Exe $libDb $prjDb 'new'
$idle = Line $new 'uIdleInit'; $reg = Line $new 'uRegInit'; $fin = Line $new 'uFinInit'
Write-Host '== unused-unit-in-uses: initialization section refs ==' -ForegroundColor Cyan
Check 'the rule fires for all three units (control: not vacuous)' (($idle -ne '') -and ($reg -ne '') -and ($fin -ne '')) "idle=$($idle.Length) reg=$($reg.Length) fin=$($fin.Length)"
Check 'idle section (only GFlag := False) -> WARNING, dead import' (($idle -match 'warning') -and ($idle -notmatch 'VERIFY BEFORE REMOVING'))
Check 'active section (calls RegisterThing) stays INFO and NAMES the callee' (($reg -match 'VERIFY BEFORE REMOVING') -and ($reg -match 'RegisterThing') -and ($reg -notmatch 'warning'))
Check 'section + finalization stays plain INFO (control: not everything downgraded)' (($fin -match 'VERIFY BEFORE REMOVING') -and ($fin -notmatch 'references:'))

# GATE: a library DB stamped by a resolver older than the section-ref backfill (1.20.0-alpha) has no
# section refs, so its empty-looking sections must read as UNKNOWN. The stamp is lowered in a COPY
# of the scratch library DB (python's sqlite3, -I isolated mode).
$py = Get-Command python -ErrorAction SilentlyContinue
if ($py) {
  $oldLib = Join-Path $WorkDir 'oldlib.sqlite'
  Copy-Item $libDb $oldLib
  $stamp = & $py.Source -I -c "import sqlite3,sys;c=sqlite3.connect(sys.argv[1]);r=c.execute(`"select value from schema_meta where key='resolver_fingerprint'`").fetchone();v=r[0].replace('r=1.20.0-alpha','r=1.19.0-alpha');c.execute(`"update schema_meta set value=? where key='resolver_fingerprint'`",(v,));c.commit();print(v)" $oldLib
  Check 'setup: copy stamped with the older resolver' ($stamp -match 'r=1\.19\.0-alpha') "$stamp"
  $old = Run-Lint $Exe $oldLib $prjDb 'oldlib'
  $oi = Line $old 'uIdleInit'
  Check 'GATE: library DB from an older resolver -> unknown -> plain INFO, never WARNING' (($oi -match 'VERIFY BEFORE REMOVING') -and ($oi -notmatch 'warning') -and ($oi -notmatch 'references:'))
} else { Write-Host '  [SKIP] old-resolver gate (no python)' -ForegroundColor Yellow }
$none = Run-Lint $Exe '' $prjDb 'nolib'
Check 'no library DB: no section finding, no crash' ((Line $none 'uIdleInit') -eq '')

if ($script:Failed) { Write-Host 'UU INIT SECTION GUARD: FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'UU INIT SECTION GUARD: PASS' -ForegroundColor Green
if (-not $env:KEEP) { [IO.Directory]::Delete($WorkDir, $true) }
exit 0
