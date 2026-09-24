<#
  run_readonly_concurrency_guard.ps1 -- a READ-ONLY verb must never fail with
  "database is locked" because some other connection held a lock for a moment,
  and must never write to the index it reads.

  THE DEFECT (docs\INBOX-readonly-sql-verb-hits-database-locked.md, 2026-09-23)
  --------------------------------------------------------------------------
  12 concurrent `sql` processes x 25 calls, NO writer: 1 of 300 exited 3 with
  `FATAL: ESQLiteNativeException ... database is locked` and nothing on stdout.
  A consumer (the charts wrapper) read that as ZERO ROWS.

  ROOT CAUSE. The store did set `PRAGMA busy_timeout = 5000` -- but only AFTER
  `Connected := True`, and FireDAC runs its own pragmas INSIDE the connect
  (cache_size, locking_mode, synchronous, journal_mode, foreign_keys;
  FireDAC.Phys.SQLite.pas InternalConnect). cache_size needs the schema, so the
  first of them opens a read transaction with NO busy handler (FireDAC's
  TSQLiteDatabase starts at busy timeout 0 and only arms its BusyTimeout param
  when UpdateOptions.LockWait is True). In WAL mode the LAST connection to close
  briefly takes an EXCLUSIVE lock on the database file to checkpoint and delete
  the -wal; an opener that lands in that window fails SQLITE_BUSY at once
  instead of waiting a millisecond. With many short-lived reader processes that
  window is hit about once in a few hundred opens.

  WHY THE FIRST CHECK IS DETERMINISTIC AND NOT THE STRESS RUN
  -----------------------------------------------------------
  A 1-in-300 race cannot be a reliable RED. So check 1 CREATES the window: it
  takes the same byte-range lock SQLite's Windows VFS takes for EXCLUSIVE
  (the 510-byte SHARED range at 0x40000002), starts a reader, and releases the
  lock after LockHoldMs. A reader with a busy handler armed from the first
  statement waits and succeeds; one without it fails immediately. The stress
  run (check 3) is kept because it is the defect as reported -- on a large DB
  pass -SourceDb to reproduce the real rate.

  AND THE WRITE HALF
  ------------------
  `top`, `graph`, `diff`, `query hints`, `export obsidian`, `workspace status`
  and `--selftest-schema` opened raw FireDAC connections with FireDAC's DEFAULT
  params: LockingMode=Exclusive and JournalMode=Delete. On a WAL index that
  rewrote the header (bytes 18/19: 2 -> 1) -- a read verb converting the index
  out of WAL -- and held an exclusive lock for the whole verb. Check 2 pins
  the header and the bytes.

  Usage: pwsh -File tests\autotest\run_readonly_concurrency_guard.ps1
           [-Exe <path>] [-SourceDb <big.sqlite>] [-Procs 12] [-Calls 25]
#>
[CmdletBinding()]
param(
    [string] $Exe       = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe",
    [string] $WorkDir   = "$env:TEMP\drag-lint-readonly-concurrency",
    [string] $SourceDb  = '',
    [int]    $Procs     = 12,
    [int]    $Calls     = 25,
    [int]    $LockHoldMs = 1500
)
$ErrorActionPreference = 'Stop'
$script:Failed = $false
function Check([string]$Name, [bool]$Ok, [string]$Detail = '') {
    $status = if ($Ok) { 'PASS' } else { 'FAIL' }
    $color  = if ($Ok) { 'Green' } else { 'Red' }
    Write-Host ("  [{0}] {1} {2}" -f $status, $Name, $Detail) -ForegroundColor $color
    if (-not $Ok) { $script:Failed = $true }
}
function Md5([string]$Path) { (Get-FileHash -Algorithm MD5 -Path $Path).Hash }
function HeaderBytes([string]$Path) {
    $f = [IO.File]::Open($Path, 'Open', 'Read', 'ReadWrite')
    try { $b = New-Object byte[] 20; [void]$f.Read($b, 0, 20); return "$($b[18]),$($b[19])" }
    finally { $f.Close() }
}
function WalState([string]$Db) {
    $w = "$Db-wal"
    if (Test-Path $w) { return "len=$((Get-Item $w).Length) md5=$(Md5 $w)" } else { return 'absent' }
}

if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
$Exe = (Resolve-Path $Exe).Path
if (Test-Path $WorkDir) { Remove-Item -Recurse -Force $WorkDir }
New-Item -ItemType Directory $WorkDir | Out-Null

