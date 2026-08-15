<#
  run_review_marker_prose.ps1 -- prose ABOUT a dl:ok marker is not a marker.

  THE DEFECT THIS PINS:
    `review-marker-unused` walks every line of every scanned file looking for the
    tag, and TReviewMarkers.Parse takes ONE LINE -- so it cannot tell that a brace
    opened on an earlier line is still open. Result: two findings on the very unit
    that DEFINES the marker syntax, on lines carrying no marker at all:

      DRagLint.Lint.ReviewMarker.pas:6    inside the unit's own braced header
                                          block; the line reads like code plus a
                                          trailing marker and is fully commented out
      DRagLint.Lint.ReviewMarker.pas:176  a `///` doc-comment quoting the grammar
                                          as an example, inside backticks

    The rule said a marker "no longer matches any finding" on lines that never had
    one, and its advice -- "remove it" -- would have deleted documentation.

  WHY THE OBVIOUS FIX IS WRONG, and what the fix actually is:
    "Ignore markers in comments" cannot be the test, because a REAL marker is
    always in a comment (`except // dl:ok bare-except@7f3a -- reason`). The
    discriminator is WHICH comment: a `//` reached in code state can carry one; a
    braced or star-paren block cannot, and neither can a `///` doc comment.
    TReviewMarkers.MarkerBearingLines carries block state across lines.

  WHY THIS TEST IS THE POINT, not a formality:
    This is the SUPPRESSION mechanism. A comment-state reader wrong in the OTHER
    direction stops recognising real `dl:ok` markers -- every suppressed finding
    silently returns, counts jump across every project at once, and nothing
    indicates the reader rather than the code was the cause. So the gate was
    applied to the REPORTER ONLY, never to the suppression path, and assertion 3
    below is what proves suppression still works. Without it, assertions 1 and 2
    would also pass with markers broken entirely.

  Assertions:
    1. No review-marker-unused on the braced-block example line.
    2. No review-marker-unused on the `///` doc-comment example line.
    3. A REAL marker still suppresses its finding (bare-except is gone) -- the
       safety assertion.
    4. A stranded own-line marker IS still reported unused. The fix deliberately
       does NOT require code before the `//`, so this behaviour must be unchanged;
       it is the "did not over-broaden" assertion.
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\drag-lint-review-marker-prose"
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

# The two prose shapes are reproduced exactly: a marker-looking line inside a
# braced header block, and the grammar quoted in a /// doc comment. RealMarked
# carries a genuine hand-written marker (no @hash -- honoured, and reported as
# unverifiable, which is enough to prove suppression still runs). Stranded has an
# own-line marker suppressing nothing.
$FixtureBody = @'
unit uProse;

{ Header block documenting the marker syntax. The line below LOOKS like code
  plus a trailing marker, and is entirely commented out:

    except // dl:ok bare-except@7f3a -- rethrown by the caller

  It must not be reported as an unused marker. }

interface

/// <summary>Formats one marker.</summary>
/// <returns>e.g. `dl:ok bare-except@7f3a -- rethrown by the caller`.</returns>
function FormatIt: string;

procedure RealMarked;
procedure Stranded;

implementation

function FormatIt: string;
begin
  Result := 'x';
end;

procedure RealMarked;
begin
  try
    Writeln('a');
  except
    Writeln('b'); // dl:ok bare-except
  end;
end;

procedure Stranded;
begin
  // dl:ok bare-except@dead
  Writeln('c');
end;

end.
'@
$file = Join-Path $WorkDir 'uProse.pas'
$norm = ($FixtureBody -replace "`r`n", "`n") -replace "`n", "`r`n"
[System.IO.File]::WriteAllText($file, $norm, [System.Text.Encoding]::ASCII)

