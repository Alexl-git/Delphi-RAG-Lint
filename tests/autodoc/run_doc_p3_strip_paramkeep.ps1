<#
  run_doc_p3_strip_paramkeep.ps1 -- Auto-Document Phase 3, Task 3 (review
  follow-up, point 2): `document --strip` must agree with `document --apply`'s
  Finding-1 param-only exception -- a marked <param> whose post-marker body
  is non-empty is now PRESERVED (marker stripped) by the write path, so strip
  must leave that exact shape COMPLETELY alone (marker included) rather than
  deleting it; <summary>/<returns> are UNCHANGED -- marked always means
  engine-owned there, stripped unconditionally regardless of content.

  Before this fix, Rule 1 stripped every marked <summary>/<param>/<returns>
  tag unconditionally, with no <param> exception -- so `--strip` would
  destroy the exact hand-written sentence `document --apply` now preserves,
  a silent divergence between the two verbs with no test catching it.

  Fixture fixtures\docp3\strip_paramkeep.pas (Task 2's static-fixture
  pattern -- markers baked in by hand, no `document` run needed): one
  function whose <summary>/<param>/<returns> are ALL marked, each carrying
  real text typed after the marker (simulating a developer who edited
  inside existing stubs without removing the HTML comments).

  Drives `index` -> `document --unit --strip --apply` and asserts:
    1. The marked <summary> SURVIVES untouched -- v(SESSION 74). It used to
       be REMOVED here ("marked = engine-owned regardless of content"), and
       that is exactly the rule the owner reversed on 2026-09-06: a bare
       AUTO_MARK tag holding words a developer typed is the HUMAN's under
       ruling D-4. `document --apply` now preserves it, so --strip must too,
       or the two verbs diverge and --strip becomes a second route to the
       data loss the apply-side fix just closed. The engine's OWN harvested
       summary carries AUTO_SUM instead and is still stripped unconditionally
       (see run_doc_p3_strip_wrongsymbol, whose fixture was re-marked).
    2. The marked <returns> is REMOVED (UNCHANGED -- marked still means
       engine-owned for that tag, because the engine always has its own mined
       content to write there).
    3. The marked <param> SURVIVES completely untouched -- marker AND typed
       text both intact, byte-identical to the pre-strip line -- the one
       exception, matching `document --apply`'s own param-only preservation.
    4. The exact reported counts: 2 tags removed (summary + returns), 0
       blocks (no facts fence in this fixture).
    5. A second `--strip --apply` is a no-op (byte-identical, idempotent) --
       the surviving <param> line does not attract a THIRD strip attempt.

  Run from a NEUTRAL CWD (C:\TEMP), pwsh 7.
#>
[CmdletBinding()]
param([string]$Exe = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe")

$ErrorActionPreference = 'Continue'
function Check($n,$ok,$d=''){ Write-Host ("[{0}] {1} {2}" -f (@('FAIL','PASS')[[int]$ok]),$n,$d) -ForegroundColor (@('Red','Green')[[int]$ok]); if(-not $ok){$script:Failed=$true} }
$script:Failed = $false

$exePath = (Resolve-Path $Exe).Path
$fixture = (Resolve-Path (Join-Path $PSScriptRoot 'fixtures\docp3\strip_paramkeep.pas')).Path

$scratch = Join-Path C:\TEMP 'draglint_docp3stripparamkeep'
if (Test-Path $scratch) { Remove-Item $scratch -Recurse -Force }
New-Item -ItemType Directory -Path $scratch | Out-Null
$target = Join-Path $scratch 'strip_paramkeep.pas'
$db     = Join-Path $scratch 'stripparamkeep.sqlite'
Copy-Item $fixture $target -Force

Push-Location C:\TEMP
try {
  & $exePath index $scratch --db $db 2>$null | Out-Null
  Check 'index exits 0' ($LASTEXITCODE -eq 0)

  $dryRunOut = (& $exePath document --unit $target --db $db --strip 2>&1) -join "`n"
  Check 'dry-run --strip exits 0' ($LASTEXITCODE -eq 0)
  # v(SESSION 74): ONE tag, not two -- <returns> alone. The <summary> joined
  # <param> on the preserved side (see assertion 1), and the count moving is
  # the cheapest possible proof that it really did.
  Check '4. dry-run reports the exact counts (1 tag, 0 blocks)' `
    ($dryRunOut -match 'stripped:\s*1\s*tags?,\s*0\s*blocks') $dryRunOut

  & $exePath document --unit $target --db $db --strip --apply 2>$null | Out-Null
  Check 'strip --apply exits 0' ($LASTEXITCODE -eq 0)

  $lines = [IO.File]::ReadAllLines($target)
  # v(SESSION 74) -- REVERSED, deliberately. See the header. Asserting the
  # TEXT and not merely the tag, so a strip that deleted the developer's words
  # while leaving an empty <summary></summary> behind still fails.
  Check '1. marked <summary> SURVIVES with the developer''s typed text (D-4; apply and strip agree)' `
    (($lines -join "`n") -match '<summary>' -and ($lines -join "`n").Contains('A developer typed this summary after the marker.'))
  Check '2. marked <returns> is REMOVED' `
    (-not (($lines -join "`n") -match '<returns>'))
  Check '3. marked <param> SURVIVES completely untouched (marker AND typed text intact)' `
    (($lines | Where-Object { $_.Trim() -eq '/// <param name="AValue"><!-- drag-lint:auto -->A developer typed this param after the marker.</param>' }).Count -eq 1)

  # --- 5. Idempotency: a second strip --apply is a no-op ---
  $afterFirstStrip = [IO.File]::ReadAllBytes($target)
  & $exePath document --unit $target --db $db --strip --apply 2>$null | Out-Null
  $afterSecondStrip = [IO.File]::ReadAllBytes($target)
  Check '5. second strip --apply is a no-op (byte-identical)' `
    ([System.Linq.Enumerable]::SequenceEqual([byte[]]$afterFirstStrip,[byte[]]$afterSecondStrip))
} finally { Pop-Location }

if($script:Failed){ Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
