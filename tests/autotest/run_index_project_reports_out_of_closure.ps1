<#
  run_index_project_reports_out_of_closure.ps1 -- a PROJECT index must SAY when
  it holds rows outside its own compile closure, because it can neither refresh
  nor evict them and the advice it prints cannot clear them.

  THE DEFECT (docs\INBOX-project-db-permanently-stale.md, defect 1; re-measured
  2026-09-06 on this repo's own self-index: 81 of 199 rows, not the 18 the note
  estimated -- 54 src\delphi-plugin, 19 src\tools, 8 src\config).

  Two deliberate behaviours combine into one silent trap:

    * `index --project` walks the COMPILE CLOSURE. A row that is not a project
      member is never visited, so it is never refreshed.
    * `EvictOutOfScopeFiles` is bounded to ProjectScopeRoots -- the directories
      of the closure files plus the project dir -- and its own remark says why
      on purpose: another project's units, indexed into the same .sqlite from a
      directory this scope never mentions, "lie outside every root and are never
      considered". That protects a shared DB from having another project's rows
      silently deleted, and it is the right default.

  Both are correct. Together they make such rows IMMORTAL -- and the freshness
  sweep still COUNTS them, so the linter prints "N file(s) changed" for ever
  while the remedy it advises does nothing at all. A standing warning nobody can
  clear is worse than no warning: it teaches the reader to skim every freshness
  note, including the ones that matter.

  THE FIX IS TO REPORT, NOT TO DELETE. Evicting them would reverse a documented
  protection and move the lint-all denominator, which is the owner's call and is
  recorded as such in the note. So `index --project` now names the count, and
  stamps it into schema_meta so the freshness note can be honest about what
  --project is actually able to fix.

  WHAT THIS ASSERTS -- three of six are controls, because "a scope line appears"
  on its own also passes for a build that prints it unconditionally, for one
  that counts the closure itself, and against a library DB where the whole
  concept does not apply.

    1. two projects sharing ONE .sqlite -> `index --project P1` reports P1's
       non-members as outside the closure                      <- THE FIX
    2. the count is exactly P2's file count, not "everything not just walked"
    3. the freshness note tells the reader --project CANNOT clear it, and names
       --rebuild                                               <- THE FIX
    4. CONTROL: P1's OWN files -- including its sibling .dfm, which is in the
       closure without being named in the .dpr -- are NOT reported. A fix that
       counted "files the walk did not parse this run" would fail here.
    5. CONTROL: a single-project DB reports NOTHING. Silence on a correct
       corpus is the whole point; a line per run would be the same noise defect
       in a new place.
    6. CONTROL: a LIBRARY-scanned DB reports nothing either -- the closure
       concept does not exist there and a folder scan legitimately holds every
       file it walked.

  RED-CHECK (performed 2026-09-06 against the pre-fix build): cases 1, 2 and 3
  FAIL -- no `scope:` line is emitted at all and the freshness note stops after
  its "refresh it with: index --project" sentence -- while 4, 5 and 6 PASS,
  since they assert absence and absence was the pre-fix behaviour everywhere.
  That asymmetry is the point: the controls cannot distinguish the builds, so
  they are controls and not evidence.
#>
[CmdletBinding()]
param(
  [string]$Exe = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe"
)
$ErrorActionPreference = 'Stop'
$script:Failed = $false
function Check($n, $ok, $d = '') {
  $s = if ($ok) { 'PASS' } else { 'FAIL' }
  $c = if ($ok) { 'Green' } else { 'Red' }
  Write-Host ("  [{0}] {1} {2}" -f $s, $n, $d) -ForegroundColor $c
  if (-not $ok) { $script:Failed = $true }
}

if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
$Exe = (Resolve-Path $Exe).Path

function Write-Ascii([string]$path, [string]$text) {
  $dir = Split-Path -Parent $path
  if (-not (Test-Path $dir)) { New-Item -ItemType Directory $dir -Force | Out-Null }
  [System.IO.File]::WriteAllText($path, ($text -replace "`r?`n", "`r`n"), [System.Text.Encoding]::ASCII)
}

# Capture through ONE OS handle. This runner reads a stderr note (the freshness
# banner) and stdout (the scope line) from the same run, and PowerShell's
# `2>&1 |` merges two pipes in DRAIN order -- measured at about a 10% reorder
# rate in run_index_all_failed_section_summary.ps1. Ordering is not asserted
# here, but reading both streams reliably still argues for one handle.
$work = Join-Path C:\TEMP 'draglint_outofclosure'
if (Test-Path $work) { Get-ChildItem $work -Recurse -Force | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue }
New-Item -ItemType Directory $work -Force | Out-Null