# Anchor rows are DERIVED from the fixture: hard-coded numbers would silently
# retarget if the fixture text is ever edited.
$src = Get-Content $file
function Row-Of([string]$Needle) {
  ($src | Select-String -Pattern $Needle -SimpleMatch | Select-Object -First 1).LineNumber
}
$rowInBlock  = Row-Of 'except // dl:ok bare-except@7f3a'
$rowInDocTag = Row-Of '/// <returns>e.g. `dl:ok'
# NOTE the marker sits on the STATEMENT line, not on the `except` keyword:
# bare-except anchors on the first statement inside the handler, so a marker
# written at the intuitive place (trailing `except`) never matches its finding and
# is then reported unused. Measured while building this test; filed as
# docs\INBOX-bare-except-anchor-defeats-a-hand-written-marker.md.
$rowReal     = Row-Of "Writeln('b'); // dl:ok bare-except"
$rowStranded = Row-Of '// dl:ok bare-except@dead'
foreach ($pair in @(@('block', $rowInBlock), @('doctag', $rowInDocTag), @('real', $rowReal), @('stranded', $rowStranded))) {
  if (-not $pair[1]) { Write-Host "FATAL: fixture anchor '$($pair[0])' not found" -ForegroundColor Red; exit 2 }
}
if (@($rowInBlock, $rowInDocTag, $rowReal, $rowStranded | Sort-Object -Unique).Count -ne 4) {
  Write-Host "FATAL: fixture anchors collapsed onto each other ($rowInBlock/$rowInDocTag/$rowReal/$rowStranded)" -ForegroundColor Red; exit 2
}
Write-Host ("  anchors: block={0} doctag={1} real={2} stranded={3}" -f $rowInBlock, $rowInDocTag, $rowReal, $rowStranded) -ForegroundColor DarkGray

$db = Join-Path $WorkDir 'fx.sqlite'
& $Exe index $WorkDir --db $db 2>&1 | Out-Null
# lint-all, NOT `lint <file>`: review-marker-unused is a whole-run rule and
# `lint <file>` reports 0 findings for it on the very file lint-all warns about.
# The first version of this test used `lint` and both prose assertions passed
# for the wrong reason. See docs\INBOX-lint-single-file-silently-omits-lint-all-rules.md.
Push-Location $WorkDir
try { $out = & $Exe lint-all --db $db 2>&1 | Out-String } finally { Pop-Location }

function Has-Finding([int]$Row, [string]$Rule) {
  [bool]([regex]::Match($out, ("uProse\.pas:{0}:\d+\s+\[\w+\]\s+{1}\b" -f $Row, [regex]::Escape($Rule))).Success)
}

Write-Host ''
Write-Host 'Prose about a marker must not be reported as an unused marker' -ForegroundColor Cyan
Check "no review-marker-unused inside the braced block (row $rowInBlock)" `
  (-not (Has-Finding $rowInBlock 'review-marker-unused'))
Check "no review-marker-unused in the /// doc tag (row $rowInDocTag)" `
  (-not (Has-Finding $rowInDocTag 'review-marker-unused'))

Write-Host ''
Write-Host 'SAFETY: a real marker still suppresses -- the gate is reporter-only' -ForegroundColor Cyan
Check "bare-except on row $rowReal is SUPPRESSED by its marker" `
  (-not (Has-Finding $rowReal 'bare-except')) `
  (($out -split "`r?`n" | Where-Object { $_ -match 'bare-except' } | Select-Object -First 1))
Check "row $rowReal is reported as unverifiable (no @hash), proving the marker was READ" `
  (Has-Finding $rowReal 'review-marker-stale')
if (Has-Finding $rowReal 'bare-except') {
  Write-Host '  !! A REAL MARKER STOPPED SUPPRESSING. This is the failure mode the' -ForegroundColor Yellow
  Write-Host '  !! fix was designed to be incapable of: every suppressed finding in' -ForegroundColor Yellow
  Write-Host '  !! every project returns at once. Revert rather than adjusting this.' -ForegroundColor Yellow
}

Write-Host ''
Write-Host 'NOT over-broadened: a stranded own-line marker is still reported' -ForegroundColor Cyan
Check "review-marker-unused still fires on the own-line marker (row $rowStranded)" `
  (Has-Finding $rowStranded 'review-marker-unused') `
  (($out -split "`r?`n" | Where-Object { $_ -match 'review-marker-unused' } | Select-Object -First 3) -join ' | ')

Write-Host ''
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
