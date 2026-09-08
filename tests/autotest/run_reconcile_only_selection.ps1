<#
  run_reconcile_only_selection.ps1 -- `reconcile-project --only <unit,...>`.

  WHY THIS EXISTS
  ---------------
  `reconcile-project --apply` was all-or-nothing: it added every MISSING unit to
  the .dpr and .dproj, or none. The IDE therefore exposed it as a REPORT only --
  offering a button that silently rewrites two project files with changes the
  user has not seen one by one is not a button anyone should press.

  `--only` is what makes a reviewed, partial apply expressible. The IDE's Uses
  tab lists each MISSING unit with a checkbox and passes the ticked ones; the
  engine keeps ownership of the edit, so the plugin never reimplements the
  rewriter (which is how a "fix button" usually goes wrong).

  SCOPE OF THE FLAG, stated because the other two sections invite the question:
  --only restricts MISSING, which is the only actionable set -- Apply adds
  missing units and does nothing else (TProjectReconciler.Apply exits early
  unless Missing is non-empty, and never touches EXTRA or STALE). EXTRA and
  STALE stay unfiltered because they are review-only; filtering an advisory
  list by what you intend to WRITE would hide findings rather than defer them.

  A DRY RUN WITH --only IS AN EXACT PREVIEW OF THE APPLY. That is the point: the
  same flag narrows the report and the write, so what the tab shows as selected
  cannot disagree with what the button then does. Two code paths that compute
  "the selected set" separately is precisely the writer-vs-checker divergence
  this repo has just spent a session removing from the doc layer.

  RED BASELINE, measured on the deployed engine before the flag existed
  (2026-09-07). The fixture reports MISSING (3) -- uHelper, uFoo_OLD_20230828,
  uData_20240101:

      RED    2a, 2c, 3b, 3c, 5a, 5b, 6
      GREEN  1, 3, 4  -- and these must STAY green: they are what proves the
             fixture and the apply path work, without which 3b would pass on an
             apply that writes nothing at all.
      GREEN BUT VACUOUS  2b, 3a, 7 -- with everything applied, the selected unit
             is trivially present. They are companions to the discriminating
             assertions (2a, 3b, 6), never evidence on their own.

  2c was written first as `MISSING[\s\S]*uFoo_OLD_20230828` and FAILED against
  correct output, because STALE legitimately lists the same unit lower down. A
  cross-section regex tests the report's layout rather than the filter; it now
  reads the MISSING block alone, and 2d pins that STALE stays unfiltered on
  purpose.

  Usage: pwsh -File tests\autotest\run_reconcile_only_selection.ps1
#>
$Exe = . "$PSScriptRoot\_manifest_common.ps1"

$fx = "$PSScriptRoot\..\fixtures\reconcile"

# A scratch name of this runner's own -- run_reconcile.ps1 already owns
# $env:TEMP\drag-lint-reconcile, and two runners sharing one fixed scratch
# directory is a defect run_battery_jobs_guard.ps1 now polices.
$work = "$env:TEMP\drag-lint-reconcile-only"

function FreshCopy {
  if (Test-Path $work) { Remove-Item -Recurse -Force $work }
  Copy-Item -Recurse $fx $work
}

Write-Host '== reconcile-project --only (partial, reviewed apply) ==' -ForegroundColor Cyan

# ---------------------------------------------------------------------------
# 1 -- BASELINE. All three are missing. If this ever changes, every count below
#      is measuring a different fixture and the numbers stop meaning anything.
# ---------------------------------------------------------------------------
FreshCopy
$all = & $Exe reconcile-project "$work\App.dpr" 2>&1 | Out-String
Check '1 baseline: three units are MISSING' `
  ($all -match 'MISSING \(3\)') `
  "got: $(($all -split "`n" | Select-String 'MISSING').Line)"

# ---------------------------------------------------------------------------
# 2 -- A DRY RUN WITH --only PREVIEWS EXACTLY ONE.
# ---------------------------------------------------------------------------
$one = & $Exe reconcile-project "$work\App.dpr" --only uHelper 2>&1 | Out-String
Check '2a --only narrows MISSING to the selected unit' `
  ($one -match 'MISSING \(1\)') `
  "got: $(($one -split "`n" | Select-String 'MISSING').Line)"
Check '2b and it is the one that was asked for' `
  ($one -match 'uHelper') 'the single remaining entry must be uHelper'
# Scoped to the MISSING BLOCK, not "anywhere after the word MISSING". The first
# version of this assertion used `MISSING[\s\S]*uFoo_OLD_20230828` and failed
# against correct output, because STALE legitimately lists the same unit further
# down the report. A cross-section regex tests the report's layout, not the
# filter.
function MissingBlock([string]$Report) {
  $lines = @($Report -split "`r?`n")
  $out = New-Object System.Collections.Generic.List[string]
  $inBlock = $false
  foreach ($l in $lines) {
    if ($l -match '^MISSING \(') { $inBlock = $true; continue }
    if ($l -match '^(EXTRA|STALE) \(') { $inBlock = $false }
    if ($inBlock) { $out.Add($l) }
  }
  return ($out -join "`n")
}
$oneMissing = MissingBlock $one
Check '2c the deselected units are gone from the MISSING block' `
  (($oneMissing -notmatch 'uFoo_OLD_20230828') -and ($oneMissing -notmatch 'uData_20240101')) `
  "a preview that still lists what it will not write is not a preview; block was:`n$oneMissing"
