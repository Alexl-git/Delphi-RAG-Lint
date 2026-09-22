<#
  run_autodoc_pure_not_on_side_effecting_handlers.ps1 -- pins
  docs\INBOX-autodoc-pure-mislabel-on-event-handlers.md.

  THE DEFECT: `FormTypeCheckClick` in ConvRules.MainForm.pas writes
  `FFormTypeRows[i].Skipped := ...` -- an array-element-of-record field write
  -- and still renders `<para>Pure</para>`. Root cause: DRagLint.Doc.
  SymbolFacts.WalkFieldRW's assignment handling only recognises a BARE-
  IDENTIFIER lhs as a field write; any other shape (an indexed lhs, `A[i] :=`,
  or an indexed-then-dotted one, `A[i].F :=`) was walked as a READ of its own
  subtree instead. So the 'Writes:' fact never saw the write, and 'Pure' (v(
  ADP3 T13), DRagLint.Doc.Regions.pas ~2202) is DERIVED from WritesFields
  being empty -- a downstream symptom of the missing Writes: entry, not an
  independent bug in the render gate itself.

  PURITY V2 (2026-09-22) RENAMED THE LINE AND CHANGED WHAT PROVES IT. The fact
  is now 'Effect-free (proven)', read from symbol_facts.effect_free, which the
  `purity` resolve stage writes by translating every callee's effect summary
  through the caller's arguments to a fixpoint. Both assertions below are kept,
  and both still mean what they meant -- but the POSITIVE side now holds for a
  different and stronger reason: PureAdd renders the line because the stage
  PROVED it (effect_free = 1; its one callee, Helper, is itself proven), not
  because five local facts happen to be empty. The negative side is
  correspondingly stronger too: MutateRow's own-field write is a blocker in the
  stage's own model ('s'), so it is refused even if WalkFieldRW were to regress
  and the 'Writes:' pin above were the only thing left failing.

  THE FIX (DRagLint.Doc.SymbolFacts.pas, WalkFieldRW): a new
  IndexedFieldWriteBase helper recognises exactly `Ident[...] := X` and
  `Ident[...].Member := X` (mirroring WalkMutatedParams' own "A[i] := v
  cannot execute without writing through A" rule for var/out parameters, one
  dot further for a field whose declared type is an array of record) and
  marks Ident as written. A bare `Ident.Member := X` with NO index at all
  stays excluded, unchanged, for the reason WalkMutatedParams already states:
  a class-typed field's dot-write mutates the POINTEE, not the field.

  THE FIXTURE mirrors the real shape: TFixClass.MutateRow writes
  FRows[AIndex].Skipped (FRows: TArray<TRowRec>, a record array -- exactly
  ConvRules' TFormTypeRows/TFormTypeRow shape) and must NOT render the effect
  line. TFixClass.PureAdd has a body with no field write, no mutated param, no
  touches, no SQL, and calls only a proven helper -- the POSITIVE CONTROL: it
  MUST still render the line, so the two assertions cannot both pass by a
  broken/always-false gate.
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\drag-lint-pure-not-on-side-effects"
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

# NOTE (re-review N3, 2026-09-22): the unit name `uPureFix1` and `PureAdd`
# contain the registered bare-word label 'Pure'. That is harmless here -- only
# MutateRow/PureAdd are documented and neither renders a `Called from:` line
# -- and since the N1 fix a WRAPPED fact is never cut by a label substring
# anyway; run_autodoc_document_is_fixed_point.ps1 fixture 3 (`uLeakPure`) is
# the explicit pin for that hazard. Keep it in mind if this guard ever
# documents `Helper` (called from `PureAdd`).
$FixtureBody = @'
unit uPureFix1;
interface
type
  TRowRec = record
    Skipped: Boolean;
  end;
  TRows = TArray<TRowRec>;
  TFixClass = class
  private
    FRows: TRows;
    function Helper(A: Integer): Integer;
  public
    procedure MutateRow(AIndex: Integer);
    function PureAdd(A, B: Integer): Integer;
  end;
implementation
procedure TFixClass.MutateRow(AIndex: Integer);
begin
  FRows[AIndex].Skipped := True;
end;
function TFixClass.Helper(A: Integer): Integer;
begin
  Result := A;
end;
function TFixClass.PureAdd(A, B: Integer): Integer;
begin
  Result := Helper(A) + B;
end;
end.
'@
$file = Join-Path $WorkDir 'uPureFix1.pas'
Write-Ascii $file $FixtureBody

$db = Join-Path $WorkDir 'fx.sqlite'
# Every engine call pins its exit code: the assertions below read the FILE, so
# a crash would otherwise be visible only through whichever pin it happened to
# trip (review-task-1 M5).
function Invoke-Engine([string]$Label, [string[]]$EngineArgs) {
  $out = (& $Exe @EngineArgs 2>&1 | Out-String)
  $code = $LASTEXITCODE
  Check "ENGINE: $Label exits 0" ($code -eq 0) ("exit=$code " + (($out -split "`r?`n" | Where-Object { $_ -ne '' } | Select-Object -Last 1)))
}
Invoke-Engine 'index' @('index', $WorkDir, '--db', $db)

# PureAdd CALLS Helper -- the effect line never creates a managed block on its
# own (DRagLint.Doc.Regions.pas ~2187, the AHasOtherContent gate, unchanged by
# purity v2). The 'Calls:' fact is what earns PureAdd a block at all; the
# effect line applies alongside it because the purity stage proved PureAdd
# effect-free -- which requires Helper to be proven too, since a call to an
# unproven callee is itself a blocker.
Push-Location $WorkDir
try {
  Invoke-Engine 'document MutateRow' @('document', '--qname', 'uPureFix1.TFixClass.MutateRow', '--db', $db, '--apply', '--no-backup')
  Invoke-Engine 'document PureAdd'   @('document', '--qname', 'uPureFix1.TFixClass.PureAdd',   '--db', $db, '--apply', '--no-backup')
} finally { Pop-Location }

$text = (Get-Content $file -Raw)

# Returns the managed doc block (BEGIN..END, inclusive) immediately above the
# declaration line matching $Anchor -- NOT a fixed line-count window, which
# silently grabs the WRONG block once an earlier declaration's comment grows
# or shrinks by even one line (measured while writing this guard: MutateRow's
# extra Writes: line pushed PureAdd's own block out of a 15-line lookback).
# Scans backward from the anchor; stops at another declaration line before
# any BEGIN/END pair is seen, so a declaration with NO managed block returns
# just the anchor line itself, correctly reading as "no Pure block".
function BlockFor([string]$Text, [string]$Anchor) {
  $lines = $Text -split "`r?`n"
  $anchorIdx = -1
  for ($i = 0; $i -lt $lines.Count; $i++) { if ($lines[$i] -match [regex]::Escape($Anchor)) { $anchorIdx = $i; break } }
  if ($anchorIdx -lt 0) { return '' }
  $endIdx = -1
  for ($i = $anchorIdx - 1; $i -ge 0; $i--) {
    if ($lines[$i] -match 'drag-lint:auto END') { $endIdx = $i; break }
    if ($lines[$i] -match '^\s*(procedure|function)\s+\S') { break }
  }
  if ($endIdx -lt 0) { return $lines[$anchorIdx] }
  $beginIdx = -1
  for ($i = $endIdx - 1; $i -ge 0; $i--) {
    if ($lines[$i] -match 'drag-lint:auto BEGIN') { $beginIdx = $i; break }
  }
  if ($beginIdx -lt 0) { return $lines[$anchorIdx] }
  return (($lines[$beginIdx..$endIdx] -join "`n") + "`n" + $lines[$anchorIdx])
}

# Anchored on the DECLARATION line (inside the class body), not the
# implementation line -- `document --apply` writes the managed block above
# the DECLARATION, and 'procedure MutateRow' (unqualified) cannot match the
# qualified implementation line 'procedure TFixClass.MutateRow'.
$mutateBlock = BlockFor $text 'procedure MutateRow'
$pureAddBlock = BlockFor $text 'function PureAdd'

Write-Host 'MutateRow: writes FRows[AIndex].Skipped' -ForegroundColor Cyan
Write-Host "  Writes: line present = $($mutateBlock -match 'Writes:')" -ForegroundColor DarkGray
Check 'THE PIN: MutateRow''s Writes: line names FRows' `
  ($mutateBlock -match 'Writes:\s*FRows') $mutateBlock
Check 'THE PIN: MutateRow does NOT render <para>Effect-free (proven)</para>' `
  ($mutateBlock -notmatch '<para>Effect-free \(proven\)</para>') $mutateBlock
Check 'THE PIN: the retired <para>Pure</para> label is not rendered either' `
  ($mutateBlock -notmatch '<para>Pure</para>') $mutateBlock

Write-Host ''
Write-Host 'CONTROL: PureAdd has no write/mutate/touch/sql and calls only a proven helper' -ForegroundColor Cyan
Check 'CONTROL: PureAdd DOES render <para>Effect-free (proven)</para> (gate is live, not vacuous)' `
  ($pureAddBlock -match '<para>Effect-free \(proven\)</para>') $pureAddBlock
Check 'CONTROL: PureAdd does NOT render the retired <para>Pure</para>' `
  ($pureAddBlock -notmatch '<para>Pure</para>') $pureAddBlock
if ($pureAddBlock -notmatch '<para>Effect-free \(proven\)</para>') {
  Write-Host '  !! The control failed. The pin above proves nothing -- it would' -ForegroundColor Yellow
  Write-Host '  !! pass with the effect line never rendering for ANYONE, which is' -ForegroundColor Yellow
  Write-Host '  !! exactly what a broken/always-false gate looks like.' -ForegroundColor Yellow
}

Write-Host ''
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
