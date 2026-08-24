<#
  run_doc_cheap_facts.ps1 -- Whole-Project Auto-Document Phase 1 / Task 3:
  the "cheap fact group" -- Overrides / Overridden by / Implements /
  Overload k of n / virtual+abstract markers -- inside the managed
  <!-- drag-lint:auto BEGIN/END --> block.

  Fixture (uCheapFacts.pas, single unit):
    - TBase.DoPaint: virtual; abstract (no body -- abstract methods can't
      have one). Expect an 'abstract' marker AND an 'Overridden by:' fact
      listing BOTH TDerived.DoPaint and TDerived2.DoPaint (transitive
      descendants of TBase that redeclare the same method name).
    - TDerived(TBase).DoPaint / TDerived2(TBase).DoPaint: override (no body
      work, just 'begin end;'). Expect an 'Overrides: ...TBase.DoPaint' fact
      on TDerived's copy (TDerived2's own block is not separately asserted --
      only that TBase's Overridden-by lists it).
    - IGreeter (interface) declares Greet; TGreeter = class(TInterfacedObject,
      IGreeter) redeclares Greet. Expect an 'Implements: ...IGreeter.Greet'
      fact on TGreeter.Greet (NAME-BASED match -- no signature verification;
      see the task report for the caveat).
    - TLogger.Log(const S: string) / Log(const N: Integer): two overloads.
      Expect 'Overload 1 of 2' on the first (S), proving the sibling-overload
      set (2 members) and self-ordinal (1) are both genuinely computed.
      (Log(const N)'s OWN block is NOT asserted -- see the DISCOVERED
      PRE-EXISTING BUG note below; it is structurally unreachable via this
      CLI today, unrelated to Task 3's gather/render logic.)
    - TCalc.Combine: THREE overloads sharing one name, in a different class.
      Expect 'Overload 1 of 3' on the first-declared -- proves OverloadCount
      genuinely tracks the sibling-set SIZE (2 vs 3), not a hard-coded '2'.

  DISCOVERED PRE-EXISTING BUG (out of scope for Task 3; NOT introduced or
  fixed here -- flagged in the task report): TDocumenter.BuildFor
  (DRagLint.Doc.Document.pas) resolves a decl via
  'AStore.FindSymbolsByQualifiedName(AQName); Sym := Syms[0];' -- i.e. PURELY
  by qualified-name text, always taking the first row. TWO overloads of the
  same method share the IDENTICAL qualified_name (verified via
  'query --name Log --json': both uCheapFacts.TLogger.Log), so BuildFor can
  NEVER resolve to the second/third overload, no matter which physical
  TSymbol row triggered the call -- confirmed empirically: document --unit's
  per-declaration loop (DRagLint.Doc.Batch.pas) calls
  BuildFor(Sym.QualifiedName) once per row, but for an overloaded name BOTH
  calls collapse onto the SAME Syms[0], producing a DUPLICATED block above
  the first-declared overload and NO block at all above the others. This
  bug lives entirely in Doc.Document.pas/Doc.Batch.pas (outside Task 3's
  authorized file list: DRagLint.Doc.Facts.pas + DRagLint.Doc.Regions.pas
  only) and affects EVERY doc-source fact for an overloaded method, not
  just Overload k-of-n -- fixing it is a separate, larger change (BuildFor
  would need to accept an already-resolved TSymbol/id, not just a qname
  string) and is explicitly out of scope here.

  PRE-EXISTING ENGINE QUIRK #2 (also out of scope, do not "fix" via this
  test): every
  class with an implemented method also picks up a spurious self-referential
  reference fact on the CLASS symbol itself (each qualified impl header,
  e.g. 'procedure TDerived.DoPaint;', emits a type_use ref to 'TDerived' that
  FindUnresolvedNameCallers name-matches). Register K17: this said
  "'Called from:' fact" until 2026-07-29, which is pre-T4 text -- a class is not
  a call target (Core.Model.CanBeCallTarget), so T4 renders the same list under
  'Used by:'. The reference itself, and the fact that it is spurious, are
  unchanged; only the label is. This affects the CLASS blocks, not
  the per-method blocks asserted here, but it does mean batch mode documents
  MORE than just the 6 method-like symbols below (TBase/TDerived/TDerived2/
  TGreeter/TLogger class blocks appear too) -- assertions below are therefore
  PRESENCE-based (does this method's OWN block contain fact X), never exact
  full-file/full-block equality or exact docCount, so that quirk cannot make
  this test flap.

  Run from a NEUTRAL CWD ($env:TEMP\drag-lint-doc-cheap-facts); a fresh copy +
  a TEMP db (never a real corpus db).
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\drag-lint-doc-cheap-facts"
)
$ErrorActionPreference = 'Continue'
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

