<#
  run_doc_p2_covered.ps1 -- Auto-Document Phase 2, Task 5: Covered-by-tests
  fact (which DUnitX/test methods exercise a routine), computed LAZILY at
  doc/hover RENDER time -- a CONTROLLER OVERRIDE to the brief's index-time
  approach. See DRagLint.Doc.SymbolFacts.ComputeCoveredBy's header comment
  for why: covered-by is a REVERSE edge (test calls target), so filling it in
  TSymbolFactsAnalyzer.Analyze at INDEX time would be non-deterministic
  w.r.t. per-file processing order (index Foo.pas before FooTests.pas, the
  usual alphabetical order, and the test->code call edge is not in
  call_edges yet). symbol_facts.covered_by stays RESERVED/UNWRITTEN.

  Uses THREE fixtures\docp2 files, all indexed into ONE scratch db:
    * covered.pas        -- function Target(X): Integer; + a NON-test caller
                             UseTargetDirectly (must NEVER appear in Target's
                             'Covered by:' fact).
    * coveredtest.pas    -- unit NAME matches the '*Test' convention (rule a);
                             TTargetTests.TestTarget calls Target, does NOT
                             derive TTestCase (proves rule (a) alone suffices).
                             ALSO holds ScanHelper -- a free, non-'Test'-named
                             helper in that same unit that calls Target (B10:
                             YADF's `CodeChars` in Test\GuardTest.dpr). A FILE-
                             name rule alone counts it as a test; it is not one.
    * coveredfixture.pas -- unit NAME does NOT match '*Test'/'Test*'; TLegacyCase
                             descends from TTestCase (rule b) and its
                             CheckTarget method calls Target (proves rule (b)
                             fires independent of naming; TTestCase itself is
                             never declared in this corpus -- an UNRESOLVED
                             heritage edge still carries the ancestor's NAME).

  Drives `index` -> `document --unit covered.pas --apply` and asserts, from
  covered.pas's content:
    1. Target's managed block has a 'Covered by:' line.
    2. That line's name-set is EXACTLY {coveredtest.TTargetTests.TestTarget,
       coveredfixture.TLegacyCase.CheckTarget} -- both test callers present,
       via BOTH detection rules -- and no more/fewer.
    3. UseTargetDirectly (the non-test caller) is NEVER in that set.
    4. UseTargetDirectly's OWN managed block (present via its own Calls:
       fact -- it calls Target) carries NO 'Covered by:' line (nothing calls
       UseTargetDirectly itself).
    5. Idempotency: reindex + a second --apply leaves covered.pas
       byte-identical (the lazy recompute is deterministic given the same DB).

  Run from a NEUTRAL CWD (C:\TEMP), pwsh 7.
#>
[CmdletBinding()]
param([string]$Exe = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe")

$ErrorActionPreference = 'Continue'
function Check($n,$ok){ Write-Host ("[{0}] {1}" -f (@('FAIL','PASS')[[int]$ok]),$n) -ForegroundColor (@('Red','Green')[[int]$ok]); if(-not $ok){$script:Failed=$true} }
$script:Failed = $false

$exePath = (Resolve-Path $Exe).Path
$fixDir  = Join-Path $PSScriptRoot 'fixtures\docp2'

$scratch = Join-Path C:\TEMP 'draglint_docp2covered'
if (Test-Path $scratch) { Remove-Item $scratch -Recurse -Force }
New-Item -ItemType Directory -Path $scratch | Out-Null
$target = Join-Path $scratch 'covered.pas'
$db     = Join-Path $scratch 'docp2covered.sqlite'
Copy-Item (Join-Path $fixDir 'covered.pas')        $target                                     -Force
Copy-Item (Join-Path $fixDir 'coveredtest.pas')    (Join-Path $scratch 'coveredtest.pas')       -Force
Copy-Item (Join-Path $fixDir 'coveredfixture.pas') (Join-Path $scratch 'coveredfixture.pas')    -Force

# Same scan-upward idiom as run_doc_p2_complexity.ps1 / run_doc_p2_fields.ps1's
# Get-DocBlockAbove: returns the contiguous run of ///-prefixed lines
# immediately above the FIRST line matching $declPattern (for a free function
# this is always the INTERFACE declaration, since it textually precedes the
# identical implementation signature line). $null if not found.
function Get-DocBlockAbove([string[]]$lines, [string]$declPattern) {
  $idx = -1
  for ($i = 0; $i -lt $lines.Count; $i++) { if ($lines[$i] -match $declPattern) { $idx = $i; break } }
  if ($idx -lt 0) { return $null }
  $blockLines = @()
  $j = $idx - 1
  while ($j -ge 0 -and $lines[$j].TrimStart() -match '^///') { $blockLines = ,($lines[$j]) + $blockLines; $j-- }
  return (($blockLines -join "`n") -replace '</?para>', '')
}

# Extracts the segment after "<label>: " to end-of-line (the 'Covered by:'
# line never shares its line with a sibling segment, unlike Reads/Writes, so
# no 3-space-separator splitting is needed here). $null if <label> is absent.
function Get-Segment([string]$block, [string]$label) {
  if ($null -eq $block) { return $null }
  $m = [regex]::Match($block, "${label}: ([^\r\n]*)")
  if (-not $m.Success) { return $null }
  return $m.Groups[1].Value
}

# Order-insensitive EXACT-SET comparison, tolerant of a trailing
# '(+N more)' suffix: $segment's comma-separated entries (trimmed) must be
# exactly $expectedNames, no more, no fewer.
function Test-NamesEqual([string]$segment, [string[]]$expectedNames) {
  if ($null -eq $segment) { return $false }
  $stripped = $segment -replace '\s*\(\+\d+ more\)$', ''
  $actual = @($stripped -split ',\s*' | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne '' })
  $expSorted = ($expectedNames | Sort-Object) -join '|'
  $actSorted = ($actual | Sort-Object) -join '|'
  return $expSorted -eq $actSorted
}

