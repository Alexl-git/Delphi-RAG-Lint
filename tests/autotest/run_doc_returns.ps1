<#
  run_doc_returns.ps1 -- AutoDoc <returns> enumeration (Batch A item 1 / Task 10):
  manifest docs.max_return_cases wired end-to-end into the mined <returns> text.

  Hand-verified real output (document --qname uRet.Grab --apply --no-backup on
  the fixture below, cap=20 default):
    <returns>TODO: describe. Observed: False; rlines &lt;&gt; 0.</returns>
  -- both '<' and '>' are XML-escaped (to &lt; and &gt;), two distinct mined
  return cases in first-seen order. A procedure (DoNothing) gets a comment with
  NO Observed: text (HasRet is False for procedures).

  document --json is a THIN summary (qname/file/line/action/edits/applied --
  no <returns> text), so every scenario applies to a FRESH copy and asserts on
  the file written by --apply --no-backup.

  SCENARIO A -- enumeration + escaping: apply to a fresh copy with the default
  cap (20, no manifest involved). Assert the Grab <returns> line carries BOTH
  observed cases (False and the escaped rlines &lt;&gt; 0), and DoNothing's
  comment has no Observed: text at all.

  SCENARIO B -- cap: a LOCAL manifest override is looked up by TManifestIO.Load
  by walking UP from the CURRENT WORKING DIRECTORY for a DOTTED `.drag-lint.json`
  (NOT `drag-lint.json` -- that filename is only ever read as the GLOBAL config,
  beside the exe). So the cap fixture writes `.drag-lint.json` (dotted) into the
  work dir and the document call runs with that dir as CWD (Push-Location) so
  Load's local-walk finds it. With max_return_cases=1, only the FIRST mined case
  (False) is kept -- the second (rlines &lt;&gt; 0) must be ABSENT. This is
  asserted against a DIFFERENT fresh copy so it never collides with Scenario A's
  uncapped output.

  SCENARIO C -- idempotency: apply to a fresh copy, RE-INDEX (the store caches
  file content by mtime -- a stale index hands back pre-insert line numbers and
  the second apply would insert a SECOND comment block above the first instead
  of recognizing daUnchanged; see tests\autodoc\run_doc_idempotent.ps1's own
  documented CRITICAL step), then apply again. Bytes must be identical and the
  second run must report action=unchanged / edits=0.

  Run from a NEUTRAL CWD ($env:TEMP\drag-lint-doc-returns by default); Scenario
  B temporarily Push-Location's into its own cap subfolder to make the manifest
  local-walk find its dotted config, then Pop-Location's back out.
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\drag-lint-doc-returns"
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
if (Test-Path $WorkDir) { Remove-Item -Recurse -Force $WorkDir }
New-Item -ItemType Directory $WorkDir | Out-Null

# Fixture: Grab has 2 distinct mined return cases (False; rlines <> 0 -- the
# second exercises XML-escaping of both '<' and '>'). DoNothing is a procedure
# (no <returns> at all).
$FixtureBody = @'
unit uRet;
interface
function Grab(const AWidth: Integer): Boolean;
procedure DoNothing;
implementation
function Grab(const AWidth: Integer): Boolean;
var rlines: Integer;
begin
  Result := False;
  rlines := AWidth;
  Result := rlines <> 0;
end;
procedure DoNothing; begin end;
end.
'@
function Write-Fixture([string]$Path) {
  $norm = $FixtureBody -replace "`r`n", "`n" -replace "`n", "`r`n"
  [System.IO.File]::WriteAllText($Path, $norm, [System.Text.Encoding]::ASCII)
}

Write-Host 'Scenario A: enumeration + XML-escaping (default cap)' -ForegroundColor Cyan
$dirA = Join-Path $WorkDir 'a'
New-Item -ItemType Directory $dirA | Out-Null
$fileA = Join-Path $dirA 'uRet.pas'
$dbA   = Join-Path $dirA 'a.sqlite'
Write-Fixture $fileA
& $Exe index $dirA --db $dbA 2>&1 | Out-Null
& $Exe document --qname uRet.Grab --db $dbA --apply --no-backup 2>&1 | Out-Null
& $Exe document --qname uRet.DoNothing --db $dbA --apply --no-backup 2>&1 | Out-Null
$textA = Get-Content $fileA -Raw

# Isolate the actual <returns>...</returns> line(s) -- the implementation body
# below legitimately contains 'rlines' and '<>' as real Pascal code, so
# assertions must anchor to the doc-comment tag itself, not bare substrings.
$returnsLinesA = @([regex]::Matches($textA, '<returns>.*?</returns>') | ForEach-Object { $_.Value })

