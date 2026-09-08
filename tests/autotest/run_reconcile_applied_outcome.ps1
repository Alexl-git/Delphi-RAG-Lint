<#
  run_reconcile_applied_outcome.ps1 -- `reconcile-project` reports the OUTCOME
  of --apply, not the flag: `applied`, `backups` and `edited`.

  WHY THIS EXISTS
  ---------------
  `reconcile-project --json` emitted {missing, extra, stale} and nothing else.
  The "Applied: ..." line went to stderr, unconditionally, whenever --apply was
  passed -- so a caller reading the document could not tell a real write from a
  project that needed none, and exit 0 covered both. The IDE's Uses & Deps tab
  wants to say "2 members added" and to offer a revert, and neither is
  expressible against that contract.

  This is defect 1 of session 77's self-review, in the other verb. uses-fix
  reported `applied` from the FLAG: --apply on an already-clean unit claimed a
  rewrite that never happened and offered a revert for a .bak that was never
  taken. Same shape here, and worse, because reconcile writes TWO files.

  THE THREE NO-OPS THAT USED TO READ AS A SUCCESSFUL WRITE. Apply can be asked
  to write and correctly write nothing:
    (a) Missing is empty -- Apply exits before taking a backup;
    (b) the .dpr has no uses clause, or no terminating ';' -- EditDpr bails;
    (c) every DCCReference is already present -- EditDproj bails.
  The old line announced "Missing units added to .dpr and .dproj (.bak backups
  written)" in all three.

  WHY `backups` AND `edited` ARE SEPARATE FIELDS, not one. The backup is taken
  BEFORE the edit is attempted and both editors are idempotent, so a run can
  leave a .bak on disk having changed nothing. A caller offering "revert" must
  key on `backups`; one reporting "N units added" must key on `edited`.
  Collapsing them is exactly how a revert button appears for a write that never
  happened -- the thing this whole change exists to prevent.

  WHY `applied` IS ALWAYS PRESENT, including on a dry run where it is false.
  An absent key is what a caller mis-reads: `@($null).Count` is 1 in
  PowerShell, so a missing field can measure as one entry (that mistake is
  logged in this repo's memory). `backups`/`edited` are the deliberate
  exception -- they appear only with --apply, because a dry run has nothing to
  say about them and the document shape stays as it was for existing dry-run
  callers. Check 2c pins that asymmetry so it cannot be "tidied" into always-on
  without someone reading this paragraph.

  RED BASELINE -- MEASURED 2026-09-07, not predicted, against an engine
  built from the pre-change sources (HEAD = a5088ba). 10 fail, 4 pass:

      RED    1b 2a 2b 2c 2d 3b 4a 4c 5a 5b
      GREEN  1a 3a 4b -- and they must STAY green. They are what proves the
             fixture still has three MISSING units, that --apply still writes
             at all, and that --only still narrows; without them the
             'applied is false' checks would pass against an engine that
             never applies anything.
      GREEN BUT VACUOUS  3c -- 'no backups and no edits reported' is trivially
             true of an engine with no such fields. It is a companion to 2b,
             never evidence on its own.

  The RED run of 5b is the defect in one screen: the report says MISSING (0)
  and the very next line says "Applied: Missing units added to .dpr and
  .dproj (.bak backups written)."

  Writing this baseline also cost two defects IN THIS FILE, both found by
  running it against RED rather than by reading it: `@($app.backups).Count`
  measured 1 for an absent key, and `Test-Path $null` threw and ended the run
  four checks early. Hence CountOf and PathList below.

  THE VACUITY TRAP THIS RUNNER IS BUILT AROUND. "applied == false" is the
  assertion most of this file makes, and it is true of an engine that writes
  nothing, of an engine that omits the key entirely, and of an engine that is
  correct. So every false-assertion below is paired with a positive control in
  the SAME fixture state: 2a (applied true) precedes 3a (applied false), and 4a
  (edited non-empty) precedes 4c (edited empty). A false-assertion with no
  paired positive is not evidence.

  Usage: pwsh -File tests\autotest\run_reconcile_applied_outcome.ps1
#>
$Exe = . "$PSScriptRoot\_manifest_common.ps1"

$fx = "$PSScriptRoot\..\fixtures\reconcile"

# This runner's own scratch name. run_reconcile.ps1 owns
# $env:TEMP\drag-lint-reconcile and run_reconcile_only_selection.ps1 owns
# ...-only; two runners sharing one fixed scratch directory is a defect
# run_battery_jobs_guard.ps1 polices.
$work = "$env:TEMP\drag-lint-reconcile-applied"

function FreshCopy {
  if (Test-Path $work) { Remove-Item -Recurse -Force $work }
  Copy-Item -Recurse $fx $work
}

# Parse stdout as one JSON object. Returns $null when it is not parseable, so a
# corrupted document fails the check that wanted a field rather than throwing
# somewhere unrelated.
function AsJson([string]$Text) {
  try { return ($Text | ConvertFrom-Json) } catch { return $null }
}

# Key presence, not value truthiness. `$o.nosuch` is $null and so is a key
# holding null; only the property list distinguishes them, and the whole point
# of 2c/2d is which keys exist.
function HasKey($Obj, [string]$Name) {
  if ($null -eq $Obj) { return $false }
  return [bool]($Obj.PSObject.Properties.Name -contains $Name)
}

# COUNT BY FILTERING, NEVER BY @().Count. `@($null).Count` is 1 in
# PowerShell, so an ABSENT json key measures as one element -- which is how
# the RED run of this very file reported `backups=1` against an engine that
# has no backups field at all. Every count below goes through here.
function CountOf($Value) {
  return @($Value | Where-Object { $null -ne $_ }).Count
}

# Test-Path THROWS on a null or empty path, which aborted the RED run of this
# runner four checks early -- turning a measurable baseline into a crash.
function PathList($Value) {
  return @($Value | Where-Object { $_ -is [string] -and $_ -ne '' })
}

Write-Host '== reconcile-project: applied / backups / edited are the OUTCOME ==' -ForegroundColor Cyan

# ---------------------------------------------------------------------------
# 1 -- BASELINE + the dry-run document.
# ---------------------------------------------------------------------------
FreshCopy
$dryRaw = & $Exe reconcile-project "$work\App.dpr" --json 2>$null | Out-String
$dry    = AsJson $dryRaw

Check '1a baseline: dry run parses and lists three MISSING units' `
  ($null -ne $dry -and (CountOf $dry.missing) -eq 3) `
  "the fixture is what every count below is measured against; got missing=$(CountOf $dry.missing)"

# A DRY RUN IS NOT AN APPLY, and the document has to say so in its own right.
# Before this change there was no field to say it with: a caller saw {missing,
# extra, stale} and had to infer "nothing was written" from the absence of a
# flag it could not see.
Check '1b dry run: applied is present and false' `
  ((HasKey $dry 'applied') -and $dry.applied -eq $false) `
  "hasKey=$(HasKey $dry 'applied') value=$($dry.applied)"

# ---------------------------------------------------------------------------
# 2 -- A REAL APPLY. Positive control for everything in 3 and 4.
# ---------------------------------------------------------------------------
$appRaw = & $Exe reconcile-project "$work\App.dpr" --apply --json 2>$null | Out-String
$app    = AsJson $appRaw

Check '2a apply that writes: applied is true' `
  ($null -ne $app -and $app.applied -eq $true) `
  "positive control -- if this is false every 'applied is false' below is vacuous; got: $($app.applied)"

# Both project files exist in the fixture, so both are backed up and both are
# rewritten. Asserting the COUNT rather than >0 pins that the .dproj arm runs
# even though the .dpr arm ran first -- they were one `and` expression at one
# point in drafting, which would have skipped the second.
Check '2b apply: two backups and two edited files' `
  ($null -ne $app -and (CountOf $app.backups) -eq 2 -and (CountOf $app.edited) -eq 2) `
  "backups=$(CountOf $app.backups) edited=$(CountOf $app.edited)"

Check '2c dry run omits backups/edited; apply carries them' `
  ((-not (HasKey $dry 'backups')) -and (-not (HasKey $dry 'edited')) -and `
   (HasKey $app 'backups') -and (HasKey $app 'edited')) `
  ("the shape stays unchanged for dry-run callers; " +
   "dry has backups=$(HasKey $dry 'backups')/edited=$(HasKey $dry 'edited'), " +
   "apply has backups=$(HasKey $app 'backups')/edited=$(HasKey $app 'edited')")

# THE PATHS MUST BE REAL. A field naming a .bak that is not on disk is worse
# than no field: it is what a revert button would offer.
$bakPaths   = PathList $app.backups
$bakAllExist = $true
foreach ($b in $bakPaths) { if (-not (Test-Path $b)) { $bakAllExist = $false } }
Check '2d apply: every reported backup path exists on disk' `
  ($bakAllExist -and $bakPaths.Count -gt 0) `
  "reported: $($bakPaths -join ' | ')"

# ---------------------------------------------------------------------------
# 3 -- THE NO-OP APPLY (case (a)): nothing MISSING, so nothing to write.
#      This is the case the old unconditional message got wrong.
# ---------------------------------------------------------------------------
$againRaw = & $Exe reconcile-project "$work\App.dpr" --apply --json 2>$null | Out-String
$again    = AsJson $againRaw

Check '3a second apply: MISSING is now empty (the fixture really was reconciled)' `
  ($null -ne $again -and (CountOf $again.missing) -eq 0) `
  "got missing=$(CountOf $again.missing)"

Check '3b second apply: applied is FALSE -- nothing was written' `
  ($null -ne $again -and $again.applied -eq $false) `
  "this is the defect: --apply on an already-reconciled project used to claim a write; got: $($again.applied)"

# No write means no NEW backup either. Apply exits before the backup step when
# Missing is empty, so the arrays are empty -- not merely 'unchanged'.
Check '3c second apply: no backups and no edits reported' `
  ($null -ne $again -and (CountOf $again.backups) -eq 0 -and (CountOf $again.edited) -eq 0) `
  "backups=$(CountOf $again.backups) edited=$(CountOf $again.edited)"

# ---------------------------------------------------------------------------
# 4 -- PARTIAL APPLY. --only narrows what is written, so `edited` must describe
#      the narrowed write, and `applied` must still be the outcome of it.
# ---------------------------------------------------------------------------
FreshCopy
$onlyRaw = & $Exe reconcile-project "$work\App.dpr" --only uHelper --apply --json 2>$null | Out-String
$only    = AsJson $onlyRaw

Check '4a --only --apply: applied is true and files were edited' `
  ($null -ne $only -and $only.applied -eq $true -and (CountOf $only.edited) -gt 0) `
  "positive control for 4c; applied=$($only.applied) edited=$(CountOf $only.edited)"

Check '4b --only --apply: the document reports the NARROWED missing set' `
  ($null -ne $only -and (CountOf $only.missing) -eq 1) `
  "a dry run with --only is meant to be an exact preview of the apply; got missing=$(CountOf $only.missing)"

# The unselected units are still missing afterwards. Without this, 4a would
# pass against an engine that ignored --only and applied everything -- which is
# the behaviour --only exists to replace.
$leftRaw = & $Exe reconcile-project "$work\App.dpr" --json 2>$null | Out-String
$left    = AsJson $leftRaw
Check '4c after a partial apply: the two unselected units are still MISSING' `
  ($null -ne $left -and (CountOf $left.missing) -eq 2 -and $left.applied -eq $false) `
  "missing=$(CountOf $left.missing) applied=$($left.applied)"

# ---------------------------------------------------------------------------
# 5 -- THE TEXT PATH. The same claim is made in prose, and it was wrong there
#      too. Checked separately because the JSON and text branches print from
#      the same result but through different code.
# ---------------------------------------------------------------------------
FreshCopy
$txtApply = & $Exe reconcile-project "$work\App.dpr" --apply 2>&1 | Out-String
Check '5a text apply that writes: names the files it updated' `
  ($txtApply -match 'Applied: updated .*App\.dpr' -and $txtApply -match 'Backup:\s+.*App\.dpr\.bak') `
  "positive control for 5b; got:`n$txtApply"

$txtNoop = & $Exe reconcile-project "$work\App.dpr" --apply 2>&1 | Out-String
Check '5b text no-op apply: says nothing was written, not "units added"' `
  ($txtNoop -match 'nothing to write' -and $txtNoop -notmatch 'Applied: updated') `
  "the old line claimed units were added to both project files; got:`n$txtNoop"

if (Test-Path $work) { Remove-Item -Recurse -Force $work }

Write-Host ''
if ($script:Failed) { Write-Host 'RECONCILE applied/backups/edited: FAIL' -ForegroundColor Red; exit 1 }
else { Write-Host 'RECONCILE applied/backups/edited: PASS' -ForegroundColor Green; exit 0 }