$FixtureBody = @'
unit uCheapFacts;

interface

type
  TBase = class
  public
    procedure DoPaint; virtual; abstract;
  end;

  TDerived = class(TBase)
  public
    procedure DoPaint; override;
  end;

  TDerived2 = class(TBase)
  public
    procedure DoPaint; override;
  end;

  IGreeter = interface
    ['{A1B2C3D4-0001-4000-8000-000000000001}']
    function Greet: string;
  end;

  TGreeter = class(TInterfacedObject, IGreeter)
  public
    function Greet: string;
  end;

  TLogger = class
  public
    procedure Log(const S: string); overload;
    procedure Log(const N: Integer); overload;
  end;

  TCalc = class
  public
    function Combine(A, B: Integer): Integer; overload;
    function Combine(A, B, C: Integer): Integer; overload;
    function Combine(const S: string): Integer; overload;
  end;

implementation

procedure TDerived.DoPaint;
begin
end;

procedure TDerived2.DoPaint;
begin
end;

function TGreeter.Greet: string;
begin
  Result := 'hi';
end;

procedure TLogger.Log(const S: string);
begin
end;

procedure TLogger.Log(const N: Integer);
begin
end;

function TCalc.Combine(A, B: Integer): Integer;
begin
  Result := A + B;
end;

function TCalc.Combine(A, B, C: Integer): Integer;
begin
  Result := A + B + C;
end;

function TCalc.Combine(const S: string): Integer;
begin
  Result := Length(S);
end;

end.
'@
function Write-Fixture([string]$Path) {
  $norm = $FixtureBody -replace "`r`n", "`n" -replace "`n", "`r`n"
  [System.IO.File]::WriteAllText($Path, $norm, [System.Text.Encoding]::ASCII)
}

$dir  = Join-Path $WorkDir 'fx'
New-Item -ItemType Directory $dir | Out-Null
$file = Join-Path $dir 'uCheapFacts.pas'
$db   = Join-Path $dir 'fx.sqlite'
Write-Fixture $file

& $Exe index $dir --db $db 2>&1 | Out-Null
& $Exe document --unit $file --db $db --apply --no-backup 2>&1 | Out-Null
$ec = $LASTEXITCODE
Check 'document --unit exit 0' ($ec -eq 0) "ec=$ec"

$lines = [IO.File]::ReadAllLines($file)

# Finds the Nth (1-based $Occurrence) line matching $Pattern, then walks
# upward collecting the contiguous '///' block directly above it (same
# scan-upward idiom run_doc_deprecated.ps1 uses for isolating one decl's own
# managed block from a neighbor's).
function Get-DocBlockAbove([string[]]$Lines, [string]$Pattern, [int]$Occurrence = 1) {
  $hits = @()
  for ($i = 0; $i -lt $Lines.Count; $i++) { if ($Lines[$i] -match $Pattern) { $hits += $i } }
  if ($hits.Count -lt $Occurrence) { return $null }
  $idx = $hits[$Occurrence - 1]
  $blockLines = New-Object System.Collections.Generic.List[string]
  for ($i = $idx - 1; $i -ge 0; $i--) {
    if ($Lines[$i] -notmatch '^\s*///') { break }
    $blockLines.Insert(0, $Lines[$i])
  }
  return ([string]::Join("`n", $blockLines.ToArray()) -replace '</?para>', '')
}

