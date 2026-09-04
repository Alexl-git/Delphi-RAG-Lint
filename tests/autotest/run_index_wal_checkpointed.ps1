<#
  run_index_wal_checkpointed.ps1 -- a COMPLETED index run must leave a database
  that is self-contained in the .sqlite file, without its -wal / -shm sidecars.

  WHY THIS EXISTS. `5e4d6c6` made a FOLDER target invalid against a PROJECT
  database, because a folder scan adopts every loose .pas beneath the folder and
  then makes that widened set the database's own scope (measured: DataCopy
  39 -> 72 files, 393 -> 1123 findings). The database knows which kind it is from
  `scan_type` in schema_meta.

  That protection was NON-DURABLE ACROSS AN ORDINARY FILE COPY. Everything a run
  writes -- the fingerprints and `scan_type` among it -- can still be sitting in
  the write-ahead log when the run finishes. Copy the .sqlite alone to back it
  up, share it, stage it or A/B it, and it silently degrades to UNKNOWN, where a
  folder scan is NOT refused. Absence of the stamp is read as "this database
  predates the stamp", which is the "a MISSING stamp is STALE, not fresh"
  failure this repo has recorded before.

  >>> WHY THE OBVIOUS FIXTURE IS VACUOUS, AND WHY THIS ONE USES --watch.

  MEASURED 2026-09-03 before writing a line of the fix. A plain one-shot
  `index --project X --db Y` leaves NO -wal at all: SQLite checkpoints when the
  last connection closes, and the engine closes it. A guard that indexed, copied
  and asserted would therefore have passed against the UNFIXED build and pinned
  nothing whatsoever.

  The hazard is a completed run whose PROCESS DOES NOT CLOSE STRAIGHT AFTER --
  `--watch`, an orphaned or killed engine, a resident LSP holding the same
  database, or any copy taken while `index --all` is still working through its
  other sections. `--watch` is the one shape a headless test can hold open
  deliberately, so that is what this fixture uses.

  MEASURED in that shape, unfixed: after the run had finished AND stamped, the
  main file was 8 KB and the -wal was 758 KB. A .sqlite-only copy carried no
  scan_type and no `files` rows at all, and `index <dir> --db <copy>` exited 0
  instead of 2.

  RED-CHECK: against an engine without TSQLiteSymbolStore.Checkpoint, cases
  2, 3 and 4 fail. Verified by running this guard against the deployed build
  before the fix was built.

  THE CONTROLS MATTER MORE THAN THE ASSERTIONS.
  * Control A -- the LIVE database (sidecars present) must still refuse. Without
    it, a guard that "passes" because the refusal itself broke looks identical
    to one that passes because the checkpoint works.
  * Control B -- a ONE-SHOT run's copy must refuse too. That passed before the
    fix and must keep passing: it records that the one-shot path was never the
    hazard, so nobody can satisfy this guard by testing only that path.

  Run from a NEUTRAL CWD, pwsh 7.
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\draglint_wal_checkpoint",
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
  [System.IO.File]::WriteAllText($p, (($s -replace "`r`n", "`n") -replace "`n", "`r`n"),
                                 (New-Object System.Text.UTF8Encoding($false)))
}

if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
$Exe = (Resolve-Path $Exe).Path

function ScanTypeOf($db) {
  $j = (& $Exe sql --query "SELECT value FROM schema_meta WHERE key='scan_type'" --db $db --json 2>$null) -join "`n"
  if ($j -match '"rows"\s*:\s*\[\s*\[\s*"([^"]*)"') { return $Matches[1] }
  return ''
}
function FileCountOf($db) {
  $j = (& $Exe sql --query 'SELECT COUNT(*) AS n FROM files' --db $db --json 2>$null) -join "`n"
  if ($j -match '"rows"\s*:\s*\[\s*\[\s*(\d+)') { return [int]$Matches[1] }
  return -1
}

if (Test-Path $WorkDir) { Remove-Item $WorkDir -Recurse -Force -ErrorAction SilentlyContinue }
New-Item -ItemType Directory -Force -Path (Join-Path $WorkDir 'proj\_D-RAG') | Out-Null

# A project of TWO members plus a LOOSE unit in the same folder. The loose unit
# is what a folder scan would wrongly adopt, so it is what the refusal protects.
$proj = Join-Path $WorkDir 'proj'
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

Write-Host '== a completed index run leaves a self-contained .sqlite ==' -ForegroundColor Cyan

