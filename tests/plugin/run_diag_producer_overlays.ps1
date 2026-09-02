<#
  run_diag_producer_overlays.ps1 -- the two lint producers must keep SEPARATE
  overlays, and the live runner must own the gutter's lint content.

  THE DEFECT THIS PINS

    Both producers called Cache.Update, which REPLACES a file's set, so
    whichever published last won. Measured on DataCopy's uFileUtils.pas:

      CLI lint and the plugin's LIVE runner : 45 findings
      LSP publishDiagnostics                : 11

    The owner saw it as flapping: "at first no icons, then it showed more
    diagnostics and icons appeared, then after refresh it again shows very
    little". That is 45 being overwritten by 11 and back.

  WHY NOT A UNION

    The two sets are not peers. The LSP's BuildDiagnostics composes the .scm
    rules plus exactly three built-ins, so its set is a strict SUBSET of the
    live runner's. Unioning would double-report every overlapping finding.
    Owner's ruling: separate overlays first, then let the live runner own the
    gutter -- which is what GetForFile now does.

  THE ContainsKey DETAIL IS LOAD-BEARING

    Preference must be by PRESENCE, not by count. A file the live runner found
    clean is a real answer of zero; falling back to the LSP's set there would
    resurrect findings the runner had just cleared. A `Length(...) > 0` test
    would do exactly that, and would look correct.

  STATIC. There is no headless harness for the BPL -- verifying the marks
  themselves needs a live IDE, and is owner-bound. What is checkable here is
  that the wiring cannot be silently undone, which is how this regressed in the
  first place: the separation existed for the COMPILER overlay and was simply
  never extended to the second lint producer.
#>
[CmdletBinding()]
param(
  [string]$Dir = "$PSScriptRoot\..\..\src\delphi-plugin"
)
$ErrorActionPreference = 'Stop'
$script:Failed = $false
function Check($n, $ok, $d = '') {
  $s = if ($ok) { 'PASS' } else { 'FAIL' }
  $c = if ($ok) { 'Green' } else { 'Red' }
  Write-Host ("  [{0}] {1} {2}" -f $s, $n, $d) -ForegroundColor $c
  if (-not $ok) { $script:Failed = $true }
}

$cachePath = Join-Path $Dir 'DragLint.Plugin.DiagnosticCache.pas'
$edPath    = Join-Path $Dir 'DragLint.Plugin.Editor.pas'
$livePath  = Join-Path $Dir 'DragLint.Plugin.LiveDiagnostics.pas'
foreach ($p in @($cachePath, $edPath, $livePath)) {
  if (-not (Test-Path $p)) { Write-Host "FATAL: not found: $p" -ForegroundColor Red; exit 2 }
}
$cache = Get-Content $cachePath -Raw
$ed    = Get-Content $edPath    -Raw
$live  = Get-Content $livePath  -Raw

Write-Host 'The producer discriminator exists and both call sites use it' -ForegroundColor Cyan
Check 'TDragLintDiagProducer is declared'      ($cache -match 'TDragLintDiagProducer\s*=\s*\(\s*dlpLive\s*,\s*dlpLsp\s*\)')
Check 'Update takes a producer'                ($cache -match 'procedure Update\([^)]*AProducer\s*:\s*TDragLintDiagProducer')
Check 'the LSP handler publishes as dlpLsp'    ($ed   -match 'Cache\.Update\([^)]*dlpLsp')
Check 'the live runner publishes as dlpLive'   ($live -match 'Cache\s*\.?\s*Update\s*\([^)]*dlpLive')
# Both tags must be present, or "separate overlays" is one overlay again.
Check 'the two producers use DIFFERENT tags'   (($ed -match 'dlpLsp') -and ($live -match 'dlpLive') -and ($ed -notmatch 'Cache\.Update\([^)]*dlpLive'))

Write-Host 'The LSP overlay is a real field with a full lifecycle' -ForegroundColor Cyan
Check 'FLspByFile is declared' ($cache -match 'FLspByFile\s*:\s*TDictionary<string,\s*TArray<TDragLintDiagnostic>>')
Check 'FLspByFile is created'  ($cache -match 'FLspByFile\s*:=\s*TDictionary<string,\s*TArray<TDragLintDiagnostic>>\.Create')
Check 'FLspByFile is freed'    ($cache -match 'FLspByFile\.Free')
Check 'FLspByFile is cleared by Clear' ($cache -match 'FLspByFile\.Clear')
Check 'Update writes the LSP overlay when asked' ($cache -match 'if\s+AProducer\s*=\s*dlpLsp\s+then\s+Target\s*:=\s*FLspByFile')

Write-Host 'GetForFile prefers the live set BY PRESENCE, not by count' -ForegroundColor Cyan
$getFor = [regex]::Match($cache, 'function TDragLintDiagnosticCache\.GetForFile.*?end; // function', 'Singleline').Value
Check 'GetForFile located' ([bool]$getFor) ("{0} chars" -f $getFor.Length)
if ($getFor) {
  Check 'it consults the LSP overlay'          ($getFor -match 'FLspByFile')
  Check 'it decides on ContainsKey'            ($getFor -match 'FByFile\.ContainsKey')
  # The trap: a count test silently resurrects findings on a file the runner
  # just cleared. Guard against it coming back.
  Check 'it does NOT gate the live set on a count' `
    ($getFor -notmatch 'Length\(\s*LintArr\s*\)\s*>\s*0') 'a Length test would resurrect cleared findings'
  Check 'the compiler overlay is still unioned in' ($getFor -match 'LintArr \+ CompArr')
}

if ($script:Failed) { Write-Host 'RESULT: FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'RESULT: PASS' -ForegroundColor Green
exit 0
