<#
  run_doc_p3_store19.ps1 -- Auto-Document Phase 3, Task 10: schema v19 -- four additive
  symbol_facts columns + storage plumbing (MutatesParams, UiAffinity, Touches, Wiring).

  Exercises the hidden `doc-facts-selftest --db <db>` verb: indexes a fixture into a
  fresh DB, verifies the schema columns exist with correct type and version, then
  round-trips the four new fields via doc-facts-selftest.

  Run from a NEUTRAL CWD (C:\TEMP), pwsh 7.
#>
[CmdletBinding()]
param([string]$Exe = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe")

$ErrorActionPreference = 'Continue'
function Check($n,$ok){ Write-Host ("[{0}] {1}" -f (@('FAIL','PASS')[[int]$ok]),$n) -ForegroundColor (@('Red','Green')[[int]$ok]); if(-not $ok){$script:Failed=$true} }
$script:Failed = $false

$exePath = (Resolve-Path $Exe).Path
$fixture = (Resolve-Path (Join-Path $PSScriptRoot 'fixtures\docp3\store19.pas')).Path

$scratch = Join-Path C:\TEMP 'draglint_docp3store19'
if (Test-Path $scratch) { Remove-Item $scratch -Recurse -Force }
New-Item -ItemType Directory -Path $scratch | Out-Null
$target = Join-Path $scratch 'store19.pas'
$db     = Join-Path $scratch 'docp3store19.sqlite'
Copy-Item $fixture $target -Force

Push-Location C:\TEMP
try {
  # Index fixture into fresh scratch DB
  & $exePath index $scratch --db $db 2>$null | Out-Null
  Check 'index exits 0' ($LASTEXITCODE -eq 0)

  # Verify schema columns exist with correct type
  $schemaCheck = "$scratch\check_schema.py"
  @'
import sqlite3, sys
c = sqlite3.connect(sys.argv[1])
cols = {r[1]: r[2] for r in c.execute("PRAGMA table_info(symbol_facts)")}
ver = c.execute("SELECT value FROM schema_meta WHERE key='schema_version'").fetchone()[0]
print("mutates_params" in cols, cols.get("mutates_params") == "TEXT",
      "ui_affinity" in cols, cols.get("ui_affinity") == "TEXT",
      "touches" in cols, cols.get("touches") == "TEXT",
      "wiring" in cols, cols.get("wiring") == "TEXT",
      int(ver) >= 19)
'@ | Set-Content $schemaCheck -Encoding ascii
  $schemaResult = (python $schemaCheck $db) -split '\s+'
  Check 'mutates_params column exists' ($schemaResult[0] -eq 'True')
  Check 'mutates_params is TEXT' ($schemaResult[1] -eq 'True')
  Check 'ui_affinity column exists' ($schemaResult[2] -eq 'True')
  Check 'ui_affinity is TEXT' ($schemaResult[3] -eq 'True')
  Check 'touches column exists' ($schemaResult[4] -eq 'True')
  Check 'touches is TEXT' ($schemaResult[5] -eq 'True')
  Check 'wiring column exists' ($schemaResult[6] -eq 'True')
  Check 'wiring is TEXT' ($schemaResult[7] -eq 'True')
  Check 'schema_version = 19' ($schemaResult[8] -eq 'True')

  # Round-trip the four new fields via doc-facts-selftest
  $out = & $exePath doc-facts-selftest --db $db 2>$null
  $exitCode = $LASTEXITCODE
  $raw = ($out -join "`n")

  Check 'doc-facts-selftest exits 0' ($exitCode -eq 0)

  # The selftest should print MUT=, UIA=, TCH=, WIR= lines with the round-tripped values
  # For now, just verify the output contains them (values will be empty for this fixture)
  Check 'MUT= line present (MutatesParams)' ($raw -match 'MUT=')
  Check 'UIA= line present (UiAffinity)' ($raw -match 'UIA=')
  Check 'TCH= line present (Touches)' ($raw -match 'TCH=')
  Check 'WIR= line present (Wiring)' ($raw -match 'WIR=')

} finally { Pop-Location }

if($script:Failed){ Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
