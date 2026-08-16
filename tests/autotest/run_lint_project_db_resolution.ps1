<#
  run_lint_project_db_resolution.ps1 -- `lint-all --project <dproj>` with NO
  explicit --db must open THAT PROJECT'S index.

  THE BUG (2026-08-12, docs\PLAN-2026-08-12-case-dataflow-fix-and-datacopy-cycle.md
  Task 0)
  ---------------------------------------------------------------------------
      drag-lint lint-all --db C:\Projects\YADF\_D-RAG\YADF.sqlite  -> 149 findings
      drag-lint lint-all --project C:\Projects\YADF\YADF.dproj     ->   0 findings,
                                                                        0 files scanned

  ResolveConsumerDbs never read AArgs.ProjectPath. It picked the manifest's
  sections in order, filtered by a platform detected from the CURRENT WORKING
  DIRECTORY, so `--project YADF.dproj` opened the FIRST section's index
  (ORM3-Micronite2027.sqlite). --project then correctly scoped the FILE LIST to
  YADF's compile closure -- and the intersection of "YADF's files" with
  "Micronite2027's index" is EMPTY. Hence `0 file(s) scanned` on a correctly
  indexed project, followed by a multi-minute project-wide pass over a foreign
  2 GB index.

  Silent zero is the worst failure a linter has: it reads as success. It cost a
  session, and it is the measure step of the LoopZero cycle.

  WHY THE EXISTING TEST MISSED IT
  -------------------------------
  run_lint_project_scope.ps1 covers --project scoping thoroughly, but every one
  of its runs passes --db explicitly. That is the one input that masks this bug:
  given the right store, the scope filter was always correct. This test is the
  complement -- it NEVER passes --db, so DB resolution is the thing under test.

  FIXTURE -- two projects in SEPARATE folders, each with its own _D-RAG index,
  both declared in a manifest beside a COPIED exe (TManifestIO.Load reads the
  engine's own directory first, so the copy is what makes the fixture manifest
  authoritative rather than the deployed one).

    code\B\AppB.dproj -> UnitB               <-- declared FIRST in the manifest
    code\A\AppA.dproj -> UnitA -> SharedU    <-- the project under test

  B comes first deliberately: under the bug, A's run opens B's index.

  THE LOAD-BEARING ASSERTION is that the --project count equals the --db count
  AND that neither is 0. A test that passed at 0 == 0 is precisely the test that
  would have missed this defect.
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\drag-lint-project-db-resolution"
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
$Exe    = (Resolve-Path $Exe).Path
$exeDir = Split-Path -Parent $Exe

if (Test-Path $WorkDir) { Remove-Item -Recurse -Force $WorkDir }
$bin   = Join-Path $WorkDir 'bin'
$codeA = Join-Path $WorkDir 'code\A'
$codeB = Join-Path $WorkDir 'code\B'
$neutral = Join-Path $WorkDir 'cwd'
New-Item -ItemType Directory $bin, $codeA, $codeB, $neutral | Out-Null

function Write-Ascii([string]$Path, [string]$Body) {
  $norm = $Body -replace "`r`n", "`n" -replace "`n", "`r`n"
  [System.IO.File]::WriteAllText($Path, $norm, [System.Text.Encoding]::ASCII)
}

# --- the engine copy: its own directory is what TManifestIO.Load reads first ---
foreach ($dll in @('tree-sitter.dll', 'tree-sitter-delphi13.dll', 'tree-sitter-dfm.dll')) {
  $src = Join-Path $exeDir $dll
  if (Test-Path $src) { Copy-Item $src (Join-Path $bin $dll) -Force }
}
$rulesSrc = Join-Path $exeDir 'rules'
if (Test-Path $rulesSrc) { Copy-Item $rulesSrc (Join-Path $bin 'rules') -Recurse -Force }
$exeCopy = Join-Path $bin 'drag-lint.exe'
Copy-Item $Exe $exeCopy -Force

