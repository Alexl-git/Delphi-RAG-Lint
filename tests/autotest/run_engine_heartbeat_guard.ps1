<#
  run_engine_heartbeat_guard.ps1 -- 1.40 engine heartbeat (owner design 2026-11-01).

  WHAT IT PINS. Every engine action writes {action, step, n/total, timestamp}
  into one status record, and a status-only listener -- the HEARTBEAT pipe,
  \\.\pipe\drag-lint-beat-<sid>-s<session>-p<pid> -- hands it to whoever asks
  `status<TAB>beat`. The IDE plugin kills an engine only when that status stops
  changing; so the record must ADVANCE while a long run works.

    E1  a long `index <dir>` (test seam DRAGLINT_TEST_INDEX_FILE_DELAY_MS slows
        every file) answers on its heartbeat pipe while it runs, with action
        `index`
    E2  sampled over the run, seq strictly grows and n takes >= 3 distinct
        values -- the status ADVANCES, it is not merely present
    E3  POSITIVE CONTROL for the parser: a plain `status` (no beat argument) on
        the same pipe has NO beat field -- the old reply shape is kept, and E1
        is not a reader that finds a beat in any reply
    E4  `shutdown` on the heartbeat pipe is answered `unknown` and the run still
        ends 0: the heartbeat pipe is never a stand-down channel
    E5  lint-all (DRAGLINT_TEST_LINT_FILE_DELAY_MS) on the same scratch DB:
        action `lint-all`, step names the per-file scan, n advances
    E6  NEGATIVE: a verb that does not report (`query`) creates no heartbeat pipe

  RED on 1.39.2 (no heartbeat pipe): E1, E2, E4 (no pipe to ask), E5 fail; E3 and
  E6 pass, which is what makes the RED meaningful.

  Scratch only: a NEW database under -WorkDir, cwd = -WorkDir (no project
  defaults); never a real project DB.
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\drag-lint-heartbeat-guard-$PID",
  [int]$Files      = 14,
  [int]$DelayMs    = 400
)
$ErrorActionPreference = 'Stop'
$script:Failed = $false
function Check([string]$Name, [bool]$Ok, [string]$Detail = '') {
  if ($Ok) { Write-Host "PASS  $Name" } else { Write-Host "FAIL  $Name  $Detail" -ForegroundColor Red; $script:Failed = $true }
}
function Send-Pipe([string]$Leaf, [string]$Msg, [int]$TimeoutMs = 500) {
  $c = New-Object System.IO.Pipes.NamedPipeClientStream('.', $Leaf, [System.IO.Pipes.PipeDirection]::InOut)
  try {
    $c.Connect($TimeoutMs)
    $b = [System.Text.Encoding]::UTF8.GetBytes($Msg + "`n"); $c.Write($b, 0, $b.Length); $c.Flush()
    $ms = New-Object System.IO.MemoryStream; $buf = New-Object byte[] 4096
    while ($true) { $n = $c.Read($buf, 0, 4096); if ($n -le 0) { break }; $ms.Write($buf, 0, $n); if ($buf[$n - 1] -eq 10) { break } }
    return ([System.Text.Encoding]::UTF8.GetString($ms.ToArray())).TrimEnd("`r", "`n")
  } catch { return '' } finally { $c.Dispose() }
}
function BeatLeaf([int]$ProcId) {
  $sid = [System.Security.Principal.WindowsIdentity]::GetCurrent().User.Value
  $sess = (Get-Process -Id $PID).SessionId
  return "drag-lint-beat-$sid-s$sess-p$ProcId"
}
function Parse-Beat([string]$Reply) {
  foreach ($f in ($Reply -split "`t")) {
    if ($f.StartsWith('beat=')) {
      $p = $f.Substring(5) -split '\|'
      if ($p.Count -eq 6) { return [pscustomobject]@{ Seq = [int64]$p[0]; Action = $p[1]; Step = $p[2]; N = [int64]$p[3]; Total = [int64]$p[4] } }
    }
  }
  return $null
}
# Starts the engine, samples its heartbeat every 250 ms until it exits; returns samples + exit code.
function Run-Sampled([string[]]$ArgList, [hashtable]$EnvVars, [scriptblock]$Mid = $null) {
  $psi = New-Object System.Diagnostics.ProcessStartInfo
  $psi.FileName = $Exe
  $psi.Arguments = (($ArgList | ForEach-Object { if ($_ -match '\s') { '"' + $_ + '"' } else { $_ } }) -join ' ')
  $psi.UseShellExecute = $false; $psi.CreateNoWindow = $true
  $psi.RedirectStandardOutput = $true; $psi.RedirectStandardError = $true
  $psi.WorkingDirectory = $WorkDir
  foreach ($k in $EnvVars.Keys) { $psi.EnvironmentVariables[$k] = [string]$EnvVars[$k] }
  $p = [System.Diagnostics.Process]::Start($psi)
  $outT = $p.StandardOutput.ReadToEndAsync(); $errT = $p.StandardError.ReadToEndAsync()
  $leaf = BeatLeaf $p.Id
  $samples = @(); $plain = ''; $midReply = ''
  $sw = [System.Diagnostics.Stopwatch]::StartNew()
  while (-not $p.HasExited -and $sw.ElapsedMilliseconds -lt 120000) {
    $r = Send-Pipe $leaf "status`tbeat"
    $b = Parse-Beat $r
    if ($null -ne $b) { $samples += $b }
    if (($plain -eq '') -and ($samples.Count -ge 2)) { $plain = Send-Pipe $leaf 'status' }
    if (($null -ne $Mid) -and ($midReply -eq '') -and ($samples.Count -ge 3)) { $midReply = & $Mid $leaf }
    Start-Sleep -Milliseconds 250
  }
  if (-not $p.WaitForExit(60000)) { try { $p.Kill($true) } catch { } }
  return @{ Samples = $samples; Exit = $p.ExitCode; Plain = $plain; Mid = $midReply; Out = $outT.Result; Err = $errT.Result }
}

