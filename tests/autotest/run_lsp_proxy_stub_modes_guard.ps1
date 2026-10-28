#Requires -Version 7
# dl:serial: LSP proxy family. Spawns and reaps LspStub children and runs the
#   four shipped proxy guards; the sibling proxy guards were observed
#   interfering with each other even when strictly serialised (root cause fixed
#   in 41b0004), so this one joins the quarantine.
<#
  run_lsp_proxy_stub_modes_guard.ps1 -- the stub server's PUSH, SCRIPTED and LOG
  modes, plus the proxy's acceptance of the --merge-* flags (merge plan P0).

  WHY THIS EXISTS. The merge handlers (diagnostics, completion, hover) need a
  DelphiLSP stand-in that does more than echo: one that pushes a notification
  unprompted (publishDiagnostics), one that ANSWERS requests with known results
  after a known delay (so a budget can be exceeded on purpose), and one that
  records what it actually received (so a guard can prove the proxy forwarded or
  swallowed a frame). Without these the merge guards could only assert silence,
  and a silence-only assertion passes with the feature off.

  Checks:
    (a) push mode through the plain relay: the pushed file's bytes reach the
        client verbatim, right after STUB-PREAMBLE-BEGIN (positive control: the
        bytes are ABSENT when the env var is not set);
    (b) scripted mode: scripted results come back framed with a correct
        Content-Length; a request whose Content-Type header precedes
        Content-Length is still answered; an unscripted request gets -32601;
    (c) the request log lists each received frame's method and id;
    (d) the four shipped proxy guards still PASS with none of the env vars set;
    (e) `lsp --proxy --merge-diagnostics --merge-budget-ms 0` is ACCEPTED (the
        stub's exit code 42, not 3); positive control: an unknown --merge-bogus
        IS rejected with 3, so the check can fail.
    (f) an interceptor answering True with an EMPTY replacement is declined: the
        relay forwards the ORIGINAL frame (merge fix round 1). Driven by the
        engine's test seam DRAGLINT_MERGE_TEST_EMPTY_REPLACEMENT=1; RED on an
        engine that swallows (output shorter than the plain relay's).

  The proxy guards default -Exe to dll-win64; a lane passes its own engine.
  Run from a NEUTRAL CWD (C:\TEMP), pwsh 7.
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\draglint_lspproxy_stubmodes_$PID"
)
try {
$ErrorActionPreference = 'Stop'
$script:Failed = $false
function Check($n, $ok, $d = '') {
  $s = if ($ok) { 'PASS' } else { 'FAIL' }
  $c = if ($ok) { 'Green' } else { 'Red' }
  Write-Host ("  [{0}] {1} {2}" -f $s, $n, $d) -ForegroundColor $c
  if (-not $ok) { $script:Failed = $true }
}

$StubEnvVars = @('DRAGLINT_STUB_PUBLISH_FILE', 'DRAGLINT_STUB_SCRIPT', 'DRAGLINT_STUB_LOG', 'DRAGLINT_STUB_LINGER')
foreach ($v in $StubEnvVars) { [Environment]::SetEnvironmentVariable($v, $null, 'Process') }

if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
$Exe = (Resolve-Path $Exe).Path
if (Test-Path $WorkDir) { Remove-Item -Recurse -Force $WorkDir }
New-Item -ItemType Directory $WorkDir | Out-Null

function Invoke-Raw {
  param([string]$exe, [string[]]$argv, [byte[]]$c1, [hashtable]$envs = @{})
  $psi = New-Object System.Diagnostics.ProcessStartInfo
  $psi.FileName               = $exe
  foreach ($a in $argv) { [void]$psi.ArgumentList.Add($a) }
  foreach ($k in $envs.Keys) { $psi.Environment[$k] = $envs[$k] }
  $psi.RedirectStandardInput  = $true
  $psi.RedirectStandardOutput = $true
  $psi.RedirectStandardError  = $true
  $psi.UseShellExecute        = $false
  $psi.CreateNoWindow         = $true
  $p = [System.Diagnostics.Process]::Start($psi)
  $outMs = New-Object System.IO.MemoryStream
  $errMs = New-Object System.IO.MemoryStream
  $outT  = $p.StandardOutput.BaseStream.CopyToAsync($outMs)
  $errT  = $p.StandardError.BaseStream.CopyToAsync($errMs)
  try {
    $sin = $p.StandardInput.BaseStream
    if ($c1 -and $c1.Length) { $sin.Write($c1, 0, $c1.Length); $sin.Flush() }
    $sin.Close()
  } catch { }
  $done = $p.WaitForExit(20000)
  if (-not $done) { try { $p.Kill($true) } catch { } }
  [void]$outT.Wait(5000); [void]$errT.Wait(5000)
  $code = if ($done) { $p.ExitCode } else { -999 }
  return [pscustomobject]@{ Out = $outMs.ToArray(); Err = $errMs.ToArray(); Code = $code }
}
function Ascii([byte[]]$b) { if (-not $b) { return '' } [System.Text.Encoding]::ASCII.GetString($b) }
function Frame([string]$body, [string]$extraHeader = '') {
  $bb = [System.Text.Encoding]::UTF8.GetBytes($body)
  $h  = [System.Text.Encoding]::ASCII.GetBytes("$($extraHeader)Content-Length: $($bb.Length)`r`n`r`n")
  return [byte[]]($h + $bb)
}
# Splits a byte stream into LSP frames. Each item: Declared, Actual, Body.
# A frame whose declared length overruns the stream is reported with Actual < Declared.
function Split-Frames([byte[]]$b) {
  $res = @()
  $s = Ascii $b
  $pos = 0
  while ($true) {
    $m = [regex]::Match($s.Substring($pos), '(?is)Content-Length:\s*(\d+)[^\r]*\r\n(?:[^\r]*\r\n)*?\r\n')
    if (-not $m.Success) { break }
    $start = $pos + $m.Index + $m.Length
    $decl  = [int]$m.Groups[1].Value
    $avail = [Math]::Min($decl, $b.Length - $start)
    $body  = [System.Text.Encoding]::UTF8.GetString($b, $start, $avail)
    $res  += [pscustomobject]@{ Declared = $decl; Actual = $avail; Body = $body }
    $pos   = $start + $avail
  }
  return ,$res
}

Write-Host ''
Write-Host 'run_lsp_proxy_stub_modes_guard -- stub push/scripted/log modes + --merge-* acceptance' -ForegroundColor Cyan

# --- the stub server, built the same way the sibling guards build it --------
$fixtureDir = "$PSScriptRoot\fixtures\lspproxy"
$outDir     = Join-Path $WorkDir 'stub'
New-Item -ItemType Directory $outDir | Out-Null
$rs = 'C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\rsvars.bat'
$null = cmd /c "call `"$rs`" && cd /d `"$fixtureDir`" && dcc64 -CC -E`"$outDir`" -N0`"$outDir`" LspStubServer.dpr" 2>&1
$stub = "$outDir\LspStubServer.exe"
Check 'LspStubServer.exe built' (Test-Path $stub) $stub
if (-not (Test-Path $stub)) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 }
$proxyArgs = @('lsp', '--proxy', '--delphi-lsp', $stub)

# --- (a) PUSH MODE ----------------------------------------------------------
Write-Host ''
Write-Host '(a) PUSH MODE through the plain relay' -ForegroundColor Cyan
$pushBody  = '{"jsonrpc":"2.0","method":"textDocument/publishDiagnostics","params":{"uri":"file:///c:/x/Unit1.pas","diagnostics":[{"message":"stub-pushed-7f3a"}]}}'
$pushBytes = Frame $pushBody
$pushFile  = Join-Path $WorkDir 'push.bin'
[IO.File]::WriteAllBytes($pushFile, $pushBytes)
$pushed = Invoke-Raw $Exe $proxyArgs ([byte[]]@()) @{ DRAGLINT_STUB_PUBLISH_FILE = $pushFile }
$want   = 'STUB-PREAMBLE-BEGIN' + (Ascii $pushBytes)
$got    = Ascii $pushed.Out
Check 'the pushed bytes follow the preamble verbatim' ($got.StartsWith($want)) ("out=$($got.Substring(0, [Math]::Min(60, $got.Length)))")
$plain  = Invoke-Raw $Exe $proxyArgs ([byte[]]@())
Check 'positive control: no pushed bytes without the env var' (-not ((Ascii $plain.Out) -match 'stub-pushed-7f3a')) ''

# --- (b) SCRIPTED MODE + (c) LOG ------------------------------------------
Write-Host ''
Write-Host '(b) SCRIPTED MODE' -ForegroundColor Cyan
$script = Join-Path $WorkDir 'script.tsv'
$logF   = Join-Path $WorkDir 'requests.log'
$initResult = '{"capabilities":{"hoverProvider":true}}'
$compResult = '{"isIncomplete":false,"items":[{"label":"StubItem"}]}'
[IO.File]::WriteAllText($script, "initialize`t0`t$initResult`r`ntextDocument/completion`t0`t$compResult`r`n")
$req  = Frame '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{}}'
$req += Frame '{"jsonrpc":"2.0","method":"initialized","params":{}}'
$req += Frame '{"jsonrpc":"2.0","id":2,"method":"textDocument/completion","params":{"textDocument":{"uri":"file:///c:/x/Unit1.pas"},"position":{"line":0,"character":0}}}' `
              "Content-Type: application/vscode-jsonrpc; charset=utf-8`r`n"
$req += Frame '{"jsonrpc":"2.0","id":3,"method":"shutdown"}'
$sc = Invoke-Raw $Exe $proxyArgs ([byte[]]$req) @{ DRAGLINT_STUB_SCRIPT = $script; DRAGLINT_STUB_LOG = $logF }
$frames = Split-Frames $sc.Out
Check 'no preamble in scripted mode' (-not ((Ascii $sc.Out) -match 'STUB-PREAMBLE')) ''
Check 'three responses (initialized is a notification: dropped)' ($frames.Count -eq 3) ("frames=$($frames.Count) out=$(Ascii $sc.Out)")
$byId = @{}
foreach ($f in $frames) {
  try { $j = $f.Body | ConvertFrom-Json -AsHashtable; $byId[[string]$j['id']] = $f } catch { }
}
$allLen = ($frames.Count -gt 0) -and (@($frames | Where-Object { $_.Declared -ne [System.Text.Encoding]::UTF8.GetByteCount($_.Body) -or $_.Actual -ne $_.Declared }).Count -eq 0)
Check 'every response has a correct Content-Length' $allLen ''
$f1 = $byId['1']
Check 'initialize answered with the scripted result' ($f1 -and $f1.Body.Contains($initResult) -and $f1.Body.Contains('"result"')) ($f1.Body)
$f2 = $byId['2']
Check 'completion (Content-Type header FIRST) answered with the scripted result' ($f2 -and $f2.Body.Contains($compResult)) ($f2.Body)
$f3 = $byId['3']
Check 'an unscripted request gets error -32601' ($f3 -and $f3.Body.Contains('-32601')) ($f3.Body)
Check 'scripted mode exits 0 on stdin EOF' ($sc.Code -eq 0) ("code=$($sc.Code)")

Write-Host ''
Write-Host '(c) REQUEST LOG' -ForegroundColor Cyan
$logTxt = if (Test-Path $logF) { Get-Content $logF -Raw } else { '' }
Check 'the log lists initialize with its id'  ($logTxt -match "(?m)^initialize`t1\r?$") $logTxt
Check 'the log lists completion with its id'  ($logTxt -match "(?m)^textDocument/completion`t2\r?$") ''
Check 'the log lists a notification with a dash' ($logTxt -match "(?m)^initialized`t-\r?$") ''

# --- (e) --merge-* ACCEPTED -------------------------------------------------
Write-Host ''
Write-Host '(e) --merge-diagnostics / --merge-budget-ms are accepted' -ForegroundColor Cyan
$m = Invoke-Raw $Exe @('lsp', '--proxy', '--merge-diagnostics', '--merge-budget-ms', '0', '--delphi-lsp', $stub) ([byte[]]@())
Check 'exit code is the stub''s 42, not 3 (Unknown argument)' ($m.Code -eq 42) ("code=$($m.Code) err=$(Ascii $m.Err)")
Check 'the relay still delivers the preamble with merge on' ((Ascii $m.Out).StartsWith('STUB-PREAMBLE-BEGIN')) ''
# The interceptor is INSTALLED here and sees real frames in both directions;
# P0's engine declines every one, so the bytes must match the plain relay's.
$eFrame = Frame '{"jsonrpc":"2.0","id":9,"method":"textDocument/hover","params":{}}'
$mOn  = Invoke-Raw $Exe @('lsp', '--proxy', '--merge-diagnostics', '--delphi-lsp', $stub) ([byte[]]$eFrame)
$mOff = Invoke-Raw $Exe $proxyArgs ([byte[]]$eFrame)
Check 'merge ON relays the same bytes as merge OFF (frames intercepted, all declined)' (($mOn.Out.Length -gt 0) -and ($null -eq (Compare-Object $mOn.Out $mOff.Out -SyncWindow 0))) ("on=$($mOn.Out.Length) off=$($mOff.Out.Length)")
$bogus = Invoke-Raw $Exe @('lsp', '--proxy', '--merge-bogus', '--delphi-lsp', $stub) ([byte[]]@())
Check 'positive control: --merge-bogus IS rejected with 3' ($bogus.Code -eq 3) ("code=$($bogus.Code)")

# --- (f) True + EMPTY replacement = decline ---------------------------------
Write-Host ''
Write-Host '(f) an empty replacement forwards the original frame' -ForegroundColor Cyan
$mEmpty = Invoke-Raw $Exe @('lsp', '--proxy', '--merge-diagnostics', '--delphi-lsp', $stub) ([byte[]]$eFrame) @{ DRAGLINT_MERGE_TEST_EMPTY_REPLACEMENT = '1' }
Check 'True + empty replacement relays the same bytes as merge OFF (no frame dropped)' (($mEmpty.Out.Length -gt 0) -and ($null -eq (Compare-Object $mEmpty.Out $mOff.Out -SyncWindow 0))) ("empty=$($mEmpty.Out.Length) off=$($mOff.Out.Length)")
Check 'the echoed hover frame came back' ((Ascii $mEmpty.Out).Contains('textDocument/hover')) ''

# --- (d) the four shipped guards, env vars unset ----------------------------
Write-Host ''
Write-Host '(d) the shipped proxy guards, none of the stub env vars set' -ForegroundColor Cyan
foreach ($g in @('relay', 'lifecycle', 'byte_identity', 'trace')) {
  $gp  = "$PSScriptRoot\run_lsp_proxy_$($g)_guard.ps1"
  $out = & pwsh -NoProfile -File $gp -Exe $Exe 2>&1 | Out-String
  $rc  = $LASTEXITCODE
  Check "run_lsp_proxy_$($g)_guard PASS" ($rc -eq 0) ("rc=$rc" + $(if ($rc -ne 0) { "`n$out" } else { '' }))
}

Write-Host ''
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
} finally {
  foreach ($d23 in @("$env:TEMP\draglint_lspproxy_stubmodes_$PID")) { if (Test-Path -LiteralPath $d23) { Remove-Item -LiteralPath $d23 -Recurse -Force -ErrorAction SilentlyContinue } }
}
