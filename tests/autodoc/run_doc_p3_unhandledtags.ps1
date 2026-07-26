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

  This is NOT a licence to fix the underlying tag-dropping (that WAS a
  separately-tracked, larger task -- Task 3b, since fixed; see
  run_doc_p3_preserve_tags.ps1) -- it is a guard that makes the DELETE
  branch conservative. Round 2 (point 3) replaced a field-by-field
  TParsedDoc whitelist (which is only correct by ENUMERATION -- a tag type
  the parser does not even model, like <value>, was still silently
  destroyed) with RegionFullyEngineOwned: delete only when EVERY /// line in
  the raw existing region carries AUTO_MARK or lies within an AUTO_BEGIN..
  AUTO_END fence. Correct by construction, no future maintenance needed as
  new tag types appear. Task 3b (tag round-tripping) did NOT touch this
  guard (per its own brief's explicit instruction: it stays defence-in-depth
  for a future, still-unmodeled tag type) -- it changed what MergeComment's
  repair path itself can say, which changes whether a given case still
  REACHES the guard's Merged='' branch at all. See the per-symbol notes
  below for which of the three that reclassifies.

  Fixture fixtures\docp3\unhandledtags.pas (fixture ITSELF unchanged by
  Task 3b -- only what MergeComment does with it changed):
    * HasException -- a hand-written comment consisting of ONLY <exception>.
      POST-Task-3b: Exceptions is now preserved verbatim by the repair path,
      so Merged is no longer '' -- this case no longer reaches the delete
      guard at all (it did not need it: the repaired Merged is byte-
      identical to the original hand-written line, so the whole-unit apply
      still reports this decl as UNCHANGED). Retained here as the REGRESSION
      case: proves the guard change did not somehow reintroduce destruction
      once the case it used to protect no longer needs protecting.
    * HasSinceSeeAlsoExampleDeprecated -- <since> + <seealso> + <example> +
      <deprecated/> + an empty <remarks></remarks>, combined. POST-Task-3b:
      all four are now preserved (in Task 3b's fixed emission order:
      <deprecated/> -> <exception>s -> <example> -> <seealso>s -> <since> --
      no <exception> here, so <deprecated/>, <example>, <seealso>, <since>),
      so Merged is no longer '' either -- THIS case also no longer reaches
      the delete guard's Merged='' branch; it now goes through the ordinary
      "existing comment differs from Merged" repair (a genuine, wanted
      rewrite: edits=2, delete+insert), not the guard's territory at all.
      The forcing empty <remarks></remarks> carried no information of its
      own (it existed ONLY to make this comment dispatch as an XML doc, a
      workaround for the OTHER pre-existing gap the note below still
      describes) and is correctly DROPPED now that there is real content to
      write instead -- an empty <remarks></remarks> was never preserved
      through a repair pass for any OTHER reason either (same omit-when-
      empty rule <summary>/<returns> already followed). NOTE: Task 3b ALSO
      fixed the separate TDocCommentParser.Dispatch gap this fixture's own
      comment used to describe as unfixed (<since>/<seealso>/<deprecated>
      now sniff correctly as XML on their own) -- the empty <remarks></
      remarks> is no longer NEEDED to force correct dispatch, but is left in
      the fixture unchanged since removing it would not change what this
      test demonstrates and the brief's Step 5 file list does not include
      this fixture.
    * HasValueTag -- <value> (a tag type the parser doesn't model AT ALL,
      still true post-Task-3b -- explicitly out of that task's scope)
      paired with a marked, EMPTY <returns>. UNCHANGED by Task 3b: <value>
      has no TParsedDoc field for Task 3b's preserve loop to read, so Merged
      is STILL '' for this decl, and this remains the guard's own load-
      bearing case -- exactly the scenario a field whitelist could never
      protect, no matter how many fields it enumerated.

  Drives `index` -> `document --unit --stubs --apply` and asserts:
    1. The whole-unit apply reports edits=2 (HasSinceSeeAlsoExampleDeprecated
       is genuinely repaired -- one delete+insert pair; HasException and
       HasValueTag contribute zero edits each).
    2. HasException's OWN doc-comment span is byte-identical to before the
       apply (Task 3b's preserve loop makes its Merged reproduce the
       original line exactly, so this decl is UNCHANGED, not merely
       "still guarded").
    3. HasValueTag's OWN doc-comment span is byte-identical to before the
       apply (Task 3b does not touch <value>; this decl still reaches
       Merged='' and is still protected by RegionFullyEngineOwned, unchanged
       from before this task).
    4. Each of the four tags on HasSinceSeeAlsoExampleDeprecated survives,
       verbatim, in Task 3b's fixed emission order; the now-empty, now-
       redundant <remarks></remarks> wrapper is correctly gone.
    5. Each hand-written tag on HasException/HasValueTag is still present,
       verbatim (same assertions the original version of this test made).
    6. Idempotency: reindex + a second `--stubs --apply` is byte-identical
       (the newly-repaired HasSinceSeeAlsoExampleDeprecated is now a stable
       fixed point, not a decl that keeps getting rewritten every cycle).

  Run from a NEUTRAL CWD (C:\TEMP), pwsh 7.
#>
[CmdletBinding()]
param([string]$Exe = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe")

$ErrorActionPreference = 'Continue'
function Check($n,$ok,$d=''){ Write-Host ("[{0}] {1} {2}" -f (@('FAIL','PASS')[[int]$ok]),$n,$d) -ForegroundColor (@('Red','Green')[[int]$ok]); if(-not $ok){$script:Failed=$true} }
$script:Failed = $false

$exePath = (Resolve-Path $Exe).Path
$fixture = (Resolve-Path (Join-Path $PSScriptRoot 'fixtures\docp3\unhandledtags.pas')).Path

# Returns the contiguous run of ///-prefixed lines immediately above the FIRST
# line matching $declPattern, joined with "`n". $null if not found. Same
# scan-upward idiom run_doc_p3_preserve_tags.ps1/run_doc_seealso.ps1 use --
# scoped to ONE declaration's own block so a check cannot bleed into a
# DIFFERENT decl's doc comment elsewhere in the file.
function Get-DocBlockAbove([string[]]$lines, [string]$declPattern) {
  $idx = -1
  for ($i = 0; $i -lt $lines.Count; $i++) { if ($lines[$i] -match $declPattern) { $idx = $i; break } }
  if ($idx -lt 0) { return $null }
  $blockLines = New-Object System.Collections.Generic.List[string]
  for ($i = $idx - 1; $i -ge 0; $i--) {
    if ($lines[$i] -notmatch '^\s*///') { break }
    $blockLines.Insert(0, $lines[$i])
  }
  return [string]::Join("`n", $blockLines.ToArray())
}

$scratch = Join-Path C:\TEMP 'draglint_docp3unhandledtags'
if (Test-Path $scratch) { Remove-Item $scratch -Recurse -Force }
New-Item -ItemType Directory -Path $scratch | Out-Null
$target = Join-Path $scratch 'unhandledtags.pas'
$db     = Join-Path $scratch 'docp3unhandledtags.sqlite'
Copy-Item $fixture $target -Force

Push-Location C:\TEMP
try {
  $beforeLines = [IO.File]::ReadAllLines($target)
  $exceptionBlockBefore = Get-DocBlockAbove $beforeLines '^procedure HasException;'
  $valueTagBlockBefore  = Get-DocBlockAbove $beforeLines '^function HasValueTag: Integer;'

  & $exePath index $scratch --db $db 2>$null | Out-Null
  Check 'index exits 0' ($LASTEXITCODE -eq 0)

  $applyJson = (& $exePath document --unit $target --db $db --stubs --apply --json 2>$null) -join "`n"
  Check 'document --unit --stubs --apply exits 0' ($LASTEXITCODE -eq 0)
  # Task 3b: HasSinceSeeAlsoExampleDeprecated's four tags are now preserved
  # (Merged is no longer '' for it), so it is genuinely repaired -- ONE
  # delete+insert pair (edits=2). HasException/HasValueTag each contribute
  # zero edits (see assertions 2/3 below), so 2 is the total for the unit.
  Check '1. apply reports edits=2 for the whole unit (ONLY HasSinceSeeAlsoExampleDeprecated is repaired)' `
    ($applyJson -match '"edits":2') $applyJson

  $lines = [IO.File]::ReadAllLines($target)

  # 2. HasException: Task 3b's <exception> preserve loop makes Merged
  # reproduce this hand-written line exactly, so the decl is genuinely
  # UNCHANGED (not merely "still guarded" -- Merged is no longer '' for it,
  # so RegionFullyEngineOwned is not even consulted for this decl anymore).
  $exceptionBlockAfter = Get-DocBlockAbove $lines '^procedure HasException;'
  Check '2. HasException''s doc-comment span is byte-identical to before the apply' `
    ($null -ne $exceptionBlockBefore -and $null -ne $exceptionBlockAfter -and $exceptionBlockAfter -ceq $exceptionBlockBefore)

  # 3. HasValueTag: <value> has no TParsedDoc field at all, so Task 3b's
  # preserve loop has nothing to read for it -- Merged is STILL '' and this
  # decl is STILL protected by RegionFullyEngineOwned, unchanged from before
  # this task (the genuinely load-bearing case for that guard, going forward).
  $valueTagBlockAfter = Get-DocBlockAbove $lines '^function HasValueTag: Integer;'
  Check '3. HasValueTag''s doc-comment span is byte-identical to before the apply (guard still protects the unmodeled tag)' `
    ($null -ne $valueTagBlockBefore -and $null -ne $valueTagBlockAfter -and $valueTagBlockAfter -ceq $valueTagBlockBefore)

  # 4. HasSinceSeeAlsoExampleDeprecated: all four tags survive, verbatim, in
  # Task 3b's fixed emission order (no <exception> on this decl, so:
  # <deprecated/> -> <example> -> <seealso>s -> <since>); the empty, now-
  # redundant <remarks></remarks> wrapper is correctly gone (omit-when-empty,
  # same rule <summary>/<returns> already followed -- it carried nothing).
  $sinceSeeAlsoBlock = Get-DocBlockAbove $lines '^procedure HasSinceSeeAlsoExampleDeprecated;'
  Check '4. HasSinceSeeAlsoExampleDeprecated decl + doc-comment found' ($null -ne $sinceSeeAlsoBlock -and $sinceSeeAlsoBlock -ne '')
  Check '4. <deprecated/> survives verbatim' ($sinceSeeAlsoBlock -match [regex]::Escape('<deprecated/>'))
  Check '4. <example> survives verbatim'     ($sinceSeeAlsoBlock -match [regex]::Escape('<example>Example text.</example>'))
  Check '4. <seealso> survives verbatim'     ($sinceSeeAlsoBlock -match [regex]::Escape('<seealso cref="Other.Thing"/>'))
  Check '4. <since> survives verbatim'       ($sinceSeeAlsoBlock -match [regex]::Escape('<since>2020-01-01</since>'))
  Check '4. fixed emission order: deprecated -> example -> seealso -> since' `
    ($sinceSeeAlsoBlock -match '(?s)<deprecated/>.*?<example>.*?<seealso.*?<since>')
  Check '4. the now-empty, now-redundant <remarks></remarks> is correctly gone (omit-when-empty)' `
    (-not ($sinceSeeAlsoBlock -match '<remarks>'))

  # 5. Original per-tag survival assertions (HasException/HasValueTag), same
  # checks the pre-Task-3b version of this test made.
  $text = [IO.File]::ReadAllText($target)
  Check '5. hand-written <exception> survives verbatim'  ($text.Contains('/// <exception cref="EFoo">Boom.</exception>'))
  Check '5. hand-written <value> survives verbatim (unmodeled tag type)' ($text.Contains('/// <value>Hand-written; must survive.</value>'))
  Check '5. the paired marked-empty <returns> survives too (untouched, not just the value tag)' ($text.Contains('/// <returns><!-- drag-lint:auto --></returns>'))

  # 6. Idempotency: reindex + a second --stubs --apply is byte-identical --
  # the newly-repaired HasSinceSeeAlsoExampleDeprecated is now a stable
  # fixed point, not a decl that keeps getting rewritten every cycle.
  $afterApply1 = [IO.File]::ReadAllBytes($target)
  & $exePath index $scratch --db $db 2>$null | Out-Null
  & $exePath document --unit $target --db $db --stubs --apply --json 2>$null | Out-Null
  $afterApply2 = [IO.File]::ReadAllBytes($target)
  Check '6. idempotent: file byte-identical on a 2nd --stubs --apply cycle' `
    ([System.Linq.Enumerable]::SequenceEqual([byte[]]$afterApply1,[byte[]]$afterApply2))
} finally { Pop-Location }

if($script:Failed){ Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
