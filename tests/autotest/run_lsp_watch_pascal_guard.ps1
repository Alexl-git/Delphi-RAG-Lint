#Requires -Version 7
<#
  run_lsp_watch_pascal_guard.ps1 -- a .pas edited ON DISK (by an agent, not in the editor)
  must re-lint without a server restart. The VS Code client watches **/*.{pas,dpr,dpk,inc,dfm}
  and sends workspace/didChangeWatchedFiles; the server re-lints files the client has NOT open.

  One LIVE server session (the fixture is rewritten between messages, so a pre-recorded
  stdin file cannot drive it).
  PC1  Changed (2), file not open, fixture has a with-statement -> publishDiagnostics non-empty
  PC2  fixture rewritten clean, Changed (2) again                -> publishDiagnostics, EMPTY array
  REF  draglint/refreshDiagnostics for an OPEN uri               -> publishes (positive control for NEG)
  NEG  Changed (2) for an OPEN uri                               -> NO publish (editor buffer is authoritative)
  NEG2 Changed (2) for a non-lintable file (drag-lint.json)      -> NO publish

  RUN RED FIRST: on an engine without the change PC1 and PC2 fail; REF fails too (unknown method).
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\drag-lint-lsp-watchpas-$PID",
  [int]$WaitMs     = 20000,
  [int]$QuietMs    = 3000
)
$ErrorActionPreference = 'Stop'
$script:Failed = $false
$script:Proc = $null
function Check($n, $ok, $d = '') {
  $s = if ($ok) { 'PASS' } else { 'FAIL' }
  $c = if ($ok) { 'Green' } else { 'Red' }
  Write-Host ("  [{0}] {1} {2}" -f $s, $n, $d) -ForegroundColor $c
  if (-not $ok) { $script:Failed = $true }
}
if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
$Exe = (Resolve-Path $Exe).Path
if (Test-Path $WorkDir) { [System.IO.Directory]::Delete($WorkDir, $true) }
New-Item -ItemType Directory -Force "$WorkDir\src" | Out-Null

function New-Src([bool]$WithFinding) {
  $body = if ($WithFinding) { @('  with X do', '    Free;') } else { @('  X.Free;') }
  (@('unit uWatch;', '', 'interface', '', 'procedure A(X: TObject);', '', 'implementation', '',
     'procedure A(X: TObject);', 'begin') + $body + @('end;', '', 'end.') -join "`r`n") + "`r`n"
}
$file  = "$WorkDir\src\uWatch.pas"
$other = "$WorkDir\src\uOpen.pas"
[System.IO.File]::WriteAllText($file, (New-Src $true), [System.Text.Encoding]::ASCII)
[System.IO.File]::WriteAllText($other, (New-Src $true), [System.Text.Encoding]::ASCII)
$json = "$WorkDir\src\drag-lint.json"
[System.IO.File]::WriteAllText($json, '{}', [System.Text.Encoding]::ASCII)
function ToUri($p) { 'file:///' + ($p -replace '\\', '/') -replace ' ', '%20' }
$uri = ToUri $file; $uriOpen = ToUri $other; $uriJson = ToUri $json

# ---- live LSP session -------------------------------------------------------------
$psi = [System.Diagnostics.ProcessStartInfo]::new($Exe, 'lsp')
$psi.WorkingDirectory = $WorkDir
$psi.RedirectStandardInput = $true; $psi.RedirectStandardOutput = $true; $psi.RedirectStandardError = $true
$psi.UseShellExecute = $false; $psi.CreateNoWindow = $true
$script:Proc = [System.Diagnostics.Process]::Start($psi)
$errTask = $script:Proc.StandardError.ReadToEndAsync()   # drain stderr so the server never blocks on it
$script:Buf = [System.Text.StringBuilder]::new()
$script:Raw = New-Object byte[] 65536
$script:Rd  = $null
$script:Pubs = [System.Collections.Generic.List[object]]::new()
$script:Scan = 0

function Send($obj) {
  $j = $obj | ConvertTo-Json -Depth 20 -Compress
  $bytes = [System.Text.Encoding]::UTF8.GetBytes($j)
  $hdr = [System.Text.Encoding]::ASCII.GetBytes("Content-Length: $($bytes.Length)`r`n`r`n")
  $s = $script:Proc.StandardInput.BaseStream
  $s.Write($hdr, 0, $hdr.Length); $s.Write($bytes, 0, $bytes.Length); $s.Flush()
}
# Reads whatever arrives within $Ms (returns early once a read completes and nothing follows quickly).
function Pump([int]$Ms) {
  $deadline = [DateTime]::UtcNow.AddMilliseconds($Ms)
  $stream = $script:Proc.StandardOutput.BaseStream
  while ([DateTime]::UtcNow -lt $deadline) {
    if ($null -eq $script:Rd) { $script:Rd = $stream.ReadAsync($script:Raw, 0, $script:Raw.Length) }
    if (-not $script:Rd.Wait(100)) { continue }
    $n = $script:Rd.Result; $script:Rd = $null
    if ($n -le 0) { break }
    # ASCII-safe: fixtures are 7-bit, so a byte is a char and Content-Length (bytes) matches.
    [void]$script:Buf.Append([System.Text.Encoding]::UTF8.GetString($script:Raw, 0, $n))
  }
  $all = $script:Buf.ToString()
  while ($true) {
    $m = [regex]::Match($all.Substring($script:Scan), 'Content-Length:\s*(\d+)\r\n\r\n')
    if (-not $m.Success) { break }
    $start = $script:Scan + $m.Index + $m.Length; $len = [int]$m.Groups[1].Value
    if ($start + $len -gt $all.Length) { break }
    $msg = $all.Substring($start, $len) | ConvertFrom-Json
    if ($msg.method -eq 'textDocument/publishDiagnostics') { $script:Pubs.Add($msg.params) }
    $script:Scan = $start + $len
  }
}
function PubCount($u) { @($script:Pubs | Where-Object { $_.uri -ceq $u }).Count }
# Waits until $u has more than $Before publishes; returns the newest publish for it, else $null.
function Wait-Pub($u, [int]$Before) {
  $deadline = [DateTime]::UtcNow.AddMilliseconds($WaitMs)
  while ([DateTime]::UtcNow -lt $deadline) {
    Pump 500
    if ((PubCount $u) -gt $Before) { return @($script:Pubs | Where-Object { $_.uri -ceq $u })[-1] }
  }
  return $null
}
function Notify-Changed($u, [int]$Type = 2) {
  Send @{ jsonrpc='2.0'; method='workspace/didChangeWatchedFiles'; params=@{ changes=@(@{ uri=$u; type=$Type }) } }
}

try {
  Send @{ jsonrpc='2.0'; id=1; method='initialize'; params=@{ processId=$null; rootUri=(ToUri $WorkDir); capabilities=@{} } }
  Send @{ jsonrpc='2.0'; method='initialized'; params=@{} }
  Pump 1500

  Write-Host 'CASE PC1: Changed, file not open, with-statement on disk' -ForegroundColor Cyan
  $b = PubCount $uri
  Notify-Changed $uri
  $p = Wait-Pub $uri $b
  Check 'PC1: publishDiagnostics arrives with findings' (($null -ne $p) -and (@($p.diagnostics).Count -ge 1)) $(if ($p) { "n=$(@($p.diagnostics).Count)" } else { 'no publish' })

  Write-Host 'CASE PC2: file rewritten clean on disk, Changed again' -ForegroundColor Cyan
  [System.IO.File]::WriteAllText($file, (New-Src $false), [System.Text.Encoding]::ASCII)
  $b = PubCount $uri
  Notify-Changed $uri
  $p = Wait-Pub $uri $b
  Check 'PC2: publishDiagnostics arrives with an EMPTY array' (($null -ne $p) -and (@($p.diagnostics).Count -eq 0)) $(if ($p) { "n=$(@($p.diagnostics).Count)" } else { 'no publish' })

  Write-Host 'CASE REF: didOpen then draglint/refreshDiagnostics (positive control)' -ForegroundColor Cyan
  Send @{ jsonrpc='2.0'; method='textDocument/didOpen'; params=@{ textDocument=@{ uri=$uriOpen; languageId='pascal'; version=1; text=[System.IO.File]::ReadAllText($other) } } }
  $p = Wait-Pub $uriOpen 0
  Check 'PC: didOpen publishes' ($null -ne $p)
  Pump $QuietMs
  $b = PubCount $uriOpen
  Send @{ jsonrpc='2.0'; method='draglint/refreshDiagnostics'; params=@{ uris=@($uriOpen) } }
  $p = Wait-Pub $uriOpen $b
  Check 'REF: refreshDiagnostics republishes an open uri' ($null -ne $p)

  Write-Host 'CASE NEG: Changed for an OPEN uri must not publish' -ForegroundColor Cyan
  Pump $QuietMs
  $b = PubCount $uriOpen
  Notify-Changed $uriOpen
  Pump $QuietMs
  Check 'NEG: no publish for the open uri' ((PubCount $uriOpen) -eq $b) "before=$b after=$(PubCount $uriOpen)"

  Write-Host 'CASE NEG2: Changed for drag-lint.json must not publish diagnostics for it' -ForegroundColor Cyan
  Notify-Changed $uriJson
  Pump $QuietMs
  Check 'NEG2: no publish for the manifest uri' ((PubCount $uriJson) -eq 0)

  Send @{ jsonrpc='2.0'; id=99; method='shutdown'; params=@{} }
  Send @{ jsonrpc='2.0'; method='exit'; params=@{} }
} finally {
  if ($script:Proc -and -not $script:Proc.HasExited) {
    if (-not $script:Proc.WaitForExit(5000)) { try { $script:Proc.Kill($true) } catch {} }
  }
  if (Test-Path $WorkDir) { try { [System.IO.Directory]::Delete($WorkDir, $true) } catch {} }
}
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
