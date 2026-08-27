<#
  run_sql_verb_guard.ps1 -- `drag-lint sql` must answer real questions and must
  refuse everything that is not a read.

  WHY THIS EXISTS
  ---------------
  `sql` is the one verb that hands an arbitrary string to the engine. Every
  other verb decides for itself what SQL runs; this one does not. The controls
  are therefore not decoration, and they are not enforced by reading the query
  text -- they are three independent mechanisms SQLite itself applies:

    1. the connection is opened read-only (PRAGMA query_only = ON), set by
       TSQLiteSymbolStore.Connect;
    2. an sqlite3 AUTHORIZER denies every action but SELECT/READ/RECURSIVE
       (plus safe functions and transaction control) -- this is what blocks
       ATTACH, which query_only does NOT;
    3. a progress handler caps wall-clock time, so a cartesian join is
       interrupted mid-step instead of wedging the IDE that holds the index.

  THE POSITIVE CONTROLS COME FIRST, AND THEY ARE THE POINT
  --------------------------------------------------------
  A guard that only asserts "the bad thing was rejected" passes with the verb
  switched off, with the database missing, and with an authorizer that denies
  literally everything. This repo has shipped guards like that. So before a
  single denial is checked, this runner proves the happy path WORKS: a real
  SELECT against a real index returns real rows with exit 0. Every denial
  assertion below is only meaningful because that one passed.

  The denial checks are two-sided for the same reason. It is not enough that
  ATTACH fails -- a typo would also fail. The message must NAME the action, and
  that text is produced by drag-lint's own authorizer callback (Explain), not
  by SQLite. So "ATTACH is not permitted" is evidence that the authorizer ran
  and made the decision. A query_only rejection would read as SQLITE_READONLY
  and could not produce that sentence.

  THE REGRESSION THAT IS PINNED HERE BY NAME
  ------------------------------------------
  The first working build set FireDAC's FetchOptions.RecsMax to enforce the row
  cap. FireDAC responds to RecsMax by appending its OWN "LIMIT n" to the
  statement, so any query that already ended in LIMIT compiled as
  "... LIMIT 2 LIMIT 201" and died with `near "LIMIT": syntax error`. LIMIT is
  the first thing anyone writes in an ad-hoc query, and every test written
  without one passed. Check 4 exists so that cannot come back quietly.

  AND THE LAST CHECK IS A CONTENT PROBE, NOT A BYTE HASH
  ------------------------------------------------------
  The obvious assertion -- hash the .sqlite before the first query and after
  the last -- is WRONG for this database, and the first draft of this runner
  used it. Two reasons, both discovered by running it:

    * the file is WAL, and when the LAST connection closes SQLite CHECKPOINTS,
      folding the -wal into the main file. The bytes change without one row
      changing. That check passes only by accident, when a live LSP happens to
      be holding the database open so ours is never the last connection --
      i.e. it is a control that flakes RED on a clean machine.
    * Get-FileHash could not open the file at all while the LSP held it, which
      turned a legitimate steady state into a runner crash.

  So the invariant asserted is the one that actually matters: the DATA is
  unchanged. A fingerprint over row counts, a summed text length (which a
  same-cardinality UPDATE would move) and the sqlite_master object count is
  taken before and after, THROUGH THE VERB ITSELF. It is only meaningful
  because check 1 already proved the verb returns real answers.

  Exit code: 0 on full pass, 1 on any failure.

  Usage: pwsh -File tests\autotest\run_sql_verb_guard.ps1
#>
[CmdletBinding()]
param(
  [string] $Exe    = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe",
  [string] $DbFile = "$PSScriptRoot\..\..\src\cli\_D-RAG\drag-lint.sqlite"
)

$ErrorActionPreference = 'Stop'
$script:Failed = $false

function Check([string]$Name, [bool]$Ok, [string]$Detail = '') {
  $status = if ($Ok) { 'PASS' } else { 'FAIL' }
  $color  = if ($Ok) { 'Green' } else { 'Red' }
  Write-Host ("  [{0}] {1} {2}" -f $status, $Name, $Detail) -ForegroundColor $color
  if (-not $Ok) { $script:Failed = $true }
}

Write-Host '== drag-lint sql: guarded read-only SQL surface ==' -ForegroundColor Cyan

# Full path only. A bare `drag-lint` resolves off PATH to a frozen Win32 build
# on this machine (NoDefaultCurrentDirectoryInExePath=1).
if (-not (Test-Path -LiteralPath $Exe)) {
  Write-Host "FATAL: engine not found at $Exe" -ForegroundColor Red; exit 1
}
$Exe = (Resolve-Path $Exe).Path
if (-not (Test-Path -LiteralPath $DbFile)) {
  Write-Host "SKIP: no self-index at $DbFile" -ForegroundColor Yellow; exit 0
}
$DbFile = (Resolve-Path $DbFile).Path

