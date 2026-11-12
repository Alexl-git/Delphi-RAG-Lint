<#
  run_sql_json_cap_reported.ps1 -- `drag-lint sql --json` must say when its row
  cap cut the answer, how many rows there were, and let the caller lift the cap
  (leftovers O8, wave 152b lane CLI).

  THE DEFECT
  ----------
  151 RB-B built a diff on `sql --json` and got 200 of 1226 rows: the JSON said
  `truncated: true` but nothing on stderr, no total, and `--limit 0` silently
  meant "default 200", so there was no way to ask for every row.

  CASES (rows come from a recursive CTE, so the fixture DB content is irrelevant)
    J1  1226 rows, default        -> 200 rows, truncated=true, row_limit=200, total_rows=1226, stderr NOTE
    J2  1226 rows, --limit 0      -> 1226 rows, truncated=false, total_rows=1226, no NOTE
    J3  control: 150 rows, default -> 150 rows, truncated=false, total_rows=150, no NOTE
    J4  1226 rows, --limit 10, text -> footer names the cap AND the total 1226

  Run from any CWD, pwsh 7:
    pwsh -File tests\autotest\run_sql_json_cap_reported.ps1 -Exe <drag-lint.exe>
#>
[CmdletBinding()]
param(
  [string]$Exe = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe"
)
if (-not (Test-Path -LiteralPath $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
. "$PSScriptRoot\lib\HermeticEngine.ps1"; $Exe = Get-HermeticEngine $Exe
$ErrorActionPreference = 'Continue'
$script:Failed = $false
function Check($n, $ok, $d = '') {
  Write-Host ("[{0}] {1} {2}" -f (@('FAIL','PASS')[[int][bool]$ok]), $n, $d) -ForegroundColor (@('Red','Green')[[int][bool]$ok])
  if (-not $ok) { $script:Failed = $true }
}

$Work = Join-Path ([IO.Path]::GetTempPath()) ('dl-sql-cap-' + [guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($Work) | Out-Null
$unit = @('unit SqlCapU;', '', 'interface', '', 'procedure P;', '', 'implementation', '', 'procedure P;', 'begin', 'end;', '', 'end.')
$dpr  = @('program SqlCap;', '', 'uses', '  SqlCapU in ''SqlCapU.pas'';', '', 'begin', '  P;', 'end.')
[IO.File]::WriteAllText((Join-Path $Work 'SqlCapU.pas'), (($unit -join "`r`n") + "`r`n"), [Text.Encoding]::ASCII)
[IO.File]::WriteAllText((Join-Path $Work 'SqlCap.dpr'),  (($dpr  -join "`r`n") + "`r`n"), [Text.Encoding]::ASCII)

function Cte($n) { "WITH RECURSIVE n(x) AS (SELECT 1 UNION ALL SELECT x + 1 FROM n WHERE x < $n) SELECT x FROM n" }
function RunSql([string[]]$extra) {
  $errFile = Join-Path $Work ('err-' + [guid]::NewGuid().ToString('N') + '.txt')
  $out = (& $Exe sql --db $script:Db @extra 2> $errFile) -join "`n"
  $err = if (Test-Path $errFile) { [IO.File]::ReadAllText($errFile) } else { '' }
  [pscustomobject]@{ Out = $out; Err = $err; Exit = $LASTEXITCODE }
}
function J($r) { try { $r.Out | ConvertFrom-Json } catch { $null } }

Push-Location $Work
try {
  $script:Db = Join-Path $Work 'sqlcap.sqlite'
  $null = & $Exe index --project (Join-Path $Work 'SqlCap.dpr') --db $script:Db 2>&1
  Check 'index exit 0' ($LASTEXITCODE -eq 0) "exit=$LASTEXITCODE"

  $r1 = RunSql @('--query', (Cte 1226), '--json'); $j1 = J $r1
  Check 'J1 JSON parses, exit 0 (non-empty answer)' (($null -ne $j1) -and $r1.Exit -eq 0 -and @($j1.rows).Count -gt 0) "exit=$($r1.Exit)"
  Check 'J1 default prints 200 rows' (@($j1.rows).Count -eq 200) "rows=$(@($j1.rows).Count)"
  Check 'J1 truncated=true' ($j1.truncated -eq $true)
  Check 'J1 row_limit=200' ($j1.row_limit -eq 200) "row_limit=$($j1.row_limit)"
  Check 'J1 total_rows=1226' ($j1.total_rows -eq 1226) "total_rows=$($j1.total_rows)"
  Check 'J1 stderr NOTE names the cap and the total' ($r1.Err -match 'NOTE' -and $r1.Err -match '1226' -and $r1.Err -match '--limit') $r1.Err.Trim()

  $r2 = RunSql @('--query', (Cte 1226), '--json', '--limit', '0'); $j2 = J $r2
  Check 'J2 --limit 0 prints all 1226 rows' (@($j2.rows).Count -eq 1226) "rows=$(@($j2.rows).Count)"
  Check 'J2 truncated=false, total_rows=1226' ($j2.truncated -eq $false -and $j2.total_rows -eq 1226)
  Check 'J2 no NOTE on stderr' ($r2.Err -notmatch 'NOTE') $r2.Err.Trim()

  $r3 = RunSql @('--query', (Cte 150), '--json'); $j3 = J $r3
  Check 'J3 control: 150 rows, truncated=false' (@($j3.rows).Count -eq 150 -and $j3.truncated -eq $false)
  Check 'J3 control: total_rows=150' ($j3.total_rows -eq 150) "total_rows=$($j3.total_rows)"
  Check 'J3 control: no NOTE on stderr' ($r3.Err -notmatch 'NOTE') $r3.Err.Trim()

  $r4 = RunSql @('--query', (Cte 1226), '--limit', '10')
  Check 'J4 text footer names the cap and the total' ($r4.Out -match 'ROW CAP REACHED at 10 rows' -and $r4.Out -match '1226') (@($r4.Out -split "`n" | Select-Object -Last 2) -join ' | ')

  # --output is the documented full-dump route (GR3 FOUND-152b): no --limit = EVERY row.
  $f5 = Join-Path $Work 'j5.json'
  $r5 = RunSql @('--query', (Cte 1226), '--json', '--output', $f5)
  $j5 = $null; try { $j5 = [IO.File]::ReadAllText($f5) | ConvertFrom-Json } catch { }
  Check 'J5 --output without --limit writes all 1226 rows' ($null -ne $j5 -and @($j5.rows).Count -eq 1226 -and $j5.truncated -eq $false) "rows=$(@($j5.rows).Count) exit=$($r5.Exit)"
  Check 'J5 no NOTE on stderr' ($r5.Err -notmatch 'NOTE') $r5.Err.Trim()
  $f6 = Join-Path $Work 'j6.json'
  $r6 = RunSql @('--query', (Cte 1226), '--json', '--output', $f6, '--limit', '10')
  $j6 = $null; try { $j6 = [IO.File]::ReadAllText($f6) | ConvertFrom-Json } catch { }
  Check 'J6 control: --output --limit 10 writes 10 rows, truncated, total 1226' ($null -ne $j6 -and @($j6.rows).Count -eq 10 -and $j6.truncated -eq $true -and $j6.total_rows -eq 1226) "rows=$(@($j6.rows).Count)"
  Check 'J6 control: and says so on stderr' ($r6.Err -match 'NOTE' -and $r6.Err -match '1226') $r6.Err.Trim()
} finally {
  Pop-Location
  try { [IO.Directory]::Delete($Work, $true) } catch { }
}
if ($script:Failed) { Write-Host 'RESULT: FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'RESULT: PASS' -ForegroundColor Green
exit 0
