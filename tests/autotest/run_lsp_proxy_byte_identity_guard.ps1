# dl:serial: LSP proxy family. These spawn and reap DelphiLSP/LspStub children and have
#   been observed interfering with EACH OTHER while strictly SERIALISED (three
#   battery runs, exactly one of two adjacent proxy guards failing each time,
#   never both, never the same one; root cause fixed in 41b0004 -- the child
#   was identified by process NAME across the whole machine). A bug class that
#   survives serialisation gets worse under concurrency, not better.
<#
  run_lsp_proxy_byte_identity_guard.ps1 -- a recorded LSP session played through
  `drag-lint lsp --proxy` must produce the same reply bytes as playing it
  through RAD Studio's DelphiLSP directly.

  WHAT THIS PINS (spec 2026-08-18-lsp-merge-proxy-design.md, criterion 2):

    2. WHEN the same recorded LSP session is played through the proxy and
       through DelphiLSP directly THE reply byte streams SHALL be identical.

  This is the criterion the whole design rests on. The IDE's Code Insight
  manager is exclusive, so registering the proxy replaces the compiler front
  end with us; the only acceptable evidence for that is that the client cannot
  tell the difference.

  NORMALISATION APPLIED: NONE.

  That is worth stating explicitly, because the plan expected trouble here and
  an over-eager normaliser would turn this criterion into a tautology.
  Measured 2026-08-18: DelphiLSP 37.0 replies to this session with 782 bytes
  that are byte-for-byte identical across repeated runs. There is no timestamp,
  no session id and no absolute path anywhere in the replies, so nothing needs
  to be masked. If a future RAD Studio makes a reply vary, the honest fix is to
  mask that ONE field and say so here -- not to relax the comparison.

  WHY IT ALSO RUNS DELPHILSP TWICE. Without that, a RAD Studio update that made
  replies nondeterministic would fail this guard as though the PROXY had
  corrupted the stream, and the next session would go looking for the bug in
  our code. Case A establishes that the reference itself is stable; only then
  does case B mean what it says.

  WHY THE CONTENT IS ASSERTED TOO. Two empty streams are byte-identical. Case C
  names bytes that must be present, so the comparison cannot pass by both sides
  failing in the same way.

  KNOWN AND NOT OUR BUG: DelphiLSP exits with 0xC0000005 when its stdin closes.
  It does so identically with and without the relay, which is itself part of
  what "indistinguishable" means here.

  RED PROOF (recorded 2026-08-18): run against the pre-Task-1 engine, case B
  fails with the proxy stream EMPTY -- the binary rejects --proxy and spawns
  nothing.
#>

[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
  [string]$Server  = 'C:\Program Files (x86)\Embarcadero\Studio\37.0\bin64\DelphiLSP.exe',
  [string]$Session = "$PSScriptRoot\fixtures\lspproxy\session-basic.txt"
)

$ErrorActionPreference = 'Stop'
$script:Failed = $false

function Check([string]$n, [bool]$ok, [string]$d) {
  $s = if ($ok) { 'PASS' } else { 'FAIL' }
  $c = if ($ok) { 'Green' } else { 'Red' }
  Write-Host ("  [{0}] {1} {2}" -f $s, $n, $d) -ForegroundColor $c
  if (-not $ok) { $script:Failed = $true }
}

function BytesEqual([byte[]]$a, [byte[]]$b) {
  if ($a.Length -ne $b.Length) { return $false }
  for ($i = 0; $i -lt $a.Length; $i++) { if ($a[$i] -ne $b[$i]) { return $false } }
  return $true
}

function FirstDiff([byte[]]$a, [byte[]]$b) {
  $n = [Math]::Min($a.Length, $b.Length)
  for ($i = 0; $i -lt $n; $i++) { if ($a[$i] -ne $b[$i]) { return "byte $i" } }
  if ($a.Length -ne $b.Length) { return "length $($a.Length) vs $($b.Length)" }
  return 'none'
}