function RunCap([string[]]$ArgList) {
  $log = Join-Path $work ('run-{0}.log' -f [guid]::NewGuid().ToString('N').Substring(0,8))
  $quoted = ($ArgList | ForEach-Object { '"' + $_ + '"' }) -join ' '
  cmd /c "`"$Exe`" $quoted > `"$log`" 2>&1" | Out-Null
  $code = $LASTEXITCODE
  $txt = if (Test-Path -LiteralPath $log) { Get-Content -LiteralPath $log -Raw } else { '' }
  if ($null -eq $txt) { $txt = '' }
  return @{ Out = $txt; Code = $code }
}

# ---------------------------------------------------------------------------
# Two independent projects, each in its own folder, sharing ONE database.
#
# P1 carries a sibling .dfm and a {$I} include deliberately: both are in the
# compile closure WITHOUT being named in the .dpr, so a fix that mistook
# "named in the project file" for "in the closure" would report them and fail
# control 4.
# ---------------------------------------------------------------------------
$aDir = Join-Path $work 'a'
$bDir = Join-Path $work 'b'

Write-Ascii (Join-Path $aDir 'P1.dpr') @'
program P1;

uses
  UnitA1 in 'UnitA1.pas';

begin
end.
'@

Write-Ascii (Join-Path $aDir 'UnitA1.pas') @'
unit UnitA1;

interface

{$I A1Inc.inc}

type
  TFormA1 = class
  public
    procedure DoA1;
  end;

implementation

procedure TFormA1.DoA1;
begin
end;

end.
'@

Write-Ascii (Join-Path $aDir 'A1Inc.inc') @'
{ an include pulled in by UnitA1 -- in the closure, not named in the .dpr }
'@

Write-Ascii (Join-Path $aDir 'UnitA1.dfm') @'
object FormA1: TFormA1
  Caption = 'A1'
end
'@

Write-Ascii (Join-Path $bDir 'P2.dpr') @'
program P2;

uses
  UnitB1 in 'UnitB1.pas';

begin
end.
'@

Write-Ascii (Join-Path $bDir 'UnitB1.pas') @'
unit UnitB1;

interface

type
  TThingB1 = class
  public
    procedure DoB1;
  end;

implementation

procedure TThingB1.DoB1;
begin
end;

end.
'@

$db = Join-Path $work 'x.sqlite'
$p1 = Join-Path $aDir 'P1.dpr'
$p2 = Join-Path $bDir 'P2.dpr'

Write-Host ''
Write-Host '=== seeding: P2 then P1, both --project, into ONE db ===' -ForegroundColor Cyan
# Two PROJECT scans into one DB are not refused -- only folder-into-project is.
# That is exactly how a real DB acquires another project's rows.
$seed2 = RunCap @('index','--project',$p2,'--db',$db)
Check 'seed: P2 indexes into the shared db' ($seed2.Code -eq 0) "exit=$($seed2.Code)"
$seed1 = RunCap @('index','--project',$p1,'--db',$db)
Check 'seed: P1 indexes into the same db' ($seed1.Code -eq 0) "exit=$($seed1.Code)"

Write-Host ''
Write-Host '=== case 1-2: index --project P1 reports P2''s rows as out-of-closure ===' -ForegroundColor Cyan
$again = RunCap @('index','--project',$p1,'--db',$db)
Write-Host $again.Out -ForegroundColor DarkGray

$scopeLine = (($again.Out -split "`r?`n") | Where-Object { $_ -match '^scope: \d+ indexed file\(s\) are outside' })
Check '1. a scope line names rows outside the compile closure' `
  ($null -ne $scopeLine -and @($scopeLine).Count -ge 1) `
  'pre-fix build prints no scope line at all'

if (@($scopeLine).Count -ge 1) {
  $n = 0
  if (@($scopeLine)[0] -match '^scope: (\d+) ') { $n = [int]$Matches[1] }
  # P2 contributes its .dpr + its one unit = 2 rows. Asserting the exact number
  # is what separates "reports the right rows" from "reports something".
  Check '2. the count is exactly P2''s two files' ($n -eq 2) "count=$n"
  Check '2b. and the sample NAMES a P2 file' `
    ((@($again.Out -split "`r?`n") -match 'UnitB1|P2\\.dpr').Count -ge 1) `
    'the listed sample must come from the other project'
}

