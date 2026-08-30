<#
  run_lintall_project_rules_honour_exclude_paths.ps1 -- exclude_paths must gate
  the PROJECT-WIDE rules, not only the per-file scan.

  THE DEFECT THIS PINS:
    lint-all runs in two passes over two different populations:
      1. a PER-FILE pass over an enumerated FilePaths list, and
      2. a PROJECT-WIDE pass in which every store-backed rule (doc-drift,
         missing-doc, unused-public-symbol, god-class, duplicate-code,
         layering, used-unit-not-resolvable) reads the WHOLE STORE and emits
         findings against files that list never contained.

    Pass 1 filtered on BOTH settings -- Cfg.IsPathExcluded and Own.IsOurs, on
    adjacent lines. Pass 2 was then given a post-hoc findings filter to stop the
    excluded noise walking back in through the store... and that filter was
    given Own.IsOurs and the --project ScopeSet, but NOT Cfg.IsPathExcluded.

    So on a repo whose ownRoots is deliberately the REPO ROOT -- drag-lint's own
    shape, where the .dproj sits in src\cli and the vendored-code exclusion
    lives ENTIRELY in exclude_paths -- ownRoots ADMITS the vendored subtree and
    nothing else stopped it. Measured on drag-lint's own source 2026-08-26:
    207 findings (204 doc-drift + 3 unused-public-symbol) against
    third_party\delphi-tree-sitter, in a run that had ALREADY printed
    "lint-all: 3 file(s) skipped by exclude_paths".

    That banner is what made it invisible: the exclusion visibly fired, so the
    report looked scoped. The count it reported was the count of files kept out
    of pass 1, which says nothing about pass 2.

  This is the same defect as run_doc_honours_exclude_paths.ps1, one pass over.
  That note recorded that IsPathExcluded "had exactly ONE call site in the whole
  engine -- inside lint-all's file loop". The doc writer was given the second
  call site; lint-all's own project-wide pass never got one.

  WHY THE CONTROLS BELOW ARE NOT OPTIONAL:
    "no third_party finding" passes just as happily when the vendored file was
    never indexed, when the project-wide rules never ran, or when the linter is
    dead. So this asserts the SAME run three ways: the vendored file is indexed,
    it genuinely produces project-wide findings when exclude_paths is EMPTY, and
    the owned file still produces findings when it is set.
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\drag-lint-lintall-exclude-paths"
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

# repo\
#   drag-lint-lint.json           exclude_paths: *\third_party\*
#   app\  App.dpr, uApp.pas, _D-RAG\drag-lint-project.json (ownRoots: ..)
#   third_party\ uVendor.pas      <- in the closure, INSIDE ownRoots, excluded
$repo   = Join-Path $WorkDir 'repo'
$app    = Join-Path $repo 'app'
$vendor = Join-Path $repo 'third_party'
$drag   = Join-Path $app '_D-RAG'
foreach ($d in @($repo, $app, $vendor, $drag)) { New-Item -ItemType Directory $d -Force | Out-Null }

# The vendored unit carries BOTH shapes of project-wide finding:
#   * a managed drag-lint:auto block with deliberately wrong facts -> doc-drift
#   * an exported routine nobody calls                             -> unused-public-symbol
# Neither is a per-file rule, so neither can be stopped by the pass-1 filter.
Write-Ascii (Join-Path $vendor 'uVendor.pas') @'
unit uVendor;
interface
const
  CVendDup = 7;
/// <summary>Vendored upstream binding; not ours to restyle.</summary>
/// <remarks>
/// <!-- drag-lint:auto BEGIN -->
/// <para>Used by: NoSuchUnit.NoSuchCaller (NoSuchUnit.pas)</para>
/// <para>Used in units: NoSuchUnit</para>
/// <!-- drag-lint:auto END -->
/// </remarks>
function ts_query_cursor_new(const AName: string): Integer;
/// <summary>Exported and never called, upstream's business.</summary>
function ts_language_state_count(const AName: string): Integer;
implementation
function ts_query_cursor_new(const AName: string): Integer;
begin
  Result := Length(AName);
end;
function ts_language_state_count(const AName: string): Integer;
begin
  Result := Length(AName) + 1;
end;
end.
'@

# The owned unit carries the SAME two shapes, so it is the live control: if the
# project-wide rules stop running, its findings vanish too and the test fails
# loudly instead of going quietly green.
Write-Ascii (Join-Path $app 'uApp.pas') @'
unit uApp;
interface
uses uVendor;
const
  CAppDup = 9;
/// <summary>Ours, and deliberately stale.</summary>
/// <remarks>
/// <!-- drag-lint:auto BEGIN -->
/// <para>Used by: NoSuchUnit.NoSuchCaller (NoSuchUnit.pas)</para>
/// <para>Used in units: NoSuchUnit</para>
/// <!-- drag-lint:auto END -->
/// </remarks>
function AppDo(const AName: string): Integer;
/// <summary>Ours, exported, never called.</summary>
function AppUnusedThing(const AName: string): Integer;
implementation
function AppDo(const AName: string): Integer;
begin
  Result := ts_query_cursor_new(AName);