# Plays the recorded session into $exe and returns the reply bytes.
#
# The wait is "output stopped growing", not a fixed sleep: a fixed sleep long
# enough for a cold DelphiLSP makes every run pay for the worst case, and one
# too short truncates the reply and reports it as a mismatch.
function Play {
  param([string]$exe, [string[]]$argv, [byte[]]$payload)

  $psi = New-Object System.Diagnostics.ProcessStartInfo
  $psi.FileName = $exe
  foreach ($a in $argv) { [void]$psi.ArgumentList.Add($a) }
  $psi.RedirectStandardInput  = $true
  $psi.RedirectStandardOutput = $true
  $psi.RedirectStandardError  = $true
  $psi.UseShellExecute        = $false
  $psi.CreateNoWindow         = $true
  $psi.WorkingDirectory       = (Split-Path $Session -Parent)

  $p     = [System.Diagnostics.Process]::Start($psi)
  $outMs = New-Object System.IO.MemoryStream
  $errMs = New-Object System.IO.MemoryStream
  $outT  = $p.StandardOutput.BaseStream.CopyToAsync($outMs)
  $errT  = $p.StandardError.BaseStream.CopyToAsync($errMs)

  $p.StandardInput.BaseStream.Write($payload, 0, $payload.Length)
  $p.StandardInput.BaseStream.Flush()

  $last     = -1
  $stableAt = $null
  $deadline = (Get-Date).AddSeconds(30)
  while ((Get-Date) -lt $deadline) {
    Start-Sleep -Milliseconds 200
    $len = $outMs.Length
    if ($len -ne $last) { $last = $len; $stableAt = Get-Date; continue }
    if ($len -gt 0 -and $stableAt -and ((Get-Date) - $stableAt).TotalMilliseconds -ge 1500) { break }
  }

  try { $p.StandardInput.BaseStream.Close() } catch { }
  if (-not $p.WaitForExit(10000)) { $p.Kill($true) }
  [void]$outT.Wait(3000)
  [void]$errT.Wait(3000)

  return [pscustomobject]@{
    Out  = $outMs.ToArray()
    Err  = [System.Text.Encoding]::UTF8.GetString($errMs.ToArray())
    Code = $p.ExitCode
  }
}

function Reap {
  foreach ($n in @('DelphiLSP','Agent0','Agent1')) {
    foreach ($q in (Get-Process $n -ErrorAction SilentlyContinue)) { try { $q.Kill() } catch { } }
  }
}

Write-Host 'run_lsp_proxy_byte_identity_guard -- the client cannot tell the relay is there' -ForegroundColor Cyan

foreach ($need in @($Exe, $Session)) {
  if (-not (Test-Path $need)) {
    Write-Host "FATAL: not found -- $need" -ForegroundColor Red
    Write-Host 'FAIL' -ForegroundColor Red
    exit 1
  }
}
if (-not (Test-Path $Server)) {
  # Not a failure: this machine simply has no RAD Studio. Say so rather than
  # reporting a green that measured nothing.
  Write-Host "SKIP: DelphiLSP not installed at $Server" -ForegroundColor Yellow
  Write-Host 'PASS' -ForegroundColor Green
  exit 0
}

$payload = [System.IO.File]::ReadAllBytes($Session)
Write-Host "  session: $($payload.Length) bytes from $(Split-Path $Session -Leaf)"

Reap

