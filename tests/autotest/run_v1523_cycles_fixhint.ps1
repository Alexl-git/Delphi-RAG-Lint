<#
  run_v1523_cycles_fixhint.ps1 -- 1.52.3 lane CYCLES-FIXHINT: the `Fix it` hint of `cycles --plan --no-hub-surface`
  (text) and of `cycles --causes --json` with --no-hub-surface carries --no-hub-surface in its dry_run / apply
  commands, so the suggested command runs the SAME planner as the plan just printed (since 1.52 a bare
  `cycles --fix` runs R3 first).
  (a) text plan + --no-hub-surface: every `dry run :` / `apply   :` line names --no-hub-surface.
  (b) json  + --no-hub-surface: every fix.dry_run / fix.apply names --no-hub-surface.
  POSITIVE CONTROL (c): the same plan WITHOUT the flag has no --no-hub-surface in the hint (the flag is not
  printed unconditionally).
  Fixture: tests\cyclefix\shop (copied).
#>
[CmdletBinding()]
param(
  [string]$Exe     = '',
  [string]$WorkDir = "$env:TEMP\drag-lint-v1523-fixhint-$PID"
)
if (-not $Exe) { $Exe = $(if (Test-Path -LiteralPath "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe") { "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe" } else { "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe" }) }
$ErrorActionPreference = 'Stop'
$script:Failed = $false
function Check($n, $ok, $d = '') {
  $s = if ($ok) { 'PASS' } else { 'FAIL' }
  $c = if ($ok) { 'Green' } else { 'Red' }
  Write-Host ("  [{0}] {1} {2}" -f $s, $n, $d) -ForegroundColor $c
  if (-not $ok) { $script:Failed = $true }
}
if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
$Exe  = (Resolve-Path $Exe).Path
$Repo = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$Src  = Join-Path $Repo 'tests\cyclefix\shop'
$Tree = Join-Path $WorkDir 'shop'
New-Item -ItemType Directory -Force $Tree | Out-Null
Get-ChildItem $Src -File | Where-Object { $_.Extension -in '.pas', '.dpr', '.dproj' } |
  ForEach-Object { Copy-Item $_.FullName (Join-Path $Tree $_.Name) -Force }
$Dproj = Join-Path $Tree 'Shop.dproj'
$Db    = Join-Path $WorkDir 'shop.sqlite'

function Invoke-Engine([string]$Tag, [string[]]$Args2) {
  $o = Join-Path $WorkDir "$Tag.out"
  $p = Start-Process -FilePath $Exe -WorkingDirectory $WorkDir -NoNewWindow -Wait -PassThru -ArgumentList $Args2 `
    -RedirectStandardOutput $o -RedirectStandardError (Join-Path $WorkDir "$Tag.err"); $null = $p.Handle
  return @{ Exit = $p.ExitCode; Out = [IO.File]::ReadAllText($o) }
}

$null = Invoke-Engine 'index' @('index', '--project', ('"' + $Dproj + '"'), '--db', ('"' + $Db + '"'))
$base = @('--db', ('"' + $Db + '"'), '--project', ('"' + $Dproj + '"'), '--library-db', 'none')

# (a) text plan, planner flag given
$a = Invoke-Engine 'a' (@('cycles', '--plan', '--no-hub-surface') + $base)
$lines = @($a.Out -split "`r?`n" | Where-Object { $_ -match '^\s*(dry run|apply)\s*:' })
Check 'a: text plan prints dry run / apply lines' ($lines.Count -ge 2) ("n=$($lines.Count) exit=$($a.Exit)")
Check 'a: every dry run / apply line names --no-hub-surface' (($lines | Where-Object { $_ -notmatch '--no-hub-surface' }).Count -eq 0 -and $lines.Count -ge 2)

# (b) json, planner flag given
$b = Invoke-Engine 'b' (@('cycles', '--causes', '--format', 'json', '--no-hub-surface') + $base)
$cmds = @([regex]::Matches($b.Out, '(?:dry_run|apply)"\s*:\s*"(.*?[^\\])"\s*[,}\r\n]') | ForEach-Object { $_.Groups[1].Value })
Check 'b: json carries dry_run / apply commands' ($cmds.Count -ge 2) ("n=$($cmds.Count) exit=$($b.Exit)")
Check 'b: every json command names --no-hub-surface' (($cmds | Where-Object { $_ -notmatch '--no-hub-surface' }).Count -eq 0 -and $cmds.Count -ge 2)

# (c) positive control: no flag -> R3's own hint (--hub-surface commands); none names --no-hub-surface
$c = Invoke-Engine 'c' (@('cycles', '--causes', '--format', 'json') + $base)
$cc = @([regex]::Matches($c.Out, '(?:dry_run|apply)"\s*:\s*"(.*?[^\\])"\s*[,}\r\n]') | ForEach-Object { $_.Groups[1].Value })
Check 'c: control: the default json carries commands' ($cc.Count -ge 2) ("n=$($cc.Count)")
Check 'c: control: and none names --no-hub-surface' (($cc | Where-Object { $_ -match '--no-hub-surface' }).Count -eq 0)
if ($script:Failed) { Write-Host 'FAILED' -ForegroundColor Red; exit 1 }
Write-Host 'run_v1523_cycles_fixhint: all PASS' -ForegroundColor Green
exit 0
