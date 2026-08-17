<#
  run_query_framework_preference.ps1 -- a bare-name lookup prefers the GUI
  framework the run's own project actually uses, and reports the tie untouched
  when the run names no project.

  THE BUG (INBOX-converter-editor-phase-g-engine-findings, finding 2.5, product
  half). `query --name TEdit` against library-Win64 returns two equally
  type-like rows, FMX.Edit.TEdit and Vcl.StdCtrls.TEdit. Nothing in either row
  distinguishes them -- same kind, same section, both usable from other units --
  so the only thing deciding which a caller sees first was `ORDER BY
  qualified_name`, and 'FMX' sorts before 'Vcl'. Measured on the shipped index,
  TEdit, TButton, TLabel and ~32 further names all handed a VCL tool the FMX
  declaration. Every consumer takes the first row; the converter editor had to
  stop doing so and report the tie by hand.

  WHY THERE IS NO --framework FLAG. The note asked for one. Measured, the tie is
  LIBRARY-ONLY -- the same query against a project index returns 0 rows, because
  a project index holds only the project's own code and neither TEdit is in it.
  And a project that could be affected already states its framework: DataCopy
  writes 25 `Vcl.*` uses and 0 `FMX.*`; YADF, 18 and 0. So the context is
  DERIVED where it exists and ABSENT where it does not, and no default has to be
  ruled on.

  WHAT EACH CHECK IS FOR.
   * The POSITIVE CONTROL is the FIRST assert, not an afterthought: with no
     project context the rows must come back in the SQL's own order, all of
     them. A suite that only checked "VCL first when a VCL project is present"
     would pass against a hardcoded VCL-over-FMX preference -- which is exactly
     the product decision this design refuses to make.
   * The FMX-project case is the de-vacuator for that: the SAME library index,
     the SAME name, and the answer flips. Only reading the project can do that.
   * SHARED GROUND (a third TEdit in a non-framework namespace) is checked to
     stay in the MIDDLE. It is not a competing answer, so it must not be pushed
     behind the preferred framework -- only ahead of the rejected one.
   * The TIE case (a project writing both frameworks equally) must behave
     exactly like no context at all.
   * Every case asserts the row COUNT is unchanged. This reorders; it never
     filters, so the tie stays visible to a consumer that wants to report it.

  NOT COVERED HERE, deliberately: the `--project <x.dproj>` branch. It resolves
  through DRagLint.Index.Manifest.ResolveProjectDb -- the same function the
  IDE's Rebuild Index and `resolve-dbs --project` use, already covered by their
  own suites -- and reaching it needs a manifest entry, which an ad-hoc fixture
  index has no business inventing. It was verified live instead:
  `query --name TEdit --db library-Win64.sqlite --project C:\Projects\DataCopy\DataCopy.dproj`
  answers Vcl.StdCtrls.TEdit first, where the same query without --project
  answers FMX.Edit.TEdit first.

  Usage: pwsh -File tests/autotest/run_query_framework_preference.ps1 [-Exe <path>]
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\drag-lint-framework-pref"
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

function Write-Ascii([string]$Path, [string]$Body) {
  $norm = $Body -replace "`r`n", "`n" -replace "`n", "`r`n"
  [System.IO.File]::WriteAllText($Path, $norm, [System.Text.Encoding]::ASCII)
}
function NewDir([string]$Name) {
  $p = Join-Path $WorkDir $Name
  New-Item -ItemType Directory $p | Out-Null
  return $p
}

# --- The LIBRARY side: one name, three declarations. -------------------------------
# Two of them are the mutually exclusive GUI frameworks; the third is SHARED
# ground (a plain namespace), which is what proves the middle rank exists.
$libSrc = NewDir 'libsrc'
Write-Ascii (Join-Path $libSrc 'Vcl.StdCtrls.pas') @'
unit Vcl.StdCtrls;

interface

type
  TEdit = class(TObject)
  public
    procedure Clear;
  end;

implementation

procedure TEdit.Clear;
begin
end;

end.
'@
Write-Ascii (Join-Path $libSrc 'FMX.Edit.pas') @'
unit FMX.Edit;

interface

type
  TEdit = class(TObject)
  public
    procedure Clear;
  end;

implementation

procedure TEdit.Clear;
begin
end;

end.
'@
# SHARED ground. 'Shared' is not a GUI framework namespace, so this row belongs
# in neither the preferred nor the rejected bucket, and its position relative to
# the others must not move when a preference is applied.
Write-Ascii (Join-Path $libSrc 'Shared.Common.pas') @'
unit Shared.Common;