Push-Location C:\TEMP
try {
  & $exePath index $scratch --db $db 2>$null | Out-Null
  Check 'index exits 0' ($LASTEXITCODE -eq 0)

  & $exePath document --unit $target --db $db --apply 2>$null | Out-Null
  Check 'document --apply #1 exits 0' ($LASTEXITCODE -eq 0)

  $lines = [IO.File]::ReadAllLines($target)

  # --- Target: Covered by exactly the two test callers, no non-test leak ---
  $targetBlock = Get-DocBlockAbove $lines '^function Target\(X: Integer\): Integer;'
  Check 'Target decl found' ($null -ne $targetBlock)
  Check 'Target has a managed block (AUTO_BEGIN)' (($null -ne $targetBlock) -and ($targetBlock -match '<!-- drag-lint:auto BEGIN -->'))
  $coveredSeg = Get-Segment $targetBlock 'Covered by'
  Check 'Target has a Covered by: line' ($null -ne $coveredSeg)
  if ($null -ne $coveredSeg) {
    Check 'Covered by is exactly {coveredtest.TTargetTests.TestTarget, coveredfixture.TLegacyCase.CheckTarget}' `
      (Test-NamesEqual $coveredSeg @('coveredtest.TTargetTests.TestTarget','coveredfixture.TLegacyCase.CheckTarget'))
    Check 'Covered by does NOT include the non-test caller UseTargetDirectly' ($coveredSeg -notmatch 'UseTargetDirectly')
    # B10: the file-name rule (a) is NECESSARY but not SUFFICIENT. ScanHelper
    # lives in coveredtest.pas and calls Target, so the reverse walk reaches it;
    # only its own NAME (and its lack of a fixture class / TTestCase ancestry)
    # separates it from TestTarget one declaration above it.
    Check 'Covered by does NOT include ScanHelper -- a non-test helper inside a *Test-named unit (B10)' ($coveredSeg -notmatch 'ScanHelper')
  }

  # --- UseTargetDirectly: has a block (via its own Calls: fact) but NO Covered by ---
  $utdBlock = Get-DocBlockAbove $lines '^procedure UseTargetDirectly;\s*$'
  Check 'UseTargetDirectly decl found' ($null -ne $utdBlock)
  Check 'UseTargetDirectly has a managed block (via its own Calls: fact)' (($null -ne $utdBlock) -and ($utdBlock -match '<!-- drag-lint:auto BEGIN -->'))
  Check 'UseTargetDirectly has NO Covered by line (nothing calls it)' (($null -eq $utdBlock) -or ($utdBlock -notmatch 'Covered by:'))

  # --- Idempotency: reindex (facts are lazily recomputed each run) + re-apply -> no change ---
  $before = [IO.File]::ReadAllBytes($target)
  & $exePath index $scratch --db $db 2>$null | Out-Null
  & $exePath document --unit $target --db $db --apply 2>$null | Out-Null
  $after = [IO.File]::ReadAllBytes($target)
  Check 'idempotent: file byte-identical after reindex + 2nd apply' ([System.Linq.Enumerable]::SequenceEqual([byte[]]$before,[byte[]]$after))
} finally { Pop-Location }

if($script:Failed){ Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
