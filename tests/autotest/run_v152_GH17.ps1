<#
  run_v152_GH17.ps1 -- GitHub #17 (owner ruling 1.52): an empty find-callees exits 1 (as query find-callers),
  and a sql stopped by the --timeout-ms cap exits 2 ("nothing was answered", docs\AI-USAGE.md exit-code table).
  1. find-callees on a routine that calls nothing exits 1 (today 0).
  2. sql stopped by the time cap exits 2 (was 1), "time cap" on stderr.
  3. controls: find-callees on a routine that calls something exits 0; a fast sql with rows exits 0;
     an empty sql SELECT still exits 0 (unchanged: sql is a query surface, not a grep-style verb).
  pwsh 7.
#>
[CmdletBinding()]
param([string]$Exe = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe")
$ErrorActionPreference = 'Stop'
$script:fail = $false
function Check($n, $ok, $d) {
  Write-Host ("[{0}] {1}" -f (@('FAIL', 'PASS')[[int][bool]$ok]), $n)
  if (-not $ok) { if ($d) { Write-Host "      $d" }; $script:fail = $true }
}
$exe = (Resolve-Path $Exe).Path
$work = Join-Path ([IO.Path]::GetTempPath()) ("dl_gh17_" + [guid]::NewGuid().ToString('N').Substring(0, 8))
$fx = Join-Path $work 'fx'
[void][IO.Directory]::CreateDirectory($fx)
[IO.File]::WriteAllText((Join-Path $fx 'Shapes.pas'), ("unit Shapes;`r`ninterface`r`nprocedure DoNothing;`r`nprocedure DoSome;`r`nimplementation`r`nprocedure DoNothing; begin end;`r`nprocedure DoSome; begin DoNothing; end;`r`nend.`r`n"), [Text.Encoding]::ASCII)
$db = Join-Path $work 'fx.sqlite'
Push-Location $work
try {
  & $exe index $fx --db $db *> $null
  Check 'fixture indexed' ($LASTEXITCODE -eq 0) "exit $LASTEXITCODE"
  $o = (& $exe find-callees --qname Shapes.DoNothing --db $db 2>&1 | Out-String); $rc = $LASTEXITCODE
  Check 'find-callees, no callee: exit 1' ($rc -eq 1) "exit $rc / $($o.Trim())"
  $o = (& $exe find-callees --qname Shapes.DoSome --db $db 2>&1 | Out-String); $rc = $LASTEXITCODE
  Check 'control: find-callees with a callee: exit 0' ($rc -eq 0 -and $o -match 'DoNothing') "exit $rc / $($o.Trim())"
  $o = (& $exe sql --query 'WITH RECURSIVE c(x) AS (SELECT 1 UNION ALL SELECT x+1 FROM c LIMIT 50000000) SELECT count(*) FROM c' --timeout-ms 200 --db $db 2>&1 | Out-String); $rc = $LASTEXITCODE
  Check 'sql time cap: exit 2' ($rc -eq 2 -and $o -match 'time cap') "exit $rc / $($o.Trim())"
  $o = (& $exe sql --query 'SELECT name FROM symbols' --db $db 2>&1 | Out-String); $rc = $LASTEXITCODE
  Check 'control: fast sql with rows exits 0' ($rc -eq 0 -and $o -match 'DoNothing') "exit $rc"
  $o = (& $exe sql --query 'SELECT id FROM symbols WHERE 0' --db $db 2>&1 | Out-String); $rc = $LASTEXITCODE
  Check 'control: empty sql SELECT exits 0' ($rc -eq 0) "exit $rc"
}
finally {
  Pop-Location
  try { [IO.Directory]::Delete($work, $true) } catch { }
}
if ($script:fail) { Write-Host 'FAIL'; exit 1 }
Write-Host 'PASS'; exit 0
