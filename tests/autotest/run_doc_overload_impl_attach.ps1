<#
  run_doc_overload_impl_attach.ps1 -- Bug B fix (ADP1): SetRoutineImplRange
  (DRagLint.Parser.Delphi13.pas ~912) attached a routine's implementation
  body span (ImplStartLine/ImplEndLine) to a decl symbol by NAME ONLY +
  "first not-yet-stamped match, scanning downto 0" (reverse symbol-table
  order). For OVERLOADED methods this is a pure index-position pairing that
  ignores which impl body actually belongs to which decl: the FIRST impl
  body encountered during the Walk always gets stamped onto the
  LAST-declared (highest symbol-table index) unstamped overload, regardless
  of which overload it is the real implementation of. See
  .superpowers/sdd/adp1-bugB-brief.md.

  Fix: SetRoutineImplRange gains an ASignature parameter (built by the SAME
  ProcSignatureOf(HdrNode, AState.Source) that produced the decl's own
  stored Signature at emit time). It now PREFERS an unstamped candidate
  whose Name AND Signature both match; it FALLS BACK to today's exact
  name-only "first unstamped, downto 0" behavior when no signature match is
  found (preserves non-overloaded / impl-only-free-routine / no-signature
  cases byte-for-byte).

  Fixture (uOverloadImplAttach.pas): TCalc exposes two overloads of Combine,
  with the impl bodies in the SAME order as the interface declarations
  (the idiomatic/common ordering):
    function Combine(A, B: Integer): Integer; overload;    // decl 1, line 8
    function Combine(const S: string): Integer; overload;  // decl 2, line 9
  implementation
    function TCalc.Combine(A, B: Integer): Integer;         // impl 1 (of decl 1)
      Result := A + B;
    function TCalc.Combine(const S: string): Integer;       // impl 2 (of decl 2)
      Result := Length(S);

  EMPIRICALLY VERIFIED (against the pre-fix exe, by hand before writing this
  test) that THIS specific ordering is the one that reproduces the bug --
  NOT a reversed-impl-order fixture. Because the buggy "downto 0, first
  unstamped" scan always grabs the HIGHEST remaining symbol-table index
  (i.e. the LAST-declared overload) for whichever impl is processed FIRST,
  a fixture with impls in the exact REVERSE of decl order cancels out for
  exactly two overloads and would give a false-GREEN even on the buggy exe.
  Impls in the SAME order as decls does NOT cancel out and genuinely
  reproduces the reported symptom (Combine(A, B: Integer) mining
  'Length(S)'): decl 1 (A, B) incorrectly gets stamped with impl 2's span
  (lines 19-22, Result := Length(S)) and decl 2 (S) incorrectly gets
  stamped with impl 1's span (lines 14-17, Result := A + B).

  Asserts (PER OVERLOAD, distinguished by the `signature` column so this
  cannot pass by picking the wrong row):
    1. (primary, direct DB) Combine(A, B: Integer)'s impl_start_line/
       impl_end_line point at ITS OWN body (14/17); Combine(const S:
       string)'s point at ITS OWN body (19/22).
    2. (secondary, end-to-end) `document --unit --apply` mines 'A + B' into
       the <returns> above Combine(A, B: Integer) and 'Length(S)' into the
       <returns> above Combine(const S: string) -- never swapped.

  RED (pre-fix exe): assertion 1 shows the two impl_start_line values
  SWAPPED (8->19/22 instead of 14/17); assertion 2 shows 'Length(S)' mined
  above the (A, B) overload and 'A + B' mined above the (S) overload.

  Run from a NEUTRAL CWD ($env:TEMP\drag-lint-doc-overload-impl-attach); a
  fresh copy + a TEMP db (never a real corpus db).
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\drag-lint-doc-overload-impl-attach",
  [string]$Python  = 'C:\Python314\python.exe'
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
unit uOverloadImplAttach;

interface

type
  TCalc = class
  public
    function Combine(A, B: Integer): Integer; overload;
    function Combine(const S: string): Integer; overload;
  end;

implementation

function TCalc.Combine(A, B: Integer): Integer;
begin
  Result := A + B;
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
$file = Join-Path $dir 'uOverloadImplAttach.pas'
$db   = Join-Path $dir 'fx.sqlite'
Write-Fixture $file

Write-Host 'Indexing fixture (FRESH db, current exe)' -ForegroundColor Cyan
$indexOut = & $Exe index $dir --db $db 2>&1
$indexExit = $LASTEXITCODE
Check 'index exits 0' ($indexExit -eq 0) "exit=$indexExit; $($indexOut | Select-Object -Last 1)"

