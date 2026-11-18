<#
  run_v152_PLUGUI.ps1 -- lane PLUGUI (1.52): rules-search UX (N2) + Find Usages theme (N3).

  1. Static: PlugUiCore is in the .dpk contains AND the .dproj; UsagesForm calls
     ApplyIdeTheme and the themed row colours (no bare clWindow / clWindowText /
     clHighlight left in its custom draw); LintOptionsFrame has the clear button,
     the debounce timer and the wait cursor.
  2. Headless harness (fixtures\plugui\PlugUiHarness.dpr, Win64, stub ToolsAPI,
     private->public copy of the frame unit): row colours through a fake dark
     theme, refill rule, debounce count, clear button, wait cursor; reports the
     clear-the-search time (CLEAR_MS).
  3. -Build: Win32 + Win64 BPL builds of dclDragLintWizard.dproj into -WorkDir
     (never into third_party).

  Usage: pwsh -File tests\autotest\run_v152_PLUGUI.ps1 [-Build]
#>
[CmdletBinding()]
param(
  [switch]$Build,
  [string]$WorkDir = "$env:TEMP\drag-lint-v152-plugui-$PID",
  [string]$Rsvars  = 'C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\rsvars.bat'
)
$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path "$PSScriptRoot\..\..").Path
$plug = Join-Path $repo 'src\delphi-plugin'
$fix  = Join-Path $PSScriptRoot 'fixtures\plugui'
$fail = 0
function Bad([string]$m) { Write-Host "FAIL: $m" -ForegroundColor Red; $script:fail++ }
function Ok([string]$m)  { Write-Host "ok: $m" }
function Code([string]$text) {
  $t = [regex]::Replace($text, '\{[^}]*\}', '')
  return [regex]::Replace($t, '//[^\r\n]*', '')
}
function Run-Bat([string]$name, [string[]]$lines) {
  $bat = Join-Path $WorkDir "$name.bat"; $log = Join-Path $WorkDir "$name.log"
  [IO.File]::WriteAllText($bat, (($lines -join "`r`n") + "`r`n"), [Text.Encoding]::ASCII)
  $null = Start-Process cmd.exe -ArgumentList '/c', "`"$bat`"" -RedirectStandardOutput $log `
            -RedirectStandardError "$log.err" -NoNewWindow -Wait
  return (Get-Content $log -Raw -ErrorAction SilentlyContinue)
}

Write-Host '== PLUGUI static ==' -ForegroundColor Cyan
$dpk   = [IO.File]::ReadAllText("$plug\dclDragLintWizard.dpk")
$dproj = [IO.File]::ReadAllText("$plug\dclDragLintWizard.dproj")
if ($dpk   -match 'DragLint\.Plugin\.PlugUiCore in') { Ok 'PlugUiCore in .dpk contains' } else { Bad 'PlugUiCore missing from .dpk contains' }
if ($dproj -match 'DragLint\.Plugin\.PlugUiCore\.pas') { Ok 'PlugUiCore in .dproj' } else { Bad 'PlugUiCore missing from .dproj' }
$us = Code ([IO.File]::ReadAllText("$plug\DragLint.Plugin.UsagesForm.pas"))
if ($us -match 'ApplyIdeTheme\s*\(\s*Self\s*,\s*TDragLintUsagesForm') { Ok 'UsagesForm applies the IDE theme' } else { Bad 'UsagesForm does not call ApplyIdeTheme' }
if ($us -match 'UsageRowColors') { Ok 'UsagesForm draws rows with themed colours' } else { Bad 'UsagesForm does not use UsageRowColors' }
$draw = [regex]::Match($us, 'procedure TDragLintUsagesForm\.TreeAdvancedCustomDrawItem.*?procedure TDragLintUsagesForm\.SetWidth', 'Singleline').Value
if ($draw -and $draw -notmatch '\bcl(Window|WindowText|Highlight|HighlightText)\b') { Ok 'custom draw has no bare system colours' } else { Bad 'custom draw still uses bare cl* system colours' }
$lo = Code ([IO.File]::ReadAllText("$plug\DragLint.Plugin.LintOptionsFrame.pas"))
if ($lo -match 'FBtnSearchClear' -and $lo -match 'FSearchTimer' -and $lo -match 'crHourGlass') { Ok 'frame has clear button, timer, wait cursor' } else { Bad 'frame lacks clear button / timer / wait cursor' }

