<#
  run_init_dependency_facts.ps1 -- 1.52.1 lane INITDEP: init-dependency facts in the index and their
  use by unused-unit-in-uses. Spec: docs\superpowers\specs\2026-11-19-init-dependency-facts-design.md.

  FACT (A1-A3): the calls pass writes init_deps -- one row per (unit, other unit its initialization
  section reaches, through same-file routines too), '?' for an unbound non-intrinsic ref -- and stamps
  schema_meta init_deps_format = 1.
  RULE (A4-A7): an unused import whose registration lands in a unit the project reaches WITHOUT it is
  not reported; one whose complete facts land nowhere live is a WARNING naming the target (even when
  the allow-list would skip it); incomplete facts / an unstamped DB fall back to the old handling.

  POSITIVE CONTROLS: uOrphanReg and dxSkinFakeReg MUST fire (a rule that suppressed every init unit
  would pass the negative checks alone); the unstamped copy MUST give uReg the old INFO finding.

  Usage: pwsh -File tests\autotest\run_init_dependency_facts.ps1 [-Exe <engine>]
#>
[CmdletBinding()]
param(
  [string]$Exe = '',
  [string]$WorkDir = "$env:TEMP\draglint_initdep_$PID"
)
if (-not $Exe) { $Exe = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe" }
$ErrorActionPreference = 'Stop'
$script:Failed = $false
function Check([string]$n, [bool]$ok, [string]$d = '') {
  Write-Host ("  [{0}] {1} {2}" -f $(if ($ok) { 'PASS' } else { 'FAIL' }), $n, $d) -ForegroundColor $(if ($ok) { 'Green' } else { 'Red' })
  if (-not $ok) { $script:Failed = $true }
}
function Write-Ascii([string]$Path, [string]$Body) {
  [IO.File]::WriteAllText($Path, ($Body -replace "`r`n", "`n" -replace "`n", "`r`n"), [Text.Encoding]::ASCII)
}
function Lib-Unit([string]$Name, [string]$Uses, [string]$Impl, [string]$Init) {
  $u = if ($Uses) { "uses`n  $Uses;`n" } else { '' }
  $i = if ($Init) { "initialization`n  $Init`n" } else { '' }
  Write-Ascii (Join-Path $lib "$Name.pas") "unit $Name;`n`ninterface`n`n$($u)`nprocedure $($Name)Export;`n`nimplementation`n`nprocedure $($Name)Export;`nbegin`nend;`n`n$Impl`n$($i)`nend.`n"
}
$Exe = (Resolve-Path $Exe).Path
if (Test-Path $WorkDir) { [IO.Directory]::Delete($WorkDir, $true) }
$lib = Join-Path $WorkDir 'lib'; $prj = Join-Path $WorkDir 'prj'
[void][IO.Directory]::CreateDirectory($lib); [void][IO.Directory]::CreateDirectory($prj)

# Registries: uRegistry is used by the project (uConsumer); uLonely by nobody but its registrants.
Lib-Unit 'uRegistry' '' '' ''
Lib-Unit 'uLonely'   '' '' ''
Lib-Unit 'uLonely2'  '' '' ''
Lib-Unit 'uLonely3'  '' '' ''
# One registry per orphan: a registrant's own uses would otherwise make a sibling's target reachable
# (the accepted mutual-drag limit of the spec).
# uReg registers into uRegistry THROUGH a same-file routine (A2).
Lib-Unit 'uReg'       'uRegistry' "procedure RegisterAll;`nbegin`n  uRegistryExport;`nend;`n" 'RegisterAll;'
Lib-Unit 'uOrphanReg' 'uLonely'   '' 'uLonelyExport;'
# Allow-listed by name (dxskin prefix), registers into uLonely2: facts win over the allow-list.
Lib-Unit 'dxSkinFakeReg' 'uLonely2' '' 'uLonely2Export;'
# Reaches uLonely3 AND an unbound name: incomplete facts, nothing live -> fallback (A6).
Lib-Unit 'uIncomplete' 'uLonely3' '' "uLonely3Export;`n  SomethingNobodyDeclares;"

Write-Ascii (Join-Path $prj 'uConsumer.pas') "unit uConsumer;`n`ninterface`n`nuses`n  uRegistry;`n`nprocedure Go;`n`nimplementation`n`nprocedure Go;`nbegin`n  uRegistryExport;`nend;`n`nend.`n"
Write-Ascii (Join-Path $prj 'uHost.pas') "unit uHost;`n`ninterface`n`nuses`n  uReg, uOrphanReg, dxSkinFakeReg, uIncomplete;`n`nimplementation`n`nend.`n"

function Run-Lint([string]$LibDb, [string]$PrjDb, [string]$Tag) {
  $rep = Join-Path $WorkDir "rep-$Tag.txt"
  & { $ErrorActionPreference = 'Continue'; & $Exe lint-all --db $PrjDb --db $LibDb --output $rep 2>&1 | ForEach-Object { "$_" } } | Out-Null
  $o = if (Test-Path $rep) { Get-Content $rep -Raw } else { '' }
  return @(($o -split "`n") | Where-Object { $_ -match 'unused-unit-in-uses' })
}
function Line([object[]]$Lines, [string]$Unit) { return (($Lines | Where-Object { $_ -match "'$Unit'" }) -join "`n") }
function Sql([string]$Db, [string]$Q) {
  return (& { $ErrorActionPreference = 'Continue'; & $Exe sql --query $Q --db $Db --json 2>$null } | Out-String)
}

$libDb = Join-Path $WorkDir 'lib.sqlite'; $prjDb = Join-Path $WorkDir 'prj.sqlite'
& { $ErrorActionPreference = 'Continue'; & $Exe index $lib --db $libDb 2>&1 | ForEach-Object { "$_" } } | Out-Null
& { $ErrorActionPreference = 'Continue'; & $Exe index $prj --db $prjDb 2>&1 | ForEach-Object { "$_" } } | Out-Null

Write-Host '== init-dependency facts: the index ==' -ForegroundColor Cyan
$stamp = Sql $libDb "SELECT value FROM schema_meta WHERE key = 'init_deps_format'"
Check 'A1 stamp init_deps_format = 1' ($stamp -match '"1"') ($stamp -replace '\s+', ' ')
$rows = Sql $libDb "SELECT u.name || '>' || d.target_unit FROM init_deps d JOIN symbols u ON u.id = d.unit_symbol_id ORDER BY 1"
Check 'A1 uOrphanReg > uLonely' ($rows -match 'uOrphanReg>uLonely') ($rows -replace '\s+', ' ')
Check 'A2 uReg > uRegistry (through RegisterAll)' ($rows -match 'uReg>uRegistry')
Check 'A3 uIncomplete carries the ? row' ($rows -match 'uIncomplete>\?')
Check 'A3 control: uReg has no ? row (own routine is followed, not unknown)' ($rows -notmatch 'uReg>\?')

Write-Host '== init-dependency facts: unused-unit-in-uses ==' -ForegroundColor Cyan
$new = @(Run-Lint $libDb $prjDb 'new')
$reg = Line $new 'uReg'; $orph = Line $new 'uOrphanReg'; $skin = Line $new 'dxSkinFakeReg'; $inc = Line $new 'uIncomplete'
Check 'A4 uReg: registry reached by uConsumer -> no finding' ($reg -eq '') "$reg"
Check 'A5 POSITIVE CONTROL uOrphanReg -> WARNING naming uLonely' (($orph -match 'warning') -and ($orph -match 'uLonely') -and ($orph -match 'init-dependency facts')) "$orph"
Check 'A5 POSITIVE CONTROL facts win over the allow-list: dxSkinFakeReg -> WARNING' (($skin -match 'warning') -and ($skin -match 'uLonely2')) "$skin"
Check 'A6 uIncomplete: incomplete facts -> fallback (old INFO, not the facts message)' (($inc -match 'VERIFY BEFORE REMOVING') -and ($inc -notmatch 'init-dependency facts')) "$inc"

# A7: a library DB without the stamp (an index from before 1.52.1) behaves exactly as before.
$py = Get-Command python -ErrorAction SilentlyContinue
if ($py) {
  $oldLib = Join-Path $WorkDir 'oldlib.sqlite'
  Copy-Item $libDb $oldLib
  & $py.Source -I -c "import sqlite3,sys;c=sqlite3.connect(sys.argv[1]);c.execute('delete from schema_meta where key=?',('init_deps_format',));c.commit()" $oldLib
  $old = @(Run-Lint $oldLib $prjDb 'old')
  $oreg = Line $old 'uReg'; $oskin = Line $old 'dxSkinFakeReg'
  Check 'A7 POSITIVE CONTROL unstamped: uReg back to the old INFO finding' (($oreg -match 'VERIFY BEFORE REMOVING') -and ($oreg -notmatch 'init-dependency facts')) "$oreg"
  Check 'A7 unstamped: dxSkinFakeReg skipped by the allow-list again' ($oskin -eq '') "$oskin"
} else { Write-Host '  [SKIP] A7 unstamped copy (no python)' -ForegroundColor Yellow }

if ($script:Failed) { Write-Host 'INIT DEPENDENCY FACTS GUARD: FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'INIT DEPENDENCY FACTS GUARD: PASS' -ForegroundColor Green
if (-not $env:KEEP) { [IO.Directory]::Delete($WorkDir, $true) }
exit 0
