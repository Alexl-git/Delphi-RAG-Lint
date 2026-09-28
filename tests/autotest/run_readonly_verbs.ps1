# drag-lint read-only-verb regression test (v0.86, Task 4).
#
# Read-looking verbs (outline, query, surface, context, dump-refs, find-unit)
# must NOT mutate the index. Before this task every read verb called Migrate,
# whose FTS5 probe / stamp / DROP-TRIGGER block issues DDL on the shared DB
# (the win32 trigger-drop bug + general DDL-on-read). The mutation sentinel is
# the DB file's md5 AND the trigger count in sqlite_master: a pure read must
# leave both byte-identical.
#
# Also asserts a pre-current (v12-shaped) DB gets an ACTIONABLE stale-schema
# message + nonzero exit from a read verb (outline), NOT a "no such column"
# field error.
#
# THE MESSAGE CHANGED IN 5080478 AND THIS ASSERTION DID NOT, so it failed
# against a CORRECT build. It used to demand the single sentence
#   index schema v12 < v<N>: run "drag-lint index <dir> --db <db>" to migrate
# but a bare folder target is refused against a PROJECT database since 5e4d6c6
# (exit 2, "refusing to index a FOLDER into a PROJECT database"). So the engine
# now names BOTH forms, and a v12 DB is exactly the case where it cannot know
# which kind it is looking at -- it predates the scan_type stamp.
#
# The assertion is therefore on SUBSTANCE, not on a sentence: the line must name
# the schema gap and offer BOTH a project and a library command. Pinning the
# prose again would just re-break on the next honest rewording, while pinning
# "some advice was printed" would not notice the engine advising a command it
# refuses -- which is the defect 5080478 existed to fix.
# (The target version is the CURRENT SCHEMA_VERSION -- matched as v\d+ so a
#  future schema bump does not re-break this test.)
#
# D24 (2026-09-24) EXTENDS THE SENTINEL TO THREE PROBES AND FIVE MORE VERBS.
# lint-all, lint-project, rename --kind symbol (dry, --json), safe-delete (dry,
# --json) and exceptions-sync (dry, --json) only READ the index, yet each opened
# it WRITABLE and called Migrate, whose stamp rewrote pages 2-3 of a copy of the
# self index on every lint-all (md5 moved, zero logical change). Each must now
# leave md5, trigger count AND header byte 18 (2 = WAL) unchanged. Two genuine
# WRITERS opened with FireDAC's defaults -- LockingMode=Exclusive and
# `journal_mode = DELETE` -- and so converted a WAL index to a rollback journal:
# `import-log` (byte 18: 2 -> 1, measured) and `migrate-dbs --apply` (its
# checkpoint probe and its post-move row count). Both must keep the file WAL.
# Positive control: a real `index` run after a source edit DOES move the md5,
# so the sentinel is proven able to fail.
#
# FIX ROUND 1 (2026-09-24): every verb's EXIT CODE is asserted (a verb dying at
# open also leaves the md5 alone); safe-delete / rename --kind symbol with a
# missing --db exit 2 "Database not found", not FATAL exit 3; and a WRITER
# converts a rollback-journal index back to WAL (ruling R16) while no reader does.
#
# BATTERY FIX (2026-09-27, controller ruling R21): a reader that closes LAST must
# checkpoint and clean up like any other SQLite connection. D25 opened readers
# SQLITE_OPEN_READONLY, and a read-only last closer can neither checkpoint nor
# delete the -wal/-shm: every read verb left both beside a cleanly closed index,
# and WAL content a writer left behind (a killed indexer, a writer that closed
# while a reader was open) stayed OUTSIDE the main file -- so copying X.sqlite
# alone, the standard practice here, silently missed it. Two probes pin it:
# every read verb below must leave no -wal/-shm, and a read of an index whose
# writer died with committed pages still in the -wal must fold them into the
# main file (the positive control proves the main file alone lacked them).
#
# Usage: pwsh -File tests/autotest/run_readonly_verbs.ps1 [-Exe <path>]
[CmdletBinding()]
param(
    [string] $Exe = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe",
    [string] $WorkDir = "$env:TEMP\drag-lint-readonly-verbs-$PID"
)
$ErrorActionPreference = 'Stop'
$script:Failed = $false
function Check([string]$Name, [bool]$Ok, [string]$Detail='') {
    $status = if ($Ok) {'PASS'} else {'FAIL'}
    $color  = if ($Ok) {'Green'} else {'Red'}
    Write-Host ("  [{0}] {1} {2}" -f $status, $Name, $Detail) -ForegroundColor $color
    if (-not $Ok) { $script:Failed = $true }
}
function Md5([string]$Path) { (Get-FileHash -Algorithm MD5 -Path $Path).Hash }
function TriggerCount([string]$Db) {
    $py = "$WorkDir\trigcount.py"
    if (-not (Test-Path $py)) {
@'
import sqlite3, sys
c = sqlite3.connect(sys.argv[1])
print(c.execute("SELECT COUNT(*) FROM sqlite_master WHERE type='trigger'").fetchone()[0])
c.close()
'@ | Set-Content $py -Encoding ascii
    }
    return (python $py $Db).Trim()
}

