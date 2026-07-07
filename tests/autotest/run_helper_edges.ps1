# drag-lint first-class helper-target edge (type_helpers) regression test, v15.
#
# Covers two things:
#   1. End-to-end parser+resolve+store: indexing the Task 0 probe fixture
#      (_probe_helper.pas: TColorHelper = record helper for TColor; TPlain =
#      an unrelated plain record) must populate exactly one type_helpers row
#      (TColorHelper -> TColor) and zero for TPlain.
#   2. Migration regression (mirrors run_migrate_v12.ps1): a pre-v15 DB (schema
#      v14, symbols table without is_helper, no type_helpers table) must
#      migrate transparently on the next drag-lint run -- no "no such table:
#      type_helpers" / "no such column: is_helper" errors.
#
# Usage: pwsh -File tests/autotest/run_helper_edges.ps1 [-Exe <path>]
[CmdletBinding()]
param(
    [string] $Exe = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe",
    [string] $FixtureDir = "$PSScriptRoot\..\refactor\fixtures\enumhelper",
    [string] $WorkDir = "$env:TEMP\drag-lint-helper-edges"
)
$ErrorActionPreference = 'Stop'
$script:Failed = $false
function Check([string]$Name, [bool]$Ok, [string]$Detail='') {
    $status = if ($Ok) {'PASS'} else {'FAIL'}
    $color  = if ($Ok) {'Green'} else {'Red'}
    Write-Host ("  [{0}] {1} {2}" -f $status, $Name, $Detail) -ForegroundColor $color
    if (-not $Ok) { $script:Failed = $true }
}
if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
if (Test-Path $WorkDir) { Remove-Item -Recurse -Force $WorkDir }
New-Item -ItemType Directory $WorkDir | Out-Null

# --- 1. end-to-end: index the probe fixture, assert type_helpers content ---
$db1 = "$WorkDir\probe.sqlite"
$idxOut = & $Exe index $FixtureDir --db $db1 2>&1
Check 'index probe fixture exits 0' ($LASTEXITCODE -eq 0) (($idxOut | Select-Object -Last 1))

$py1 = "$WorkDir\check_edges.py"
@'
import sqlite3, sys
c = sqlite3.connect(sys.argv[1])
helper = c.execute(
    "SELECT th.target_name, th.helper_kind, s.name FROM type_helpers th "
    "JOIN symbols s ON s.id = th.helper_symbol_id WHERE th.target_name = 'TColor'"
).fetchall()
plain = c.execute(
    "SELECT * FROM type_helpers WHERE target_name = 'TPlain'"
).fetchall()
tobyte = c.execute(
    "SELECT qualified_name FROM symbols WHERE name = 'ToByte'"
).fetchall()
print(len(helper), (helper[0][2] if helper else ''), (helper[0][1] if helper else ''), len(plain), len(tobyte))
'@ | Set-Content $py1 -Encoding ascii
$state1 = (python $py1 $db1) -split '\s+'
Check 'exactly 1 type_helpers edge for TColor'        ($state1[0] -eq '1')
Check 'edge helper symbol is TColorHelper'             ($state1[1] -eq 'TColorHelper')
Check 'edge helper_kind = record'                      ($state1[2] -eq 'record')
Check '0 type_helpers edges for TPlain'                ($state1[3] -eq '0')
Check 'ToByte (helper method) is indexed as a member'  ($state1[4] -eq '1')

# --- 2. migration regression: pre-v15 DB (schema v14, no is_helper column, ---
# ---    no type_helpers table) must self-heal on the next run.            ---
$db2 = "$WorkDir\v14.sqlite"
$py2 = "$WorkDir\make_v14.py"
@'
import sqlite3, sys
c = sqlite3.connect(sys.argv[1])
c.executescript("""
CREATE TABLE schema_meta (key TEXT PRIMARY KEY, value TEXT NOT NULL);
INSERT INTO schema_meta(key, value) VALUES ('schema_version', '14');
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
  end_line INTEGER NOT NULL, end_col INTEGER NOT NULL,
  enclosing_symbol_id INTEGER REFERENCES symbols(id) ON DELETE SET NULL);
CREATE TABLE type_ancestors (
  symbol_id INTEGER NOT NULL REFERENCES symbols(id) ON DELETE CASCADE,
  ordinal INTEGER NOT NULL, ancestor_name TEXT NOT NULL,
  ancestor_kind TEXT, ancestor_symbol_id INTEGER, ancestor_file_id INTEGER);
""")
c.commit()
c.close()
'@ | Set-Content $py2 -Encoding ascii
python $py2 $db2
Check 'v14 fixture DB created' (($LASTEXITCODE -eq 0) -and (Test-Path $db2))

$idxOut2 = & $Exe index $FixtureDir --db $db2 2>&1
Check 'index onto v14 db exits 0 (no "no such table/column" error)' ($LASTEXITCODE -eq 0) (($idxOut2 | Select-Object -Last 1))

$py3 = "$WorkDir\check_migrated.py"
@'
import sqlite3, sys
c = sqlite3.connect(sys.argv[1])
cols = [r[1] for r in c.execute("PRAGMA table_info(symbols)")]
ver = c.execute("SELECT value FROM schema_meta WHERE key='schema_version'").fetchone()[0]
th = c.execute("SELECT name FROM sqlite_master WHERE type='table' AND name='type_helpers'").fetchone()
helper_rows = c.execute("SELECT COUNT(*) FROM type_helpers WHERE target_name='TColor'").fetchone()[0]
print(("is_helper" in cols), int(ver) >= 15, th is not None, helper_rows)
'@ | Set-Content $py3 -Encoding ascii
$state3 = (python $py3 $db2) -split '\s+'
Check 'symbols.is_helper column added'      ($state3[0] -eq 'True')
Check 'schema_version stamped >= 15'        ($state3[1] -eq 'True')
Check 'type_helpers table created'          ($state3[2] -eq 'True')
Check 'type_helpers populated post-migrate' ($state3[3] -eq '1')

Write-Host ''
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
