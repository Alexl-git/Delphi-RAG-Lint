<#
  run_sqlite_bundled.ps1 -- the engine loads ONLY the sqlite3.dll shipped
  beside it (2026-10-07).

  THE PROBLEM. Nothing set FireDAC's VendorLib, so the loader took whatever
  sqlite3.dll PATH reached first. Measured on the reference machine: RAD
  Studio 13's Studio\37.0\bin64\sqlite3.dll. drag-lint therefore depended on a
  Delphi 13 install (a 10.3-only machine has no x64 sqlite3.dll on PATH at
  all), and the SQLite version -- which decides the query planner -- moved with
  whatever happened to be installed.

  THE FIX. third_party\dll-win64\sqlite3.dll (see third_party\SQLITE-VERSION.txt)
  is staged beside the exe, and DRagLint.Storage.SQLite pins VendorLib to
  <exe dir>\sqlite3.dll at unit initialization.

  WHAT THIS PINS.
    S1  --version names the pinned version and the path beside the exe.
    S2  with every Embarcadero folder removed from PATH the engine still opens
        and indexes a database (FTS5 and the trigram index included).
    S3  a copy of the exe WITHOUT sqlite3.dll beside it fails with exit 3 and
        names the expected path -- even though PATH still reaches a Studio
        sqlite3.dll, which proves PATH is never consulted.

  Usage: pwsh -File tests/autotest/run_sqlite_bundled.ps1 [-Exe <path>]
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\drag-lint-sqlite-bundled-$PID"
)
try {
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
$ExeDir = Split-Path $Exe
$repo = (Resolve-Path "$PSScriptRoot\..\..").Path
$record = Get-Content (Join-Path $repo 'third_party\SQLITE-VERSION.txt') -Raw
$pinned = if ($record -match 'Version\s*:\s*(\d+\.\d+\.\d+)') { $Matches[1] } else { '' }
Check 'precondition: SQLITE-VERSION.txt names a version' ($pinned -ne '') "pinned=$pinned"
if (Test-Path $WorkDir) { Remove-Item -Recurse -Force $WorkDir }
New-Item -ItemType Directory $WorkDir | Out-Null

# --- S1 ---------------------------------------------------------------------------
Write-Host 'S1 -- --version names the bundled engine' -ForegroundColor Cyan
$v = (@(& $Exe --version 2>&1) | ForEach-Object { "$_" }) -join "`n"
Check 'S1 exits 0' ($LASTEXITCODE -eq 0) $v
Check 'S1 reports the pinned version' ($v -match ('sqlite ' + [regex]::Escape($pinned) + ' ')) $v
Check 'S1 the library path is beside the exe' ($v -match [regex]::Escape((Join-Path $ExeDir 'sqlite3.dll'))) $v

# --- S2 ---------------------------------------------------------------------------
Write-Host ''
Write-Host 'S2 -- no Embarcadero folder on PATH' -ForegroundColor Cyan
$src = Join-Path $WorkDir 'src'
New-Item -ItemType Directory $src | Out-Null
[IO.File]::WriteAllText((Join-Path $src 'Probe.pas'),
  "unit Probe;`r`n`r`ninterface`r`n`r`nfunction Hello: string;`r`n`r`nimplementation`r`n`r`nfunction Hello: string;`r`nbegin`r`n  Result := 'bundled engine text';`r`nend;`r`n`r`nend.`r`n",
  [Text.Encoding]::ASCII)
$db = Join-Path $WorkDir 'probe.sqlite'
$oldPath = $env:PATH
try {
  $env:PATH = ($env:PATH -split ';' | Where-Object { $_ -and $_ -notmatch 'Embarcadero' }) -join ';'
  $o2 = (@(& $Exe index $src --db $db --quiet 2>&1) | ForEach-Object { "$_" }) -join "`n"
  $c2 = $LASTEXITCODE
  $v2 = (@(& $Exe --version 2>&1) | ForEach-Object { "$_" }) -join "`n"
} finally { $env:PATH = $oldPath }
Check 'S2 index exits 0' ($c2 -eq 0) $o2
Check 'S2 FTS5 available' ($o2 -match 'FTS5 probe: AVAILABLE') $o2
Check 'S2 still the pinned engine' ($v2 -match ('sqlite ' + [regex]::Escape($pinned) + ' ')) $v2
$py = Join-Path $WorkDir 'q.py'
[IO.File]::WriteAllText($py, "import sqlite3,sys`nc=sqlite3.connect(sys.argv[1])`nprint(c.execute(sys.argv[2]).fetchone()[0])`n", [Text.Encoding]::ASCII)
$tri = (python $py $db "SELECT COUNT(*) FROM string_fts_tri WHERE string_fts_tri MATCH '""ed engi""'") -join ''
Check 'S2 the trigram index holds the literal' ($tri -eq '1') "hits=$tri"

# --- S3 ---------------------------------------------------------------------------
Write-Host ''
Write-Host 'S3 -- exe without sqlite3.dll beside it' -ForegroundColor Cyan
$lone = Join-Path $WorkDir 'lone'
New-Item -ItemType Directory $lone | Out-Null
Copy-Item $Exe $lone
Get-ChildItem $ExeDir -Filter 'tree-sitter*.dll' | Copy-Item -Destination $lone
$studioOnPath = @($env:PATH -split ';' | Where-Object { $_ -match 'Embarcadero' -and (Test-Path (Join-Path $_ 'sqlite3.dll')) }).Count
Write-Host "  (PATH folders holding a Studio sqlite3.dll: $studioOnPath -- S3 is strongest when > 0)"
$o3 = (@(& (Join-Path $lone 'drag-lint.exe') --version 2>&1) | ForEach-Object { "$_" }) -join "`n"
Check 'S3 exits 3' ($LASTEXITCODE -eq 3) $o3
Check 'S3 names the expected path beside the exe' ($o3 -match [regex]::Escape((Join-Path $lone 'sqlite3.dll'))) $o3
Check 'S3 prints no engine version (nothing fell back to PATH)' ($o3 -notmatch 'sqlite \d+\.\d+') $o3

Write-Host ''
if ($script:Failed) { Write-Host 'RESULT: FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'RESULT: PASS' -ForegroundColor Green
exit 0
}
finally {
  if ($WorkDir -and (Test-Path $WorkDir)) { Remove-Item -Recurse -Force $WorkDir -ErrorAction SilentlyContinue }
}
