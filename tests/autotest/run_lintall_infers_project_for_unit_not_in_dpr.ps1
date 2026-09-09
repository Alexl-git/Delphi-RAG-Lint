# Guard: the canonical `lint-all --db <db>` evaluates unit-not-in-dpr, by
# INFERRING the project file from the manifest section that owns that DB.
#
# THE DEFECT (docs\PLAN-SESSION-81.md section 3). The membership check was gated
# behind `if AArgs.ProjectPath <> ''`, so it ran only when the caller passed
# --project. The canonical invocation everyone actually uses -- and the one
# CLAUDE.md prescribes -- is `lint-all --db <db>`, which never supplies it. The
# rule therefore NEVER RAN on a default run, and a unit missing from the .dpr
# went unreported while the report looked complete. Silence, not an error.
#
# WHY INFERENCE RATHER THAN "ALWAYS PASS --project". The project file is not a
# new input that has to be supplied by hand: the manifest section that owns the
# DB already names it, and LintAnchorDir performs that exact db -> section ->
# project lookup for ownRoots. The walk was extracted to
# ManifestProjectFileForDb so there is ONE implementation, not two that drift.
#
# THE INFERENCE IS DELIBERATELY NARROW, and check 3 is what pins that. It feeds
# the membership check and NOTHING else -- not ScopeSet, not ResolveIndexProfile,
# not the report BaseDir. "No --project" still means UNSCOPED, and that default
# must stay byte-identical; an inference that leaked into scoping would silently
# drop every finding outside the project closure from every default run, which
# is a far worse defect than the one being fixed.
#
# RED-CHECK -- ACTUALLY RUN, 2026-09-08, against the deployed 19:46 build which
# predates the fix. Measured signature: 1 FAIL (with `unit-not-in-dpr lines=[]`,
# i.e. the rule genuinely never ran), 2 PASS, 3 PASS, 3b PASS, 4 PASS, 5 PASS.
# That run is what upgraded the defect from "read out of the source" to
# "reproduced".
#
# The first version of this guard PASSED check 1 against that same unfixed
# build, because it matched a bare 'Lib.Absent' and lint-all prints a per-file
# PROGRESS line naming every file it scans. See DprFindingLines below: a guard
# that cannot fail is not a guard, and this repo has three recorded instances.
#
# Check 2 is the positive control: it proves the fixture really contains a
# missing unit and the rule really fires, so a fixture that had silently
# stopped reproducing could not read as a passing fix.
#
# Usage: pwsh -File tests/autotest/run_lintall_infers_project_for_unit_not_in_dpr.ps1 [-Exe <path>]
[CmdletBinding()]
param(
    [string] $Exe     = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe",
    [string] $WorkDir = "$env:TEMP\drag-lint-lintall-infers-project"
)
$ErrorActionPreference = 'Stop'
$script:Failed = $false
function Check([string]$Name, [bool]$Ok, [string]$Detail='') {
    $status = if ($Ok) {'PASS'} else {'FAIL'}
    $color  = if ($Ok) {'Green'} else {'Red'}
    Write-Host ("  [{0}] {1}" -f $status, $Name) -ForegroundColor $color
    if (-not $Ok -and $Detail) { Write-Host ("      " + $Detail) -ForegroundColor DarkGray }
    if (-not $Ok) { $script:Failed = $true }
}
if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
$Exe = (Resolve-Path $Exe).Path
if (Test-Path $WorkDir) { Remove-Item -Recurse -Force $WorkDir }
New-Item -ItemType Directory $WorkDir | Out-Null

function Write-Ascii([string]$Path, [string]$Body) {
  $norm = $Body -replace "`r`n", "`n" -replace "`n", "`r`n"
  [System.IO.File]::WriteAllText($Path, $norm, [System.Text.Encoding]::ASCII)
}

# Fixture, same shape as run_unit_not_in_dpr_qualified.ps1:
#   App.Main  -- in the .dproj AND the .dpr      -> must NOT be reported
#   Lib.Absent-- in the .dproj, NOT in the .dpr  -> MUST be reported
Write-Ascii (Join-Path $WorkDir 'Lib.Absent.pas') @'
unit Lib.Absent;

interface

implementation

end.
'@

Write-Ascii (Join-Path $WorkDir 'App.Main.pas') @'
unit App.Main;

interface

implementation

end.
'@

Write-Ascii (Join-Path $WorkDir 'P.dpr') @'
program P;

uses
  App.Main in 'App.Main.pas';

begin
end.
'@

