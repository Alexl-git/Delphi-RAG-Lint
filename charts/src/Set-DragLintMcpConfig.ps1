<#
  Set-DragLintMcpConfig.ps1 -- registers drag-lint's MCP server (`drag-lint serve`) with
  MCP clients. Ships with the installer, which calls it with -All as an OPTIONAL task.

  Targets (one switch each, or -All):
    -ClaudeCode   Claude Code, USER scope: the top-level "mcpServers" object of
                  ~\.claude.json ($env:CLAUDE_CONFIG_DIR\.claude.json when that is set).
                  The `claude mcp` CLI is PREFERRED when it is on PATH (see SAFETY 5);
                  otherwise the file is edited.
    -VSCode       VS Code, user level: the "servers" object of %APPDATA%\Code\User\mcp.json
                  (the dedicated MCP file VS Code reads since MCP went GA; the older
                  settings.json "mcp.servers" key is migrated by VS Code itself and is not
                  written here).

  The entry written (name -Name, default "drag-lint"):
    Claude Code  { "type": "stdio", "command": "<engine>", "args": [...], "env": {} }
    VS Code      { "type": "stdio", "command": "<engine>", "args": [...] }
  args = ["serve", "--db", "<-DbPath>"] when -DbPath is given (one MCP entry = one index: `serve`
  answers from its FIRST --db only), else ["serve"] -- the engine then resolves the index
  from its manifest when the client starts it. The engine is Resolve-DragLintEngine's
  answer (Emit-Common.ps1: -Engine > DRAGLINT_ENGINE > settings.json > beside the
  scripts > <app>\bin > shared > repo), always a FULL path.

  SAFETY -- this edits a real user's configuration, so:
    1. -DryRun prints the exact change (the entry before and after, the file and the
       backup it would write, or the exact CLI commands) and writes NOTHING.
    2. A real write first copies the file to <file>.bak-<yyyyMMdd-HHmmss>, then writes a
       temp file beside it and moves it into place. The file is re-checked just before
       the move: if it changed since it was read (a running client rewrote it), nothing
       is written and the run says so.
    3. It MERGES: only the one entry named -Name is added, updated or (with -Remove)
       deleted. Every other key and every other server stays; values are carried through
       System.Text.Json unchanged (numbers keep their text, strings their value).
    4. It is IDEMPOTENT: an entry whose type/command/args already match is "unchanged",
       nothing is written and no backup is made. Keys a user added to OUR entry (env, ...)
       are kept on an update.
    5. The claude CLI is only ever run for the DEFAULT config file. With -ConfigPath it is
       never run unless -ClaudeCli names one explicitly (tests pass a fake), so a test
       pointed at a temp copy can never reach the real ~\.claude.json through the CLI.
    6. A file that does not parse is REFUSED with the parser's position, and nothing is
       written. A file that parses only with comments or trailing commas allowed is
       refused too -- a rewrite would silently drop the comments; the entry to paste by
       hand is printed instead. An empty file counts as {}.
  JSON is written as UTF-8 without BOM, keeping the file's own line-ending style.

  -ConfigPath points ONE target at another file (tests use temp copies; never the real
  ones). Output: one object per target -- Target, Path, Mode (file|cli), Action
  (added|updated|unchanged|removed|absent, prefixed would- under -DryRun; skipped when a
  -All target's client is not installed), Backup, Before, After, Commands.

  Examples:
    pwsh -NoProfile -File Set-DragLintMcpConfig.ps1 -All -DryRun
    pwsh -NoProfile -File Set-DragLintMcpConfig.ps1 -ClaudeCode -DbPath C:\Projects\MyApp\_D-RAG\MyApp.sqlite
    pwsh -NoProfile -File Set-DragLintMcpConfig.ps1 -All -Remove
#>
[CmdletBinding()]
param(
  [switch] $ClaudeCode,
  [switch] $VSCode,
  [switch] $All,
  [switch] $Remove,
  [switch] $DryRun,
  [string] $Name       = 'drag-lint',
  [string] $DbPath     = '',   # NOT -Db: CmdletBinding aliases that to -Debug
  # '' = Resolve-DragLintEngine (Emit-Common.ps1)
  [string] $Engine     = '',
  # one target only: the file to read/write instead of the client's own
  [string] $ConfigPath = '',
  # '' = `claude` on PATH, used ONLY for the default Claude Code file (SAFETY 5)
  [string] $ClaudeCli  = '',
  [switch] $NoCli
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Emit-Common.ps1')   # functions only; Resolve-DragLintEngine

# ---- the request ---------------------------------------------------------------
$targets = @()
if ($ClaudeCode -or $All) { $targets += 'ClaudeCode' }
if ($VSCode -or $All)     { $targets += 'VSCode' }
if ($targets.Count -eq 0) { throw 'name a target: -ClaudeCode, -VSCode or -All' }
if ($ConfigPath -and $targets.Count -ne 1) { throw '-ConfigPath names ONE file, so pass exactly one of -ClaudeCode / -VSCode with it' }
if ([string]::IsNullOrWhiteSpace($Name) -or $Name -notmatch '^[A-Za-z0-9_.-]+$') { throw "-Name '$Name' must be letters, digits, '_', '.' or '-'" }

$args2 = @('serve')
if (-not $Remove) {
  $Engine = Resolve-DragLintEngine $Engine
  if ($DbPath) {
    $dbFull = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($DbPath)
    if (-not (Test-Path -LiteralPath $dbFull -PathType Leaf)) { throw "-DbPath $DbPath does not exist ($dbFull) -- serve refuses a missing index, so the entry would never start" }
    $args2 += @('--db', $dbFull)
  }
}

# ---- JSON helpers (System.Text.Json: values pass through unchanged) -------------
$strictOpts  = [System.Text.Json.JsonDocumentOptions]@{ CommentHandling = 'Disallow'; AllowTrailingCommas = $false }
$lenientOpts = [System.Text.Json.JsonDocumentOptions]@{ CommentHandling = 'Skip'; AllowTrailingCommas = $true }

function Read-ConfigJson([string] $Path, [string] $PasteHint) {
  if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
    return [pscustomobject]@{ Exists = $false; Text = ''; Root = [System.Text.Json.Nodes.JsonObject]::new(); Stamp = $null; NewLine = "`r`n" }
  }
  $item = Get-Item -LiteralPath $Path
  $text = [IO.File]::ReadAllText($Path)
  $nl = $(if ($text.Contains("`r`n") -or -not $text.Contains("`n")) { "`r`n" } else { "`n" })
  if ([string]::IsNullOrWhiteSpace($text.TrimStart([char]0xFEFF))) {
    return [pscustomobject]@{ Exists = $true; Text = $text; Root = [System.Text.Json.Nodes.JsonObject]::new(); Stamp = $item.LastWriteTimeUtc; NewLine = $nl }
  }
  try { $root = [System.Text.Json.Nodes.JsonNode]::Parse($text, $null, $strictOpts) }
  catch {
    $why = $_.Exception.InnerException.Message
    if (-not $why) { $why = $_.Exception.Message }
    $lenientOk = $true
    try { [void][System.Text.Json.Nodes.JsonNode]::Parse($text, $null, $lenientOpts) } catch { $lenientOk = $false }
    if ($lenientOk) {
      throw ("refusing $Path -- it holds comments or trailing commas, and rewriting it would silently drop them. " +
             "Nothing was written. Add this entry by hand instead:`n$PasteHint")
    }
    throw "refusing $Path -- it is not valid JSON, so nothing was written: $why"
  }
  if ($root -isnot [System.Text.Json.Nodes.JsonObject]) { throw "refusing $Path -- its top level is not a JSON object, so nothing was written" }
  [pscustomobject]@{ Exists = $true; Text = $text; Root = $root; Stamp = $item.LastWriteTimeUtc; NewLine = $nl }
}

function ConvertTo-ConfigText($Root, [string] $NewLine) {
  $o = [System.Text.Json.JsonSerializerOptions]::new()
  $o.WriteIndented = $true
  $o.NewLine = $NewLine
  $o.Encoder = [System.Text.Encodings.Web.JavaScriptEncoder]::UnsafeRelaxedJsonEscaping
  $Root.ToJsonString($o) + $NewLine
}

function Get-Member2($Obj, [string] $Key) {
  $v = $null
  if ($Obj.TryGetPropertyValue($Key, [ref]$v)) { return , $v }
  $null
}

# the part of an entry that decides "same server": type (absent = stdio), command, args
function Test-SameEntry($Node, [string] $Command, [string[]] $ArgList) {
  if ($null -eq $Node -or $Node -isnot [System.Text.Json.Nodes.JsonObject]) { return $false }
  $e = $Node.ToJsonString() | ConvertFrom-Json -NoEnumerate
  $type = $(if ($e.PSObject.Properties['type']) { [string]$e.type } else { 'stdio' })
  if ($type -ne 'stdio') { return $false }
  if (-not [string]::Equals([string]$e.command, $Command, [StringComparison]::OrdinalIgnoreCase)) { return $false }
  $have = @($(if ($e.PSObject.Properties['args']) { $e.args }) | ForEach-Object { [string]$_ })
  if ($have.Count -ne $ArgList.Count) { return $false }
  for ($i = 0; $i -lt $have.Count; $i++) { if ($have[$i] -cne $ArgList[$i]) { return $false } }
  $true
}

function New-EntryNode([string] $Target) {
  $h = [ordered]@{ type = 'stdio'; command = $Engine; args = @($args2) }
  if ($Target -eq 'ClaudeCode') { $h.env = @{} }
  # the unary comma: a JsonObject is IEnumerable, and a bare return would be enumerated into its pairs
  , [System.Text.Json.Nodes.JsonNode]::Parse(($h | ConvertTo-Json -Depth 5 -Compress))
}

function Get-NodeText($Node) {
  if ($null -eq $Node) { return '(none)' }
  $o = [System.Text.Json.JsonSerializerOptions]::new()
  $o.Encoder = [System.Text.Encodings.Web.JavaScriptEncoder]::UnsafeRelaxedJsonEscaping
  $Node.ToJsonString($o)
}

function Get-BackupPath([string] $Path) {
  $b = "$Path.bak-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
  if (Test-Path -LiteralPath $b) { $b = "$Path.bak-$(Get-Date -Format 'yyyyMMdd-HHmmss-fff')" }
  $b
}

# ---- one target ------------------------------------------------------------------
function Invoke-Target([string] $Target) {
  $isClaude  = $Target -eq 'ClaudeCode'
  $container = $(if ($isClaude) { 'mcpServers' } else { 'servers' })
  $default   = $(if ($isClaude) {
                   Join-Path $(if ($env:CLAUDE_CONFIG_DIR) { $env:CLAUDE_CONFIG_DIR } else { $HOME }) '.claude.json'
                 } else { Join-Path $env:APPDATA 'Code\User\mcp.json' })
  $path = $(if ($ConfigPath) { $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($ConfigPath) } else { $default })
  $res = [ordered]@{ Target = $Target; Path = $path; Mode = 'file'; Action = ''; Backup = ''; Before = ''; After = ''; Commands = @() }

  # a client that is not installed is skipped under -All, refused when asked for by name
  $dir = Split-Path -Parent $path
  if (-not $ConfigPath -and -not (Test-Path -LiteralPath $dir -PathType Container) -and -not (Test-Path -LiteralPath $path)) {
    if ($All) { $res.Action = 'skipped'; Write-Host "$Target -- skipped: $dir not found (client not installed)"; return [pscustomobject]$res }
    throw "$Target -- $dir not found; is the client installed? (pass -ConfigPath to name the file)"
  }

  $want = $null; if (-not $Remove) { $want = New-EntryNode $Target }
  $hint = "  `"$container`": { `"$Name`": $(Get-NodeText $want) }"
  $cfg  = Read-ConfigJson $path $hint
  $box  = Get-Member2 $cfg.Root $container
  if ($null -ne $box -and $box -isnot [System.Text.Json.Nodes.JsonObject]) { throw "refusing $path -- `"$container`" is not a JSON object, so nothing was written" }
  $have = $null; if ($null -ne $box) { $have = Get-Member2 $box $Name }
  $res.Before = Get-NodeText $have

  if ($Remove) {
    if ($null -eq $have) { $verb = 'absent' } else { $verb = 'removed' }
  } elseif ($null -eq $have) { $verb = 'added' }
  elseif (Test-SameEntry $have $Engine $args2) { $verb = 'unchanged' }
  else { $verb = 'updated' }

  # the new entry: an update keeps keys the user added to OUR entry (env, ...)
  $newNode = $null
  if ($verb -eq 'added') { $newNode = $want }
  elseif ($verb -eq 'updated') {
    $newNode = [System.Text.Json.Nodes.JsonNode]::Parse($have.ToJsonString())
    if ($newNode -isnot [System.Text.Json.Nodes.JsonObject]) { $newNode = $want }
    else { foreach ($k in 'type', 'command', 'args') { $newNode[$k] = (Get-Member2 $want $k).DeepClone() } }
  }
  $res.After = $(if ($verb -in 'removed', 'absent') { '(none)' } elseif ($verb -eq 'unchanged') { $res.Before } else { Get-NodeText $newNode })

  if ($verb -in 'unchanged', 'absent') {
    $res.Action = $(if ($DryRun) { "would-$verb" } else { $verb })
    Write-Host ("$Target -- $Name is $(if ($verb -eq 'absent') { 'not there; nothing to remove' } else { 'already registered as asked; no change' }) ($path)")
    return [pscustomobject]$res
  }

  # ---- CLI (Claude Code, default file only -- SAFETY 5) -------------------------
  $cli = ''
  if ($isClaude -and -not $NoCli) {
    if ($ClaudeCli) { $cli = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($ClaudeCli) }
    elseif (-not $ConfigPath) {
      $c = @(Get-Command 'claude' -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1)
      if ($c.Count) { $cli = $c[0].Source }
    }
  }
  $backup = $(if ($cfg.Exists) { Get-BackupPath $path } else { '' })
  if ($cli) {
    $res.Mode = 'cli'
    $cmds = New-Object System.Collections.Generic.List[object]
    if ($verb -in 'updated', 'removed') { $cmds.Add(@('mcp', 'remove', '--scope', 'user', $Name)) }
    if ($verb -in 'added', 'updated')   { $cmds.Add(@('mcp', 'add', '--scope', 'user', $Name, '--', $Engine) + $args2) }
    $res.Commands = @($cmds | ForEach-Object { "`"$cli`" " + (($_ | ForEach-Object { if ($_ -match '[\s"]') { '"' + $_ + '"' } else { $_ } }) -join ' ') })
    if ($DryRun) {
      $res.Action = "would-$verb"
      Write-Host "$Target -- would $($verb -replace 'ed$', '') $Name via the claude CLI (backup $(if ($backup) { $backup } else { 'none: no file yet' })):"
      foreach ($c in $res.Commands) { Write-Host "  $c" }
      Write-Host "  before: $($res.Before)"; Write-Host "  after:  $($res.After)"
      return [pscustomobject]$res
    }
    if ($backup) { [IO.File]::Copy($path, $backup, $false); $res.Backup = $backup }
    foreach ($c in $cmds) {
      $out = & $cli @c 2>&1
      if ($LASTEXITCODE -ne 0) { throw "$Target -- claude $($c -join ' ') failed (exit $LASTEXITCODE): $(@($out) -join ' | ')$(if ($backup) { " -- the file before this run is at $backup" })" }
    }
    $res.Action = $verb
    Write-Host "$Target -- $verb $Name via the claude CLI$(if ($backup) { " (backup $backup)" })"
    return [pscustomobject]$res
  }

  # ---- file edit -------------------------------------------------------------------
  if ($verb -eq 'removed') { [void]$box.Remove($Name) }
  else {
    if ($null -eq $box) { $box = [System.Text.Json.Nodes.JsonObject]::new(); $cfg.Root[$container] = $box }
    $box[$Name] = $newNode
  }
  $text = ConvertTo-ConfigText $cfg.Root $cfg.NewLine
  if ($DryRun) {
    $res.Action = "would-$verb"
    Write-Host "$Target -- would $($verb -replace 'ed$', '') `"$container`".`"$Name`" in $path"
    Write-Host "  before: $($res.Before)"; Write-Host "  after:  $($res.After)"
    Write-Host "  would write $path ($([Text.Encoding]::UTF8.GetByteCount($text)) bytes, UTF-8 no BOM); backup $(if ($backup) { $backup } else { 'none: no file yet' })"
    return [pscustomobject]$res
  }
  if ($cfg.Exists) {
    $now = (Get-Item -LiteralPath $path).LastWriteTimeUtc
    if ($now -ne $cfg.Stamp -or [IO.File]::ReadAllText($path) -cne $cfg.Text) { throw "$path changed while this ran (a running client rewrote it?) -- nothing was written; run again" }
    [IO.File]::Copy($path, $backup, $false); $res.Backup = $backup
  } elseif (-not (Test-Path -LiteralPath $dir -PathType Container)) {
    New-Item -ItemType Directory -Force $dir | Out-Null
  }
  $tmp = "$path.tmp-$PID"
  [IO.File]::WriteAllText($tmp, $text, [Text.UTF8Encoding]::new($false))
  [IO.File]::Move($tmp, $path, $true)
  $res.Action = $verb
  Write-Host "$Target -- $verb `"$container`".`"$Name`" in $path$(if ($backup) { " (backup $backup)" })"
  [pscustomobject]$res
}

foreach ($t in $targets) { Invoke-Target $t }
