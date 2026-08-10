<#
  run_project_db_resolve.ps1 -- a project file resolves to the ONE index that owns it.

  What this guards
  ----------------
  DRagLint.Index.Manifest.ResolveProjectDb answers "which single DB should a
  WRITER target for this project file". It is reached two ways:

    drag-lint resolve-dbs --project <file.dproj>        (this test)
    the IDE plugin's "Rebuild Index for This Project"   (not headlessly testable)

  Both call the SAME function, which is the point: a design-time BPL cannot be
  exercised without a running IDE, so the CLI verb is how the resolution the IDE
  depends on gets a regression test at all.

  WHY IT EXISTS -- the bug it was written for
  -------------------------------------------
  The plugin used to resolve a DB by folding each manifest `include` entry down
  to its FOLDER and taking the longest matching prefix
  (DragLint.Plugin.DbResolver.ManifestDbForFile). That is exact enough while one
  folder holds one project. It stopped being true on 2026-08-09, when the
  manifest was converted to per-project closure sections and several folders
  ended up holding two or more:

    C:\Projects\DB\ORM3\PACKAGE\   Interfaces.dproj + TestMicroniteObjects.dproj
    C:\Projects\DataCopy\          DataCopy.dproj   + SortTest.dproj
    C:\Projects\TableTools\        TableTools370P.dproj + MemTableFieldWizard.dproj
    C:\Projects\YADF\              YADF + YADFOT + YADFSetup
    ...Delphi-RAG-Lint-Graph\src\pkg\  DragLintGraph.dproj + DragLintGraphDb.dproj

  Every sibling folds to one identical key, the length comparison is a strict
  '>', and so the FIRST section silently wins for all of them. Activating
  TestMicroniteObjects resolved to ORM3-Interfaces.sqlite.

  While indexing was incremental and additive that was untidy. It became DATA
  LOSS the moment the same code path started passing `--rebuild`, which clears
  every indexed file from the DB before walking: the wrong index is emptied and
  refilled with a different project's closure, and the right one is never
  written. Nothing errors.

  So this file asserts the three behaviours that make that impossible, and the
  ambiguity/none cases assert a REFUSAL rather than a fallback -- a wrong DB
  under --rebuild destroys an index, while refusing costs a click.

  Checks
  ------
    two sibling projects in ONE folder each resolve to their OWN db (the
      regression: folder-prefix matching cannot do this)
    a folder section covering the same directory does NOT capture a project
      (folder sections keep working as folder sections, and are not consulted
      for a project file)
    a project no section names resolves to NOTHING: exit 2, nothing on stdout
      (it must not fall back to the nearby folder section's db)
    a project claimed by TWO sections is REFUSED: exit 2, both section names
      reported, nothing on stdout
    matching survives case differences and '..' segments in the path
    --json emits the section name alongside the db

  and for READ resolution (resolve-dbs --in <file>, what hover / Find Usages /
  the LSP would open -- the same defect on the read side, same cause):

    a .pas in a shared folder resolves to the ACTIVE project's db FIRST, and
      follows the active project when it changes (same file, different answer)
    the folder-matched db is KEPT as a second entry, never replaced -- an editor
      file outside the active project (library source browsed with a project
      open) must not go from a wrong answer to no answer
    with NO active project, the folder behaviour is unchanged
    an AMBIGUOUS active project falls back to the folder db rather than
      refusing: on the READ path a too-broad db is cosmetic, whereas the WRITE
      path refuses (above), and the two must not be confused

  Exit code: 0 on full pass, 1 on any failure.

  Usage: pwsh -File tests\autotest\run_project_db_resolve.ps1
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\draglint-project-db-resolve"
)

$ErrorActionPreference = 'Stop'
$script:Failed = $false

function Check([string]$Name, [bool]$Ok, [string]$Detail = '') {
  $status = if ($Ok) { 'PASS' } else { 'FAIL' }
  $color  = if ($Ok) { 'Green' } else { 'Red' }
  Write-Host ("  [{0}] {1} {2}" -f $status, $Name, $Detail) -ForegroundColor $color
  if (-not $Ok) { $script:Failed = $true }
}

Write-Host '== project -> owning index db (resolve-dbs --project) ==' -ForegroundColor Cyan

if (-not (Test-Path -LiteralPath $Exe -PathType Leaf)) {
  Write-Host "  [FAIL] engine not found: $Exe" -ForegroundColor Red
  Write-Host 'PROJECT DB RESOLVE: FAIL' -ForegroundColor Red
  exit 1
}

