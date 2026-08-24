<#
  run_doc_returns.ps1 -- AutoDoc <returns> enumeration (Batch A item 1 / Task 10):
  manifest docs.max_return_cases wired end-to-end into the mined <returns> text.

  Hand-verified real output (document --qname uRet.Grab --apply --no-backup on
  the fixture below, cap=20 default):
    <returns><!-- drag-lint:auto -->Observed: False; rlines &lt;&gt; 0.</returns>
  -- both '<' and '>' are XML-escaped (to &lt; and &gt;), two distinct mined
  return cases in first-seen order, and NO "TODO" placeholder text (ADP1: the
  engine emits empty/Observed-only placeholders, never "TODO"). A procedure
  (DoNothing) gets a comment with NO Observed: text (HasRet is False for
  procedures). [Late Phase 3 T1 churn: the '<!-- drag-lint:auto -->' provenance
  marker (T1, commit 317d192) sits immediately after the opening <returns> tag
  on every managed/mined-only returns tag -- this file's Scenario A anchor
  check was missed by T1's own regression sweep; updated here, expectations
  only, no engine change.]

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

  SCENARIO D -- both-exist merge (global + local): LoadDocMaxReturnCases always
  calls TManifestIO.Load(ExtractFilePath(ParamStr(0)), GetCurrentDir) -- i.e.
  the GLOBAL config is read from beside the EXE ITSELF (not overridable via
  --config for the document verb). To exercise the both-exist merge branch we
  must run a COPY of the exe (+ its tree-sitter DLLs) from a throwaway dir that
  has its own undotted drag-lint.json (global, cap=20) beside it, with CWD'd
  into a subfolder carrying a dotted .drag-lint.json (local, cap=1). Regression
  guard for the bug where ParseTextEx never set a presence bit for the 'docs'
  block, so Load's both-exist branch (which starts Result:= GlobalManifest and
  only overrides Settings.* scalars gated on skXxx-in-LocalKeys) never carried
  Result.Docs from the local manifest -- a local max_return_cases override was
  silently dropped whenever a global manifest ALSO existed (the normal
  deployment, since a global drag-lint.json ships beside the real exe). Asserts
  exactly ONE Observed case survives (cap=1 from local), proving local won.

  Run from a NEUTRAL CWD ($env:TEMP\drag-lint-doc-returns by default); Scenario
  B temporarily Push-Location's into its own cap subfolder to make the manifest
  local-walk find its dotted config, then Pop-Location's back out. Scenario D
  does the same but additionally runs a COPIED exe so a GLOBAL config also
  resolves (beside that copy), forcing HaveGlobal=True simultaneously with
  HaveLocal=True.
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
# Resolve $Exe to an ABSOLUTE path up front: scenarios B and D Push-Location into
# a fixture dir, which breaks a RELATIVE -Exe (the relative path no longer resolves
# from the new CWD). Absolutize once so every '& $Exe' works regardless of CWD.
$Exe = (Resolve-Path $Exe).Path
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
# v(ADP3 T3) fix: REINDEX before documenting the SECOND symbol in the SAME
# file -- same requirement this suite documents extensively elsewhere (see
# Scenario C below, run_doc_idempotent.ps1, run_doc_no_todo.ps1 Scenario B):
# a stale index still holds DoNothing's PRE-INSERT line number after Grab's
# apply shifted it down, so FindDocRegionAbove can misattribute or corrupt a
# NEIGHBORING symbol's just-written comment. This was previously masked by
# coincidence -- Grab's old-shape fresh comment (<summary>+<param>+<returns>,
# 3 lines) always spanned past the 1-line stale window, so the mismatch was
# never actually hit; v(ADP3 T3) omit-when-empty shrinks Grab's comment here
# to ONE line (<returns> only -- no hand-written summary/param), which fits
# inside that window and exposed the missing reindex. Fixing the test, not
# the engine: every OTHER back-to-back apply in this suite already reindexes
# for exactly this reason.
& $Exe index $dirA --db $dbA 2>&1 | Out-Null
& $Exe document --qname uRet.DoNothing --db $dbA --apply --no-backup 2>&1 | Out-Null
$textA = Get-Content $fileA -Raw