# --- the database under test: a scratch COPY, never the caller's file -------
$db = "$WorkDir\ro.sqlite"
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
  end;

implementation

function TFoo.Greet: string;
begin
  Result := 'hello world from fixture';
end;

end.
'@ | Set-Content $pas -Encoding ascii
if ($SourceDb -ne '') {
    Copy-Item $SourceDb $db
    if (Test-Path "$SourceDb-wal") { Copy-Item "$SourceDb-wal" "$db-wal" }
} else {
    $idxOut = & $Exe index $srcDir --db $db 2>&1
    Check 'index fixture exits 0' ($LASTEXITCODE -eq 0) (($idxOut | Select-Object -Last 1))
}
# A pristine copy: every write check below starts from it, so one verb that
# converts the header cannot make the next verb's check pass or fail.
$pristine = "$WorkDir\pristine.sqlite"
Copy-Item $db $pristine
if (Test-Path "$db-wal") { Copy-Item "$db-wal" "$pristine-wal" }
function Reset-Db {
    foreach ($side in "$db-wal", "$db-shm") { if (Test-Path $side) { Remove-Item $side } }
    Copy-Item $pristine $db -Force
    if (Test-Path "$pristine-wal") { Copy-Item "$pristine-wal" "$db-wal" -Force }
}
$hdrBase = HeaderBytes $db
Check 'positive control: the DB under test is WAL (header 2,2)' ($hdrBase -eq '2,2') "header=$hdrBase"
$countSql = 'SELECT COUNT(*) AS n FROM files'
$expected = (& $Exe sql --db $db --query $countSql --format json 2>$null) -join "`n"
Check 'positive control: sql answers with a row' (($LASTEXITCODE -eq 0) -and ($expected -match '\d')) $expected
$md5Base = Md5 $db
$walBase = WalState $db

