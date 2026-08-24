<#
  run_doc_p3_markededit.ps1 -- Auto-Document Phase 3, Task 3 (review follow-up,
  Finding 1 -- REVISED after the coordinator's own reversal, round 2):
  a marked tag carrying real post-marker content is preserved (marker
  stripped) for <param> ONLY. <summary>/<returns> revert to the ORIGINAL
  Task 3 rule: marked means engine-owned, full stop, regardless of what
  follows the marker.

  History: an earlier round of this fix tried to preserve marked+content for
  ALL THREE tags via an exact-string compare against freshly generated text
  (AFreshFill). The coordinator reversed that ruling on further review: the
  PLAN had already adjudicated <summary>/<returns> deliberately -- a human
  edit inside the markers is NOT separable from "the source comment
  changed" by the plan's own string comparison, so BOTH refresh, and a
  human takes ownership only by REMOVING the marker (Task 9's drift report
  is the documented, future safeguard). The exact-string compare was ALSO
  independently wrong: it is content-keyed ownership by the back door, more
  brittle than the StartsText('Observed:') sniff Task 1 deleted (whitespace
  normalization and legitimate code drift both defeat exact equality, where
  a prefix match would have survived both) -- reproduced and regression-
  tested separately in run_doc_p3_idempotent_edgecases.ps1.

  <param> remains the ONE exception: harvesting is explicitly out of scope
  for it forever, so "engine-owned, dropped" there is PERMANENT,
  unrecoverable loss with no refresh mechanism and no drift report ever able
  to surface it -- a decision the plan never made for summary/returns.

  Fixture fixtures\docp3\markededit.pas:
    * Foo(AValue: Integer): Integer -- ALREADY carries a marked <summary>,
      <param name="AValue">, and <returns>, each with REAL text typed after
      the marker (simulating a developer typing into an existing stub
      without removing the HTML comment).
    * Bar(AValue: Integer): Integer -- UNDOCUMENTED. Used to prove the
      DISTINCT nuance: the engine's own fresh <returns> refill (marker +
      mined 'Observed: ...' suffix) must NOT be misclassified as "a human
      edited this" on the very NEXT run just because it is marked+content --
      it must stay recognized as engine-owned so the marker survives across
      a fresh-to-repair transition, and idempotency holds.

  Drives `index` -> `document --unit --apply` and asserts:
    1. Foo's <summary> is GONE entirely -- marked, engine-owned, nothing
       harvested to refill it (v(ADP3 T3) omit-when-empty); the human's
       typed sentence is NOT preserved (this is the plan's own recorded,
       deliberate deviation, not a bug).
    2. Foo's <param name="AValue"> SURVIVES with its typed sentence,
       UNMARKED (marker stripped) -- the one narrow exception.
    3. Foo's <returns> is REGENERATED to the engine's own mined Observed
       case, marked -- the human's typed sentence is discarded (same
       deliberate deviation as summary); no separate 'Returns:' fact line
       (the tag itself carries the mined content, same as any other
       engine-owned/refilled returns).
    4. Bar gains a FRESH, MARKED <returns> (engine's own mined-Observed
       refill) -- the normal, unaffected omit-when-empty/refill behavior.
    5. Idempotency: reindex + a second --apply is byte-identical for BOTH
       symbols. In particular, Bar's <returns> marker MUST SURVIVE (not be
       stripped) -- proving the engine's own current output stays
       recognized as engine-owned across the fresh-to-repair transition.

  Run from a NEUTRAL CWD (C:\TEMP), pwsh 7.
