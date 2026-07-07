# drag-lint schema-migration regression test (D5 Task 13, v13 -> v14).
#
# Existing (pre-D5) user indexes are stamped schema_version=13 and have NO
# call_edges table. When the D5 exe opens such a DB, TSQLiteSymbolStore.Migrate
# re-runs SCHEMA_DDL (which now includes 'CREATE TABLE IF NOT EXISTS
# call_edges (...)' -- Task 1) and stamps schema_meta.schema_version=14. This
# must happen with NO crash, and a subsequent reindex must POPULATE call_edges
# (ResolveCallTargets, Task 6), proving the upgraded DB yields a working call
# graph, not just an empty table.
#
# A pre-D5 exe is not available, so we SIMULATE a v13 DB: index the receivers.pas
# fixture with the CURRENT (D5) exe, then hand-mutate the resulting DB to look
# like a genuine v13 DB (schema_version -> '13', DROP TABLE call_edges). We
# assert the mutated DB really is v13-shaped (version=13, call_edges absent)
# BEFORE migrating, so the AFTER assertions are non-vacuous -- they would fail
# if Migrate did not (re)create call_edges / bump the stamped version.
#
# Usage: pwsh -File tests/callresolve/run_migrate_v13_to_v14.ps1 [-Exe <path>]
[CmdletBinding()]
param(
    [string] $Exe = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe",
    [string] $FixtureDir = "$PSScriptRoot\fixtures",
    [string] $WorkDir = "$env:TEMP\drag-lint-migrate-v13"
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
$exePath = (Resolve-Path $Exe).Path
if (Test-Path $WorkDir) { Remove-Item -Recurse -Force $WorkDir }
New-Item -ItemType Directory $WorkDir | Out-Null

# Isolate the fixture to its own scratch source dir (only receivers.pas) so the
# index run is small and deterministic -- other callresolve fixtures are unrelated.
$srcDir = Join-Path $WorkDir 'src'
New-Item -ItemType Directory $srcDir | Out-Null
Copy-Item (Join-Path $FixtureDir 'receivers.pas') (Join-Path $srcDir 'receivers.pas') -Force

$db = Join-Path $WorkDir 'v13.sqlite'

Push-Location C:\TEMP
try {
    # --- 0. build a real (v14) index with the CURRENT D5 exe -----------------
    & $exePath index $srcDir --db $db 2>&1 | Out-Null
    Check 'seed index (current exe) exits 0' ($LASTEXITCODE -eq 0)
    Check 'seed db created' (Test-Path $db)

    # --- 1. hand-mutate the seed DB to look like a genuine v13 DB -------------
    # (stamp schema_version back to 13; drop call_edges + its indexes, mirroring
    # what a real pre-D5 index looks like). Uses the same python-sqlite3
    # mechanism as tests/autotest/run_migrate_v12.ps1.
    $mutate = "$WorkDir\mutate_to_v13.py"
    @'
import sqlite3, sys
c = sqlite3.connect(sys.argv[1])
c.executescript("""
UPDATE schema_meta SET value='13' WHERE key='schema_version';
DROP TABLE IF EXISTS call_edges;
""")
c.commit()
c.close()
'@ | Set-Content $mutate -Encoding ascii
    python $mutate $db
    Check 'v13 mutation script exits 0' ($LASTEXITCODE -eq 0)

    # --- 2. confirm the "v13 state" BEFORE migrating (non-vacuous baseline) --
    $probe = "$WorkDir\probe.py"
    @'
import sqlite3, sys
c = sqlite3.connect(sys.argv[1])
ver = c.execute("SELECT value FROM schema_meta WHERE key='schema_version'").fetchone()[0]
tbl = c.execute("SELECT name FROM sqlite_master WHERE type='table' AND name='call_edges'").fetchone()
print(ver, tbl is None)
'@ | Set-Content $probe -Encoding ascii
    $before = (python $probe $db) -split '\s+'
    Check 'BEFORE: schema_version == 13'       ($before[0] -eq '13')
    Check 'BEFORE: call_edges table ABSENT'    ($before[1] -eq 'True')

    # --- 3. migrate: reindex the SAME fixture into the SAME (mutated) db ------
    # This is the realistic upgrade path: opening the store re-runs SCHEMA_DDL
    # (Migrate) THEN re-parses + ResolveCallTargets, so call_edges is both
    # created and repopulated in one step.
    $idxOut = & $exePath index $srcDir --db $db 2>&1
    Check 'migrate reindex exits 0' ($LASTEXITCODE -eq 0) (($idxOut | Select-Object -Last 1))

    # --- 4. assert the upgrade ------------------------------------------------
    $after = "$WorkDir\after.py"
    @'
import sqlite3, sys
c = sqlite3.connect(sys.argv[1])
ver = c.execute("SELECT value FROM schema_meta WHERE key='schema_version'").fetchone()[0]
tbl = c.execute("SELECT name FROM sqlite_master WHERE type='table' AND name='call_edges'").fetchone()
cols = [r[1] for r in c.execute("PRAGMA table_info(call_edges)")]
idx_target = c.execute("SELECT name FROM sqlite_master WHERE name='idx_call_edges_target'").fetchone()
idx_ref = c.execute("SELECT name FROM sqlite_master WHERE name='idx_call_edges_ref'").fetchone()
cnt = c.execute("SELECT COUNT(*) FROM call_edges").fetchone()[0]
print(ver, tbl is not None, idx_target is not None, idx_ref is not None, cnt, ",".join(sorted(cols)))
'@ | Set-Content $after -Encoding ascii
    $state = (python $after $db) -split '\s+'
    # Assert >= 14 (not an exact '14') so later schema bumps (e.g. v15 for the
    # enum-helper first-class indexing milestone) don't spuriously fail this
    # v13-origin migration check -- the real assertion is "Migrate advanced the
    # DB past v13 and (re)created call_edges", not a specific version literal.
    Check 'AFTER: schema_version >= 14'            ([int]$state[0] -ge 14)
    Check 'AFTER: call_edges table EXISTS'          ($state[1] -eq 'True')
    Check 'AFTER: idx_call_edges_target created'    ($state[2] -eq 'True')
    Check 'AFTER: idx_call_edges_ref created'       ($state[3] -eq 'True')
    $rowCount = [int]$state[4]
    Check 'AFTER: call_edges POPULATED (> 0 rows)'  ($rowCount -gt 0) "(rows=$rowCount)"
    $expectedCols = 'confidence,receiver_type_symbol_id,ref_id,target_symbol_id'
    Check 'AFTER: call_edges has expected columns'  ($state[5] -eq $expectedCols) "(got: $($state[5]))"

    # --- 5. sanity: a resolved-callers query works against the migrated db ---
    $callersOut = & $exePath query find-callers --name Run --resolved --db $db 2>&1
    Check 'find-callers --resolved exits 0 on migrated db' ($LASTEXITCODE -eq 0)
} finally { Pop-Location }

Write-Host ''
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
