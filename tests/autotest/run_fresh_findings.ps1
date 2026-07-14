[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\drag-lint-fresh-findings"
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
$db = Join-Path $WorkDir 'ff.sqlite'

# Task 1: the schema verb reports the new column exists after a migrate.
# Force a migrate by indexing an empty dir (creates + migrates the db).
$src = Join-Path $WorkDir 'src'; New-Item -ItemType Directory $src | Out-Null
[System.IO.File]::WriteAllText((Join-Path $src 'Empty.pas'),
  "unit Empty;`r`ninterface`r`nimplementation`r`nend.`r`n", [System.Text.Encoding]::ASCII)
& $Exe index $src --db $db | Out-Null
$schema = (& $Exe schema --json --db $db) -join "`n"
Check "files.last_compiled_unix column exists" ($schema -match 'last_compiled_unix') "schema had no such column"

Write-Host ''
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
