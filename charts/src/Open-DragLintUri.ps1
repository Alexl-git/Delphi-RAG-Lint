<#
  Open-DragLintUri.ps1 -- the browser half of click-to-source.

  A browser cannot write to a named pipe, so a draglint:// click needs a
  registered protocol handler. This is it. Register it with
  Register-DragLintProtocol.ps1 (which installs a COPY of this file under
  %LOCALAPPDATA%\drag-lint and registers the copy).

  The IDE-side server already exists and is live whenever the plugin is loaded:
  DragLint.Plugin.OpenSourceServer.pas creates \\.\pipe\drag-lint-open-source
  with PIPE_ACCESS_INBOUND, byte mode and PIPE_UNLIMITED_INSTANCES, and reads
  <file><TAB><line>[<TAB><col>]<LF> as UTF-8. This script speaks exactly that.

  URI:  draglint://open?file=<url-encoded path>&line=<n>[&col=<n>]

  SECURITY (fix round 1, 2026-09-28). ANY web page or local HTML can carry a
  draglint:// link, so the URI is hostile until proven otherwise. Test-DragLintTarget
  validates it BEFORE any Test-Path (a UNC Test-Path alone leaks NTLM) and before any
  pipe write, and a rejection exits 2 with one log line naming the reason:
    * no control character in file / line / col (a TAB or LF would forge a second
      pipe frame);
    * a rooted LOCAL DRIVE path only (`X:\...`): no UNC, no WebDAV, no \\?\ or \\.\
      device path, no relative or drive-less path, no ':' or wildcard after the drive
      (an NTFS stream `a.exe:b.pas` reads like a .pas), no reserved device name;
    * an allow-listed SOURCE extension: .pas .dfm .dpr .dpk .inc .sql .fmx -- never a
      project file (.dproj/.groupproj: loading a project from a URL is worse than a unit);
    * line and col are digits. line=0 (a chart's focus box) and a missing line open at 1.
  IDE not running: the file opens in NOTEPAD, never by ShellExecute of its default verb.
  The default verb of an allow-listed extension is still whatever the machine associates
  with it (an IDE that loads the file's project, a SQL tool that connects); notepad only
  displays text, and a click still shows the code. The line is not positioned there.

  Dot-sourcing this file (`. .\Open-DragLintUri.ps1`) defines Test-DragLintTarget and does
  nothing else, so the validation is testable without launching anything
  (Test-DragLintProtocol.ps1). -WhatIfOnly validates and reports, never the pipe, never a
  process. Parses and runs under Windows PowerShell 5.1 as well as pwsh 7.
#>
[CmdletBinding()]
param(
  [Parameter(Position = 0)][string] $Uri,
  [int]    $TimeoutMs = 1000,
  [switch] $WhatIfOnly,          # validate + report, never touch the pipe or start a process
  [string] $LogPath = (Join-Path $env:LOCALAPPDATA 'drag-lint\uri-handler.log')
)

$ErrorActionPreference = 'Stop'

# The whole verdict on one (file, line, col) triple, already URL-decoded. Returns
# Ok/Reason/File/Line/Col; never touches the file system.
function Test-DragLintTarget([string] $File, [string] $Line, [string] $Col) {
  $no = { param($why) [pscustomobject]@{ Ok = $false; Reason = $why; File = $File; Line = 0; Col = '' } }
  if ([string]::IsNullOrEmpty($File))    { return (& $no 'no file= in uri') }
  if ($File -match '[\x00-\x1F\x7F]')    { return (& $no 'control character in file') }
  if ("$Line" -match '[\x00-\x1F\x7F]')  { return (& $no 'control character in line') }
  if ("$Col" -match '[\x00-\x1F\x7F]')   { return (& $no 'control character in col') }
  if ($File -match '^[\\/][\\/]')        { return (& $no 'network or device path') }
  if ($File -notmatch '^[A-Za-z]:\\')    { return (& $no 'not a local drive path') }
  if ($File.Substring(2) -match '[:*?"<>|/]') { return (& $no 'illegal character in path') }
  foreach ($seg in $File.Substring(3).Split('\')) {
    if ((($seg -split '\.')[0]).TrimEnd(' ') -match '^(CON|PRN|AUX|NUL|COM[0-9]|LPT[0-9])$') { return (& $no 'reserved device name') }
  }
  $ext = [IO.Path]::GetExtension($File).ToLowerInvariant()
  if (@('.pas', '.dfm', '.dpr', '.dpk', '.inc', '.sql', '.fmx') -notcontains $ext) {
    return (& $no ('extension not allowed: ' + $(if ($ext) { $ext } else { '(none)' })))
  }
  $n = 1
  if (-not [string]::IsNullOrEmpty($Line)) {
    if ($Line -notmatch '^\d{1,9}$') { return (& $no 'line is not a number') }
    $n = [Math]::Max(1, [int]$Line)
  }
  if (-not [string]::IsNullOrEmpty($Col) -and $Col -notmatch '^\d{1,9}$') { return (& $no 'col is not a number') }
  [pscustomobject]@{ Ok = $true; Reason = ''; File = $File; Line = $n; Col = "$Col" }
}

if ($MyInvocation.InvocationName -eq '.') { return }

function Write-Log([string] $m) {
  # the URI is attacker text: no control character reaches the log
  $line = "{0}  {1}" -f (Get-Date).ToString('s'), ($m -replace '[\x00-\x1F\x7F]', '?')
  try {
    $dir = Split-Path -Parent $LogPath
    if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    Add-Content -LiteralPath $LogPath -Value $line -Encoding utf8
  } catch { }
  Write-Verbose $line
}
function Stop-Rejected([string] $Why, [string] $File = '') {
  Write-Log "rejected: $Why"
  if ($WhatIfOnly) { [pscustomobject]@{ Ok = $false; Reason = $Why; File = $File; Line = 0; Col = ''; Payload = '' } }
  exit 2
}

if ([string]::IsNullOrWhiteSpace($Uri)) { Stop-Rejected 'no uri given' }
Write-Log "uri: $Uri"

# Browsers hand the whole URI as one argument and may append a trailing slash.
$u = $Uri.Trim().TrimEnd('/')
if ($u -notmatch '^draglint://') { Stop-Rejected 'not a draglint uri' }

$q = $u -replace '^draglint://[^?]*\??', ''
$parts = @{}
foreach ($kv in ($q -split '&')) {
  $i = $kv.IndexOf('=')
  if ($i -gt 0) { $parts[$kv.Substring(0, $i).ToLower()] = [uri]::UnescapeDataString($kv.Substring($i + 1)) }
}

$v = Test-DragLintTarget -File $parts['file'] -Line $parts['line'] -Col $parts['col']
if (-not $v.Ok) { Stop-Rejected $v.Reason $v.File }
$file = $v.File; $line = $v.Line; $col = $v.Col

$payload = $(if ($col) { "$file`t$line`t$col`n" } else { "$file`t$line`n" })
Write-Log ("resolved: file={0} line={1} col={2}" -f $file, $line, $(if ($col) { $col } else { '-' }))

if ($WhatIfOnly) {
  [pscustomobject]@{ Ok = $true; Reason = ''; File = $file; Line = $line; Col = $col
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
  Write-Log "IDE not running ($($_.Exception.Message))"
}

if (-not $sent) {
  # a validated LOCAL drive path only reaches this Test-Path
  if (Test-Path -LiteralPath $file -PathType Leaf) {
    Start-Process -FilePath (Join-Path $env:SystemRoot 'System32\notepad.exe') -ArgumentList ('"' + $file + '"')
    Write-Log "opened in notepad (line $line is not positioned there)"
  } else {
    Write-Log "file not found on disk: $file"
    exit 3
  }
}
exit 0