#>
[CmdletBinding()]
param([string]$Exe = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe")

$ErrorActionPreference = 'Continue'
function Check($n,$ok,$d=''){ Write-Host ("[{0}] {1} {2}" -f (@('FAIL','PASS')[[int]$ok]),$n,$d) -ForegroundColor (@('Red','Green')[[int]$ok]); if(-not $ok){$script:Failed=$true} }
$script:Failed = $false

$exePath = (Resolve-Path $Exe).Path
$fixture = (Resolve-Path (Join-Path $PSScriptRoot 'fixtures\docp3\markededit.pas')).Path

# Returns the contiguous run of ///-prefixed lines immediately above the FIRST
# line matching $declPattern. $null if the declaration is not found. Same
# scan-upward idiom the sibling p3 runners use.
function Get-DocBlockAbove([string[]]$lines, [string]$declPattern) {
  $idx = -1
  for ($i = 0; $i -lt $lines.Count; $i++) { if ($lines[$i] -match $declPattern) { $idx = $i; break } }
  if ($idx -lt 0) { return $null }
  $blockLines = @()
  $j = $idx - 1
  while ($j -ge 0 -and $lines[$j].TrimStart() -match '^///') { $blockLines = ,($lines[$j]) + $blockLines; $j-- }
  return (($blockLines -join "`n") -replace '</?para>', '')
}

$MARK = '<!-- drag-lint:auto -->'

$scratch = Join-Path C:\TEMP 'draglint_docp3markededit'
if (Test-Path $scratch) { Remove-Item $scratch -Recurse -Force }
New-Item -ItemType Directory -Path $scratch | Out-Null
$target = Join-Path $scratch 'markededit.pas'
$db     = Join-Path $scratch 'docp3markededit.sqlite'
Copy-Item $fixture $target -Force

Push-Location C:\TEMP
try {
  & $exePath index $scratch --db $db 2>$null | Out-Null
  Check 'index exits 0' ($LASTEXITCODE -eq 0)

  # --stubs is required so Bar (a fresh create whose only content is a
  # <returns> tag, with no facts fence) is kept -- the facts-only default
  # would otherwise skip it, same as run_doc_p3_strip.ps1's Plain.
  & $exePath document --unit $target --db $db --stubs --apply 2>$null | Out-Null
  Check 'document --unit --apply #1 exits 0' ($LASTEXITCODE -eq 0)

  $lines = [IO.File]::ReadAllLines($target)
  $fooBlock = Get-DocBlockAbove $lines '^function Foo\(AValue: Integer\): Integer;'
  Check 'Foo decl found' ($null -ne $fooBlock)

  Check '1. Foo <summary> is GONE (marked = engine-owned regardless of content; nothing harvested)' `
    ($null -eq $fooBlock -or (-not ($fooBlock -match '<summary>')))
  Check "1. Foo's typed summary sentence does NOT survive anywhere (deliberate, plan-sanctioned loss)" `
    (-not ($lines -join "`n").Contains('A developer typed this after the marker.'))

  Check '2. Foo <param name="AValue"> SURVIVES with its typed text, unmarked (the one exception)' `
    (($lines | Where-Object { $_.Trim() -eq '/// <param name="AValue">Also typed after the marker.</param>' }).Count -eq 1)

  Check '3. Foo <returns> is REGENERATED to the mined Observed case, marked' `
    ($null -ne $fooBlock -and $fooBlock -match [regex]::Escape('<returns>' + $MARK) + '(?:[^<]*-- )?Observed:\s*AValue\.')
  Check "3. Foo's typed returns sentence does NOT survive (deliberate, plan-sanctioned loss)" `
    (-not ($lines -join "`n").Contains('Also typed here after the marker.'))
  Check '3. no separate Returns: fact line for Foo (mined content is IN the regenerated tag, not duplicated)' `
    ($null -eq $fooBlock -or (-not ($fooBlock -match 'Returns:\s*AValue\b')))

  $barBlock = Get-DocBlockAbove $lines '^function Bar\(AValue: Integer\): Integer;'
  Check 'Bar decl found' ($null -ne $barBlock)
  Check '4. Bar gained a fresh MARKED <returns> (mined Observed refill)' `
    ($null -ne $barBlock -and $barBlock -match [regex]::Escape('<returns>' + $MARK) -and $barBlock -match 'Observed:\s*AValue\.')

  # --- 5. Idempotency: reindex + 2nd apply -> byte-identical; Bar's marker survives ---
  $before = [IO.File]::ReadAllBytes($target)
  & $exePath index $scratch --db $db 2>$null | Out-Null
  # --stubs is required so Bar (a fresh create whose only content is a
  # <returns> tag, with no facts fence) is kept -- the facts-only default
  # would otherwise skip it, same as run_doc_p3_strip.ps1's Plain.
  & $exePath document --unit $target --db $db --stubs --apply 2>$null | Out-Null
  $after = [IO.File]::ReadAllBytes($target)
  Check '5. idempotent: file byte-identical after reindex + 2nd apply' `
    ([System.Linq.Enumerable]::SequenceEqual([byte[]]$before,[byte[]]$after))

  $linesAfter = [IO.File]::ReadAllLines($target)
  $barBlockAfter = Get-DocBlockAbove $linesAfter '^function Bar\(AValue: Integer\): Integer;'
  Check '5. Bar''s <returns> marker SURVIVES the repair pass (still engine-owned, not misclassified as hand-edited)' `
    ($null -ne $barBlockAfter -and $barBlockAfter -match [regex]::Escape('<returns>' + $MARK))
} finally { Pop-Location }

if($script:Failed){ Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