Check '2d and STALE is deliberately NOT filtered (advisory, not actionable)' `
  ($one -match 'STALE[\s\S]*uFoo_OLD_20230828') `
  'filtering an advisory list by what you intend to write hides findings'

# ---------------------------------------------------------------------------
# 3 -- THE APPLY WRITES ONLY THE SELECTION. This is the assertion the feature
#      exists for; 3b is what was impossible before the flag.
# ---------------------------------------------------------------------------
FreshCopy
& $Exe reconcile-project "$work\App.dpr" --only uHelper --apply 2>&1 | Out-Null
Check '3 apply with --only exits 0' ($LASTEXITCODE -eq 0) "exit $LASTEXITCODE"
$dpr = Get-Content "$work\App.dpr" -Raw
Check '3a the selected unit WAS added' `
  ($dpr -match 'uHelper\s+in\s+''uHelper\.pas''') 'selection was not applied'
Check '3b the deselected units were NOT added' `
  (($dpr -notmatch 'uFoo_OLD_20230828') -and ($dpr -notmatch 'uData_20240101')) `
  'all-or-nothing behaviour survived -- --only did not restrict the write'
$dproj = Get-Content "$work\App.dproj" -Raw
Check '3c the .dproj moved in step with the .dpr' `
  (($dproj -match 'DCCReference Include="uHelper\.pas"') -and
   ($dproj -notmatch 'uFoo_OLD_20230828')) `
  'the two project files must never disagree about the member list'

# ---------------------------------------------------------------------------
# 4 -- POSITIVE CONTROL. Without --only, all three still land. Without this,
#      assertion 3b passes just as well on an apply that writes NOTHING.
# ---------------------------------------------------------------------------
FreshCopy
& $Exe reconcile-project "$work\App.dpr" --apply 2>&1 | Out-Null
$dprAll = Get-Content "$work\App.dpr" -Raw
Check '4 positive control: no --only still adds all three' `
  (($dprAll -match 'uHelper') -and ($dprAll -match 'uFoo_OLD_20230828') -and
   ($dprAll -match 'uData_20240101')) `
  'if this fails, 3b proves nothing -- it would pass on a broken apply'

# ---------------------------------------------------------------------------
# 5 -- A SELECTION THAT MATCHES NOTHING WRITES NOTHING, and says so rather than
#      reporting a cheerful success. Silence here would read as "applied".
# ---------------------------------------------------------------------------
FreshCopy
$none = & $Exe reconcile-project "$work\App.dpr" --only NoSuchUnitHere --apply 2>&1 | Out-String
$dprNone = Get-Content "$work\App.dpr" -Raw
Check '5a an unmatched --only writes nothing' `
  (($dprNone -notmatch 'uHelper') -and ($dprNone -notmatch 'uFoo_OLD_20230828')) `
  'a typo in a unit name must not silently apply everything'
Check '5b and it names what it could not match' `
  ($none -match 'NoSuchUnitHere') `
  'a selection that matched nothing has to be reported, or a typo looks like a clean run'

# ---------------------------------------------------------------------------
# 6 -- MULTI-SELECT. The tab passes a comma-separated list of ticked units.
# ---------------------------------------------------------------------------
FreshCopy
& $Exe reconcile-project "$work\App.dpr" --only "uHelper,uData_20240101" --apply 2>&1 | Out-Null
$dpr2 = Get-Content "$work\App.dpr" -Raw
Check '6 a comma-separated selection applies exactly those' `
  (($dpr2 -match 'uHelper') -and ($dpr2 -match 'uData_20240101') -and
   ($dpr2 -notmatch 'uFoo_OLD_20230828')) `
  'two selected, one not -- the third must stay out'

# ---------------------------------------------------------------------------
# 7 -- CASE. Pascal unit names are case-insensitive, and a checkbox list built
#      from one query and passed back to another must not depend on casing.
# ---------------------------------------------------------------------------
FreshCopy
& $Exe reconcile-project "$work\App.dpr" --only "UHELPER" --apply 2>&1 | Out-Null
$dpr3 = Get-Content "$work\App.dpr" -Raw
Check '7 --only matches unit names case-insensitively' `
  ($dpr3 -match 'uHelper\s+in\s+''uHelper\.pas''') `
  'Pascal identifiers are case-insensitive; the flag must be too'

if (Test-Path $work) { Remove-Item -Recurse -Force $work }

Write-Host ''
if ($script:Failed) { Write-Host 'RECONCILE --only: FAIL' -ForegroundColor Red; exit 1 }
else { Write-Host 'RECONCILE --only: PASS' -ForegroundColor Green; exit 0 }
