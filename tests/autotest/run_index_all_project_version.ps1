<#
  run_index_all_project_version.ps1 -- every project is preprocessed for ITS OWN
  Delphi: the .dproj <ProjectVersion> picks VER<N>0 / CompilerVersion.

  THE GAP (x11, after x139 9cac74e6). ApplyPreprocessCompilerVersion read the
  ProjectVersion of --project only, once per process. `index --all` builds many
  manifest sections, each with its own .dproj, and every one of them was
  preprocessed for the INSTALLED Delphi: a 10.3 section on a Delphi 13 box got
  VER370, its {$IFDEF VER330} branches were never indexed. The idea comes from
  outside PR #11 (Jonathas Paiva, "the project's own Delphi").

  WHAT IS ASSERTED (BDS pinned to a fake ...\Studio\37.0 = the installed Delphi)
    1. `index <dir> --project Rio.dproj` (ProjectVersion 18.8) -> VER330, not
       VER370 (the --project auto path of x139; it had no test).
    2. `index --all --jobs 1`: section Rio (18.8) gets VER330, section Flo
       (20.4) gets VER370 -- two sections, two different VER defines.
    3. The same through `--jobs 2` (each section in its own child process).
    4. `--target-compiler 10.3` still beats every section's ProjectVersion,
       sequential AND in the children (the flag must travel).
    5. CONTROL: a section whose .dproj has no ProjectVersion keeps the installed
       Delphi (VER370).

  Usage: pwsh -File tests/autotest/run_index_all_project_version.ps1 [-Exe <path>]
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
  [string]$WorkDir = "C:\TEMP\drag-lint-allpv-$PID"
)
$savedBds = $env:BDS
try {
$ErrorActionPreference = 'Continue'
$script:Failed = $false
function Check($n, $ok, $d = '') {
  $s = if ($ok) { 'PASS' } else { 'FAIL' }
  $c = if ($ok) { 'Green' } else { 'Red' }
  Write-Host ("  [{0}] {1} {2}" -f $s, $n, $d) -ForegroundColor $c
  if (-not $ok) { $script:Failed = $true }
}

if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
$Exe = (Resolve-Path $Exe).Path
if (Test-Path $WorkDir) { [IO.Directory]::Delete($WorkDir, $true) }
New-Item -ItemType Directory $WorkDir | Out-Null
$env:BDS = 'C:\FakeEmbarcadero\Studio\37.0'

function Write-Ascii([string]$Path, [string]$Body) {
  $norm = $Body -replace "`r`n", "`n" -replace "`n", "`r`n"
  [System.IO.File]::WriteAllText($Path, $norm, [System.Text.Encoding]::ASCII)
}

function Write-Project([string]$Name, [string]$Pv) {
  $dir = Join-Path $WorkDir $Name
  New-Item -ItemType Directory $dir | Out-Null
  Write-Ascii (Join-Path $dir "u$Name.pas") @"
unit u$Name;

interface

{`$IFDEF VER330}
procedure RioOnly;
{`$ENDIF}
{`$IFDEF VER370}
procedure FlorenceOnly;
{`$ENDIF}

implementation

end.
"@
  Write-Ascii (Join-Path $dir "$Name.dpr") @"
program $Name;

uses
  u$Name in 'u$Name.pas';

begin
end.
"@
  $pvLine = if ($Pv) { "        <ProjectVersion>$Pv</ProjectVersion>`r`n" } else { '' }
  Write-Ascii (Join-Path $dir "$Name.dproj") @"
<?xml version="1.0" encoding="utf-8"?>
<Project xmlns="http://schemas.microsoft.com/developer/msbuild/2003">
    <PropertyGroup>
        <MainSource>$Name.dpr</MainSource>
$pvLine        <Platform>Win64</Platform>
        <Config Condition="'`$(Config)'==''">Debug</Config>
    </PropertyGroup>
    <ItemGroup>
        <DelphiCompile Include="$Name.dpr">
            <MainSource>MainSource</MainSource>
        </DelphiCompile>
        <DCCReference Include="u$Name.pas"/>
    </ItemGroup>
</Project>
"@
}
Write-Project 'Rio' '18.8'
Write-Project 'Flo' '20.4'
Write-Project 'Bare' ''

function Has([string]$Db, [string]$Name) {
  & $Exe query --name $Name --db $Db --exact 2>&1 | Out-Null
  return ($LASTEXITCODE -eq 0)
}

$cfg = Join-Path $WorkDir 'manifest.drag-lint.json'
@"
{
  "settings": { "defaultPlatform": "Win64", "sizeGuardMB": 1500, "enginePath": "auto", "maxJobs": 2 },
  "indexes": {
    "outDir": "out",
    "sections": [
      { "name": "Rio",  "db": "rio.sqlite",  "include": ["Rio/Rio.dproj"] },
      { "name": "Flo",  "db": "flo.sqlite",  "include": ["Flo/Flo.dproj"] },
      { "name": "Bare", "db": "bare.sqlite", "include": ["Bare/Bare.dproj"] }
    ]
  }
}
"@ | Set-Content $cfg -Encoding ascii

function RunAll([string]$Tag, [string[]]$Extra) {
  $out = Join-Path $WorkDir 'out'
  if (Test-Path $out) { [IO.Directory]::Delete($out, $true) }
  $o = @(& $Exe index --all --config $cfg --rebuild @Extra 2>&1)
  $rc = $LASTEXITCODE
  Check "$Tag index --all exits 0" ($rc -eq 0) "exit=$rc $(($o | Select-Object -Last 3) -join ' | ')"
  return @{
    Rio  = @{ R = (Has (Join-Path $out 'rio.sqlite')  'RioOnly'); F = (Has (Join-Path $out 'rio.sqlite')  'FlorenceOnly') }
    Flo  = @{ R = (Has (Join-Path $out 'flo.sqlite')  'RioOnly'); F = (Has (Join-Path $out 'flo.sqlite')  'FlorenceOnly') }
    Bare = @{ R = (Has (Join-Path $out 'bare.sqlite') 'RioOnly'); F = (Has (Join-Path $out 'bare.sqlite') 'FlorenceOnly') }
  }
}

Push-Location C:\TEMP
try {
  Write-Host '1. index <dir> --project Rio.dproj (ProjectVersion 18.8) on a 13 box' -ForegroundColor Cyan
  $db1 = Join-Path $WorkDir 'p1.sqlite'
  & $Exe index (Join-Path $WorkDir 'Rio') --project (Join-Path $WorkDir 'Rio\Rio.dproj') --db $db1 --quiet 2>&1 | Out-Null
  Check '1. index exits 0' ($LASTEXITCODE -eq 0) "exit=$LASTEXITCODE"
  Check '1. ASSERT: --project 18.8 defines VER330 (RioOnly)' (Has $db1 'RioOnly')
  Check '1. ASSERT: ... and not VER370 (FlorenceOnly absent)' (-not (Has $db1 'FlorenceOnly'))

  foreach ($jobs in @('1', '2')) {
    Write-Host ''
    Write-Host "index --all --jobs ${jobs}: each section its own ProjectVersion" -ForegroundColor Cyan
    $r = RunAll "jobs=$jobs" @('--jobs', $jobs)
    Check "jobs=$jobs ASSERT: section Rio (18.8) gets VER330" ($r.Rio.R -and -not $r.Rio.F) "R=$($r.Rio.R) F=$($r.Rio.F)"
    Check "jobs=$jobs ASSERT: section Flo (20.4) gets VER370" ($r.Flo.F -and -not $r.Flo.R) "R=$($r.Flo.R) F=$($r.Flo.F)"
    Check "jobs=$jobs CONTROL: section Bare (no ProjectVersion) keeps the installed 13" ($r.Bare.F -and -not $r.Bare.R) "R=$($r.Bare.R) F=$($r.Bare.F)"

    Write-Host "index --all --jobs $jobs --target-compiler 10.3 - the flag beats every section" -ForegroundColor Cyan
    $t = RunAll "jobs=$jobs tc" @('--jobs', $jobs, '--target-compiler', '10.3')
    Check "jobs=$jobs ASSERT: Flo (20.4) under --target-compiler 10.3 gets VER330" ($t.Flo.R -and -not $t.Flo.F) "R=$($t.Flo.R) F=$($t.Flo.F)"
    Check "jobs=$jobs ASSERT: Bare under --target-compiler 10.3 gets VER330" ($t.Bare.R -and -not $t.Bare.F) "R=$($t.Bare.R) F=$($t.Bare.F)"
  }
} finally { Pop-Location }

Write-Host ''
if ($script:Failed) { Write-Host 'RESULT: FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'RESULT: PASS' -ForegroundColor Green
exit 0
} finally {
  $env:BDS = $savedBds
  if (Test-Path $WorkDir) { try { [IO.Directory]::Delete($WorkDir, $true) } catch {} }
}
