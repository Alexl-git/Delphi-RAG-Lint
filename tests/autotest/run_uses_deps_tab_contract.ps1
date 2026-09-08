<#
  run_uses_deps_tab_contract.ps1 -- the source-level contract of the
  "Uses & Deps" dock tab (DragLint.Plugin.UsesDepsFrame.pas).

  WHY A SOURCE GUARD AND NOT A BEHAVIOUR TEST
  -------------------------------------------
  The tab is UI inside a design-time BPL. Nothing in this battery can open the
  IDE, click a checkbox and watch a .dpr change, so the properties asserted here
  are the ones that CAN be checked without a live IDE -- and they are chosen
  because each has a specific, known way of going wrong, not because they are
  easy to check.

  A guard like this is worth exactly as much as its RED baseline, so each check
  below names what it would catch.

  RED SWEEP, MEASURED 2026-09-07 -- every check individually, not the file as a
  whole. For each assertion the property it claims to guard was broken in the
  real source, this guard was run, and the failing check ids recorded; then the
  source was restored. All 14 mutations produce exactly the intended failure
  (5a's also trips 5c, because deleting the reload block removes both), and the
  unmutated tree is green. The file simply not existing is NOT a RED baseline:
  it proves nothing about any individual check.

  THE SWEEP PAID FOR ITSELF IMMEDIATELY. Two checks were incapable of failing
  and both looked fine on the page:
    * 2b matched ONE `--only ... --apply`, so dropping the flag from the
      uses-fix arm left it green on the strength of the reconcile arm. It
      counts both arms now.
    * 3b's regex matched the INTERFACE declaration of the factory and then ran
      to the first `end;` in the file -- an unrelated helper -- so it was
      inspecting text that could never contain a query. Worse, 3a ('the body
      was found') passed the whole time, because a non-empty match is not the
      same as the right match. Both are anchored on `var` now, which only the
      implementation has.

  THE FIVE PROPERTIES

  1. THE UNIT IS IN BOTH THE .dpk AND THE .dproj. A new unit needs the package's
     `contains` clause AND a <DCCReference>; with only one of them the build
     fails with F2613 at a point far from the cause, and with neither the tab
     silently is not in the shipped BPL. This is the single most likely thing to
     be forgotten when a unit is added.

  2. THE ENGINE OWNS THE EDIT. The whole point of --only is that the plugin
     never grows a second rewriter: the frame collects ticks and passes them as
     a flag. If this file ever writes source itself, uses-fix's per-candidate
     compiler verification is out of the loop and the two implementations start
     to disagree. Asserted as: no file-writing call anywhere in the frame.

  3. NOTHING RUNS ON ACTIVATION. uses-fix shadow-compiles once per candidate.
     A refresh wired to tab activation would make the dock feel hung every time
     the user clicked the tab. Asserted as: the CreateEmbeddedUsesDeps factory
     runs no query.

  4. THE APPLY BELIEVES `applied`, NOT THE EXIT CODE, and only offers a revert
     when a backup exists. This is defect 1 of session 77 -- reporting the FLAG
     rather than the outcome told a caller its unit had been rewritten when it
     had not. The tab is the one caller putting a button in front of a human.

  5. MODULES ARE RELOADED AFTER A WRITE. The engine writes the file on disk
     while the IDE may hold it open; a stale editor buffer silently overwrites
     the fix on the next save. This is the one correctness requirement in the
     whole tab, and its failure is invisible -- the change appears to work and
     then vanishes.

  6. THE OTHER FIVE TABS SURVIVE THIS ONE FAILING. Session 77's lesson, stated
     in the design: the feature's own guard was blind to a crash because every
     check exercised the flag and the bug lived where the flag was absent. Here
     the equivalent control is that a tab which fails to build must cost only
     itself -- so the dock's embed call has its own try/except, exactly like its
     five neighbours.

  Usage: pwsh -File tests\autotest\run_uses_deps_tab_contract.ps1
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$script:Failed = $false
function Check([string]$Name, [bool]$Ok, [string]$Detail = '') {
  $status = if ($Ok) { 'PASS' } else { 'FAIL' }
  $color  = if ($Ok) { 'Green' } else { 'Red' }
  Write-Host ("  [{0}] {1}" -f $status, $Name) -ForegroundColor $color
  if (-not $Ok -and $Detail) { Write-Host "        $Detail" -ForegroundColor DarkGray }
  if (-not $Ok) { $script:Failed = $true }
}

$plugin = Resolve-Path "$PSScriptRoot\..\..\src\delphi-plugin"
$frame  = Join-Path $plugin 'DragLint.Plugin.UsesDepsFrame.pas'
$dock   = Join-Path $plugin 'DragLint.Plugin.DockForm.pas'
$dpk    = Join-Path $plugin 'dclDragLintWizard.dpk'
$dproj  = Join-Path $plugin 'dclDragLintWizard.dproj'

Write-Host '== Uses & Deps tab: source contract ==' -ForegroundColor Cyan

# ---------------------------------------------------------------------------
# 0 -- the file exists at all. Everything below reads it, so a miss here would
#      otherwise surface as eight confusing failures instead of one clear one.
# ---------------------------------------------------------------------------
Check '0 the frame unit exists' (Test-Path $frame) $frame
if (-not (Test-Path $frame)) { Write-Host 'USES & DEPS TAB: FAIL' -ForegroundColor Red; exit 1 }

$src     = Get-Content $frame -Raw
$dockSrc = Get-Content $dock  -Raw

# ---------------------------------------------------------------------------
# 1 -- registered in BOTH project files.
# ---------------------------------------------------------------------------
Check '1a the unit is in the .dpk contains clause' `
  ((Get-Content $dpk -Raw) -match 'DragLint\.Plugin\.UsesDepsFrame\s+in\s+') `
  'without it the unit is not compiled into the BPL and the tab is simply absent'

Check '1b the unit has a <DCCReference> in the .dproj' `
  ((Get-Content $dproj -Raw) -match 'DCCReference\s+Include="DragLint\.Plugin\.UsesDepsFrame\.pas"') `
  'a unit in the .dpk but not the .dproj fails the build with F2613'

# ---------------------------------------------------------------------------
# 2 -- the ENGINE owns the edit.
#
# Matched against the file-writing calls this codebase actually uses. Note this
# is a TEXT scan and so cannot tell code from a comment -- which is precisely
# why the pattern requires a call shape ("Ident(") rather than a bare word, and
# why the doc comments in that file deliberately say "rewrites" rather than
# naming an RTL writer.
# ---------------------------------------------------------------------------
$writers = @('TFile\.WriteAllText\(', 'TFile\.WriteAllLines\(', 'TFile\.AppendAllText\(',
             'TStringList\.SaveToFile\(', '\.SaveToFile\(', 'Rewrite\(', 'TFile\.Copy\(')
$writeHits = @()
foreach ($w in $writers) { if ($src -match $w) { $writeHits += $w } }
Check '2 the frame writes no source file itself (the engine owns the edit)' `
  ($writeHits.Count -eq 0) `
  "found: $($writeHits -join ', ') -- a second rewriter in the plugin bypasses uses-fix's compiler verification"

# The positive half: it must actually pass --only, or "reviewed apply" is a lie
# and every tick is decoration over an all-or-nothing rewrite.
# BOTH command lines, COUNTED -- not one regex that either could satisfy.
# The RED sweep caught this: dropping --only from the uses-fix arm alone left
# the check green, because the reconcile-project arm still matched.
$onlyArms = ([regex]::Matches($src, '--only %s --apply')).Count
Check '2b BOTH apply command lines pass the ticked names as --only' `
  ($onlyArms -eq 2) `
  "found $onlyArms of 2 -- without --only that button applies EVERYTHING regardless of what was ticked"

# ---------------------------------------------------------------------------
# 3 -- nothing runs on activation.
# ---------------------------------------------------------------------------
# ANCHORED ON `var`, WHICH ONLY THE IMPLEMENTATION HAS. The first version
# matched the INTERFACE declaration and then ran on to the first `end;` in
# the file -- which belongs to an unrelated helper -- so 3b was inspecting
# the wrong text entirely and could not fail. 3a passed throughout, because
# a non-empty match is not the same as the RIGHT match. Found by the RED
# sweep, not by reading it.
$factory = [regex]::Match($src,
  'procedure CreateEmbeddedUsesDeps\([^)]*\);\r?\nvar[\s\S]*?\r?\nend;').Value
Check '3a the factory IMPLEMENTATION body was found' `
  ($factory -match 'TUsesDepsFrame\.Create') `
  'matched text that is not the factory -- 3b would then be measuring nothing'
Check '3b the factory runs no query' `
  ($factory -ne '' -and $factory -notmatch 'RefreshAll|RunEngine|\.Refresh\b') `
  'uses-fix shadow-compiles per candidate; querying on open makes the dock feel hung'

# ---------------------------------------------------------------------------
# 4 -- believe `applied`, not the exit code; revert only against a real backup.
# ---------------------------------------------------------------------------
Check '4a the outcome is read from the document''s `applied` field' `
  ($src -match "TryGetValue<Boolean>\('applied'") `
  'reporting the --apply FLAG instead is defect 1 of session 77, in a new place'

Check '4b a revert is offered only when a backup path came back' `
  ($src -match 'if Length\(AOutcome\.Backups\) > 0 then') `
  'offering a revert for a .bak that was never written is the same defect'

Check '4c an unreadable document is NOT reported as "nothing was written"' `
  ($src -match 'Readable' -and $src -match 'may or may not have been written') `
  'the engine may have written before whatever spoiled the document; silence there loses a change'

# ---------------------------------------------------------------------------
# 5 -- the stale-buffer requirement.
# ---------------------------------------------------------------------------
Check '5a a successful apply reloads the affected modules' `
  ($src -match 'if Outcome\.Applied then[\s\S]{0,200}ReloadModules') `
  'a stale IDE buffer silently overwrites the fix on the next save -- the fix appears to work, then vanishes'

Check '5b the reload is deferred with ForceQueue, not called inline' `
  ($src -match 'TThread\.ForceQueue') `
  'refreshing a module from inside a control''s own dispatch left a dangling TEditSource and closed the tab (Keyboard.pas)'

Check '5c the project section reloads exactly the files the engine says it edited' `
  ($src -match 'ReloadModules\(Outcome\.Edited\)') `
  'reloading a guessed set disturbs modules that did not change'

# ---------------------------------------------------------------------------
# 6 -- THE NEIGHBOUR CONTROL. A tab that fails to build costs only itself.
# ---------------------------------------------------------------------------
Check '6a the dock builds the tab as the sixth tab' `
  ($dockSrc -match "AddTab\('Uses & Deps'") `
  'the tab is not constructed at all'

Check '6b the embed is wrapped in its own try/except' `
  ($dockSrc -match 'try\s*\r?\n\s*CreateEmbeddedUsesDeps\(Self, FTabUsesDeps\);\s*\r?\n\s*except') `
  'without it, one tab failing to build takes the other five with it'

# The dead field the tab count was once taken from. Removed with this change;
# pinned so it cannot come back and make the next count wrong again.
Check '6c the dead FTabGraph field is gone' `
  ($dockSrc -notmatch '(?m)^\s*FTabGraph\s*:\s*TTabSheet') `
  'it was declared and never assigned, and is what made a tab count read one too high'

Write-Host ''
if ($script:Failed) { Write-Host 'USES & DEPS TAB: FAIL' -ForegroundColor Red; exit 1 }
else { Write-Host 'USES & DEPS TAB: PASS' -ForegroundColor Green; exit 0 }
