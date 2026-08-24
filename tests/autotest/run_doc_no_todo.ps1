<#
  run_doc_no_todo.ps1 -- ADP1 "remove TODO placeholder" regression.

  The auto-document engine used to emit 'TODO: describe.' as BOTH the
  placeholder text (<summary>/<param>/<returns>) AND the sentinel that tells
  the merge logic "this is managed/regenerable content, not hand-typed
  prose". drag-lint's own TODO lint rule then flagged its own generated
  docs. Fix: emit EMPTY placeholders (and for <returns>, just the mined
  'Observed: ...' facts when there are any) while IsManagedDesc keeps
  recognizing BOTH empty content and the legacy 'TODO: describe.' string so
  hand-typed prose is still preserved and old TODO docs get cleaned up on
  re-run.

  v(ADP3 T1) update: "EMPTY placeholders" is no longer literally true --
  ownership is now marker-keyed (AUTO_MARK, '<!-- drag-lint:auto -->'),
  emitted as the FIRST characters of a managed tag's text content, so a
  managed <summary>/<param> is empty-OF-PROSE but carries the marker, and a
  managed <returns> carries the marker immediately followed by the mined
  'Observed: ...' suffix. The zero-TODO guarantee this scenario tests is
  unchanged; only the exact managed-tag SHAPE below reflects the marker.

  v(ADP3 T3) update: "empty-OF-PROSE but carries the marker" is no longer
  true for <summary>/<param> either -- omit-when-empty means a tag with
  NOTHING to say (no hand-written/harvested content) is not written AT ALL,
  not written as a marker-only stub. Grab has no hand-written/harvested
  summary and AWidth has no hand-written description, so BOTH tags are now
  entirely ABSENT from the fresh comment. <returns> is UNCHANGED (Grab has a
  real mined return case, so it survives with content, same shape as before).

  SCENARIO A -- fresh emit, zero TODO, facts survive: index a fixture with a
  function (Grab: params + a single mined `Result := ...` case) and a caller
  (UseGrab, for the Called-from fact), `document --apply --no-backup`, then
  assert the written file contains ZERO occurrences of the substring 'TODO'
  ANYWHERE, while the facts are genuinely present:
    - NO <summary> tag at all (nothing hand-written/harvested to say)
    - NO <param name="AWidth"> tag at all (no hand-written description)
    - <returns><!-- drag-lint:auto -->Observed: ...</returns> (marker, then
      the mined case, no TODO prefix)
    - the drag-lint:auto BEGIN/END facts fence with "Called from:"

  SCENARIO B -- idempotency: RE-INDEX (mirrors run_doc_returns.ps1 Scenario
  C / run_doc_idempotent.ps1's documented mtime-staleness requirement -- a
  stale index hands back pre-insert line numbers and a naive second apply
  would insert a second comment block) then apply again. Bytes must be
  byte-identical and the second run must report action=unchanged/edits=0.

  SCENARIO C -- legacy cleanup: seed a unit whose managed doc region ALREADY
  carries the old bare 'TODO: describe.' placeholders (summary + param +
  returns, the shape the OLD engine used to write BEFORE any return case was
  mined, AUTO_PARAM-marked so they read as managed on re-parse) plus a stale
  managed facts fence. Running `document --apply` again must REMOVE every
  'TODO' occurrence (replaced by empty / freshly mined Observed facts) --
  proving IsManagedDesc still recognizes the legacy sentinel and regenerates
  it away, i.e. old TODO docs self-heal on the next document run.

  Run from a NEUTRAL CWD ($env:TEMP\drag-lint-doc-no-todo).
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\drag-lint-doc-no-todo"
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
# Resolve $Exe to an ABSOLUTE path up front (see run_doc_returns.ps1 -- other
# scenarios in this suite family Push-Location, so keep the habit here too).
$Exe = (Resolve-Path $Exe).Path
if (Test-Path $WorkDir) { Remove-Item -Recurse -Force $WorkDir }
New-Item -ItemType Directory $WorkDir | Out-Null

# Fixture: Grab has ONE mined return case (rlines <> 0) and one param
# (AWidth). UseGrab is a caller so the facts block carries "Called from:".
$FixtureBody = @'
unit uNoTodo;
interface
function Grab(const AWidth: Integer): Boolean;
function UseGrab: Boolean;
implementation
function Grab(const AWidth: Integer): Boolean;
var rlines: Integer;
begin
  rlines := AWidth;
  Result := rlines <> 0;