$db = Join-Path $proj '_D-RAG\App.sqlite'
$watcher = $null
try {
  # A COMPLETED run whose process stays resident. --interval is large so the
  # second tick never arrives while the guard is sampling.
  $watcher = Start-Process -FilePath $Exe `
      -ArgumentList @('index', '--project', (Join-Path $proj 'App.dpr'), '--db', $db, '--watch', '--interval', '600') `
      -PassThru -WindowStyle Hidden `
      -RedirectStandardOutput (Join-Path $WorkDir 'watch.out') `
      -RedirectStandardError  (Join-Path $WorkDir 'watch.err')

  # Completion signal: the engine's stdout is block-buffered and the process
  # never exits, so the 'Done.' trailer never reaches the redirect file --
  # measured. Read the database through its sidecars instead; the full member
  # set plus the stamp only appear once the walk and resolve have finished.
  $deadline = (Get-Date).AddSeconds(120)
  $ready = $false
  while ((Get-Date) -lt $deadline) {
    if ((FileCountOf $db) -eq 3 -and (ScanTypeOf $db) -ne '') { $ready = $true; break }
    Start-Sleep -Milliseconds 400
  }

  # 1. PRECONDITION, not a result. If this fails the rest is meaningless, and
  #    saying so is the difference between a red test and a misleading one.
  Check 'the resident run completed and stamped (read WITH sidecars)' $ready `
    'the watcher never reached 3 files + scan_type in 120 s -- the fixture did not run, so nothing below is evidence'

  if ($ready) {
    $liveN  = FileCountOf $db
    $liveSt = ScanTypeOf $db

    # CONTROL A -- the refusal itself must be alive. A broken refusal would make
    # every assertion below fail for the wrong reason.
    $outLive = (& $Exe index $proj --db $db 2>&1 | Out-String)
    $rcLive  = $LASTEXITCODE
    Check 'CONTROL A: the LIVE database (sidecars present) still refuses a folder' `
      (($rcLive -ne 0) -and ($outLive -match 'refusing to index a FOLDER')) `
      "exit=$rcLive -- if this is 0 the refusal is broken and the rest of this guard proves nothing"
    Check 'CONTROL A: and the live scope was not widened' ((FileCountOf $db) -eq $liveN) `
      "was $liveN, now $(FileCountOf $db)"

    # THE DEFECT: copy the .sqlite ALONE, exactly as a backup or a stage would.
    $copyDir = Join-Path $WorkDir 'copy'
    New-Item -ItemType Directory -Force -Path $copyDir | Out-Null
    $copy = Join-Path $copyDir 'App.sqlite'
    Copy-Item $db $copy -Force
    Check 'the copy really is sidecar-free (fixture integrity)' `
      (-not (Test-Path "$copy-wal")) 'a -wal came along, so this is not the copy the defect is about'

    # 2. the stamp survives the copy
    $stCopy = ScanTypeOf $copy
    Check 'the .sqlite-only copy carries scan_type=project' ($stCopy -eq 'project') `
      "got '$stCopy' -- RED means the stamp was stranded in the -wal (live said '$liveSt')"

    # 3. and so does the run's actual content -- the stamp is not a special case
    $nCopy = FileCountOf $copy
    Check 'the .sqlite-only copy carries the indexed rows' ($nCopy -eq $liveN) `
      "copy=$nCopy live=$liveN -- RED means the whole run was stranded, not just the stamp"

    # 4. the consequence that matters: the protection still works on the copy
    $outCopy = (& $Exe index $proj --db $copy 2>&1 | Out-String)
    $rcCopy  = $LASTEXITCODE
    Check 'a FOLDER into the copied project DB is still refused' ($rcCopy -ne 0) `
      "exit=$rcCopy -- 0 means a plain file copy disarmed the folder-into-project refusal"
    Check 'and it did NOT report the database as unstamped' `
      (-not ($outCopy -match 'records no scan_type')) `
      'the copy was read as "predates the stamp", which is absence being taken for an answer'
  }
}
finally {
  if ($watcher) { Stop-Process -Id $watcher.Id -Force -ErrorAction SilentlyContinue }
}

# CONTROL B -- the ONE-SHOT path was never the hazard, and must not become one.
# This assertion passed BEFORE the fix. It is here so that a future change
# cannot satisfy this guard by only ever testing a run that exits.
$osDir = Join-Path $WorkDir 'oneshot'
New-Item -ItemType Directory -Force -Path (Join-Path $osDir '_D-RAG') | Out-Null
Copy-Item (Join-Path $proj 'uMemberA.pas') $osDir -Force
Copy-Item (Join-Path $proj 'uMemberB.pas') $osDir -Force
Copy-Item (Join-Path $proj 'uLooseNotAMember.pas') $osDir -Force
Copy-Item (Join-Path $proj 'App.dpr') $osDir -Force
$osDb = Join-Path $osDir '_D-RAG\App.sqlite'
& $Exe index --project (Join-Path $osDir 'App.dpr') --db $osDb 2>&1 | Out-Null
$osCopyDir = Join-Path $WorkDir 'oneshot-copy'
New-Item -ItemType Directory -Force -Path $osCopyDir | Out-Null
$osCopy = Join-Path $osCopyDir 'App.sqlite'
Copy-Item $osDb $osCopy -Force
$osOut = (& $Exe index $osDir --db $osCopy 2>&1 | Out-String)
$osRc  = $LASTEXITCODE
Check 'CONTROL B: a ONE-SHOT run''s .sqlite-only copy also still refuses' `
  (($osRc -ne 0) -and ($osOut -match 'refusing to index a FOLDER')) `
  "exit=$osRc -- this path checkpoints on close and passed before the fix too"

Write-Host ''
if ($script:fail) { Write-Host 'INDEX-WAL-CHECKPOINT GUARD: FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'INDEX-WAL-CHECKPOINT GUARD: PASS' -ForegroundColor Green
exit 0