$scratch = Join-Path ([IO.Path]::GetTempPath()) ("draglint-sql-" + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $scratch -Force | Out-Null
$errFile = Join-Path $scratch 'stderr.txt'

# The engine prints "(loaded defaults from ...)" on STDERR. Capturing the two
# streams separately is not fussiness: merging them with 2>&1 under
# $ErrorActionPreference='Stop' turns that banner into an ErrorRecord that
# Out-String renders with decoration, which has already corrupted one JSON
# slice in this repo by adding a stray brace.
function Run([string[]]$SqlArgs) {
  $out = & $Exe @SqlArgs 2>$errFile
  $rc  = $LASTEXITCODE
  $err = if (Test-Path -LiteralPath $errFile) { (Get-Content -LiteralPath $errFile -Raw) } else { '' }
  if ($null -eq $err) { $err = '' }
  [pscustomobject]@{
    Out  = ($out -join "`n")
    Err  = $err
    Code = $rc
  }
}

# The DATA fingerprint. Row counts alone would miss an UPDATE that changed a
# value without changing cardinality, so a summed text length rides along; the
# sqlite_master count covers DDL. Taken through the verb under test, which is
# sound only because check 1 below proves the verb answers correctly.
$fpSql = @'
SELECT (SELECT COUNT(*) FROM symbols) || '/' ||
       (SELECT COUNT(*) FROM refs) || '/' ||
       (SELECT COUNT(*) FROM files) || '/' ||
       (SELECT COALESCE(SUM(LENGTH(name)), 0) FROM symbols) || '/' ||
       (SELECT COUNT(*) FROM sqlite_master) AS fingerprint
'@
function Fingerprint {
  $f = Run @('sql','--query',$fpSql,'--db',$DbFile)
  if ($f.Code -ne 0) { return "ERROR($($f.Code)): $($f.Err.Trim())" }
  $m = [regex]::Match($f.Out, '(?m)^\s*(\d+(?:/\d+){4})\s*$')
  if ($m.Success) { return $m.Groups[1].Value }
  return "UNPARSED: $($f.Out)"
}
$fpBefore = Fingerprint

# ---------------------------------------------------------------------------
# CHECK 1 -- POSITIVE CONTROL. Everything below depends on this passing.
# ---------------------------------------------------------------------------
Write-Host ''
Write-Host '-- check 1: the happy path actually works' -ForegroundColor Cyan

$r = Run @('sql','--query','SELECT COUNT(*) AS n FROM symbols','--db',$DbFile)
Check 'a real SELECT exits 0' ($r.Code -eq 0) "exit $($r.Code) / $($r.Err.Trim())"
$countOk = $r.Out -match '(?m)^\s*(\d+)\s*$'
$symCount = if ($countOk) { [int]$Matches[1] } else { 0 }
Check 'it returns a row with a plausible symbol count' ($symCount -gt 100) "symbols = $symCount"
Check 'it reports a row count footer' ($r.Out -match '1 row\(s\) in \d+ ms') ''

if ($r.Code -ne 0 -or $symCount -le 100) {
  Write-Host 'FATAL: the positive control failed; every denial check below would pass vacuously.' -ForegroundColor Red
  Remove-Item -LiteralPath $scratch -Recurse -Force -ErrorAction SilentlyContinue
  exit 1
}

# A join and a recursive CTE, because "SELECT COUNT(*)" alone would also pass
# with an authorizer that happened to allow only the simplest shape.
$r = Run @('sql','--query','SELECT f.path, COUNT(s.id) AS n FROM files f JOIN symbols s ON s.file_id = f.id GROUP BY f.path ORDER BY n DESC','--db',$DbFile,'--limit','3')
Check 'a GROUP BY / JOIN query works' (($r.Code -eq 0) -and ($r.Out -match '\.pas')) "exit $($r.Code)"

$r = Run @('sql','--query','WITH RECURSIVE c(x) AS (SELECT 1 UNION ALL SELECT x+1 FROM c WHERE x < 5) SELECT x FROM c','--db',$DbFile)
Check 'a RECURSIVE CTE works (SQLITE_RECURSIVE is allowed)' `
  (($r.Code -eq 0) -and ($r.Out -match '5 row\(s\)')) "exit $($r.Code) / $($r.Err.Trim())"

# ---------------------------------------------------------------------------
# CHECK 2 -- the authorizer refuses everything that is not a read, BY NAME
# ---------------------------------------------------------------------------
Write-Host ''
Write-Host '-- check 2: the authorizer' -ForegroundColor Cyan

# "<action> is not permitted" is produced by drag-lint's OWN authorizer callback
# (TSqlGuard.Explain). SQLite's own refusals do not say that. So matching this
# text proves WHICH layer refused, not merely that something did.
$denials = @(
  @{ Name = 'ATTACH';        Sql = "ATTACH DATABASE 'other.sqlite' AS other"; Expect = 'ATTACH is not permitted' },
  @{ Name = 'DETACH';        Sql = 'DETACH DATABASE other';                   Expect = 'is not permitted'        },
  @{ Name = 'PRAGMA';        Sql = 'PRAGMA journal_mode';                     Expect = 'PRAGMA is not permitted' },
  @{ Name = 'DELETE';        Sql = 'DELETE FROM symbols';                     Expect = 'DELETE is not permitted' },
  @{ Name = 'INSERT';        Sql = "INSERT INTO symbols (name) VALUES ('x')"; Expect = 'INSERT is not permitted' },
  @{ Name = 'UPDATE';        Sql = "UPDATE symbols SET name = 'x'";           Expect = 'UPDATE is not permitted' },
  # DDL does NOT surface as SQLITE_CREATE_TABLE / SQLITE_DROP_TABLE here, and
  # that is SQLite's behaviour rather than a defect: it authorizes the write to
  # sqlite_master FIRST, so the first denial -- the one that aborted the
  # statement, and therefore the one reported -- is INSERT/DELETE on
  # sqlite_master. Asserting the tidier name made this check fail against
  # CORRECT code. The expectation is the observed mechanism, on purpose.
  @{ Name = 'CREATE TABLE';  Sql = 'CREATE TABLE zz (a INTEGER)';             Expect = 'INSERT is not permitted (sqlite_master)' },
  @{ Name = 'DROP TABLE';    Sql = 'DROP TABLE symbols';                      Expect = 'DELETE is not permitted (sqlite_master)' },
  @{ Name = 'load_extension';Sql = "SELECT load_extension('evil.dll')";       Expect = 'load_extension' }
)

foreach ($d in $denials) {
  $r = Run @('sql','--query',$d.Sql,'--db',$DbFile)
  $named = ($r.Err -match [regex]::Escape($d.Expect))
  Check ("{0} is refused, and the message names it" -f $d.Name) `
    (($r.Code -eq 1) -and $named -and ($r.Err -match 'refused')) `
    ("exit {0} / {1}" -f $r.Code, ($r.Err -split "`n")[0].Trim())
}

