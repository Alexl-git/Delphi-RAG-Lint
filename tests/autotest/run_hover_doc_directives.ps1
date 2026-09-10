<#
  run_hover_doc_directives.ps1 -- PLAN A T3.

  ONE FORMATTER, TWO SURFACES. TDocRegions.FormatPhase2FactLines is the single
  place that renders fact lines for BOTH the managed doc block (via
  RenderFactsBlock) and hover (LSP, CLI and plugin). If the `Directives:` line
  were added to only one of them they would drift, and the drift would be
  invisible until someone compared a tooltip with a source comment by eye. This
  guard asserts the line on both surfaces and then asserts the two agree.

  ORDER OF ASSERTIONS IS NOT COSMETIC (spec MINOR 11). PRESENCE is asserted
  first and EQUALITY second. On an unfixed build both surfaces render NO
  Directives line, so a byte-equality check alone would compare '' with '' and
  PASS -- a guard that is green precisely because the feature is missing. That is
  the "guard that cannot fail" shape this repo has now recorded five times, so
  equality here is strictly the drift check, never the existence check.

  THE SURFACE IS THE CLI hover, NOT THE LSP -- deliberately, and the plan says
  why: LSP.Server only builds fact lines when a doc row already exists
  (`if Doc.HasContent`), so on an UNDOCUMENTED fixture the LSP would render
  nothing and this guard would read a real feature as broken. Measured on the
  pre-change engine: CLI hover on a free routine already returns facts=[Pure]
  with no doc row, so the CLI path is live without one.

  DISPLAY FORM vs STORED FORM, stated because they differ ON PURPOSE:
    stored   symbols.directives  = 'virtual overload stdcall'   (space-joined)
    displayed  Directives:         virtual; overload; stdcall   ('; '-joined)
  The column is a machine-readable canonical list; the fact line is written the
  way a Delphi programmer writes directives. Both are asserted, so neither can
  drift into the other.

  MEASURED RED, THEN GREEN -- pre-change engine
  (scratchpad\engine-preA, extractor 1.14.0-alpha,
   sha256 C47510745578EB3C4F501EBEB3BCD832E8B3F9A1F3357F0FF8B28EF847B12C34):
  hover facts for MVirtual/MCombo are [] and the applied doc block carries no
  Directives line, so every presence assertion fails. See the T6 block below.

  VERBATIM RED, captured 2026-09-09 22:49 against that engine:

    engine: extractor=1.14.0-alpha exe=C:\TEMP\claude\c--Projects-Delphi-RAG-lint\46ac75c6-8655-4a1c-9ca4-6ea10187bdad\scratchpad\engine-preA\drag-lint.exe
      [PASS] index exits 0 exit=0
      [FAIL] hover MVirtual HAS a Directives fact got: ABSENT
      [FAIL] hover MCombo   HAS a Directives fact got: ABSENT
      [PASS] hover MPlain has NO Directives fact got:
      [FAIL] doc block for MVirtual HAS a Directives line got: ABSENT
      [FAIL] doc block for MCombo   HAS a Directives line got: ABSENT
      [PASS] doc block for MPlain has NO Directives line got:
      [FAIL] MVirtual: drift check is REACHABLE (both surfaces present) skipped -- one or both surfaces rendered nothing, so equality would be vacuous
    FAIL

#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\drag-lint-hover-doc-directives"
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

$info = (& $Exe info --json 2>$null) -join "`n" | ConvertFrom-Json
Write-Host ("engine: extractor={0} exe={1}" -f $info.extractor_version, $Exe) -ForegroundColor Cyan

function Write-Ascii([string]$Path, [string]$Body) {
  $norm = $Body -replace "`r`n", "`n" -replace "`n", "`r`n"
  $dir = Split-Path -Parent $Path
  if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Force $dir | Out-Null }
  [System.IO.File]::WriteAllText($Path, $norm, [System.Text.Encoding]::ASCII)
}

$work = Join-Path $WorkDir 'fixture'
$unit = Join-Path $work 'uHov.pas'
Write-Ascii $unit @'
unit uHov;

interface

type
  THovKit = class(TObject)
  public
    procedure MVirtual; virtual;
    procedure MCombo; virtual; overload; stdcall;
    procedure MPlain;
  end;

implementation

procedure THovKit.MVirtual;
begin
end;

procedure THovKit.MCombo;
begin
end;

procedure THovKit.MPlain;
begin
end;

end.
'@

$db = Join-Path $WorkDir 'hov.sqlite'
$null = & $Exe index $work --db $db 2>$null
Check 'index exits 0' ($LASTEXITCODE -eq 0) "exit=$LASTEXITCODE"

function Get-HoverFacts([string]$QName) {
  $raw = (& $Exe hover --qname $QName --db $db --format json 2>$null) -join "`n"
  if ([string]::IsNullOrWhiteSpace($raw)) { return @() }
  return @(($raw | ConvertFrom-Json).facts)
}
function Get-DirectivesFact([string[]]$Facts) {
  return @($Facts | Where-Object { $_ -match '^\s*Directives:' }) | Select-Object -First 1
}

