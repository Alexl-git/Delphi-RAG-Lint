<#
  run_doc_cap_parity.ps1 -- the CHECKER and the WRITER must build doc facts
  with the SAME caps.

  THE DEFECT THIS PINS (fixed 2026-08-14, commit f5c99cf):
    TDocDrift.Analyze called TDocFactsBuilder.Build with three arguments and
    took the DEFAULTS for the rest, while every `document` entry point passed
    the MANIFEST values. docs.max_return_cases is 6 in the deployed manifest
    and 20 in Build's default, so any routine with more than 6 minable return
    cases DEADLOCKED PERMANENTLY:

      document -> writes a `Returns:` fact line capped at 6
      checker  -> rebuilds one capped at 20, calls the block stale
      document -> re-renders the same 6, reports "nothing to document"

    No command could resolve it. Found on DRagLint.Refactor.EnumHelper.Generate.

  WHY THIS FILE EXISTS AT ALL (read before editing):
    Two earlier fixture attempts went VACUOUS -- they passed while testing
    nothing, because neither ever produced the `Returns:` FACT line the cap
    truncates. See docs\INBOX-OWED-guard-for-checker-writer-cap-parity.md.
    The missing precondition, found in DRagLint.Doc.Regions.pas:2856-2860:

      IncludeReturns := ReturnsHandWritten and AHasReturn
                        and (Length(AFacts.ReturnCases) > 0)

    where ReturnsHandWritten requires the declaration to ALREADY CARRY A
    HAND-WRITTEN <returns> TAG (AExistingHasAnyTag and
    StandaloneReturns.HasReturnsTag and not IsEngineOwnedRegardlessOfContent).
    For a managed/empty <returns> the mined cases go INSIDE the tag as
    "Observed: ..." instead (they never appear in both places), so a fixture
    with only bare `///` prose -- which is what both earlier attempts had --
    can never grow a `Returns:` fact line no matter how many cases it mines.

    Hence Grab below carries `/// <returns>The mapped code.</returns>`, copied
    from tests\autodoc\fixtures\docret\docret.pas's Doubler, which is the one
    fixture in the tree already known to take this path.

  Fixture (uCapPar.pas, single unit):
    - Grab: NINE distinct straight-line `Result := '<literal>'` sites, so the
      mined set (9) exceeds the manifest cap (6) and the fact line is genuinely
      truncated. Straight-line assignment is the shape run_doc_returns.ps1 and
      run_doc_returns_and_callers.ps1 already prove the miner handles; the
      `case`-statement shape attempt 1 used is NOT proven and is avoided here.
    - Grab carries a HAND-WRITTEN <returns> (see above) -- load-bearing.
    - Caller01: one resolved caller, so the facts-only gate emits a managed
      block at all (attempt 1 failed on exactly this: no caller, no block).

  Manifest: a LOCAL .drag-lint.json (TManifestIO.Load's DOTTED local-override
  slot, discovered by walking UP from the CURRENT WORKING DIRECTORY), rewritten
  in place between phases. Both commands are therefore run with CWD inside the
  fixture dir, and the ONLY thing that changes between the positive and the
  negative phase is docs.max_return_cases. Nothing depends on this machine's
  deployed manifest.

  Phases:
    1. PRECONDITION -- after `document --apply` at cap 6, the written file must
       carry a `Returns:` fact line listing EXACTLY 6 of the 9 cases, with the
       7th absent. If this fails the rest of the test is VACUOUS and says so.
    2. POSITIVE -- `lint` at cap 6 reports ZERO "managed facts block is out of
       date". Checker agrees with writer. This is the assertion the fix makes
       pass.
    3. NEGATIVE CONTROL -- rewrite the manifest to cap 20 and lint again: the
       finding MUST appear. This proves phase 2 is a live assertion and not a
       green light from two sides sharing one default, and it proves the
       checker reads the manifest cap at all (which is what f5c99cf installed).
    4. CONVERGENCE -- restore cap 6; a second `document --apply` must plan no
       further edits and leave the file byte-identical. This is the deadlock
       itself, asserted directly.
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\drag-lint-doc-cap-parity"
)
$ErrorActionPreference = 'Stop'
$script:Failed = $false
$script:Vacuous = $false
function Check($n, $ok, $d = '') {
  $s = if ($ok) { 'PASS' } else { 'FAIL' }
  $c = if ($ok) { 'Green' } else { 'Red' }
  Write-Host ("  [{0}] {1} {2}" -f $s, $n, $d) -ForegroundColor $c
  if (-not $ok) { $script:Failed = $true }
}

if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
# Resolve $Exe up front: Push-Location below would break a RELATIVE -Exe.
$Exe = (Resolve-Path $Exe).Path
if (Test-Path $WorkDir) { Remove-Item -Recurse -Force $WorkDir }
New-Item -ItemType Directory $WorkDir | Out-Null

# Nine DISTINCT mined return cases. The literals are single letters a..i so the
# "6 shown, 7th absent" assertion below can name an exact one ('g') that must
# not appear rather than counting separators and hoping.
$FixtureBody = @'
unit uCapPar;
interface
/// <summary>Maps a kind to its code.</summary>
/// <returns>The mapped code.</returns>
function Grab(const AKind: Integer): string;
procedure Caller01;
implementation
function Grab(const AKind: Integer): string;
begin
  Result := 'a';
  if AKind = 1 then Result := 'b';
  if AKind = 2 then Result := 'c';
  if AKind = 3 then Result := 'd';
  if AKind = 4 then Result := 'e';
  if AKind = 5 then Result := 'f';
  if AKind = 6 then Result := 'g';
  if AKind = 7 then Result := 'h';
  if AKind = 8 then Result := 'i';
