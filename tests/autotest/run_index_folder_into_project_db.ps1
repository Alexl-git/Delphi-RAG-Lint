<#
  run_index_folder_into_project_db.ps1 -- a FOLDER target is valid only for a
  LIBRARY database. Indexing a folder into a PROJECT database must be refused.

  OWNER RULING, 2026-09-02: there are exactly two kinds of index. A LIBRARY
  scans every file under the folders it names. A PROJECT scans only a project's
  members -- which may span several folders, and which deliberately EXCLUDE
  loose .pas files parked among them.

  WHAT WENT WRONG WITHOUT THIS. `index <dir> --db <projectDb>` took the
  directory as the whole scope and added every .pas beneath it; out-of-scope
  eviction then set the in-scope set from the walk it had just done, so the
  widened set became the database's own definition of itself. Silent, and sticky
  until somebody happened to run a section rebuild.

  Measured TWICE on 2026-09-02, both from agents following the then-documented
  post-build recipe: DataCopy 39 -> 72 files (lint-all 393 -> 1123 findings over
  38 -> 70 files), and this repository's own self-index 198 -> 200.

  HOW THE DATABASE KNOWS. `scan_type` in schema_meta, written after any run that
  completes. For databases written before that key existed, the documented
  layout is the fallback: a project index lives in a `_D-RAG` folder beside its
  project file. Neither answering is NOT treated as "library" -- it proceeds
  with a NOTE, because reading an absent stamp as a positive answer is the
  failure recorded in auto-memory as "a MISSING stamp is STALE, not fresh".

  THE REFUSAL IS THE EASY HALF. The three positive controls matter more: this
  guard must fail if the refusal ever grows to cover the correct project form,
  an ordinary library scan, or a repeat library scan.

  RED-CHECK: against an engine built before the DoIndex refusal, case 2 exits 0
  and the file count rises.

  Run from a NEUTRAL CWD, pwsh 7.
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\draglint_folder_into_project",
  [switch]$Quiet
)
$ErrorActionPreference = 'Stop'
$script:fail = $false
function Check($n, $ok, $d) {
  if ($Quiet) { if (-not $ok) { $script:fail = $true }; return }
  Write-Host ("  [{0}] {1}" -f (@('FAIL', 'PASS')[[int]$ok]), $n) -ForegroundColor (@('Red', 'Green')[[int]$ok])
  if (-not $ok) { if ($d) { Write-Host "        $d" -ForegroundColor DarkGray }; $script:fail = $true }
}
function W($p, $s) {
  [System.IO.File]::WriteAllText($p, ($s -replace "`r`n", "`n" -replace "`n", "`r`n"),
                                 (New-Object System.Text.UTF8Encoding($false)))
}

if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
$Exe = (Resolve-Path $Exe).Path

# A project of TWO members, plus a LOOSE unit in the same folder that belongs to
# no project. The loose unit is the whole point: a project index must not hold
# it, and the folder form is what used to pull it in.
$proj = Join-Path $WorkDir 'proj'
$drag = Join-Path $proj '_D-RAG'
if (-not (Test-Path $drag)) { New-Item -ItemType Directory -Force -Path $drag | Out-Null }

W (Join-Path $proj 'uMemberA.pas') @'
unit uMemberA;
interface
procedure MemberAThing;
implementation
procedure MemberAThing;
begin
end;
end.
'@
W (Join-Path $proj 'uMemberB.pas') @'
unit uMemberB;
interface
procedure MemberBThing;
implementation
procedure MemberBThing;
begin
end;
end.
'@
W (Join-Path $proj 'uLooseNotAMember.pas') @'
unit uLooseNotAMember;
interface
procedure LooseThing;
implementation
procedure LooseThing;
begin
end;
end.
'@
W (Join-Path $proj 'App.dpr') @'
program App;
uses
  uMemberA in 'uMemberA.pas',
  uMemberB in 'uMemberB.pas';
begin
end.
'@

$projDb = Join-Path $drag 'App.sqlite'
if (Test-Path $projDb) { Remove-Item $projDb -Force -ErrorAction SilentlyContinue }

function FileCount($db) {
  $j = (& $Exe sql --query 'SELECT COUNT(*) AS n FROM files' --db $db --json 2>$null) -join "`n"
  $i = $j.IndexOf('{'); if ($i -lt 0) { return -1 }
  try { return [int](($j.Substring($i) | ConvertFrom-Json).rows[0][0]) } catch { return -1 }
}

Write-Host '== a folder target is valid only for a LIBRARY database ==' -ForegroundColor Cyan

