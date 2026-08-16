<#
  run_doc_facts_ignore_comment_prose.ps1 -- the Calls: and raises body scans must
  not harvest ENGLISH WORDS out of comments.

  THE DEFECT THIS PINS:
    CollectCallIdents and CollectRaiseClass each declared their brace-comment
    depth as a LOCAL, reset to zero on EVERY line, and neither handled star-paren
    comments at all. So a block comment opened on an earlier line was invisible
    and its prose was scanned as code.

    That matters because the call scan matches "Identifier" followed by an open
    paren, and ordinary English matches it:

      { ... the defect (2026-08-14) was ... }   ->  Calls: defect
      { ..., so (in this case) ... }            ->  Calls: so

    Both were found in COMMITTED source -- EnumHelper.Generate carried `so`, and
    Doc.SharedFacts.BlockDrifted carried `defect`, harvested by the same autodoc
    pass that rendered the comment it came from. A corpus sweep of this repo's own
    documentation found 150 such entries (`constantly`, `unreferenced`,
    `untouched`, `until`, `yet`), and that is a FLOOR: it counted only
    all-lowercase single tokens, so capitalised prose is not in the number.

    Worse than noise. The block ASSERTS A CALL THAT DOES NOT EXIST -- the class
    this repo treats as more serious than an absent fact, which is why
    doc-param-not-in-signature was split out of doc-drift and raised to error.
    It is also self-reinforcing: the fact is rendered into a comment, which is
    then prose the next extraction reads.

    The raises scan is the sharper edge of the same bug: prose reading "we raise
    EFoo when ..." inside a block comment produces not a noisy fact line but a
    FABRICATED <exception cref> tag for a class that is never raised.

  Assertions (all against the block actually written to the file):
    1. `defect` (prose, brace comment, followed by a paren) is NOT a callee.
    2. `so` (prose, brace comment) is NOT a callee.
    3. `pretend` (prose, STAR-PAREN comment) is NOT a callee -- that comment form
       was not handled on any line, not merely across lines.
    4. The real callee IS listed. Without this the three above would pass with
       the Calls: line absent entirely, which is exactly how a filter that
       over-fires looks.
    5. No <exception cref> for the class named only in comment prose.
    6. The genuinely raised class IS documented -- the control for 5.
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\drag-lint-doc-comment-prose"
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

# Worker's body carries three multi-line comments whose prose has the exact shape
# the scan mistakes for a call -- a word followed by an open paren -- plus one
# real call and one real raise. Caller01 exists so the facts-only gate emits a
# managed block at all (a routine with no callers gets none).
$FixtureBody = @'
unit uProse2;
interface
type
  EReal = class(Exception);
  EOnlyInProse = class(Exception);
function Helper(const A: Integer): Integer;
function Worker(const A: Integer): Integer;
procedure Caller01;
implementation
uses System.SysUtils;
function Helper(const A: Integer): Integer;
begin
  Result := A + 1;
end;
function Worker(const A: Integer): Integer;
begin
  { This comment spans several lines on purpose, because the brace depth used to
    reset on every one of them.

    The defect (2026-08-14) was that prose like this was scanned as code, and
    so (in this case) two ordinary words became callees.

    It also claimed we raise EOnlyInProse here, which we never do. }
  (* A star-paren comment, which was not handled on any line at all. Let us
     pretend (briefly) that this reads as a call. *)
  Result := Helper(A);
  if Result < 0 then
    raise EReal.Create('negative');
end;
procedure Caller01;
begin
  Worker(1);
end;
end.
'@
$file = Join-Path $WorkDir 'uProse2.pas'
$norm = ($FixtureBody -replace "`r`n", "`n") -replace "`n", "`r`n"
[System.IO.File]::WriteAllText($file, $norm, [System.Text.Encoding]::ASCII)

$db = Join-Path $WorkDir 'fx.sqlite'
& $Exe index $WorkDir --db $db 2>&1 | Out-Null
Push-Location $WorkDir
try { & $Exe document --qname uProse2.Worker --db $db --apply --no-backup 2>&1 | Out-Null }
finally { Pop-Location }

$text = Get-Content $file -Raw
$callsLine = ($text -split "`r?`n" | Where-Object { $_ -match '///\s*Calls:' } | Select-Object -First 1)
if (-not $callsLine) { $callsLine = '' }

Write-Host 'Prose in a block comment is not a call' -ForegroundColor Cyan
Write-Host "  Calls: line = $callsLine" -ForegroundColor DarkGray
Check 'brace-comment prose word "defect" is NOT a callee' (-not ($callsLine -match '\bdefect\b')) $callsLine
Check 'brace-comment prose word "so" is NOT a callee'     (-not ($callsLine -match '(?<![\w.])so(?![\w.])')) $callsLine
Check 'star-paren prose word "pretend" is NOT a callee'   (-not ($callsLine -match '\bpretend\b')) $callsLine

Write-Host ''
Write-Host 'CONTROL: the real callee is still listed' -ForegroundColor Cyan
Check 'Helper IS listed as a callee' ($callsLine -match 'Helper') $callsLine
if ($callsLine -notmatch 'Helper') {
  Write-Host '  !! The control failed. The three assertions above prove nothing --' -ForegroundColor Yellow
  Write-Host '  !! they would all pass with the Calls: line missing entirely, which' -ForegroundColor Yellow
  Write-Host '  !! is precisely what an over-firing comment filter looks like.' -ForegroundColor Yellow
}

Write-Host ''
Write-Host 'The raises scan: prose must not fabricate an <exception cref>' -ForegroundColor Cyan
$crefs = @([regex]::Matches($text, '<exception cref="([^"]+)"') | ForEach-Object { $_.Groups[1].Value })
Write-Host ("  exception crefs = " + ($crefs -join ', ')) -ForegroundColor DarkGray
Check 'EOnlyInProse (named only in a comment) has NO cref' `
  (-not ($crefs -match 'EOnlyInProse')) (($crefs -join ', '))
Check 'EReal (genuinely raised) IS documented -- the control for the above' `
  ([bool]($crefs -match 'EReal')) (($crefs -join ', '))

Write-Host ''
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
