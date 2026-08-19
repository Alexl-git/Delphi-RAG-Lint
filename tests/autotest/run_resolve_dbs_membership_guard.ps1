<#
  run_resolve_dbs_membership_guard.ps1 -- `resolve-dbs --in <file>` must answer
  from what the indexes CONTAIN, not from where the project file happens to sit.

  THE DEFECT THIS PINS (docs\INBOX-resolve-dbs-in-folder-match.md, 2026-08-18):

      drag-lint resolve-dbs --in C:\...\src\lsp\DRagLint.LSP.Server.pas
      -> nothing at all

  while the very DB that should have been named answers
  `query --name HandleHover` about that same file. Resolution came from
  ResolveReadDbs, which offers the active project's DB plus the section whose
  ROOTS contain the file's folder -- so a member unit living outside its
  .dproj's own folder matched nothing.

  WHY THAT IS WORSE THAN AN ERROR. CLAUDE.md instructs every session to resolve
  DB paths with this command rather than guess them, and states that a
  project's member units may live in several folders. An empty answer therefore
  reads as "no index covers this file" and sends the reader to Grep -- the
  exact fallback the index exists to remove. This repo is that shape:
  drag-lint.dproj sits in src\cli and pulls in src\lsp, src\core, src\resolver
  and a dozen more.

  WHY THIS FIXTURE AND NOT THE EXISTING ONE. run_project_db_resolve.ps1 already
  covers --in, and stayed green throughout the defect, because every file in
  its fixtures sits in the SAME FOLDER as the .dproj that claims it. That shape
  cannot distinguish "resolved by membership" from "resolved by folder". Here
  the project files live in SUBDIRECTORIES (app\, app2\) and the unit under
  test lives in a SIBLING folder (shared\), which is the shape that failed.

  Case C is the one that keeps the fix honest: a file NO index contains must
  still fall back to the folder rule, or library and third-party source
  browsing breaks.

  A DESIGN CONFLICT SETTLED HERE. The INBOX note proposed returning the holders
  ALONE. run_project_db_resolve.ps1 already contracts the opposite -- that this
  resolution is a PERMUTATION of the candidates and never a shorter list -- for
  the same library-source reason as case C, and implementing the note verbatim
  turned that existing guard red. Holders therefore LEAD rather than replace: a
  caller reading the first entry gets an index that can answer, and a caller
  reading the whole list loses nothing it used to be offered.

  RED PROOF (recorded 2026-08-18): run with
  -Exe third_party\dll-win64\drag-lint.exe (the pre-fix engine). Case A returns
  ONE line -- TreeWide.sqlite, the folder-wide index that does NOT contain the
  file -- while the two project indexes that do contain it are absent. So the
  pre-fix answer was not merely empty here; it was the wrong index, which is
  the more dangerous shape of the same bug.
#>

[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\draglint_resolvedbs_membership"
)

$ErrorActionPreference = 'Stop'
$script:Failed = $false

function Check([string]$n, [bool]$ok, [string]$d) {
  $s = if ($ok) { 'PASS' } else { 'FAIL' }
  $c = if ($ok) { 'Green' } else { 'Red' }
  Write-Host ("  [{0}] {1} {2}" -f $s, $n, $d) -ForegroundColor $c
  if (-not $ok) { $script:Failed = $true }
}

Write-Host 'run_resolve_dbs_membership_guard -- --in resolves by index membership, not by folder' -ForegroundColor Cyan

if (-not (Test-Path $Exe)) {
  Write-Host "FATAL: engine not found at $Exe" -ForegroundColor Red
  Write-Host 'FAIL' -ForegroundColor Red
  exit 1
}

if (Test-Path $WorkDir) { [System.IO.Directory]::Delete($WorkDir, $true) }
New-Item -ItemType Directory $WorkDir | Out-Null

# --- fixture ---------------------------------------------------------------
# THE SHAPE IS THE POINT: the project files sit in subdirectories of the tree
# they own, and the unit both of them use sits in a sibling folder.
#
#   root\shared\SharedHelper.pas   <- claimed by BOTH projects, in NEITHER folder
#   root\app\Main.pas   + DemoApp.dpr
#   root\app2\Other.pas + DemoApp2.dpr
#   root\loose\Orphan.pas          <- in no project at all
$root = Join-Path $WorkDir 'root'
foreach ($d in 'shared','app','app2','loose') { New-Item -ItemType Directory -Path (Join-Path $root $d) -Force | Out-Null }

