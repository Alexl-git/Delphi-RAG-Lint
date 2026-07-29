<#
  run_index_progress_flush.ps1 -- Task 4e, INBOX
  "index --all --only Library --platform win32 aborts mid-run, exit -1".

  WHAT THIS GUARDS (the SECOND defect in that report, not the abort itself)

  `TIndexer.ReportProgress` and the `DIAG:` loop beside it write to `Output`
  with plain `Writeln` and NEVER flush. Delphi buffers `Output` through
  `TTextRec.BufPtr`, whose buffer is `TTextBuf = array[0..127]` -- 128 bytes.
  A buffered stream is only written out when the buffer FILLS, or when the RTL
  closes `Output` during a normal `_Halt0`. So when the process dies WITHOUT
  running `_Halt0` -- TerminateProcess, ExitProcess, a fault -- everything
  still sitting in that 128-byte buffer is lost, and the log on disk ends
  wherever the last 128-byte boundary happened to fall: in the MIDDLE of a
  line, usually mid-token.

  That is exactly what made the reported abort so expensive to diagnose. The
  three surviving logs of the five failed runs end:

      run 1  ...FireDAC.Phys.FBDef.pas -> 76 symbols...   then  `  c:\`
      run 4  ...dxPSContainerLnk.pas -> 15                (cut mid-number)
      run 5  `    DIAG: C:\Progr`                         (cut mid-path)

  and MEASURED at Task 4e, the drag-lint-written byte count of all three is an
  EXACT multiple of 128 (120448 = 941*128; 413312 = 3229*128; 23936 = 187*128).
  So the visible last token is a buffer-boundary artifact and NOT the crash
  site -- the report's "it crashed while emitting the DIAG line" reading was an
  artifact of this defect. Up to 127 bytes of evidence were destroyed on every
  run.

  THE ASSERTION

  Kill an in-flight `index` with Stop-Process (TerminateProcess -- the same
  no-_Halt0 shape as the reported abort) and require that the log an external
  reader sees is always COMPLETE: every sample ends on a line terminator, and
  so does the final post-kill content. Nothing partial, nothing lost.

  Sampling repeatedly rather than once is deliberate. Without the flush a
  single sample lands mid-line only ~(1 - lineLen/128) of the time, so one
  sample could pass by luck; requiring EVERY sample to end cleanly drives that
  luck to nil.

  THE PRECONDITION -- WHY THIS FILE PINS ITS OWN PATH LENGTH (register K54)

  The flush does NOT make every sample clean unconditionally, and the first
  version of this header said it did. What the per-file flush guarantees is
  that a COMPLETED burst is never left sitting in the buffer. It cannot
  guarantee that the file ends on a line terminator when a single emitted line
  is LONGER than the 128-byte buffer: the RTL empties the buffer the moment it
  fills, so a 166-byte progress line reaches disk as 128 + 38 and an outside
  reader sampling in between sees it cut mid-path -- flush or no flush.

  A progress line is `  <fullpath> -> N symbols, N refs, N errors` + CRLF, so
  its length is driven entirely by the fixture's path. That made the earlier
  version of this runner GREEN only because `$env:TEMP` is `C:\TEMP` on the
  machine it was written on: re-run with `-WorkDir` under a 112-character
  scratchpad path it FAILED, on a build whose flush was working perfectly
  (`8 of 8` samples off the 128-byte boundary, so the fix was demonstrably
  live). A check that passes by accident of `$env:TEMP` is not a check.

  So the precondition is now BOUNDED TWICE, and neither route is silent:
    * before the fixture is written, PathBudget below rejects a `-WorkDir` that
      cannot keep every progress line inside 128 bytes -- exit 2, naming the
      measured length, rather than a misleading "the flush does not work";
    * after the run, the longest COMPLETE line actually emitted is measured
      from the log on disk and asserted <= 128, because the pre-flight is an
      estimate and the log is ground truth.
  The default `-WorkDir` is deliberately short (`$env:TEMP\dlflush`, a `s`
  subdirectory, `uNNNN.pas` units) so the budget holds for any plausible
  `$env:TEMP` rather than only for this box's.

  NON-VACUITY is itself asserted: the run must still have been ALIVE at the
  moment we killed it, and the log must have grown past the first buffer.
  A run that finished on its own would end cleanly via _Halt0 and prove
  nothing, so that case FAILS rather than silently passing.

  CWD: this runner does NOT Push-Location, unlike the `tests\autodoc\*` runners
  whose headers say "run from a NEUTRAL CWD" and then actually do it. It does
  not need to -- every path it hands the exe (`$srcDir`, `--db`) is absolute,
  and the battery supplies the repo root as CWD deliberately (see
  tests\run_battery.ps1) so config-walk-up effects stay visible. `$env:TEMP\dlflush`
  below is where the FIXTURE lives, not a working directory.
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\dlflush"
)
$ErrorActionPreference = 'Stop'
$script:Failed = $false
function Check($n, $ok, $d = '') {
  $s = if ($ok) { 'PASS' } else { 'FAIL' }
  $c = if ($ok) { 'Green' } else { 'Red' }
  Write-Host ("  [{0}] {1} {2}" -f $s, $n, $d) -ForegroundColor $c
  if (-not $ok) { $script:Failed = $true }
}

if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
$Exe = (Resolve-Path $Exe).Path

# Enough units that the walk cannot finish before we have sampled it, and
# small enough that the whole runner stays a few seconds.
$UnitCount = 900
$srcDir = Join-Path $WorkDir 's'

# --- PRE-FLIGHT: the 128-byte precondition, before anything is written -------
# ReportProgress emits `  %s -> %d symbols, %d refs, %d errors` + CRLF
# (DRagLint.Core.Indexer.pas). Everything but the path is fixed text plus three
# counts:
#     2  leading indent
#    28  ' -> ' + ' symbols,' + ' refs,' + ' errors' + the two separating spaces
#    12  three counts, allowing a generous 4 digits each (this fixture emits 1)
#     2  CRLF
# = 44 bytes that are not the path, so the longest fixture path must fit in 84.
# Rejecting HERE, loudly, is the point: past 84 the "ends on a complete line"
# assertion below stops being true of a correct build, and a runner that cannot
# assert what it claims must fail, not pass.
$SuffixBytes = 44
$PathBudget  = 128 - $SuffixBytes
$LongestPath = (Join-Path $srcDir ('u{0:D4}.pas' -f ($UnitCount - 1)))
if ($LongestPath.Length -gt $PathBudget) {
  Write-Host ("FATAL: -WorkDir is too long for this runner's own precondition." ) -ForegroundColor Red
  Write-Host ("  longest fixture path : {0} bytes ({1})" -f $LongestPath.Length, $LongestPath) -ForegroundColor Red
  Write-Host ("  budget               : {0} bytes (128-byte TTextBuf minus {1} bytes of fixed progress-line text)" -f $PathBudget, $SuffixBytes) -ForegroundColor Red
  Write-Host ("  this is NOT a flush defect -- a progress line longer than 128 bytes reaches disk in") -ForegroundColor Red
  Write-Host ("  128-byte pieces however often Output is flushed. Re-run with a shorter -WorkDir.") -ForegroundColor Red
  exit 2
}

if (Test-Path $WorkDir) { Remove-Item -Recurse -Force $WorkDir }
New-Item -ItemType Directory $WorkDir | Out-Null
New-Item -ItemType Directory $srcDir | Out-Null
for ($i = 0; $i -lt $UnitCount; $i++) {
  $n = 'u{0:D4}' -f $i
  $body = @(
    "unit $n;"
    'interface'
    "function F$i(const A: Integer): Integer;"
    'implementation'
    "function F$i(const A: Integer): Integer;"
    'begin'
    "  Result := A + $i;"
    'end;'
    'end.'
  ) -join "`r`n"
  [System.IO.File]::WriteAllText((Join-Path $srcDir "$n.pas"), $body + "`r`n", [System.Text.Encoding]::ASCII)
}

$log = Join-Path $WorkDir 'index.log'
$err = Join-Path $WorkDir 'index.err'
$db  = Join-Path $WorkDir 'flush.sqlite'

# Read the log the way an outside observer does, while the writer still holds
# it open. FileShare.ReadWrite|Delete or the open handle blocks us.
function Read-LogBytes([string]$Path) {
  if (-not (Test-Path $Path)) { return [byte[]]@() }
  $fs = [System.IO.File]::Open($Path, [System.IO.FileMode]::Open,
        [System.IO.FileAccess]::Read,
        [System.IO.FileShare]::ReadWrite -bor [System.IO.FileShare]::Delete)
  try {
    $buf = New-Object byte[] $fs.Length
    [void]$fs.Read($buf, 0, $buf.Length)
    return $buf
  } finally { $fs.Dispose() }
}
function EndsOnCompleteLine([byte[]]$b) {
  if ($b.Length -eq 0) { return $false }
  return ($b[$b.Length - 1] -eq 10)   # LF -- every emitted line ends CRLF
}
function TailText([byte[]]$b, [int]$n = 60) {
  if ($b.Length -eq 0) { return '<empty>' }
  $s = [System.Text.Encoding]::ASCII.GetString($b)
  return $s.Substring([Math]::Max(0, $s.Length - $n)) -replace "`r", '\r' -replace "`n", '\n'
}
# Longest COMPLETE line in a log, counting its CRLF -- i.e. the largest burst
# the 128-byte buffer was ever asked to hold. A trailing partial line is not a
# complete line and is excluded.
function MaxLineBytes([byte[]]$b) {
  $max = 0; $run = 0
  foreach ($x in $b) {
    $run++
    if ($x -eq 10) { if ($run -gt $max) { $max = $run }; $run = 0 }
  }
  return $max
}

Write-Host 'Scenario A: an abnormally-killed index leaves a COMPLETE log' -ForegroundColor Cyan

$p = Start-Process -FilePath $Exe `
       -ArgumentList 'index', "`"$srcDir`"", '--db', "`"$db`"" `
       -NoNewWindow -PassThru -RedirectStandardOutput $log -RedirectStandardError $err

