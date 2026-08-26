<#
  run_uses_clause_aligned_dots.ps1 -- a qualified unit name with whitespace
  around its dots is ONE unit, and every uses-clause parser must read it as one.

  THE DEFECT THIS PINS:
    Whitespace around the dot of a qualified unit name is insignificant to the
    compiler, and this codebase aligns them for readability -- DRagLint.CLI.pas
    alone carries 64 entries of the shape

        , DRagLint.Doc        .Batch
        , DRagLint.Core   .Interfaces

    Both uses parsers tokenised identifiers with [A-Za-z_][A-Za-z0-9_.]* , which
    stops at the space. Such an entry therefore produced TWO junk tokens --
    "DRagLint.Doc" and "Batch" -- and never the real unit name, so every
    consumer asking "is this unit reached via uses?" answered NO.

    Measured on this repo 2026-08-26: `reconcile-project` reported
    **EXTRA (28) -- listed but never reached via uses (review)** for 28 units
    that are all used, from that one file. "review" invites deleting units the
    build needs, which is why a wrong answer here is worse than no answer.

    The INDEX was never short a file: the closure also takes the .dproj member
    list, which covers them (closure 108 = indexed 108, before and after). So
    this is about REACHABILITY, not about what gets extracted.

  WHY THE CONTROL IS NOT OPTIONAL:
    "no unit is reported EXTRA" is satisfied just as well by a build where EXTRA
    is never computed, or where the fixture's units are unreachable for some
    unrelated reason. So the fixture also contains a genuinely orphaned unit that
    MUST still be reported -- if that stops firing, the assertion above is empty.
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\drag-lint-aligned-dots"
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
New-Item -ItemType Directory $WorkDir -Force | Out-Null

# App.Aligned.Used is reached ONLY through a column-aligned uses entry in
# uMid.pas. App.Truly.Orphan is in the .dproj and reached from nowhere.
Write-Ascii (Join-Path $WorkDir 'App.Aligned.Used.pas') @'
unit App.Aligned.Used;
interface
function AlignedValue: Integer;
implementation
function AlignedValue: Integer;
begin
  Result := 7;
end;
end.
'@

Write-Ascii (Join-Path $WorkDir 'App.Truly.Orphan.pas') @'
unit App.Truly.Orphan;
interface
function OrphanValue: Integer;
implementation
function OrphanValue: Integer;
begin
  Result := 9;
end;
end.
'@

# THE FIXTURE'S WHOLE POINT is the spacing on the next uses entry.
Write-Ascii (Join-Path $WorkDir 'uMid.pas') @'
unit uMid;
interface
uses
  System.SysUtils
  , App.Aligned    .Used
  ;
function MidValue: Integer;
implementation
function MidValue: Integer;
begin
  Result := AlignedValue;
end;
end.
'@

Write-Ascii (Join-Path $WorkDir 'App.dpr') @'
program App;
uses
  uMid in 'uMid.pas';
begin
  Writeln(MidValue);
end.
'@

# Both extra units are listed as project members; only one is genuinely orphaned.
Write-Ascii (Join-Path $WorkDir 'App.dproj') @'
<Project xmlns="http://schemas.microsoft.com/developer/msbuild/2003">
  <PropertyGroup>
    <MainSource>App.dpr</MainSource>
  </PropertyGroup>
  <ItemGroup>
    <DCCReference Include="uMid.pas"/>
    <DCCReference Include="App.Aligned.Used.pas"/>
    <DCCReference Include="App.Truly.Orphan.pas"/>
  </ItemGroup>
</Project>
'@

Push-Location $WorkDir
try { $out = & $Exe reconcile-project (Join-Path $WorkDir 'App.dproj') 2>&1 | Out-String }
finally { Pop-Location }

# The EXTRA section runs from its header to the next section header.
$extra = ''
if ($out -match '(?s)EXTRA \(\d+\)[^\r\n]*\r?\n(.*?)(?=^\s*(MISSING|STALE|Run a full)|\z)') {
  $extra = $Matches[1]
}

Write-Host 'THE ASSERTION: a unit reached through a COLUMN-ALIGNED uses entry is reachable' -ForegroundColor Cyan
Check 'App.Aligned.Used is NOT reported as EXTRA' `
  ($extra -notmatch 'App\.Aligned\.Used') `
  (($extra -split "`r?`n" | Where-Object { $_ -match 'Aligned' } | Select-Object -First 1))

Write-Host ''
Write-Host 'CONTROL: a genuinely orphaned unit IS still reported' -ForegroundColor Cyan
# Without this, the assertion above passes on a build that never computes EXTRA.
Check 'App.Truly.Orphan IS reported as EXTRA' `
  ($extra -match 'App\.Truly\.Orphan') `
  (($extra -split "`r?`n" | Where-Object { $_ -match 'Orphan' } | Select-Object -First 1))

Write-Host ''
Write-Host 'The closure agrees: the aligned unit is in the compile closure' -ForegroundColor Cyan
$clo = & $Exe selftest closure --project (Join-Path $WorkDir 'App.dproj') 2>&1 | Out-String
Check 'closure contains App.Aligned.Used' ($clo -match 'App\.Aligned\.Used\.pas')

Write-Host ''
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
