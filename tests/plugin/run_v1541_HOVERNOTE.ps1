<#
  run_v1541_HOVERNOTE.ps1 -- build and run HoverNoteTests.dpr, then pin the
  IDE-side wiring by source (lane 1.54.1 HOVERNOTE, owner request 2026-11-25).

  The .dpr drives DragLint.Plugin.HoverNote: the token under a position, the
  note texts, pointer -> column, the empty-answer memo, and the strip's texts
  and layout while a job runs. The W-checks pin what a console test cannot
  reach: the dwell asks about the POINTER (never the caret), the texts come
  from that unit, an empty answer is remembered instead of cached, and the
  strip shows note and progress together. Each W-check that asserts an absence
  has a presence control in the same check.

  -NoteUnit tests another HoverNote.pas (the RED run used a stub).
  Exit 0 on full pass, 1 on any failure, 2 when the harness cannot be built.
#>
[CmdletBinding()]
param(
  [string]$NoteUnit = '',
  [string]$WorkDir  = "$env:TEMP\drag-lint-hovernote-$PID"
)
$ErrorActionPreference = 'Stop'
$script:Failed = 0
$script:Passed = 0
function Check($n, $ok, $d = '') {
  if ($ok) { Write-Host "PASS  $n"; $script:Passed++ } else { Write-Host "FAIL  $n  $d" -ForegroundColor Red; $script:Failed++ }
}
try {
  $plugin = (Resolve-Path "$PSScriptRoot\..\..\src\delphi-plugin").Path
  $dpr    = (Resolve-Path "$PSScriptRoot\..\HoverNoteTests.dpr").Path
  if (-not $NoteUnit) { $NoteUnit = Join-Path $plugin 'DragLint.Plugin.HoverNote.pas' }

  $rs = 'C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\rsvars.bat'
  if (-not (Test-Path $rs)) { Write-Host "SKIP: rsvars not found: $rs" -ForegroundColor Yellow; exit 0 }
  if (Test-Path $WorkDir) { [IO.Directory]::Delete($WorkDir, $true) }
  $dcu = Join-Path $WorkDir 'dcu'
  New-Item -ItemType Directory $dcu -Force | Out-Null

  # The .dpr names the unit by path; the copy built here names -NoteUnit's.
  $src = [IO.File]::ReadAllText($dpr).Replace('..\src\delphi-plugin\DragLint.Plugin.HoverNote.pas', (Resolve-Path $NoteUnit).Path)
  $copy = Join-Path $WorkDir 'HoverNoteTests.dpr'
  [IO.File]::WriteAllText($copy, $src, [Text.Encoding]::ASCII)
  $bat = Join-Path $WorkDir 'build.bat'
  $lines = @('@echo off', ('call "{0}"' -f $rs), ('cd /d "{0}"' -f $WorkDir),
    ('dcc64 -B -E"{0}" -N0"{1}" -NSSystem;Winapi HoverNoteTests.dpr' -f $WorkDir, $dcu), 'echo BUILD_EXITCODE=%ERRORLEVEL%')
  [IO.File]::WriteAllText($bat, (($lines -join "`r`n") + "`r`n"), [Text.Encoding]::ASCII)
  $log = Join-Path $WorkDir 'build.log'
  Start-Process cmd.exe -ArgumentList '/c', "`"$bat`"" -RedirectStandardOutput $log -RedirectStandardError "$log.err" -NoNewWindow -Wait
  $buildOut = [IO.File]::ReadAllText($log)
  if ($buildOut -notmatch 'BUILD_EXITCODE=0') {
    Write-Host 'FATAL: compile failed' -ForegroundColor Red
    ($buildOut -split "`r?`n") | Where-Object { $_ -match 'Error|Fatal' } | Select-Object -First 10 | ForEach-Object { Write-Host "  $_" }
    exit 2
  }
  $outFile = Join-Path $WorkDir 'out.txt'
  $proc = Start-Process (Join-Path $WorkDir 'HoverNoteTests.exe') -RedirectStandardOutput $outFile -RedirectStandardError "$outFile.err" -NoNewWindow -PassThru
  $null = $proc.Handle
  if (-not $proc.WaitForExit(30000)) { $proc.Kill(); Check 'harness finished within 30 s' $false 'killed' }
  $out = [IO.File]::ReadAllText($outFile)
  Write-Host $out.TrimEnd()
  Check 'H1 every console check passed' ($out -match '(?m)^[1-9]\d* passed, 0 failed') ''

  Write-Host '-- W: IDE wiring (source pins; the IDE itself is not driven here)'
  function Src($n) { [IO.File]::ReadAllText((Join-Path $plugin "DragLint.Plugin.$n.pas")) }
  $ht = Src 'HoverTracker'; $ed = Src 'Editor'; $sb = Src 'StatusBar'; $jq = Src 'JobQueue'
  $dpk = [IO.File]::ReadAllText((Join-Path $plugin 'dclDragLintWizard.dpk'))
  $dproj = [IO.File]::ReadAllText((Join-Path $plugin 'dclDragLintWizard.dproj'))
  $tick = [regex]::Match($ht, '(?s)procedure TDragLintHoverHelper\.OnTick.*?\r?\nend; // procedure').Value

  Check 'W1 the package builds HoverNote (dpk + dproj)' ($dpk.Contains('DragLint.Plugin.HoverNote in') -and $dproj.Contains('DragLint.Plugin.HoverNote.pas')) ''
  Check 'W2 the old text is gone from both hover paths; both take the empty-answer text from HoverNote' `
    (-not $ht.Contains('nothing indexed at the cursor') -and -not $ed.Contains('nothing indexed at the cursor') -and
     $ht.Contains('DLEmptyAnswerNote(') -and $ed.Contains('DLEmptyAnswerNote(')) ''
  Check 'W3 the dwell never reads the caret: no EditView.Position in OnTick (control: the caret-panel link still does)' `
    ($tick.Length -gt 0 -and $tick -notmatch '\.Position\.' -and $ht -match 'EditView\.Position\.Row') "tick=$($tick.Length)"
  Check 'W4 the cell comes from the editor UNDER THE POINTER (its own state and view), not from the painter globals' `
    ($ht.Contains('GetEditorState(') -and $ht.Contains('.LogicalLineNum') -and $ht.Contains('DLColumnAt(') -and -not ($ht -match 'GGutter(AnchorLine|AnchorTopY|TextLeft|CharWidth|LineHeight)')) ''
  Check 'W5 no cell = no question: the tick exits on a cell that is not text before any request' `
    ($tick -match '(?s)Cell\.Verdict\s*<>\s*hcvText.*RequestHoverBundleAsync') ''
  Check 'W6 an empty answer is remembered, held per tick, and dropped by a re-dwell' `
    ($ht.Contains('FEmpty.Remember(') -and $ht.Contains('FEmpty.Holds(') -and ($ht -match '(?s)procedure TDragLintHoverHelper\.ResetState;.*?FEmpty\.Clear')) ''
  Check 'W7 an empty answer is never cached under FLastLspKey' ($ht -match 'FLastLspKey\s*:= if AMarkdown <> '''' then FInflightKey else ''''') ''
  Check 'W8 the queue counts finished index jobs and names the running kind' `
    ($jq.Contains('CurrentKind') -and $jq.Contains('IndexGeneration') -and ($jq -match 'Inc\(FState\.IndexGeneration\)')) ''
  Check 'W9 the strip composes both texts and lays them out by HoverNote' ($sb.Contains('DLStripTexts(') -and $sb.Contains('DLStripLayout(')) ''
  Check 'W10 the dwell telemetry names source, pointer, grid and token' ($ht -match "src=%s x=%d y=%d" -and $ht -match 'tok=%s') ''
  Check 'W11 the announce names the asked token (no caret announce left in the dwell)' ($ht.Contains('DLHoverAnnounceNote(') -and -not $tick.Contains('AnnounceHoverStart')) ''
  Check 'W12 an engine error is not reported as not indexed' ($ht -match '(?s)hvsUnsupported.{0,400}engine could not answer') ''

  Write-Host ("{0} runner checks passed, {1} failed" -f $script:Passed, $script:Failed)
  if ($script:Failed -gt 0) { exit 1 }
  exit 0
}
catch { Write-Host "FATAL: $($_.Exception.Message)" -ForegroundColor Red; exit 2 }