# --- fixture source: two findings per unit (redundant-parentheses, self-assignment) ---
function Write-Unit([string]$Dir, [string]$Name, [string]$Uses) {
  $usesClause = if ($Uses) { "`r`nuses`r`n  $Uses;`r`n" } else { '' }
  Write-Ascii (Join-Path $Dir "$Name.pas") @"
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

function Write-Project([string]$Dir, [string]$App, [string]$Unit) {
  Write-Ascii (Join-Path $Dir "$App.dpr") @"
program $App;

uses
  $Unit in '$Unit.pas';

begin
  Run_$Unit;
end.
"@
  Write-Ascii (Join-Path $Dir "$App.dproj") @"
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

Write-Unit $codeA 'SharedU' ''
Write-Unit $codeA 'UnitA'   'SharedU'
Write-Unit $codeB 'UnitB'   ''
Write-Project $codeA 'AppA' 'UnitA'
Write-Project $codeB 'AppB' 'UnitB'

$dprojA = Join-Path $codeA 'AppA.dproj'
$dprojB = Join-Path $codeB 'AppB.dproj'
$dbA    = Join-Path $codeA '_D-RAG\AppA.sqlite'
$dbB    = Join-Path $codeB '_D-RAG\AppB.sqlite'

# --- the manifest, with B FIRST so a project-blind resolver picks the wrong DB ---
$manifest = @{
  settings = @{ defaultPlatform = 'Win64'; maxJobs = 1 }
  indexes  = @{
    outDir   = (Join-Path $WorkDir 'out')
    sections = @(
      @{ name = 'FixtureB'; include = @($dprojB) },
      @{ name = 'FixtureA'; include = @($dprojA) }
    )
  }
} | ConvertTo-Json -Depth 8
Write-Ascii (Join-Path $bin 'drag-lint.json') $manifest

Write-Host 'Indexing both fixture projects (index --all)' -ForegroundColor Cyan
& $exeCopy index --all --jobs 1 --quiet 2>&1 | Out-Null
Check 'AppA index exists' (Test-Path $dbA) $dbA
Check 'AppB index exists' (Test-Path $dbB) $dbB
if (-not ((Test-Path $dbA) -and (Test-Path $dbB))) {
  Write-Host 'FAIL (fixture did not index)' -ForegroundColor Red; exit 1
}

function Get-Findings([string[]]$JsonLines) {
  $raw = ($JsonLines -join "`n")
  try { return @($raw | ConvertFrom-Json) } catch { return $null }
}

# Everything below runs from a NEUTRAL cwd: no fixture project underfoot, so the
# only signal the engine has about which index to open is --project itself.
Push-Location $neutral
try {
  # -------------------------------------------------------------------------
  # 1) The reference numbers, taken WITH --db (the path already covered by
  #    run_lint_project_scope.ps1 and known good).
  # -------------------------------------------------------------------------
  Write-Host ''
  Write-Host 'Reference: lint-all --db <A> --project AppA.dproj' -ForegroundColor Cyan
  $refA = Get-Findings (& $exeCopy lint-all --db $dbA --project $dprojA --json 2>$null)
  Check 'reference run emitted parseable JSON' ($null -ne $refA)
  Check 'reference run finds something (a 0 baseline proves nothing)' ($refA.Count -gt 0) "count=$($refA.Count)"

  # -------------------------------------------------------------------------
  # 2) THE REGRESSION: same run, no --db. Must resolve AppA's own index.
  # -------------------------------------------------------------------------
  Write-Host ''
  Write-Host 'Under test: lint-all --project AppA.dproj (no --db)' -ForegroundColor Cyan
  $autoOut = & $exeCopy lint-all --project $dprojA --json 2>$null
  $autoA   = Get-Findings $autoOut
  Check 'auto-resolved run emitted parseable JSON' ($null -ne $autoA)
  Check 'auto-resolved run is NOT empty' ($autoA.Count -gt 0) "count=$($autoA.Count)"
  Check 'auto-resolved count == explicit --db count' ($autoA.Count -eq $refA.Count) "auto=$($autoA.Count) db=$($refA.Count)"

  $leaves = @($autoA | ForEach-Object { Split-Path $_.file_path -Leaf } | Sort-Object -Unique)
  Check 'auto-resolved run reports AppA''s own units' (
    ($leaves -contains 'UnitA.pas') -and ($leaves -contains 'SharedU.pas')) ($leaves -join ',')
  Check 'auto-resolved run reports nothing from the OTHER project' (
    -not ($leaves -contains 'UnitB.pas')) ($leaves -join ',')

  # The banner must agree with the findings. "0 file(s) scanned" IS the symptom
  # this test exists to catch, and it is the line a human reads to decide a
  # project is clean -- so assert the banner too, not only the JSON. Streams are
  # merged deliberately: the banner is prose, so it moves to stderr on --json
  # and stays on stdout otherwise, and which stream carried it is not the point
  # here (run_pipeline_tests.ps1 owns that contract).
  $bannerAll = ((& $exeCopy lint-all --project $dprojA 2>&1 | ForEach-Object { "$_" }) -join "`n")
  $scanned = 0
  if ($bannerAll -match 'scanning (\d+) \.pas file') { $scanned = [int]$Matches[1] }
  Check 'banner reports a non-zero scanned-file count' ($scanned -gt 0) "scanned=$scanned"

  # -------------------------------------------------------------------------
  # 3) The other project resolves to ITS OWN index -- proves the resolution
  #    follows the argument rather than settling on one fixed section.
  # -------------------------------------------------------------------------
  Write-Host ''
  Write-Host 'Under test: lint-all --project AppB.dproj (no --db)' -ForegroundColor Cyan
  $autoB = Get-Findings (& $exeCopy lint-all --project $dprojB --json 2>$null)
  $refB  = Get-Findings (& $exeCopy lint-all --db $dbB --project $dprojB --json 2>$null)
  Check 'AppB auto-resolved run is NOT empty' ($autoB.Count -gt 0) "count=$($autoB.Count)"
  Check 'AppB auto-resolved count == explicit --db count' ($autoB.Count -eq $refB.Count) "auto=$($autoB.Count) db=$($refB.Count)"
  $leavesB = @($autoB | ForEach-Object { Split-Path $_.file_path -Leaf } | Sort-Object -Unique)
  Check 'AppB run keeps UnitB'  ($leavesB -contains 'UnitB.pas') ($leavesB -join ',')
  Check 'AppB run drops UnitA'  (-not ($leavesB -contains 'UnitA.pas')) ($leavesB -join ',')

  # -------------------------------------------------------------------------
  # 4) A bare `lint <file>` -- NO --project and NO --db -- must open the index
  #    that HOLDS the file, not the manifest's first section.
  #
  #    ResolveConsumerDbs honoured --project but nothing consulted the FILE, so
  #    consumers took Result[0] = the first declared section. `resolve-dbs --in`
  #    had the membership ordering all along; the diagnostic had it and the
  #    consumers did not. Field symptom: `index schema v19 < v21` from ORM3's
  #    Micronite2027.sqlite while linting a YADF unit whose own index was
  #    current. The QUIET form is the dangerous one -- every store-backed
  #    per-file rule and every index-dependent autofix silently answers from a
  #    foreign project's symbols.
  #
  #    This fixture is already the right shape: the manifest declares the WRONG
  #    project first, so a run that ignores membership picks it.
  # -------------------------------------------------------------------------
  Write-Host ''
  Write-Host 'Under test: bare `lint <file>` (no --project, no --db)' -ForegroundColor Cyan
  $unitA = Join-Path (Split-Path $dprojA) 'UnitA.pas'
  Check 'fixture has UnitA.pas to lint' (Test-Path $unitA) $unitA
  if (Test-Path $unitA) {
    $bareOut  = Get-Findings (& $exeCopy lint $unitA --json 2>$null)
    $refOut   = Get-Findings (& $exeCopy lint $unitA --db $dbA --json 2>$null)
    $wrongOut = Get-Findings (& $exeCopy lint $unitA --db $dbB --json 2>$null)
    Check 'bare `lint <file>` emitted parseable JSON' ($null -ne $bareOut)
    # The reference run is what "correct" means here. If IT is empty the
    # comparison below is vacuous -- two zeros match -- so say so.
    Check 'reference (explicit --db) run is NOT empty (else the match is vacuous)' `
      ($refOut.Count -gt 0) "ref=$($refOut.Count)"

    # PRECONDITION, and it is the whole point of this case: the two indexes must
    # give DIFFERENT answers for UnitA, or "the bare run matches the right index"
    # is satisfied by matching the wrong one too.
    #
    # Measured 2026-08-14: on this fixture they do NOT differ -- 5 findings either
    # way -- because the rules that fire on UnitA are syntactic and never ask the
    # store. So the assertion below PASSED against a build that did not have the
    # membership ordering at all. It is reported rather than quietly kept, because
    # a green assertion that cannot fail is worse than a missing one: the next
    # reader would take this case as proof the defect is pinned.
    $canTell = ($refOut.Count -ne $wrongOut.Count)
    if (-not $canTell) {
      Write-Host ("  [NOTE] case 4 is NON-DISCRIMINATING on this fixture: right-db=$($refOut.Count) " +
                  "wrong-db=$($wrongOut.Count) are equal, so the match below cannot detect the " +
                  "wrong index. It still guards against a CRASH or an empty result. " +
                  "To make it real, UnitA needs a finding from a STORE-BACKED per-file " +
                  "rule -- one whose answer differs when the index does not contain the file.") `
                  -ForegroundColor Yellow
    } else {
      Check 'the two indexes DO give different answers (case 4 can discriminate)' $true `
        "right=$($refOut.Count) wrong=$($wrongOut.Count)"
      Check 'bare run does NOT match the wrong index' `
        ($bareOut.Count -ne $wrongOut.Count) "bare=$($bareOut.Count) wrong=$($wrongOut.Count)"
    }
    Check 'bare run finding count == explicit --db count' `
      ($bareOut.Count -eq $refOut.Count) "bare=$($bareOut.Count) db=$($refOut.Count)"
    # No schema-version complaint: that warning names the wrong index out loud,
    # and it is the observable that reported this defect in the first place.
    $bareBanner = ((& $exeCopy lint $unitA 2>&1 | ForEach-Object { "$_" }) -join "`n")
    Check 'bare run does not report a schema mismatch (i.e. it opened a current index)' `
      (-not ($bareBanner -match 'schema v\d+ < v\d+')) `
      (($bareBanner -split "`n" | Where-Object { $_ -match 'schema v' } | Select-Object -First 1))
  }
}
finally {
  Pop-Location
}

Write-Host ''
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