end;
function UseGrab: Boolean;
begin
  Result := Grab(3);
end;
end.
'@
function Write-Fixture([string]$Path) {
  $norm = $FixtureBody -replace "`r`n", "`n" -replace "`n", "`r`n"
  [System.IO.File]::WriteAllText($Path, $norm, [System.Text.Encoding]::ASCII)
}

Write-Host 'Scenario A: fresh emit -- zero TODO, facts survive' -ForegroundColor Cyan
$dirA  = Join-Path $WorkDir 'a'
New-Item -ItemType Directory $dirA | Out-Null
$fileA = Join-Path $dirA 'uNoTodo.pas'
$dbA   = Join-Path $dirA 'a.sqlite'
Write-Fixture $fileA
& $Exe index $dirA --db $dbA 2>&1 | Out-Null
& $Exe document --qname uNoTodo.Grab --db $dbA --apply --no-backup 2>&1 | Out-Null
$textA = Get-Content $fileA -Raw

Check 'ZERO "TODO" occurrences anywhere in the file' `
  ($textA -cnotmatch 'TODO') $textA

# v(ADP3 T3): omit-when-empty -- Grab has no hand-written/harvested summary
# and AWidth has no hand-written description, so NEITHER tag is emitted at
# all anymore (a marker-only stub is no longer written; see the header note).
$summaryLinesA = @([regex]::Matches($textA, '<summary>.*?</summary>') | ForEach-Object { $_.Value })
Check 'T3: NO <summary> tag at all (nothing to say)' ($summaryLinesA.Count -eq 0) "count=$($summaryLinesA.Count)"

# v(PHASE A3, ruling D-3): <param> parts company with <summary> here. An empty
# <summary> renders a BLANK tooltip and is omitted; an empty <param> is
# STRUCTURE -- it states the parameter exists and is undocumented, and it is what
# lets doc-drift's 'has no <param> tag' finding be cleared at all. What this
# runner is ABOUT is unchanged and still holds: the tag carries no 'TODO'
# text -- an empty body, not a stub sentence (the zero-TODO assertion below
# covers the whole file).
$paramLinesA = @([regex]::Matches($textA, '<param name="AWidth">.*?</param>') | ForEach-Object { $_.Value })
# v(2026-08-10, owner ruling): the body is the DECLARED TYPE under AUTO_TYPE,
# not an empty shell -- a <param> must reflect the current signature because
# these comments are generated into doc/HTML help. Still exactly ONE tag, and
# still not a TODO stub, which is what this runner actually guards.
Check 'v(PHASE A3): exactly ONE <param name="AWidth"> tag, carrying its TYPE' `
  (($paramLinesA.Count -eq 1) -and ($paramLinesA[0] -eq '<param name="AWidth"><!-- drag-lint:auto type -->const Integer</param>')) "got=$($paramLinesA -join ' | ')"

$returnsLinesA = @([regex]::Matches($textA, '<returns>.*?</returns>') | ForEach-Object { $_.Value })
Check 'exactly one <returns> tag' ($returnsLinesA.Count -eq 1) "count=$($returnsLinesA.Count)"
Check '<returns> carries the marker then the mined Observed fact, no TODO prefix' `
  ($returnsLinesA.Count -gt 0 -and $returnsLinesA[0] -eq '<returns><!-- drag-lint:auto -->Boolean -- Observed: rlines &lt;&gt; 0.</returns>') $returnsLinesA

Check 'managed facts fence present' ($textA.Contains('<!-- drag-lint:auto BEGIN -->') -and $textA.Contains('<!-- drag-lint:auto END -->'))
Check 'facts: Called from: uNoTodo.UseGrab present' ($textA -match 'Called from:.*uNoTodo\.UseGrab')

Write-Host ''
Write-Host 'Scenario B: idempotency (apply, re-index, apply again -> byte-identical)' -ForegroundColor Cyan
$dirB  = Join-Path $WorkDir 'b'
New-Item -ItemType Directory $dirB | Out-Null
$fileB = Join-Path $dirB 'uNoTodo.pas'
$dbB   = Join-Path $dirB 'b.sqlite'
Write-Fixture $fileB
& $Exe index $dirB --db $dbB 2>&1 | Out-Null
& $Exe document --qname uNoTodo.Grab --db $dbB --apply --no-backup 2>&1 | Out-Null
$bytes1 = [IO.File]::ReadAllBytes($fileB)
# CRITICAL: re-index so the store sees the post-insert line numbers (see
# run_doc_returns.ps1 Scenario C / run_doc_idempotent.ps1) -- otherwise the
# stale index hands back pre-insert line numbers and the second apply would
# insert a SECOND comment block instead of recognizing daUnchanged.
& $Exe index $dirB --db $dbB 2>&1 | Out-Null
$r2 = (& $Exe document --qname uNoTodo.Grab --db $dbB --apply --no-backup --json 2>&1) -join "`n"
$bytes2 = [IO.File]::ReadAllBytes($fileB)

