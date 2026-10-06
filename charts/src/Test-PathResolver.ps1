<#
  Test-PathResolver.ps1 -- R2(a): where the chart scripts find the drag-lint engine and
  Graphviz dot (Resolve-DragLintEngine / Resolve-GraphvizDot in Emit-Common.ps1).

  Self-asserting and fast (no engine call, no database): it builds a fake installed layout
  and a fake repo layout under -OutDir, forces each step of each chain in turn, and checks
  which file comes back. Test-Emitters.ps1 runs it as E-R2 and fails on any line it returns;
  it can also be run on its own (exit 0 / 1).

  Environment: DRAGLINT_ENGINE, DRAGLINT_DOT and PATH are cleared for the duration and
  restored EXACTLY in a finally (absent stays absent). The real %APPDATA%\drag-lint\
  settings.json is never read or written -- every case passes -SettingsPath to a temp file.

  Engine order (pinned E-ORDER): -Engine -> DRAGLINT_ENGINE -> settings.json "engine" ->
  <app>\bin\drag-lint.exe -> the shared C:\Projects engine -> <repo>\third_party\dll-win64.
  The shared engine sits BEFORE the repo-relative copy on purpose: a worktree can hold an
  old build there (this one held 1.16.0-alpha against a deployed 1.22.0-alpha), and taking
  it would change every chart on this machine.
