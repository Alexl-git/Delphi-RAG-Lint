<#
  run_doc_p3_markededit.ps1 -- Auto-Document Phase 3, Task 3 (review follow-up,
  Finding 1): a MARKED tag carrying real post-marker content is preserved
  (marker stripped), never dropped along with its text.

  Live scenario this protects against: a prior rollout left N
  <summary><!-- drag-lint:auto --></summary> stubs on disk. A developer sees a
  blank tooltip, types a description INSIDE the existing tag without deleting
  the HTML comment, and commits. The next `document --apply` must NOT delete
  the tag and the sentence -- pre-fix, ClassifyTagAction keyed purely on the
  marker being PRESENT (regardless of what followed it), so a marked
  <summary>/<param> fell to the always-empty-today harvest arm and was
  dropped with its text; a marked <returns> was treated the same way even
  though the engine's OWN live Observed-suffix refill is *also* marked+
  content, which (if not corrected) makes the fix indistinguishable from the
  bug it just fixed on the very next run.

  Fixture fixtures\docp3\markededit.pas:
    * Foo(AValue: Integer): Integer -- ALREADY carries a marked <summary>,
      <param name="AValue">, and <returns>, each with REAL text typed after
      the marker (simulating exactly the developer scenario above).
    * Bar(AValue: Integer): Integer -- UNDOCUMENTED. Used to prove the
      DISTINCT nuance: the engine's own fresh <returns> refill (marker +
      mined 'Observed: ...' suffix) must NOT be misclassified as "a human
      edited this" on the very NEXT run just because it is marked+content --
      it must stay recognized as engine-owned (matches a fresh computation)
      so idempotency holds and the marker survives across repair passes.

  Drives `index` -> `document --unit --apply` and asserts:
    1. Foo's <summary> survives with its typed sentence, UNMARKED (marker
       stripped) -- not dropped.
    2. Foo's <param name="AValue"> survives with its typed sentence,
       UNMARKED -- not dropped.
    3. Foo's <returns> survives with its typed sentence, UNMARKED -- not
       dropped; the mined return case surfaces separately as a 'Returns:'
       fact line (not lost, not duplicated into the tag itself).
    4. Bar gains a FRESH, MARKED <returns> (engine's own mined-Observed
       refill) -- the normal, unaffected omit-when-empty/refill behavior.
    5. Idempotency: reindex + a second --apply is byte-identical for BOTH
       symbols. In particular, Bar's <returns> marker MUST SURVIVE (not be
       stripped) -- proving the engine's own current output is recognized
       as engine-owned across the fresh-to-repair transition, not
       misclassified as a human edit.

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
  return ($blockLines -join "`n")
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

  Check '1. Foo <summary> survives with its typed text, unmarked' `
    (($lines | Where-Object { $_.Trim() -eq '/// <summary>A developer typed this after the marker.</summary>' }).Count -eq 1)
  Check '2. Foo <param name="AValue"> survives with its typed text, unmarked' `
    (($lines | Where-Object { $_.Trim() -eq '/// <param name="AValue">Also typed after the marker.</param>' }).Count -eq 1)
  Check '3. Foo <returns> survives with its typed text, unmarked' `
    (($lines | Where-Object { $_.Trim() -eq '/// <returns>Also typed here after the marker.</returns>' }).Count -eq 1)
  Check '3. Foo <returns> mined case surfaces as a separate Returns: fact line' `
    ($null -ne $fooBlock -and $fooBlock -match 'Returns:\s*AValue\b')
  Check 'Foo doc block carries NO marker anywhere (fully de-owned by the edit)' `
    ($null -eq $fooBlock -or (-not ($fooBlock -match [regex]::Escape($MARK))))

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
