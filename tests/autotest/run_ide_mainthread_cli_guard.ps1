<#
  run_ide_mainthread_cli_guard.ps1 -- IDE-MAINTHREAD-CLI: units whose CLI runs were
  moved off the IDE main thread must not grow a synchronous spawn back.

  It is a source guard because the behaviour needs a live IDE: a blocked message
  loop cannot be observed from a console. What makes the moved runs safe is proved by
  tests\plugin\run_cli_async.ps1; this one pins that the forms use it.

  Each row names a unit and how many synchronous spawns it may still hold. 0 = the
  unit runs nothing on the main thread. A non-zero budget is a site that is on a
  worker thread or a known main-thread site left for later, named in its note; the
  count stops a new one arriving unseen.

  POSITIVE CONTROL. -Plugin points the guard at another tree. The base commit of this
  branch (bea4f375) fails it on every row:
    git -C <repo> archive bea4f375 src/delphi-plugin | tar -x -C <dir>
    pwsh -File run_ide_mainthread_cli_guard.ps1 -Plugin <dir>\src\delphi-plugin
  The run also checks itself: a spawn line is added to an in-memory copy of each unit
  and must be counted, so a broken pattern cannot pass by matching nothing.

  Usage: pwsh -File tests\autotest\run_ide_mainthread_cli_guard.ps1
#>
[CmdletBinding()]
param(
  [string]$Plugin = "$PSScriptRoot\..\..\src\delphi-plugin"
)
$ErrorActionPreference = 'Stop'

$SpawnPattern = '\b(RunCaptureStdout|RunAndCaptureStdout|RunCaptureStreaming)\s*\('

function Strip-Comments([string]$t) {
  $t = [regex]::Replace($t, '\{[^}]*\}', '')
  $t = [regex]::Replace($t, '(?m)//.*$', '')
  return $t
}

function Count-Spawns([string]$t) {
  return [regex]::Matches((Strip-Comments $t), $SpawnPattern).Count
}

$Rows = @(
  @{ Unit = 'DragLint.Plugin.SymbolSearchForm'; Budget = 0; Note = 'timer-driven search' }
  @{ Unit = 'DragLint.Plugin.SearchForm';       Budget = 0; Note = 'debounced search' }
)

$failed = 0
foreach ($r in $Rows) {
  $path = Join-Path $Plugin ($r.Unit + '.pas')
  if (-not (Test-Path -LiteralPath $path)) { Write-Host "FAIL $($r.Unit): unit not found at $path" -ForegroundColor Red; $failed++; continue }
  $src = [IO.File]::ReadAllText($path)

  $probe = Count-Spawns ($src + "`r`nx:= RunCaptureStdout(a, b, 1);`r`n")
  $n = Count-Spawns $src
  if ($probe -ne ($n + 1)) { Write-Host "FAIL $($r.Unit): the pattern did not count a planted spawn ($probe vs $n)" -ForegroundColor Red; $failed++; continue }

  if ($n -gt $r.Budget) {
    Write-Host "FAIL $($r.Unit): $n synchronous spawn(s), budget $($r.Budget) ($($r.Note))" -ForegroundColor Red
    $failed++
  } else {
    Write-Host "ok   $($r.Unit): $n of $($r.Budget)"
  }
}

if ($failed -gt 0) { Write-Host "IDE-MAINTHREAD-CLI GUARD: FAIL ($failed)" -ForegroundColor Red; exit 1 }
Write-Host "IDE-MAINTHREAD-CLI GUARD: PASS ($($Rows.Count) units)" -ForegroundColor Green
exit 0
