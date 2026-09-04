<#
  run_lint_verb_reports_unused_marker.ps1 -- the `lint` verb must be able to
  report review-marker-unused and review-marker-malformed.

  WHY. FinalizeAndOutput takes AScannedFiles, and both marker meta-rules need it:
  the finding-driven line cache only ever holds files that still PRODUCE
  findings, so a marker whose finding is GONE -- exactly the case
  review-marker-unused exists to catch -- is invisible without the scanned set.
  `DoLint` passed nil, so both rules were STRUCTURALLY unreachable from `lint`,
  and a file could carry a dead marker or a marker naming a misspelled rule id
  and the per-file verb reported neither. Only lint-all could see them.

  That matters because `lint <file>` is the command people actually run before
  committing, and the plugin runs it on every buffer.

  >>> THE SCOPE TRAP, WHICH IS WHY THIS IS NOT A ONE-LINE CHANGE.
  For a DIRECTORY the scanned set must be the POST-SCOPE list, not the raw walk.
  A walk reaches files no project compiles -- 84 of ORM3 CLIENT's 284 -- and
  feeding those in would start reporting markers in files the run deliberately
  drops findings for. Case 4 below is that assertion.

  RED-CHECK: against a build where DoLint passes nil, cases 1 and 2 fail and the
  controls pass. Verified.

  Run from a NEUTRAL CWD, pwsh 7.
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\draglint_lint_verb_markers",
  [switch]$Quiet
)
$ErrorActionPreference = 'Stop'
$script:fail = $false
function Check($n, $ok, $d) {
  if ($Quiet) { if (-not $ok) { $script:fail = $true }; return }
  Write-Host ("  [{0}] {1}" -f (@('FAIL', 'PASS')[[int]$ok]), $n) -ForegroundColor (@('Red', 'Green')[[int]$ok])
  if (-not $ok) { if ($d) { Write-Host "        $d" -ForegroundColor DarkGray }; $script:fail = $true }
}
function W($p, $s) {
  [System.IO.File]::WriteAllText($p, (($s -replace "`r`n", "`n") -replace "`n", "`r`n"),
                                 (New-Object System.Text.UTF8Encoding($false)))
}

if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
$Exe = (Resolve-Path $Exe).Path
if (Test-Path $WorkDir) { Remove-Item $WorkDir -Recurse -Force -ErrorAction SilentlyContinue }
New-Item -ItemType Directory -Force -Path (Join-Path $WorkDir '_D-RAG') | Out-Null

# uMember.pas -- a project MEMBER carrying three markers:
#   * a DEAD one (no such finding on that line)      -> must be reported unused
#   * a MALFORMED one (rule id that does not exist)  -> must be reported malformed
#   * a LIVE one on a real finding                   -> must stay silent
W (Join-Path $WorkDir 'uMember.pas') @'
unit uMember;

interface

procedure Go(const AItems: array of string; out AOut: string);

implementation

uses
  System.SysUtils;

procedure Go(const AItems: array of string; out AOut: string);
var
  I  : Integer;
  Str: string ;
begin
  Str := ''; // dl:ok bare-except@dead
  for I := Low(AItems) to High(AItems) do
    Str := Str + Format(' [%d] %s', [I, AItems[I]]); // dl:ok concat-in-loop
  AOut := Str + IntToStr(31337); // dl:ok not-a-real-rule-id
end;

end.
'@
W (Join-Path $WorkDir 'App.dpr') @'
program App;
uses
  uMember in 'uMember.pas';
begin
end.
'@

# uLoose.pas -- NOT a project member, carrying a dead marker of its own. It is
# what case 4 is about: the directory walk reaches it, the run drops it, and its
# marker must therefore never be reported.
W (Join-Path $WorkDir 'uLoose.pas') @'
unit uLoose;

interface

procedure Loose;

implementation

procedure Loose;
begin
  // dl:ok bare-except@alsodead
end;

end.
'@

$db = Join-Path $WorkDir '_D-RAG\App.sqlite'
& $Exe index --project (Join-Path $WorkDir 'App.dpr') --db $db 2>&1 | Out-Null

$member = Join-Path $WorkDir 'uMember.pas'

function RuleLines($text, $rule) {
  $out = @()
  foreach ($line in $text) {
    if ("$line" -match (':(\d+):\d+\s+\[\w+\]\s+' + [regex]::Escape($rule) + ':')) { $out += [int]$Matches[1] }
  }
  return @($out | Sort-Object -Unique)
}

Write-Host '== the lint verb and the marker meta-rules ==' -ForegroundColor Cyan

# Establish what lint-all says, so the per-file expectation is derived from the
# engine rather than from this script's opinion. If lint-all cannot see them
# either, the fixture is wrong and everything below would be measuring nothing.
$allOut = (& $Exe lint-all --db $db 2>&1)
$allUnused    = RuleLines $allOut 'review-marker-unused'
$allMalformed = RuleLines $allOut 'review-marker-malformed'
Check 'PRECONDITION: lint-all sees an unused marker in the member' ($allUnused.Count -ge 1) `
  "lint-all found none -- the fixture does not contain the case under test"
Check 'PRECONDITION: lint-all sees a malformed marker in the member' ($allMalformed.Count -ge 1) `
  "lint-all found none -- the fixture does not contain the case under test"

# 1 + 2. THE DEFECT: the same file, through the per-file verb.
$fileOut = (& $Exe lint $member --db $db 2>&1)
$fileUnused    = RuleLines $fileOut 'review-marker-unused'
$fileMalformed = RuleLines $fileOut 'review-marker-malformed'

Check 'lint <file> reports review-marker-unused' ($fileUnused.Count -ge 1) `
  'RED today: DoLint passes nil for AScannedFiles, so the rule cannot fire at all'
Check 'lint <file> reports review-marker-malformed' ($fileMalformed.Count -ge 1) `
  'RED today: same cause -- the scan that finds malformed markers never runs'

# 3. CONTROL -- a marker that DOES match a finding must stay silent. Without
#    this, "report every marker" satisfies cases 1 and 2 and destroys the
#    feature for everyone who annotated correctly.
$concatLine = 0
$src = Get-Content $member
for ($i = 0; $i -lt $src.Count; $i++) { if ($src[$i] -match 'dl:ok concat-in-loop\s*$') { $concatLine = $i + 1 } }
Check 'CONTROL: the LIVE marker is not reported unused' `
  (($concatLine -gt 0) -and (-not ($fileUnused -contains $concatLine))) `
  "line $concatLine was reported -- a working marker is being called dead"
Check 'CONTROL: and the finding it covers stays suppressed' `
  ((RuleLines $fileOut 'concat-in-loop').Count -eq 0) `
  'the marker stopped suppressing -- the scanned set must not change suppression'

# 4. >>> THE SCOPE ASSERTION. The directory form must report the member's
#    markers and NOT the non-member's.
$dirOut = (& $Exe lint $WorkDir --db $db 2>&1)
$dirText = ($dirOut | Out-String)
Check 'lint <dir> reports the MEMBER''s unused marker' `
  ((RuleLines $dirOut 'review-marker-unused').Count -ge 1) ''
Check 'CONTROL: lint <dir> does NOT report the NON-MEMBER''s marker' `
  (-not ($dirText -match 'uLoose\.pas.*review-marker')) `
  'the raw walk was used as the scanned set -- markers are now reported in files the run drops'

Write-Host ''
if ($script:fail) { Write-Host 'LINT-VERB-MARKER GUARD: FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'LINT-VERB-MARKER GUARD: PASS' -ForegroundColor Green
exit 0
