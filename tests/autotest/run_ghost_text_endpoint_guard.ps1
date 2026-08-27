<#
  run_ghost_text_endpoint_guard.ps1 -- the ghost-text completion endpoint must
  exist, answer both client shapes, stay on loopback, and NEVER invent code.

  WHAT THIS PINS. The IDE logged, repeatedly:

      -32603 http error ... -- http://127.0.0.1:8765/api/generate
      tcp connect error: No connection could be made ... -- os error 10061

  8765 is GhostTextPort's default and /api/generate is Ollama's shape: KAI was
  configured to use drag-lint as a local completion provider and nothing was
  listening. The settings existed; the server did not.

  THE DESIGN DECISION THIS ENFORCES. drag-lint has no language model. It cannot
  generate code and must not appear to. So the endpoint answers with an
  index-derived completion only where one strong candidate exists, and with a
  WELL-FORMED EMPTY completion everywhere else. B3.4 is the assertion that
  matters: on a prompt it does not recognise, the text must be EMPTY, not a
  best guess. A plausible-looking invented completion is the worst available
  outcome -- indistinguishable from a real suggestion, and wrong.

  B3.4 is paired with a positive control on purpose. "Always return empty"
  would satisfy the emptiness assertion on its own and be useless, so the
  harness also has a prompt it DOES recognise, and that one must produce text.

  WHY A HARNESS. The real host is the IDE plugin, in-process, because only the
  OTA knows which file and cursor a request is about -- llm-ls sends neither.
  The transport therefore lives in a pure unit (DRagLint.Core.GhostText) with
  the completion source injected, and GhostTextHarness.dpr supplies a known
  source. Everything below is driven over REAL HTTP against the real server.

  WHAT THIS CANNOT SHOW: that the IDE stops logging 10061. That needs the IDE.
  Verified here is that something correct is listening and answering.

  RED PROOF (recorded 2026-08-18): before DRagLint.Core.GhostText existed there
  was no harness to build and no listener at all -- every request failed with
  the same os error 10061 the IDE reports.
#>

[CmdletBinding()]
param(
  [string]$WorkDir = "$env:TEMP\draglint_ghosttext_guard"
)

$ErrorActionPreference = 'Stop'
$script:Failed = $false

function Check([string]$n, [bool]$ok, [string]$d) {
  $s = if ($ok) { 'PASS' } else { 'FAIL' }
  $c = if ($ok) { 'Green' } else { 'Red' }
  Write-Host ("  [{0}] {1} {2}" -f $s, $n, $d) -ForegroundColor $c
  if (-not $ok) { $script:Failed = $true }
}

function Get-FreePort {
  $l = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback, 0)
  $l.Start()
  $p = $l.LocalEndpoint.Port
  $l.Stop()
  return $p
}

function Post-Json([string]$url, [string]$body, [int]$timeoutSec = 5) {
  try {
    $r = Invoke-WebRequest -Uri $url -Method Post -Body $body -ContentType 'application/json' -TimeoutSec $timeoutSec -UseBasicParsing
    return [pscustomobject]@{ Ok = $true; Status = [int]$r.StatusCode; Body = $r.Content; Err = '' }
  } catch {
    $st = 0
    if ($_.Exception.Response) { try { $st = [int]$_.Exception.Response.StatusCode } catch { } }
    return [pscustomobject]@{ Ok = $false; Status = $st; Body = ''; Err = "$($_.Exception.Message)" }
  }
}

function Wait-Listening([int]$port, [int]$timeoutMs = 8000) {
  $deadline = (Get-Date).AddMilliseconds($timeoutMs)
  while ((Get-Date) -lt $deadline) {
    $c = [System.Net.Sockets.TcpClient]::new()
    try {
      if ($c.ConnectAsync('127.0.0.1', $port).Wait(300)) { $c.Close(); return $true }
    } catch { } finally { $c.Dispose() }
    Start-Sleep -Milliseconds 150
  }
  return $false
}

Write-Host 'run_ghost_text_endpoint_guard -- the endpoint answers, on loopback, without inventing code' -ForegroundColor Cyan

$fixtureDir = "$PSScriptRoot\fixtures\ghosttext"
$srcDir     = "$PSScriptRoot\..\..\src\core"
$outDir     = "$fixtureDir\Win64\Debug"
$harness    = "$outDir\GhostTextHarness.exe"