Check 'exactly one <returns> tag in the file (Grab only; DoNothing has none)' `
  ($returnsLinesA.Count -eq 1) "count=$($returnsLinesA.Count)"
Check 'Grab <returns> carries Observed:' ($returnsLinesA[0] -match '<returns>TODO: describe\. Observed:') $returnsLinesA[0]
Check 'Grab <returns> lists False'       ($returnsLinesA[0] -match 'Observed: False') $returnsLinesA[0]
Check 'Grab <returns> lists escaped rlines &lt;&gt; 0' ($returnsLinesA[0] -match 'rlines &lt;&gt; 0') $returnsLinesA[0]
Check 'Grab <returns> does NOT contain a raw unescaped < or >' `
  (-not ($returnsLinesA[0] -match 'rlines <> 0')) $returnsLinesA[0]

Write-Host ''
Write-Host 'Scenario B: manifest cap (max_return_cases=1) via LOCAL .drag-lint.json' -ForegroundColor Cyan
$dirB = Join-Path $WorkDir 'b'
New-Item -ItemType Directory $dirB | Out-Null
$fileB = Join-Path $dirB 'uRet.pas'
$dbB   = Join-Path $dirB 'b.sqlite'
Write-Fixture $fileB
# TManifestIO.Load's LOCAL override is a DOTTED .drag-lint.json, found by walking
# UP from the CURRENT WORKING DIRECTORY -- NOT beside the exe (that's the GLOBAL
# slot, undotted). Placing it in $dirB and running `document` with CWD=$dirB
# (Push-Location) is what makes Load's local-walk pick it up.
'{ "docs": { "max_return_cases": 1 } }' | Set-Content (Join-Path $dirB '.drag-lint.json') -Encoding ascii
& $Exe index $dirB --db $dbB 2>&1 | Out-Null
Push-Location $dirB
try {
  & $Exe document --qname uRet.Grab --db $dbB --apply --no-backup 2>&1 | Out-Null
} finally {
  Pop-Location
}
$textB = Get-Content $fileB -Raw
Remove-Item (Join-Path $dirB '.drag-lint.json') -Force

# Same anchoring discipline as Scenario A: assert against the <returns> tag
# itself, not bare substrings (the implementation body also contains 'rlines').
$returnsLinesB = @([regex]::Matches($textB, '<returns>.*?</returns>') | ForEach-Object { $_.Value })
Check 'cap=1: exactly one <returns> tag' ($returnsLinesB.Count -eq 1) "count=$($returnsLinesB.Count)"
Check 'cap=1: Observed: present'         ($returnsLinesB[0] -match 'Observed:') $returnsLinesB[0]
Check 'cap=1: keeps first case (False)'  ($returnsLinesB[0] -match 'Observed: False') $returnsLinesB[0]
Check 'cap=1: drops second case (rlines is absent from the tag)' `
  (-not ($returnsLinesB[0] -match 'rlines')) $returnsLinesB[0]
Check 'cap=1 <returns> DIFFERS from uncapped Scenario A <returns> (proves the wire works)' `
  ($returnsLinesB[0] -ne $returnsLinesA[0]) "B=$($returnsLinesB[0]) A=$($returnsLinesA[0])"

Write-Host ''
Write-Host 'Scenario C: idempotency (apply, re-index, apply again -> byte-identical)' -ForegroundColor Cyan
$dirC = Join-Path $WorkDir 'c'
New-Item -ItemType Directory $dirC | Out-Null
$fileC = Join-Path $dirC 'uRet.pas'
$dbC   = Join-Path $dirC 'c.sqlite'
Write-Fixture $fileC
& $Exe index $dirC --db $dbC 2>&1 | Out-Null
& $Exe document --qname uRet.Grab --db $dbC --apply --no-backup 2>&1 | Out-Null
$bytes1 = [IO.File]::ReadAllBytes($fileC)
# CRITICAL: re-index so the store sees the post-insert line numbers (mirrors
# tests\autodoc\run_doc_idempotent.ps1's documented requirement) -- otherwise
# the stale index hands back the pre-insert line and the second apply inserts a
# SECOND comment block instead of recognizing the symbol is already documented.
& $Exe index $dirC --db $dbC 2>&1 | Out-Null
$r2 = (& $Exe document --qname uRet.Grab --db $dbC --apply --no-backup --json 2>&1) -join "`n"
$bytes2 = [IO.File]::ReadAllBytes($fileC)

Check 'run2: action=unchanged' ($r2 -match '"action":"unchanged"') $r2
Check 'run2: edits=0'          ($r2 -match '"edits":0')            $r2
Check 'apply is idempotent (byte-identical)' `
  ([System.Linq.Enumerable]::SequenceEqual([byte[]]$bytes1, [byte[]]$bytes2))

Write-Host ''
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
