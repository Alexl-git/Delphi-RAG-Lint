<#
  run_calls_resolved.ps1 -- Task 10: AutoDocument's outgoing "Calls:" facts
  prefer RESOLVED callees (qualified, via call_edges) over the bare-identifier
  body-scan, falling back to the body-scan for sites call_edges can't resolve.

  Fixture callsfacts.pas, TDriver.DoWork:
    W := TWorker.Create;   -- Create has no call_edge AND no '(' -> invisible to
                              both paths (accepted; not asserted either way)
    W.Run;                 -- typed-local receiver -> RESOLVES to
                               callsfacts.TWorker.Run
    SetLength(Arr, 3);     -- a compiler INTRINSIC -> deliberately NOT a callee
    ExternalHelper(3);     -- declared nowhere -> never resolves -> body-scan
                              FALLBACK must still show it
    W.Free;                -- no call_edge, no '(' -> invisible to both paths

  After `document --qname callsfacts.TDriver.DoWork --apply`, the Calls line:
    - INCLUDES the RESOLVED qualified callee 'callsfacts.TWorker.Run'
    - EXCLUDES the bare 'Run' (suppressed -- same call site, now shown qualified)
    - STILL INCLUDES 'ExternalHelper' via the body-scan fallback (nothing lost)
    - EXCLUDES 'SetLength' (an intrinsic is syntax, not a collaborator)
  A second index+apply must reproduce a BYTE-IDENTICAL file (idempotency).

  Run from a NEUTRAL CWD (C:\TEMP) so no drag-lint-lint.json is picked up.
#>
[CmdletBinding()]
param([string]$Exe = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe")

$ErrorActionPreference = 'Stop'; $fail = $false
function Check($n,$ok){ Write-Host ("[{0}] {1}" -f (@('FAIL','PASS')[[int]$ok]),$n) -ForegroundColor (@('Red','Green')[[int]$ok]); if(-not $ok){$script:fail=$true} }

$exePath = (Resolve-Path $Exe).Path
$fixture = (Resolve-Path (Join-Path $PSScriptRoot 'fixtures\callsfacts.pas')).Path

# Fresh scratch dir; keep the unit name so unit-name-matches-file stays quiet.
$scratch = Join-Path C:\TEMP 'draglint_callsresolved'
if (Test-Path $scratch) { Remove-Item $scratch -Recurse -Force }
New-Item -ItemType Directory -Path $scratch | Out-Null
$target  = Join-Path $scratch 'callsfacts.pas'
$db      = Join-Path $scratch 'cr.sqlite'
Copy-Item $fixture $target -Force

Push-Location C:\TEMP
try {
  & $exePath index $scratch --db $db 2>$null | Out-Null

  & $exePath document --qname callsfacts.TDriver.DoWork --db $db --apply 2>$null | Out-Null
  Check 'apply: .bak written' (Test-Path "$target.bak")

  $txt = [IO.File]::ReadAllText($target)
  # The '^\s*///' half is LOAD-BEARING, not decoration. Without it this picked
  # up the fixture's own header comment, which DISCUSSES what a Calls line looks
  # like -- so every assertion below ran against prose instead of engine output
  # and four of them failed while the emitted line was perfectly correct. A
  # filter that matches the thing it is describing is the shape of a vacuous
  # test; run_doc_p3_callerline records being bitten by exactly this.
  $line = ($txt -split "`r?`n" | Where-Object { $_ -match '^\s*///' -and $_ -match 'Calls:' } | Select-Object -First 1)
  Check 'Calls: line present' ($null -ne $line -and $line -ne '')

  # --- RESOLVED: W.Run resolves (typed-local receiver) to callsfacts.TWorker.Run.
  Check 'INCLUDES resolved qualified callee callsfacts.TWorker.Run' `
    ($line -match 'callsfacts\.TWorker\.Run')

  # --- SUPPRESSED: the bare 'Run' must NOT appear as its own separate entry --
  # only the qualified 'callsfacts.TWorker.Run' should be present (no
  # double-listing of the same call site).
  $lineWithoutQualified = $line -replace 'callsfacts\.TWorker\.Run', ''
  Check 'EXCLUDES bare Run as a separate entry (no double-listing)' `
    (-not ($lineWithoutQualified -match '(?<!\.)\bRun\b'))

  # --- FALLBACK: ExternalHelper is declared nowhere, so it never resolves --
  # still present via the body-scan fallback, so nothing is lost.
  Check 'STILL INCLUDES ExternalHelper (unresolved, body-scan fallback)' `
    ($line -match '\bExternalHelper\b')

  # --- INTRINSIC: SetLength is in the body but is NOT a collaborator. The pair
  # of assertions is the point: on its own, the one above passes even if the
  # fallback bucket were emptied, and this one passes even if Calls were dropped
  # entirely. Together they say intrinsics -- and only intrinsics -- are filtered.
  Check 'EXCLUDES SetLength (a compiler intrinsic, not a callee)' `
    (-not ($line -match '\bSetLength\b'))

  # --- D5 fast-follow (T10): SAME-LEAF-NAME, DIFFERENT-QUALIFIED targets. O.Run
  # (typed-local receiver) resolves to callsfacts.TOther.Run -- a DIFFERENT
  # method that merely shares the leaf name 'Run' with W.Run's target
  # (callsfacts.TWorker.Run). Both must appear, fully qualified, and distinct --
  # if the resolver ever collapsed same-leaf-name targets, this would either
  # drop one qualified entry or double up a bare 'Run'.
  Check 'INCLUDES resolved qualified callee callsfacts.TOther.Run' `
    ($line -match 'callsfacts\.TOther\.Run')
  $lineWithoutEitherQualified = $line -replace 'callsfacts\.TWorker\.Run', '' -replace 'callsfacts\.TOther\.Run', ''
  Check 'EXCLUDES bare Run even with two distinct qualified Run targets' `
    (-not ($lineWithoutEitherQualified -match '(?<!\.)\bRun\b'))

  # --- IDEMPOTENCY: reindex (call_edges is rebuilt) + apply again -> byte-identical.
  $before = [IO.File]::ReadAllBytes($target)
  & $exePath index $scratch --db $db 2>$null | Out-Null
  & $exePath document --qname callsfacts.TDriver.DoWork --db $db --apply 2>$null | Out-Null
  $after = [IO.File]::ReadAllBytes($target)
  Check 'idempotent: second apply is byte-identical' ([System.Linq.Enumerable]::SequenceEqual([byte[]]$before,[byte[]]$after))
} finally { Pop-Location }

if($fail){ Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