end;
function AppUnusedThing(const AName: string): Integer;
begin
  Result := Length(AName) + 2;
end;
end.
'@

# global-only-uses-edge is the THIRD shape, added 2026-08-30, and it is the one
# that most needed covering here: it is anchored at the READING unit, so unlike
# doc-drift and unused-public-symbol the vendored file has to be the CONSUMER
# for the exclusion to bite at all.
Write-Ascii (Join-Path $app 'uGlob.pas') @'
unit uGlob;
interface
var
  gTheOnlyLink: Boolean;
implementation
end.
'@

Write-Ascii (Join-Path $vendor 'uVendorReader.pas') @'
unit uVendorReader;
interface
const
  CVendDup = 7;
uses uGlob;
function VendorReads: Boolean;
implementation
function VendorReads: Boolean;
begin
  Result:= gTheOnlyLink;
end;
end.
'@

# The owned twin: identical shape, inside ownRoots and NOT excluded, so it is
# the live control for the new rule specifically.
Write-Ascii (Join-Path $app 'uAppReader.pas') @'
unit uAppReader;
interface
uses uGlob;
const
  CAppDup = 9;
function AppReads: Boolean;
implementation
function AppReads: Boolean;
begin
  Result:= gTheOnlyLink;
end;
end.
'@

Write-Ascii (Join-Path $app 'App.dpr') @'
program App;
uses
  uApp in 'uApp.pas',
  uGlob in 'uGlob.pas',
  uAppReader in 'uAppReader.pas',
  uVendorReader in '..\third_party\uVendorReader.pas',
  uVendor in '..\third_party\uVendor.pas';
begin
  Writeln(AppDo('x'));
  Writeln(AppReads);
  Writeln(VendorReads);
end.
'@

# ownRoots = the REPO root (the parent of the project folder). This is the
# drag-lint shape, and it is what makes exclude_paths load-bearing: ownRoots
# ADMITS third_party\, so nothing but exclude_paths keeps these findings out.
Write-Ascii (Join-Path $drag 'drag-lint-project.json') '{ "ownRoots": [".."] }'
$cfgOn  = Join-Path $repo 'drag-lint-lint.json'
$cfgOff = Join-Path $repo 'drag-lint-lint-noexclude.json'
Write-Ascii $cfgOn  '{ "exclude_paths": ["*\\third_party\\*"], "enabled": ["global-only-uses-edge", "uses-global-census"] }'
Write-Ascii $cfgOff '{ "exclude_paths": [], "enabled": ["global-only-uses-edge", "uses-global-census"] }'

$db    = Join-Path $drag 'app.sqlite'
$proj  = Join-Path $app 'App.dpr'
& $Exe index $repo --db $db 2>&1 | Out-Null

function Lint-Run([string]$Cfg, [string]$OutFile) {
  Push-Location $repo
  try { & $Exe lint-all --project $proj --db $db --config $Cfg --output $OutFile 2>&1 | Out-String }
  finally { Pop-Location }
}
function Vendor-Findings([string]$OutFile) {
  if (-not (Test-Path $OutFile)) { return @() }
  @(Get-Content $OutFile | Where-Object { $_ -match 'third_party' -and $_ -match '\[(error|warning|info|hint)\]' })
}
function Owned-Findings([string]$OutFile) {
  if (-not (Test-Path $OutFile)) { return @() }
  @(Get-Content $OutFile | Where-Object { $_ -match 'uApp\.pas' -and $_ -match '\[(error|warning|info|hint)\]' })
}

Write-Host 'PRECONDITION: the vendored unit is indexed' -ForegroundColor Cyan
$q = & $Exe query --name ts_query_cursor_new --db $db 2>&1 | Out-String
$inIndex = $q -match 'ts_query_cursor_new'
Check 'uVendor is indexed (so excluding it is a real decision)' $inIndex
if (-not $inIndex) {
  Write-Host '  !! Every assertion below is VACUOUS. Fix the fixture, not the assertions.' -ForegroundColor Yellow
  $script:Failed = $true
}

