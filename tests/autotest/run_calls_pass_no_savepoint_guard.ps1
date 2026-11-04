<#
  run_calls_pass_no_savepoint_guard.ps1 -- the calls pass must be the OUTERMOST transaction.

  WHY. 1.41 IDX-HALFREAD wrapped clear + pass in the store's batch transaction, so the
  pass's own StartTransaction became a SAVEPOINT (FireDAC nesting). Every row write then
  opens a statement savepoint inside it, and releasing that truncates the in-memory
  sub-journal (temp_store = MEMORY) to a NON-ZERO size, which walks the journal's linked
  list from its head (memjrnlTruncate). One walk per written row, over a list that grows
  with every page the pass touches: quadratic in the pass. The 1.42 re-parse: DragLint-Cli
  calls 343 s -> 2348 s, the libraries 34 min -> 5.5 h and counting. A timing assertion on
  a fixture this small could not fail, so the guard reads the cause: the nesting level the
  pass itself prints under DRAGLINT_PROFILE.

    N1 positive control: an incremental index (a file edited, no clear asked) prints the line at
       nesting 1 -- no line would make the guard vacuous; this path was never affected
    N2 `index --resolve-only` (the path that clears first): nesting 1. RED before the fix: 2
    N3 it still ends 0 with the same resolved-ref and call-edge counts (same rows)
    N4 the first index of a new DB (stale resolver stamp, clears first): nesting 1. RED before: 2

  Scratch only (-WorkDir); never a real project DB. Needs python on PATH. pwsh 7.
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\drag-lint-nosavepoint-guard-$PID"
)
$ErrorActionPreference = 'Stop'
$script:Failed = $false
function Check([string]$Name, [bool]$Ok, [string]$Detail = '') {
  if ($Ok) { Write-Host "PASS  $Name  $Detail" } else { Write-Host "FAIL  $Name  $Detail" -ForegroundColor Red; $script:Failed = $true }
}
function Run-Exe([string[]]$ArgList) {
  $psi = New-Object System.Diagnostics.ProcessStartInfo
  $psi.FileName = $Exe
  $psi.Arguments = (($ArgList | ForEach-Object { if ($_ -match '\s') { '"' + $_ + '"' } else { $_ } }) -join ' ')
  $psi.UseShellExecute = $false; $psi.CreateNoWindow = $true
  $psi.RedirectStandardOutput = $true; $psi.RedirectStandardError = $true
  $psi.WorkingDirectory = $WorkDir
  $psi.EnvironmentVariables['DRAGLINT_PROFILE'] = '1'
  $p = [System.Diagnostics.Process]::Start($psi)
  $o = $p.StandardOutput.ReadToEndAsync(); $e = $p.StandardError.ReadToEndAsync()
  if (-not $p.WaitForExit(120000)) { try { $p.Kill($true) } catch { } }
  $p.WaitForExit()
  return @{ Code = $p.ExitCode; Text = $o.Result + $e.Result }
}
function Nesting([string]$Text) {
  $m = [regex]::Match($Text, 'calls\s+transaction nesting (\d+)')
  if ($m.Success) { return [int]$m.Groups[1].Value }
  return -1
}
function Scalar([string]$Db, [string]$Sql) {
  return [int](& python -I -c "import sqlite3,sys; c=sqlite3.connect(sys.argv[1]); print(c.execute(sys.argv[2]).fetchone()[0])" $Db $Sql)
}
$ResolvedSql = 'SELECT count(*) FROM refs WHERE symbol_id IS NOT NULL'
$EdgesSql    = 'SELECT count(*) FROM call_edges'

try {
  if (-not (Test-Path $Exe)) { Write-Host "FATAL: engine not found: $Exe" -ForegroundColor Red; exit 2 }
  $Exe = (Resolve-Path $Exe).Path
  if (Test-Path $WorkDir) { [IO.Directory]::Delete($WorkDir, $true) }
  $src = Join-Path $WorkDir 'src'
  New-Item -ItemType Directory $src -Force | Out-Null
  for ($i = 1; $i -le 4; $i++) {
    $j = if ($i -lt 4) { $i + 1 } else { 1 }
    $t = "unit NestUnit$i;`r`n`r`ninterface`r`n`r`nprocedure Work$i(A: Integer);`r`n`r`nimplementation`r`n`r`nuses NestUnit$j;`r`n`r`nprocedure Work$i(A: Integer);`r`nbegin`r`n  if A > 0 then begin Work$i(A - 1); Work$j(A - 1); end;`r`nend;`r`n`r`nend.`r`n"
    [IO.File]::WriteAllText((Join-Path $src "NestUnit$i.pas"), $t, [Text.Encoding]::ASCII)
  }
  $db = Join-Path $WorkDir 'nest.sqlite'
  $first = Run-Exe @('index', $src, '--db', $db)
  if ($first.Code -ne 0) { Write-Host "FATAL: setup index failed: $($first.Text)" -ForegroundColor Red; exit 2 }
  $n4 = Nesting $first.Text
  $u1 = Join-Path $src 'NestUnit1.pas'
  [IO.File]::AppendAllText($u1, "
{ edited }
", [Text.Encoding]::ASCII)
  $inc = Run-Exe @('index', $src, '--db', $db)
  $n1 = Nesting $inc.Text
  Check 'N1 positive control: an incremental index prints the nesting line, level 1' ($n1 -eq 1) "nesting=$n1"
  $r0 = Scalar $db $ResolvedSql
  $e0 = Scalar $db $EdgesSql
  if (($r0 -le 0) -or ($e0 -le 0)) { Write-Host "FATAL: setup resolved nothing (refs=$r0 edges=$e0)" -ForegroundColor Red; exit 2 }

  $v = Run-Exe @('index', $src, '--db', $db, '--resolve-only')
  $n2 = Nesting $v.Text
  Check 'N2 --resolve-only: the calls pass is the outermost transaction, not a SAVEPOINT' ($n2 -eq 1) "nesting=$n2"
  $r1 = Scalar $db $ResolvedSql
  $e1 = Scalar $db $EdgesSql
  Check 'N3 --resolve-only ends 0 with the same rows' (($v.Code -eq 0) -and ($r1 -eq $r0) -and ($e1 -eq $e0)) "exit=$($v.Code) refs $r0->$r1 edges $e0->$e1"
  Check 'N4 the first index of a new DB: the calls pass is the outermost transaction' ($n4 -eq 1) "nesting=$n4"
}
catch {
  Write-Host "FATAL: $($_.Exception.Message)" -ForegroundColor Red
  exit 2
}
finally {
  try { if (Test-Path $WorkDir) { [IO.Directory]::Delete($WorkDir, $true) } } catch { }
}
if ($script:Failed) { exit 1 }
Write-Host 'ALL PASS'
exit 0