Write-Host ''
Write-Host 'CASE A: the reference is stable -- DelphiLSP replies the same twice' -ForegroundColor Cyan
$d1 = Play $Server @() $payload
Start-Sleep -Milliseconds 400
$d2 = Play $Server @() $payload
Check 'direct run 1 produced replies' ($d1.Out.Length -gt 0) "$($d1.Out.Length) bytes, exit $($d1.Code)"
Check 'direct run 2 produced replies' ($d2.Out.Length -gt 0) "$($d2.Out.Length) bytes, exit $($d2.Code)"
$stable = BytesEqual $d1.Out $d2.Out
Check 'DelphiLSP is deterministic for this session' $stable `
  $(if ($stable) { 'no normalisation needed' } else { "diverges at $(FirstDiff $d1.Out $d2.Out) -- the REFERENCE moved, not the relay" })

# v(session 73): establish the EXIT CODE's stability too, because CASE B
# asserts the relay passes it through unchanged.
#
# It did not establish it before, and that is the whole of
# INBOX-lsp-proxy-guard-asserts-an-unstable-exit-code: this runner failed about
# 1 run in 6 (measured: 1 failure in a battery, then 2 of 3, then 5 passes and a
# failure on the 6th standalone -- so NOT battery contention, which is the usual
# cause in this repo). DelphiLSP's shutdown code is nondeterministic for the
# same input, so "proxy code equals direct code" was a coin toss dressed as an
# invariant, and the relay -- which is innocent -- took the blame.
#
# A flaky guard in a 474-runner battery is a standing tax: every red forces a
# standalone re-run before anyone can trust the result, which is exactly the
# habit that lets a REAL regression be waved through as "that one flakes".
# The reference exit code is a TWO-VALUED RANDOM VARIABLE, and this took two
# attempts to get right -- both recorded, because the first was a plausible fix
# that would have kept flaking.
#
# Measured over 6 standalone runs: DelphiLSP exits either 0 or -1073741819
# (0xC0000005, an access violation) after the same session, apparently depending
# on whether its shutdown races itself. So:
#
#   Attempt 1 -- "assert the code is stable across two direct runs". WRONG. Run
#   4 of 6 had BOTH direct runs at -1073741819, i.e. "stable", and the proxy run
#   exited differently anyway. With two outcomes, two samples agreeing carries
#   almost no information; the check merely moved the coin toss to a new line.
#
#   What is left is what can actually be established: the set of codes the
#   reference produced on this machine, this run. Asserting the proxy's code is
#   a MEMBER of that set is sound -- it can never fail on a value DelphiLSP
#   itself produced, and it still rejects a relay that invented one (1, 3, a
#   mangled signal), which is the only failure the criterion ever cared about.
#   Attempt 2 -- "assert the proxy's code is one of the two the reference just
#   produced". ALSO WRONG, and it failed 1 run in 8: both direct runs crashed,
#   so the sampled set was {-1073741819} alone, and the proxy exited 0 -- a
#   value DelphiLSP produces perfectly legitimately. Two samples cannot
#   establish the support of a two-valued distribution. Sampling harder is not
#   the answer either; it only makes the flake rarer and therefore more
#   confusing when it finally fires.
#
# So the universe is PINNED FROM MEASUREMENT instead of sampled per run. These
# are the only codes observed across 14 standalone runs. The assertion is still
# non-vacuous -- it rejects a relay that invents 1, 3, or a mangled signal,
# which is the only failure the pass-through criterion ever cared about -- and
# it cannot flake on a value the child chose for itself.
#
# THE CRASH IS A REAL FINDING, not just noise to route around: DelphiLSP exits
# 0xC0000005 (access violation) on shutdown roughly half the time for a session
# it has just served correctly. The reply stream is byte-identical either way,
# so it is a teardown race, not a protocol fault -- recorded here and in
# INBOX-lsp-proxy-guard-asserts-an-unstable-exit-code.md rather than lost.
$KnownCodes = @(0, -1073741819)
$refCodes   = @($d1.Code, $d2.Code) | Select-Object -Unique
Write-Host "  [NOTE] direct-run exit codes this run: $($refCodes -join ', ')" -ForegroundColor DarkGray
Check 'the reference produces only exit codes this guard knows about' `
  (@($refCodes | Where-Object { $KnownCodes -notcontains $_ }).Count -eq 0) `
  "saw $($refCodes -join ',') -- expected a subset of $($KnownCodes -join ',')"

Write-Host ''
Write-Host 'CASE B: criterion 2 -- through the relay, byte for byte' -ForegroundColor Cyan
Start-Sleep -Milliseconds 400
$viaProxy = Play $Exe @('lsp','--proxy') $payload
Check 'proxied run produced replies' ($viaProxy.Out.Length -gt 0) "$($viaProxy.Out.Length) bytes, exit $($viaProxy.Code)"
Check 'reply stream is byte-identical to a direct connection' `
  (BytesEqual $d1.Out $viaProxy.Out) `
  ("direct=$($d1.Out.Length)b proxy=$($viaProxy.Out.Length)b, first difference: $(FirstDiff $d1.Out $viaProxy.Out)")
Check 'the relay does not invent an exit code of its own' `
  ($KnownCodes -contains $viaProxy.Code) `
  "proxy=$($viaProxy.Code), known DelphiLSP codes are $($KnownCodes -join ',') -- see CASE A"

Write-Host ''
Write-Host 'CASE C: the identical streams are not identically empty' -ForegroundColor Cyan
$txt = [System.Text.Encoding]::UTF8.GetString($viaProxy.Out)
Check 'carries the initialize capabilities reply' `
  ($txt -match '"capabilities"') 'the reply that proves DelphiLSP answered'
Check 'carries a real completion result' `
  ($txt -match '"isIncomplete"') 'a completion reply with items, not an error'
Check 'carries the shutdown reply' `
  ($txt -match '"id":4') 'the session ran to the end'
Check 'framing survived: every reply has a Content-Length header' `
  (([regex]::Matches($txt, 'Content-Length:')).Count -ge 4) `
  "found $(([regex]::Matches($txt, 'Content-Length:')).Count) headers"

Reap
Write-Host ''
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