# --- 1. a reader WAITS for a held lock instead of failing -------------------
# SQLite's Windows VFS: PENDING_BYTE=0x40000000, SHARED_FIRST=PENDING+2,
# SHARED_SIZE=510. EXCLUSIVE = that whole range locked exclusively.
$SHARED_FIRST = 0x40000002
$SHARED_SIZE  = 510
function ReaderWaitsForLock([string]$Label, [string[]]$VerbArgs) {
    $out = "$WorkDir\lock-$Label.out"
    $err = "$WorkDir\lock-$Label.err"
    $fs = [IO.File]::Open($db, 'Open', 'ReadWrite', 'ReadWrite')
    try {
        $fs.Lock($SHARED_FIRST, $SHARED_SIZE)
        # One quoted string: Start-Process joins an array on spaces unquoted,
        # which would split the SQL text into separate arguments.
        $argLine = ($VerbArgs | ForEach-Object { '"' + $_ + '"' }) -join ' '
        $p = Start-Process -FilePath $Exe -ArgumentList $argLine -PassThru -NoNewWindow `
               -RedirectStandardOutput $out -RedirectStandardError $err
        Start-Sleep -Milliseconds $LockHoldMs
        $fs.Unlock($SHARED_FIRST, $SHARED_SIZE)
    } finally { $fs.Close() }
    $p.WaitForExit()
    $o = (Get-Content $out -Raw) + ''
    $e = (Get-Content $err -Raw) + ''
    Check "$Label waits out a ${LockHoldMs} ms lock and exits 0" ($p.ExitCode -eq 0) "exit=$($p.ExitCode) stderr=$($e.Trim())"
    Check "$Label printed its result" ($o.Trim().Length -gt 0) ''
    Check "$Label did not report 'database is locked'" (-not ($o + $e).Contains('database is locked')) ''
}
ReaderWaitsForLock 'sql'     @('sql', '--db', $db, '--query', $countSql, '--format', 'json')
ReaderWaitsForLock 'query'   @('query', '--name', 'TFoo', '--db', $db)
ReaderWaitsForLock 'top'     @('top', '--db', $db, '--limit', '3')
ReaderWaitsForLock 'graph'   @('graph', '--db', $db)

# --- 2. read verbs leave the bytes, the -wal and the WAL header alone -------
$raw = @(
    @('sql',   '--db', $db, '--query', $countSql),
    @('query', '--name', 'TFoo', '--db', $db),
    @('top',   '--db', $db, '--limit', '3'),
    @('graph', '--db', $db),
    @('query', 'hints', '--db', $db),
    @('diff',  '--db', $db, '--db', $db),
    @('--selftest-schema', '--db', $db)
)
foreach ($a in $raw) {
    Reset-Db
    & $Exe @a *> $null
    $label = ($a | Select-Object -First 2) -join ' '
    Check "$label keeps the WAL header" ((HeaderBytes $db) -eq $hdrBase) "was=$hdrBase now=$(HeaderBytes $db)"
    Check "$label leaves the DB bytes unchanged" ((Md5 $db) -eq $md5Base) ''
    Check "$label leaves the -wal unchanged" ((WalState $db) -eq $walBase) "was=$walBase now=$(WalState $db)"
}

# --- 3. the reported load: Procs x Calls concurrent sql readers -------------
Reset-Db
$jobs = 1..$Procs | ForEach-Object {
    Start-Job -ArgumentList $Exe, $db, $Calls, $countSql -ScriptBlock {
        param($Exe, $Db, $Calls, $Sql)
        for ($i = 0; $i -lt $Calls; $i++) {
            $o = & $Exe sql --db $Db --query $Sql --format json 2>&1
            [pscustomobject]@{ Exit = $LASTEXITCODE; Out = ($o | Out-String) }
        }
    }
}
$all = @($jobs | Wait-Job | Receive-Job)
$jobs | Remove-Job
$bad = @($all | Where-Object { ($_.Exit -ne 0) -or ($_.Out -notmatch '"n"') })
Check "stress: $($all.Count) of $($Procs * $Calls) calls completed" ($all.Count -eq $Procs * $Calls) ''
Check "stress: 0 failed calls" ($bad.Count -eq 0) "failed=$($bad.Count) first=$(($bad | Select-Object -First 1).Out)"
Check 'stress leaves the DB bytes unchanged' ((Md5 $db) -eq $md5Base) ''

# --- 4. a pre-migration DB is REFUSED by a store reader, and NOT migrated ---
# `query` goes through the store's read path, which refuses a stale schema.
# `sql` is the raw passthrough: it does not judge the schema (inspecting an
# old DB is one of its uses), so for it the invariant is only "not migrated".
$py = "$WorkDir\make_v12.py"
@'
import sqlite3, sys
c = sqlite3.connect(sys.argv[1])
c.execute("PRAGMA journal_mode=WAL")
c.executescript("""
CREATE TABLE schema_meta (key TEXT PRIMARY KEY, value TEXT NOT NULL);
INSERT INTO schema_meta(key, value) VALUES ('schema_version', '12');
CREATE TABLE files (id INTEGER PRIMARY KEY, path TEXT NOT NULL UNIQUE,
  mtime_unix INTEGER NOT NULL, sha256 TEXT NOT NULL,
  parsed_at INTEGER NOT NULL, language TEXT NOT NULL);
CREATE TABLE symbols (id INTEGER PRIMARY KEY, file_id INTEGER NOT NULL,
  parent_id INTEGER, kind TEXT NOT NULL, name TEXT NOT NULL,
  qualified_name TEXT NOT NULL, start_line INTEGER NOT NULL,
  start_col INTEGER NOT NULL, end_line INTEGER NOT NULL, end_col INTEGER NOT NULL);
""")
c.commit()
c.close()
'@ | Set-Content $py -Encoding ascii
$v12 = "$WorkDir\v12.sqlite"
python $py $v12
Check 'v12 fixture DB created' (($LASTEXITCODE -eq 0) -and (Test-Path $v12))
$v12Md5 = Md5 $v12
$v12Out = (& $Exe query --name TFoo --db $v12 2>&1) -join "`n"
$v12Ec  = $LASTEXITCODE
Check 'query on a pre-migration DB exits nonzero' ($v12Ec -ne 0) "exit=$v12Ec"
Check 'query on a pre-migration DB names the schema gap' ($v12Out -match 'schema v12 < v\d+') $v12Out
Check 'query on a pre-migration DB does NOT migrate it' ((Md5 $v12) -eq $v12Md5) ''
& $Exe sql --db $v12 --query 'SELECT COUNT(*) FROM files' *> $null
Check 'sql on a pre-migration DB does NOT migrate it' ((Md5 $v12) -eq $v12Md5) ''
Check 'sql on a pre-migration DB keeps its header' ((HeaderBytes $v12) -eq '2,2') "header=$(HeaderBytes $v12)"

Write-Host ''
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
