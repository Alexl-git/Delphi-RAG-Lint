<#
  run_marker_span.ps1 -- a `dl:ok` marker must be honoured anywhere in the
  finding's STATEMENT SPAN, not only on its anchor line.

  THE BUG (reported by DataCopy, 2026-08-31)
  ------------------------------------------
  A trailing `// dl:ok` can only be written where a statement ENDS. A rule
  reports where the statement BEGINS. On a WRAPPED statement those differ, so
  one reviewed site produced TWO messages:

    uFileUtils.pas:2029:7  [info] concat-in-loop: ...
    uFileUtils.pas:2030:1  [hint] review-marker-unused: ... remove it.

  The finding was never suppressed, and the marker was simultaneously called
  dead -- advice that, if followed, DELETES a legitimate review record and
  leaves the finding firing forever.

  It generalises to every rule that anchors to a statement's first line, which
  is why the fix is in the marker matcher, not in concat-in-loop.

  WHY THE POSITIVE CONTROL EXISTS
  -------------------------------
  The obvious wrong fix is "look for the marker anywhere in the file", which
  would make any marker suppress anything. So the fixture keeps a THIRD concat
  statement carrying no marker in its own span, while two markers sit elsewhere
  in the same file: it must still fire.

  That one check guards BOTH failure directions, which matters here -- an
  earlier draft asserted the absence of findings only, and would have passed if
  concat-in-loop had simply stopped firing at all.

  review-marker-unused IS asserted here, in its own lint-all pass at the bottom.
  It was previously left out because the `lint` verb calls FinalizeAndOutput
  WITHOUT AScannedFiles, so the hint is unreachable from a single-file run (see
  docs\INBOX-lint-verb-cannot-report-unused-markers.md) -- but leaving it out
  meant the report's MORE SERIOUS half was pinned by nothing. The suppression
  failing costs a duplicate message; "remove it" being wrong costs a legitimate
  review record, because obeying it deletes the marker and the finding then
  fires for ever. So the second pass indexes the same fixture and runs lint-all.
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\drag-lint-marker-span"
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

$fixture = Join-Path $WorkDir 'MarkerSpan.pas'
$body = @'
unit MarkerSpan;

interface

procedure P;

implementation

uses
  System.SysUtils;

procedure P;
var
  I: Integer;
  S: string;
begin
  S := '';
  for I := 0 to 3 do
  begin
    S := S + Format(
      ' [%d]', [I]); // dl:ok concat-in-loop
  end;
  for I := 0 to 3 do
  begin
    S := S + IntToStr(I); // dl:ok concat-in-loop
  end;
  for I := 0 to 3 do
  begin
    S := S + Trim(S);
  end;
  Writeln(S); // dl:ok bare-except
end;

end.
'@
$norm = $body -replace "`r`n", "`n" -replace "`n", "`r`n"
[System.IO.File]::WriteAllText($fixture, $norm, [System.Text.Encoding]::ASCII)

$lines = [System.IO.File]::ReadAllLines($fixture)
function LineOf([string]$Needle) {
  for ($i = 0; $i -lt $lines.Count; $i++) { if ($lines[$i].Trim() -eq $Needle) { return $i + 1 } }
  return -1
}
$lnWrapStart = LineOf 'S := S + Format('
$lnWrapEnd   = LineOf "' [%d]', [I]); // dl:ok concat-in-loop"
$lnSingle    = LineOf 'S := S + IntToStr(I); // dl:ok concat-in-loop'
$lnUnmarked  = LineOf 'S := S + Trim(S);'
Check 'all four fixture lines located' (
  @($lnWrapStart,$lnWrapEnd,$lnSingle,$lnUnmarked) -notcontains -1) `
  "wrap $lnWrapStart-$lnWrapEnd, single $lnSingle, unmarked $lnUnmarked"

$concat = @()
foreach ($line in (& $Exe lint $fixture 2>$null)) {
  if ("$line" -match ':(\d+):\d+\s+\[\w+\]\s+concat-in-loop:')        { $concat += [int]$Matches[1] }
}
$concat = @($concat | Sort-Object -Unique)
Write-Host ("  concat-in-loop fired on: {0}" -f ($concat -join ', ')) -ForegroundColor DarkGray

Write-Host ''
Write-Host 'THE DEFECT -- a marker on the statement''s LAST line must suppress' -ForegroundColor Cyan
Check "wrapped statement (anchor $lnWrapStart, marker $lnWrapEnd) is suppressed" (-not ($concat -contains $lnWrapStart))

Write-Host ''
Write-Host 'REGRESSION -- a marker on the anchor line itself still works' -ForegroundColor Cyan
Check "single-line statement (line $lnSingle) is suppressed" (-not ($concat -contains $lnSingle))

Write-Host ''
Write-Host 'POSITIVE CONTROL -- the span is BOUNDED, and the rule is live' -ForegroundColor Cyan
# This statement carries no marker in its own span, while two markers exist
# elsewhere in the same file. If the matcher had degenerated into 'any marker
# suppresses anything' this would be silent -- and if concat-in-loop had simply
# stopped firing, the two checks above would pass vacuously. It guards both.
Check "unmarked statement (line $lnUnmarked) STILL fires" ($concat -contains $lnUnmarked)
Check "exactly one finding survives" ($concat.Count -eq 1) "got: $($concat -join ', ')"

# ---------------------------------------------------------------------------
# THE OTHER HALF OF THE REPORT, and the one that destroys data if it is wrong.
# DataCopy's site produced a PAIR: the finding fired at the anchor AND the
# correctly-placed marker was called dead. Obeying "remove it" deletes a real
# review record and leaves the finding firing for ever, which is why they
# refused to. review-marker-unused is a lint-all feature, so it needs its own
# pass over an indexed fixture.
# ---------------------------------------------------------------------------
Write-Host ''
Write-Host 'THE OTHER HALF -- the span marker must not be reported UNUSED' -ForegroundColor Cyan
$db = Join-Path $WorkDir 'MarkerSpan.sqlite'
& $Exe index $WorkDir --db $db 2>&1 | Out-Null
Check 'fixture indexed' (Test-Path $db)

$unused = @()
foreach ($line in (& $Exe lint-all --db $db 2>&1)) {
  if ("$line" -match ':(\d+):\d+\s+\[\w+\]\s+review-marker-unused:') { $unused += [int]$Matches[1] }
}
$unused = @($unused | Sort-Object -Unique)
Write-Host ("  review-marker-unused fired on: {0}" -f ($unused -join ', ')) -ForegroundColor DarkGray

$lnBareExcept = LineOf 'Writeln(S); // dl:ok bare-except'
Check "the wrapped statement's marker (line $lnWrapEnd) is NOT called unused" (-not ($unused -contains $lnWrapEnd)) `
  'obeying that hint deletes a legitimate review record'
Check "nor is the anchor line ($lnWrapStart)" (-not ($unused -contains $lnWrapStart))
Check "nor the single-line marker ($lnSingle)"  (-not ($unused -contains $lnSingle))

# POSITIVE CONTROL. Without it, this section passes with review-marker-unused
# switched off entirely -- and it also re-guards the degeneration the triage
# warned about: if the matcher had become "any marker in the file suppresses
# anything", this genuinely dead marker would be silently accounted for too.
Check "a genuinely dead marker (line $lnBareExcept) IS still reported unused" ($unused -contains $lnBareExcept) `
  'bare-except is marked on a line with no such finding'
Check 'exactly one marker is reported unused' ($unused.Count -eq 1) "got: $($unused -join ', ')"

Write-Host ''
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'PASS' -ForegroundColor Green
exit 0
