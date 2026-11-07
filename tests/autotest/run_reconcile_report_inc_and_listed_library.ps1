<#
  run_reconcile_report_inc_and_listed_library.ps1 -- E-RECONCILE-INC / E-RECONCILE-ARRAYHELPER

  1. A {$I} include in the closure is reported (the review surface keeps it) but is
     NOT a unit: suggestedFix is 'none', so no caller offers it as a project or
     library fix. (--apply already refuses it: run_reconcile_apply_refuses_inc_files.)
  2. A unit the project LISTS that lives under a library root and is used is not an
     'extra': the closure leaves library files out by design, so "not in the closure"
     is not "unused" for it.
  POSITIVE CONTROLS: a listed project unit listed only in the dproj and used by nobody is still an
  extra; a missing project unit (uOwn) is still suggestedFix=project.

  Usage: pwsh -File tests\autotest\run_reconcile_report_inc_and_listed_library.ps1
#>
param([string]$Exe)
try {
if (-not $Exe) { $Exe = . "$PSScriptRoot\_manifest_common.ps1" }
$work = "$env:TEMP\drag-lint-reconcile-incextra-$PID"
if (Test-Path $work) { [IO.Directory]::Delete($work, $true) }
function W([string]$Path, [string]$Text) {
  $dir = Split-Path $Path
  if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Force $dir | Out-Null }
  [IO.File]::WriteAllText($Path, ($Text -replace "`r?`n", "`r`n"), [Text.Encoding]::ASCII)
}
$proj = "$work\repo\proj"; $libv = "$work\libvendor"
W "$proj\App.dpr" @'
program App;

uses
  uMain in 'uMain.pas',
  LibUnit in '..\..\libvendor\LibUnit.pas';

begin
end.
'@
W "$proj\App.dproj" @'
<?xml version="1.0" encoding="utf-8"?>
<Project xmlns="http://schemas.microsoft.com/developer/msbuild/2003">
  <PropertyGroup>
    <DCC_UnitSearchPath>..\common;..\..\libvendor</DCC_UnitSearchPath>
  </PropertyGroup>
  <ItemGroup>
    <DCCReference Include="uMain.pas"/>
    <DCCReference Include="uStray.pas"/>
    <DCCReference Include="..\..\libvendor\LibUnit.pas"/>
  </ItemGroup>
</Project>
'@
W "$proj\uMain.pas" "unit uMain;`n`ninterface`n`nuses`n  uOwn, LibUnit;`n`n{`$I Defs.inc}`n`nimplementation`n`nend.`n"
W "$proj\Defs.inc" "{ an include, not a unit }`n"
W "$proj$([char]92)uStray.pas" "unit uStray;`n`ninterface`n`nimplementation`n`nend.`n"
W "$work\repo\common\uOwn.pas" "unit uOwn;`n`ninterface`n`nimplementation`n`nend.`n"
W "$libv\LibUnit.pas" "unit LibUnit;`n`ninterface`n`nimplementation`n`nend.`n"
W "$proj\_D-RAG\drag-lint-project.json" '{ "ownRoots": [".."] }'
$bs = [string][char]92; $libJson = $libv.Replace($bs, $bs + $bs)
$cfg = "$work\.drag-lint.json"
W $cfg @"
{
  "indexes": { "sections": [ { "name": "Library", "source": "registry-libraries", "platforms": ["Win64"], "include": ["$libJson"] } ] }
}
"@
$script:Failed = $false
function Check([string]$Name, [bool]$Ok, [string]$Detail='') {
  Write-Host ("  [{0}] {1}" -f $(if ($Ok) {'PASS'} else {'FAIL'}), $Name) -ForegroundColor $(if ($Ok) {'Green'} else {'Red'})
  if (-not $Ok) { $script:Failed = $true; if ($Detail) { Write-Host "      $Detail" -ForegroundColor DarkGray } }
}
$raw = & $Exe reconcile-project "$proj\App.dproj" --json --config $cfg 2>$null | Out-String
$doc = $null; try { $doc = $raw | ConvertFrom-Json } catch { }
Check '0 --json parses' ($null -ne $doc) $raw
$inc = @($doc.missing | Where-Object { $_.file -like '*Defs.inc' })
$own = @($doc.missing | Where-Object { $_.unit -eq 'uOwn' })
Check '1a the include is still in the report' ($inc.Count -eq 1) $raw
Check '1b the include has suggestedFix none' (($inc.Count -eq 1) -and ($inc[0].suggestedFix -eq 'none')) $raw
Check '1c control: uOwn is missing with suggestedFix project' (($own.Count -eq 1) -and ($own[0].suggestedFix -eq 'project')) $raw
$lib = @($doc.extra | Where-Object { $_.unit -eq 'LibUnit' })
$str = @($doc.extra | Where-Object { $_.unit -eq 'uStray' })
Check '2a a listed, used library unit is NOT an extra' ($lib.Count -eq 0) $raw
Check '2b control: the listed project unit listed only in the dproj and unused uStray IS an extra' ($str.Count -eq 1) $raw
if (Test-Path $work) { [IO.Directory]::Delete($work, $true) }
if ($script:Failed) { exit 1 } else { exit 0 }
} catch { Write-Host "FATAL: $_" -ForegroundColor Red; exit 2 }