Write-Ascii (Join-Path $WorkDir 'P.dproj') @'
<Project xmlns="http://schemas.microsoft.com/developer/msbuild/2003">
    <PropertyGroup>
        <MainSource>P.dpr</MainSource>
    </PropertyGroup>
    <ItemGroup>
        <DCCReference Include="App.Main.pas"/>
        <DCCReference Include="Lib.Absent.pas"/>
    </ItemGroup>
</Project>
'@

$dproj = Join-Path $WorkDir 'P.dproj'

# A LOCAL manifest claiming this project. ManifestProjectFileForDb merges the
# engine-dir global config with the nearest .drag-lint.json walked up from the
# CWD, so the run below must happen with the CWD inside $WorkDir.
# Absolute include + no explicit "db": ExpandSectionDb then defaults a project
# section to <project folder>\_D-RAG\<project base>.sqlite, which is the path
# the index is written to below. That equality IS the inference.
$dprojJson = $dproj -replace '\\', '\\'
Write-Ascii (Join-Path $WorkDir '.drag-lint.json') @"
{
  "indexes": {
    "sections": [
      { "name": "FixtureP", "include": ["$dprojJson"] }
    ]
  }
}
"@

$db = Join-Path $WorkDir '_D-RAG\P.sqlite'
& $Exe index --project $dproj --db $db 2>&1 | Out-Null
if (-not (Test-Path $db)) { Write-Host "FATAL: index not created at $db" -ForegroundColor Red; exit 2 }

Push-Location $WorkDir
try {
    $inferred = (& $Exe lint-all --db $db --rule unit-not-in-dpr 2>&1) -join "`n"
    $explicit = (& $Exe lint-all --db $db --project $dproj --rule unit-not-in-dpr 2>&1) -join "`n"

    # A DB no manifest section claims. Inference must decline, not invent one.
    $strayDb = Join-Path $WorkDir 'stray.sqlite'
    Copy-Item $db $strayDb
    $stray = (& $Exe lint-all --db $strayDb --rule unit-not-in-dpr 2>&1) -join "`n"
} finally { Pop-Location }

# MATCH THE FINDING, NOT THE FILENAME. lint-all prints a per-file PROGRESS line
# ("lint-all: [2/3] 66% Lib.Absent.pas"), so a bare `-match 'Lib\.Absent'` is
# satisfied by the progress output alone and passes even when the rule never
# ran. That is not hypothetical: the first version of this guard did exactly
# that and PASSED against the unfixed build -- a guard incapable of failing.
# Every assertion below is therefore made against findings lines only.
function DprFindingLines([string]$Text) {
    @($Text -split "`r?`n" | Where-Object { $_ -match 'unit-not-in-dpr' })
}
$infFind   = (DprFindingLines $inferred) -join "`n"
$expFind   = (DprFindingLines $explicit) -join "`n"
$strayFind = (DprFindingLines $stray)    -join "`n"

Write-Host ''
Write-Host 'THE FIX -- lint-all evaluates unit-not-in-dpr with no --project' -ForegroundColor Cyan
Check '1. Lib.Absent IS reported by a bare `lint-all --db`' `
    ($infFind -match 'Lib\.Absent') "unit-not-in-dpr lines=[$infFind]"

Write-Host ''
Write-Host 'CONTROLS' -ForegroundColor Cyan
# POSITIVE CONTROL. Must pass with AND without the fix. If this ever fails the
# fixture stopped reproducing, and check 1 is then meaningless either way.
Check '2. positive control: explicit --project still reports it' `
    ($expFind -match 'Lib\.Absent') "unit-not-in-dpr lines=[$expFind]"

# NARROWNESS. The scoping block emits this line only when ScopeSet <> nil, i.e.
# only for a real --project. Its ABSENCE is the proof the inference did not leak.
Check '3. inference does NOT scope the run (no --project scope line)' `
    (-not ($inferred -match "belong to the project's")) "inferred=$inferred"
Check '3b. explicit --project DOES scope (proves check 3 can fail)' `
    ($explicit -match "belong to the project's") "explicit=$explicit"

# FAIL-SAFE. An unclaimed DB must yield no membership findings and no crash --
# inference declines rather than guessing a project.
Check '4. an unclaimed DB reports no unit-not-in-dpr finding' `
    ($strayFind -eq '') "unit-not-in-dpr lines=[$strayFind]"

# App.Main is in both project files and must never be reported, in either run.
Check '5. App.Main is NOT reported (it IS in the .dpr)' `
    (-not ($infFind -match 'App\.Main')) "unit-not-in-dpr lines=[$infFind]"

Write-Host ''
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
