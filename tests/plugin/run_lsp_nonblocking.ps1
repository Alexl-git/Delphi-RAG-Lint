<#
  run_lsp_nonblocking.ps1 -- build and run LspNonBlockingTests.dpr, then pin
  the IDE-side wiring by source.

  Owner rule, 2026-10-29: "whatever gets stuck in DL must not make the IDE
  stuck" (docs\INBOX-ide-hang-on-slow-engine.md section 1). The .dpr proves the
  mechanics outside the IDE: the write queue never blocks on a pipe nobody
  reads, a superseded hover is dropped (callback never runs, $/cancelRequest
  sent), timeouts / busy / stuck are observed, and the hover show-gate geometry.

  The W-checks below pin what a console test cannot reach -- the IDE units that
  must USE the non-blocking API: no synchronous Client.Request / Initialize call
  is left in a main-thread unit, the dwell sends ONE hover request, and the
  popup is gated on the window under the cursor.

  Exit 0 on full pass, 1 on any failure, 2 when the harness cannot be built.
#>
[CmdletBinding()]
param(
  [string]$Dpr     = "$PSScriptRoot\..\LspNonBlockingTests.dpr",
  [string]$WorkDir = "$env:TEMP\drag-lint-lsp-nonblocking-$PID"
)
$ErrorActionPreference = 'Stop'
$script:Failed = $false
function Check($n, $ok, $d = '') {
  if ($ok) { Write-Host "PASS  $n" } else { Write-Host "FAIL  $n  $d" -ForegroundColor Red; $script:Failed = $true }
}
try {
  if (-not (Test-Path $Dpr)) { Write-Host "FATAL: dpr not found: $Dpr" -ForegroundColor Red; exit 2 }
  $Dpr     = (Resolve-Path $Dpr).Path
  $DprDir  = Split-Path $Dpr -Parent
  $DprName = Split-Path $Dpr -Leaf
  $plugin  = (Resolve-Path "$PSScriptRoot\..\..\src\delphi-plugin").Path
  $core    = (Resolve-Path "$PSScriptRoot\..\..\src\core").Path

  $rs = 'C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\rsvars.bat'
  if (-not (Test-Path $rs)) { Write-Host "SKIP: rsvars not found: $rs" -ForegroundColor Yellow; exit 0 }

  if (Test-Path $WorkDir) { [IO.Directory]::Delete($WorkDir, $true) }
  $DcuDir = Join-Path $WorkDir 'dcu'
  New-Item -ItemType Directory $DcuDir -Force | Out-Null

  $bat = Join-Path $WorkDir 'build.bat'
  $lines = @(
    '@echo off',
    ('call "{0}"' -f $rs),
    ('cd /d "{0}"' -f $DprDir),
    ('dcc64 -B -DDRAGLINT_TEST_REGROOT -U"{0};{1}" -E"{2}" -N0"{3}" {4}' -f $plugin, $core, $WorkDir, $DcuDir, $DprName),
    'echo BUILD_EXITCODE=%ERRORLEVEL%'
  )
  [IO.File]::WriteAllText($bat, (($lines -join "`r`n") + "`r`n"), [Text.Encoding]::ASCII)
  $buildLog = Join-Path $WorkDir 'build.log'
  $null = Start-Process cmd.exe -ArgumentList '/c', "`"$bat`"" -RedirectStandardOutput $buildLog `
            -RedirectStandardError "$buildLog.err" -NoNewWindow -Wait -PassThru
  $buildOut = Get-Content $buildLog -Raw
  if ($buildOut -notmatch 'BUILD_EXITCODE=0') {
    Write-Host 'FATAL: compile failed' -ForegroundColor Red
    ($buildOut -split "`r?`n") | Where-Object { $_ -match 'Error|Fatal' } | Select-Object -First 10 | ForEach-Object { Write-Host "  $_" }
    exit 2
  }
  $exe = Join-Path $WorkDir ([IO.Path]::GetFileNameWithoutExtension($DprName) + '.exe')

  # The harness bounds every blocking call itself; this outer limit only guards
  # against a harness bug turning the battery into a hang.
  $outFile = Join-Path $WorkDir 'out.txt'
  $proc = Start-Process $exe -RedirectStandardOutput $outFile -RedirectStandardError "$outFile.err" -NoNewWindow -PassThru
  if (-not $proc.WaitForExit(120000)) { $proc.Kill(); Check 'harness finished within 120 s' $false 'killed' }
  $out = Get-Content $outFile -Raw
  Write-Host $out.TrimEnd()
  if ($out -notmatch '(\d+) passed, 0 failed') { $script:Failed = $true }

  Write-Host '-- W: IDE wiring (source pins; the IDE itself is not driven here)'
  $ed = [IO.File]::ReadAllText((Join-Path $plugin 'DragLint.Plugin.Editor.pas'))
  $ht = [IO.File]::ReadAllText((Join-Path $plugin 'DragLint.Plugin.HoverTracker.pas'))
  $cl = [IO.File]::ReadAllText((Join-Path $plugin 'DragLint.Plugin.CodeLensCache.pas'))
  foreach ($u in @(@{n='Editor';t=$ed}, @{n='HoverTracker';t=$ht}, @{n='CodeLensCache';t=$cl})) {
    $sync = [regex]::Matches($u.t, '\.Request\(').Count
    Check "W1 $($u.n): no synchronous Client.Request on the main thread" ($sync -eq 0) "count=$sync"
  }
  Check 'W2 Editor: the engine handshake is InitializeAsync, not the blocking Initialize' `
    ($ed.Contains('.InitializeAsync(') -and -not ($ed -match 'GLspClient\.Initialize\b')) ''
  Check 'W3 HoverTracker: the dwell sends ONE async hover bundle (no serial QueryHoverText / spawn fallback)' `
    ($ht.Contains('RequestHoverBundleAsync(') -and -not $ht.Contains('QueryHoverText(') -and -not $ht.Contains('TryBuildHoverModel(')) ''
  Check 'W4 HoverTracker: superseded hovers are cancelled' ($ht.Contains('.CancelRequest(')) ''
  Check 'W5 HoverTracker: the popup is gated (DLHoverGate) on WindowFromPoint at show time' `
    ($ht.Contains('DLHoverGate(') -and $ht.Contains('WindowFromPoint(')) ''
  Check 'W6 HoverTracker: an engine-busy client gets no new hover and says so' `
    ($ht.Contains('.IsBusy') -and $ht.Contains("'drag-lint: engine busy'")) ''
  Check 'W7 the watchdog restarts a stuck engine through EnsureLspClient' ($ed.Contains('.IsStuck') -and $ht.Contains('.IsStuck')) ''
  Check 'W8 didChange is coalesced per document' ($ed.Contains("'didChange|' + AUri")) ''
  # fix/late-results (owner ruling 2026-11-01): an lrsTimeout / hvsTimeout is a
  # LATE notice, not the end -- every consumer keeps its slot open and takes the
  # answer when it arrives (the C-side L1-L5 prove the client delivers it).
  $lc = [IO.File]::ReadAllText((Join-Path $plugin 'DragLint.Plugin.LspClient.pas'))
  $htLate = [regex]::Matches($ht, '(?s)if AStatus = hvsTimeout then\s*begin\s*SetDragLintNote\(DL_NOTE_HOVER_LATE\);\s*Exit;\s*end;\s*FInflightId\s*:= 0').Count
  Check 'W9 HoverTracker: a late hover keeps its in-flight slot, so the answer is still shown (bundle + text)' ($htLate -eq 2) "count=$htLate"
  Check 'W10 Editor: a late callerCounts keeps its slot and merges the counts when they arrive' `
    ($ed -match '(?s)procedure\(AId: Integer; AStatus: TDLLspReplyStatus; AReply: TJSONValue\)\s*var\s*Arr\s*: TJSONArray;.*?begin\s*if AStatus = lrsTimeout then\s*begin[^;]*;\s*Exit;\s*end;\s*if AId = GCallerCountsId') ''
  Check 'W11 LspClient: a late initialize does not fail the handshake (ADone only on the answer)' `
    ($lc -match "(?s)RequestAsync\('initialize'.*?begin\s*(\{[^}]*\}\s*)?if AStatus = lrsTimeout then\s*begin.*?Exit;\s*end;") ''
  Check 'W12 Editor: no "timed out -- engine busy" note survives; late answers are announced as late' `
    (-not $ed.Contains('timed out -- engine busy') -and ([regex]::Matches($ed, 'DL_NOTE_LATE_SUFFIX|DL_NOTE_HOVER_LATE').Count -ge 5)) ''
  Check 'W13 the watchdog also covers an engine hung in its handshake (dlsStarting)' `
    ($ed -match 'GLspClient\.State in \[dlsStarting, dlsConnected\]\) and GLspClient\.IsStuck') ''
  Check 'W14 Editor: a late definition only jumps while the caret is still where it was asked' `
    ($ed -match "(?s)'textDocument/definition'.*?if Late and not CaretStillAt\(Uri, Line, Col\) then Exit;") ''
  # 1.40 lane hang (IDE-HANG residue + PLUG-INFWAIT): the CLI-spawn paths left on
  # the main thread, and the two INFINITE idle waits. H / K above prove the
  # mechanics; these pin that the IDE units use them.
  $sf = [IO.File]::ReadAllText((Join-Path $plugin 'DragLint.Plugin.StructureForm.pas'))
  $ev = [IO.File]::ReadAllText((Join-Path $plugin 'DragLint.Plugin.EditViewNotifier.pas'))
  Check 'W15 StructureForm: the outline is fetched async (RefreshSymbolsAsync), never by the blocking GetSymbolsForFile' `
    ($sf.Contains('.RefreshSymbolsAsync(') -and -not $sf.Contains('.GetSymbolsForFile(')) ''
  Check 'W16 CodeLensCache: the spawn fallback runs on a worker and each child is stall-bounded (no raw ReadFile loop)' `
    ($cl.Contains('TThread.CreateAnonymousThread(') -and $cl.Contains('RunCaptureStdout(') -and -not $cl.Contains('ReadFile(')) ''
  Check 'W17 EditViewNotifier: a late code-lens answer repaints the gutter' `
    ($ev -match 'PopulateOnce\(FilePath, S\.ExePath, DbPath, procedure begin ForceGutterRepaint; end\)') ''
  foreach ($q in @(@{n='JobQueue';c='WORKER_IDLE_RECHECK_MS'}, @{n='LspWriteQueue';c='WRITER_IDLE_RECHECK_MS'})) {
    $qt = [IO.File]::ReadAllText((Join-Path $plugin "DragLint.Plugin.$($q.n).pas"))
    $inf = [regex]::Matches($qt, 'WaitFor\(\s*INFINITE\s*\)').Count
    Check "W18 $($q.n): no INFINITE wait; the idle loop waits in bounded slices ($($q.c))" `
      (($inf -eq 0) -and $qt.Contains("FWake.WaitFor($($q.c))")) "infinite=$inf"
  }
}
catch {
  Check "runner: $($_.Exception.Message)" $false
}
finally {
  Set-Location -LiteralPath $env:TEMP
  if (Test-Path -LiteralPath $WorkDir) { try { [IO.Directory]::Delete($WorkDir, $true) } catch { } }
}
if ($script:Failed) { Write-Host 'LSP NON-BLOCKING: FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'LSP NON-BLOCKING: PASS' -ForegroundColor Green
exit 0
