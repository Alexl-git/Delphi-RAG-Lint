<#
  run_reconcile_apply_writes_relative_paths.ps1 -- `reconcile-project --apply`
  edits CHECKED-IN project files. What it writes has to be portable, and it must
  not reorder the clause it edits.

  TWO DEFECTS THIS PINS, both observed by running --apply on this repo:

  1. IT WROTE MACHINE-ABSOLUTE PATHS.
       DRagLint.Lint.SharedUnit in 'C:\Projects\Delphi-RAG-lint\src\lint\...pas',
       <DCCReference Include="C:\Projects\Delphi-RAG-lint\src\lint\...pas"/>
     into the .dpr and .dproj, where all 101 existing entries are relative.
     Those files are committed; an absolute path breaks every other machine and
     every other checkout location. drag-lint's OWN hardcoded-absolute-path rule
     fired on the two .dpr lines, which is the system working -- but the tool
     should not have written them.

     Cause: MakeRelPath only stripped a base PREFIX, so a unit outside the
     project folder (the common case -- src\lint from a project in src\cli) had
     no expressible relative form and it fell back to absolute. The fix is
     ExtractRelativePath, which walks up with '..'.

  2. IT APPENDED AFTER THE MAIN UNIT.
     A .dpr uses clause ends with the main unit, and clause order IS
     initialization order, so the main unit belongs last. Splicing at the ';'
     demoted it. Harmless the day it was found -- neither added unit had an
     initialization section -- but that is luck, and the failure it invites is a
     startup-order bug that reproduces nowhere else.

  The fixture puts the missing unit in a SIBLING directory, because that is the
  shape that produced the absolute path; a fixture with everything in one folder
  passes on the broken code.
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\drag-lint-reconcile-apply"
)
$ErrorActionPreference = 'Stop'
$script:Failed = $false
function Check($n, $ok, $d = '') {
  $s = if ($ok) { 'PASS' } else { 'FAIL' }
  $c = if ($ok) { 'Green' } else { 'Red' }
  Write-Host ("  [{0}] {1} {2}" -f $s, $n, $d) -ForegroundColor $c
  if (-not $ok) { $script:Failed = $true }
}
function Write-Ascii([string]$Path, [string]$Text) {
  $norm = ($Text -replace "`r`n", "`n") -replace "`n", "`r`n"
  [System.IO.File]::WriteAllText($Path, $norm, [System.Text.Encoding]::ASCII)
}

if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
$Exe = (Resolve-Path $Exe).Path
if (Test-Path $WorkDir) { Remove-Item -Recurse -Force $WorkDir }

# repo\app\App.dpr   (the project)      <- MainUnit must stay LAST
# repo\lib\uHelper.pas                  <- a SIBLING dir: only '..\lib\' works
$repo = Join-Path $WorkDir 'repo'
$app  = Join-Path $repo 'app'
$lib  = Join-Path $repo 'lib'
foreach ($d in @($repo, $app, $lib)) { New-Item -ItemType Directory $d -Force | Out-Null }

Write-Ascii (Join-Path $lib 'uHelper.pas') @'
unit uHelper;
interface
function HelperValue: Integer;
implementation
function HelperValue: Integer;
begin
  Result := 5;
end;
end.
'@

# uKnown is LISTED with its path, which is what teaches the resolver that
# ..\lib\ is a source directory. Without it uHelper is not discoverable
# at all and the whole suite goes vacuous -- which is exactly what the first
# draft of this fixture did.
Write-Ascii (Join-Path $lib 'uKnown.pas') @'
unit uKnown;
interface
uses uHelper;
function KnownValue: Integer;
implementation
function KnownValue: Integer;
begin
  Result := HelperValue + 2;
end;
end.
'@

Write-Ascii (Join-Path $app 'uMain.pas') @'
unit uMain;
interface
uses uKnown;
function MainValue: Integer;
implementation
function MainValue: Integer;
begin
  Result := KnownValue;
end;
end.
'@

# uMain is LAST in the clause and must remain last. uHelper is used but unlisted,
# so it is the MISSING unit --apply will add.
Write-Ascii (Join-Path $app 'App.dpr') @'
program App;
uses
  System.SysUtils,
  uKnown in '..\lib\uKnown.pas',
  uMain in 'uMain.pas';
begin
  Writeln(MainValue);
end.
'@

Write-Ascii (Join-Path $app 'App.dproj') @'
<Project xmlns="http://schemas.microsoft.com/developer/msbuild/2003">
  <PropertyGroup>
    <MainSource>App.dpr</MainSource>
  </PropertyGroup>
  <ItemGroup>
    <DCCReference Include="uMain.pas"/>
    <DCCReference Include="..\lib\uKnown.pas"/>
  </ItemGroup>
</Project>
'@

$dpr   = Join-Path $app 'App.dpr'
$dproj = Join-Path $app 'App.dproj'

Push-Location $app
try { $out = & $Exe reconcile-project $dproj --apply 2>&1 | Out-String }
finally { Pop-Location }

$dprText   = Get-Content $dpr   -Raw
$dprojText = Get-Content $dproj -Raw

Write-Host 'PRECONDITION: --apply actually added the missing unit' -ForegroundColor Cyan
# Without this every assertion below passes on a build that writes nothing.
Check '.dpr now references uHelper'   ($dprText   -match 'uHelper')  ''
Check '.dproj now references uHelper' ($dprojText -match 'uHelper')  ''

Write-Host ''
Write-Host 'DEFECT 1: no machine-absolute path may be written' -ForegroundColor Cyan
Check '.dpr entry is relative, not absolute' `
  ($dprText -notmatch "in\s+'[A-Za-z]:\\") `
  (($dprText -split "`r?`n" | Where-Object { $_ -match 'uHelper' } | Select-Object -First 1))
Check '.dproj entry is relative, not absolute' `
  ($dprojText -notmatch 'Include="[A-Za-z]:\\') `
  (($dprojText -split "`r?`n" | Where-Object { $_ -match 'uHelper' } | Select-Object -First 1))
Check '.dpr entry walks up with ..\' `
  ($dprText -match "uHelper in '\.\.\\lib\\uHelper\.pas'") ''

Write-Host ''
Write-Host 'DEFECT 2: the MAIN unit must stay last in the uses clause' -ForegroundColor Cyan
# Clause order is initialization order; the main unit initializes last.
$clause = ''
if ($dprText -match '(?is)\buses\b(.*?);') { $clause = $Matches[1] }
$iMain   = $clause.IndexOf('uMain',   [StringComparison]::OrdinalIgnoreCase)
$iHelper = $clause.IndexOf('uHelper', [StringComparison]::OrdinalIgnoreCase)
Check 'both units are in the clause' (($iMain -ge 0) -and ($iHelper -ge 0)) "uMain@$iMain uHelper@$iHelper"
Check 'uHelper is inserted BEFORE uMain' `
  (($iHelper -ge 0) -and ($iMain -gt $iHelper)) "uMain@$iMain uHelper@$iHelper"

Write-Host ''
Write-Host 'The result still parses as a project' -ForegroundColor Cyan
$again = & $Exe reconcile-project $dproj 2>&1 | Out-String
Check 'a second run reports MISSING (0) -- the edit was understood' `
  ($again -match 'MISSING \(0\)') `
  (($again -split "`r?`n" | Where-Object { $_ -match '^MISSING' } | Select-Object -First 1))

Write-Host ''
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
