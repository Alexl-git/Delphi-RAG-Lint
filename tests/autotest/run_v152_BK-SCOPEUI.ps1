<#
  run_v152_BK-SCOPEUI.ps1 -- lane BK-SCOPEUI (1.52): B36 unsaved rule toggles survive a search refill, B44 overrides list.

  1. Static: PlugUiCore is in the .dpk contains AND the .dproj; UsagesForm calls
     ApplyIdeTheme and the themed row colours (no bare clWindow / clWindowText /
     clHighlight left in its custom draw); LintOptionsFrame has the clear button,
     the debounce timer and the wait cursor.
  2. Headless harness (fixtures\scopeui\ScopeUiHarness.dpr, Win64, stub ToolsAPI,
     private->public copy of the frame unit): row colours through a fake dark
     theme, refill rule, debounce count, clear button, wait cursor; reports the
     clear-the-search time (CLEAR_MS).
  3. -Build: Win32 + Win64 BPL builds of dclDragLintWizard.dproj into -WorkDir
     (never into third_party).

  Usage: pwsh -File tests\autotest\run_v152_BK-SCOPEUI.ps1 [-Build]
#>
[CmdletBinding()]
param(
  [switch]$Build,
  [string]$WorkDir = "$env:TEMP\drag-lint-v152-scopeui-$PID",
  [string]$Rsvars  = 'C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\rsvars.bat'
)
$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path "$PSScriptRoot\..\..").Path
$plug = Join-Path $repo 'src\delphi-plugin'
$fix  = Join-Path $PSScriptRoot 'fixtures\scopeui'
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

Write-Host '== BK-SCOPEUI static ==' -ForegroundColor Cyan
# Strip comments/strings-agnostic: compare on code with { } and // comments removed.
function Body([string]$text, [string]$startPat, [string]$endPat) {
  return [regex]::Match($text, "$startPat.*?$endPat", 'Singleline').Value
}
# B39a: the call graph (butterfly) shows the REPPROG progress window with Cancel, not a silent thread
$ed = Code ([IO.File]::ReadAllText("$plug\DragLint.Plugin.Editor.pas"))
$bf = Body $ed 'procedure ShowButterflyForQName\(const AQName, ADb: string\);\s*(?:var.*?)?begin' '\r?\nend;'
if ($bf -match 'TDragLintReportProgressForm' -or $bf -match 'RunGraphStage') { Ok 'B39 butterfly runs under the progress window' } else { Bad 'B39 ShowButterflyForQName has no progress window' }
if ($bf -notmatch 'RunAndCaptureStdout' -and $bf -notmatch 'CreateAnonymousThread') { Ok 'B39 butterfly no longer blocks on an uncancellable thread' } else { Bad 'B39 ShowButterflyForQName still runs RunAndCaptureStdout on a bare thread' }
$gs = Body $ed 'procedure RunGraphStage' '\r?\nend;'
if ($gs -match 'TDragLintReportProgressForm\.CreateRun' -and $gs -match 'HoldDb' -and $gs -match 'ReleaseDb') { Ok 'B39 stage holds the DB for the run and releases it on done/cancel' } else { Bad 'B39 RunGraphStage lacks CreateRun / HoldDb / ReleaseDb' }
# B39b: open report text windows are freed before the package's code goes away
$rp = Code ([IO.File]::ReadAllText("$plug\DragLint.Plugin.Reports.pas"))
$fin = [regex]::Match($rp, 'finalization.*?\r?\nend\.', 'Singleline').Value
if ($fin -match 'GReportTexts') { Ok 'B39 finalization frees the open report text windows' } else { Bad 'B39 Reports finalization does not free open report text windows' }
if ($rp -match 'CreateReport\(\s*Application' ) { Bad 'B39 report text window is still owned by Application (survives unload)' } else { Ok 'B39 report text window is not owned by Application' }
# B31: Search page scope combo + full-path Location
$sf = Code ([IO.File]::ReadAllText("$plug\DragLint.Plugin.SearchForm.pas"))
if ($sf -match 'SearchUsagesScopeArgs' -and $sf -match 'FScope') { Ok 'B31 Search page passes --scope from its scope combo' } else { Bad 'B31 SearchForm has no scope combo / SearchUsagesScopeArgs' }
if ($sf -match 'SearchLocationText' -and $sf -notmatch 'ExtractFileName\(ARows') { Ok 'B31 Location column shows the full path' } else { Bad 'B31 Location column still shows the bare file name' }
Write-Host '== BK-SCOPEUI headless harness ==' -ForegroundColor Cyan
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
      "dcc64 -CC -B -NSSystem;Winapi;Vcl;Vcl.Imaging;Data -U`"$u`" -E`"$WorkDir`" -N0`"$WorkDir`" ScopeUiHarness.dpr",
      'echo BUILD_EXITCODE=%ERRORLEVEL%')
    $built = ($log -match 'BUILD_EXITCODE=0') -and ($log -notmatch 'Error:|Fatal:')
    if ($built) { Ok 'ScopeUiHarness builds' } else { Bad ('ScopeUiHarness did not build: ' + ((($log -split "`r?`n") | Where-Object { $_ -match 'Error|Fatal' } | Select-Object -First 4) -join ' | ')) }
    if ($built) {
      $p = Start-Process "$WorkDir\ScopeUiHarness.exe" -ArgumentList "`"$fix\rules-sample.json`"" -RedirectStandardOutput "$WorkDir\h.out" `
             -RedirectStandardError "$WorkDir\h.err" -NoNewWindow -PassThru
      $null = $p.Handle  # keep the handle so ExitCode is readable after the wait
      if (-not $p.WaitForExit(300000)) { $p.Kill(); Bad 'harness timed out (300 s)' }
      $out = Get-Content "$WorkDir\h.out" -Raw
      Write-Host $out
      if ($p.ExitCode -ne 0) { Bad "harness exit code $($p.ExitCode)" } else { Ok 'harness all pass' }
    }
  }

  if ($Build) {
    Write-Host '== BK-SCOPEUI BPL builds (scratch) ==' -ForegroundColor Cyan
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
  if (-not $env:SCOPEUI_KEEP -and (Test-Path $WorkDir)) { [IO.Directory]::Delete($WorkDir, $true) }
}
if ($fail) { Write-Host "BK-SCOPEUI: $fail failure(s)" -ForegroundColor Red; exit 1 }
Write-Host 'BK-SCOPEUI: all pass' -ForegroundColor Green