# --- fixture ---------------------------------------------------------------
# Two projects in ONE folder is the whole point; Gamma is present on disk and
# inside the folder section's tree but named by no project section; Delta is
# deliberately claimed by two sections.
if (Test-Path -LiteralPath $WorkDir) { Remove-Item -LiteralPath $WorkDir -Recurse -Force }
$shared = Join-Path $WorkDir 'shared'
New-Item -ItemType Directory -Path $shared -Force | Out-Null
foreach ($p in 'Alpha', 'Beta', 'Gamma', 'Delta') {
  Set-Content -LiteralPath (Join-Path $shared "$p.dproj") -Value '<Project/>' -Encoding Ascii
}

$sharedJson = $shared.Replace('\', '\\')
$outJson    = $WorkDir.Replace('\', '\\')
$manifest   = @"
{
  "settings": { "defaultPlatform": "Win64" },
  "indexes": {
    "outDir": "$outJson",
    "sections": [
      { "name": "Union", "db": "Union.sqlite", "include": ["$sharedJson"] },
      { "name": "Alpha", "db": "Alpha.sqlite", "include": ["$sharedJson\\Alpha.dproj"] },
      { "name": "Beta",  "db": "Beta.sqlite",  "include": ["$sharedJson\\Beta.dproj"] },
      { "name": "DupOne", "db": "DupOne.sqlite", "include": ["$sharedJson\\Delta.dproj"] },
      { "name": "DupTwo", "db": "DupTwo.sqlite", "include": ["$sharedJson\\Delta.dproj"] }
    ]
  }
}
"@
$cfg = Join-Path $WorkDir 'drag-lint.json'
Set-Content -LiteralPath $cfg -Value $manifest -Encoding Ascii

function Resolve-Project([string]$ProjPath, [switch]$Json) {
  $out = Join-Path $WorkDir 'out.txt'
  $err = Join-Path $WorkDir 'err.txt'
  $a = @('resolve-dbs', '--project', $ProjPath, '--config', $cfg)
  if ($Json) { $a += '--json' }
  $p = Start-Process -FilePath $Exe -ArgumentList $a -NoNewWindow -Wait -PassThru `
         -RedirectStandardOutput $out -RedirectStandardError $err
  # Cast to [string]: Get-Content -Raw yields $null for an EMPTY file, and an
  # empty stdout is exactly what the refusal cases produce. Left uncast, the
  # -like comparisons below return an empty array rather than a Boolean and the
  # Check parameter binding blows up -- turning a passing assertion into a
  # script crash.
  [pscustomobject]@{
    Exit   = $p.ExitCode
    Stdout = [string](Get-Content -LiteralPath $out -Raw -ErrorAction SilentlyContinue)
    Stderr = [string](Get-Content -LiteralPath $err -Raw -ErrorAction SilentlyContinue)
  }
}

# --- 1/2: siblings in one folder each get their OWN db ---------------------
$a = Resolve-Project (Join-Path $shared 'Alpha.dproj')
Check 'Alpha.dproj exits 0' ($a.Exit -eq 0) "exit=$($a.Exit) $($a.Stderr)"
Check 'Alpha.dproj resolves to Alpha.sqlite' ($a.Stdout.Trim() -like '*Alpha.sqlite') $a.Stdout.Trim()

$b = Resolve-Project (Join-Path $shared 'Beta.dproj')
Check 'Beta.dproj exits 0' ($b.Exit -eq 0) "exit=$($b.Exit) $($b.Stderr)"
# THE regression assertion: folder-prefix matching returns Union (or Alpha) here.
Check 'Beta.dproj resolves to its OWN db, not the first section in the folder' `
  ($b.Stdout.Trim() -like '*Beta.sqlite') $b.Stdout.Trim()
Check 'the folder section (Union) did not capture either project' `
  (($a.Stdout -notlike '*Union.sqlite*') -and ($b.Stdout -notlike '*Union.sqlite*')) ''

# --- 3: unmatched project resolves to NOTHING, no fallback -----------------
$g = Resolve-Project (Join-Path $shared 'Gamma.dproj')
Check 'unmatched project exits 2' ($g.Exit -eq 2) "exit=$($g.Exit)"
Check 'unmatched project prints NO db on stdout' ([string]::IsNullOrWhiteSpace($g.Stdout)) $g.Stdout
Check 'unmatched project does NOT fall back to the folder section db' `
  ($g.Stdout -notlike '*Union.sqlite*') ''
Check 'unmatched project explains itself on stderr' ($g.Stderr -like '*no manifest section includes*') $g.Stderr.Trim()

# --- 4: ambiguity is REFUSED, and names the claimants ----------------------
$d = Resolve-Project (Join-Path $shared 'Delta.dproj')
Check 'doubly-claimed project exits 2' ($d.Exit -eq 2) "exit=$($d.Exit)"
Check 'doubly-claimed project prints NO db on stdout' ([string]::IsNullOrWhiteSpace($d.Stdout)) $d.Stdout
Check 'doubly-claimed project names BOTH claiming sections' `
  (($d.Stderr -like '*DupOne*') -and ($d.Stderr -like '*DupTwo*')) $d.Stderr.Trim()
Check 'doubly-claimed project refuses rather than picking one' `
  (($d.Stderr -like '*refusing*') -and ($d.Stdout -notlike '*DupOne.sqlite*')) ''

# --- 5: path normalisation -------------------------------------------------
$weird = Join-Path $shared 'sub\..\ALPHA.DPROJ'
New-Item -ItemType Directory -Path (Join-Path $shared 'sub') -Force | Out-Null
$n = Resolve-Project $weird
Check 'match survives case differences and a ".." segment' `
  (($n.Exit -eq 0) -and ($n.Stdout.Trim() -like '*Alpha.sqlite')) "exit=$($n.Exit) $($n.Stdout.Trim())"

# --- 6b: READ resolution prefers the ACTIVE PROJECT ------------------------
# The read-side half of the same defect. A .pas can only be folder-matched, so
# with two projects in one folder every file there resolved to whichever section
# came first, regardless of what the developer had active. ORM3's COMMON\ units
# genuinely belong to two projects at once, so no rule keyed on the file alone
# can pick between them -- the active project is the tiebreak.
function Resolve-Read([string]$EditorFile, [string]$ProjPath) {
  $out = Join-Path $WorkDir 'rout.txt'
  $err = Join-Path $WorkDir 'rerr.txt'
  $a = @('resolve-dbs', '--in', $EditorFile, '--config', $cfg)
  if ($ProjPath) { $a += @('--project', $ProjPath) }
  $p = Start-Process -FilePath $Exe -ArgumentList $a -NoNewWindow -Wait -PassThru `
         -RedirectStandardOutput $out -RedirectStandardError $err
  $lines = @(Get-Content -LiteralPath $out -ErrorAction SilentlyContinue |
             Where-Object { $_.Trim() -ne '' })
  [pscustomobject]@{ Exit = $p.ExitCode; Lines = $lines }
}

# A source file in the SHARED folder -- folder-matchable only.
$sharedPas = Join-Path $shared 'Common.pas'
Set-Content -LiteralPath $sharedPas -Value 'unit Common;' -Encoding Ascii

$rAlpha = Resolve-Read $sharedPas (Join-Path $shared 'Alpha.dproj')
Check 'read: shared-folder .pas resolves to the ACTIVE project db FIRST' `
  (($rAlpha.Lines.Count -ge 1) -and ($rAlpha.Lines[0] -like '*Alpha.sqlite')) ($rAlpha.Lines -join ' | ')

$rBeta = Resolve-Read $sharedPas (Join-Path $shared 'Beta.dproj')
# THE assertion: same file, different active project, different primary db.
Check 'read: the SAME .pas follows the active project when it changes' `
  (($rBeta.Lines.Count -ge 1) -and ($rBeta.Lines[0] -like '*Beta.sqlite')) ($rBeta.Lines -join ' | ')

Check 'read: the folder db is KEPT as a fallback entry, not replaced' `
  ((($rAlpha.Lines -join ';') -like '*Union.sqlite*')) ($rAlpha.Lines -join ' | ')

# No active project -> unchanged folder behaviour.
$rNone = Resolve-Read $sharedPas $null
Check 'read: with NO active project it falls back to the folder db alone' `
  (($rNone.Lines.Count -eq 1) -and ($rNone.Lines[0] -like '*Union.sqlite')) ($rNone.Lines -join ' | ')

# Editor file OUTSIDE the active project entirely (browsing library source):
# the active project db still leads, and nothing regresses to empty.
$outside = Join-Path $WorkDir 'elsewhere\Lib.pas'
New-Item -ItemType Directory -Path (Split-Path $outside) -Force | Out-Null
Set-Content -LiteralPath $outside -Value 'unit Lib;' -Encoding Ascii
$rOut = Resolve-Read $outside (Join-Path $shared 'Alpha.dproj')
Check 'read: a file outside the active project still yields the project db' `
  (($rOut.Lines.Count -ge 1) -and ($rOut.Lines[0] -like '*Alpha.sqlite')) ($rOut.Lines -join ' | ')

$rOutNone = Resolve-Read $outside $null
Check 'read: outside file with no active project yields nothing (no bogus match)' `
  ($rOutNone.Lines.Count -eq 0) ($rOutNone.Lines -join ' | ')

# An AMBIGUOUS active project must not poison the read path -- it falls through
# to the folder rule (cosmetic there), unlike the write path which refuses.
$rAmb = Resolve-Read $sharedPas (Join-Path $shared 'Delta.dproj')
Check 'read: an ambiguous active project falls back to the folder db, not a refusal' `
  (($rAmb.Exit -eq 0) -and ($rAmb.Lines.Count -eq 1) -and ($rAmb.Lines[0] -like '*Union.sqlite')) `
  "exit=$($rAmb.Exit) $($rAmb.Lines -join ' | ')"

# --- 6c: ordering by real INDEX MEMBERSHIP ---------------------------------
# Everything above resolves from the manifest alone. This block asserts the part
# that depends on DB CONTENT: which index actually holds the open file.
#
# Why it matters: TDragLintStructureForm.ResolveDbForFile consumes ONE db (the
# first). "Consumers tolerate an extra db" is only true of consumers that read
# more than one -- that one reads Dbs[0] and gets silence, not an error, when the
# first entry does not contain the file. So these DBs are REAL, built by the real
# indexer, with real files rows.
$memDir = Join-Path $WorkDir 'mem'
New-Item -ItemType Directory -Path $memDir -Force | Out-Null
Set-Content -LiteralPath (Join-Path $memDir 'AlphaOnly.pas') `
  -Value "unit AlphaOnly;`r`ninterface`r`nimplementation`r`nend." -Encoding Ascii
Set-Content -LiteralPath (Join-Path $memDir 'BetaOnly.pas') `
  -Value "unit BetaOnly;`r`ninterface`r`nimplementation`r`nend." -Encoding Ascii
Set-Content -LiteralPath (Join-Path $memDir 'Shared.pas') `
  -Value "unit Shared;`r`ninterface`r`nimplementation`r`nend." -Encoding Ascii
Set-Content -LiteralPath (Join-Path $memDir 'Stranger.pas') `
  -Value "unit Stranger;`r`ninterface`r`nimplementation`r`nend." -Encoding Ascii
foreach ($p in 'PA', 'PB') {
  Set-Content -LiteralPath (Join-Path $memDir "$p.dproj") -Value '<Project/>' -Encoding Ascii
}

$dbA = Join-Path $WorkDir 'PA.sqlite'
$dbB = Join-Path $WorkDir 'PB.sqlite'
# Single-FILE index walks give exact control over membership:
#   PA holds AlphaOnly + Shared;  PB holds BetaOnly + Shared;  neither holds Stranger.
foreach ($pair in @(@($dbA, 'AlphaOnly.pas'), @($dbA, 'Shared.pas'),
                    @($dbB, 'BetaOnly.pas'),  @($dbB, 'Shared.pas'))) {
  & $Exe index (Join-Path $memDir $pair[1]) --db $pair[0] *> $null
}
Check 'membership fixture: both project DBs were built' `
  ((Test-Path -LiteralPath $dbA) -and (Test-Path -LiteralPath $dbB)) ''

# TWO manifests, differing only in SECTION ORDER. Not fixture padding -- it is
# forced by the shape of the thing under test, in two ways worth stating:
#
#   1. ResolveReadDbs offers exactly two candidates: the ACTIVE project's db and
#      the FOLDER-matched db. The non-active sibling's db is only ever reachable
#      as the folder match. (A real limitation, recorded in the task report:
#      with three siblings in one folder the third is never a candidate at all.)
#   2. Both sibling .dproj includes fold to the SAME folder, so the folder rule's
#      longest-prefix comparison is a tie and its strict '>' keeps the FIRST
#      section. Which sibling is the folder match is therefore decided by
#      declaration order -- so swapping the order is what swaps the candidate.
#
# Hence: PA-first exercises "PA is the folder match", PB-first the mirror image.
function New-MemManifest([string]$Tag, [string]$First, [string]$Second) {
  $j = @"
{
  "settings": { "defaultPlatform": "Win64" },
  "indexes": {
    "outDir": "$outJson",
    "sections": [
      { "name": "$First",  "db": "$First.sqlite",  "include": ["$($memDir.Replace('\','\\'))\\$First.dproj"] },
      { "name": "$Second", "db": "$Second.sqlite", "include": ["$($memDir.Replace('\','\\'))\\$Second.dproj"] }
    ]
  }
}
"@
  $path = Join-Path $WorkDir "mem-$Tag.json"
  Set-Content -LiteralPath $path -Value $j -Encoding Ascii
  $path
}
$memCfgA = New-MemManifest 'a' 'PA' 'PB'   # folder match -> PA
$memCfgB = New-MemManifest 'b' 'PB' 'PA'   # folder match -> PB

function Resolve-Mem([string]$EditorFile, [string]$ProjPath, [string]$Cfg) {
  $out = Join-Path $WorkDir 'mout.txt'
  $err = Join-Path $WorkDir 'merr.txt'
  $a = @('resolve-dbs', '--in', $EditorFile, '--config', $Cfg)
  if ($ProjPath) { $a += @('--project', $ProjPath) }
  $p = Start-Process -FilePath $Exe -ArgumentList $a -NoNewWindow -Wait -PassThru `
         -RedirectStandardOutput $out -RedirectStandardError $err
  ,@(Get-Content -LiteralPath $out -ErrorAction SilentlyContinue |
     Where-Object { $_.Trim() -ne '' })
}

# THE assertion: AlphaOnly.pas is in PA only. With PB ACTIVE, PA must lead
# anyway, because PB does not contain the file at all. Pre-fix: PB led.
$mA = Resolve-Mem (Join-Path $memDir 'AlphaOnly.pas') (Join-Path $memDir 'PB.dproj') $memCfgA
Check 'membership: the db that CONTAINS the file leads, even when the other project is active' `
  (($mA.Count -ge 1) -and ($mA[0] -like '*PA.sqlite')) ($mA -join ' | ')

# The same swap the other way round, so the assertion cannot be passing by
# accident of ordering.
$mB = Resolve-Mem (Join-Path $memDir 'BetaOnly.pas') (Join-Path $memDir 'PA.dproj') $memCfgB
Check 'membership: and symmetrically the other way round' `
  (($mB.Count -ge 1) -and ($mB[0] -like '*PB.sqlite')) ($mB -join ' | ')

# Tie: Shared.pas is in BOTH dbs -> the ACTIVE project breaks it. Both spellings,
# so each case really has two holders to choose between.
$mT1 = Resolve-Mem (Join-Path $memDir 'Shared.pas') (Join-Path $memDir 'PB.dproj') $memCfgA
Check 'membership tie: a file in BOTH dbs resolves to the ACTIVE project (PB)' `
  (($mT1.Count -eq 2) -and ($mT1[0] -like '*PB.sqlite')) ($mT1 -join ' | ')
$mT2 = Resolve-Mem (Join-Path $memDir 'Shared.pas') (Join-Path $memDir 'PA.dproj') $memCfgB
Check 'membership tie: same file, other project active, other db (PA)' `
  (($mT2.Count -eq 2) -and ($mT2[0] -like '*PA.sqlite')) ($mT2 -join ' | ')

# No holder: nothing contains Stranger.pas -> order untouched, list not shortened
# (this is the library-source case that must not regress).
$mN = Resolve-Mem (Join-Path $memDir 'Stranger.pas') (Join-Path $memDir 'PB.dproj') $memCfgA
Check 'membership: with NO db containing the file, the active-project order is unchanged' `
  (($mN.Count -eq 2) -and ($mN[0] -like '*PB.sqlite')) ($mN -join ' | ')

Check 'membership: reordering is a permutation -- no candidate is dropped' `
  (($mA.Count -eq 2) -and ($mB.Count -eq 2)) "A=$($mA.Count) B=$($mB.Count)"

# --- 6: --json carries the section name ------------------------------------
$j = Resolve-Project (Join-Path $shared 'Alpha.dproj') -Json
$obj = $null
try { $obj = $j.Stdout | ConvertFrom-Json } catch { }
Check '--json emits an object with section + db' `
  (($null -ne $obj) -and ($obj.section -eq 'Alpha') -and ($obj.db -like '*Alpha.sqlite')) $j.Stdout.Trim()

Remove-Item -LiteralPath $WorkDir -Recurse -Force -ErrorAction SilentlyContinue

Write-Host ''
if ($script:Failed) { Write-Host 'PROJECT DB RESOLVE: FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'PROJECT DB RESOLVE: PASS' -ForegroundColor Green
exit 0
