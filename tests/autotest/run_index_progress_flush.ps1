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
  luck to nil. With the flush every sample is clean by construction, so the
  check is deterministic in the passing direction.

  NON-VACUITY is itself asserted: the run must still have been ALIVE at the
  moment we killed it, and the log must have grown past the first buffer.
  A run that finished on its own would end cleanly via _Halt0 and prove
  nothing, so that case FAILS rather than silently passing.

  Run from a NEUTRAL CWD ($env:TEMP\drag-lint-index-flush).
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\drag-lint-index-flush"
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
if (Test-Path $WorkDir) { Remove-Item -Recurse -Force $WorkDir }
New-Item -ItemType Directory $WorkDir | Out-Null

# Enough units that the walk cannot finish before we have sampled it, and
# small enough that the whole runner stays a few seconds.
$UnitCount = 900
$srcDir = Join-Path $WorkDir 'src'
New-Item -ItemType Directory $srcDir | Out-Null
for ($i = 0; $i -lt $UnitCount; $i++) {
  $n = 'uFlush{0:D4}' -f $i
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

# The mechanism itself, stated as a number. While an UNFLUSHED Delphi Output
# stream is mid-run, the file on disk has only ever received whole 128-byte
# buffer dumps, so EVERY in-flight sample length is an exact multiple of 128 --
# that is certain, not probable, which is what makes this check fail pre-fix
# every single time rather than merely usually. One flushed line breaks the
# pattern, so post-fix all 8 samples would have to coincide with a boundary at
# once (~(1/128)^8) for this to misfire.
$nonBoundary = @($samples | Where-Object { ($_.Length % 128) -ne 0 }).Count
Check 'at least one in-flight sample is NOT a bare 128-byte buffer multiple' `
      ($nonBoundary -gt 0) `
      ("{0} of {1} samples off-boundary; lengths=[{2}]" -f $nonBoundary, $samples.Count,
       (($samples | ForEach-Object { $_.Length }) -join ','))

Write-Host ''
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