function W([string]$path, [string[]]$lines) {
  [System.IO.File]::WriteAllText($path, (($lines -join "`r`n") + "`r`n"), [System.Text.Encoding]::ASCII)
}

W (Join-Path $root 'shared\SharedHelper.pas') @(
  'unit SharedHelper;', '', 'interface', '',
  'function SharedThing: Integer;', '', 'implementation', '',
  'function SharedThing: Integer;', 'begin', '  Result := 7;', 'end;', '', 'end.')

W (Join-Path $root 'app\Main.pas') @(
  'unit Main;', '', 'interface', '',
  'procedure RunApp;', '', 'implementation', '', 'uses', '  SharedHelper', '  ;', '',
  'procedure RunApp;', 'begin', '  SharedThing;', 'end;', '', 'end.')

W (Join-Path $root 'app\DemoApp.dpr') @(
  'program DemoApp;', '', '{$APPTYPE CONSOLE}', '', 'uses',
  "  SharedHelper in '..\shared\SharedHelper.pas',",
  "  Main in 'Main.pas';", '', 'begin', '  RunApp;', 'end.')

W (Join-Path $root 'app2\Other.pas') @(
  'unit Other;', '', 'interface', '',
  'procedure RunOther;', '', 'implementation', '', 'uses', '  SharedHelper', '  ;', '',
  'procedure RunOther;', 'begin', '  SharedThing;', 'end;', '', 'end.')

W (Join-Path $root 'app2\DemoApp2.dpr') @(
  'program DemoApp2;', '', '{$APPTYPE CONSOLE}', '', 'uses',
  "  SharedHelper in '..\shared\SharedHelper.pas',",
  "  Other in 'Other.pas';", '', 'begin', '  RunOther;', 'end.')

W (Join-Path $root 'loose\Orphan.pas') @('unit Orphan;', '', 'interface', '', 'implementation', '', 'end.')

