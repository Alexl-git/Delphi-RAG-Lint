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
      (an NTFS stream `a.exe:b.pas` reads like a .pas), no segment ending in a dot or a
      space (Windows strips them: `x.hta.` IS x.hta), no reserved device name. A drive
      letter does not prove the file is local -- a mapped or subst'ed drive can be SMB or
      WebDAV -- so this reaches only servers the user has ALREADY mapped, never one a
      link names;
    * an allow-listed SOURCE extension: .pas .dfm .dpr .inc .sql .fmx. Never a project or
      package file (.dproj/.groupproj/.dpk: a link must not make the IDE load a project or
      a package; ruling SEC-R3). .dpr stays: charts anchor project sources, and opening one
      shows it -- nothing builds;
    * line and col are ASCII digits (`[0-9]`, not `\d`, which takes any Unicode digit).
      line=0 (a chart's focus box) and a missing line open at 1;
    * every key at most once: a duplicate `file=` or `line=` is refused, never "last wins".
  IDE not running: the file opens in NOTEPAD, never by ShellExecute of its default verb.
  The default verb of an allow-listed extension is still whatever the machine associates
  with it (an IDE that loads the file's project, a SQL tool that connects); notepad only
  displays text, and a click still shows the code. The line is not positioned there.

  ONE ARGUMENT, NOTHING ELSE (ruling SEC-R2, fix round 2). The registry runs
  `... -File "<this file>" "%1"` with %1 substituted RAW; a launcher that does not
  percent-encode `"` (a .url file, an Office or PDF hyperlink, a chat app, `start`) can
  close the quote and append `-LogPath "<Startup>\a.cmd"`. So this script declares NO
  parameters: whatever arrives lands in $args, and anything but exactly one argument that
  starts with `draglint:` is refused (exit 2, logged). The log path is FIXED:
  %LOCALAPPDATA%\drag-lint\uri-handler.log, whose folder is the only one ever created.
  Test overrides come ONLY from the environment, never from the command line or the URI:
    DRAGLINT_URI_TEST_WHATIF=1   validate + report an object; never the pipe, never a process
    DRAGLINT_URI_TEST_LOG=<file> log there instead (its folder is NOT created)
    DRAGLINT_URI_TEST_TIMEOUT=<ms> pipe connect timeout (default 1000)

  Dot-sourcing this file (`. .\Open-DragLintUri.ps1`) defines Test-DragLintTarget and does
  nothing else, so the validation is testable without launching anything
  (Test-DragLintProtocol.ps1). Parses and runs under Windows PowerShell 5.1 as well as pwsh 7.
#>

$ErrorActionPreference = 'Stop'
$argv = @($args)

# The whole verdict on one (file, line, col) triple, already URL-decoded. Returns
# Ok/Reason/File/Line/Col; never touches the file system.
function Test-DragLintTarget([string] $File, [string] $Line, [string] $Col) {
  $no = { param($why) [pscustomobject]@{ Ok = $false; Reason = $why; File = $File; Line = 0; Col = '' } }
  if ([string]::IsNullOrEmpty($File))    { return (& $no 'no file= in uri') }
  if ($File -match '[\x00-\x1F\x7F]')    { return (& $no 'control character in file') }
  if ("$Line" -match '[\x00-\x1F\x7F]')  { return (& $no 'control character in line') }
  if ("$Col" -match '[\x00-\x1F\x7F]')   { return (& $no 'control character in col') }
  if ($File -match '^[\\/][\\/]')        { return (& $no 'network or device path') }
  # CASE-SENSITIVE on purpose (fix round 3, SEC-R4): -match folds U+212A (Kelvin) to k and U+0130 to i
  if ($File -cnotmatch '^[A-Za-z]:\\')   { return (& $no 'not a local drive path') }
  if ($File.Substring(2) -match '[:*?"<>|/]') { return (& $no 'illegal character in path') }
  # Windows also reserves COM/LPT followed by a SUPERSCRIPT 1, 2 or 3 (U+00B9, U+00B2, U+00B3), and
  # CONIN$ / CONOUT$. Written as [char] codes: this file stays 7-bit ASCII.
  $sup = [string][char]0x00B9 + [char]0x00B2 + [char]0x00B3
  $dev = '^(CON|PRN|AUX|NUL|CONIN\$|CONOUT\$|COM[0-9' + $sup + ']|LPT[0-9' + $sup + '])$'
  foreach ($seg in $File.Substring(3).Split('\')) {
    if ($seg -match '[. ]$') { return (& $no 'trailing dot or space') }
    if ((($seg -split '\.')[0]).TrimEnd(' ') -match $dev) { return (& $no 'reserved device name') }
  }
  # ordinal after lowering: a case-insensitive -contains could fold `.pa<U+017F>` (long s) into `.pas`
  $ext = [IO.Path]::GetExtension($File).ToLowerInvariant()
  if (@('.pas', '.dfm', '.dpr', '.inc', '.sql', '.fmx') -cnotcontains $ext) {
    return (& $no ('extension not allowed: ' + $(if ($ext) { $ext -replace '[^\x20-\x7E]', '?' } else { '(none)' })))
  }
  $n = 1
  if (-not [string]::IsNullOrEmpty($Line)) {
    if ($Line -notmatch '^[0-9]{1,9}$') { return (& $no 'line is not a number') }
    $n = [Math]::Max(1, [int]$Line)
  }
  if (-not [string]::IsNullOrEmpty($Col) -and $Col -notmatch '^[0-9]{1,9}$') { return (& $no 'col is not a number') }
  [pscustomobject]@{ Ok = $true; Reason = ''; File = $File; Line = $n; Col = "$Col" }
}

if ($MyInvocation.InvocationName -eq '.') { return }

# ---- the environment is the only override channel (SEC-R2) -------------------------
$WhatIfOnly = ($env:DRAGLINT_URI_TEST_WHATIF -eq '1')
$TimeoutMs  = $(if ("$env:DRAGLINT_URI_TEST_TIMEOUT" -match '^[0-9]{1,6}$') { [int]$env:DRAGLINT_URI_TEST_TIMEOUT } else { 1000 })
$LogDir     = $(if ($env:LOCALAPPDATA) { Join-Path $env:LOCALAPPDATA 'drag-lint' } else { '' })
$LogPath    = $(if ($env:DRAGLINT_URI_TEST_LOG) { $env:DRAGLINT_URI_TEST_LOG } elseif ($LogDir) { Join-Path $LogDir 'uri-handler.log' } else { '' })

function Write-Log([string] $m) {
  # the URI is attacker text: capped at 512 chars (fix round 3, SEC-R4: a 30 KB line per click was
  # observed) and no control character reaches the log
  if ($m.Length -gt 512) { $m = $m.Substring(0, 512) + "...(+$($m.Length - 512) chars)" }
  $entry = "{0}  {1}" -f (Get-Date).ToString('s'), ($m -replace '[\x00-\x1F\x7F]', '?')
  if (-not $LogPath) { return }
  try {
    # the ONE folder this script ever creates is its own fixed log folder
    if (-not $env:DRAGLINT_URI_TEST_LOG -and -not (Test-Path -LiteralPath $LogDir)) { New-Item -ItemType Directory -Force -Path $LogDir | Out-Null }
    Add-Content -LiteralPath $LogPath -Value $entry -Encoding utf8
  } catch { }
}
function Stop-Rejected([string] $Why, [string] $File = '') {
  Write-Log "rejected: $Why"
  if ($WhatIfOnly) { [pscustomobject]@{ Ok = $false; Reason = $Why; File = $File; Line = 0; Col = ''; Payload = '' } }
  exit 2
}

# exactly one argument, and it is the URI -- before anything else is looked at
if ($argv.Count -ne 1) {
  Write-Log ("args: " + (($argv | ForEach-Object { "[$_]" }) -join ' '))
  Stop-Rejected "expected exactly one argument, the draglint:// uri (got $($argv.Count))"
}
$Uri = [string]$argv[0]
if ([string]::IsNullOrWhiteSpace($Uri)) { Stop-Rejected 'no uri given' }
Write-Log "uri: $Uri"

# Browsers hand the whole URI as one argument and may append a trailing slash.
$u = $Uri.Trim().TrimEnd('/')
if ($u -notmatch '^draglint://') { Stop-Rejected 'not a draglint uri' }

$q = $u -replace '^draglint://[^?]*\??', ''
$parts = @{}
foreach ($kv in ($q -split '&')) {
  $i = $kv.IndexOf('=')
  if ($i -le 0) { continue }
  $key = $kv.Substring(0, $i).ToLower()
  # every key at most once: "last wins" would validate one value and a reader might see another
  if ($parts.ContainsKey($key)) { Stop-Rejected "duplicate $key= in uri" }
  $parts[$key] = [uri]::UnescapeDataString($kv.Substring($i + 1))
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
