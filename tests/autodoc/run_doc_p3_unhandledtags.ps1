<#
  run_doc_p3_unhandledtags.ps1 -- Auto-Document Phase 3, Task 3 (review
  follow-up, Finding 2): the empty-merge delete branch must NOT delete a
  hand-written comment that carries a tag type MergeComment cannot re-emit.

  Background (pre-existing, unrelated to Task 3 -- see the Task 3 report's
  Concern 2 for the full investigation): MergeComment has never round-
  tripped <exception>/<example>/<since>/<seealso>/the doc's own
  <deprecated/> tag. Before Task 3's empty-merge guard existed, a repair
  pass on a comment consisting ONLY of one of these (no summary/param/
  returns, no facts) would REPLACE it with an empty/near-empty stub --
  visibly wrong, but the source lines survived. Task 3's delete branch
  raised the blast radius: for exactly this shape, Merged comes out ''
  (nothing MergeComment understands to say) and the ORIGINAL (unguarded)
  delete branch removed the WHOLE region outright -- hand-written source
  lines gone, not just replaced.

  This is NOT a licence to fix the underlying tag-dropping (that is a
  separately-tracked, larger task) -- it is a guard that makes the DELETE
  branch conservative: only delete when Existing carries NONE of the tag
  types MergeComment cannot re-emit. Kept even after a future task makes
  these tags round-trip -- defence-in-depth for any tag type MergeComment
  does not yet handle, correct by construction rather than by coincidence.

  Fixture fixtures\docp3\unhandledtags.pas: three parameterless, factless,
  return-less procedures --
    * HasException -- a hand-written comment consisting of ONLY <exception>.
    * HasExample -- ONLY <example>.
    * HasSinceSeeAlsoDeprecated -- <since> + <seealso> + <deprecated/>
      together, plus an empty <remarks></remarks> (see the fixture's own
      comment for why: SinceText/SeeAlso alone do not set HasContent, and a
      bare <since>/<seealso>/<deprecated> mis-dispatches to ParseOneline --
      a SEPARATE, pre-existing, unfixed defect this fixture works around so
      it exercises ONLY Finding 2's guard, not that other bug).
  Nothing else for MergeComment to preserve or regenerate in any of the
  three, so Merged comes out '' for every one of them.

  Drives `index` -> `document --unit --apply` and asserts:
    1. The file is BYTE-IDENTICAL to the pre-apply fixture (--json reports
       edits=0 for the whole unit) -- none of the three comments is
       deleted, replaced, or otherwise touched.
    2. Each hand-written tag is still present, verbatim.

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
  Check '2. hand-written <example> survives verbatim'    ($text.Contains('/// <example>Example text.</example>'))
  Check '2. hand-written <since> survives verbatim'       ($text.Contains('/// <since>2020-01-01</since>'))
  Check '2. hand-written <seealso> survives verbatim'     ($text.Contains('/// <seealso cref="Other.Thing"/>'))
  Check '2. hand-written <deprecated/> survives verbatim' ($text.Contains('/// <deprecated/>'))
  Check '2. the forcing-dispatch <remarks></remarks> survives verbatim too' ($text.Contains('/// <remarks></remarks>'))
} finally { Pop-Location }

if($script:Failed){ Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