Write-Host 'TBase.DoPaint: abstract marker + Overridden by (both descendants)' -ForegroundColor Cyan
$baseBlock = Get-DocBlockAbove $lines '^\s*procedure DoPaint; virtual; abstract;\s*$' 1
Check 'TBase.DoPaint has a managed block' (($null -ne $baseBlock) -and ($baseBlock -match '<!-- drag-lint:auto BEGIN -->')) $baseBlock
Check 'TBase.DoPaint has an abstract marker line' ($null -ne $baseBlock -and $baseBlock -match '(?m)^\s*///\s*abstract\s*$') $baseBlock
Check 'TBase.DoPaint Overridden by lists TDerived.DoPaint'  ($null -ne $baseBlock -and $baseBlock -match 'Overridden by:.*TDerived\.DoPaint')  $baseBlock
Check 'TBase.DoPaint Overridden by lists TDerived2.DoPaint' ($null -ne $baseBlock -and $baseBlock -match 'Overridden by:.*TDerived2\.DoPaint') $baseBlock

Write-Host ''
Write-Host 'TDerived.DoPaint: Overrides fact' -ForegroundColor Cyan
$derivedBlock = Get-DocBlockAbove $lines '^\s*procedure DoPaint; override;\s*$' 1
Check 'TDerived.DoPaint has a managed block' (($null -ne $derivedBlock) -and ($derivedBlock -match '<!-- drag-lint:auto BEGIN -->')) $derivedBlock
Check 'TDerived.DoPaint Overrides TBase.DoPaint' ($null -ne $derivedBlock -and $derivedBlock -match 'Overrides:.*TBase\.DoPaint') $derivedBlock

Write-Host ''
Write-Host 'TGreeter.Greet: Implements fact (name-based)' -ForegroundColor Cyan
# Occurrence 2: the pattern also matches IGreeter's OWN 'function Greet: string;'
# member declaration (which appears FIRST in the file and carries no doc block
# of its own) -- TGreeter's redeclaration is the SECOND occurrence.
$greeterBlock = Get-DocBlockAbove $lines '^\s*function Greet: string;\s*$' 2
Check 'TGreeter.Greet has a managed block' (($null -ne $greeterBlock) -and ($greeterBlock -match '<!-- drag-lint:auto BEGIN -->')) $greeterBlock
Check 'TGreeter.Greet Implements IGreeter.Greet' ($null -ne $greeterBlock -and $greeterBlock -match 'Implements:.*IGreeter\.Greet') $greeterBlock

Write-Host ''
Write-Host 'TLogger.Log overloads: k of n ordinal (2-member group)' -ForegroundColor Cyan
$logSBlock = Get-DocBlockAbove $lines '^\s*procedure Log\(const S: string\); overload;\s*$' 1
Check 'Log(const S) has a managed block' (($null -ne $logSBlock) -and ($logSBlock -match '<!-- drag-lint:auto BEGIN -->')) $logSBlock
Check 'Log(const S) is Overload 1 of 2' ($null -ne $logSBlock -and $logSBlock -match 'Overload 1 of 2') $logSBlock

Write-Host ''
Write-Host 'TCalc.Combine overloads: k of n count (3-member group, proves n is not hard-coded)' -ForegroundColor Cyan
$combineBlock = Get-DocBlockAbove $lines '^\s*function Combine\(A, B: Integer\): Integer; overload;\s*$' 1
Check 'Combine(A,B) has a managed block' (($null -ne $combineBlock) -and ($combineBlock -match '<!-- drag-lint:auto BEGIN -->')) $combineBlock
Check 'Combine(A,B) is Overload 1 of 3' ($null -ne $combineBlock -and $combineBlock -match 'Overload 1 of 3') $combineBlock

Write-Host ''
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