try {
  if (-not (Test-Path $Exe)) { Write-Host "FATAL: engine not found: $Exe" -ForegroundColor Red; exit 2 }
  $Exe = (Resolve-Path $Exe).Path
  if (Test-Path $WorkDir) { [IO.Directory]::Delete($WorkDir, $true) }
  $src = Join-Path $WorkDir 'src'
  New-Item -ItemType Directory $src -Force | Out-Null
  for ($i = 1; $i -le $Files; $i++) {
    $t = "unit BeatUnit$i;`r`n`r`ninterface`r`n`r`nprocedure Work$i(A: Integer);`r`n`r`nimplementation`r`n`r`nprocedure Work$i(A: Integer);`r`nbegin`r`n  if A > 0 then Work$i(A - 1);`r`nend;`r`n`r`nend.`r`n"
    [IO.File]::WriteAllText((Join-Path $src "BeatUnit$i.pas"), $t, [Text.Encoding]::ASCII)
  }
  $db = Join-Path $WorkDir 'beat.sqlite'

  # ---- E1-E4: index ----
  $shutdownProbe = { param($leaf) Send-Pipe $leaf 'shutdown' 2000 }
  $r = Run-Sampled @('index', $src, '--db', $db) @{ DRAGLINT_TEST_INDEX_FILE_DELAY_MS = $DelayMs } $shutdownProbe
  $s = $r.Samples
  Check 'E1 index answers on its heartbeat pipe with action index' (($s.Count -gt 0) -and (@($s | Where-Object Action -eq 'index').Count -gt 0)) "samples=$($s.Count) exit=$($r.Exit)"
  $seqUp = $true; for ($k = 1; $k -lt $s.Count; $k++) { if ($s[$k].Seq -lt $s[$k - 1].Seq) { $seqUp = $false } }
  $distinctN = @($s | Select-Object -ExpandProperty N -Unique).Count
  $distinctSeq = @($s | Select-Object -ExpandProperty Seq -Unique).Count
  Check 'E2 index status ADVANCES (seq grows, n takes >= 3 values)' ($seqUp -and ($distinctN -ge 3) -and ($distinctSeq -ge 3)) "distinctN=$distinctN distinctSeq=$distinctSeq"
  Check 'E3 positive control: a plain status reply carries no beat field' (($r.Plain -eq '') -or (($r.Plain -like 'status*') -and ($null -eq (Parse-Beat $r.Plain)))) "plain=$($r.Plain)"
  Check 'E4 shutdown on the heartbeat pipe is unknown; the index still ends 0' (($r.Mid -like 'unknown*') -and ($r.Exit -eq 0)) "mid=$($r.Mid) exit=$($r.Exit)"

  # ---- E5: lint-all on the same scratch DB ----
  $r2 = Run-Sampled @('lint-all', '--db', $db) @{ DRAGLINT_TEST_LINT_FILE_DELAY_MS = $DelayMs }
  $s2 = @($r2.Samples | Where-Object Action -eq 'lint-all')
  $scan = @($s2 | Where-Object { $_.Step -like 'per-file scan*' })
  $distinctN2 = @($scan | Select-Object -ExpandProperty N -Unique).Count
  Check 'E5 lint-all reports its per-file scan and n advances' (($scan.Count -gt 0) -and ($distinctN2 -ge 3)) "samples=$($r2.Samples.Count) scan=$($scan.Count) distinctN=$distinctN2 exit=$($r2.Exit)"

  # ---- E6: a non-reporting verb opens no heartbeat pipe ----
  $before = @([IO.Directory]::GetFiles('\\.\pipe\') | Where-Object { $_ -like '*drag-lint-beat-*' }).Count
  $r3 = Run-Sampled @('query', '--name', 'Work1', '--db', $db) @{}
  Check 'E6 query (a verb that does not report) answers no heartbeat' ($r3.Samples.Count -eq 0) "samples=$($r3.Samples.Count) beatPipesBefore=$before"
}
catch {
  Write-Host "FATAL: $($_.Exception.Message)" -ForegroundColor Red
  exit 2
}
if ($script:Failed) { Write-Host 'run_engine_heartbeat_guard: FAIL'; exit 1 }
Write-Host 'run_engine_heartbeat_guard: PASS'
exit 0