# ---------------------------------------------------------------------------
# CHECK 3 -- one statement, and the scanner is not a naive semicolon search
# ---------------------------------------------------------------------------
Write-Host ''
Write-Host '-- check 3: single-statement enforcement' -ForegroundColor Cyan

$r = Run @('sql','--query','SELECT 1; DROP TABLE symbols','--db',$DbFile)
Check 'a second statement is rejected as a usage error' `
  (($r.Code -eq 2) -and ($r.Err -match 'more than one statement')) `
  "exit $($r.Code)"

# NEGATIVE CONTROL for the scanner. If it merely searched for ';' both of these
# would fail, and the "rejects multiple statements" check above would still be
# green -- which is exactly how a too-eager guard hides.
$r = Run @('sql','--query',"SELECT 'a;b' AS s",'--db',$DbFile)
Check 'a semicolon INSIDE a string literal is not a second statement' `
  (($r.Code -eq 0) -and ($r.Out -match 'a;b')) "exit $($r.Code) / $($r.Err.Trim())"

$r = Run @('sql','--query','SELECT 1 AS one;','--db',$DbFile)
Check 'a single trailing semicolon is allowed' ($r.Code -eq 0) "exit $($r.Code) / $($r.Err.Trim())"

$r = Run @('sql','--query','   ;  ','--db',$DbFile)
Check 'an empty query is rejected rather than answered with no rows' `
  (($r.Code -eq 2) -and ($r.Err -match 'empty')) "exit $($r.Code)"

# ---------------------------------------------------------------------------
# CHECK 4 -- the caps, and the RecsMax/LIMIT regression
# ---------------------------------------------------------------------------
Write-Host ''
Write-Host '-- check 4: row cap, user LIMIT, time cap' -ForegroundColor Cyan

# THE REGRESSION PIN. FireDAC appends its own LIMIT when FetchOptions.RecsMax is
# set, so a user LIMIT produced `near "LIMIT": syntax error`.
$r = Run @('sql','--query','SELECT id FROM files ORDER BY id LIMIT 2','--db',$DbFile)
Check 'a user-supplied LIMIT is not mangled by the fetch options' `
  (($r.Code -eq 0) -and ($r.Out -match '2 row\(s\)')) `
  "exit $($r.Code) / $($r.Err.Trim())"

