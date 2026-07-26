<#
  run_doc_p3_strip.ps1 -- Auto-Document Phase 3, Task 2: `document --strip` --
  exact marker-keyed removal of engine output.

  Fixture fixtures\docp3\strip.pas:
    * Mixed(AValue): a HAND-WRITTEN <summary>/<param>/<remarks> comment (no
      <returns> tag yet), preceded by an ordinary '//' implementation-style
      comment that must survive untouched.
    * Plain(AValue): NO comment at all.

  Sequence: index -> `document --unit --stubs --apply` (--stubs is required
  here: the facts-only default would otherwise SKIP Plain entirely -- a fresh
  all-TODO create with no index-grounded facts -- leaving it undocumented and
  rule 5 [an emptied doc region collapses away completely] untested; Mixed is
  kept either way, since it already has a comment [daExtended]) -> `document
  --unit --strip --apply` -> byte-identical round-trip back to the pre-apply
  fixture.

  After the first --apply:
    * Mixed gains exactly one NEW marked tag: a managed <returns> (it is a
      function with no prior <returns>). Facts stay empty for both routines
      (trivial single-file arithmetic, no callers, no complexity) so NEITHER
      gets a <remarks> facts fence -- this fixture exercises rules 1 + 5, not
      2/3/4 (those need a facts-bearing symbol elsewhere; see the task
      report for why this exact fixture can't reach them).
    * Plain gains a brand-new, fully-managed comment (<summary>/<param>/
      <returns>, all AUTO_MARK-only, no facts).

  After `--strip --apply`:
    * Mixed's added <returns> tag is gone (rule 1); its hand-written
      <summary>/<param>/<remarks> and the preceding '//' comment are
      untouched.
    * Plain's ENTIRE fresh comment is gone (rule 5: dropping every managed
      tag empties the region, so the whole region -- not just its tags -- is
      dropped, leaving no stray blank line).
    * The file is byte-identical to the pre-apply snapshot.

  Then: a second `--strip --apply` is confirmed a no-op (byte-identical,
  exit 0), and a dry-run `--strip` (no --apply, run against the STILL-
  documented file, before the real strip above) is confirmed to (a) write
  nothing and (b) report the tag/block counts on stdout.

  Run from a NEUTRAL CWD (C:\TEMP), pwsh 7.
#>
[CmdletBinding()]
param([string]$Exe = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe")

$ErrorActionPreference = 'Continue'
function Check($n,$ok){ Write-Host ("[{0}] {1}" -f (@('FAIL','PASS')[[int]$ok]),$n) -ForegroundColor (@('Red','Green')[[int]$ok]); if(-not $ok){$script:Failed=$true} }
$script:Failed = $false

$exePath = (Resolve-Path $Exe).Path
$fixture = (Resolve-Path (Join-Path $PSScriptRoot 'fixtures\docp3\strip.pas')).Path

$scratch = Join-Path C:\TEMP 'draglint_docp3strip'
if (Test-Path $scratch) { Remove-Item $scratch -Recurse -Force }
New-Item -ItemType Directory -Path $scratch | Out-Null
$target = Join-Path $scratch 'strip.pas'
$db     = Join-Path $scratch 'docp3strip.sqlite'
Copy-Item $fixture $target -Force

Push-Location C:\TEMP
try {
  $before = [IO.File]::ReadAllBytes($target)

  & $exePath index $scratch --db $db 2>$null | Out-Null
  Check 'index exits 0' ($LASTEXITCODE -eq 0)

  # --stubs is required so Plain (no facts) is documented too -- see header.
  & $exePath document --unit $target --db $db --stubs --apply 2>$null | Out-Null
  Check 'document --stubs --apply exits 0' ($LASTEXITCODE -eq 0)

  $afterApply = [IO.File]::ReadAllBytes($target)
  Check 'file differs from pre-apply snapshot' (-not [System.Linq.Enumerable]::SequenceEqual([byte[]]$before,[byte[]]$afterApply))

  $afterApplyText = [IO.File]::ReadAllText($target)
  Check 'Mixed gained a managed <returns> tag' `
    ($afterApplyText -match [regex]::Escape('<returns><!-- drag-lint:auto -->'))
  Check 'Plain gained a fresh managed comment' `
    ($afterApplyText -match '(?s)<summary><!-- drag-lint:auto --></summary>\s*\r?\n\s*///\s*<param name="AValue"><!-- drag-lint:auto --></param>\s*\r?\n\s*///\s*<returns><!-- drag-lint:auto -->.*?</returns>\s*\r?\n\s*function Plain')

  # --- dry-run --strip (no --apply), run against the STILL-documented file --
  # (before the real strip below) so there is engine content to report on.
  $dryRunOut = (& $exePath document --unit $target --db $db --strip 2>&1) -join "`n"
  $dryRunExit = $LASTEXITCODE
  Check 'dry-run --strip exits 0' ($dryRunExit -eq 0)
  $afterDryRun = [IO.File]::ReadAllBytes($target)
  Check 'dry-run --strip writes nothing (file unchanged)' `
    ([System.Linq.Enumerable]::SequenceEqual([byte[]]$afterApply,[byte[]]$afterDryRun))
  Check 'dry-run --strip reports tag/block counts on stdout' `
    ($dryRunOut -match 'stripped:\s*\d+\s*tags?,\s*\d+\s*blocks?') $dryRunOut

  # --- real strip --apply: round-trip back to the pre-apply snapshot ---
  & $exePath document --unit $target --db $db --strip --apply 2>$null | Out-Null
  Check 'strip --apply exits 0' ($LASTEXITCODE -eq 0)

  $afterStrip = [IO.File]::ReadAllBytes($target)
  Check 'ROUND-TRIP: file byte-identical to pre-apply snapshot' `
    ([System.Linq.Enumerable]::SequenceEqual([byte[]]$before,[byte[]]$afterStrip))

  # --- second strip --apply is a no-op ---
  & $exePath document --unit $target --db $db --strip --apply 2>$null | Out-Null
  Check 'second strip --apply exits 0' ($LASTEXITCODE -eq 0)
  $afterStrip2 = [IO.File]::ReadAllBytes($target)
  Check 'second strip --apply is a no-op (byte-identical)' `
    ([System.Linq.Enumerable]::SequenceEqual([byte[]]$afterStrip,[byte[]]$afterStrip2))

  # --- survivors: ordinary comment + both hand-written tags present ---
  $finalText = [IO.File]::ReadAllText($target)
  Check 'ordinary // comment survives' `
    ($finalText.Contains('// An ordinary implementation-style comment that must survive untouched.'))
  Check 'hand-written <summary> survives' `
    ($finalText.Contains('/// <summary>Hand-written summary; must survive.</summary>'))
  Check 'hand-written <param> survives' `
    ($finalText.Contains('/// <param name="AValue">Hand-written param desc; must survive.</param>'))
  Check 'hand-written <remarks> survives (single-line, untouched)' `
    ($finalText.Contains('/// <remarks>Hand-written remarks prose; must survive.</remarks>'))
  Check 'no drag-lint:auto marker survives anywhere' `
    (-not ($finalText -match 'drag-lint:auto'))
} finally { Pop-Location }

if($script:Failed){ Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
