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
      2/3/4 (those need a facts-bearing symbol, which this fixture's trivial,
      caller-free routines never produce). Rules 2/3/4, the multi-line branch
      of rule 1, --qname --strip's region-scoping, and --strip + --stubs's
      exit 2 are covered by the sibling run_doc_p3_strip_static.ps1, which
      strips a fixture with every marker baked in by hand -- no `document`
      run at all.
    * Plain gains a brand-new managed comment -- but v(ADP3 T3) omit-when-empty
      means that comment is JUST a managed <returns> (Plain has a mined return
      case), NOT a <summary>/<param>/<returns> trio: Plain has no hand-written/
      harvested summary and no hand-written param description, so neither tag
      is emitted at all (a fresh comment never carries either skeleton).

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
# Review fix (Finding 4): a 3rd $d(etail) param, matching sibling runners
# (e.g. run_doc_returns.ps1) -- without it, a call site passing a 3rd arg
# (a diagnostic string) silently drops it into PowerShell's automatic $args,
# so a failing Check prints only the label and no diagnostic.
function Check($n,$ok,$d=''){ Write-Host ("[{0}] {1} {2}" -f (@('FAIL','PASS')[[int]$ok]),$n,$d) -ForegroundColor (@('Red','Green')[[int]$ok]); if(-not $ok){$script:Failed=$true} }
$script:Failed = $false

$exePath = (Resolve-Path $Exe).Path
$fixture = (Resolve-Path (Join-Path $PSScriptRoot 'fixtures\docp3\strip.pas')).Path

# Returns the contiguous run of ///-prefixed lines immediately above the FIRST
# line matching $declPattern. $null if the declaration is not found. Same
# scan-upward idiom run_doc_p3_provenance.ps1/run_doc_p3_emptytags.ps1 use --
# scoped to ONE declaration's own block so a check cannot cross into a
# DIFFERENT decl's doc comment earlier in the same file.
function Get-DocBlockAbove([string[]]$lines, [string]$declPattern) {
  $idx = -1
  for ($i = 0; $i -lt $lines.Count; $i++) { if ($lines[$i] -match $declPattern) { $idx = $i; break } }
  if ($idx -lt 0) { return $null }
  $blockLines = @()
  $j = $idx - 1
  while ($j -ge 0 -and $lines[$j].TrimStart() -match '^///') { $blockLines = ,($lines[$j]) + $blockLines; $j-- }
  return ($blockLines -join "`n")
}

$scratch = Join-Path C:\TEMP 'draglint_docp3strip'
if (Test-Path $scratch) { Remove-Item $scratch -Recurse -Force }
New-Item -ItemType Directory -Path $scratch | Out-Null
$target = Join-Path $scratch 'strip.pas'
$db     = Join-Path $scratch 'docp3strip.sqlite'
Copy-Item $fixture $target -Force

Push-Location C:\TEMP
try {
  $before = [IO.File]::ReadAllBytes($target)

  & $exePath index $scratch --db $db 2>&1 | Out-Null
  Check 'index exits 0' ($LASTEXITCODE -eq 0)

  # --stubs is required so Plain (no facts) is documented too -- see header.
  & $exePath document --unit $target --db $db --stubs --apply 2>&1 | Out-Null
  Check 'document --stubs --apply exits 0' ($LASTEXITCODE -eq 0)

  $afterApply = [IO.File]::ReadAllBytes($target)
  Check 'file differs from pre-apply snapshot' (-not [System.Linq.Enumerable]::SequenceEqual([byte[]]$before,[byte[]]$afterApply))

  $afterApplyText = [IO.File]::ReadAllText($target)
  Check 'Mixed gained a managed <returns> tag' `
    ($afterApplyText -match [regex]::Escape('<returns><!-- drag-lint:auto -->'))

  # v(ADP3 T3): Plain has no hand-written/harvested summary and no
  # hand-written param description, so its fresh comment is JUST the managed
  # <returns> (a mined return case) -- no <summary>/<param> skeleton at all.
  # Scoped to Plain's OWN doc block (Get-DocBlockAbove) so this cannot be
  # satisfied by Mixed's separate, EARLIER hand-written <summary>/<param>.
  $plainLinesAfterApply = [IO.File]::ReadAllLines($target)
  $plainBlock = Get-DocBlockAbove $plainLinesAfterApply '^function Plain\(AValue: Integer\): Integer;'
  Check 'Plain gained a fresh managed comment' ($null -ne $plainBlock) $plainBlock
  Check 'Plain gained a managed <returns> tag' `
    ($null -ne $plainBlock -and $plainBlock -match [regex]::Escape('<returns><!-- drag-lint:auto -->')) $plainBlock
  Check 'Plain gained NO <summary> tag (nothing to say)' `
    ($null -eq $plainBlock -or (-not ($plainBlock -match '<summary>'))) $plainBlock
  # v(PHASE A3, ruling D-3) reverses v(ADP3 T3) here: STRUCTURE ALWAYS, MEANING
  # ONLY WHERE THE SOURCE CARRIES IT. The old rule -- no <param> unless a human
  # wrote a description -- was itself the defect: doc-drift reported those tags as
  # missing while `document` refused to write them, so the two halves could never
  # converge. The tag is now emitted, engine-marked, with an EMPTY body.
  Check 'Plain gained an engine-marked <param name="AValue"> tag with an EMPTY body' `
    (($null -ne $plainBlock) -and ($plainBlock -match [regex]::Escape('<param name="AValue"><!-- drag-lint:auto --></param>'))) $plainBlock

  # --- dry-run --strip (no --apply), run against the STILL-documented file --
  # (before the real strip below) so there is engine content to report on.
  $dryRunOut = (& $exePath document --unit $target --db $db --strip 2>&1) -join "`n"
  $dryRunExit = $LASTEXITCODE
  Check 'dry-run --strip exits 0' ($dryRunExit -eq 0)
  $afterDryRun = [IO.File]::ReadAllBytes($target)
  Check 'dry-run --strip writes nothing (file unchanged)' `
    ([System.Linq.Enumerable]::SequenceEqual([byte[]]$afterApply,[byte[]]$afterDryRun))
  # Review fix (Finding 3): assert the EXACT counts, not just "some digits" --
  # the generic \d+ regex would also match the 'stripped: 0 tags, 0 blocks'
  # nothing-to-strip branch, so a regression that always reported zero would
  # still pass. v(ADP3 T3): Mixed's one managed <returns> + Plain's ONE
  # managed <returns> (its <summary>/<param> are never emitted -- omit-when-
  # empty, see the header) = 2 tags, 0 blocks (neither routine has a facts
  # fence -- see the header). This was 4 tags before T3 (Plain used to also
  # carry a marked-empty <summary> and <param>).
  Check 'dry-run --strip reports the exact tag/block counts on stdout' `
    ($dryRunOut -match 'stripped:\s*3\s*tags,\s*0\s*blocks') $dryRunOut

  # --- real strip --apply: round-trip back to the pre-apply snapshot ---
  & $exePath document --unit $target --db $db --strip --apply 2>&1 | Out-Null
  Check 'strip --apply exits 0' ($LASTEXITCODE -eq 0)

  $afterStrip = [IO.File]::ReadAllBytes($target)
  Check 'ROUND-TRIP: file byte-identical to pre-apply snapshot' `
    ([System.Linq.Enumerable]::SequenceEqual([byte[]]$before,[byte[]]$afterStrip))

  # --- second strip --apply is a no-op ---
  & $exePath document --unit $target --db $db --strip --apply 2>&1 | Out-Null
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
