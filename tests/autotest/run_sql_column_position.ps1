<#
  run_sql_column_position.ps1 -- a `sql_column` symbol sits on the line and
  column of its OWN identifier.

  THE DEFECT (INBOX-sql-column-start-line-one-early.md, charts 2026-09-24):
  ParseColumnList.FlushItem took the column's position from the item's first
  character -- the one just past the comma -- which is the newline before a
  column written on its own line. Every such column was recorded ONE LINE EARLY
  (CAUSFAIL.REASON at 1410 for 1411; FOLDERCOUNT."TABLE" at 3847 for
  MS1.SQL:3848), so every chart anchored on a column opened the script a line
  above it.

  The first column, written on the CREATE line right after `(`, has no newline
  before it and was already right: it is the control that a fix which merely
  added 1 to every line would break.
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\drag-lint-sql-colpos-$PID"
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

# MS*.SQL: the extractor indexes migration scripts by that name by default.
$sql = @(
  '/* fixture */'
  'CREATE TABLE CAUSFAIL (ID INTEGER NOT NULL,'
  '  REASON VARCHAR(40),'
  '    NOTE_TEXT VARCHAR(200),'
  '  "TABLE" VARCHAR(10),'
  '  AMOUNT NUMERIC(10,2),'
  '  PRIMARY KEY (ID));'
) -join "`r`n"
$sqlPath = Join-Path $WorkDir 'MSFIX.SQL'
[IO.File]::WriteAllText($sqlPath, $sql + "`r`n", [Text.Encoding]::ASCII)
$db = Join-Path $WorkDir 'sql.sqlite'

$lines = [IO.File]::ReadAllLines($sqlPath)
function PosOf([string]$Token) {
  for ($i = 0; $i -lt $lines.Count; $i++) {
    $c = $lines[$i].IndexOf($Token)
    if ($c -ge 0) { return @(($i + 1), ($c + 1)) }
  }
  return @(-1, -1)
}
$expect = [ordered]@{
  'ID'        = PosOf 'ID INTEGER'
  'REASON'    = PosOf 'REASON'
  'NOTE_TEXT' = PosOf 'NOTE_TEXT'
  'TABLE'     = PosOf '"TABLE"'
  'AMOUNT'    = PosOf 'AMOUNT'
}

& $Exe index $WorkDir --db $db 2>&1 | Out-Null
Check 'fixture indexed' ((Test-Path $db) -and $LASTEXITCODE -eq 0) "exit=$LASTEXITCODE"

# sql --json rows are POSITIONAL arrays: map them onto columns[].name.
$raw = & $Exe sql --db $db --json --query "SELECT name, start_line, start_col FROM symbols WHERE kind = 'sql_column' ORDER BY start_line, start_col" 2>$null | Out-String
$doc = $raw | ConvertFrom-Json
$names = @($doc.columns | ForEach-Object { $_.name })
$got = @{}
foreach ($r in @($doc.rows)) {
  $o = @{}
  for ($k = 0; $k -lt $names.Count; $k++) { $o[$names[$k]] = $r[$k] }
  $got[[string]$o.name] = @([int]$o.start_line, [int]$o.start_col)
}
Write-Host ("  sql_column rows: {0}" -f (($got.GetEnumerator() | Sort-Object Name | ForEach-Object { "$($_.Key)@$($_.Value[0]):$($_.Value[1])" }) -join ', ')) -ForegroundColor DarkGray
Check 'all five columns indexed (PRIMARY KEY clause is not a column)' ($got.Count -eq 5) "count=$($got.Count)"

foreach ($kv in $expect.GetEnumerator()) {
  $n = $kv.Key; $want = $kv.Value
  $have = if ($got.ContainsKey($n)) { $got[$n] } else { @(-1, -1) }
  $label = if ($n -eq 'ID') { "ID (on the CREATE line -- the control)" } else { $n }
  Check ("{0} at line {1}" -f $label, $want[0]) ($have[0] -eq $want[0]) ("got line {0}" -f $have[0])
  Check ("{0} at column {1}" -f $label, $want[1]) ($have[1] -eq $want[1]) ("got col {0}" -f $have[1])
}

if (Test-Path $WorkDir) { Remove-Item -Recurse -Force $WorkDir -ErrorAction SilentlyContinue }
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
