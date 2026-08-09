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
