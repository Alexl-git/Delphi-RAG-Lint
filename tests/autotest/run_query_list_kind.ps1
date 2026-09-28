<#
  run_query_list_kind.ps1 -- `query --kind <k> --all` lists EVERY symbol of a
  kind: no name, no doc clause, no row cap.

  WHY (INBOX-2026-09-24-converter-to-engine-list-units-and-object-leak #1): the
  converter's unit picker needs "every unit in DB X". No verb could say it:
  `query --kind unit` demands --name, `query find --kind unit` demands a doc
  clause, and `query find --no-docs --kind unit` -- the obvious spelling -- is a
  FILTER (undocumented units only), so the picker silently listed 2,103 of
  5,646 library units. The editor fell back to `sql`, whose default row cap of
  200 is one more silent truncation.

  WHAT IS PINNED
    * 250 units, one of them DOCUMENTED -> all 250 listed (text and JSON).
      250 > 200 proves no row cap; the documented one proves it is not the
      --no-docs filter.
    * --kind class --all lists classes, not units (the kind is honoured).
    * CONTROLS (unchanged behaviour): `query --kind unit` without --all still
      exits 2 asking for --name; `query --all` without --kind exits 2 and says
      --kind is required.
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\drag-lint-query-list-kind-$PID"
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

$N = 250
$nl = "`r`n"
for ($k = 1; $k -le $N; $k++) {
  $name = 'LU{0:D3}' -f $k
  $doc = if ($k -eq 1) { "/// <summary>The one DOCUMENTED unit -- a --no-docs filter would drop it.</summary>$nl" } else { '' }
  $cls = if ($k -eq 2) { "type$nl  TListMe = class$nl  end;$nl" } else { '' }
  $src = "${doc}unit $name;$nl${nl}interface$nl$nl${cls}implementation$nl${nl}end.$nl"
  [IO.File]::WriteAllText((Join-Path $WorkDir "$name.pas"), $src, [Text.Encoding]::ASCII)
}
$db = Join-Path $WorkDir 'list.sqlite'
& $Exe index $WorkDir --db $db *> $null
Check 'fixture indexed' ((Test-Path $db) -and $LASTEXITCODE -eq 0) "exit=$LASTEXITCODE"

Write-Host ''
Write-Host 'query --kind unit --all' -ForegroundColor Cyan
$text = @(& $Exe query --kind unit --all --db $db 2>$null)
$textExit = $LASTEXITCODE
$found = @($text | Where-Object { $_ -match '\bLU\d{3}\b' } | ForEach-Object { [regex]::Match($_, '\bLU\d{3}\b').Value } | Sort-Object -Unique)
Check 'exits 0' ($textExit -eq 0) "exit=$textExit"
Check "text lists all $N units (more than sql's 200-row default)" ($found.Count -eq $N) "found=$($found.Count)"
Check 'the DOCUMENTED unit LU001 is listed (not the --no-docs filter)' ($found -contains 'LU001')

$json = (& $Exe query --kind unit --all --json --db $db 2>$null) | Out-String
$rows = @()
try { $rows = @($json | ConvertFrom-Json) } catch { }
$jNames = @($rows | ForEach-Object { $_.name } | Where-Object { $_ -match '^LU\d{3}$' } | Sort-Object -Unique)
Check "--json parses and lists all $N units" ($jNames.Count -eq $N) "rows=$($rows.Count) unit names=$($jNames.Count)"

Write-Host ''
Write-Host 'the kind is honoured' -ForegroundColor Cyan
$cls = @(& $Exe query --kind class --all --db $db 2>$null)
Check 'query --kind class --all lists TListMe' (@($cls | Where-Object { $_ -match '\bTListMe\b' }).Count -ge 1) "lines=$($cls.Count)"
Check 'and lists no unit rows' (@($cls | Where-Object { $_ -match '\bunit\b.*\bLU\d{3}\b' }).Count -eq 0)

Write-Host ''
Write-Host 'controls: unchanged behaviour' -ForegroundColor Cyan
$o1 = (& $Exe query --kind unit --db $db 2>&1) | Out-String
Check 'query --kind unit WITHOUT --all still exits 2 asking for --name' (($LASTEXITCODE -eq 2) -and ($o1 -match '--name')) "exit=$LASTEXITCODE"
$o2 = (& $Exe query --all --db $db 2>&1) | Out-String
Check 'query --all WITHOUT --kind exits 2 and names --kind' (($LASTEXITCODE -eq 2) -and ($o2 -match '--kind')) "exit=$LASTEXITCODE out=$($o2.Trim())"

if (Test-Path $WorkDir) { Remove-Item -Recurse -Force $WorkDir -ErrorAction SilentlyContinue }
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