interface

type
  TEdit = class(TObject)
  public
    procedure Clear;
  end;

implementation

procedure TEdit.Clear;
begin
end;

end.
'@

# --- The PROJECT side: three projects, differing ONLY in their uses clauses. --------
$vclSrc = NewDir 'vclsrc'
Write-Ascii (Join-Path $vclSrc 'VclApp.pas') @'
unit VclApp;

interface

uses
  System.Classes, Vcl.StdCtrls, Vcl.Forms, Vcl.Controls;

type
  TVclThing = class(TObject)
  public
    procedure Run;
  end;

implementation

procedure TVclThing.Run;
begin
end;

end.
'@

$fmxSrc = NewDir 'fmxsrc'
Write-Ascii (Join-Path $fmxSrc 'FmxApp.pas') @'
unit FmxApp;

interface

uses
  System.Classes, FMX.Edit, FMX.Forms, FMX.Types;

type
  TFmxThing = class(TObject)
  public
    procedure Run;
  end;

implementation

procedure TFmxThing.Run;
begin
end;

end.
'@

# Equal counts on purpose: a project that genuinely writes both frameworks has
# no single one to prefer, and must be answered '' rather than arbitrarily.
$bothSrc = NewDir 'bothsrc'
Write-Ascii (Join-Path $bothSrc 'BothApp.pas') @'
unit BothApp;

interface

uses
  System.Classes, Vcl.StdCtrls, Vcl.Forms, FMX.Edit, FMX.Forms;

type
  TBothThing = class(TObject)
  public
    procedure Run;
  end;

implementation

procedure TBothThing.Run;
begin
end;

end.
'@

# The `library-` FILENAME PREFIX is load-bearing -- it is how the engine tells a
# library index from a project one (the same test ResolveLibraryDb uses). Rename
# this file and every case below silently becomes a no-context case.
$libDb  = Join-Path $WorkDir 'library-Test.sqlite'
$vclDb  = Join-Path $WorkDir 'vclproj.sqlite'
$fmxDb  = Join-Path $WorkDir 'fmxproj.sqlite'
$bothDb = Join-Path $WorkDir 'bothproj.sqlite'

Write-Host 'Indexing fixtures' -ForegroundColor Cyan
foreach ($pair in @(@($libSrc, $libDb), @($vclSrc, $vclDb), @($fmxSrc, $fmxDb), @($bothSrc, $bothDb))) {
  $out = & $Exe index $pair[0] --db $pair[1] --quiet 2>&1
  Check ("index {0}" -f (Split-Path $pair[1] -Leaf)) ($LASTEXITCODE -eq 0) "exit=$LASTEXITCODE; $($out -join ' | ')"
}

# --- Probe. -------------------------------------------------------------------------
# Returns the qualified names of `query --name TEdit`, IN ORDER. --quiet keeps
# the defaults banner off stderr; the StartsWith filter keeps anything else that
# lands there out of the JSON.
function QNames([string[]]$Dbs) {
  $dbArgs = @()
  foreach ($d in $Dbs) { $dbArgs += '--db'; $dbArgs += $d }
  $raw = @(& $Exe query --name TEdit @dbArgs --json --quiet 2>&1) | ForEach-Object { "$_" }
  $script:LastExit = $LASTEXITCODE
  $json = ($raw | Where-Object { -not $_.TrimStart().StartsWith('(') }) -join "`n"
  if (-not $json.Trim()) { return @() }
  return @(($json | ConvertFrom-Json) | ForEach-Object { $_.qualified_name })
}

# --- POSITIVE CONTROL: no project context, so the tie is reported as it always was. --
Write-Host ''
Write-Host 'POSITIVE CONTROL -- library alone: every row, in the SQL order' -ForegroundColor Cyan

$bare = QNames @($libDb)
Check 'precondition: the library fixture declares TEdit three times' ($bare.Count -eq 3) `
  "rows=$($bare.Count) [$($bare -join ', ')] -- fewer and the whole suite is vacuous"
Check 'ASSERT: with NO project context the FMX row is still first (ORDER BY qualified_name)' `
  ($bare[0] -eq 'FMX.Edit.TEdit') `
  "first=$($bare[0]) -- this is the untouched behaviour; if it changed, the engine now picks a framework with no evidence"
Check 'control: the bare lookup exits 0' ($script:LastExit -eq 0) "exit=$script:LastExit"

# --- A VCL project: its own framework leads. ----------------------------------------
Write-Host ''
Write-Host 'a VCL project in the scan set' -ForegroundColor Cyan

$vcl = QNames @($libDb, $vclDb)
Check 'ASSERT: Vcl.StdCtrls.TEdit is first' ($vcl[0] -eq 'Vcl.StdCtrls.TEdit') "order=[$($vcl -join ', ')]"
Check 'ASSERT: FMX.Edit.TEdit is LAST -- the rejected framework, not merely not-first' `
  ($vcl[-1] -eq 'FMX.Edit.TEdit') "order=[$($vcl -join ', ')]"