$r = Run @('sql','--query','SELECT id FROM files ORDER BY id','--db',$DbFile,'--limit','3')
Check 'the row cap truncates at --limit' (($r.Code -eq 0) -and ($r.Out -match '3 row\(s\)')) "exit $($r.Code)"
Check 'and SAYS SO -- a silent cap reads as the whole answer' `
  ($r.Out -match 'ROW CAP REACHED') ''

# The other side of it: the banner must not cry wolf when nothing was cut off.
$r = Run @('sql','--query','SELECT id FROM files ORDER BY id LIMIT 3','--db',$DbFile,'--limit','3')
Check 'no cap banner when the result exactly fits' `
  (($r.Code -eq 0) -and ($r.Out -notmatch 'ROW CAP REACHED')) "exit $($r.Code)"

$r = Run @('sql','--query','SELECT COUNT(*) FROM refs a, refs b, refs c','--db',$DbFile,'--timeout-ms','600')
Check 'a cartesian join is interrupted by the time cap' `
  (($r.Code -eq 1) -and ($r.Err -match 'time cap')) "exit $($r.Code) / $($r.Err.Trim())"
# A timeout is not a read-only refusal, and telling the user it is sends them
# hunting for a write they never wrote.
Check 'the time cap does NOT report itself as a read-only refusal' `
  ($r.Err -notmatch 'is read-only') $r.Err.Trim()

# ---------------------------------------------------------------------------
# CHECK 5 -- JSON is a clean document on stdout, with types preserved
# ---------------------------------------------------------------------------
Write-Host ''
Write-Host '-- check 5: --json' -ForegroundColor Cyan

$r = Run @('sql','--query','SELECT 1 AS one','--db',$DbFile,'--json')
$obj = $null
try { $obj = $r.Out | ConvertFrom-Json } catch { }
Check 'stdout is ONE valid JSON document (the banner is on stderr)' ($null -ne $obj) $r.Out
if ($null -ne $obj) {
  Check 'it declares the stable schema sql/1' ($obj.schema -eq 'sql/1') "got $($obj.schema)"
  Check 'columns are named' (($obj.columns.Count -eq 1) -and ($obj.columns[0].name -eq 'one')) ''
  # An id that comes back as the string "12" instead of the number 12 is the
  # difference that makes a consumer's join silently match nothing.
  Check 'a numeric cell stays a JSON number, not a string' `
    ($obj.rows[0][0] -is [int64] -or $obj.rows[0][0] -is [int]) `
    ("type: " + $obj.rows[0][0].GetType().Name)
  Check 'truncated is reported explicitly' ($obj.truncated -eq $false) ''
}

$r = Run @('sql','--query','SELECT NULL AS n','--db',$DbFile,'--json')
$obj = $null
try { $obj = $r.Out | ConvertFrom-Json } catch { }
Check 'a NULL cell is JSON null, not the string "NULL"' `
  (($null -ne $obj) -and ($null -eq $obj.rows[0][0])) ''

# ---------------------------------------------------------------------------
# CHECK 6 -- it never creates a database, and never mutates one
# ---------------------------------------------------------------------------
Write-Host ''
Write-Host '-- check 6: no side effects' -ForegroundColor Cyan

$ghost = Join-Path $scratch 'no-such-index.sqlite'
$r = Run @('sql','--query','SELECT 1','--db',$ghost)
Check 'a missing --db is a usage error' (($r.Code -eq 2) -and ($r.Err -match 'not found')) "exit $($r.Code)"
# EXISTENCE IS NOT SUFFICIENCY, and its cousin: a read-only SQLite open still
# CREATES the file. That once left a 4096-byte drag-lint.sqlite in an arbitrary
# directory and reported it as a valid, empty index.
Check 'and it did NOT create the file it was pointed at' (-not (Test-Path -LiteralPath $ghost)) $ghost

# POSITIVE CONTROL on the fingerprint itself: a value that failed to parse would
# compare equal to another failure and the check would pass while measuring
# nothing.
Check 'the data fingerprint was actually read' ($fpBefore -match '^\d+(/\d+){4}$') "before = $fpBefore"
$fpAfter = Fingerprint
Check 'the index DATA is unchanged after every query above' ($fpBefore -eq $fpAfter) `
  "before $fpBefore / after $fpAfter"

Remove-Item -LiteralPath $scratch -Recurse -Force -ErrorAction SilentlyContinue

Write-Host ''
if ($script:Failed) { Write-Host 'SQL VERB GUARD: FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'SQL VERB GUARD: PASS' -ForegroundColor Green
exit 0
