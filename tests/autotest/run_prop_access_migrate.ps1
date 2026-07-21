# drag-lint prop_access column migration test (proptree assignability engine,
# Task 1).
#
# A pre-prop_access index (symbols table shaped like the current schema, but
# WITHOUT the prop_access column) must migrate transparently on the next
# drag-lint run: ALTER TABLE symbols ADD COLUMN prop_access TEXT, existing
# rows read back prop_access IS NULL, schema_version bumps, and a SECOND run
# against the already-migrated DB must be idempotent (no error, no duplicate
# column). No accessor extraction happens yet (that is a later task) -- the
# column ships empty for now; this test only proves the DB plumbing.
#
# Usage: pwsh -File tests/autotest/run_prop_access_migrate.ps1 [-Exe <path>]
[CmdletBinding()]
param(
    [string] $Exe = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe",
    [string] $FixtureDir = "$PSScriptRoot\..\fixtures\formsmap",
    [string] $WorkDir = "$env:TEMP\drag-lint-prop-access-migrate"
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
$db = "$WorkDir\pre.sqlite"

# --- build a pre-prop_access DB: symbols table shaped like the current
#     (v16) schema (incl. the is_helper column that only exists via ALTER),
#     WITHOUT prop_access, carrying one pre-existing row.
#     schema_version is stamped '10' (deliberately BELOW any real engine
#     version, old or new) rather than '16': TSQLiteSymbolStore.Create has an
#     eager-PrepareStatements-before-Migrate fast path gated on
#     IsSchemaCurrent (stored version >= the exe's SCHEMA_VERSION). Stamping
#     '16' would coincidentally read as "current" against the UNCHANGED
#     (pre-task) exe -- whose SCHEMA_VERSION is still 16 -- even though this
#     hand-rolled fixture only has 3 of ~20 tables, so the eager prepare
#     would run against an incomplete DB and crash with an unrelated
#     "no such table" error before Migrate ever gets to build the rest.
#     A version safely below the target keeps IsSchemaCurrent False for both
#     the old and new exe, so Migrate always runs first, as it would for a
#     genuinely old real-world DB. ---
$py = "$WorkDir\make_pre.py"
@'
import sqlite3, sys
c = sqlite3.connect(sys.argv[1])
c.executescript("""
CREATE TABLE schema_meta (key TEXT PRIMARY KEY, value TEXT NOT NULL);
INSERT INTO schema_meta(key, value) VALUES ('schema_version', '10');
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
  impl_start_line INTEGER, impl_end_line INTEGER, is_helper INTEGER);
INSERT INTO files(id, path, mtime_unix, sha256, parsed_at, language)
  VALUES (1, 'dummy.pas', 0, 'x', 0, 'pascal');
INSERT INTO symbols(id, file_id, parent_id, kind, name, qualified_name,
  signature, modifiers, section, heritage, is_virtual, start_line, start_col,
  end_line, end_col, impl_start_line, impl_end_line, is_helper)
  VALUES (1, 1, NULL, 'property', 'Caption', 'TFoo.Caption',
  NULL, NULL, 'published', NULL, NULL, 10, 3, 10, 30, NULL, NULL, NULL);
""")
c.commit()
c.close()
'@ | Set-Content $py -Encoding ascii
python $py $db
Check 'pre-prop_access fixture DB created' (($LASTEXITCODE -eq 0) -and (Test-Path $db))

# --- 1. index onto the old DB must migrate + succeed (self-heal path) ---
$idxOut = & $Exe index $FixtureDir --db $db 2>&1
Check 'index onto pre-prop_access db exits 0' ($LASTEXITCODE -eq 0) (($idxOut | Select-Object -Last 1))

# --- 2. column must now exist (exactly once); pre-existing row reads NULL ---
$chk = "$WorkDir\check.py"
@'
import sqlite3, sys
c = sqlite3.connect("file:" + sys.argv[1] + "?mode=ro", uri=True)
cols = [r[1] for r in c.execute("PRAGMA table_info(symbols)")]
has_col = "prop_access" in cols
n_cols = cols.count("prop_access")
if has_col:
    row = c.execute("SELECT prop_access FROM symbols WHERE id=1").fetchone()
    existing_null = (row is not None) and (row[0] is None)
else:
    existing_null = False
ver = c.execute("SELECT value FROM schema_meta WHERE key='schema_version'").fetchone()[0]
print(has_col, n_cols, existing_null, ver)
'@ | Set-Content $chk -Encoding ascii
$state = (python $chk $db) -split '\s+'
Check 'symbols.prop_access column added'         ($state[0] -eq 'True')
Check 'prop_access column appears exactly once'  ($state[1] -eq '1')
Check 'existing row prop_access IS NULL'         ($state[2] -eq 'True')
Check 'schema_version bumped past 16'             ([int]$state[3] -gt 16) "(got $($state[3]))"

# --- 3. re-open (already-migrated DB) must be idempotent: no error, no dup column ---
$idxOut2 = & $Exe index $FixtureDir --db $db 2>&1
Check 'second index (idempotent re-migrate) exits 0' ($LASTEXITCODE -eq 0) (($idxOut2 | Select-Object -Last 1))
$state2 = (python $chk $db) -split '\s+'
Check 'prop_access still appears exactly once after re-migrate' ($state2[1] -eq '1')

Write-Host ''
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
