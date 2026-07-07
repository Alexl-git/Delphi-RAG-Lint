# drag-lint read-only-verb regression test (v0.86, Task 4).
#
# Read-looking verbs (outline, query, surface, context, dump-refs, find-unit)
# must NOT mutate the index. Before this task every read verb called Migrate,
# whose FTS5 probe / stamp / DROP-TRIGGER block issues DDL on the shared DB
# (the win32 trigger-drop bug + general DDL-on-read). The mutation sentinel is
# the DB file's md5 AND the trigger count in sqlite_master: a pure read must
# leave both byte-identical.
#
# Also asserts a pre-current (v12-shaped) DB gets the actionable
#   index schema v12 < v<N>: run "drag-lint index <dir> --db <db>" to migrate
# message + nonzero exit from a read verb (outline), NOT a "no such column"
# (the target version <N> is the CURRENT SCHEMA_VERSION -- assertion matches
#  v12 < v\d+ so a future schema bump does not re-break this test)
# field error.
#
# Usage: pwsh -File tests/autotest/run_readonly_verbs.ps1 [-Exe <path>]
[CmdletBinding()]
param(
    [string] $Exe = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe",
    [string] $WorkDir = "$env:TEMP\drag-lint-readonly-verbs"
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

if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
if (Test-Path $WorkDir) { Remove-Item -Recurse -Force $WorkDir }
New-Item -ItemType Directory $WorkDir | Out-Null

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

$trigBase = TriggerCount $db
Check 'fixture has FTS5 sync triggers (>0)' ([int]$trigBase -gt 0) "triggers=$trigBase"

# --- run each read verb; DB md5 + trigger count must be UNCHANGED after each ---
# Give WAL a moment to checkpoint after the index write so the baseline md5 is
# stable (the read verbs must not touch it thereafter).
Start-Sleep -Milliseconds 200
$md5Base = Md5 $db

function ReadVerbUnchanged([string]$Label, [scriptblock]$Run) {
    & $Run *> $null
    $ec = $LASTEXITCODE
    Start-Sleep -Milliseconds 100
    $md5  = Md5 $db
    $trig = TriggerCount $db
    Check "$Label leaves md5 unchanged"        ($md5 -eq $md5Base)      "was=$md5Base now=$md5"
    Check "$Label leaves trigger count intact"  ($trig -eq $trigBase)    "was=$trigBase now=$trig"
}

ReadVerbUnchanged 'outline'      { & $Exe outline --file $pas --db $db }
ReadVerbUnchanged 'query --name' { & $Exe query --name TFoo --db $db }
ReadVerbUnchanged 'query --text' { & $Exe query --text "hello world" --db $db }
ReadVerbUnchanged 'surface'      { & $Exe surface --qname Fixture.TFoo --db $db }
ReadVerbUnchanged 'context'      { & $Exe context --task "modify Fixture.TFoo.Greet" --db $db }
ReadVerbUnchanged 'dump-refs'    { & $Exe dump-refs $pas --db $db }

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
Check 'read verb on v12 db prints actionable stale-schema line' `
    ($staleOut -match 'index schema v12 < v\d+: run "drag-lint index <dir> --db <db>" to migrate') `
    $staleOut
Check 'read verb on v12 db does NOT print a field error' `
    (-not ($staleOut -match 'no such column')) `
    $staleOut

Write-Host ''
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
