<#
  run_allow_refuses_codeless_line.ps1 -- `allow --apply` must REFUSE a line that
  carries no code, and must still write on a line that does.

  THE DEFECT (DataCopy, 2026-09-01, reproduced here exactly)
  ---------------------------------------------------------
  `drag-lint allow uConfigurationService.pas --fix-line 1163 --fix-rule doc-drift
   --apply` wrote the marker into a DocInsight `///` line. `///` runs to end of
  line, so the appended `// dl:ok ...` became DOCUMENTATION TEXT. It had to be
  reverted by hand. That is data damage in the user's source, which is the worst
  class of defect this tool can produce.

  WHY THE EXISTING ROUND-TRIP GUARD DID NOT CATCH IT
  --------------------------------------------------
  A guard already exists for the BLOCK-comment case: the marker lands inside
  `{ ... }`, Parse refuses to see it, and the write is rejected. On a `///` line
  Parse SUCCEEDS -- LineCommentStart finds the `//` of the `///` itself -- so the
  marker round-trips, the guard passes, and the doc is corrupted anyway.

  The written marker also carried `@e3b0`, the first four hex of SHA-256 of the
  EMPTY string: the line normalizes to nothing because it is all comment, so the
  marker could never match and would report stale forever. Both failures have
  one cause -- there is no code on the line -- which is what this now tests.

  BOTH POLARITIES ARE ASSERTED. A test that only checked "the doc line is
  untouched" would pass with `allow --apply` broken outright, so the code-line
  case must still be written and must still round-trip.
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\drag-lint-allow-codeless"
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

$body = @'
unit DocLine;

interface

type
  TThing = class
  public
    /// <summary>Does the thing and returns whether it worked.</summary>
    function DoThing(const AName: string): Boolean;
  end;

implementation

uses
  System.SysUtils;

function TThing.DoThing(const AName: string): Boolean;
var
  S: string;
begin
  S := 'C:\Temp\x.txt';
  Result := (AName <> '') and (S <> '');
end;

end.
'@
$fixture = Join-Path $WorkDir 'DocLine.pas'
$norm = $body -replace "`r`n", "`n" -replace "`n", "`r`n"
[System.IO.File]::WriteAllText($fixture, $norm, [System.Text.Encoding]::ASCII)

$lines = [System.IO.File]::ReadAllLines($fixture)
function LineOf([string]$Needle) {
  for ($i = 0; $i -lt $lines.Count; $i++) { if ($lines[$i].Trim() -eq $Needle) { return $i + 1 } }
  return -1
}
$docLine  = LineOf '/// <summary>Does the thing and returns whether it worked.</summary>'
$codeLine = LineOf "S := 'C:\Temp\x.txt';"
$blankLine = 2
Check 'fixture lines located' (($docLine -gt 0) -and ($codeLine -gt 0)) "doc=$docLine code=$codeLine"

# --- 1. THE DEFECT: a /// doc line must be REFUSED and left byte-identical ----
$before = [System.IO.File]::ReadAllText($fixture)
$out = & $Exe allow $fixture --fix-line $docLine --fix-rule doc-drift --apply 2>&1
$rc  = $LASTEXITCODE
$after = [System.IO.File]::ReadAllText($fixture)
Check '1 exit code is non-zero (refused)' ($rc -ne 0) "got $rc"
Check '1 the file is byte-identical -- the doc comment was NOT touched' ($before -eq $after)
Check '1 the refusal explains itself' (("$out" -match 'no code') -and ("$out" -match 'dl:ok'))
Check '1 no dl:ok was written into the doc comment' (-not ($after -match '///.*dl:ok'))

# --- 2. a blank line is the same class and must also be refused --------------
$before = [System.IO.File]::ReadAllText($fixture)
& $Exe allow $fixture --fix-line $blankLine --fix-rule doc-drift --apply 2>&1 | Out-Null
$rc = $LASTEXITCODE
Check '2 a blank line is refused' ($rc -ne 0) "got $rc"
Check '2 the file is byte-identical' ($before -eq ([System.IO.File]::ReadAllText($fixture)))

# --- 3. POSITIVE CONTROL: a real code line MUST still be written -------------
# Without this, every assertion above passes with `allow --apply` simply broken.
$out = & $Exe allow $fixture --fix-line $codeLine --fix-rule magic-literal --apply 2>&1
$rc  = $LASTEXITCODE
$after = [System.IO.File]::ReadAllLines($fixture)
Check '3 POSITIVE CONTROL: a code line is accepted' ($rc -eq 0) "got $rc"
Check '3 the marker was written to the code line' ($after[$codeLine - 1] -match 'dl:ok\s+magic-literal')
# The hash must be a REAL hash, not SHA-256 of the empty string. e3b0 is the
# fingerprint of "there was no code to hash" and is the sharpest single symptom
# of the defect this file exists to prevent.
Check '3 the hash is not the empty-string hash e3b0' (-not ($after[$codeLine - 1] -match 'dl:ok\s+magic-literal@e3b0')) `
  $after[$codeLine - 1]

Write-Host ''
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'PASS' -ForegroundColor Green
exit 0
