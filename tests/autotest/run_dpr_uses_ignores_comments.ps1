<#
  run_dpr_uses_ignores_comments.ps1 -- a commented-out unit is not a member of the
  compile closure, and the word "uses" in a header comment does not start a uses
  clause.

  THE DEFECT THIS PINS:
    ParseDprUses (DRagLint.Index.Closure) had two independent halves of the same
    bug. It anchored `\buses\b` against UNSCRUBBED text, and its ad-hoc stripper
    handled BRACE comments only -- not slash-slash, not star-paren -- and ran only
    AFTER the clause had been located. So:

      * a .dpr header comment containing the word "uses" anchored the search, and
        whatever followed was read as a uses clause;
      * `// OldUnit in 'old.pas',` inside a real clause survived the strip and was
        harvested as a live unit.

    Either way PHANTOM UNITS ENTER THE COMPILE CLOSURE, which is the input to
    project index membership: the unit gets indexed, its symbols answer queries,
    and `lint-all --project` reports on a file the project does not compile. A
    member wrongly DROPPED is the same defect in the quiet direction, which is why
    the positive control below matters as much as the negative one.

    Fixed by scrubbing the whole file with StripPasCommentsKeepLayout FIRST -- the
    same function ParseUsesFromContent already used for the .pas path, so the two
    readers now agree by construction rather than by coincidence. This was the 5th
    of nine instances of "a text scan cannot tell code from comment"; see
    docs\INBOX-remaining-raw-text-scans-read-comments-as-code.md.

  The fixture puts all three comment forms in the clause, and a "uses" in the
  header comment, so a regression in any one of them is visible separately.
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\drag-lint-dpr-uses-comments"
)
$ErrorActionPreference = 'Stop'
$script:Failed = $false
function Check($n, $ok, $d = '') {
  $s = if ($ok) { 'PASS' } else { 'FAIL' }
  $c = if ($ok) { 'Green' } else { 'Red' }
  Write-Host ("  [{0}] {1} {2}" -f $s, $n, $d) -ForegroundColor $c
  if (-not $ok) { $script:Failed = $true }
}
function Write-Ascii([string]$Path, [string]$Text) {
  $norm = ($Text -replace "`r`n", "`n") -replace "`n", "`r`n"
  [System.IO.File]::WriteAllText($Path, $norm, [System.Text.Encoding]::ASCII)
}

if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
$Exe = (Resolve-Path $Exe).Path
if (Test-Path $WorkDir) { Remove-Item -Recurse -Force $WorkDir }
New-Item -ItemType Directory $WorkDir | Out-Null

# Real members: uLive, uAlsoLive. Commented out three different ways: uSlashOut,
# uBraceOut, uParenOut -- each of which EXISTS on disk, so the only thing keeping
# it out of the closure is that its mention is commented.
foreach ($u in @('uLive','uAlsoLive','uSlashOut','uBraceOut','uParenOut')) {
  Write-Ascii (Join-Path $WorkDir "$u.pas") @"
unit $u;
interface
procedure ${u}_Marker;
implementation
procedure ${u}_Marker;
begin
end;
end.
"@
}

# NOTE the header comment contains the word "uses" -- that alone used to anchor
# the clause search.
Write-Ascii (Join-Path $WorkDir 'App.dpr') @'
program App;

{ This program uses several units. The word above is deliberate: it used to
  anchor the uses-clause search all by itself. }

uses
  uLive in 'uLive.pas',
  // uSlashOut in 'uSlashOut.pas',
  { uBraceOut in 'uBraceOut.pas', }
  (* uParenOut in 'uParenOut.pas', *)
  uAlsoLive in 'uAlsoLive.pas';

begin
  uLive_Marker;
  uAlsoLive_Marker;
end.
'@

$db = Join-Path $WorkDir 'app.sqlite'
# `--project`, NOT a positional path. A positional .dpr is indexed as a single
# FILE (measured: "Files: 1, Symbols: 0"); only the --project arm runs
# TClosureResolver, which is what calls ParseDprUses. The positive control below
# is what caught this -- the negative assertions all "passed" against an index
# containing nothing at all.
$idx = & $Exe index --project (Join-Path $WorkDir 'App.dpr') --db $db --platform Win64 --quiet 2>&1 | Out-String
if ($LASTEXITCODE -ne 0) {
  Write-Host "FATAL: index --project failed (exit $LASTEXITCODE): $(($idx -split "`r?`n" | Where-Object { $_ } | Select-Object -Last 2) -join ' | ')" -ForegroundColor Red
  exit 2
}

# selftest files lists what the closure actually put in the index.
$files = & $Exe selftest files --db $db 2>&1 | Out-String
function InIndex([string]$Unit) { [bool]($files -match [regex]::Escape("$Unit.pas")) }

Write-Host 'PRECONDITION: the commented-out units EXIST on disk' -ForegroundColor Cyan
$allPresent = $true
foreach ($u in @('uSlashOut','uBraceOut','uParenOut')) {
  if (-not (Test-Path (Join-Path $WorkDir "$u.pas"))) { $allPresent = $false }
}
Check 'all three commented-out units are real files' $allPresent `
  'otherwise their absence from the index proves nothing'
if (-not $allPresent) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 }

Write-Host ''
Write-Host 'POSITIVE CONTROL: the real members ARE in the closure' -ForegroundColor Cyan
# Without this, every assertion below passes when the clause fails to parse at all
# -- which is exactly what over-aggressive scrubbing would cause.
Check 'uLive is indexed (the clause parsed at all)'     (InIndex 'uLive')     $null
Check 'uAlsoLive is indexed (the clause parsed to its END, past all three comments)' `
  (InIndex 'uAlsoLive') 'this is what catches a scrub that swallows the rest of the clause'

Write-Host ''
Write-Host 'A commented-out member is NOT a closure member' -ForegroundColor Cyan
Check 'uSlashOut (slash-slash) is NOT indexed' (-not (InIndex 'uSlashOut')) $null
Check 'uBraceOut (brace) is NOT indexed'       (-not (InIndex 'uBraceOut'))  $null
Check 'uParenOut (star-paren) is NOT indexed'  (-not (InIndex 'uParenOut'))  $null

Write-Host ''
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