function HeaderByte18([string]$Db) { [IO.File]::ReadAllBytes($Db)[18] }

# The -wal / -shm files beside $Db, as a comma list ('' when there are none).
function Sidecars([string]$Db) { (@('-wal','-shm') | Where-Object { Test-Path -LiteralPath ($Db + $_) }) -join ',' }

if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
if (Test-Path $WorkDir) { Remove-Item -Recurse -Force $WorkDir }
New-Item -ItemType Directory $WorkDir | Out-Null
try {

# --- build a tiny fixture: one .pas file with a class + a string literal ---
$srcDir = "$WorkDir\src"
New-Item -ItemType Directory $srcDir | Out-Null
$pas = "$srcDir\Fixture.pas"
@'
unit Fixture;

interface

type
  TFoo = class
  public
    function Greet: string;
    procedure DoWork;
  end;

implementation

function TFoo.Greet: string;
begin
  Result := 'hello world from fixture';
end;

procedure TFoo.DoWork;
begin
  Greet;
end;

end.
'@ | Set-Content $pas -Encoding ascii

# --- index it with the fresh win64 exe (has FTS5 -> triggers exist) ---
$db = "$WorkDir\ro.sqlite"
$idxOut = & $Exe index $srcDir --db $db 2>&1
Check 'index fixture exits 0' ($LASTEXITCODE -eq 0) (($idxOut | Select-Object -Last 1))
Check 'db created' (Test-Path $db)
Check 'fixture index (a writer, closed last) leaves no -wal/-shm' ((Sidecars $db) -eq '') "sidecars=$(Sidecars $db)"

$trigBase = TriggerCount $db
Check 'fixture has FTS5 sync triggers (>0)' ([int]$trigBase -gt 0) "triggers=$trigBase"

# --- run each read verb; DB md5 + trigger count must be UNCHANGED after each ---
# Give WAL a moment to checkpoint after the index write so the baseline md5 is
# stable (the read verbs must not touch it thereafter).
Start-Sleep -Milliseconds 200
$md5Base = Md5 $db

$b18Base = HeaderByte18 $db
Check 'fixture index is WAL (header byte 18 = 2)' ($b18Base -eq 2) "byte18=$b18Base"

# Each verb is judged against the file as it was JUST BEFORE it ran, so one
# writer cannot make every later verb fail with it (that hid which verb wrote).
# The EXIT CODE is asserted too (fix round 1): a verb that dies at open leaves
# the md5 alone just as well as one that read correctly, so without it the
# sentinel could not tell a clean read from a crash. Every case here exits 0 on
# this fixture (measured 2026-09-24; lint-all finds nothing to report in it).
function ReadVerbUnchanged([string]$Label, [scriptblock]$Run, [int]$ExpectExit = 0) {
    $md5Base = Md5 $db
    & $Run *> $null
    $ec = $LASTEXITCODE
    Check "$Label exits $ExpectExit" ($ec -eq $ExpectExit) "exit=$ec"
    # Sidecars FIRST: TriggerCount's python connection, closing last, would
    # clean up whatever the verb left and make this probe vacuous.
    $side = Sidecars $db
    Check "$Label leaves no -wal/-shm (a reader that closes last cleans up)" ($side -eq '') "sidecars=$side"
    Start-Sleep -Milliseconds 100
    $md5  = Md5 $db
    $trig = TriggerCount $db
    $b18  = HeaderByte18 $db
    Check "$Label leaves md5 unchanged"        ($md5 -eq $md5Base)      "was=$md5Base now=$md5"
    Check "$Label leaves trigger count intact"  ($trig -eq $trigBase)    "was=$trigBase now=$trig"
    Check "$Label leaves header byte 18 (WAL)"  ($b18 -eq $b18Base)      "was=$b18Base now=$b18"
}

ReadVerbUnchanged 'outline'      { & $Exe outline --file $pas --db $db }
ReadVerbUnchanged 'query --name' { & $Exe query --name TFoo --db $db }
ReadVerbUnchanged 'query --text' { & $Exe query --text "hello world" --db $db }
ReadVerbUnchanged 'surface'      { & $Exe surface --qname Fixture.TFoo --db $db }
ReadVerbUnchanged 'context'      { & $Exe context --task "modify Fixture.TFoo.Greet" --db $db }
ReadVerbUnchanged 'dump-refs'    { & $Exe dump-refs $pas --db $db }

# --- D24: verbs that only READ the index but opened it writable + Migrate ---
$excCfg = "$WorkDir\exc-on.json"
Set-Content -LiteralPath $excCfg -Value '{ "exceptions": { } }' -Encoding ascii
ReadVerbUnchanged 'lint-all'                  { & $Exe lint-all --db $db --quiet }
ReadVerbUnchanged 'lint-project'              { & $Exe lint-project --db $db }
ReadVerbUnchanged 'rename --kind symbol (dry)' { & $Exe rename --kind symbol --name Fixture.TFoo.Greet --to Salute --db $db --json }
ReadVerbUnchanged 'safe-delete (dry)'         { & $Exe safe-delete --name Fixture.TFoo.DoWork --db $db --json }
ReadVerbUnchanged 'exceptions-sync (dry)'     { & $Exe exceptions-sync --db $db --config $excCfg --json }

# A read-only open does not create a missing file, so these two died
# "FATAL: unable to open database file" (exit 3) until fix round 1.
foreach ($mv in @(@('safe-delete', @('safe-delete','--name','X','--json')), @('rename --kind symbol', @('rename','--kind','symbol','--name','X.Y','--to','Z','--json')))) {
    $mo = (& $Exe @($mv[1] + @('--db', "$WorkDir\no-such.sqlite")) 2>&1) -join "`n"
    Check "$($mv[0]) with a missing --db exits 2 with 'Database not found'" (($LASTEXITCODE -eq 2) -and ($mo -match 'Database not found')) "exit=$LASTEXITCODE :: $mo"
    Check "$($mv[0]) with a missing --db does not create it" (-not (Test-Path "$WorkDir\no-such.sqlite"))
}

# The dry verbs above must still ANSWER from the read-only store -- a verb that
# failed to open would also leave the md5 alone.
$rn = (& $Exe rename --kind symbol --name Fixture.TFoo.Greet --to Salute --db $db --json 2>&1) -join "`n"
Check 'rename --kind symbol (dry) still computes its edits' ($rn -match '"new"\s*:\s*"Salute"') $rn

# --- D24: genuine WRITERS must keep a WAL index WAL ---
# import-log: a raw TFDConnection with FireDAC defaults rewrote byte 18 to 1.
$impDb = "$WorkDir\imp.sqlite"
Copy-Item -LiteralPath $db -Destination $impDb
$log = "$WorkDir\dcc.log"
Set-Content -LiteralPath $log -Encoding ascii -Value "$pas(82,3): Warning W1036: Variable 'X' might not have been initialized [x.dproj]"
$impOut = (& $Exe import-log $log --db $impDb 2>&1) -join "`n"
Check 'import-log exits 0' ($LASTEXITCODE -eq 0) $impOut
Check 'import-log imported the finding' ($impOut -match 'Imported 1 compiler finding') $impOut
Check 'import-log keeps the index WAL (header byte 18 = 2)' ((HeaderByte18 $impDb) -eq 2) "byte18=$(HeaderByte18 $impDb)"
Check 'import-log leaves no rollback -journal file' (-not (Test-Path "$impDb-journal"))

# A WRITER REQUESTS WAL (ruling R16, fix round 1): an index an older engine
# flipped to a rollback journal is healed by its next write -- here an
# incremental index with nothing to re-parse. Readers never convert (above).
$rbDb = "$WorkDir\rollback.sqlite"
Copy-Item -LiteralPath $db -Destination $rbDb
python -c "import sqlite3,sys; c=sqlite3.connect(sys.argv[1]); c.execute('PRAGMA journal_mode=DELETE'); c.close()" $rbDb
Check 'rollback fixture really is a rollback journal (byte 18 = 1)' ((HeaderByte18 $rbDb) -eq 1) "byte18=$(HeaderByte18 $rbDb)"
$rbOut = (& $Exe index $srcDir --db $rbDb 2>&1) -join "`n"
Check 'incremental index of a rollback-journal index exits 0' ($LASTEXITCODE -eq 0) $rbOut
Check 'the writer converts it back to WAL (byte 18 = 2)' ((HeaderByte18 $rbDb) -eq 2) "byte18=$(HeaderByte18 $rbDb)"

# migrate-dbs --apply: the checkpoint probe before the move and the row count
# after it both opened with FireDAC defaults.
$mproj = "$WorkDir\mproj"; New-Item -ItemType Directory $mproj | Out-Null
$mout  = "$WorkDir\mout" ; New-Item -ItemType Directory $mout  | Out-Null
Set-Content -LiteralPath "$mproj\App.dproj" -Value '<Project/>' -NoNewline
Set-Content -LiteralPath "$mproj\App.pas"   -Value "unit App;`r`ninterface`r`nimplementation`r`nend." -Encoding ascii
$oldDb = "$mout\Old-App.sqlite"
& $Exe index $mproj --db $oldDb *> $null
Check 'migrate fixture index is WAL before the move' ((HeaderByte18 $oldDb) -eq 2) "byte18=$(HeaderByte18 $oldDb)"
$mcfg = "$WorkDir\migrate.json"
$mj = @{ indexes = @{ outDir = $mout; sections = @(
          @{ name = 'Old-App'; db = 'Old-App.sqlite'; include = @("$mproj\App.dproj") } ) } }
Set-Content -LiteralPath $mcfg -Value ($mj | ConvertTo-Json -Depth 8)
$migOut = (& $Exe migrate-dbs --config $mcfg --apply 2>&1) -join "`n"
$newDb = "$mproj\_D-RAG\App.sqlite"
Check 'migrate-dbs --apply exits 0 and moves the index' (($LASTEXITCODE -eq 0) -and (Test-Path $newDb)) $migOut
if (Test-Path $newDb) {
    Check 'migrate-dbs keeps the moved index WAL (header byte 18 = 2)' ((HeaderByte18 $newDb) -eq 2) "byte18=$(HeaderByte18 $newDb)"
}

# --- R21: a reader that closes LAST folds a dead writer's WAL into the main file ---
# The writer commits one row with autocheckpoint off and then exits WITHOUT
# closing (os._exit), exactly as a killed indexer would: the row lives only in
# the -wal. A read verb is then the only -- so the last -- connection.
$walDb = "$WorkDir\walleft.sqlite"
Copy-Item -LiteralPath $db -Destination $walDb
$walPy = "$WorkDir\wal_writer_dies.py"
@'
import os, sqlite3, sys
c = sqlite3.connect(sys.argv[1])
c.execute("PRAGMA wal_autocheckpoint = 0")
c.execute("CREATE TABLE r21_probe (v TEXT)")
c.execute("INSERT INTO r21_probe VALUES ('folded')")
c.commit()
os._exit(0)
'@ | Set-Content $walPy -Encoding ascii
$probePy = "$WorkDir\probe_main_only.py"
@'
import shutil, sqlite3, sys
shutil.copyfile(sys.argv[1], sys.argv[2])
c = sqlite3.connect(sys.argv[2])
r = c.execute("SELECT COUNT(*) FROM sqlite_master WHERE name = 'r21_probe'").fetchone()[0]
print(c.execute("SELECT v FROM r21_probe").fetchone()[0] if r else "absent")
c.close()
'@ | Set-Content $probePy -Encoding ascii
python $walPy $walDb
$walLen = if (Test-Path -LiteralPath "$walDb-wal") { (Get-Item -LiteralPath "$walDb-wal").Length } else { 0 }
Check 'R21 fixture: the dead writer left committed pages in the -wal' ($walLen -gt 0) "wal bytes=$walLen"
# POSITIVE CONTROL for the Sidecars helper itself: it must SEE the -wal/-shm
# the dead writer left, or every "leaves no -wal/-shm" check above is vacuous.
Check 'R21 POSITIVE CONTROL: Sidecars sees the dead writer''s -wal/-shm' ((Sidecars $walDb) -ne '') "sidecars=$(Sidecars $walDb)"
$before = (python $probePy $walDb "$WorkDir\mainonly-before.sqlite").Trim()
Check 'R21 POSITIVE CONTROL: the main file ALONE lacks the row before the read' ($before -eq 'absent') "main-only=$before"
$rq = (& $Exe query --name TFoo --db $walDb 2>&1) -join "`n"
Check 'R21 read verb on the dead writer''s index exits 0' ($LASTEXITCODE -eq 0) $rq
Check 'R21 the reader, closing last, leaves no -wal/-shm' ((Sidecars $walDb) -eq '') "sidecars=$(Sidecars $walDb)"
$after = (python $probePy $walDb "$WorkDir\mainonly-after.sqlite").Trim()
Check 'R21 the main file ALONE now holds the row (the WAL was checkpointed into it)' ($after -eq 'folded') "main-only=$after"
Check 'R21 the reader leaves header byte 18 (WAL)' ((HeaderByte18 $walDb) -eq 2) "byte18=$(HeaderByte18 $walDb)"

# --- read verbs still produce correct output (guard against a broken read path) ---
$q = & $Exe query --name TFoo --db $db 2>&1
Check 'query --name TFoo finds the class' (($q -join "`n") -match 'TFoo') (($q | Select-Object -First 1))

# --- v12-shaped DB: a read verb must print the actionable stale-schema line ---
$py = "$WorkDir\make_v12.py"
@'
import sqlite3, sys
c = sqlite3.connect(sys.argv[1])
c.executescript("""
CREATE TABLE schema_meta (key TEXT PRIMARY KEY, value TEXT NOT NULL);
INSERT INTO schema_meta(key, value) VALUES ('schema_version', '12');
CREATE TABLE files (id INTEGER PRIMARY KEY, path TEXT NOT NULL UNIQUE,
  mtime_unix INTEGER NOT NULL, sha256 TEXT NOT NULL,
  parsed_at INTEGER NOT NULL, language TEXT NOT NULL);
CREATE TABLE symbols (id INTEGER PRIMARY KEY,
  file_id INTEGER NOT NULL REFERENCES files(id) ON DELETE CASCADE,
  parent_id INTEGER REFERENCES symbols(id) ON DELETE CASCADE,
  kind TEXT NOT NULL, name TEXT NOT NULL, qualified_name TEXT NOT NULL,
  signature TEXT, modifiers TEXT, section TEXT, heritage TEXT,
  is_virtual INTEGER, start_line INTEGER NOT NULL, start_col INTEGER NOT NULL,
  end_line INTEGER NOT NULL, end_col INTEGER NOT NULL,
  impl_start_line INTEGER, impl_end_line INTEGER);
CREATE TABLE refs (id INTEGER PRIMARY KEY,
  symbol_id INTEGER REFERENCES symbols(id) ON DELETE SET NULL,
  file_id INTEGER NOT NULL REFERENCES files(id) ON DELETE CASCADE,
  kind TEXT NOT NULL, name_text TEXT NOT NULL,
  start_line INTEGER NOT NULL, start_col INTEGER NOT NULL,
  end_line INTEGER NOT NULL, end_col INTEGER NOT NULL);
""")
c.commit()
c.close()
'@ | Set-Content $py -Encoding ascii
$dbv12 = "$WorkDir\v12.sqlite"
python $py $dbv12
Check 'v12 fixture DB created' (($LASTEXITCODE -eq 0) -and (Test-Path $dbv12))

$staleOut = (& $Exe outline --file $pas --db $dbv12 2>&1) -join "`n"
$staleEc  = $LASTEXITCODE
Check 'read verb on v12 db exits nonzero' ($staleEc -ne 0) "exit=$staleEc"
Check 'read verb on v12 db names the schema gap' `
    ($staleOut -match 'index schema v12 < v\d+') `
    $staleOut
Check 'read verb on v12 db offers a PROJECT migration command' `
    ($staleOut -match 'drag-lint index --project') `
    $staleOut
Check 'read verb on v12 db offers a LIBRARY migration command' `
    ($staleOut -match 'drag-lint index <dir>') `
    $staleOut
Check 'read verb on v12 db does NOT print a field error' `
    (-not ($staleOut -match 'no such column')) `
    $staleOut

# --- POSITIVE CONTROL: a genuine write DOES move the sentinel ---
Add-Content -LiteralPath $pas -Value '{ touched by the positive control }' -Encoding ascii
& $Exe index $srcDir --db $db *> $null
Start-Sleep -Milliseconds 100
Check 'positive control: a real index run after an edit changes the md5' ((Md5 $db) -ne $md5Base)
} finally {
    if (Test-Path $WorkDir) { Remove-Item -Recurse -Force $WorkDir -ErrorAction SilentlyContinue }
}

Write-Host ''
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