if (Test-Path $WorkDir) { [System.IO.Directory]::Delete($WorkDir, $true) }
New-Item -ItemType Directory $WorkDir | Out-Null
New-Item -ItemType Directory -Force $outDir | Out-Null

# ---- build the harness -----------------------------------------------------
$rsvars  = 'C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\rsvars.bat'
$batPath = "$WorkDir\build_harness.bat"
$logPath = "$WorkDir\build_harness.log"
$batBody = (@(
  '@echo off'
  "call `"$rsvars`""
  "cd /d `"$fixtureDir`""
  "dcc64 -CC -U`"$srcDir`" -E`"$outDir`" -N0`"$outDir`" GhostTextHarness.dpr"
  'echo BUILD_EXITCODE=%ERRORLEVEL%'
) -join "`r`n")
[System.IO.File]::WriteAllText($batPath, $batBody, [System.Text.Encoding]::ASCII)
$null = Start-Process cmd.exe -ArgumentList "/c","`"$batPath`"" -RedirectStandardOutput $logPath -RedirectStandardError "$logPath.err" -NoNewWindow -Wait -PassThru
$blog = Get-Content $logPath -Raw -ErrorAction SilentlyContinue
Check 'GhostTextHarness.dpr builds (Win64)' `
  (($blog -match 'BUILD_EXITCODE=0') -and (Test-Path $harness)) `
  (($blog -split "`r?`n" | Where-Object { $_ -match 'Error|BUILD_EXITCODE' } | Select-Object -First 3) -join ' | ')

if (-not (Test-Path $harness)) {
  Write-Host "FATAL: harness not built -- see $logPath" -ForegroundColor Red
  Write-Host 'FAIL' -ForegroundColor Red
  exit 1
}

$procs = @()
function Start-Harness([int]$port, [string]$mode, [string]$enabled) {
  $p = Start-Process $harness `
        -ArgumentList '--port',"$port",'--seconds','25','--mode',$mode,'--enabled',$enabled `
        -PassThru -NoNewWindow -RedirectStandardOutput "$WorkDir\h_$port.log"
  $script:procs += $p
  return $p
}
function Stop-All { foreach ($p in $script:procs) { try { if (-not $p.HasExited) { $p.Kill() } } catch { } } }

try {
  # ---- CASE A: B3.1 -- off means off --------------------------------------
  Write-Host ''
  Write-Host 'CASE A: B3.1 with the setting off, NOTHING listens' -ForegroundColor Cyan
  $offPort = Get-FreePort
  $null = Start-Harness $offPort 'empty' '0'
  Start-Sleep -Milliseconds 1200
  $offLog = Get-Content "$WorkDir\h_$offPort.log" -Raw -ErrorAction SilentlyContinue
  Check 'the server reports it did not start' `
    ($offLog -match 'NOT LISTENING') "harness said: $($offLog.Trim())"
  Check 'B3.1 the port is not reachable' `
    (-not (Wait-Listening $offPort 1500)) "port $offPort"

  # ---- the serving instance ------------------------------------------------
  $port = Get-FreePort
  $null = Start-Harness $port 'candidate' '1'
  $up = Wait-Listening $port
  Check 'the server came up' $up "port $port"
  if (-not $up) { throw "harness never listened on $port" }

  # ---- CASE B: B3.2 -- Ollama shape ---------------------------------------
  Write-Host ''
  Write-Host 'CASE B: B3.2 POST /api/generate answers in Ollama shape' -ForegroundColor Cyan
  $r = Post-Json "http://127.0.0.1:$port/api/generate" '{"model":"drag-lint","prompt":"begin W.TSampleWorker."}'
  Check 'HTTP 200' ($r.Ok -and $r.Status -eq 200) "status=$($r.Status) $($r.Err)"
  $j = $null; try { $j = $r.Body | ConvertFrom-Json } catch { }
  Check 'B3.2 the body is valid JSON' ($null -ne $j) $r.Body
  Check 'B3.2 it carries a `response` member (Ollama shape)' `
    (($null -ne $j) -and ($null -ne $j.response)) $r.Body
  Check 'B3.2 it is marked done' (($null -ne $j) -and ($j.done -eq $true)) $r.Body
  # POSITIVE CONTROL for B3.4: a recognised context DOES produce text, so
  # "always empty" cannot satisfy the emptiness assertion below.
  Check 'positive control: a recognised context produces a completion' `
    (($null -ne $j) -and ($j.response -eq 'Describe')) "response='$($j.response)'"

  # ---- CASE C: B3.3 -- OpenAI shape ---------------------------------------
  Write-Host ''
  Write-Host 'CASE C: B3.3 POST /v1/completions answers in OpenAI shape' -ForegroundColor Cyan
  $r2 = Post-Json "http://127.0.0.1:$port/v1/completions" '{"prompt":"begin W.TSampleWorker."}'
  Check 'HTTP 200' ($r2.Ok -and $r2.Status -eq 200) "status=$($r2.Status) $($r2.Err)"
  $j2 = $null; try { $j2 = $r2.Body | ConvertFrom-Json } catch { }
  Check 'B3.3 the body is valid JSON' ($null -ne $j2) $r2.Body
  Check 'B3.3 it carries choices[0].text (OpenAI shape)' `
    (($null -ne $j2) -and ($null -ne $j2.choices) -and ($j2.choices.Count -ge 1) -and ($null -ne $j2.choices[0].text)) $r2.Body
  Check 'the same completion is served on both shapes' `
    (($null -ne $j2) -and ($j2.choices[0].text -eq 'Describe')) $r2.Body

  # ---- CASE D: B3.4 -- THE ONE THAT MATTERS -------------------------------
  Write-Host ''
  Write-Host 'CASE D: B3.4 an unrecognised context yields EMPTY, never a guess' -ForegroundColor Cyan
  foreach ($nonsense in @(
      '{"prompt":"qqq zzz not a delphi thing at all"}',
      '{"prompt":""}',
      '{"not-even-a-prompt":123}',
      'this is not json')) {
    $rn = Post-Json "http://127.0.0.1:$port/api/generate" $nonsense
    $jn = $null; try { $jn = $rn.Body | ConvertFrom-Json } catch { }
    $short = if ($nonsense.Length -gt 34) { $nonsense.Substring(0,34) + '...' } else { $nonsense }
    Check "B3.4 empty completion for: $short" `
      (($rn.Ok) -and ($rn.Status -eq 200) -and ($null -ne $jn) -and ($jn.response -eq '')) `
      "status=$($rn.Status) body=$($rn.Body)"
  }

  # ---- CASE E: B3.5 -- loopback only --------------------------------------
  Write-Host ''
  Write-Host 'CASE E: B3.5 the listener is bound to loopback ONLY' -ForegroundColor Cyan
  $lanIps = @(Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue |
              Where-Object { $_.IPAddress -notlike '127.*' -and $_.IPAddress -ne '0.0.0.0' } |
              Select-Object -ExpandProperty IPAddress -Unique)
  if ($lanIps.Count -eq 0) {
    Check 'B3.5 SKIPPED -- this machine has no non-loopback IPv4 address' $true 'nothing to probe'
  } else {
    $reachable = @()
    foreach ($ip in $lanIps) {
      $c = [System.Net.Sockets.TcpClient]::new()
      try { if ($c.ConnectAsync($ip, $port).Wait(700)) { $reachable += $ip } } catch { } finally { $c.Dispose() }
    }
    Check 'B3.5 the port is NOT reachable on any non-loopback address' `
      ($reachable.Count -eq 0) "probed $($lanIps -join ', '); reachable on: $($reachable -join ', ')"
  }

  # ---- CASE F: an unknown path is refused, not answered -------------------
  Write-Host ''
  Write-Host 'CASE F: an endpoint we do not serve is a 404, not a fabricated 200' -ForegroundColor Cyan
  $r4 = Post-Json "http://127.0.0.1:$port/v1/chat/completions" '{"prompt":"begin W.TSampleWorker."}'
  Check 'an unserved path returns 404' ($r4.Status -eq 404) "status=$($r4.Status) $($r4.Err)"

  # ---- CASE G: Stop() must RETURN -- the IDE-hang regression --------------
  # 2026-08-26: bds.exe twice failed to exit after the IDE window closed. The
  # teardown trace ended at "-> GGhostText.Stop" and never continued, with
  # 127.0.0.1:8765 STILL LISTENING. Stop assumed closesocket() from another
  # thread interrupts a blocked accept(); Windows does not guarantee that, so
  # Stop joined a thread that never woke.
  #
  # Every check above passes with that bug present, because they all probe a
  # server that is UP. The hang is on the way OUT, so it needs its own case.
  Write-Host ""
  Write-Host 'CASE G: Stop() returns promptly with the accept thread parked' -ForegroundColor Cyan
  $sPort = Get-FreePort
  $sLog  = "$WorkDir\stop_$sPort.log"
  $sp = Start-Process $harness -ArgumentList '--port',"$sPort",'--seconds','2','--mode','empty','--enabled','1' `
         -PassThru -NoNewWindow -RedirectStandardOutput $sLog
  $script:procs += $sp
  $exited = $sp.WaitForExit(20000)
  Check 'the harness process exits (Stop did not hang)' $exited `
    $(if ($exited) { "" } else { "still running after 20s -- Stop() never returned" })
  if (-not $exited) { try { $sp.Kill() } catch { } }
  $sOut = Get-Content $sLog -Raw -ErrorAction SilentlyContinue
  $ms = -1
  if ($sOut -match 'STOP_MS=(\d+)') { $ms = [int]$Matches[1] }
  Check 'the harness reported a teardown time' ($ms -ge 0) "output: $($sOut.Trim())"
  Check 'Stop() returned in under 2000 ms' (($ms -ge 0) -and ($ms -lt 2000)) "STOP_MS=$ms"
  # POSITIVE CONTROL: the port really was serving, so a fast Stop cannot be
  # explained by the server having failed to start.
  Check 'positive control: that harness had actually been LISTENING' `
    ($sOut -match 'LISTENING') "output: $($sOut.Trim())"
  Check 'the port is released after Stop' (-not (Wait-Listening $sPort 1200)) "port $sPort"
  # ---- CASE H: Stop() with a client MID-REQUEST -- the observed hang --------
  # CASE G parks the thread in accept(), which closesocket already unblocked.
  # The IDE hang was the other shape: the thread inside ServeOne, in recv/send.
  # Those are bounded by SO_RCVTIMEO/SO_SNDTIMEO at 5s -- LONGER than the 3s
  # join -- so the join always lost that race and abandoned a thread that was
  # working normally. Teardown telemetry showed exactly this on 2026-08-26:
  #   Stop: listening socket closed; joining accept thread
  #   Stop: TIMEOUT -- accept thread did not exit within 3000 ms
  # The fix is for Stop to close the CONNECTION BEING SERVED, not just the
  # listener. This case fails without it.
  Write-Host ""
  Write-Host 'CASE H: Stop() returns promptly with a client mid-request' -ForegroundColor Cyan
  $hPort = Get-FreePort
  $hLog  = "$WorkDir\stop_mid_$hPort.log"
  $hp = Start-Process $harness -ArgumentList '--port',"$hPort",'--seconds','4','--mode','empty','--enabled','1' `
         -PassThru -NoNewWindow -RedirectStandardOutput $hLog
  $script:procs += $hp
  $null = Wait-Listening $hPort 8000
  # Connect and send a PARTIAL request -- no blank line, so ServeOne stays in recv.
  $cli = [System.Net.Sockets.TcpClient]::new()
  try {
    $cli.Connect('127.0.0.1', $hPort)
    $s = $cli.GetStream()
    $b = [System.Text.Encoding]::ASCII.GetBytes("POST /api/generate HTTP/1.1`r`nHost: x`r`nContent-Length: 999`r`n`r`n{")
    $s.Write($b, 0, $b.Length); $s.Flush()
  } catch { }
  $exitedH = $hp.WaitForExit(25000)
  Check 'the harness exits with a client mid-request' $exitedH `
    $(if ($exitedH) { "" } else { "still running after 25s" })
  if (-not $exitedH) { try { $hp.Kill() } catch { } }
  try { $cli.Close() } catch { }
  $hOut = Get-Content $hLog -Raw -ErrorAction SilentlyContinue
  $hMs = -1
  if ($hOut -match 'STOP_MS=(\d+)') { $hMs = [int]$Matches[1] }
  Check 'positive control: that harness really was serving' ($hOut -match 'LISTENING') "output: $($hOut.Trim())"
  # 500ms, not 1500: measured FIXED=0 and UNFIXED=1513, and a threshold 13ms
  # from the failing value is a control that flakes into green.
  Check 'Stop() with a client mid-request returns in under 500 ms' `
    (($hMs -ge 0) -and ($hMs -lt 500)) "STOP_MS=$hMs (measured unfixed: 1513)"
}
finally {
  Stop-All
}

Write-Host ''
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