$rootJson = $root.Replace('\','\\')
$outJson  = $WorkDir.Replace('\','\\')
# A folder-wide section as well, so case C has something for the folder rule to
# fall back TO. Without it, "no DB claims the file" and "no section covers the
# folder" would be indistinguishable and case C would prove nothing.
$manifest = @"
{
  "settings": { "defaultPlatform": "Win64" },
  "indexes": {
    "outDir": "$outJson",
    "sections": [
      { "name": "DemoApp",  "db": "DemoApp.sqlite",  "include": ["$rootJson\\app\\DemoApp.dpr"] },
      { "name": "DemoApp2", "db": "DemoApp2.sqlite", "include": ["$rootJson\\app2\\DemoApp2.dpr"] },
      { "name": "TreeWide", "db": "TreeWide.sqlite", "include": ["$rootJson"] }
    ]
  }
}
"@
$cfg = Join-Path $WorkDir 'drag-lint.json'
[System.IO.File]::WriteAllText($cfg, $manifest, [System.Text.Encoding]::ASCII)

# Membership is built FILE BY FILE, the same way run_project_db_resolve.ps1 does
# it. That is deliberate: what is under test here is the reverse mapping from a
# file to the indexes holding it, so the fixture states membership exactly
# rather than depending on the indexer's project-closure walk. (Handing `index`
# a bare .dpr indexes only the .dpr; closure comes from a .dproj, which is a
# different mechanism and a different test.)
#
#   DemoApp  holds Main.pas    + shared\SharedHelper.pas
#   DemoApp2 holds Other.pas   + shared\SharedHelper.pas   <- shared by both
#   TreeWide holds Orphan.pas only, so it EXISTS (TDbSelect drops a section
#            whose DB was never built) without containing the files in A and B.
foreach ($pair in @(
    @('DemoApp.sqlite' , 'app\Main.pas'),
    @('DemoApp.sqlite' , 'shared\SharedHelper.pas'),
    @('DemoApp2.sqlite', 'app2\Other.pas'),
    @('DemoApp2.sqlite', 'shared\SharedHelper.pas'),
    @('TreeWide.sqlite', 'loose\Orphan.pas'))) {
  & $Exe index (Join-Path $root $pair[1]) --db (Join-Path $WorkDir $pair[0]) *> $null
}

$dbA = Join-Path $WorkDir 'DemoApp.sqlite'
$dbB = Join-Path $WorkDir 'DemoApp2.sqlite'
$dbT = Join-Path $WorkDir 'TreeWide.sqlite'
Check 'fixture: all three indexes were built' `
  ((Test-Path $dbA) -and (Test-Path $dbB) -and (Test-Path $dbT)) ''

# Sanity: the shared unit really IS a member of both project indexes. If this
# fails the fixture is wrong and every assertion below is meaningless.
$qa = & $Exe query --name SharedThing --db $dbA 2>$null | Out-String
$qb = & $Exe query --name SharedThing --db $dbB 2>$null | Out-String
Check 'fixture: the sibling-folder unit is indexed in BOTH project DBs' `
  (($qa -match 'SharedThing') -and ($qb -match 'SharedThing')) 'membership is real, not assumed'

function Resolve-In([string]$File, [string]$Proj) {
  $a = @('resolve-dbs','--in',$File,'--config',$cfg)
  if ($Proj) { $a += @('--project',$Proj) }
  $o = Join-Path $WorkDir 'o.txt'
  $e = Join-Path $WorkDir 'e.txt'
  $p = Start-Process -FilePath $Exe -ArgumentList $a -NoNewWindow -Wait -PassThru -RedirectStandardOutput $o -RedirectStandardError $e
  ,@(Get-Content -LiteralPath $o -ErrorAction SilentlyContinue | Where-Object { $_.Trim() -ne '' })
}

# ---- CASE A: B2.1 -- the reported defect -----------------------------------
Write-Host ''
Write-Host 'CASE A: B2.1 a member unit OUTSIDE the project file''s folder' -ForegroundColor Cyan
$shared = Join-Path $root 'shared\SharedHelper.pas'
$a = Resolve-In $shared $null
Check 'it resolves to something at all' ($a.Count -ge 1) "got $($a.Count) line(s): $($a -join ' | ')"
Check 'B2.1 the project index that CONTAINS it is named' `
  (($a -join ';') -like '*DemoApp.sqlite*') ($a -join ' | ')

# ---- CASE B: B2.3 -- two projects, both genuinely holding the file ---------
Write-Host ''
Write-Host 'CASE B: B2.3 a unit shared by two projects lists BOTH' -ForegroundColor Cyan
Check 'B2.3 both holding indexes are listed' `
  ((($a -join ';') -like '*DemoApp.sqlite*') -and (($a -join ';') -like '*DemoApp2.sqlite*')) ($a -join ' | ')
# A holder must LEAD. The non-holder is deliberately still present: see the
# header note on the permutation contract -- this resolution reorders, it never
# shortens, because a shorter list is how library-source browsing breaks.
Check 'a holder leads the list' `
  (($a.Count -ge 1) -and (($a[0] -like '*DemoApp.sqlite*') -or ($a[0] -like '*DemoApp2.sqlite*'))) ($a -join ' | ')
Check 'the non-holding folder index is kept as a trailing fallback, not dropped' `
  (($a -join ';') -like '*TreeWide.sqlite*') ($a -join ' | ')

$aActive = Resolve-In $shared (Join-Path $root 'app2\DemoApp2.dpr')
Check 'the active project breaks the tie and leads' `
  (($aActive.Count -ge 1) -and ($aActive[0] -like '*DemoApp2.sqlite*')) ($aActive -join ' | ')

# ---- CASE C: B2.2 -- the folder fallback must survive ----------------------
Write-Host ''
Write-Host 'CASE C: B2.2 a file NO index contains still falls back to the folder rule' -ForegroundColor Cyan
# Written after the indexes were built, so nothing contains it, but it sits
# inside TreeWide's declared root.
$latecomer = Join-Path $root 'Latecomer.pas'
W $latecomer @('unit Latecomer;', '', 'interface', '', 'implementation', '', 'end.')
$c = Resolve-In $latecomer $null
Check 'B2.2 the folder-matched index still answers' `
  (($c -join ';') -like '*TreeWide.sqlite*') ($c -join ' | ')

# ---- CASE D: positive control ---------------------------------------------
Write-Host ''
Write-Host 'CASE D: positive control -- a file INSIDE the project folder still resolves' -ForegroundColor Cyan
# This case passed before the fix. It is here so a "fix" that replaced folder
# resolution with membership and broke the ordinary path cannot go green.
$d = Resolve-In (Join-Path $root 'app\Main.pas') $null
Check 'a unit in the project file''s own folder resolves to its index' `
  (($d -join ';') -like '*DemoApp.sqlite*') ($d -join ' | ')

Write-Host ''
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