Check 'ASSERT: shared ground stays in the MIDDLE, ahead of the rejected framework' `
  ($vcl[1] -eq 'Shared.Common.TEdit') `
  "order=[$($vcl -join ', ')] -- Shared.* is not a competing answer and must not be demoted with FMX"
Check 'control: nothing was FILTERED -- still three rows' ($vcl.Count -eq 3) "rows=$($vcl.Count)"

# --- An FMX project: the SAME library, and the answer flips. ------------------------
# This is the de-vacuator for the case above. Both cases pass under a hardcoded
# VCL-over-FMX preference; only this one distinguishes "reads the project" from
# "prefers VCL".
Write-Host ''
Write-Host 'an FMX project in the scan set -- same library index, opposite answer' -ForegroundColor Cyan

$fmx = QNames @($libDb, $fmxDb)
Check 'ASSERT: FMX.Edit.TEdit is first' ($fmx[0] -eq 'FMX.Edit.TEdit') "order=[$($fmx -join ', ')]"
Check 'ASSERT: Vcl.StdCtrls.TEdit is LAST' ($fmx[-1] -eq 'Vcl.StdCtrls.TEdit') "order=[$($fmx -join ', ')]"
Check 'ASSERT: shared ground stays in the MIDDLE here too' ($fmx[1] -eq 'Shared.Common.TEdit') "order=[$($fmx -join ', ')]"
Check 'control: nothing was FILTERED -- still three rows' ($fmx.Count -eq 3) "rows=$($fmx.Count)"
Check 'ASSERT: the two project cases disagree, so the project is what decided' `
  ($vcl[0] -ne $fmx[0]) "vcl-first=$($vcl[0]) fmx-first=$($fmx[0])"

# --- A project writing BOTH: no preference to express. ------------------------------
Write-Host ''
Write-Host 'a project that writes both frameworks equally -- a tie is not an answer' -ForegroundColor Cyan

$both = QNames @($libDb, $bothDb)
Check 'ASSERT: a tied project leaves the order exactly as the no-context case' `
  (($both -join '|') -eq ($bare -join '|')) `
  "tied=[$($both -join ', ')] bare=[$($bare -join ', ')]"

# --- Two project indexes: ambiguous context is NO context. --------------------------
# A guessed project is worse than none: it would reorder on the strength of a
# project the caller never named.
Write-Host ''
Write-Host 'two project indexes at once -- ambiguous, so no preference' -ForegroundColor Cyan

$amb = QNames @($libDb, $vclDb, $fmxDb)
Check 'ASSERT: two candidate projects leave the order untouched' `
  (($amb -join '|') -eq ($bare -join '|')) `
  "ambiguous=[$($amb -join ', ')] bare=[$($bare -join ', ')]"

# --- Controls. ----------------------------------------------------------------------
Write-Host ''
Write-Host 'controls' -ForegroundColor Cyan

# A single-row name cannot be ordered wrong, and the reorder must not disturb it.
$one = @(& $Exe query --name TVclThing --db $libDb --db $vclDb --json --quiet 2>&1) |
         ForEach-Object { "$_" } | Where-Object { -not $_.TrimStart().StartsWith('(') }
$oneExit = $LASTEXITCODE
$oneRows = @(($one -join "`n" | ConvertFrom-Json))
Check 'control: a single-match name is unaffected and still exits 0' `
  (($oneExit -eq 0) -and ($oneRows.Count -eq 1) -and ($oneRows[0].qualified_name -eq 'VclApp.TVclThing')) `
  "exit=$oneExit rows=$($oneRows.Count)"

# Zero hits keeps its documented contract (exit 1), which the reorder sits after.
& $Exe query --name TNoSuchThingAnywhere --db $libDb --db $vclDb --exact --json --quiet 2>&1 | Out-Null
Check 'control: zero hits still exits 1' ($LASTEXITCODE -eq 1) "exit=$LASTEXITCODE"

Write-Host ''
if ($script:Failed) { Write-Host 'RESULT: FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'RESULT: PASS' -ForegroundColor Green
exit 0
