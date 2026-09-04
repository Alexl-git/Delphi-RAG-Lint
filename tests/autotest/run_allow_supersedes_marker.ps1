<#
  run_allow_supersedes_marker.ps1 -- `allow` must SUPERSEDE a marker already on
  the same statement, not add a second one beside it.

  THE DEFECT (docs\INBOX-allow-leaves-a-superseded-marker-behind.md, measured
  2026-09-03 on DataCopy's uFileUtils.pas:2028/2055). A rule reports where a
  statement BEGINS; a trailing `// dl:ok` can only be written where it ENDS. On a
  WRAPPED statement those are different lines, so an old marker sits on the last
  line while `review-marker-stale` names the first. Following that hint's OWN
  printed remedy --

      Re-review, then: allow --fix-line 20 --fix-rule concat-in-loop

  -- used to produce:

      Str := Str + Format(  // dl:ok concat-in-loop@ab38     <- written by allow
        ' [%d]: %s', [I, X]); // dl:ok concat-in-loop@54b7    <- now dead

  The finding IS suppressed and the stale hint IS gone. But the operator followed
  the sanctioned instruction and ended the run with a NEW hint they had no way to
  foresee (review-marker-unused), plus two review records for one review. The
  lint-clean standard is that a message means something; a remedy that produces a
  message teaches people that review-marker-* output is noise.

  WHAT THIS ASSERTS, and every case is scoped to a RULE and a LINE. Three of the
  five are controls, because "the unused hint is gone" on its own also passes
  with the rule switched off, with the fixture failing to index, and with a fix
  that deletes markers file-wide -- which is the specific wrong fix the note
  names ("Do NOT fix it by making review-marker-unused quieter").

    1. the wrapped statement's finding is SUPPRESSED after allow
    2. NO review-marker-unused anywhere            <- THE FIX
    3. exactly ONE dl:ok for that rule on that statement
    4. CONTROL: the SAME rule's marker on a DIFFERENT statement is UNTOUCHED,
       byte for byte, and still reported stale. Span-scoped, not file-scoped.
    5. CONTROL: an unrelated dead marker for a DIFFERENT rule is STILL reported
       unused. The fix must not have quieted the reporter.

  RED-CHECK: against a build with the supersede block in DoAllow disabled, cases
  2 and 3 FAIL and 1, 4, 5 PASS.

  Neighbour: run_marker_span.ps1, whose `allow` round-trip section says in its
  own comment that its review-marker-unused assertion is NOT red-checked, and
  points at this defect for what would exercise it. This is that runner.
#>
[CmdletBinding()]
param(
  [string]$Exe = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe"
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

$dllSrc = "$PSScriptRoot\..\..\third_party\dll-win64"
if (Test-Path $dllSrc) {
  Get-ChildItem "$dllSrc\*.dll" | ForEach-Object {
    $dst = Join-Path (Split-Path $Exe) $_.Name
    if (-not (Test-Path $dst)) { Copy-Item $_.FullName $dst }
  }
}

$WorkDir = Join-Path $env:TEMP ("allow_supersede_" + [Guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Force -Path (Join-Path $WorkDir '_D-RAG') | Out-Null
$pas = Join-Path $WorkDir 'uRt.pas'
$dpr = Join-Path $WorkDir 'App.dpr'

# The fixture is written LF-normalized then converted, because these sources are
# strict CRLF + 7-bit ASCII (run_encoding_guard.ps1 enforces it repo-wide).
[System.IO.File]::WriteAllText($pas, ((@'
unit uRt;

interface

procedure Build(const AItems: array of string; out AOut: string);
procedure Other(const AItems: array of string; out AOut: string);
procedure Quiet(out AOut: string);

implementation

uses
  System.SysUtils;

procedure Build(const AItems: array of string; out AOut: string);
var
  I  : Integer;
  Str: string ;
begin
  Str := '';
  for I := Low(AItems) to High(AItems) do
    Str := Str + Format(
      ' [%d] item: %s', [I, AItems[I]]); // dl:ok concat-in-loop@54b7
  AOut := Str;
end;

// CONTROL (case 4): the SAME rule, a DIFFERENT statement. An allow aimed at
// Build's statement must not touch this one -- span-scoped, not file-scoped.
procedure Other(const AItems: array of string; out AOut: string);
var
  I  : Integer;
  Str: string ;
begin
  Str := '';
  for I := Low(AItems) to High(AItems) do
    Str := Str + AItems[I]; // dl:ok concat-in-loop@dead
  AOut := Str;
end;

// CONTROL (case 5): a dead marker for an UNRELATED rule. concat-in-loop never
// fires here, so this marker is genuinely unused and must STAY reported. If the
// fix had worked by quieting review-marker-unused, this goes silent.
procedure Quiet(out AOut: string);
begin
  AOut := 'x'; // dl:ok concat-in-loop@beef
end;

end.
'@ -replace "`r`n", "`n") -replace "`n", "`r`n"), (New-Object System.Text.ASCIIEncoding))

[System.IO.File]::WriteAllText($dpr, ((@'
program App;
uses
  uRt in 'uRt.pas';
begin
end.
'@ -replace "`r`n", "`n") -replace "`n", "`r`n"), (New-Object System.Text.ASCIIEncoding))

$db = Join-Path $WorkDir '_D-RAG\App.sqlite'
& $Exe index --project $dpr --db $db 2>&1 | Out-Null
Check 'fixture indexed' ((Test-Path $db) -and ($LASTEXITCODE -eq 0))

function Report {
  $out = @()
  foreach ($line in (& $Exe lint-all --db $db 2>&1)) {
    if ("$line" -match ':(\d+):\d+\s+\[\w+\]\s+([a-z0-9-]+):') { $out += [pscustomobject]@{ Line = [int]$Matches[1]; Rule = $Matches[2] } }
  }
  return $out
}
function LinesFor($rep, $rule) { return @($rep | Where-Object { $_.Rule -eq $rule } | ForEach-Object { $_.Line } | Sort-Object -Unique) }

# Locate the fixture lines by content, so a fixture edit fails loudly here
# instead of silently aiming an assertion at a blank line.
$src = [System.IO.File]::ReadAllLines($pas)
function LineOf([string]$needle) {
  for ($i = 0; $i -lt $src.Count; $i++) { if ($src[$i].Contains($needle)) { return $i + 1 } }
  return -1
}
$anchor   = LineOf 'Str := Str + Format('
$wrapEnd  = LineOf "' [%d] item: %s'"
$otherLn  = LineOf 'Str := Str + AItems[I];'
$quietLn  = LineOf "AOut := 'x';"
Check 'fixture lines located' (($anchor -gt 0) -and ($wrapEnd -gt 0) -and ($otherLn -gt 0) -and ($quietLn -gt 0)) `
  "anchor=$anchor wrapEnd=$wrapEnd other=$otherLn quiet=$quietLn"

# PRECONDITION: the defect only exists on a WRAPPED statement. If the anchor line
# ended the statement, allow would write onto the very line that already carries
# the marker and this whole runner would prove nothing.
Check 'precondition: the anchor is a WRAPPED statement (it does not end in ";")' `
  ($src[$anchor - 1] -notmatch ';\s*$') "line $anchor = '$($src[$anchor - 1])'"

$before = Report
Check 'precondition: the wrapped statement reports concat-in-loop before allow' `
  ((LinesFor $before 'concat-in-loop') -contains $anchor) "got: $((LinesFor $before 'concat-in-loop') -join ', ')"

# Follow the remedy the engine itself prints.
& $Exe allow $pas --fix-line $anchor --fix-rule concat-in-loop --apply 2>&1 | Out-Null
Check 'allow --apply exits 0' ($LASTEXITCODE -eq 0)
& $Exe index --project $dpr --db $db 2>&1 | Out-Null

$after = Report
$post  = [System.IO.File]::ReadAllLines($pas)

Write-Host 'after allow:'
$after | ForEach-Object { Write-Host ("  {0}:{1}" -f $_.Line, $_.Rule) }

# 1. the reviewed finding is actually suppressed
Check "1. the wrapped statement's concat-in-loop is SUPPRESSED (line $anchor)" `
  (-not ((LinesFor $after 'concat-in-loop') -contains $anchor))

# 2. THE FIX -- no new hint ON THE REVIEWED STATEMENT.
#
#    SCOPED, and the first draft of this assertion was not. It read "no
#    review-marker-unused anywhere" and failed against the CORRECT build, because
#    case 5 deliberately plants a dead marker at line $quietLn that MUST stay
#    reported. The two assertions contradicted each other: a file-wide "zero
#    unused" is only satisfiable by the wrong fix this runner exists to rule out.
#    Scoping it to the statement is what makes cases 2 and 5 independent.
$unusedOnStmt = @((LinesFor $after 'review-marker-unused') | Where-Object { $_ -ge $anchor -and $_ -le $wrapEnd })
Check "2. no review-marker-unused on the reviewed statement (lines $anchor-$wrapEnd)" `
  ($unusedOnStmt.Count -eq 0) `
  "got lines: $($unusedOnStmt -join ', ')  (all unused: $((LinesFor $after 'review-marker-unused') -join ', '))"

# 3. exactly one marker for the rule on that statement
$stmtMarkers = @($post[($anchor - 1)..($wrapEnd - 1)] | Where-Object { $_ -match 'dl:ok[^/]*concat-in-loop' }).Count
Check '3. exactly ONE dl:ok concat-in-loop on the reviewed statement' ($stmtMarkers -eq 1) "found $stmtMarkers"

# 4. CONTROL -- the same rule on a DIFFERENT statement is untouched, byte for byte
Check "4. CONTROL: the same rule's marker on a DIFFERENT statement is byte-identical (line $otherLn)" `
  ($post[$otherLn - 1] -ceq $src[$otherLn - 1]) `
  "before='$($src[$otherLn - 1])' after='$($post[$otherLn - 1])'"
Check "4b. CONTROL: and that statement still reports concat-in-loop" `
  ((LinesFor $after 'concat-in-loop') -contains $otherLn)

# 5. CONTROL -- the unused reporter is still alive
Check "5. CONTROL: the unrelated dead marker is STILL reported stale-or-unused (line $quietLn)" `
  ((($after | Where-Object { $_.Line -eq $quietLn -and $_.Rule -like 'review-marker-*' }).Count) -ge 1) `
  'if this went silent, the fix worked by quieting the reporter -- the wrong fix'

Write-Host ''
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'PASS' -ForegroundColor Green
exit 0
