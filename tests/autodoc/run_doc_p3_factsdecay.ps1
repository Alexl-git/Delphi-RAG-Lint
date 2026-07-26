<#
  run_doc_p3_factsdecay.ps1 -- Auto-Document Phase 3, Task 3 (review follow-up
  round 3, Regression 2): a WHOLLY engine-authored facts-only <remarks> region
  (just the '<remarks>'/'</remarks>' wrapper around an AUTO_BEGIN..AUTO_END
  fence, no hand-written prose at all) was never recognized as fully
  engine-owned by RegionFullyEngineOwned. The engine always emits the wrapper
  as bare '<remarks>' / '</remarks>' lines (TDocRegions.MergeComment's remarks
  emission) -- neither line carries AUTO_MARK, and neither lies INSIDE the
  fence it encloses (the fence starts the line AFTER '<remarks>' and ends the
  line BEFORE '</remarks>'). So the guard's per-line loop always rejected such
  a region on its own wrapper tags: a DECAYED one (the source changed, so the
  fact it asserts -- e.g. "Called from: X" -- is no longer true) was neither
  refreshed nor deleted, and sat on disk asserting a stale, false fact
  permanently. `doc-drift` correctly flagged this as `ddFactsBlockStale,
  fixable:true` -- but neither `document --apply` nor `lint-all --fix --apply`
  could ever actually satisfy that fixable flag: the same defect class as the
  `ddParamMissing` staleness escalated earlier in this task.

  The fix: IsFenceOnlyRemarksSpan recognizes a '<remarks>'/'</remarks>' span
  as engine-owned ONLY when it encloses NOTHING but one well-formed fence (no
  hand-written prose alongside it) -- narrow enough that a '<remarks>' mixing
  real prose with the fence is NOT exempted (that prose line still has to earn
  ownership on its own merits, so the overall guard verdict is unaffected for
  that case), and a bare hand-written empty '<remarks></remarks>' (no fence at
  all) is also NOT exempted (fails closed when there is nothing to prove
  ownership).

  Scenario: Target has no doc comment; Caller calls it. First apply inserts a
  facts-only <remarks> (Called from: Caller). The call is then REMOVED
  (simulating real code drift) and the unit reindexed, making the fact false.
  Asserts:
    1. First apply: action=created, the facts-only remarks block is written.
    2. After removing the call + reindexing, `doc-drift` reports
       ddFactsBlockStale, fixable=true (corroborates the bug's own framing).
    3. Second apply: action=extended, edits=1 (a single delete -- the stale
       block is REMOVED, not left in place, and nothing survives to be
       reinserted since there is no longer anything to say).
    4. The stale "Called from:" text and the fence markers are GONE from the
       file; no comment remains above Target at all.
    5. Idempotent at the new (comment-less) fixed point: a further reindex +
       apply is byte-identical, action=unchanged, edits=0.

  Run from a NEUTRAL CWD (C:\TEMP), pwsh 7.
#>
[CmdletBinding()]
param([string]$Exe = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe")

$ErrorActionPreference = 'Continue'
function Check($n,$ok,$d=''){ Write-Host ("[{0}] {1} {2}" -f (@('FAIL','PASS')[[int]$ok]),$n,$d) -ForegroundColor (@('Red','Green')[[int]$ok]); if(-not $ok){$script:Failed=$true} }
$script:Failed = $false

$exePath = (Resolve-Path $Exe).Path

function Write-Ansi([string]$Path, [string]$Body) {
  $norm = $Body -replace "`r`n", "`n" -replace "`n", "`r`n"
  [System.IO.File]::WriteAllText($Path, $norm, [System.Text.Encoding]::ASCII)
}

$scratch = Join-Path C:\TEMP 'draglint_docp3factsdecay'
if (Test-Path $scratch) { Remove-Item $scratch -Recurse -Force }
New-Item -ItemType Directory -Path $scratch | Out-Null
$target = Join-Path $scratch 'factsdecay.pas'
$db     = Join-Path $scratch 'factsdecay.sqlite'

Write-Ansi $target @'
unit factsdecay;

interface

procedure Target;

procedure Caller;

implementation

procedure Target;
begin
end;

procedure Caller;
begin
  Target;
end;

end.
'@

Push-Location C:\TEMP
try {
  & $exePath index $scratch --db $db 2>$null | Out-Null
  Check 'index exits 0' ($LASTEXITCODE -eq 0)

  $json1 = (& $exePath document --qname factsdecay.Target --db $db --apply --json 2>$null) -join "`n"
  Check 'apply #1 exits 0' ($LASTEXITCODE -eq 0)
  Check '1. apply #1: action=created' ($json1 -match '"action":"created"') $json1
  $textFirst = [IO.File]::ReadAllText($target)
  Check '1. facts-only remarks block written (Called from: factsdecay.Caller)' `
    ($textFirst -match '<!-- drag-lint:auto BEGIN -->' -and $textFirst -match 'Called from:.*factsdecay\.Caller')

  # Simulate real code drift: remove the call, so the fact above is now false.
  $drifted = (Get-Content -Raw $target) -replace `
    "begin\r\n  Target;\r\nend;", `
    "begin`r`n  // no longer calls Target -- the fact above is now stale`r`nend;"
  [System.IO.File]::WriteAllText($target, $drifted, [System.Text.Encoding]::ASCII)

  & $exePath index $scratch --db $db 2>$null | Out-Null
  Check 'reindex (post-drift) exits 0' ($LASTEXITCODE -eq 0)

  $driftJson = (& $exePath doc-drift --qname factsdecay.Target --db $db --json 2>$null) -join "`n"
  Check '2. doc-drift reports ddFactsBlockStale' ($driftJson -match '"kind":"ddFactsBlockStale"') $driftJson
  Check '2. doc-drift reports fixable=true' ($driftJson -match '"fixable":true') $driftJson

  $json2 = (& $exePath document --qname factsdecay.Target --db $db --apply --json 2>$null) -join "`n"
  Check 'apply #2 exits 0' ($LASTEXITCODE -eq 0)
  Check '3. apply #2: action=extended' ($json2 -match '"action":"extended"') $json2
  Check '3. apply #2: edits=1 (a single delete, nothing reinserted)' ($json2 -match '"edits":1') $json2

  $textAfter = [IO.File]::ReadAllText($target)
  Check '4. stale "Called from:" text is gone' (-not ($textAfter -match 'Called from:'))
  Check '4. stale fence markers are gone' (-not ($textAfter -match 'drag-lint:auto'))
  $lines = [IO.File]::ReadAllLines($target)
  $declIdx = -1
  for ($i = 0; $i -lt $lines.Count; $i++) { if ($lines[$i] -match '^procedure Target;') { $declIdx = $i; break } }
  Check '4. Target decl found' ($declIdx -ge 0)
  Check '4. no /// line directly above Target (comment fully removed)' `
    (($declIdx -le 0) -or (-not ($lines[$declIdx - 1].TrimStart() -match '^///')))

  # --- 5. Idempotency at the new (comment-less) fixed point ---
  $before = [IO.File]::ReadAllBytes($target)
  & $exePath index $scratch --db $db 2>$null | Out-Null
  $json3 = (& $exePath document --qname factsdecay.Target --db $db --apply --json 2>$null) -join "`n"
  Check '5. apply #3: action=unchanged' ($json3 -match '"action":"unchanged"') $json3
  Check '5. apply #3: edits=0' ($json3 -match '"edits":0') $json3
  $after = [IO.File]::ReadAllBytes($target)
  Check '5. byte-identical after reindex + apply #3' `
    ([System.Linq.Enumerable]::SequenceEqual([byte[]]$before,[byte[]]$after))
} finally { Pop-Location }

if($script:Failed){ Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
