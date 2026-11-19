<#
  run_v1511_CLI_f3_resolve_only_no_library_warns.ps1 -- lane v1511 CLI, item F3 (controller).
  `index --project <p> --db <db outside the manifest> --resolve-only` attaches no library
  store, so the calls pass silently clears every refs.external_target the DB had (32908 -> 0
  on a CLIENT copy). Now the run says so on stderr when the DB was resolved against a library
  before (external_stores meta) and this run attaches none: "no library store attached:
  external targets will be cleared; pass --library-db".
  Hermetic: a folder library LIB (uLibA.LibAdd), a program P calling it.
    control: --resolve-only WITH --library-db keeps external targets, no warning;
    case:    --resolve-only WITHOUT it warns (and the targets are cleared -- the behaviour
             itself is unchanged, only announced).
  Usage: pwsh -File tests\autotest\run_v1511_CLI_f3_resolve_only_no_library_warns.ps1 [-Exe <exe>]
#>
param([string]$Exe = '')
# Defaults that need the script path are resolved HERE, not in param(): Windows PowerShell 5 run with
# -File leaves $PSScriptRoot/$MyInvocation empty inside an advanced script's param block (Repo became C:\).
if (-not $Exe) { $Exe = (Join-Path $PSScriptRoot '..\..\src\cli\Win64\Debug\drag-lint.exe') }
$ErrorActionPreference = 'Stop'
$exePath = (Resolve-Path $Exe).Path
$scratch = Join-Path $env:TEMP ("v1511_cli_f3_" + $PID)
$fail = 0
function Check([string]$Name, [bool]$Ok, [string]$Detail = '') {
  if ($Ok) { Write-Host "PASS $Name" } else { Write-Host "FAIL $Name $Detail" -ForegroundColor Red; $script:fail++ }
}
function WriteAscii([string]$Path, [string]$Text) {
  [IO.File]::WriteAllText($Path, ($Text -replace "`r`n", "`n" -replace "`n", "`r`n"), (New-Object System.Text.ASCIIEncoding))
}
function ExtCount([string]$Db) {
  $o = & $exePath sql --query "SELECT COUNT(*) AS n FROM refs WHERE external_target IS NOT NULL" --db $Db --json 2>$null | Out-String
  try { $j = $o | ConvertFrom-Json; return [int]$j.rows[0][0] } catch { return -1 }
}
try {
  foreach ($d in 'lib', 'p') { New-Item -ItemType Directory -Path (Join-Path $scratch $d) -Force | Out-Null }
  WriteAscii (Join-Path $scratch 'lib\uLibA.pas') "unit uLibA;`n`ninterface`n`nfunction LibAdd(A, B: Integer): Integer;`n`nimplementation`n`nfunction LibAdd(A, B: Integer): Integer;`nbegin`n  Result := A + B;`nend;`n`nend.`n"
  WriteAscii (Join-Path $scratch 'p\P.dpr') "program P;`n`nuses`n  uLibA;`n`nvar`n  N: Integer;`n`nbegin`n  N := LibAdd(1, 2);`n  N := LibAdd(N, 3);`nend.`n"
  $lib = Join-Path $scratch 'lib.sqlite'; $db = Join-Path $scratch 'p.sqlite'
  & $exePath index (Join-Path $scratch 'lib') --db $lib 2>&1 | Out-Null
  & $exePath index --project (Join-Path $scratch 'p\P.dpr') --db $db --library-db $lib 2>&1 | Out-Null
  $n0 = ExtCount $db
  Check 'sanity: the project DB has external targets after a run with --library-db' ($n0 -gt 0) "n=$n0"

  $c1 = Join-Path $scratch 'c1.sqlite'; Copy-Item $db $c1
  $e1 = Join-Path $scratch 'c1.err'
  & $exePath index --project (Join-Path $scratch 'p\P.dpr') --db $c1 --resolve-only --library-db $lib 1>$null 2> $e1
  Check 'control: --resolve-only WITH --library-db keeps the external targets' ((ExtCount $c1) -eq $n0) "n=$(ExtCount $c1)"
  Check 'control: --resolve-only WITH --library-db prints no warning' (-not ([IO.File]::ReadAllText($e1) -match 'no library store attached'))

  $c2 = Join-Path $scratch 'c2.sqlite'; Copy-Item $db $c2
  $e2 = Join-Path $scratch 'c2.err'
  & $exePath index --project (Join-Path $scratch 'p\P.dpr') --db $c2 --resolve-only 1>$null 2> $e2
  $err2 = [IO.File]::ReadAllText($e2)
  Check 'case: the run without a library KEEPS the stored targets (1.52 EXTR; 1.51.1 cleared them)' ((ExtCount $c2) -eq $n0) "n=$(ExtCount $c2) want $n0"
  Check 'case: stderr warns "no library store attached ... pass --library-db"' ($err2 -match 'no library store attached: library bindings are kept from the last library run, not refreshed; pass --library-db') $err2
} finally {
  if (Test-Path -LiteralPath $scratch) { [IO.Directory]::Delete($scratch, $true) }
}
if ($fail -gt 0) { Write-Host "FAIL ($fail)" -ForegroundColor Red; exit 1 }
Write-Host 'PASS' -ForegroundColor Green; exit 0