# Isolate the actual <returns>...</returns> line(s) -- the implementation body
# below legitimately contains 'rlines' and '<>' as real Pascal code, so
# assertions must anchor to the doc-comment tag itself, not bare substrings.
$returnsLinesA = @([regex]::Matches($textA, '<returns>.*?</returns>') | ForEach-Object { $_.Value })

Check 'exactly one <returns> tag in the file (Grab only; DoNothing has none)' `
  ($returnsLinesA.Count -eq 1) "count=$($returnsLinesA.Count)"
# v(ADP3 T1) late churn: the returns tag now carries the '<!-- drag-lint:auto -->'
# provenance marker immediately after the opening tag (see this file's header).
Check 'Grab <returns> carries Observed: (no TODO placeholder)' ($returnsLinesA[0] -match '^<returns><!-- drag-lint:auto -->(?:[^<]*-- )?Observed:') $returnsLinesA[0]
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
Write-Host 'Scenario D: both-exist merge -- local docs.max_return_cases must win over global' -ForegroundColor Cyan
# Copy the exe + its tree-sitter DLLs into a throwaway "global" dir so
# ExtractFilePath(ParamStr(0)) resolves to OUR copy (not the real build output),
# then drop an undotted drag-lint.json (GLOBAL config, cap=20) beside it. A
# subfolder gets a dotted .drag-lint.json (LOCAL override, cap=1); running with
# CWD in that subfolder makes Load see BOTH configs at once.
$dirD    = Join-Path $WorkDir 'd'
$globalD = Join-Path $dirD 'globaldir'
$projD   = Join-Path $globalD 'proj'
New-Item -ItemType Directory $dirD, $globalD, $projD | Out-Null
$exeDir = Split-Path -Parent $Exe
foreach ($dll in @('tree-sitter.dll', 'tree-sitter-delphi13.dll', 'tree-sitter-dfm.dll')) {
  $src = Join-Path $exeDir $dll
  if (Test-Path $src) { Copy-Item $src (Join-Path $globalD $dll) -Force }
}
$exeCopy = Join-Path $globalD 'drag-lint.exe'
Copy-Item $Exe $exeCopy -Force
'{ "docs": { "max_return_cases": 20 } }' | Set-Content (Join-Path $globalD 'drag-lint.json') -Encoding ascii
'{ "docs": { "max_return_cases": 1 } }'  | Set-Content (Join-Path $projD '.drag-lint.json') -Encoding ascii

$fileD = Join-Path $projD 'uRet.pas'
$dbD   = Join-Path $projD 'd.sqlite'
Write-Fixture $fileD
& $exeCopy index $projD --db $dbD 2>&1 | Out-Null
Push-Location $projD
try {
  & $exeCopy document --qname uRet.Grab --db $dbD --apply --no-backup 2>&1 | Out-Null
} finally {
  Pop-Location
}
$textD = Get-Content $fileD -Raw
$returnsLinesD = @([regex]::Matches($textD, '<returns>.*?</returns>') | ForEach-Object { $_.Value })
Check 'both-exist: exactly one <returns> tag' ($returnsLinesD.Count -eq 1) "count=$($returnsLinesD.Count)"
Check 'both-exist: local cap=1 wins (keeps first case, False)' `
  ($returnsLinesD.Count -gt 0 -and $returnsLinesD[0] -match 'Observed: False') $returnsLinesD
Check 'both-exist: local cap=1 wins (drops second case -- rlines absent)' `
  ($returnsLinesD.Count -gt 0 -and -not ($returnsLinesD[0] -match 'rlines')) $returnsLinesD

Write-Host ''
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
