<#
  run_doc_returns_and_callers.ps1 -- Whole-Project Auto-Document Phase 1 /
  Task 1: manifest docs.max_return_cases + docs.max_callers wired end-to-end
  into ONE `document --qname` run.

  This is the combined regression for Task 1's two config knobs:
    - docs.max_return_cases (ALREADY wired since Task 10 -- see
      tests\autotest\run_doc_returns.ps1): caps the mined <returns>
      "Observed: ..." enumeration.
    - docs.max_callers (Task 1, NEW): caps the "Called from:" list. Before
      Task 1 this was a HARD-CODED constant (DocDisplayCount: total > 15 ->
      show 10) with no manifest knob at all -- see
      tests\autodoc\run_doc_cap.ps1, which pinned that OLD hard-coded
      behavior against the DEPLOYED exe and was UPDATED by this task to the
      new config-driven default (cap=5, "(+11 more)" for its 16-caller
      fixture). DocDisplayCount itself is untouched and still governs the
      separate Calls:/Used in units: lines -- only CalledFrom moved to the
      new docs.max_callers knob.

  Fixture (single unit, uRetCap.pas):
    - Grab: a function with 2 DISTINCT `Result := ...` sites (False; then
      `rlines <> 0`, which also exercises XML-escaping of the mined '<>' --
      same idiom as run_doc_returns.ps1's uRet.Grab).
    - Caller01..Caller07: seven separate top-level procedures, each calling
      Grab exactly once -- seven DISTINCT resolved callers (call_edges
      resolves each; distinct-by "EnclosingQName|File" so no dedupe collapses
      them).

  Manifest: a LOCAL .drag-lint.json (TManifestIO.Load's DOTTED local-override
  slot, found by walking UP from the CURRENT WORKING DIRECTORY -- NOT the
  undotted global-beside-exe slot; see run_doc_returns.ps1 Scenario B for the
  same mechanism) with:
    { "docs": { "max_return_cases": 6, "max_callers": 5 } }
  dropped into the fixture dir; `document` is run with CWD Push-Location'd
  into that dir so Load's local-walk finds it. This is deliberately NOT the
  real deployed third_party/dll-win64/drag-lint.json (which this task also
  updates for production) -- the test must be self-contained/deterministic
  regardless of the machine's real deployed manifest.

  Asserts (after --apply --no-backup, reading the written file):
    1. Exactly one <returns> tag; it carries 'Observed:' (mined enumeration,
       NOT a bare '<returns></returns>' with no Observed clause at all --
       mining is genuinely ON) with BOTH mined cases (False; the
       XML-escaped rlines &lt;&gt; 0), and NO "TODO" placeholder text (ADP1:
       the engine emits empty/Observed-only placeholders, never "TODO").
       [Late Phase 3 T1 churn: the opening tag now reads
       '<returns><!-- drag-lint:auto -->Observed: ...' -- the provenance
       marker (T1, commit 317d192) sits right after '<returns>'. This
       assertion was missed by T1's own regression sweep; updated here as an
       expectation-only fix, no engine change.]
    2. Exactly one "Called from:" line; it lists EXACTLY 5 distinct
       "uRetCap.CallerNN" names (Caller01..Caller05, first-seen/file order)
       and ends with the "(+2 more)" suffix (7 distinct callers - 5 shown).
       Caller06/Caller07 must NOT appear (past the cap).

  Run from a NEUTRAL CWD ($env:TEMP\drag-lint-doc-returns-and-callers);
  Push-Location's into the fixture dir only for the `document` call itself
  (mirrors run_doc_returns.ps1's discipline) then Pop-Location's back out.
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\drag-lint-doc-returns-and-callers"
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
# Resolve $Exe to an ABSOLUTE path up front: Push-Location below breaks a
# RELATIVE -Exe (it would no longer resolve from the new CWD).
$Exe = (Resolve-Path $Exe).Path
if (Test-Path $WorkDir) { Remove-Item -Recurse -Force $WorkDir }
New-Item -ItemType Directory $WorkDir | Out-Null

# Fixture: Grab has 2 distinct mined return cases (False; rlines <> 0 -- the
# second exercises XML-escaping of both '<' and '>'). Caller01..Caller07 are
# 7 distinct resolved callers of Grab.
$FixtureBody = @'
unit uRetCap;
interface
function Grab(const AWidth: Integer): Boolean;
procedure Caller01;
procedure Caller02;
procedure Caller03;
procedure Caller04;
procedure Caller05;
procedure Caller06;
procedure Caller07;
implementation
function Grab(const AWidth: Integer): Boolean;
var rlines: Integer;
begin
  Result := False;
  rlines := AWidth;
  Result := rlines <> 0;
end;
procedure Caller01; begin Grab(1); end;
procedure Caller02; begin Grab(2); end;
procedure Caller03; begin Grab(3); end;
procedure Caller04; begin Grab(4); end;
procedure Caller05; begin Grab(5); end;
procedure Caller06; begin Grab(6); end;
procedure Caller07; begin Grab(7); end;
end.
'@
function Write-Fixture([string]$Path) {
  $norm = $FixtureBody -replace "`r`n", "`n" -replace "`n", "`r`n"
  [System.IO.File]::WriteAllText($Path, $norm, [System.Text.Encoding]::ASCII)
}

$dir  = Join-Path $WorkDir 'fx'
New-Item -ItemType Directory $dir | Out-Null
$file = Join-Path $dir 'uRetCap.pas'
$db   = Join-Path $dir 'fx.sqlite'
Write-Fixture $file

# LOCAL .drag-lint.json (dotted -- TManifestIO.Load's local-override slot).
'{ "docs": { "max_return_cases": 6, "max_callers": 5 } }' |
  Set-Content (Join-Path $dir '.drag-lint.json') -Encoding ascii

& $Exe index $dir --db $db 2>&1 | Out-Null
Push-Location $dir
try {
  & $Exe document --qname uRetCap.Grab --db $db --apply --no-backup 2>&1 | Out-Null
} finally {
  Pop-Location
}
$text = Get-Content $file -Raw

Write-Host 'Returns: max_return_cases=6 enumerates the mined cases' -ForegroundColor Cyan
$returnsLines = @([regex]::Matches($text, '<returns>.*?</returns>') | ForEach-Object { $_.Value })
Check 'exactly one <returns> tag' ($returnsLines.Count -eq 1) "count=$($returnsLines.Count)"
$returnsTag = if ($returnsLines.Count -gt 0) { $returnsLines[0] } else { '' }
# v(ADP3 T1) late churn: see this file's header for why the marker is expected here.
Check 'returns carries Observed: (mining is ON, not a bare empty tag) with no TODO text' `
  ($returnsTag -match '^<returns><!-- drag-lint:auto -->Observed:') $returnsTag
Check 'returns lists False'                       ($returnsTag -match 'Observed: False') $returnsTag
Check 'returns lists escaped rlines &lt;&gt; 0'    ($returnsTag -match 'rlines &lt;&gt; 0') $returnsTag
Check 'returns has NO raw unescaped < or >'        (-not ($returnsTag -match 'rlines <> 0')) $returnsTag

Write-Host ''
Write-Host 'Callers: max_callers=5 caps "Called from:" to 5 + (+2 more)' -ForegroundColor Cyan
$calledLines = @($text -split "`r?`n" | Where-Object { $_ -match 'Called from:' })
Check 'exactly one "Called from:" line' ($calledLines.Count -eq 1) "count=$($calledLines.Count)"
$calledLine = if ($calledLines.Count -gt 0) { $calledLines[0] } else { '' }

Check 'callers: line ends with "(+2 more)"' ($calledLine -match '\(\+2 more\)\s*$') $calledLine

$shown = ([regex]::Matches($calledLine, 'uRetCap\.Caller\d{2}')).Count
Check 'callers: exactly 5 named callers shown' ($shown -eq 5) "shown=$shown; line=$calledLine"

Check 'callers: Caller01 shown (first)'      ($calledLine -match 'uRetCap\.Caller01\b') $calledLine
Check 'callers: Caller05 shown (last kept)'  ($calledLine -match 'uRetCap\.Caller05\b') $calledLine
Check 'callers: Caller06 NOT shown (past cap)' (-not ($calledLine -match 'uRetCap\.Caller06\b')) $calledLine
Check 'callers: Caller07 NOT shown (past cap)' (-not ($calledLine -match 'uRetCap\.Caller07\b')) $calledLine

Write-Host ''
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