Check 'run2: action=unchanged' ($r2 -match '"action":"unchanged"') $r2
Check 'run2: edits=0'          ($r2 -match '"edits":0')            $r2
Check 'apply is idempotent (byte-identical)' `
  ([System.Linq.Enumerable]::SequenceEqual([byte[]]$bytes1, [byte[]]$bytes2))
$textB2 = Get-Content $fileB -Raw
Check 'still ZERO "TODO" after the idempotent 2nd apply' ($textB2 -cnotmatch 'TODO') $textB2

Write-Host ''
Write-Host 'Scenario C: legacy cleanup -- old TODO docs are regenerated away' -ForegroundColor Cyan
$dirC  = Join-Path $WorkDir 'c'
New-Item -ItemType Directory $dirC | Out-Null
$fileC = Join-Path $dirC 'uNoTodo.pas'
$dbC   = Join-Path $dirC 'c.sqlite'
# Same Grab/UseGrab shape, but pre-seeded with the shape the OLD engine used
# to write BEFORE any return case was mined: bare TODO summary, TODO param
# (AUTO_PARAM-marked so it reads back as managed), bare TODO returns (no
# Observed suffix yet), and a stale managed facts fence.
$LegacyBody = @'
unit uNoTodo;
interface
/// <summary>TODO: describe.</summary>
/// <param name="AWidth">TODO: describe.</param><!-- drag-lint:auto param -->
/// <returns>TODO: describe.</returns>
/// <remarks>
/// <!-- drag-lint:auto BEGIN -->
/// Called from: (none)
/// <!-- drag-lint:auto END -->
/// </remarks>
function Grab(const AWidth: Integer): Boolean;
function UseGrab: Boolean;
implementation
function Grab(const AWidth: Integer): Boolean;
var rlines: Integer;
begin
  rlines := AWidth;
  Result := rlines <> 0;
end;
function UseGrab: Boolean;
begin
  Result := Grab(3);
end;
end.
'@
$normC = $LegacyBody -replace "`r`n", "`n" -replace "`n", "`r`n"
[System.IO.File]::WriteAllText($fileC, $normC, [System.Text.Encoding]::ASCII)

& $Exe index $dirC --db $dbC 2>&1 | Out-Null
& $Exe document --qname uNoTodo.Grab --db $dbC --apply --no-backup 2>&1 | Out-Null
$textC = Get-Content $fileC -Raw

Check 'legacy cleanup: ZERO "TODO" occurrences after re-run' `
  ($textC -cnotmatch 'TODO') $textC
# v(ADP3 T3): the legacy 'TODO: describe.' summary sentinel still self-heals
# (IsEngineOwnedRegardlessOfContent recognizes it, same as the marker), but
# omit-when-empty now means it is regenerated to NOTHING rather than to a
# marker-only stub -- Grab has no hand-written/harvested summary, so the tag
# is dropped entirely.
$summaryLinesC = @([regex]::Matches($textC, '<summary>.*?</summary>') | ForEach-Object { $_.Value })
Check 'T3: legacy cleanup -- <summary> self-heals to NO tag at all (nothing to say)' `
  ($summaryLinesC.Count -eq 0) $summaryLinesC
$returnsLinesC = @([regex]::Matches($textC, '<returns>.*?</returns>') | ForEach-Object { $_.Value })
Check 'legacy cleanup: <returns> regenerated to marker + fresh Observed (stale text dropped)' `
  ($returnsLinesC.Count -gt 0 -and $returnsLinesC[0] -eq '<returns><!-- drag-lint:auto -->Boolean -- Observed: rlines &lt;&gt; 0.</returns>') $returnsLinesC
Check 'legacy cleanup: facts fence refreshed with real Called from:' `
  ($textC -match 'Called from:.*uNoTodo\.UseGrab')

Write-Host ''
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