Write-Host '== PLUGUI headless harness ==' -ForegroundColor Cyan
try {
  if (Test-Path $WorkDir) { [IO.Directory]::Delete($WorkDir, $true) }
  New-Item -ItemType Directory $WorkDir | Out-Null
  if (-not (Test-Path $Rsvars)) { Write-Host "SKIP harness: no rsvars" -ForegroundColor Yellow }
  else {
    $pub = Join-Path $WorkDir 'pub'; New-Item -ItemType Directory $pub | Out-Null
    $src = [IO.File]::ReadAllText("$plug\DragLint.Plugin.LintOptionsFrame.pas")
    [IO.File]::WriteAllText("$pub\DragLint.Plugin.LintOptionsFrame.pas", ($src -replace '(?m)^  private\r?$', '  public'), [Text.Encoding]::ASCII)
    $s = "$repo\src"
    $u = "$pub;$plug;$fix\stub;$s\core;$s\lint;$s\parser;$s\index;$s\doc;$s\config"
    $log = Run-Bat 'harness_build' @('@echo off', "call `"$Rsvars`"", "cd /d `"$fix`"",
      "dcc64 -CC -B -NSSystem;Winapi;Vcl;Vcl.Imaging;Data -U`"$u`" -E`"$WorkDir`" -N0`"$WorkDir`" PlugUiHarness.dpr",
      'echo BUILD_EXITCODE=%ERRORLEVEL%')
    $built = ($log -match 'BUILD_EXITCODE=0') -and ($log -notmatch 'Error:|Fatal:')
    if ($built) { Ok 'PlugUiHarness builds' } else { Bad ('PlugUiHarness did not build: ' + ((($log -split "`r?`n") | Where-Object { $_ -match 'Error|Fatal' } | Select-Object -First 4) -join ' | ')) }
    if ($built) {
      $p = Start-Process "$WorkDir\PlugUiHarness.exe" -ArgumentList "`"$fix\rules-sample.json`"" -RedirectStandardOutput "$WorkDir\h.out" `
             -RedirectStandardError "$WorkDir\h.err" -NoNewWindow -PassThru
      $null = $p.Handle  # keep the handle so ExitCode is readable after the wait
      if (-not $p.WaitForExit(300000)) { $p.Kill(); Bad 'harness timed out (300 s)' }
      $out = Get-Content "$WorkDir\h.out" -Raw
      Write-Host $out
      if ($p.ExitCode -ne 0) { Bad "harness exit code $($p.ExitCode)" } else { Ok 'harness all pass' }
    }
  }

  if ($Build) {
    Write-Host '== PLUGUI BPL builds (scratch) ==' -ForegroundColor Cyan
    foreach ($pl in 'Win32', 'Win64') {
      $out = Join-Path $WorkDir "bpl-$pl"; New-Item -ItemType Directory $out | Out-Null
      $log = Run-Bat "build_$pl" @('@echo off', "call `"$Rsvars`"", "cd /d `"$plug`"",
        "msbuild /t:Build /p:Config=Debug /p:Platform=$pl /p:DCC_BplOutput=$out /p:DCC_DcpOutput=$out /p:DCC_DcuOutput=$out\dcu /v:normal dclDragLintWizard.dproj",
        'echo BUILD_EXITCODE=%ERRORLEVEL%')
      if (($log -match 'BUILD_EXITCODE=0') -and ($log -notmatch '\[dcc\w*\] Error')) { Ok "BPL $pl builds" } else { Bad "BPL $pl failed" }
    }
  }
}
finally {
  if (-not $env:PLUGUI_KEEP -and (Test-Path $WorkDir)) { [IO.Directory]::Delete($WorkDir, $true) }
}
if ($fail) { Write-Host "PLUGUI: $fail failure(s)" -ForegroundColor Red; exit 1 }
Write-Host 'PLUGUI: all pass' -ForegroundColor Green
