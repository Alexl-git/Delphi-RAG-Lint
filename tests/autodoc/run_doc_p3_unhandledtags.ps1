<#
  run_doc_p3_unhandledtags.ps1 -- Auto-Document Phase 3, Task 3 (review
  follow-up, Finding 2 -- REVISED in review round 2, point 3/point 5): the
  empty-merge delete branch must NOT delete a hand-written comment that
  carries a tag type MergeComment cannot re-emit.

  Background (pre-existing, unrelated to Task 3 -- see the Task 3 report's
  Concern 2 for the full investigation): MergeComment has never round-
  tripped <exception>/<example>/<since>/<seealso>/the doc's own
  <deprecated/> tag, and it has NO field at all for a tag type like <value>.
  Before Task 3's empty-merge guard existed, a repair pass on a comment
  consisting ONLY of one of these (no summary/param/returns, no facts)
  would REPLACE it with an empty/near-empty stub -- visibly wrong, but the
  source lines survived. Task 3's delete branch raised the blast radius:
  for exactly this shape, Merged comes out '' (nothing MergeComment
  understands to say) and an unguarded delete branch removed the WHOLE
  region outright -- hand-written source lines gone, not just replaced.

  This is NOT a licence to fix the underlying tag-dropping (that is a
  separately-tracked, larger task) -- it is a guard that makes the DELETE
  branch conservative. Round 2 (point 3) replaced a field-by-field
  TParsedDoc whitelist (which is only correct by ENUMERATION -- a tag type
  the parser does not even model, like <value>, was still silently
  destroyed) with RegionFullyEngineOwned: delete only when EVERY /// line in
  the raw existing region carries AUTO_MARK or lies within an AUTO_BEGIN..
  AUTO_END fence. Correct by construction, no future maintenance needed as
  new tag types appear.

  Fixture fixtures\docp3\unhandledtags.pas:
    * HasException -- a hand-written comment consisting of ONLY <exception>
      (Exceptions IS in TParsedDoc.HasContent's OR-chain, so this case
      genuinely reaches the delete guard on its own).
    * HasSinceSeeAlsoExampleDeprecated -- <since> + <seealso> + <example> +
      <deprecated/> + an empty <remarks></remarks>, combined -- see the
      fixture's own comment for why: SinceText/SeeAlso/ExampleText are ALL
      absent from HasContent's OR-chain (round 2, point 5's vacuous-test
      finding: a BARE <example>-only case never even reached the delete
      guard's own outer precondition, so it "passed" regardless of whether
      the guard logic was correct). Pairing with <deprecated/> (which DOES
      set HasContent) is what makes this case genuinely load-bearing; the
      empty <remarks></remarks> additionally forces correct XML dispatch for
      <since>/<seealso> specifically (a SEPARATE, unfixed
      TDocCommentParser.Dispatch gap, not fixed here).
    * HasValueTag -- <value> (a tag type the parser doesn't model AT ALL)
      paired with a marked, EMPTY <returns> (correctly dispatched via
      ParseXmlDoc, sets HasContent=True, then drops itself since it is
      engine-owned and empty) -- exactly the scenario a field whitelist
      could never protect, no matter how many fields it enumerated.
  Nothing else for MergeComment to preserve or regenerate in any of the
  three, so Merged comes out '' for every one of them.

  Drives `index` -> `document --unit --apply` and asserts:
    1. The file is BYTE-IDENTICAL to the pre-apply fixture (--json reports
       edits=0 for the whole unit) -- none of the three comments is
       deleted, replaced, or otherwise touched.
    2. Each hand-written tag is still present, verbatim.
    3. Each case is LOAD-BEARING: temporarily disabling the guard (verified
       by hand during development, see the fix report) reproduces RED for
       every one of these three cases, not just HasException -- closing the
       vacuous-test gap round 2 found.

  Run from a NEUTRAL CWD (C:\TEMP), pwsh 7.
#>
[CmdletBinding()]
param([string]$Exe = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe")

$ErrorActionPreference = 'Continue'
function Check($n,$ok,$d=''){ Write-Host ("[{0}] {1} {2}" -f (@('FAIL','PASS')[[int]$ok]),$n,$d) -ForegroundColor (@('Red','Green')[[int]$ok]); if(-not $ok){$script:Failed=$true} }
$script:Failed = $false

$exePath = (Resolve-Path $Exe).Path
$fixture = (Resolve-Path (Join-Path $PSScriptRoot 'fixtures\docp3\unhandledtags.pas')).Path

$scratch = Join-Path C:\TEMP 'draglint_docp3unhandledtags'
if (Test-Path $scratch) { Remove-Item $scratch -Recurse -Force }
New-Item -ItemType Directory -Path $scratch | Out-Null
$target = Join-Path $scratch 'unhandledtags.pas'
$db     = Join-Path $scratch 'docp3unhandledtags.sqlite'
Copy-Item $fixture $target -Force

Push-Location C:\TEMP
try {
  $before = [IO.File]::ReadAllBytes($target)

  & $exePath index $scratch --db $db 2>$null | Out-Null
  Check 'index exits 0' ($LASTEXITCODE -eq 0)

  $applyJson = (& $exePath document --unit $target --db $db --stubs --apply --json 2>$null) -join "`n"
  Check 'document --unit --stubs --apply exits 0' ($LASTEXITCODE -eq 0)
  Check '1. apply reports zero edits for the whole unit' ($applyJson -match '"edits":0') $applyJson

  $after = [IO.File]::ReadAllBytes($target)
  Check '1. file is byte-identical to the pre-apply fixture (nothing deleted/replaced)' `
    ([System.Linq.Enumerable]::SequenceEqual([byte[]]$before,[byte[]]$after))

  $text = [IO.File]::ReadAllText($target)
  Check '2. hand-written <exception> survives verbatim'  ($text.Contains('/// <exception cref="EFoo">Boom.</exception>'))
  Check '2. hand-written <since> survives verbatim'       ($text.Contains('/// <since>2020-01-01</since>'))
  Check '2. hand-written <seealso> survives verbatim'     ($text.Contains('/// <seealso cref="Other.Thing"/>'))
  Check '2. hand-written <example> survives verbatim'    ($text.Contains('/// <example>Example text.</example>'))
  Check '2. hand-written <deprecated/> survives verbatim' ($text.Contains('/// <deprecated/>'))
  Check '2. the forcing-dispatch <remarks></remarks> survives verbatim too' ($text.Contains('/// <remarks></remarks>'))
  Check '2. hand-written <value> survives verbatim (unmodeled tag type)' ($text.Contains('/// <value>Hand-written; must survive.</value>'))
  Check '2. the paired marked-empty <returns> survives too (untouched, not just the value tag)' ($text.Contains('/// <returns><!-- drag-lint:auto --></returns>'))
} finally { Pop-Location }

if($script:Failed){ Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