end;
procedure Caller01; begin Grab(1); end;
end.
'@
function Write-Fixture([string]$Path) {
  $norm = $FixtureBody -replace "`r`n", "`n" -replace "`n", "`r`n"
  [System.IO.File]::WriteAllText($Path, $norm, [System.Text.Encoding]::ASCII)
}

$dir      = Join-Path $WorkDir 'fx'
New-Item -ItemType Directory $dir | Out-Null
$file     = Join-Path $dir 'uCapPar.pas'
$db       = Join-Path $dir 'fx.sqlite'
$manifest = Join-Path $dir '.drag-lint.json'
Write-Fixture $file

function Set-Cap([int]$N) {
  ('{ "docs": { "max_return_cases": ' + $N + ', "max_callers": 5 } }') |
    Set-Content $manifest -Encoding ascii
}
function Invoke-InDir([string[]]$DlArgs) {
  Push-Location $dir
  try { & $Exe @DlArgs 2>&1 | Out-String } finally { Pop-Location }
}
# doc-drift is a LINT-ALL rule, not a `lint <file>` rule: `lint uCapPar.pas`
# reports "0 finding(s)" on the very file `lint-all` reports the drift warning
# on, because the rule needs the store-wide documented-decl walk. Measured
# while building this test -- do not "simplify" these calls back to `lint`, it
# turns both phases green and vacuous. (Filed as
# docs\INBOX-lint-single-file-silently-omits-lint-all-rules.md.)
function Get-StaleCount {
  $out = Invoke-InDir @('lint-all', '--db', $db)
  ([regex]::Matches($out, 'managed facts block is out of date')).Count
}

Set-Cap 6
& $Exe index $dir --db $db 2>&1 | Out-Null
Invoke-InDir @('document', '--qname', 'uCapPar.Grab', '--db', $db, '--apply', '--no-backup') | Out-Null
$text = Get-Content $file -Raw

Write-Host 'PRECONDITION: the writer emitted a TRUNCATED "Returns:" fact line' -ForegroundColor Cyan
$retFactLines = @($text -split "`r?`n" | Where-Object { $_ -match 'Returns:' })
Check 'exactly one "Returns:" fact line' ($retFactLines.Count -eq 1) "count=$($retFactLines.Count)"
$retFact = if ($retFactLines.Count -gt 0) { $retFactLines[0] } else { '' }
# Mined cases render as the quoted source expression, semicolon-joined.
$shownCases = ([regex]::Matches($retFact, "'[a-i]'")).Count
Check 'exactly 6 of 9 cases shown (cap took effect)' ($shownCases -eq 6) "shown=$shownCases; line=$retFact"
Check "7th case 'g' NOT shown (past cap)" (-not ($retFact -match "'g'")) $retFact
if ($retFactLines.Count -ne 1 -or $shownCases -ne 6) {
  $script:Vacuous = $true
  Write-Host '  !! PRECONDITION FAILED -- every assertion below is VACUOUS.' -ForegroundColor Yellow
  Write-Host '  !! Do NOT "fix" this by relaxing the checks; two earlier attempts' -ForegroundColor Yellow
  Write-Host '  !! passed exactly this way while testing nothing. See the header.' -ForegroundColor Yellow
}

# The file changed, so the index must be refreshed before the checker reads it
# -- doc-drift inflates against a stale index (a full session was lost to this).
& $Exe index $dir --db $db 2>&1 | Out-Null

Write-Host ''
Write-Host 'POSITIVE: at cap 6 the checker AGREES with the writer' -ForegroundColor Cyan
$stale6 = Get-StaleCount
Check 'zero "managed facts block is out of date" at cap 6' ($stale6 -eq 0) "count=$stale6"

Write-Host ''
Write-Host 'NEGATIVE CONTROL: at cap 20 the checker MUST disagree' -ForegroundColor Cyan
Set-Cap 20
$stale20 = Get-StaleCount
Check 'the finding DOES fire when the caps diverge' ($stale20 -ge 1) "count=$stale20"
if ($stale20 -lt 1) {
  Write-Host '  !! The negative control did not fire, so the POSITIVE assertion' -ForegroundColor Yellow
  Write-Host '  !! above proves nothing: it would pass with the checker ignoring' -ForegroundColor Yellow
  Write-Host '  !! the manifest entirely, which is the bug this file pins.' -ForegroundColor Yellow
}

Write-Host ''
Write-Host 'CONVERGENCE: a second document pass at cap 6 is a no-op' -ForegroundColor Cyan
Set-Cap 6
$before = Get-Content $file -Raw
$doc2   = Invoke-InDir @('document', '--qname', 'uCapPar.Grab', '--db', $db, '--apply', '--no-backup')
$after  = Get-Content $file -Raw
Check 'file byte-identical after the second pass' ($before -ceq $after) `
  ("lenBefore={0} lenAfter={1}" -f $before.Length, $after.Length)
Check 'second pass applied 0 edits' ($doc2 -notmatch '[1-9]\d* edit\(s\) applied') `
  (($doc2 -split "`r?`n" | Where-Object { $_ -match 'edit\(s\)' } | Select-Object -First 1))

Write-Host ''
if ($script:Vacuous) {
  Write-Host 'FAIL (VACUOUS -- precondition not met)' -ForegroundColor Red; exit 1
}
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
