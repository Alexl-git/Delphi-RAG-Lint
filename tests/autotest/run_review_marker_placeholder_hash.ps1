<#
  run_review_marker_placeholder_hash.ps1 -- `review-marker-placeholder-hash`.

  THE HOLE (docs\INBOX-new-rules-from-graph-and-converter-facts.md, B1)
  --------------------------------------------------------------------
  `src\analysis\DRagLint.Analysis.LintTree.pas` carried
      { REVIEWED 2026-09-11, dl:ok deep-nesting@0000 -- six levels ... }
  An all-zero hash is not a computed hash, and a marker inside a BRACE comment
  is not parsed at all -- only a `//` line comment carries a live marker. It
  suppressed nothing, and `review-marker-stale` / `-unused` came back CLEAN over
  the file, because neither ever saw it. Invisible in both directions.

  On a `//` marker the placeholder WAS seen, but misreported: with a finding on
  the line it read as `review-marker-stale` ("the code changed, or the hashing
  scheme did"), and with none as `review-marker-unused` ("remove it"). Neither
  names the real cause -- the hash was never computed.

  WHAT THIS PINS
    * `//` marker, @0000, finding on the line  -> placeholder hint, finding
      still reported, NO stale hint for it;
    * `//` marker, malformed @xxxx             -> placeholder hint;
    * `//` marker, @0000, no finding            -> placeholder hint, NO unused;
    * brace-comment marker, @0000, known rule   -> placeholder hint;
  and the NEGATIVE controls that keep it from flooding:
    * brace-comment PROSE quoting a realistic hash (@7f3a) -> nothing;
    * a well-formed but wrong hash (@abcd)      -> still `review-marker-stale`,
      not placeholder;
    * the unmarked statement still fires (the rule under the markers is live).

  Run from a NEUTRAL CWD, pwsh 7.
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\drag-lint-marker-placeholder-hash"
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
if (-not (Test-Path $WorkDir)) { New-Item -ItemType Directory $WorkDir | Out-Null }
foreach ($stale in @(Get-ChildItem -LiteralPath $WorkDir -File -ErrorAction SilentlyContinue)) {
  [System.IO.File]::Delete($stale.FullName)
}
$fixture = Join-Path $WorkDir 'PlaceholderHash.pas'

$body = @'
unit PlaceholderHash;

interface

procedure P;

implementation

uses
  System.SysUtils;

{ dl:ok deep-nesting@0000 -- six levels, and they stay for now }
{ Prose about the syntax: write dl:ok bare-except@7f3a -- rethrown }
procedure P;
var
  I: Integer;
  S: string;
begin
  S := '';
  for I := 0 to 3 do
  begin
    S := S + IntToStr(I); // dl:ok concat-in-loop@0000
  end;
  for I := 0 to 3 do
  begin
    S := S + Trim(S); // dl:ok concat-in-loop@xxxx -- reviewed, bounded
  end;
  for I := 0 to 3 do
  begin
    S := S + UpperCase(S); // dl:ok concat-in-loop@abcd -- reviewed, bounded
  end;
  for I := 0 to 3 do
  begin
    S := S + IntToHex(I, 2);
  end;
  Writeln(S); // dl:ok concat-in-loop@0000
end;

end.
'@
function Write-Ascii([string]$Path, [string]$Text) {
  $norm = $Text -replace "`r`n", "`n" -replace "`n", "`r`n"
  [System.IO.File]::WriteAllText($Path, $norm, [System.Text.Encoding]::ASCII)
}
Write-Ascii $fixture $body

$lines = [System.IO.File]::ReadAllLines($fixture)
function LineOf([string]$Needle) {
  for ($i = 0; $i -lt $lines.Count; $i++) { if ($lines[$i].Trim() -eq $Needle) { return $i + 1 } }
  return -1
}
$lnBrace   = LineOf '{ dl:ok deep-nesting@0000 -- six levels, and they stay for now }'
$lnProse   = LineOf '{ Prose about the syntax: write dl:ok bare-except@7f3a -- rethrown }'
$lnZero    = LineOf 'S := S + IntToStr(I); // dl:ok concat-in-loop@0000'
$lnXxxx    = LineOf 'S := S + Trim(S); // dl:ok concat-in-loop@xxxx -- reviewed, bounded'
$lnWrong   = LineOf 'S := S + UpperCase(S); // dl:ok concat-in-loop@abcd -- reviewed, bounded'
$lnUnmark  = LineOf 'S := S + IntToHex(I, 2);'
$lnNoFind  = LineOf 'Writeln(S); // dl:ok concat-in-loop@0000'
Check 'all fixture lines located' (
  @($lnBrace,$lnProse,$lnZero,$lnXxxx,$lnWrong,$lnUnmark,$lnNoFind) -notcontains -1)

$concat = @(); $stale = @{}; $unused = @{}; $ph = @{}
foreach ($line in (& $Exe lint $fixture 2>&1)) {
  $t = "$line"
  if     ($t -match ':(\d+):\d+\s+\[\w+\]\s+concat-in-loop:')                 { $concat += [int]$Matches[1] }
  elseif ($t -match ':(\d+):\d+\s+\[\w+\]\s+review-marker-stale:')            { $stale[[int]$Matches[1]] = $t }
  elseif ($t -match ':(\d+):\d+\s+\[\w+\]\s+review-marker-unused:')           { $unused[[int]$Matches[1]] = $t }
  elseif ($t -match ':(\d+):\d+\s+\[\w+\]\s+review-marker-placeholder-hash:') { $ph[[int]$Matches[1]] = $t }
}
Write-Host ("  concat-in-loop fired on: {0}; placeholder on: {1}" -f ($concat -join ','), ($ph.Keys -join ',')) -ForegroundColor DarkGray

Write-Host 'POSITIVE CONTROL' -ForegroundColor Cyan
Check "unmarked statement (line $lnUnmark) still fires" ($concat -contains $lnUnmark)

Write-Host 'THE RULE' -ForegroundColor Cyan
Check "@0000 on a // marker with a finding (line $lnZero) is reported as a placeholder" ($ph.ContainsKey($lnZero))
Check "  ...and its finding is still reported (a placeholder suppresses nothing)" ($concat -contains $lnZero)
Check "  ...and it is NOT misreported as review-marker-stale" (-not $stale.ContainsKey($lnZero)) "$($stale[$lnZero])"
Check "@xxxx (malformed) on line $lnXxxx is reported as a placeholder" ($ph.ContainsKey($lnXxxx))
Check "  ...and its finding is still reported" ($concat -contains $lnXxxx)
Check "@0000 with no finding (line $lnNoFind) is reported as a placeholder" ($ph.ContainsKey($lnNoFind))
Check "  ...and NOT as review-marker-unused" (-not $unused.ContainsKey($lnNoFind)) "$($unused[$lnNoFind])"
Check "@0000 in a BRACE comment (line $lnBrace) is reported -- the LintTree.pas shape" ($ph.ContainsKey($lnBrace))
if ($ph.ContainsKey($lnBrace)) {
  Check '  ...and the message says why a brace comment never works' ($ph[$lnBrace] -match '//')
}

Write-Host 'NEGATIVE CONTROLS' -ForegroundColor Cyan
Check "brace-comment PROSE with a realistic hash (line $lnProse) is not reported" (-not $ph.ContainsKey($lnProse))
Check "a well-formed wrong hash (line $lnWrong) is NOT a placeholder" (-not $ph.ContainsKey($lnWrong))
Check "  ...it stays review-marker-stale" ($stale.ContainsKey($lnWrong))

Write-Host ''
if ($script:Failed) { Write-Host 'FAIL: review-marker-placeholder-hash' -ForegroundColor Red; exit 1 }
Write-Host 'PASS: review-marker-placeholder-hash' -ForegroundColor Green
exit 0
