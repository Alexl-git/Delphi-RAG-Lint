<#
  run_convert_request_writer.ps1 -- C-PLUGIN-CONVERT-HANDOFF: the plugin half of the C12 contract.

  1. Builds and runs ConvertRequestWriterTests.dpr: the request document key for key, read back by the
     EDITOR's own ParseConvertRequest; the capability reader against the editor's own CapabilitiesJson.
  2. Source anchors on the unit that talks to the IDE (no headless harness can run it): the hand-off
     order of spec N1, the bounded child wait, the probe off the main thread, the three menu items.
  3. Positive control: the order check rejects a hand-off that closes the unit before it saves.
  Live proof owed: the owner's IDE test.

  RED BASELINE, measured 2026-11-06: the plugin had no reference to --convert-request; this guard fails
  on the missing dpr units and the missing menu items.

  Usage: pwsh -File tests\plugin\run_convert_request_writer.ps1
#>
[CmdletBinding()]
param([string]$SrcDir = "$PSScriptRoot\..\..\src\delphi-plugin")
$ErrorActionPreference = 'Stop'
$script:Failed = $false
function Check($n, $ok, $d = '') {
  Write-Host ("  [{0}] {1} {2}" -f $(if ($ok) { 'PASS' } else { 'FAIL' }), $n, $d)
  if (-not $ok) { $script:Failed = $true }
}
$root = (Resolve-Path "$PSScriptRoot\..\..").Path
$work = Join-Path $env:TEMP "drag-lint-convert-request-$PID"
$dcu = Join-Path $work 'dcu'
[void][IO.Directory]::CreateDirectory($dcu)
try {
  $bat = Join-Path $work 'build.bat'
  $lines = '@echo off', 'call "C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\rsvars.bat"', ('cd /d "{0}\tests"' -f $root),
    ('dcc64 -B -E"{0}" -N0"{1}" -U"{2}\src\tools\convrules-editor;{2}\src\report" ConvertRequestWriterTests.dpr' -f $work, $dcu, $root), 'echo BUILD_EXITCODE=%ERRORLEVEL%'
  [IO.File]::WriteAllText($bat, (($lines -join "`r`n") + "`r`n"), [Text.Encoding]::ASCII)
  $log = Join-Path $work 'build.log'
  Start-Process cmd.exe -ArgumentList '/c', "`"$bat`"" -RedirectStandardOutput $log -RedirectStandardError "$log.err" -NoNewWindow -Wait
  $built = (Get-Content $log -Raw) -match 'BUILD_EXITCODE=0'
  Check 'ConvertRequestWriterTests compiles' $built
  if ($built) {
    $out = & (Join-Path $work 'ConvertRequestWriterTests.exe') 2>&1 | Out-String
    Write-Host $out.TrimEnd()
    Check 'the writer tests pass' (($LASTEXITCODE -eq 0) -and ($out -match '\d+ passed, 0 failed'))
  }

  $unit = [IO.File]::ReadAllText((Join-Path $SrcDir 'DragLint.Plugin.ConvertLaunch.pas'))
  $order = '(?s)function SavedOrClean\(.*?ModuleIsDirty\(pModule\).*?pModule\.Save\(False, True\).*?procedure HandOff\(.*?SavedOrClean\(Module.*?RefusedForLivingChild.*?BuildConvertRequestJson.*?PruneConvertRequests.*?WriteAllText.*?Module\.Close.*?StartChild\('
  Check 'hand-off order: save, refuse, write (after pruning), close, start' ($unit -match $order)
  Check 'positive control: the order check rejects close before save' ('function SavedOrClean( ModuleIsDirty(pModule) pModule.Save(False, True) procedure HandOff( Module.Close SavedOrClean(Module RefusedForLivingChild BuildConvertRequestJson PruneConvertRequests WriteAllText StartChild(' -notmatch $order)
  Check 'the selection is read and the editor found before the probe' ($unit -match '(?s)procedure StartConversion\(.*?ReadSelection\(Sel\).*?FindEditor\(Editor\).*?WithProbedEditor\(')
  Check 'the probe runs off the main thread, inside the contract budget' ($unit -match '(?s)RunCliAsync\(Format\(''"%s" --write-capabilities "%s"''.*?PROBE_BUDGET_MS\)' -and $unit -match 'PROBE_BUDGET_MS = 5000;')
  Check 'the child wait is bounded' (($unit -match 'WaitForSingleObject\(FProcess, WAIT_SLICE_MS\)') -and ($unit -notmatch 'INFINITE\s*\)'))
  Check 'the child is started detached and never killed' (($unit -match 'DETACHED_PROCESS') -and ($unit -notmatch 'TerminateProcess|KillProcess'))
  $ed = [IO.File]::ReadAllText((Join-Path $SrcDir 'DragLint.Plugin.Editor.pas'))
  foreach ($cap in 'Convert Selected Component(s)...', 'Convert All of This Type on the Form...', 'Open Conversion Editor...') {
    Check "menu item: $cap" ($ed.Contains("AddWrappedItem(SubConvert, '$cap'"))
  }
  $g = $ed.IndexOf("SubGen.Caption"); $c = $ed.IndexOf("SubConvert.Caption"); $m = $ed.IndexOf("SubMaint.Caption")
  Check 'the submenu sits between Generate and Maintenance' (($g -ge 0) -and ($g -lt $c) -and ($c -lt $m))
  Check 'unload stops the watcher' ($ed -match 'ShutdownConvertLaunch;')
} finally {
  try { [IO.Directory]::Delete($work, $true) } catch { }
}
if ($script:Failed) { Write-Host 'FAILED' -ForegroundColor Red; exit 1 }
Write-Host 'PASSED' -ForegroundColor Green