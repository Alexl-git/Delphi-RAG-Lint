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

  THE SAME MECHANISM, ONE LABEL OVER (review-task-1 I1, 2026-09-22): the fix
  registered two labels and left nine more unregistered. 'Overridden by:' is a
  COMMA LIST of qualified names, so a stored `Called from: A (U.pas)` directly
  followed by `Overridden by: P.TC1.M, P.TC2.M` yields the swallowed entry
  `P.TC2.M` -- plausible, and unvouchable under any project whose closure lacks
  unit P -- and `Deprecated: use X, Y` yields the bare token `Y` in the OWN
  project. Both fed back into `Called from:` forever. Fixture 2 below carries
  exactly those two adjacencies. RED on the 4fbc8c9d engine (which lacked the
  labels), GREEN once ALL_LABELS covers every renderer label AND ParseBlock
  bounds each fact at its own <para> before the wrapper is stripped.

  THE FIXTURES. Fixture 1: one interface with two implementors, whose
  declaration ALREADY carries a hand-authored managed block shaped exactly like
  a prior `document` run's output: a deliberately STALE 'Used in units:' entry
  (naming a unit that does not exist) directly followed by a correct-looking
  'Implemented by:' line -- the adjacency that triggers the swallow.
  Fixture 2: a class with a virtual method and a deprecated method, each
  called from the unit's own driver, each carrying a stored block whose
  `Called from:` line is directly followed by the reviewer's two leak shapes.

  ASSERTIONS:
    0. Every engine call exits 0 -- a crash must not surface only through the
       pins below.
    1. POSITIVE CONTROL -- the first `document --apply` DOES rewrite the stale
       non-inbound 'Complexity: 999' fact (proves the write path is live, not a
       no-op that would make every assertion below pass vacuously), and the
       'Used in units:' line IS rendered at all (so a notmatch pin cannot pass
       on an empty string).
    2. THE PINS -- after that same first run, 'Used in units:' names units
       only (neither 'TImplA' nor 'TImplB'), and neither `Called from:` line in
       fixture 2 gained `P.TC2.Hook` or `HookY`.
    3. FIXED POINT -- a second `document --apply` per symbol, with no source
       change in between, produces byte-identical file content (hash match)
       for BOTH fixture units.
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
# Runs the engine, swallows its stdout/stderr, and pins the exit code -- the
# assertions below read the FILE, so a crash would otherwise be invisible until
# a pin happened to trip over it.
function Invoke-Engine([string]$Label, [string[]]$EngineArgs) {
  $out = (& $Exe @EngineArgs 2>&1 | Out-String)
  $code = $LASTEXITCODE
  Check "ENGINE: $Label exits 0" ($code -eq 0) ("exit=$code " + (($out -split "`r?`n" | Where-Object { $_ -ne '' } | Select-Object -Last 1)))
}
function Line-Of([string]$Text, [string]$Pattern) {
  $l = ($Text -split "`r?`n" | Where-Object { $_ -match $Pattern } | Select-Object -First 1)
  if (-not $l) { return '' } else { return $l }
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

# Fixture 2 -- the reviewer's live leak shapes. Unit P does not exist in this
# closure, so `P.TC2.Hook` is exactly the entry the accumulate-only contract
# would preserve if the `Called from:` slice swallowed it; `HookY` is the
# bare token a comma inside a `Deprecated:` message yields in the OWN project.
$FixtureBody2 = @'
unit uGenFix2;
interface
type
  TBaseFix2 = class
    /// <summary>A virtual hook.</summary>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: uGenFix2.DriveFix2 (uGenFix2.pas)</para>
    /// <para>Overridden by: P.TC1.Hook, P.TC2.Hook</para>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    procedure Hook; virtual;
    /// <summary>An old hook.</summary>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: uGenFix2.DriveFix2 (uGenFix2.pas)</para>
    /// <para>Deprecated: use HookX, HookY</para>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    procedure OldHook; deprecated 'use HookX, HookY';
  end;
procedure DriveFix2;
implementation
procedure TBaseFix2.Hook;
begin
end;
procedure TBaseFix2.OldHook;
begin
end;
procedure DriveFix2;
var
  B: TBaseFix2;
begin
  B := TBaseFix2.Create;
  try
    B.Hook;
    B.OldHook;
  finally
    B.Free;
  end;
end;
end.
'@
$file2 = Join-Path $WorkDir 'uGenFix2.pas'
Write-Ascii $file2 $FixtureBody2

$db = Join-Path $WorkDir 'fx.sqlite'
Invoke-Engine 'index' @('index', $WorkDir, '--db', $db)

$Symbols = @('uGenFix1.IAnalysisFix1', 'uGenFix2.TBaseFix2.Hook', 'uGenFix2.TBaseFix2.OldHook')
Push-Location $WorkDir
try {
  foreach ($q in $Symbols) {
    Invoke-Engine "document $q (pass 1)" @('document', '--qname', $q, '--db', $db, '--apply', '--no-backup')
  }
} finally { Pop-Location }

$text1 = Get-Content $file -Raw
$hash1 = (Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash
$usedLine1 = Line-Of $text1 'Used in units:'
$text1b = Get-Content $file2 -Raw
$hash1b = (Get-FileHash -LiteralPath $file2 -Algorithm SHA256).Hash
$hookLines1 = @($text1b -split "`r?`n" | Where-Object { $_ -match 'Called from:' })
$hookCalled1 = if ($hookLines1.Count -ge 1) { $hookLines1[0] } else { '' }
$oldCalled1  = if ($hookLines1.Count -ge 2) { $hookLines1[1] } else { '' }

Write-Host 'Pass 1: document --apply against a stale existing block' -ForegroundColor Cyan
Write-Host "  Used in units: line = $usedLine1" -ForegroundColor DarkGray
Write-Host "  Hook    Called from: line = $hookCalled1" -ForegroundColor DarkGray
Write-Host "  OldHook Called from: line = $oldCalled1" -ForegroundColor DarkGray
# NOTE: 'BogusStaleUnit' is EXPECTED to survive here -- INBOUND_LABELS
# entries this store cannot vouch for are deliberately UNIONED IN, never
# dropped (TSharedFacts.MergeInboundFacts' whole accumulate-only contract).
# So the positive control below targets a NON-inbound fact instead, which
# MergeComment always fully regenerates from Facts with no preservation.
Check 'CONTROL: the stale non-inbound fact (Complexity: 999) was dropped' `
  ($text1 -notmatch 'Complexity: 999') 'Complexity: 999 present after pass 1?'
Check 'CONTROL: Used in units: line rendered (the pins below are not over an empty string)' `
  ($usedLine1 -ne '') 'no Used in units: line in uGenFix1.pas after pass 1'
Check 'THE PIN: no implementor class name (TImplA) on Used in units:' `
  ($usedLine1 -notmatch 'TImplA') $usedLine1
Check 'THE PIN: no implementor class name (TImplB) on Used in units:' `
  ($usedLine1 -notmatch 'TImplB') $usedLine1
Check 'CONTROL: both Called from: lines rendered in uGenFix2.pas' `
  ($hookLines1.Count -eq 2) "Called from: lines = $($hookLines1.Count)"
Check 'THE PIN: Hook Called from: gained no Overridden-by name (P.TC2.Hook) -- closure lacks unit P' `
  ($hookCalled1 -notmatch 'P\.TC2\.Hook') $hookCalled1
Check 'THE PIN: OldHook Called from: gained no Deprecated-message token (HookY)' `
  ($oldCalled1 -notmatch '\bHookY\b') $oldCalled1

Push-Location $WorkDir
try {
  foreach ($q in $Symbols) {
    Invoke-Engine "document $q (pass 2)" @('document', '--qname', $q, '--db', $db, '--apply', '--no-backup')
  }
} finally { Pop-Location }

$text2 = Get-Content $file -Raw
$hash2 = (Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash
$usedLine2 = Line-Of $text2 'Used in units:'
$hash2b = (Get-FileHash -LiteralPath $file2 -Algorithm SHA256).Hash

Write-Host ''
Write-Host 'Pass 2: document --apply again, no source change in between' -ForegroundColor Cyan
Write-Host "  Used in units: line = $usedLine2" -ForegroundColor DarkGray
Check 'FIXED POINT: uGenFix1 pass 2 is byte-identical to pass 1 (hash match)' `
  ($hash1 -eq $hash2) "pass1=$hash1 pass2=$hash2"
Check 'FIXED POINT: uGenFix2 pass 2 is byte-identical to pass 1 (hash match)' `
  ($hash1b -eq $hash2b) "pass1=$hash1b pass2=$hash2b"

Write-Host ''
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
