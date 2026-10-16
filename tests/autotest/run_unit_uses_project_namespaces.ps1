<#
  run_unit_uses_project_namespaces.ps1 -- a PROJECT index resolves a bare `uses`
  name through the project's own unit scope names (DCC_Namespace).

  THE PROBLEM (ProjectA, 2026-09-29). `uses Dialogs` in a VCL project means
  Vcl.Dialogs -- dcc resolves it through the project's DCC_Namespace list, and
  ProjectA even keeps a local copy of Vcl.Dialogs.pas. ResolveUnitUseTargets'
  rule B infers a scope prefix only when exactly one indexed stem carries the
  name AND it is not a GUI framework (it cannot know which framework a project
  uses), so the row stayed NULL and the uses graph never reached that file.

  THE FIX (resolver 1.16.0-alpha). A project-scoped index records the .dproj's
  DCC_Namespace (MSBuild's four groups, in dcc's search order) in schema_meta,
  and a new rule C tries each scope prefix in order before rule B. That is the
  project's own setting, not an inference, so rule B's GUI refusal does not
  apply. A library index has no list and is untouched.

  Usage: pwsh -File tests/autotest/run_unit_uses_project_namespaces.ps1 [-Exe <path>]
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\drag-lint-uses-namespaces-$PID"
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

function Write-Ascii([string]$Path, [string]$Body) {
  $norm = $Body -replace "`r`n", "`n" -replace "`n", "`r`n"
  [System.IO.File]::WriteAllText($Path, $norm, [System.Text.Encoding]::ASCII)
}

# Two copies of one project; only their .dproj differs (with / without Vcl in
# DCC_Namespace). Vcl.FixDlg.pas is a PROJECT member, so it is in the closure.
function MakeProject([string]$Dir, [string]$Namespaces) {
  New-Item -ItemType Directory $Dir -Force | Out-Null
  Write-Ascii (Join-Path $Dir 'Vcl.FixDlg.pas') "unit Vcl.FixDlg;`n`ninterface`n`nprocedure RunDlg;`n`nimplementation`n`nprocedure RunDlg;`nbegin`nend;`n`nend.`n"
  Write-Ascii (Join-Path $Dir 'UMain.pas') "unit UMain;`n`ninterface`n`nuses`n  FixDlg;`n`nprocedure Go;`n`nimplementation`n`nprocedure Go;`nbegin`n  RunDlg;`nend;`n`nend.`n"
  Write-Ascii (Join-Path $Dir 'App.dpr') "program App;`n`nuses`n  Vcl.FixDlg in 'Vcl.FixDlg.pas',`n  UMain in 'UMain.pas';`n`nbegin`nend.`n"
  $ns = if ($Namespaces) { "    <DCC_Namespace>$Namespaces;`$(DCC_Namespace)</DCC_Namespace>`n" } else { '' }
  Write-Ascii (Join-Path $Dir 'App.dproj') @"
<Project xmlns="http://schemas.microsoft.com/developer/msbuild/2003">
  <PropertyGroup Condition="'`$(Base)'!=''">
$ns  </PropertyGroup>
  <ItemGroup>
    <DelphiCompile Include="App.dpr"><MainSource>MainSource</MainSource></DelphiCompile>
    <DCCReference Include="Vcl.FixDlg.pas"/>
    <DCCReference Include="UMain.pas"/>
  </ItemGroup>
</Project>
"@
}
$vcl  = Join-Path $WorkDir 'vcl'
$bare = Join-Path $WorkDir 'bare'
MakeProject $vcl  'System;Vcl'
MakeProject $bare ''

$py = Join-Path $WorkDir 'uu.py'
New-Item -ItemType Directory $WorkDir -Force | Out-Null
Write-Ascii $py @'
import sqlite3, sys
c = sqlite3.connect(sys.argv[1])
r = c.execute("""select ifnull(f.path,'') from unit_uses u left join files f on f.id = u.target_file_id
  where lower(u.unit_name) = 'fixdlg'""").fetchall()
ns = c.execute("select ifnull(value,'') from schema_meta where key='dcc_namespace'").fetchall()
print((r[0][0] if r else '<no row>') + '|' + (ns[0][0] if ns else ''))
'@
function Target([string]$Dir) {
  $db = Join-Path $Dir 'app.sqlite'
  & $Exe index --project (Join-Path $Dir 'App.dproj') --db $db --platform win32 --quiet 2>&1 | Out-Null
  $code = $LASTEXITCODE
  $o = ((python $py $db) -join '').Split('|')
  return @{ Code = $code; Target = $o[0]; Ns = $o[1] }
}

$v = Target $vcl
Check 'index (Vcl project) exits 0' ($v.Code -eq 0) "exit=$($v.Code)"
Check 'ASSERT: the project''s DCC_Namespace is recorded' ($v.Ns -eq 'System;Vcl') "dcc_namespace='$($v.Ns)'"
Check 'ASSERT: `uses FixDlg` resolves to Vcl.FixDlg.pas through the Vcl scope name' ($v.Target -like '*\Vcl.FixDlg.pas') "target='$($v.Target)'"
$b = Target $bare
Check 'CONTROL: without Vcl in the list the GUI refusal still holds (row stays NULL)' ($b.Target -eq '') "target='$($b.Target)'"

Write-Host ''
if ($script:Failed) { Write-Host 'RESULT: FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'RESULT: PASS' -ForegroundColor Green
exit 0
} finally {
  foreach ($d in @("$env:TEMP\drag-lint-uses-namespaces-$PID")) { if (Test-Path -LiteralPath $d) { Remove-Item -LiteralPath $d -Recurse -Force -ErrorAction SilentlyContinue } }
}