Write-Host ''
Write-Host '=== case 4: CONTROL -- P1''s own closure files are NOT reported ===' -ForegroundColor Cyan
# UnitA1.dfm and A1Inc.inc are in the closure but are NOT named in P1.dpr. A fix
# that equated "in the closure" with "listed in the project file" would name
# them here, and a fix that reported "files not parsed this run" would name
# every up-to-date file.
$outTail = $again.Out
$scopeBlock = ''
$m = [regex]::Match($outTail, '(?ms)^scope: \d+ indexed file\(s\) are outside.*?(?=^\S|\z)')
if ($m.Success) { $scopeBlock = $m.Value }
# EXTRACTION CONTROL FIRST. The three absence checks below are worthless if
# $scopeBlock does not actually contain the sample lines -- an extraction that
# returned the header alone, or '', would pass all three while asserting
# nothing. So prove the block can see a name before trusting it not to see one.
Check '4-pre. CONTROL: the extracted scope block really contains its samples' `
  ($scopeBlock -match 'UnitB1|P2\\.dpr') `
  'without this, the three absence checks below are fail-open'
Check '4. CONTROL: P1''s sibling .dfm is NOT reported as out-of-closure' `
  (-not ($scopeBlock -match 'UnitA1\.dfm')) "block=$scopeBlock"
Check '4b. CONTROL: P1''s {$I} include is NOT reported as out-of-closure' `
  (-not ($scopeBlock -match 'A1Inc\.inc')) "block=$scopeBlock"
Check '4c. CONTROL: P1''s own unit is NOT reported as out-of-closure' `
  (-not ($scopeBlock -match 'UnitA1\.pas')) "block=$scopeBlock"

Write-Host ''
Write-Host '=== case 3: the freshness note admits --project cannot clear it ===' -ForegroundColor Cyan
# Touch P2's unit so the sweep sees a CHANGED file that P1's walk can never
# refresh -- the note's literal symptom.
Start-Sleep -Milliseconds 1100
$b1 = Join-Path $bDir 'UnitB1.pas'
Write-Ascii $b1 ((Get-Content -LiteralPath $b1 -Raw) + "`r`n{ touched }`r`n")
$lint = RunCap @('lint',(Join-Path $aDir 'UnitA1.pas'),'--db',$db)
Write-Host $lint.Out -ForegroundColor DarkGray
Check '3. the note says --project CANNOT clear the out-of-closure rows' `
  ($lint.Out -match 'lie OUTSIDE this project.s compile closure') `
  'pre-fix the note stops after "refresh it with: index --project"'
Check '3b. and it names --rebuild as the remedy that does work' `
  ($lint.Out -match '--rebuild') 'the only command that can drop these rows'

Write-Host ''
Write-Host '=== case 5: CONTROL -- a single-project db says nothing ===' -ForegroundColor Cyan
$dbSolo = Join-Path $work 'solo.sqlite'
$solo1 = RunCap @('index','--project',$p1,'--db',$dbSolo)
Check 'solo: indexes' ($solo1.Code -eq 0) "exit=$($solo1.Code)"
$solo2 = RunCap @('index','--project',$p1,'--db',$dbSolo)
Check '5. CONTROL: a correct project db prints NO scope line' `
  (-not ($solo2.Out -match '^scope: \d+ indexed file\(s\) are outside')) `
  "out=$($solo2.Out)"
$soloLint = RunCap @('lint',(Join-Path $aDir 'UnitA1.pas'),'--db',$dbSolo)
Check '5b. CONTROL: and its freshness note carries no out-of-closure sentence' `
  (-not ($soloLint.Out -match 'lie OUTSIDE this project')) "out=$($soloLint.Out)"

Write-Host ''
Write-Host '=== case 6: CONTROL -- a LIBRARY db is unaffected ===' -ForegroundColor Cyan
# A folder scan legitimately holds every file it walked; the compile-closure
# concept does not apply, so nothing new may be said about it.
$dbLib = Join-Path $work 'lib.sqlite'
$lib1 = RunCap @('index',$aDir,'--db',$dbLib)
Check 'lib: folder scan indexes' ($lib1.Code -eq 0) "exit=$($lib1.Code)"
$lib2 = RunCap @('index',$aDir,'--db',$dbLib)
Check '6. CONTROL: a library db prints NO out-of-closure scope line' `
  (-not ($lib2.Out -match 'are outside this project')) "out=$($lib2.Out)"

Write-Host ''
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'PASS' -ForegroundColor Green
exit 0
