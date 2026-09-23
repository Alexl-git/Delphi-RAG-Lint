<#
  Open-DragLintUri.ps1 -- the browser half of click-to-source.

  A browser cannot write to a named pipe, so a draglint:// click needs a
  registered protocol handler. This is it. Register it with
  Register-DragLintProtocol.ps1.

  The IDE-side server already exists and is live whenever the plugin is loaded:
  DragLint.Plugin.OpenSourceServer.pas creates \\.\pipe\drag-lint-open-source
  with PIPE_ACCESS_INBOUND, byte mode and PIPE_UNLIMITED_INSTANCES, and reads
  <file><TAB><line>[<TAB><col>]<LF> as UTF-8. This script speaks exactly that.

  Fallback mirrors the standalone viewer: if no server answers within the
  timeout, ShellExecute the file so a click still does something useful when
  the IDE is not running. Never fails silently.

  URI:  draglint://open?file=<url-encoded path>&line=<n>[&col=<n>]
#>
[CmdletBinding()]
param(
  [Parameter(Position = 0)][string] $Uri,
  [int]    $TimeoutMs = 1000,
  [switch] $WhatIfOnly,          # parse + report, never touch the pipe
  [string] $LogPath = (Join-Path $env:TEMP 'draglint-uri.log')
)

$ErrorActionPreference = 'Stop'

function Write-Log([string] $m) {
  $line = "{0}  {1}" -f (Get-Date).ToString('s'), $m
  try { Add-Content -Path $LogPath -Value $line -Encoding utf8 } catch { }
  Write-Verbose $line
}

if ([string]::IsNullOrWhiteSpace($Uri)) { Write-Log 'no URI given'; exit 2 }
Write-Log "uri: $Uri"

# Browsers hand the whole URI as one argument and may append a trailing slash.
$u = $Uri.Trim().TrimEnd('/')
if ($u -notmatch '^draglint://') { Write-Log "not a draglint uri: $u"; exit 2 }

$q = $u -replace '^draglint://[^?]*\??', ''
$parts = @{}
foreach ($kv in ($q -split '&')) {
  $i = $kv.IndexOf('=')
  if ($i -gt 0) { $parts[$kv.Substring(0, $i).ToLower()] = [uri]::UnescapeDataString($kv.Substring($i + 1)) }
}

$file = $parts['file']
$line = $parts['line']
$col  = $parts['col']
if ([string]::IsNullOrWhiteSpace($file)) { Write-Log 'no file= in uri'; exit 2 }
# "Treat a missing/garbled line number as 1 rather than rejecting the message."
if ($line -notmatch '^\d+$' -or [int]$line -lt 1) { $line = '1' }

$payload = if ($col -match '^\d+$') { "$file`t$line`t$col`n" } else { "$file`t$line`n" }
Write-Log ("resolved: file={0} line={1} col={2}" -f $file, $line, $(if ($col) { $col } else { '-' }))

if ($WhatIfOnly) {
  [pscustomobject]@{ File = $file; Line = [int]$line; Col = $col
                     Payload = ($payload -replace "`t", '<TAB>' -replace "`n", '<LF>') }
  exit 0
}

$sent = $false
try {
  $c = New-Object System.IO.Pipes.NamedPipeClientStream('.', 'drag-lint-open-source', [System.IO.Pipes.PipeDirection]::Out)
  $c.Connect($TimeoutMs)
  $b = [Text.Encoding]::UTF8.GetBytes($payload)
  $c.Write($b, 0, $b.Length)
  $c.Flush()
  $c.Dispose()
  $sent = $true
  Write-Log "sent $($b.Length) bytes to the IDE"
} catch {
  Write-Log "pipe unavailable ($($_.Exception.Message)) -- falling back to ShellExecute"
}

if (-not $sent) {
  if (Test-Path -LiteralPath $file) {
    Start-Process -FilePath $file
    Write-Log 'opened via ShellExecute'
  } else {
    Write-Log "file not found on disk: $file"
    exit 3
  }
}
exit 0
