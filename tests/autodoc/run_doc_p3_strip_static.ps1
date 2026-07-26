<#
  run_doc_p3_strip_static.ps1 -- Auto-Document Phase 3, Task 2 (review Finding
  2): `document --strip` exercised against a STATIC fixture with every marker
  already baked in by hand -- no `document --apply` run at all. Covers the
  ground run_doc_p3_strip.ps1 cannot reach (its fixture's trivial, caller-free
  routines never produce a facts block, so rules 2/3/4 and the multi-line
  branch of rule 1 never fire there):

    * FenceOnly           -- rule 2 (AUTO_BEGIN..AUTO_END) + rule 4's POSITIVE
                              case: the <remarks> pair's ONLY content is the
                              fence, so once the fence is gone the pair is
                              dropped too. The hand <summary> alongside it
                              proves the drop is scoped to <remarks>, not a
                              whole-region (rule 5) collapse.
    * FenceWithProse      -- rule 2 where hand prose ALSO shares the
                              <remarks> pair: only the fence lines go; the
                              prose and the tags around it survive (rule 4
                              must NOT fire here).
    * LegacyParam         -- rule 3 (legacy trailing AUTO_PARAM sentinel):
                              the whole <param> line is dropped.
    * MultiLineReturns    -- rule 1's multi-line branch: a marked <returns>
                              tag whose value spans two physical /// lines
                              (AUTO_MARK never actually produces this today,
                              per EmitTagged/ObservedSuffix always being
                              single-line -- but the brief calls the
                              continuation-scan out explicitly as something a
                              marked tag CAN do via EmitTagged, so it is
                              exercised here by construction).
    * UntouchedEmptyRemarks / UntouchedBareLineRemarks -- review Finding 1
                              regression cases: a HAND-WRITTEN <remarks> pair
                              that the engine never touched (nothing between
                              the tags, or only a bare '///' line between
                              them) must survive completely untouched --
                              rule 4's AnyDeleted gate is what a broken build
                              would fail here (the pre-fix code deleted both
                              tag lines, and for the bare-line case, ALSO
                              orphaned that line since it was never itself
                              marked deleted).
    * GapDoc              -- a marked <summary>/<param> comment separated
                              from its declaration by a blank line (the 1-line
                              gap TDocumenter's own FindDocRegionAbove
                              tolerates). Used by the --qname scoped-strip
                              scenario below to prove StripSymbolRegion's
                              ADeclLine-2/ADeclLine-1 gap arithmetic finds the
                              region correctly.

  SCENARIO A -- whole-file strip (`document --unit --strip --apply`, fresh
  copy, no prior `document` run): byte-compares the ENTIRE resulting file
  against a hand-computed expected text, and asserts the exact
  "stripped: 4 tags, 2 blocks" count (LegacyParam + MultiLineReturns +
  GapDoc's summary + GapDoc's param = 4 tags; FenceOnly + FenceWithProse's
  fences = 2 blocks -- rule 4's own pair-drops are not separately counted,
  same as rule 5's whole-region collapse).

  SCENARIO B -- `document --qname strip_static.GapDoc --strip --apply` on a
  SEPARATE fresh copy: asserts ONLY GapDoc's two marked lines are gone
  (exact count "stripped: 2 tags, 0 blocks") and every OTHER function's
  markers -- FenceOnly's fence in particular -- are completely untouched,
  proving the scoped strip does not leak into neighbouring doc regions.

  SCENARIO C -- `document --unit --strip --stubs` (no --apply needed) exits 2
  with the mutual-exclusion error.

  Run from a NEUTRAL CWD (C:\TEMP), pwsh 7.
#>
[CmdletBinding()]
param([string]$Exe = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe")

$ErrorActionPreference = 'Continue'
function Check($n,$ok,$d=''){ Write-Host ("[{0}] {1} {2}" -f (@('FAIL','PASS')[[int]$ok]),$n,$d) -ForegroundColor (@('Red','Green')[[int]$ok]); if(-not $ok){$script:Failed=$true} }
$script:Failed = $false

$exePath = (Resolve-Path $Exe).Path
$fixture = (Resolve-Path (Join-Path $PSScriptRoot 'fixtures\docp3\strip_static.pas')).Path

# The exact hand-computed post-whole-file-strip text (Scenario A). Written as
# an LF here-string then normalized to CRLF, matching every sibling runner's
# own fixture-writing convention (e.g. run_doc_returns.ps1's Write-Fixture).
$ExpectedAfterA = @'
unit strip_static;

interface

/// <summary>Hand summary that survives.</summary>
function FenceOnly: Integer;

/// <summary>Hand summary that survives too.</summary>
/// <remarks>
/// Hand prose that survives.
/// </remarks>
function FenceWithProse: Integer;

/// <summary>Hand summary.</summary>
function LegacyParam(AValue: Integer): Integer;

/// <summary>Hand summary for multi-line returns.</summary>
function MultiLineReturns: Integer;

/// <summary>Hand summary only, untouched.</summary>
/// <remarks>
/// </remarks>
function UntouchedEmptyRemarks: Integer;

/// <summary>Hand summary only, untouched too.</summary>
/// <remarks>
///
/// </remarks>
function UntouchedBareLineRemarks: Integer;


function GapDoc(AValue: Integer): Integer;

implementation

function FenceOnly: Integer;
begin
  Result := 1;
end;

function FenceWithProse: Integer;
begin
  Result := 2;
end;

function LegacyParam(AValue: Integer): Integer;
begin
  Result := AValue;
end;

function MultiLineReturns: Integer;
begin
  Result := 3;
end;

function UntouchedEmptyRemarks: Integer;
begin
  Result := 4;
end;

function UntouchedBareLineRemarks: Integer;
begin
  Result := 5;
end;

function GapDoc(AValue: Integer): Integer;
begin
  Result := AValue + 1;
end;

end.
'@
# PowerShell's @'...'@ here-string drops the FINAL newline immediately before
# the closing '@ delimiter -- re-add it so this matches the fixture's own
# trailing newline (TTextEditApplier.Apply preserves a trailing terminator
# when the original file had one, which this fixture does).
$ExpectedAfterA = (($ExpectedAfterA -replace "`r`n", "`n") -replace "`n", "`r`n") + "`r`n"

Push-Location C:\TEMP
try {
  # --- Scenario A: whole-file strip, byte-compare against the expected text ---
  $scratchA = Join-Path C:\TEMP 'draglint_docp3stripstaticA'
  if (Test-Path $scratchA) { Remove-Item $scratchA -Recurse -Force }
  New-Item -ItemType Directory -Path $scratchA | Out-Null
  $targetA = Join-Path $scratchA 'strip_static.pas'
  $dbA     = Join-Path $scratchA 'a.sqlite'
  Copy-Item $fixture $targetA -Force

  & $exePath index $scratchA --db $dbA 2>&1 | Out-Null
  Check 'Scenario A: index exits 0' ($LASTEXITCODE -eq 0)

  $dryA = (& $exePath document --unit $targetA --db $dbA --strip 2>&1) -join "`n"
  Check 'Scenario A: dry-run exits 0' ($LASTEXITCODE -eq 0)
  Check 'Scenario A: dry-run reports the exact counts (4 tags, 2 blocks)' `
    ($dryA -match 'stripped:\s*4\s*tags,\s*2\s*blocks') $dryA

  & $exePath document --unit $targetA --db $dbA --strip --apply 2>&1 | Out-Null
  Check 'Scenario A: strip --apply exits 0' ($LASTEXITCODE -eq 0)

  $actualA = [IO.File]::ReadAllText($targetA)
  Check 'Scenario A: whole-file strip result is byte-identical to the hand-computed expected text' `
    ($actualA -ceq $ExpectedAfterA) "actual length=$($actualA.Length) expected length=$($ExpectedAfterA.Length)"

  # --- Scenario B: --qname --strip scoped to GapDoc only ---
  $scratchB = Join-Path C:\TEMP 'draglint_docp3stripstaticB'
  if (Test-Path $scratchB) { Remove-Item $scratchB -Recurse -Force }
  New-Item -ItemType Directory -Path $scratchB | Out-Null
  $targetB = Join-Path $scratchB 'strip_static.pas'
  $dbB     = Join-Path $scratchB 'b.sqlite'
  Copy-Item $fixture $targetB -Force

  & $exePath index $scratchB --db $dbB 2>&1 | Out-Null
  Check 'Scenario B: index exits 0' ($LASTEXITCODE -eq 0)

  $qOut = (& $exePath document --qname strip_static.GapDoc --db $dbB --strip --apply 2>&1) -join "`n"
  Check 'Scenario B: --qname --strip --apply exits 0' ($LASTEXITCODE -eq 0)
  Check 'Scenario B: reports the exact counts (2 tags, 0 blocks -- GapDoc only)' `
    ($qOut -match 'stripped:\s*2\s*tags,\s*0\s*blocks') $qOut

  $textB = [IO.File]::ReadAllText($targetB)
  Check 'Scenario B: GapDoc''s marked <summary> line is gone' `
    (-not $textB.Contains('/// <summary><!-- drag-lint:auto --></summary>'))
  Check 'Scenario B: GapDoc''s marked <param> line is gone' `
    (-not $textB.Contains('/// <param name="AValue"><!-- drag-lint:auto --></param>'))
  Check 'Scenario B: GapDoc decl survives (scope did not delete the declaration itself)' `
    ($textB -match 'function GapDoc\(AValue: Integer\): Integer;')
  Check 'Scenario B: an UNRELATED region (FenceOnly''s fence) is completely untouched' `
    ($textB.Contains('<!-- drag-lint:auto BEGIN -->') -and $textB.Contains('Some facts line here.') -and $textB.Contains('<!-- drag-lint:auto END -->'))
  Check 'Scenario B: LegacyParam''s legacy AUTO_PARAM line is completely untouched' `
    ($textB.Contains('/// <param name="AValue">Hand desc.</param> <!-- drag-lint:auto param -->'))
  Check 'Scenario B: MultiLineReturns'' two-line marked tag is completely untouched' `
    ($textB.Contains('/// <returns><!-- drag-lint:auto -->Observed: a mined case that') -and $textB.Contains('/// spans two physical lines.</returns>'))

  # --- Scenario C: --strip + --stubs exits 2 (no --apply needed) ---
  & $exePath document --unit $targetA --db $dbA --strip --stubs 2>&1 | Out-Null
  Check 'Scenario C: --strip + --stubs exits 2' ($LASTEXITCODE -eq 2)
} finally { Pop-Location }

if($script:Failed){ Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