# --- surface 1: hover ---------------------------------------------------------
Write-Host ''
Write-Host 'SURFACE 1: CLI hover' -ForegroundColor Cyan
$hovVirtual = Get-DirectivesFact (Get-HoverFacts 'uHov.THovKit.MVirtual')
$hovCombo   = Get-DirectivesFact (Get-HoverFacts 'uHov.THovKit.MCombo')
$hovPlain   = Get-DirectivesFact (Get-HoverFacts 'uHov.THovKit.MPlain')

Check "hover MVirtual HAS a Directives fact" ($null -ne $hovVirtual) "got: $(if ($null -eq $hovVirtual) { 'ABSENT' } else { $hovVirtual })"
Check "hover MCombo   HAS a Directives fact" ($null -ne $hovCombo)   "got: $(if ($null -eq $hovCombo)   { 'ABSENT' } else { $hovCombo })"
if ($null -ne $hovVirtual) { Check "hover MVirtual reads 'Directives: virtual'" (($hovVirtual.Trim()) -eq 'Directives: virtual') "got: '$($hovVirtual.Trim())'" }
if ($null -ne $hovCombo)   { Check "hover MCombo reads 'Directives: virtual; overload; stdcall'" (($hovCombo.Trim()) -eq 'Directives: virtual; overload; stdcall') "got: '$($hovCombo.Trim())'" }
# NEGATIVE
Check "hover MPlain has NO Directives fact" ($null -eq $hovPlain) "got: $hovPlain"

# --- surface 2: the managed doc block ----------------------------------------
Write-Host ''
Write-Host 'SURFACE 2: the managed doc block (document --apply)' -ForegroundColor Cyan
foreach ($q in @('uHov.THovKit.MVirtual','uHov.THovKit.MCombo','uHov.THovKit.MPlain')) {
  $null = & $Exe document --qname $q --db $db --apply --no-backup 2>$null
}
$src = [System.IO.File]::ReadAllText($unit)

function Get-DocDirectivesLine([string]$Source, [string]$MethodName) {
  # Walk UPWARD from the declaration and stop at the first line that is not part
  # of ITS OWN doc comment.
  #
  # The first version scanned a fixed 40-line window backwards and took the
  # nearest Directives: line it found. That is wrong in the one direction that
  # matters: for a method with NO block of its own it happily returned the
  # PREVIOUS method's line, so the negative control read 'virtual' for MPlain --
  # and MCombo, whose real value is 'virtual; overload; stdcall', also reported
  # 'virtual'. Both were the first method's block. A window is not a boundary.
  $lines = $Source -split "`r?`n"
  for ($i = 0; $i -lt $lines.Count; $i++) {
    if ($lines[$i] -match "procedure\s+$MethodName\b") {
      for ($j = $i - 1; $j -ge 0; $j--) {
        $t = $lines[$j].Trim()
        if ($t -eq '') { continue }
        # Only a doc-comment line may be walked through; anything else is the
        # end of this declaration's own block.
        if ($t -notmatch '^///') { return $null }
        if ($t -match 'Directives:\s*(.+?)\s*(?:</para>)?\s*$') {
          return ($Matches[1] -replace '</para>\s*$', '').Trim()
        }
      }
      return $null
    }
  }
  return $null
}

$docVirtual = Get-DocDirectivesLine $src 'MVirtual'
$docCombo   = Get-DocDirectivesLine $src 'MCombo'
$docPlain   = Get-DocDirectivesLine $src 'MPlain'

Check "doc block for MVirtual HAS a Directives line" ($null -ne $docVirtual) "got: $(if ($null -eq $docVirtual) { 'ABSENT' } else { $docVirtual })"
Check "doc block for MCombo   HAS a Directives line" ($null -ne $docCombo)   "got: $(if ($null -eq $docCombo)   { 'ABSENT' } else { $docCombo })"
Check "doc block for MPlain has NO Directives line" ($null -eq $docPlain) "got: $docPlain"

# --- the drift check, LAST and only once both surfaces are known present ------
Write-Host ''
Write-Host 'DRIFT: the two surfaces must agree (asserted only after presence)' -ForegroundColor Cyan
if (($null -ne $hovVirtual) -and ($null -ne $docVirtual)) {
  $h = ($hovVirtual -replace '^\s*Directives:\s*', '').Trim()
  Check "MVirtual: hover and doc block render the SAME directives" ($h -eq $docVirtual.Trim()) "hover='$h' doc='$($docVirtual.Trim())'"
} else {
  Check "MVirtual: drift check is REACHABLE (both surfaces present)" $false 'skipped -- one or both surfaces rendered nothing, so equality would be vacuous'
}

Write-Host ''
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