# Wait until output is well past the first 128-byte buffer, so the samples are
# taken inside the per-file progress loop rather than during start-up.
$sw = [Diagnostics.Stopwatch]::StartNew()
while ((Read-LogBytes $log).Length -lt 4096 -and -not $p.HasExited -and $sw.Elapsed.TotalSeconds -lt 60) {
  Start-Sleep -Milliseconds 40
}

$samples = @()
for ($s = 0; $s -lt 8 -and -not $p.HasExited; $s++) {
  $samples += ,(Read-LogBytes $log)
  Start-Sleep -Milliseconds 120
}

$wasAlive = -not $p.HasExited
Check 'non-vacuity: the run was still ALIVE when we killed it' $wasAlive `
      "(a run that finished on its own flushes via _Halt0 and proves nothing)"
if ($wasAlive) { Stop-Process -Id $p.Id -Force; $p.WaitForExit(20000) | Out-Null }

$final = Read-LogBytes $log
Check 'non-vacuity: log grew past the first 128-byte buffer' ($final.Length -ge 4096) `
      "bytes=$($final.Length)"
Check 'non-vacuity: at least 4 in-flight samples were taken' ($samples.Count -ge 4) `
      "samples=$($samples.Count)"

# The precondition, MEASURED rather than assumed. The pre-flight above bounded
# the path; this bounds what was actually emitted, banner lines included. If a
# real line ever exceeds the buffer, the two "ends on a complete line" checks
# below are no longer true of a CORRECT build, and this is the failure that
# says so -- not them.
$maxLine = MaxLineBytes $final
Check 'precondition: every emitted line fits the 128-byte Output buffer' `
      ($maxLine -le 128) `
      ("longest complete line = {0} bytes (incl CRLF); above 128 the RTL splits a line across writes regardless of Flush" -f $maxLine)

$badIdx = @()
for ($i = 0; $i -lt $samples.Count; $i++) {
  if (-not (EndsOnCompleteLine $samples[$i])) { $badIdx += $i }
}
Check 'every in-flight sample ends on a complete line (nothing stuck in the buffer)' `
      ($badIdx.Count -eq 0) `
      ("partial samples: [{0}] e.g. ...{1}" -f ($badIdx -join ','),
       $(if ($badIdx.Count) { TailText $samples[$badIdx[0]] } else { '' }))

Check 'after TerminateProcess the log still ends on a complete line' `
      (EndsOnCompleteLine $final) ("tail=...{0}" -f (TailText $final))

# The mechanism itself, stated as a number, and the one check here that does
# NOT depend on the line-length precondition: it is about sample LENGTH, not
# about where a line ends. While an UNFLUSHED Delphi Output stream is mid-run,
# the file on disk has only ever received whole 128-byte buffer dumps, so EVERY
# in-flight sample length is an exact multiple of 128 -- that is certain, not
# probable, which is what makes this check fail pre-fix every single time
# rather than merely usually. One flushed line breaks the pattern, so post-fix
# all 8 samples would have to coincide with a boundary at once (~(1/128)^8) for
# this to misfire.
$nonBoundary = @($samples | Where-Object { ($_.Length % 128) -ne 0 }).Count
Check 'at least one in-flight sample is NOT a bare 128-byte buffer multiple' `
      ($nonBoundary -gt 0) `
      ("{0} of {1} samples off-boundary; lengths=[{2}]" -f $nonBoundary, $samples.Count,
       (($samples | ForEach-Object { $_.Length }) -join ','))

Write-Host ''
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