# 1. POSITIVE CONTROL -- the correct project form must work, and must stamp.
& $Exe index --project (Join-Path $proj 'App.dpr') --db $projDb 2>&1 | Out-Null
$rc1 = $LASTEXITCODE
$n1  = FileCount $projDb
Check 'the project form succeeds' ($rc1 -eq 0) "exit=$rc1"
Check 'and indexes ONLY the members, not the loose unit' ($n1 -eq 3) `
  "expected 3 (App.dpr + 2 members), got $n1 -- if this is 4 the loose unit got in"

$st = (& $Exe sql --query "SELECT value FROM schema_meta WHERE key='scan_type'" --db $projDb --json 2>$null) -join "`n"
Check 'and records scan_type=project' ($st -match 'project') `
  'without the stamp the refusal below falls back to the _D-RAG heuristic'

# 2. THE DEFECT -- a folder into that project DB must be refused, and must not write.
$out2 = (& $Exe index $proj --db $projDb 2>&1 | Out-String)
$rc2  = $LASTEXITCODE
$n2   = FileCount $projDb
Check 'a FOLDER into a project DB is refused' ($rc2 -ne 0) "exit=$rc2 -- 0 means it indexed"
Check 'and says so in a message naming the right command' `
  (($out2 -match 'refusing to index a FOLDER') -and ($out2 -match '--project')) ''
Check 'and the database is UNCHANGED' ($n2 -eq $n1) `
  "was $n1, now $n2 -- the scope was widened, which is the defect itself"

# 3. POSITIVE CONTROLS -- the refusal must not spread.

# A SINGLE FILE TARGET IS NOT A FOLDER TARGET, and must still work. Refreshing
# one member after editing it is the ordinary incremental move, and IndexFile
# touches one row rather than walking and adopting a scope.
#
# This control exists because the first version of the refusal DID catch file
# targets, and this guard passed anyway -- it only ever tried folders. The
# battery found it: run_index_rebuild_recompile pollutes a project DB with one
# out-of-root FILE on purpose, and the refusal blocked the setup.
& $Exe index (Join-Path $proj 'uMemberA.pas') --db $projDb 2>&1 | Out-Null
$rcFile = $LASTEXITCODE
Check 'a single FILE into a project DB still works' ($rcFile -eq 0) `
  "exit=$rcFile -- refreshing one member is not a folder walk and must not be refused"
Check 'and it did not widen the scope' ((FileCount $projDb) -eq $n1) `
  "was $n1, now $(FileCount $projDb)"

$libDir = Join-Path $WorkDir 'lib'
if (-not (Test-Path $libDir)) { New-Item -ItemType Directory -Force -Path $libDir | Out-Null }
W (Join-Path $libDir 'uLibOne.pas') @'
unit uLibOne;
interface
implementation
end.
'@
$libDb = Join-Path $libDir 'lib.sqlite'
if (Test-Path $libDb) { Remove-Item $libDb -Force -ErrorAction SilentlyContinue }

& $Exe index $libDir --db $libDb 2>&1 | Out-Null
$rc3 = $LASTEXITCODE
Check 'a folder into a NEW database still works' ($rc3 -eq 0) "exit=$rc3"
$st3 = (& $Exe sql --query "SELECT value FROM schema_meta WHERE key='scan_type'" --db $libDb --json 2>$null) -join "`n"
Check 'and records scan_type=library' ($st3 -match 'library') ''

& $Exe index $libDir --db $libDb 2>&1 | Out-Null
Check 'and a REPEAT folder scan of a library DB still works' ($LASTEXITCODE -eq 0) `
  'RED here means the refusal caught library databases too'

# AN UNSTAMPED DATABASE IN A `_D-RAG` FOLDER MUST STILL PROCEED.
#
# The first version of this refusal treated a `_D-RAG` parent as proof of a
# project database. It is not -- `_D-RAG` says where a project DB LIVES, not how
# it was BUILT -- and NINE existing runners index a folder into a `_D-RAG`
# database on purpose, because that path is what the config anchor walk keys
# off. They all went red and this guard did not notice, because it never tried
# the combination. Absence of the stamp is not evidence of "project" any more
# than it is evidence of "library".
$anchorDir = Join-Path $WorkDir 'anchorlike\_D-RAG'
if (-not (Test-Path $anchorDir)) { New-Item -ItemType Directory -Force -Path $anchorDir | Out-Null }
W (Join-Path $WorkDir 'anchorlike\uAnchorOne.pas') @'
unit uAnchorOne;
interface
implementation
end.
'@
$anchorDb = Join-Path $anchorDir 'p.sqlite'
if (Test-Path $anchorDb) { Remove-Item $anchorDb -Force -ErrorAction SilentlyContinue }
& $Exe index (Join-Path $WorkDir 'anchorlike') --db $anchorDb 2>&1 | Out-Null
Check 'an UNSTAMPED db in a _D-RAG folder is NOT refused' ($LASTEXITCODE -eq 0) `
  'the _D-RAG path is a location convention, not proof of how the DB was built'

Write-Host ''
if ($script:fail) { Write-Host 'FOLDER-INTO-PROJECT-DB GUARD: FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'FOLDER-INTO-PROJECT-DB GUARD: PASS' -ForegroundColor Green
exit 0