Write-Host ''
Write-Host 'POSITIVE CONTROL: with exclude_paths EMPTY the vendored file DOES report' -ForegroundColor Cyan
# Without this, "0 vendored findings" below would also pass if the project-wide
# rules never fired on this fixture at all -- which is the failure mode that let
# the real defect sit behind a reassuring "skipped by exclude_paths" banner.
$outOff = Join-Path $WorkDir 'off.txt'
$null   = Lint-Run $cfgOff $outOff
$vOff   = Vendor-Findings $outOff
Check 'vendored file produces project-wide findings when NOT excluded' `
  ($vOff.Count -gt 0) ("{0} finding(s)" -f $vOff.Count)
if ($vOff.Count -eq 0) {
  Write-Host '  !! The main assertion below cannot fail, so it proves nothing.' -ForegroundColor Yellow
}

Write-Host ''
Write-Host 'THE ASSERTION: with exclude_paths SET, no vendored finding survives' -ForegroundColor Cyan
$outOn = Join-Path $WorkDir 'on.txt'
$oOn   = Lint-Run $cfgOn $outOn
$vOn   = Vendor-Findings $outOn
Check 'no finding is reported against an excluded path' `
  ($vOn.Count -eq 0) ("{0} leaked: {1}" -f $vOn.Count, (($vOn | Select-Object -First 3) -join ' | '))

Check 'the run still says what it skipped' `
  ($oOn -match 'skipped by exclude_paths') `
  (($oOn -split "`r?`n" | Where-Object { $_ -match 'exclude_paths' } | Select-Object -First 1))

Write-Host ''
Write-Host 'BY NAME: global-only-uses-edge obeys the same filter' -ForegroundColor Cyan
# Named explicitly rather than left to the generic counts above. A project-wide
# rule added later inherits this filter only because the pass is generic -- but
# nothing PROVES it for a given rule until that rule is asserted by id, and
# project-wide rules bypassed this filter entirely until 59612f1.
Check 'POSITIVE CONTROL: the vendored reader reports it when NOT excluded' `
  (@(Vendor-Findings $outOff | Where-Object { $_ -match 'global-only-uses-edge' }).Count -gt 0) `
  'if this is 0 the assertion below proves nothing'
Check 'no global-only-uses-edge survives against an excluded path' `
  (@(Vendor-Findings $outOn | Where-Object { $_ -match 'global-only-uses-edge' }).Count -eq 0)
Check 'LIVE CONTROL: the owned reader still reports it in the same run' `
  (@(Get-Content $outOn | Where-Object { $_ -match 'uAppReader' -and $_ -match 'global-only-uses-edge' }).Count -gt 0) `
  'otherwise the rule was simply off and the check above is empty'

Write-Host ''
Write-Host 'BY NAME: duplicate-global-decl obeys the same filter' -ForegroundColor Cyan
# Same reasoning as the block above, and it needs its own fixture rather than
# riding on that one: this rule is anchored at the FIRST declaring site in
# (path, line) order, so a pair straddling the boundary would be filtered or
# kept by an accident of sort order. CVendDup has BOTH sites inside
# third_party\; CAppDup has both sites owned.
Check 'POSITIVE CONTROL: the vendored pair reports it when NOT excluded' `
  (@(Vendor-Findings $outOff | Where-Object { $_ -match 'duplicate-global-decl' }).Count -gt 0) `
  'if this is 0 the assertion below proves nothing'
Check 'no duplicate-global-decl survives against an excluded path' `
  (@(Vendor-Findings $outOn | Where-Object { $_ -match 'duplicate-global-decl' }).Count -eq 0)
Check 'LIVE CONTROL: the owned pair still reports it in the same run' `
  (@(Get-Content $outOn | Where-Object { $_ -match 'CAppDup' -and $_ -match 'duplicate-global-decl' }).Count -gt 0) `
  'otherwise the rule was simply off and the check above is empty'

Write-Host ''
Write-Host 'BY NAME: uses-global-census obeys the same filter' -ForegroundColor Cyan
# The census anchors at the READER's uses line, so the vendored READER is what
# has to disappear -- uVendorReader draws gTheOnlyLink from uGlob.
Check 'POSITIVE CONTROL: the vendored reader reports it when NOT excluded' `
  (@(Vendor-Findings $outOff | Where-Object { $_ -match 'uses-global-census' }).Count -gt 0) `
  'if this is 0 the assertion below proves nothing'
Check 'no uses-global-census survives against an excluded path' `
  (@(Vendor-Findings $outOn | Where-Object { $_ -match 'uses-global-census' }).Count -eq 0)
Check 'LIVE CONTROL: the owned reader still reports it in the same run' `
  (@(Get-Content $outOn | Where-Object { $_ -match 'uAppReader' -and $_ -match 'uses-global-census' }).Count -gt 0) `
  'otherwise the rule was simply off and the check above is empty'

Write-Host ''
Write-Host 'LIVE CONTROL: the owned file is still reported in the SAME run' -ForegroundColor Cyan
# If the fix over-reached and killed the project-wide pass outright, the
# assertion above would pass and this one fails.
$oOwned = Owned-Findings $outOn
Check 'owned file still produces project-wide findings with exclude_paths set' `
  ($oOwned.Count -gt 0) ("{0} finding(s)" -f $oOwned.Count)

Write-Host ''
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
