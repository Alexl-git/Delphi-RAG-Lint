<#
  run_lint_project_scope.ps1 -- `lint-all --project <dproj>` must report ONLY on
  the units that project compiles.

  THE BUG (docs\INBOX-lint-scope-stale-files-and-project-members.md, bug 2)
  ------------------------------------------------------------------------
      drag-lint lint-all --db <db>                          -> 674 findings
      drag-lint lint-all --db <db> --project DataCopy.dproj -> 675 findings

  The flag was accepted, appeared in `help`, and changed NOTHING measurable --
  the +1 was unit-not-in-dpr, which --project happens to enable. There was no
  way to lint only the units a given project actually compiles.

  In the user's words:

    "the linter should not pick them up anyway because they are not project
     members. So if they happen to reside in the same folder, what if I had more
     related projects in the same folder? This is not illegal, so why linter
     complains about non-members?"

  That is a normal layout, not an abuse: C:\Projects\DataCopy holds BOTH
  DataCopy.dproj and SortTest.dproj, so reviewing DataCopy meant wading through
  93 findings belonging to a different program.

  Per-project INDEXING (`index --project`) already existed and works, but it
  cannot help a shared or folder-scoped DB, and a per-project DB still pulls in
  the resolved library roots -- so the filter has to exist on the LINT side too.

  FIXTURE -- one folder, TWO projects, one shared DB (the real situation)
    AppA.dproj/.dpr -> UnitA -> SharedU
    AppB.dproj/.dpr -> UnitB
    Stray.pas        -- compiled by neither project

  Each unit carries the two findings that fixtures\multi.pas is already proven
  to produce (redundant-parentheses on `((A + B))`, self-assignment on `X := X`),
  so the assertions below are about WHICH FILES are reported, never about which
  rules happen to be on by default.

  Run from a NEUTRAL CWD ($env:TEMP\drag-lint-lint-project-scope by default).
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\drag-lint-lint-project-scope"
)
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
New-Item -ItemType Directory $WorkDir | Out-Null
$proj = Join-Path $WorkDir 'proj'
New-Item -ItemType Directory $proj | Out-Null

function Write-Ascii([string]$Path, [string]$Body) {
  $norm = $Body -replace "`r`n", "`n" -replace "`n", "`r`n"
  [System.IO.File]::WriteAllText($Path, $norm, [System.Text.Encoding]::ASCII)
}

# A unit with exactly the two proven-fixable findings, optionally using another.
function Write-Unit([string]$Name, [string]$Uses) {
  $usesClause = if ($Uses) { "`r`nuses`r`n  $Uses;`r`n" } else { '' }
  Write-Ascii (Join-Path $proj "$Name.pas") @"
unit $Name;

interface
$usesClause
procedure Run_$Name;

implementation

procedure Run_$Name;
var
  A, B, X: Integer;
begin
  A := 1;
  B := 2;
  X := ((A + B));
  X := X;
end;

end.
"@
}

function Write-Project([string]$App, [string]$Unit) {
  Write-Ascii (Join-Path $proj "$App.dpr") @"
program $App;

uses
  $Unit in '$Unit.pas';

begin
  Run_$Unit;
end.
"@
  Write-Ascii (Join-Path $proj "$App.dproj") @"
<?xml version="1.0" encoding="utf-8"?>
<Project xmlns="http://schemas.microsoft.com/developer/msbuild/2003">
    <PropertyGroup>
        <MainSource>$App.dpr</MainSource>
        <ProjectVersion>20.3</ProjectVersion>
        <Platform>Win64</Platform>
        <Config Condition="'`$(Config)'==''">Debug</Config>
    </PropertyGroup>
    <ItemGroup>
        <DelphiCompile Include="$App.dpr">
            <MainSource>MainSource</MainSource>
        </DelphiCompile>
        <DCCReference Include="$Unit.pas"/>
    </ItemGroup>
</Project>
"@
}

Write-Unit 'SharedU' ''
Write-Unit 'UnitA'   'SharedU'
Write-Unit 'UnitB'   ''
Write-Unit 'Stray'   ''
Write-Project 'AppA' 'UnitA'
Write-Project 'AppB' 'UnitB'

$db = Join-Path $WorkDir 'scope.sqlite'
& $Exe index $proj --db $db --quiet 2>&1 | Out-Null

