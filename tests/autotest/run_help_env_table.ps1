<#
  run_help_env_table.ps1 -- the "Environment variables" section of --help names
  EVERY DRAGLINT_* environment variable a binary under src\ reads, and nothing
  else (leftovers O3, wave 152b lane CLI).

  THE DEFECT
  ----------
  77 DRAGLINT_* names were read by the engine, LSP / MCP, charts and
  drag-lint-open.exe; --help named none of them, README / AI-USAGE a handful.
  The section is printed from ONE const table (ENV_VARS_HELP in
  src\cli\DRagLint.CLI.pas); this guard keeps the table equal to the source.

  CHECKS
    E1  the source scan finds the variables (non-empty answer, >= 40 names)
    E2  --help has the section and prints >= 40 rows
    E3  every quoted 'DRAGLINT_*' literal under src\ (.pas/.dpr) is a row of the section
    E4  every row of the section is still read somewhere under src\ (no stale rows), no duplicates
    E5  control: the same comparison over src\ + a fixture source holding a fake
        name FAILS and names it -- the check is capable of failing

  Run from any CWD, pwsh 7:
    pwsh -File tests\autotest\run_help_env_table.ps1 -Exe <drag-lint.exe> [-Repo <repo root>]
#>
[CmdletBinding()]
param(
  [string]$Exe  = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
  [string]$Repo = "$PSScriptRoot\..\.."
)
if (-not (Test-Path -LiteralPath $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
. "$PSScriptRoot\lib\HermeticEngine.ps1"; $Exe = Get-HermeticEngine $Exe
$ErrorActionPreference = 'Continue'
$script:Failed = $false
function Check($n, $ok, $d = '') {
  Write-Host ("[{0}] {1} {2}" -f (@('FAIL','PASS')[[int][bool]$ok]), $n, $d) -ForegroundColor (@('Red','Green')[[int][bool]$ok])
  if (-not $ok) { $script:Failed = $true }
}
$Repo = (Resolve-Path -LiteralPath $Repo).Path

function SourceNames([string[]]$roots) {
  $set = [Collections.Generic.SortedSet[string]]::new()
  foreach ($r in $roots) {
    Get-ChildItem -LiteralPath $r -Recurse -File -Include *.pas, *.dpr | ForEach-Object {
      $text = [regex]::Replace([IO.File]::ReadAllText($_.FullName), "\(Name: 'DRAGLINT_[A-Z0-9_]+';", '')   # the ENV_VARS_HELP rows themselves are not a read
      foreach ($m in [regex]::Matches($text, "'(DRAGLINT_[A-Z0-9_]+)'")) { [void]$set.Add($m.Groups[1].Value) }
    }
  }
  ,@($set)
}
# NOTE: rows of ENV_VARS_HELP are stripped before the scan, or the table would satisfy its own check.
function Missing($src, $rows) { ,@($src | Where-Object { $rows -notcontains $_ }) }

$src = SourceNames @(Join-Path $Repo 'src')
Check 'E1 source scan finds the variables (non-empty answer)' ($src.Count -ge 40) "names=$($src.Count)"

$help = @(& $Exe --help 2>$null)
$at = -1
for ($i = 0; $i -lt $help.Count; $i++) { if ($help[$i] -like 'Environment variables*') { $at = $i; break } }
$rows = @()
if ($at -ge 0) {
  for ($i = $at + 1; $i -lt $help.Count; $i++) {
    if ($help[$i] -match '^  (DRAGLINT_[A-Z0-9_]+)\s') { $rows += $Matches[1] } elseif ($help[$i].Trim() -ne '') { break }
  }
}
Check 'E2 --help prints the Environment variables section' ($at -ge 0 -and $rows.Count -ge 40) "rows=$($rows.Count)"

$miss = Missing $src $rows
Check 'E3 every DRAGLINT_* literal under src\ is in the section' ($miss.Count -eq 0) ($miss -join ', ')
$stale = @($rows | Where-Object { $src -notcontains $_ })
$dups  = @($rows | Group-Object | Where-Object Count -gt 1 | ForEach-Object Name)
Check 'E4 no stale row (every row is read under src\)' ($stale.Count -eq 0) ($stale -join ', ')
Check 'E4 no duplicate row' ($dups.Count -eq 0) ($dups -join ', ')

$fx = Join-Path ([IO.Path]::GetTempPath()) ('dl-env-table-' + [guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($fx) | Out-Null
try {
  [IO.File]::WriteAllText((Join-Path $fx 'FakeEnv.pas'), "unit FakeEnv;`r`ninterface`r`nimplementation`r`nconst X = 'DRAGLINT_FAKE_152B_CONTROL';`r`nend.`r`n", [Text.Encoding]::ASCII)
  $ctl = Missing (SourceNames @((Join-Path $Repo 'src'), $fx)) $rows
  Check 'E5 control: a fake name in a fixture source is reported missing' ($ctl -contains 'DRAGLINT_FAKE_152B_CONTROL') ($ctl -join ', ')
} finally {
  try { [IO.Directory]::Delete($fx, $true) } catch { }
}
if ($script:Failed) { Write-Host 'RESULT: FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'RESULT: PASS' -ForegroundColor Green
exit 0
