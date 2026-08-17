<#
  run_index_resume_per_file.ps1 -- an interrupted engine-change reindex RESUMES:
  the next run re-parses only the files the killed run never reached.

  THE PROBLEM. The indexer fingerprint was stored once for the WHOLE database,
  so an engine/schema/platform change meant "re-parse every file in scope" with
  no per-file memory. A Library[Win64] re-parse ran 12.5 HOURS, reached 4,748 of
  6,978 files, was stopped to apply a schema index -- and restarted from file 1.
  The information needed to resume had been computed and thrown away.

  THE FIX. files.indexed_at_fingerprint, stamped INSIDE the per-file transaction
  CommitFileTx closes. A run forced by a fingerprint change may then take the
  ordinary up-to-date skip for any file already stamped with the CURRENT
  fingerprint.

  WHY THE FIXTURE LOOKS LIKE THIS -- and why the shape written into
  PLAN-SESSION-23-IMPLEMENTATION.md section 5b DOES NOT WORK.

  That plan said: index a folder; index ONE file with --no-preprocess; index the
  folder with --no-preprocess; assert the third run parses exactly one file.
  Measured against the code, the second step ALSO commits the database-level
  fingerprint (DRagLint.CLI.pas, the ad-hoc index path calls
  CommitIndexerFingerprint once the walk finishes, for a single file just as for
  a folder). So by step three Prev = Cur, the run is NOT a fingerprint-change run
  at all, nothing is forced, and BOTH files take the plain incremental skip. The
  assertion would have read "skipped 2" and the positive control -- that step 3
  still announces "Indexer changed since this DB was built" -- would have failed.

  So the interrupted state is constructed explicitly instead: after the
  --no-preprocess single-file run, the DATABASE-level fingerprint is rolled back
  to a stale value by SQL. That is precisely the state a kill leaves behind --
  per-file stamps written, database-level stamp never updated (which is what
  session 22's CommitIndexerFingerprint split guarantees) -- and building it
  deterministically beats racing a Ctrl-C.

  STATED PLAINLY, because the plan asked for it: the REAL shape -- a process
  killed hours into a library walk -- is SIMULATED here, not reproduced. What is
  genuinely verified is the resume LOGIC over the exact database state such a
  kill produces.

  Usage: pwsh -File tests/autotest/run_index_resume_per_file.ps1 [-Exe <path>]
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\drag-lint-index-resume"
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
if (Test-Path $WorkDir) { Remove-Item -Recurse -Force $WorkDir }
New-Item -ItemType Directory $WorkDir | Out-Null

function Write-Ascii([string]$Path, [string]$Body) {
  $norm = $Body -replace "`r`n", "`n" -replace "`n", "`r`n"
  [System.IO.File]::WriteAllText($Path, $norm, [System.Text.Encoding]::ASCII)
}

$src = Join-Path $WorkDir 'src'
New-Item -ItemType Directory $src | Out-Null
foreach ($n in @('AlphaUnit', 'BetaUnit')) {
  Write-Ascii (Join-Path $src "$n.pas") @"
unit $n;

interface

type
  T$n = class(TObject)
  public
    procedure Run;
  end;

implementation

procedure T$n.Run;
begin
end;

end.
"@
}

$db = Join-Path $WorkDir 'resume.sqlite'

# --- Step 1: a normal, complete index. Both files stamped with the pp=1 engine. ---
Write-Host 'step 1 -- full index (preprocess ON)' -ForegroundColor Cyan
$o1 = @(& $Exe index $src --db $db --quiet 2>&1) | ForEach-Object { "$_" }
Check 'step 1 exits 0' ($LASTEXITCODE -eq 0) "$($o1 -join ' | ')"

# --- Probe. -----------------------------------------------------------------------
$py = Join-Path $WorkDir 'sql.py'
Write-Ascii $py @'
import sqlite3, sys
con = sqlite3.connect(sys.argv[1])
cur = con.execute(sys.argv[2])
rows = cur.fetchall()
if rows:
    print("\n".join("|".join("" if v is None else str(v) for v in r) for r in rows))
con.commit(); con.close()
'@
function Sql([string]$Q) { return ((python $py $db $Q) -join "`n").Trim() }

$stamped = Sql "SELECT COUNT(*) FROM files WHERE indexed_at_fingerprint IS NOT NULL"
Check 'precondition: both files carry a per-file fingerprint stamp' ($stamped -eq '2') `
  "stamped=$stamped -- if 0, CommitFileTx is not stamping and every assertion below is vacuous"

# --- Step 2: re-index ONE file under a DIFFERENT engine fingerprint (pp=0). --------
# This is the "completed prefix" of an interrupted run: AlphaUnit has now been
# parsed by the pp=0 engine, BetaUnit has not.
Write-Host ''
Write-Host 'step 2 -- one file re-indexed with --no-preprocess (the completed prefix)' -ForegroundColor Cyan
$o2 = @(& $Exe index (Join-Path $src 'AlphaUnit.pas') --db $db --no-preprocess --quiet 2>&1) | ForEach-Object { "$_" }
Check 'step 2 exits 0' ($LASTEXITCODE -eq 0) "$($o2 -join ' | ')"

$distinct = Sql "SELECT COUNT(DISTINCT indexed_at_fingerprint) FROM files"
Check 'precondition: the two files now carry DIFFERENT stamps' ($distinct -eq '2') `
  "distinct stamps=$distinct -- they must differ, or step 4 cannot discriminate and would pass for the wrong reason"

# --- Step 3: roll the DATABASE-level stamp back, i.e. "the run never finished". ----
# See the header: the plan's fixture omitted this and would have tested nothing.
Write-Host ''
Write-Host 'step 3 -- roll the DB-level fingerprint back (simulating the kill)' -ForegroundColor Cyan
Sql "INSERT OR REPLACE INTO schema_meta(key, value) VALUES ('indexer_fingerprint', 'v=0.0.0-interrupted;schema=1;pp=1;plat=win64')" | Out-Null
$fp = Sql "SELECT value FROM schema_meta WHERE key='indexer_fingerprint'"
Check 'precondition: the DB-level fingerprint now reads stale' ($fp -like 'v=0.0.0-interrupted*') "fp=$fp"

# --- Step 4: the resuming run. ----------------------------------------------------
Write-Host ''
Write-Host 'step 4 -- re-index the folder with --no-preprocess: it must RESUME' -ForegroundColor Cyan
$o4 = (@(& $Exe index $src --db $db --no-preprocess --quiet 2>&1) | ForEach-Object { "$_" }) -join "`n"
Check 'step 4 exits 0' ($LASTEXITCODE -eq 0) $o4

# POSITIVE CONTROL: this must genuinely be a forced, fingerprint-changed run.
# Without it, "skipped 1" could just mean the ordinary incremental skip ran and
# the resume path was never exercised at all.
Check 'POSITIVE CONTROL: step 4 still announces the indexer change' `
  ($o4 -match 'Indexer changed since this DB was built') `
  "$o4 -- if absent, this is a plain incremental run and the assertion below proves nothing about resume"

Check 'ASSERT: exactly ONE file was skipped as up-to-date' `
  ($o4 -match 'skipped 1 up-to-date') `
  "$o4 -- 0 means the stamp was ignored (no resume); 2 means an unstamped file was skipped, which is the silent-staleness failure"

Check 'ASSERT: the file NOT stamped with the current engine was re-parsed' `
  ($o4 -match 'BetaUnit\.pas ->') `
  "$o4 -- BetaUnit carries the pp=1 stamp, so a pp=0 run must re-parse it"

Check 'ASSERT: the already-current file was NOT re-parsed' `
  ($o4 -notmatch 'AlphaUnit\.pas ->') `
  "$o4 -- AlphaUnit already carries the pp=0 stamp; re-parsing it is the whole cost this change removes"

# --- Step 5: --force-reparse must NOT resume. -------------------------------------
# The flag means "ignore the skip". Honouring a stamp would silently disobey it,
# and this is the arm the written plan did not distinguish at all.
Write-Host ''
Write-Host 'step 5 -- --force-reparse must ignore the stamps entirely' -ForegroundColor Cyan
$o5 = (@(& $Exe index $src --db $db --no-preprocess --force-reparse --quiet 2>&1) | ForEach-Object { "$_" }) -join "`n"
Check 'ASSERT: --force-reparse skips NOTHING' `
  (($o5 -match 'skipped 0 up-to-date') -or ($o5 -notmatch 'skipped [1-9]')) `
  "$o5 -- a stamp must never override an explicit --force-reparse"
Check 'ASSERT: --force-reparse re-parsed BOTH files' `
  (($o5 -match 'AlphaUnit\.pas ->') -and ($o5 -match 'BetaUnit\.pas ->')) "$o5"

Write-Host ''
if ($script:Failed) { Write-Host 'RESULT: FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'RESULT: PASS' -ForegroundColor Green
exit 0