# Findings' file leaves, from the JSON document on stdout.
function Get-Leaves([string[]]$JsonLines) {
  $raw = ($JsonLines -join "`n")
  $obj = $null
  try { $obj = $raw | ConvertFrom-Json } catch { return $null }
  return @($obj | ForEach-Object { Split-Path $_.file_path -Leaf } | Sort-Object -Unique)
}

# ---------------------------------------------------------------------------
# 1) BARE run: the DB spans both projects, so everything shows up.
# ---------------------------------------------------------------------------
Write-Host 'Bare lint-all (no --project)' -ForegroundColor Cyan
$bareOut = & $Exe lint-all --db $db --json 2>$null
$bare = Get-Leaves $bareOut
Check 'bare run emitted parseable JSON' ($null -ne $bare)
Check 'bare run sees all four units' (
  ($bare -contains 'UnitA.pas') -and ($bare -contains 'SharedU.pas') -and
  ($bare -contains 'UnitB.pas') -and ($bare -contains 'Stray.pas')) ($bare -join ',')

# ---------------------------------------------------------------------------
# 2) SCOPED run: only AppA's closure.
# ---------------------------------------------------------------------------
Write-Host ''
Write-Host 'lint-all --project AppA.dproj' -ForegroundColor Cyan
$dprojA  = Join-Path $proj 'AppA.dproj'
$scopeOut = & $Exe lint-all --db $db --project $dprojA --json 2>$null
$scoped = Get-Leaves $scopeOut
Check 'scoped run emitted parseable JSON' ($null -ne $scoped)
Check 'scoped run KEEPS the project member'        ($scoped -contains 'UnitA.pas')   ($scoped -join ',')
Check 'scoped run KEEPS the transitive dependency' ($scoped -contains 'SharedU.pas') 'closure follows uses, not just DCCReference'
Check 'scoped run DROPS the other project''s unit' (-not ($scoped -contains 'UnitB.pas'))
Check 'scoped run DROPS the unreferenced stray'    (-not ($scoped -contains 'Stray.pas'))

$bareCount  = @(($bareOut  -join "`n") | ConvertFrom-Json).Count
$scopeCount = @(($scopeOut -join "`n") | ConvertFrom-Json).Count
Check 'scoping actually reduces the finding count' ($scopeCount -lt $bareCount) "$scopeCount < $bareCount"

# The scope summary is human text, so on --json it must go to stderr (same
# contract as the lint-all scanning banner -- see run_pipeline_tests.ps1 #6).
$scopeErr = ((& $Exe lint-all --db $db --project $dprojA --json 2>&1 |
              Where-Object { $_ -is [System.Management.Automation.ErrorRecord] }) -join "`n")
Check 'scope summary goes to stderr, not into the JSON' (
  ($scopeErr -match 'belong to the project') -and -not (($scopeOut -join "`n") -match 'belong to the project'))

# ---------------------------------------------------------------------------
# 3) The other project scopes to ITS OWN member -- proves the filter follows the
#    argument rather than just shrinking to whatever the first project was.
# ---------------------------------------------------------------------------
Write-Host ''
Write-Host 'lint-all --project AppB.dproj' -ForegroundColor Cyan
$scopedB = Get-Leaves (& $Exe lint-all --db $db --project (Join-Path $proj 'AppB.dproj') --json 2>$null)
Check 'AppB scope keeps UnitB'  ($scopedB -contains 'UnitB.pas') ($scopedB -join ',')
Check 'AppB scope drops UnitA'  (-not ($scopedB -contains 'UnitA.pas'))

# ---------------------------------------------------------------------------
# 4) An unresolvable --project must be a usage error, NOT a clean bill of health.
#    Scoping to an empty set would report zero findings and exit 0 -- the most
#    dangerous possible failure for a linter.
# ---------------------------------------------------------------------------
Write-Host ''
Write-Host 'lint-all --project <nonexistent>' -ForegroundColor Cyan
& $Exe lint-all --db $db --project (Join-Path $proj 'NoSuch.dproj') --json 2>$null | Out-Null
Check 'unresolvable --project exits 2 (usage), not 0' ($LASTEXITCODE -eq 2) "exit=$LASTEXITCODE"

Write-Host ''
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
