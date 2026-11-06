<#
  run_mcp_rename_atomic_probe.ps1 -- 1.40 lane mcp (INBOX-139 #3 and #5).

  A. rename_symbol (dry_run=false) is all-or-nothing: with the test seam
     DRAGLINT_TEST_FAIL_WRITE_AT=2 the second file write raises; the first file
     (already written) must be restored byte-for-byte, and the call answers
     isError. Positive control: without the seam both units are rewritten.
  B. The MCP freshness probe is throttled: with DRAGLINT_MCP_PROBE_TTL_MS=60000 a
     file touched between two calls does NOT add the note to the second call;
     with TTL=0 (every call) it does. First call is fresh in both.
  Run from a neutral cwd, pwsh 7.
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
  [string]$WorkDir = "C:\TEMP\draglint_mcp_atomic_probe_$PID"
)
try {
$ErrorActionPreference = 'Stop'; $script:fail = $false
$env:DRAGLINT_RENAME_TEST_UNGATED = '1' # lane 144: these fixtures do not compile; run_rename_precise.ps1 proves the gate
function Check($n, $ok, $d) {
  Write-Host ("[{0}] {1}" -f (@('FAIL', 'PASS')[[int][bool]$ok]), $n) -ForegroundColor (@('Red', 'Green')[[int][bool]$ok])
  if (-not $ok) { if ($d) { Write-Host "      $d" -ForegroundColor DarkGray }; $script:fail = $true }
}
function Write-Ascii($p, $t) { [IO.File]::WriteAllText($p, (($t -replace "`r`n", "`n") -replace "`n", "`r`n"), [Text.Encoding]::ASCII) }
$Exe = (Resolve-Path $Exe).Path
if (Test-Path $WorkDir) { [IO.Directory]::Delete($WorkDir, $true) }
New-Item -ItemType Directory $WorkDir | Out-Null

function New-Fixture([string]$Name) {
  $src = Join-Path $WorkDir "$Name\src"; New-Item -ItemType Directory $src -Force | Out-Null
  Write-Ascii (Join-Path $src 'uLib.pas') "unit uLib;`r`n`r`ninterface`r`n`r`nprocedure Helper;`r`n`r`nimplementation`r`n`r`nprocedure Helper;`r`nbegin`r`nend;`r`n`r`nend.`r`n"
  Write-Ascii (Join-Path $src 'uUse.pas') "unit uUse;`r`n`r`ninterface`r`n`r`nprocedure Go;`r`n`r`nimplementation`r`n`r`nuses uLib;`r`n`r`nprocedure Go;`r`nbegin`r`n  Helper;`r`nend;`r`n`r`nend.`r`n"
  Write-Ascii (Join-Path $src 'P.dpr') "program P;`r`n`r`nuses uLib, uUse;`r`n`r`nbegin`r`n  Go;`r`nend.`r`n"
  $db = Join-Path $WorkDir "$Name\p.sqlite"
  $env:DRAGLINT_RULE_CACHE = '0'
  & $Exe index --project (Join-Path $src 'P.dpr') --db $db 2>&1 | Out-Null
  $env:DRAGLINT_RULE_CACHE = $null
  [pscustomobject]@{ Src = $src; Db = $db }
}
# Live serve session: send a request, read one response line, return parsed object.
function Start-Serve($db) {
  $psi = [Diagnostics.ProcessStartInfo]::new($Exe, "serve --db `"$db`"")
  $psi.RedirectStandardInput = $true; $psi.RedirectStandardOutput = $true; $psi.RedirectStandardError = $true
  $psi.UseShellExecute = $false; $psi.WorkingDirectory = $WorkDir
  $p = [Diagnostics.Process]::Start($psi)
  $null = $p.StandardError.ReadToEndAsync()
  $p
}
function Ask($p, $id, $method, $params) {
  $p.StandardInput.WriteLine((@{ jsonrpc = '2.0'; id = $id; method = $method; params = $params } | ConvertTo-Json -Depth 8 -Compress))
  $p.StandardInput.Flush()
  $t = $p.StandardOutput.ReadLineAsync()
  if (-not $t.Wait(30000)) { throw "no answer to $method" }
  $t.Result | ConvertFrom-Json
}
function Open-Session($db) {
  $p = Start-Serve $db
  $null = Ask $p 1 'initialize' @{ protocolVersion = '2024-11-05'; capabilities = @{}; clientInfo = @{ name = 'guard'; version = '1' } }
  $p.StandardInput.WriteLine('{"jsonrpc":"2.0","method":"notifications/initialized"}'); $p.StandardInput.Flush()
  $p
}
function Stop-Serve($p) { try { $p.StandardInput.Close(); if (-not $p.WaitForExit(10000)) { $p.Kill($true) } } catch {} }

# --- A: atomic rename ---------------------------------------------------------
function Rename-With($fx, $failAt) {
  $env:DRAGLINT_TEST_FAIL_WRITE_AT = $failAt
  try { $p = Open-Session $fx.Db } finally { $env:DRAGLINT_TEST_FAIL_WRITE_AT = $null }
  try { Ask $p 2 'tools/call' @{ name = 'rename_symbol'; arguments = @{ qname = 'uLib.Helper'; to = 'HelperRenamed'; dry_run = $false } } }
  finally { Stop-Serve $p }
}
$a = New-Fixture 'A'
$lib = Join-Path $a.Src 'uLib.pas'; $use = Join-Path $a.Src 'uUse.pas'
$h0 = (Get-FileHash $lib).Hash + (Get-FileHash $use).Hash
$ra = Rename-With $a 2
Check 'A write #2 fails: the call answers isError' ($ra.result.isError -eq $true) ($ra | ConvertTo-Json -Depth 6 -Compress)
Check 'A ... and NEITHER unit is left renamed (rolled back)' (((Get-FileHash $lib).Hash + (Get-FileHash $use).Hash) -eq $h0) ((Get-Content $lib -Raw) + (Get-Content $use -Raw))
$b = New-Fixture 'B'
$rb = Rename-With $b $null
Check 'A control (no seam): applied, both units rewritten' ($rb.result.isError -ne $true -and (Select-String -Path (Join-Path $b.Src 'uLib.pas'), (Join-Path $b.Src 'uUse.pas') -Pattern 'HelperRenamed' -Quiet) -and (Get-Content (Join-Path $b.Src 'uUse.pas') -Raw) -match 'HelperRenamed') ($rb | ConvertTo-Json -Depth 6 -Compress)

# --- B: throttled probe -------------------------------------------------------
function Probe-Run([string]$Ttl) {
  $fx = New-Fixture "P$Ttl"
  $env:DRAGLINT_MCP_PROBE_TTL_MS = $Ttl
  try { $p = Open-Session $fx.Db } finally { $env:DRAGLINT_MCP_PROBE_TTL_MS = $null }
  try {
    $r1 = Ask $p 2 'tools/call' @{ name = 'find_symbol'; arguments = @{ name = 'Helper' } }
    (Get-Item (Join-Path $fx.Src 'uUse.pas')).LastWriteTime = (Get-Date).AddMinutes(5)
    $r2 = Ask $p 3 'tools/call' @{ name = 'find_symbol'; arguments = @{ name = 'Helper' } }
    [pscustomobject]@{ N1 = @($r1.result.content).Count; N2 = @($r2.result.content).Count }
  } finally { Stop-Serve $p }
}
$t0 = Probe-Run '0'
Check 'B control TTL=0: first call fresh (1 item), second carries the note (2 items)' ($t0.N1 -eq 1 -and $t0.N2 -eq 2) "$($t0 | ConvertTo-Json -Compress)"
$t6 = Probe-Run '60000'
Check 'B TTL=60000: second call within the window does not re-probe (1 item)' ($t6.N1 -eq 1 -and $t6.N2 -eq 1) "$($t6 | ConvertTo-Json -Compress)"
}
finally {
  $env:DRAGLINT_RULE_CACHE = $null; $env:DRAGLINT_TEST_FAIL_WRITE_AT = $null; $env:DRAGLINT_MCP_PROBE_TTL_MS = $null
  if ($WorkDir -and (Test-Path $WorkDir)) { try { [IO.Directory]::Delete($WorkDir, $true) } catch {} }
}
if ($script:fail) { Write-Host 'run_mcp_rename_atomic_probe: FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'run_mcp_rename_atomic_probe: PASS' -ForegroundColor Green; exit 0
