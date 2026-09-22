<#
  run_autodoc_document_is_fixed_point.ps1 -- pins
  docs\INBOX-2026-09-17-autodoc-used-in-units-gains-class-names.md.

  THE DEFECT: DRagLint.Doc.SharedFacts.ALL_LABELS (the list ParseBlock/
  NextLabelPos use to find where one stored fact's text ENDS in the flattened
  managed doc block) never learned the 'Implemented by:'/'Extended by:' labels
  RenderFactsBlock started emitting for interfaces on 2026-09-16 (commit
  02541c58). So when TSharedFacts.MergeInboundFacts re-parses an EXISTING
  managed block whose 'Used in units:' line is immediately followed by an
  'Implemented by:' line, FactContentEnd cannot find the boundary between them
  -- the 'Used in units:' slice runs on and swallows the class names off the
  'Implemented by:' line. Those swallowed names then look like caller-visible
  entries "this project's index cannot vouch for" (they are not real unit
  files), so the accumulate-only reconciliation re-inserts the plausible ones
  (bare class identifiers) back into the FRESH 'Used in units:' line on every
  subsequent `document` run -- not a fixed point, and a UNIT list gaining CLASS
  names, exactly as measured on the self-index 2026-09-17 (TEscape, TFreedState,
  TLiveness leaking onto IDataFlowAnalysis's 'Used in units:' line).

  THE FIXTURE. One interface with two implementors, whose declaration ALREADY
  carries a hand-authored managed block shaped exactly like a prior `document`
  run's output: a deliberately STALE 'Used in units:' entry (naming a unit that
  does not exist) directly followed by a correct-looking 'Implemented by:'
  line -- the adjacency that triggers the swallow.

  ASSERTIONS:
    1. POSITIVE CONTROL -- the first `document --apply` DOES rewrite the stale
       'Used in units:' entry (proves the merge write path is live, not a
       no-op that would make every assertion below pass vacuously).
    2. THE PIN -- after that same first run, 'Used in units:' names units only:
       neither implementor class name ('TImplA', 'TImplB') appears on it.
    3. FIXED POINT -- a second `document --apply`, with no source change in
       between, produces byte-identical file content (hash match). Before the
       fix this second run keeps appending: the corpus repro measured the
       class names arriving on pass 2, and this fixture reproduces the same
       shape one document-cycle earlier because the stale seed already carries
       the adjacency pass 1 would otherwise have to manufacture.
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\drag-lint-doc-fixed-point"
)
$ErrorActionPreference = 'Stop'
if (Test-Path Variable:PSNativeCommandUseErrorActionPreference) { $PSNativeCommandUseErrorActionPreference = $false }
$script:Failed = $false
function Check($n, $ok, $d = '') {
  $s = if ($ok) { 'PASS' } else { 'FAIL' }
  $c = if ($ok) { 'Green' } else { 'Red' }
  Write-Host ("  [{0}] {1} {2}" -f $s, $n, $d) -ForegroundColor $c
  if (-not $ok) { $script:Failed = $true }
}

if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
$Exe = (Resolve-Path $Exe).Path
if (Test-Path $WorkDir) { Remove-Item -Recurse -Force -LiteralPath $WorkDir }
New-Item -ItemType Directory $WorkDir | Out-Null

function Write-Ascii([string]$Path, [string]$Text) {
  $norm = $Text -replace "`r`n", "`n" -replace "`n", "`r`n"
  [System.IO.File]::WriteAllText($Path, $norm, [System.Text.Encoding]::ASCII)
}

# The pre-existing block's 'Used in units:' is deliberately wrong (names a unit
# that is not in this fixture at all) and is immediately followed by an
# 'Implemented by:' line -- the exact adjacency FactContentEnd must bound.
$FixtureBody = @'
unit uGenFix1;
interface
type
  /// <summary>An analysis contract.</summary>
  /// <remarks>
  /// <!-- drag-lint:auto BEGIN -->
  /// <para>Complexity: 999 (a deliberately stale non-inbound fact)</para>
  /// <para>Used in units: BogusStaleUnit</para>
  /// <para>Implemented by: TImplA, TImplB</para>
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  IAnalysisFix1<T> = interface
    function Get: T;
  end;
  TImplA = class(TInterfacedObject, IAnalysisFix1<Integer>)
    function Get: Integer;
  end;
  TImplB = class(TInterfacedObject, IAnalysisFix1<Integer>)
    function Get: Integer;
  end;
implementation
function TImplA.Get: Integer;
begin
  Result := 1;
end;
function TImplB.Get: Integer;
begin
  Result := 2;
end;
end.
'@
$file = Join-Path $WorkDir 'uGenFix1.pas'
Write-Ascii $file $FixtureBody

$db = Join-Path $WorkDir 'fx.sqlite'
& $Exe index $WorkDir --db $db 2>$null | Out-Null

Push-Location $WorkDir
try {
  & $Exe document --qname uGenFix1.IAnalysisFix1 --db $db --apply --no-backup 2>$null | Out-Null
} finally { Pop-Location }

$text1 = Get-Content $file -Raw
$hash1 = (Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash
$usedLine1 = ($text1 -split "`r?`n" | Where-Object { $_ -match 'Used in units:' } | Select-Object -First 1)
if (-not $usedLine1) { $usedLine1 = '' }

Write-Host 'Pass 1: document --apply against a stale existing block' -ForegroundColor Cyan
Write-Host "  Used in units: line = $usedLine1" -ForegroundColor DarkGray
# NOTE: 'BogusStaleUnit' is EXPECTED to survive here -- INBOUND_LABELS
# entries this store cannot vouch for are deliberately UNIONED IN, never
# dropped (TSharedFacts.MergeInboundFacts' whole accumulate-only contract).
# So the positive control below targets a NON-inbound fact instead, which
# MergeComment always fully regenerates from Facts with no preservation.
Check 'CONTROL: the stale non-inbound fact (Complexity: 999) was dropped' `
  ($text1 -notmatch 'Complexity: 999') 'Complexity: 999 present after pass 1?'
Check 'THE PIN: no implementor class name (TImplA) on Used in units:' `
  ($usedLine1 -notmatch 'TImplA') $usedLine1
Check 'THE PIN: no implementor class name (TImplB) on Used in units:' `
  ($usedLine1 -notmatch 'TImplB') $usedLine1

Push-Location $WorkDir
try {
  & $Exe document --qname uGenFix1.IAnalysisFix1 --db $db --apply --no-backup 2>$null | Out-Null
} finally { Pop-Location }

$text2 = Get-Content $file -Raw
$hash2 = (Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash
$usedLine2 = ($text2 -split "`r?`n" | Where-Object { $_ -match 'Used in units:' } | Select-Object -First 1)

Write-Host ''
Write-Host 'Pass 2: document --apply again, no source change in between' -ForegroundColor Cyan
Write-Host "  Used in units: line = $usedLine2" -ForegroundColor DarkGray
Check 'FIXED POINT: pass 2 is byte-identical to pass 1 (hash match)' `
  ($hash1 -eq $hash2) "pass1=$hash1 pass2=$hash2"

Write-Host ''
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