#>
[CmdletBinding()]
param(
  [string] $OutDir = (Join-Path $PSScriptRoot ('..\scratch\resolver-' + (Get-Date -Format 'yyyyMMdd-HHmmss'))),
  [switch] $Quiet
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Emit-Common.ps1')

$fail = New-Object System.Collections.ArrayList
function Fail([string] $code, [string] $msg) { [void]$fail.Add("[$code] $msg") }
function Chk([string] $code, $actual, $expected) { if ("$actual" -cne "$expected") { Fail $code "expected $expected, got $actual" } }
function Throws([string] $code, [scriptblock] $body) {
  try { $null = & $body; Fail $code 'expected a throw, got a result'; return '' } catch { return $_.Exception.Message }
}
function New-Exe([string] $Path) {
  New-Item -ItemType Directory -Force (Split-Path -Parent $Path) | Out-Null
  [IO.File]::WriteAllText($Path, 'x')
  [IO.Path]::GetFullPath($Path)
}

New-Item -ItemType Directory -Force $OutDir | Out-Null
$root = Join-Path ([IO.Path]::GetFullPath($OutDir)) 'r2'
if (Test-Path -LiteralPath $root) { Remove-Item -LiteralPath $root -Recurse -Force }

# an installed layout: <app>\charts\src, <app>\bin\drag-lint.exe, <app>\graphviz\bin\dot.exe
$appCharts = Join-Path $root 'app\charts'
New-Item -ItemType Directory -Force (Join-Path $appCharts 'src') | Out-Null
$appEng = New-Exe (Join-Path $root 'app\bin\drag-lint.exe')
$appDot = New-Exe (Join-Path $root 'app\graphviz\bin\dot.exe')
# a repo layout: <repo>\charts\src, <repo>\third_party\dll-win64\drag-lint.exe
$repoCharts = Join-Path $root 'repo\charts'
New-Item -ItemType Directory -Force (Join-Path $repoCharts 'src') | Out-Null
$repoEng = New-Exe (Join-Path $root 'repo\third_party\dll-win64\drag-lint.exe')
# an empty charts root: neither layout
$bareCharts = Join-Path $root 'bare\charts'
New-Item -ItemType Directory -Force $bareCharts | Out-Null
$shared    = New-Exe (Join-Path $root 'shared\drag-lint.exe')
$sharedDot = New-Exe (Join-Path $root 'shared\dot.exe')
$noShared  = Join-Path $root 'nowhere\drag-lint.exe'
$noSharedDot = Join-Path $root 'nowhere\dot.exe'
$envEng = New-Exe (Join-Path $root 'env\drag-lint.exe')
$envDot = New-Exe (Join-Path $root 'env\dot.exe')
$setEng = New-Exe (Join-Path $root 'set\drag-lint.exe')
$setDot = New-Exe (Join-Path $root 'set\dot.exe')
$expEng = New-Exe (Join-Path $root 'explicit\drag-lint.exe')
$expDot = New-Exe (Join-Path $root 'explicit\dot.exe')
$pathDir = Join-Path $root 'pathdir'
$pathDot = New-Exe (Join-Path $pathDir 'dot.exe')
$emptyPath = Join-Path $root 'emptypath'
New-Item -ItemType Directory -Force $emptyPath | Out-Null

$setDir = Join-Path $root 'settings'
New-Item -ItemType Directory -Force $setDir | Out-Null
$setGood = Join-Path $setDir 'good.json'
[IO.File]::WriteAllText($setGood, (@{ engine = $setEng; dot = $setDot } | ConvertTo-Json))
$setBad = Join-Path $setDir 'bad.json'
[IO.File]::WriteAllText($setBad, '{ not json')
$setNoKey = Join-Path $setDir 'nokey.json'
[IO.File]::WriteAllText($setNoKey, '{ "other": "x" }')
$setGone = Join-Path $setDir 'gone.json'
$setStale = Join-Path $setDir 'stale.json'
[IO.File]::WriteAllText($setStale, (@{ engine = (Join-Path $root 'moved\drag-lint.exe'); dot = (Join-Path $root 'moved\dot.exe') } | ConvertTo-Json))

$saved = @{}
foreach ($n in 'DRAGLINT_ENGINE', 'DRAGLINT_DOT', 'PATH') { $saved[$n] = [Environment]::GetEnvironmentVariable($n, 'Process') }
function Clear-Env {
  Remove-Item Env:\DRAGLINT_ENGINE -ErrorAction SilentlyContinue
  Remove-Item Env:\DRAGLINT_DOT -ErrorAction SilentlyContinue
  $env:PATH = $emptyPath
}
try {
  # ---- engine -------------------------------------------------------------------------------
  Clear-Env
  $E = @{ SettingsPath = $setGood; ChartsRoot = $appCharts; SharedDefault = $shared }
  $env:DRAGLINT_ENGINE = $envEng
  Chk 'E-EXPLICIT' (Resolve-DragLintEngine $expEng @E) $expEng
  $m = Throws 'E-EXPLICIT-MISSING' { Resolve-DragLintEngine (Join-Path $root 'typo.exe') @E }
  if ($m -notlike "*-Engine*typo.exe*") { Fail 'E-EXPLICIT-MISSING' "the message does not name the -Engine path: $m" }
  Chk 'E-ENV' (Resolve-DragLintEngine '' @E) $envEng
  $env:DRAGLINT_ENGINE = Join-Path $root 'moved\drag-lint.exe'
  Chk 'E-ENV-MISSING' (Resolve-DragLintEngine '' @E) $setEng
  Clear-Env
  Chk 'E-SETTINGS' (Resolve-DragLintEngine '' @E) $setEng
  foreach ($c in @(@('E-SETTINGS-BAD', $setBad), @('E-SETTINGS-NOKEY', $setNoKey), @('E-SETTINGS-GONE', $setGone), @('E-SETTINGS-STALE', $setStale))) {
    Chk $c[0] (Resolve-DragLintEngine '' -SettingsPath $c[1] -ChartsRoot $appCharts -SharedDefault $shared) $appEng
  }
  Chk 'E-APP'    (Resolve-DragLintEngine '' -SettingsPath $setGone -ChartsRoot $appCharts  -SharedDefault $shared) $appEng
  Chk 'E-ORDER'  (Resolve-DragLintEngine '' -SettingsPath $setGone -ChartsRoot $repoCharts -SharedDefault $shared) $shared
  Chk 'E-REPO'   (Resolve-DragLintEngine '' -SettingsPath $setGone -ChartsRoot $repoCharts -SharedDefault $noShared) $repoEng
  Chk 'E-SHARED' (Resolve-DragLintEngine '' -SettingsPath $setGone -ChartsRoot $bareCharts -SharedDefault $shared) $shared
  $env:DRAGLINT_ENGINE = Join-Path $root 'moved\drag-lint.exe'
  $m = Throws 'E-NONE' { Resolve-DragLintEngine '' -SettingsPath $setStale -ChartsRoot $bareCharts -SharedDefault $noShared }
  $want = @('-Engine', 'DRAGLINT_ENGINE', (Join-Path $root 'moved\drag-lint.exe'), $setStale, '"engine"',
            [IO.Path]::GetFullPath((Join-Path $bareCharts '..\bin\drag-lint.exe')), $noShared,
            [IO.Path]::GetFullPath((Join-Path $bareCharts '..\third_party\dll-win64\drag-lint.exe')))
  $at = -1
  foreach ($w in $want) {
    $i = $m.IndexOf($w, [StringComparison]::OrdinalIgnoreCase)
    if ($i -lt 0) { Fail 'E-NONE' "the message does not name '$w': $m"; break }
    if ($i -lt $at) { Fail 'E-NONE' "the message names '$w' out of order: $m"; break }
    $at = $i
  }
  Clear-Env
  # the defaults as every emitter calls them: the per-user settings file, and on THIS machine the same engine as before R2
  Chk 'E-SETTINGS-PATH' (Get-DragLintSettingsPath) $(if ($env:APPDATA) { Join-Path $env:APPDATA 'drag-lint\settings.json' } else { '' })
  if (-not (Test-Path -LiteralPath (Get-DragLintSettingsPath))) {
    Chk 'E-DEFAULT-HERE' (Resolve-DragLintEngine '') 'C:\Projects\Delphi-RAG-lint\third_party\dll-win64\drag-lint.exe'
  }

  # ---- dot ----------------------------------------------------------------------------------
  Clear-Env
  $D = @{ SettingsPath = $setGood; ChartsRoot = $appCharts; SharedDefault = $sharedDot }
  $env:DRAGLINT_DOT = $envDot
  $env:PATH = $pathDir
  Chk 'D-EXPLICIT' (Resolve-GraphvizDot $expDot @D) $expDot
  $m = Throws 'D-EXPLICIT-MISSING' { Resolve-GraphvizDot (Join-Path $root 'typo-dot.exe') @D }
  if ($m -notlike "*-Dot*typo-dot.exe*") { Fail 'D-EXPLICIT-MISSING' "the message does not name the -Dot path: $m" }
  Chk 'D-ENV' (Resolve-GraphvizDot '' @D) $envDot
  Remove-Item Env:\DRAGLINT_DOT
  Chk 'D-SETTINGS' (Resolve-GraphvizDot '' @D) $setDot
  Chk 'D-SETTINGS-BAD' (Resolve-GraphvizDot '' -SettingsPath $setBad -ChartsRoot $appCharts -SharedDefault $sharedDot) $appDot
  Chk 'D-APP'    (Resolve-GraphvizDot '' -SettingsPath $setGone -ChartsRoot $appCharts  -SharedDefault $sharedDot) $appDot
  Chk 'D-PATH'   (Resolve-GraphvizDot '' -SettingsPath $setGone -ChartsRoot $bareCharts -SharedDefault $sharedDot) $pathDot
  $env:PATH = $emptyPath
  Chk 'D-SHARED' (Resolve-GraphvizDot '' -SettingsPath $setGone -ChartsRoot $bareCharts -SharedDefault $sharedDot) $sharedDot
  $env:DRAGLINT_DOT = Join-Path $root 'moved\dot.exe'
  $m = Throws 'D-NONE' { Resolve-GraphvizDot '' -SettingsPath $setStale -ChartsRoot $bareCharts -SharedDefault $noSharedDot }
  $want = @('-Dot', 'DRAGLINT_DOT', (Join-Path $root 'moved\dot.exe'), $setStale, '"dot"',
            [IO.Path]::GetFullPath((Join-Path $bareCharts '..\graphviz\bin\dot.exe')), 'PATH', $noSharedDot)
  $at = -1
  foreach ($w in $want) {
    $i = $m.IndexOf($w, [StringComparison]::OrdinalIgnoreCase)
    if ($i -lt 0) { Fail 'D-NONE' "the message does not name '$w': $m"; break }
    if ($i -lt $at) { Fail 'D-NONE' "the message names '$w' out of order: $m"; break }
    $at = $i
  }
} finally {
  foreach ($n in $saved.Keys) {
    if ($null -eq $saved[$n]) { Remove-Item "Env:\$n" -ErrorAction SilentlyContinue } else { Set-Item "Env:\$n" $saved[$n] }
  }
}
foreach ($n in $saved.Keys) {
  if ([Environment]::GetEnvironmentVariable($n, 'Process') -cne $saved[$n]) { Fail 'E-ENV-RESTORE' "$n was not restored" }
}

if (-not $Quiet) { Write-Host $(if ($fail.Count) { "  resolver: $($fail.Count) failure(s)" } else { '  resolver: PASS' }) }
# returned to Test-Emitters (each line one failure); the exit code is for a standalone run
$fail
if ($fail.Count) { exit 1 }
