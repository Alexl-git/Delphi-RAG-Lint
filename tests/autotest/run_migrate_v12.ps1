# drag-lint schema-migration regression test (v0.83.1).
#
# A pre-v13 index (refs table WITHOUT enclosing_symbol_id) must migrate
# transparently on the next drag-lint run. Regression: the core SCHEMA_DDL
# loop contained 'CREATE INDEX idx_refs_enclosing ON refs(enclosing_symbol_id)'
# which ran BEFORE the v13 ALTER TABLE retrofit, so every command that calls
# Migrate on an old DB died with "no such column: enclosing_symbol_id"
# (seen in the wild via the IDE forms-csv menu on a v12 per-project DB).
#
# Usage: pwsh -File tests/autotest/run_migrate_v12.ps1 [-Exe <path>]
[CmdletBinding()]
param(
    [string] $Exe = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe",
    [string] $FixtureDir = "$PSScriptRoot\..\fixtures\formsmap",
    [string] $WorkDir = "$env:TEMP\drag-lint-migrate-v12"
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
$db = "$WorkDir\v12.sqlite"

# --- build a minimal v12-shaped DB: refs WITHOUT enclosing_symbol_id ---
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
python $py $db
Check 'v12 fixture DB created' (($LASTEXITCODE -eq 0) -and (Test-Path $db))

# --- 1. index into the old DB must migrate + succeed (self-heal path) ---
$idxOut = & $Exe index $FixtureDir --db $db 2>&1
Check 'index onto v12 db exits 0' ($LASTEXITCODE -eq 0) (($idxOut | Select-Object -Last 1))

# --- 2. column must now exist, schema stamped v13+ ---
$chk = "$WorkDir\check.py"
@'
import sqlite3, sys
c = sqlite3.connect(sys.argv[1])
cols = [r[1] for r in c.execute("PRAGMA table_info(refs)")]
ver = c.execute("SELECT value FROM schema_meta WHERE key='schema_version'").fetchone()[0]
idx = c.execute("SELECT name FROM sqlite_master WHERE name='idx_refs_enclosing'").fetchone()
print(("enclosing_symbol_id" in cols), int(ver) >= 13, idx is not None)
'@ | Set-Content $chk -Encoding ascii
$state = (python $chk $db) -split '\s+'
Check 'refs.enclosing_symbol_id added'  ($state[0] -eq 'True')
Check 'schema_version stamped >= 13'    ($state[1] -eq 'True')
Check 'idx_refs_enclosing created'      ($state[2] -eq 'True')

# --- 3. forms-csv against the migrated DB must succeed (user scenario) ---
$out = "$WorkDir\forms.csv"
& $Exe forms-csv --project "$FixtureDir\Demo.dproj" --db $db --out $out 2>&1 | Out-Null
Check 'forms-csv exits 0' ($LASTEXITCODE -eq 0)
Check 'csv exists' (Test-Path $out)

# --- 4. forms-csv alone on a FRESH v12 db (no prior index) must also migrate ---
$db2 = "$WorkDir\v12b.sqlite"
python $py $db2
& $Exe forms-csv --project "$FixtureDir\Demo.dproj" --db $db2 --out "$WorkDir\forms2.csv" 2>&1 | Out-Null
Check 'forms-csv directly on v12 db exits 0' ($LASTEXITCODE -eq 0)

Write-Host ''
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