# --- 1. Primary: per-overload impl_start_line/impl_end_line, direct DB read. ------
Write-Host ''
Write-Host 'Per-overload impl_start_line/impl_end_line (direct DB read, distinguished by signature)' -ForegroundColor Cyan
$chk = Join-Path $WorkDir 'check.py'
Set-Content -Path $chk -Encoding ascii -Value @'
import sqlite3, sys
c = sqlite3.connect("file:" + sys.argv[1] + "?mode=ro", uri=True)
for sig, s, e in c.execute(
    "SELECT signature, impl_start_line, impl_end_line FROM symbols "
    "WHERE qualified_name='uOverloadImplAttach.TCalc.Combine' ORDER BY signature"):
    print(sig, s, e)
c.close()
'@
$rows = & $Python $chk $db
Write-Host ("  DB: " + ($rows -join ' | ')) -ForegroundColor DarkGray

$byIntSig = "(A, B: Integer): Integer"
$byStrSig = "(const S: string): Integer"
$got = @{}
foreach ($line in $rows) {
  if ($line -match '^(.*): Integer\s+(\d+)\s+(\d+)\s*$') {
    $sig = $Matches[1] + ': Integer'
    $got[$sig] = @{ Start = [int]$Matches[2]; End = [int]$Matches[3] }
  }
}

Check "Combine(A, B: Integer) row found"    ($got.ContainsKey($byIntSig)) "rows=$($rows -join ' | ')"
Check "Combine(const S: string) row found"  ($got.ContainsKey($byStrSig)) "rows=$($rows -join ' | ')"

if ($got.ContainsKey($byIntSig)) {
  Check "Combine(A, B: Integer) impl_start_line == 14 (ITS OWN body, not Combine(S)'s)" `
    ($got[$byIntSig].Start -eq 14) "got=$($got[$byIntSig].Start)"
  Check "Combine(A, B: Integer) impl_end_line == 17" `
    ($got[$byIntSig].End -eq 17) "got=$($got[$byIntSig].End)"
}
if ($got.ContainsKey($byStrSig)) {
  Check "Combine(const S: string) impl_start_line == 19 (ITS OWN body, not Combine(A,B)'s)" `
    ($got[$byStrSig].Start -eq 19) "got=$($got[$byStrSig].Start)"
  Check "Combine(const S: string) impl_end_line == 22" `
    ($got[$byStrSig].End -eq 22) "got=$($got[$byStrSig].End)"
}

# --- 2. Secondary (end-to-end): document --unit mines the RIGHT expression per overload. ---
Write-Host ''
Write-Host 'document --unit --apply: mined <returns> attaches to the right overload' -ForegroundColor Cyan
& $Exe document --unit $file --db $db --apply --no-backup 2>&1 | Out-Null
$docExit = $LASTEXITCODE
Check 'document --unit exit 0' ($docExit -eq 0) "ec=$docExit"

$lines = [IO.File]::ReadAllLines($file)

# Finds the Nth (1-based $Occurrence) line matching $Pattern, then walks
# upward collecting the contiguous '///' block directly above it (same
# scan-upward idiom run_doc_cheap_facts.ps1 / run_doc_overload_idempotent.ps1 use).
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

$intBlock = Get-DocBlockAbove $lines '^\s*function Combine\(A, B: Integer\): Integer; overload;\s*$' 1
$strBlock = Get-DocBlockAbove $lines '^\s*function Combine\(const S: string\): Integer; overload;\s*$' 1

Check 'Combine(A, B: Integer) has a managed block' (($null -ne $intBlock) -and ($intBlock -match '<!-- drag-lint:auto BEGIN -->')) $intBlock
Check 'Combine(const S: string) has a managed block' (($null -ne $strBlock) -and ($strBlock -match '<!-- drag-lint:auto BEGIN -->')) $strBlock

Check "Combine(A, B: Integer) <returns> mentions 'A + B' (ITS OWN body)" `
  ($null -ne $intBlock -and $intBlock -match 'Observed:.*A \+ B') $intBlock
Check "Combine(A, B: Integer) <returns> does NOT mention 'Length(S)' (wrong overload's body)" `
  ($null -ne $intBlock -and -not ($intBlock -match 'Length\(S\)')) $intBlock

Check "Combine(const S: string) <returns> mentions 'Length(S)' (ITS OWN body)" `
  ($null -ne $strBlock -and $strBlock -match 'Observed:.*Length\(S\)') $strBlock
Check "Combine(const S: string) <returns> does NOT mention 'A + B' (wrong overload's body)" `
  ($null -ne $strBlock -and -not ($strBlock -match 'A \+ B')) $strBlock

Write-Host ''
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
