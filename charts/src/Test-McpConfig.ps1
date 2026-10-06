<#
  Test-McpConfig.ps1 -- fast checks for Set-DragLintMcpConfig.ps1 (no index, no engine run).

  EVERY case runs against a TEMP COPY passed with -ConfigPath, and the engine / index paths
  are dummy files in that temp folder. Nothing here may touch ~\.claude.json or VS Code's
  mcp.json: the CLI case passes a FAKE claude (-ClaudeCli) that only logs its arguments.

  Exit 0 = all passed; 1 = failures (listed).
#>
[CmdletBinding()]
param([switch] $Quiet)

$ErrorActionPreference = 'Stop'
$fail = New-Object System.Collections.ArrayList
function Fail([string] $Code, [string] $Msg) { [void]$fail.Add("$Code -- $Msg") }
function Chk([string] $Code, $Actual, $Expected) { if ("$Actual" -cne "$Expected") { Fail $Code "expected '$Expected', got '$Actual'" } }
function Note([string] $s) { if (-not $Quiet) { Write-Host $s } }

$SCRIPT = Join-Path $PSScriptRoot 'Set-DragLintMcpConfig.ps1'
$tmp = Join-Path ([IO.Path]::GetTempPath()) ("mcpcfg-test-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Force $tmp | Out-Null
$eng = Join-Path $tmp 'drag-lint.exe';  [IO.File]::WriteAllText($eng, 'dummy')
$db1 = Join-Path $tmp 'One.sqlite';     [IO.File]::WriteAllText($db1, 'dummy')
$db2 = Join-Path $tmp 'Two.sqlite';     [IO.File]::WriteAllText($db2, 'dummy')

# the real files, fingerprinted before and after: the suite must leave them byte-identical
$real = @((Join-Path $HOME '.claude.json'), (Join-Path $env:APPDATA 'Code\User\mcp.json'))
$realBefore = @{}
foreach ($r in $real) { $realBefore[$r] = $(if (Test-Path -LiteralPath $r) { (Get-FileHash -LiteralPath $r).Hash } else { 'absent' }) }

# run the script; returns @{ Out = objects; Err = message or '' }
function Run([hashtable] $P) {
  $P = $P.Clone()
  if (-not $P.ContainsKey('Engine')) { $P.Engine = $eng }
  try { $o = & $SCRIPT @P 6>$null; [pscustomobject]@{ Out = @($o); Err = '' } }
  catch { [pscustomobject]@{ Out = @(); Err = $_.Exception.Message } }
}
function Baks([string] $Path) { @(Get-ChildItem -LiteralPath (Split-Path -Parent $Path) -Filter "$(Split-Path -Leaf $Path).bak-*" -ErrorAction SilentlyContinue) }
function J([string] $Path) { [IO.File]::ReadAllText($Path) | ConvertFrom-Json }
function NodeText([string] $Path, [string] $Key) {
  $n = [System.Text.Json.Nodes.JsonNode]::Parse([IO.File]::ReadAllText($Path))
  $n[$Key].ToJsonString()
}

try {
  # ---- T1 dry-run writes nothing: missing file stays missing, existing file is byte-identical
  Note 'T1 dry-run ...'
  $f1 = Join-Path $tmp 't1.json'
  $r = Run @{ VSCode = $true; ConfigPath = $f1; DbPath = $db1; DryRun = $true }
  Chk 'T1-ERR' $r.Err ''
  Chk 'T1-ACTION' $r.Out[0].Action 'would-added'
  if (Test-Path -LiteralPath $f1) { Fail 'T1-NOFILE' 'dry-run created the file' }
  [IO.File]::WriteAllText($f1, '{ "servers": { "other": { "command": "x.exe" } } }')
  $h1 = (Get-FileHash $f1).Hash; $m1 = (Get-Item $f1).LastWriteTimeUtc
  $r = Run @{ VSCode = $true; ConfigPath = $f1; DbPath = $db1; DryRun = $true }
  Chk 'T1-ACTION2' $r.Out[0].Action 'would-added'
  Chk 'T1-BYTES' (Get-FileHash $f1).Hash $h1
  Chk 'T1-MTIME' (Get-Item $f1).LastWriteTimeUtc $m1
  Chk 'T1-NOBAK' (Baks $f1).Count 0
  if ($r.Out[0].After -notmatch '"--db"') { Fail 'T1-AFTER' "dry-run did not print the entry it would write: $($r.Out[0].After)" }

  # ---- T2 add to an EMPTY (0-byte) file, and to a MISSING file
  Note 'T2 add to empty / missing ...'
  $f2 = Join-Path $tmp 't2.json'; [IO.File]::WriteAllText($f2, '')
  $r = Run @{ VSCode = $true; ConfigPath = $f2; DbPath = $db1 }
  Chk 'T2-ERR' $r.Err ''
  Chk 'T2-ACTION' $r.Out[0].Action 'added'
  $j = J $f2
  Chk 'T2-TYPE' $j.servers.'drag-lint'.type 'stdio'
  Chk 'T2-CMD'  $j.servers.'drag-lint'.command $eng
  Chk 'T2-ARGS' ($j.servers.'drag-lint'.args -join '|') "serve|--db|$db1"
  if ($j.servers.'drag-lint'.PSObject.Properties['env']) { Fail 'T2-NOENV' 'VS Code entry carries env (Claude Code shape)' }
  Chk 'T2-BAK' (Baks $f2).Count 1
  $f2b = Join-Path $tmp 't2-missing.json'
  $r = Run @{ ClaudeCode = $true; ConfigPath = $f2b }
  Chk 'T2b-ACTION' $r.Out[0].Action 'added'
  Chk 'T2b-MODE' $r.Out[0].Mode 'file'      # -ConfigPath without -ClaudeCli never runs the CLI (SAFETY 5)
  $j = J $f2b
  Chk 'T2b-ARGS' ($j.mcpServers.'drag-lint'.args -join '|') 'serve'
  if (-not $j.mcpServers.'drag-lint'.PSObject.Properties['env']) { Fail 'T2b-ENV' 'Claude Code entry has no env {}' }
  Chk 'T2b-NOBAK' (Baks $f2b).Count 0       # nothing existed to back up
  $bytes = [IO.File]::ReadAllBytes($f2b)
  if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB) { Fail 'T2b-BOM' 'written with a BOM' }

  # ---- T3 a file with OTHER servers and other keys: values carried through unchanged
  Note 'T3 merge preserves others ...'
  $f3 = Join-Path $tmp 't3.json'
  $orig = "{`n  `"numStartups`": 1.50,`n  `"big`": 12345678901234567890,`n  `"name`": `"caf\u00e9 <x>`",`n  `"mcpServers`": {`n    `"keep-me`": { `"type`": `"stdio`", `"command`": `"C:\\a b\\k.exe`", `"args`": [`"--x`", `"1`"], `"env`": { `"K`": `"v`" } }`n  },`n  `"projects`": { `"C:/p`": { `"allowedTools`": [], `"n`": 0.1e2 } }`n}`n"
  [IO.File]::WriteAllText($f3, $orig, [Text.UTF8Encoding]::new($false))
  $before = @{}; foreach ($k in 'numStartups', 'big', 'name', 'projects') { $before[$k] = NodeText $f3 $k }
  $keepBefore = ([System.Text.Json.Nodes.JsonNode]::Parse($orig))['mcpServers']['keep-me'].ToJsonString()
  $r = Run @{ ClaudeCode = $true; ConfigPath = $f3; DbPath = $db1 }
  Chk 'T3-ACTION' $r.Out[0].Action 'added'
  foreach ($k in 'numStartups', 'big', 'name', 'projects') { Chk "T3-KEEP-$k" (NodeText $f3 $k) $before[$k] }
  $after = [System.Text.Json.Nodes.JsonNode]::Parse([IO.File]::ReadAllText($f3))
  Chk 'T3-KEEP-SERVER' $after['mcpServers']['keep-me'].ToJsonString() $keepBefore
  $txt3 = [IO.File]::ReadAllText($f3)
  if ($txt3 -notmatch '"numStartups": 1\.50') { Fail 'T3-NUMTEXT' 'number text 1.50 was rewritten' }
  if ($txt3 -notmatch '12345678901234567890') { Fail 'T3-BIGINT' 'big integer was rewritten' }
  if ($txt3.Contains("`r`n")) { Fail 'T3-EOL' 'an LF file was rewritten with CRLF' }
  # T7 rides on T3: the backup is the ORIGINAL bytes
  $bk = Baks $f3
  Chk 'T7-BAKCOUNT' $bk.Count 1
  if ($bk.Count -eq 1) { Chk 'T7-BAKBYTES' ([IO.File]::ReadAllText($bk[0].FullName)) $orig }

  # ---- T4 idempotence: second run is "unchanged", writes nothing, makes no backup
  Note 'T4 idempotence ...'
  $h3 = (Get-FileHash $f3).Hash; $m3 = (Get-Item $f3).LastWriteTimeUtc
  Start-Sleep -Milliseconds 1100      # a second write would move the mtime
  $r = Run @{ ClaudeCode = $true; ConfigPath = $f3; DbPath = $db1 }
  Chk 'T4-ACTION' $r.Out[0].Action 'unchanged'
  Chk 'T4-BYTES' (Get-FileHash $f3).Hash $h3
  Chk 'T4-MTIME' (Get-Item $f3).LastWriteTimeUtc $m3
  Chk 'T4-BAKS' (Baks $f3).Count 1

  # ---- T5 update: a different -DbPath replaces command/args, keeps a key the user added to OUR entry
  Note 'T5 update ...'
  $n = [System.Text.Json.Nodes.JsonNode]::Parse([IO.File]::ReadAllText($f3))
  $n['mcpServers']['drag-lint']['env'] = [System.Text.Json.Nodes.JsonNode]::Parse('{"MINE":"1"}')
  [IO.File]::WriteAllText($f3, $n.ToJsonString(), [Text.UTF8Encoding]::new($false))
  Start-Sleep -Milliseconds 1100      # distinct backup name
  $r = Run @{ ClaudeCode = $true; ConfigPath = $f3; DbPath = $db2 }
  Chk 'T5-ACTION' $r.Out[0].Action 'updated'
  $j = J $f3
  Chk 'T5-ARGS' ($j.mcpServers.'drag-lint'.args -join '|') "serve|--db|$db2"
  Chk 'T5-USERENV' $j.mcpServers.'drag-lint'.env.MINE '1'
  Chk 'T5-OTHER' $j.mcpServers.'keep-me'.command 'C:\a b\k.exe'

  # ---- T6 remove: only our entry goes; a second remove is "absent" and writes nothing
  Note 'T6 remove ...'
  Start-Sleep -Milliseconds 1100
  $r = Run @{ ClaudeCode = $true; ConfigPath = $f3; Remove = $true }
  Chk 'T6-ACTION' $r.Out[0].Action 'removed'
  $j = J $f3
  if ($j.mcpServers.PSObject.Properties['drag-lint']) { Fail 'T6-GONE' 'entry still present' }
  Chk 'T6-OTHER' $j.mcpServers.'keep-me'.env.K 'v'
  Chk 'T6-TOP' (NodeText $f3 'projects') $before['projects']
  $h6 = (Get-FileHash $f3).Hash; $nb = (Baks $f3).Count
  $r = Run @{ ClaudeCode = $true; ConfigPath = $f3; Remove = $true }
  Chk 'T6-ABSENT' $r.Out[0].Action 'absent'
  Chk 'T6-BYTES' (Get-FileHash $f3).Hash $h6
  Chk 'T6-NOBAK' (Baks $f3).Count $nb

  # ---- T8 malformed JSON: refused with a clear message, nothing written, no backup
  Note 'T8 malformed ...'
  $f8 = Join-Path $tmp 't8.json'; [IO.File]::WriteAllText($f8, '{ "servers": { "a": 1, } ')
  $h8 = (Get-FileHash $f8).Hash
  $r = Run @{ VSCode = $true; ConfigPath = $f8 }
  if ($r.Err -notmatch 'is not valid JSON, so nothing was written') { Fail 'T8-MSG' "got: $($r.Err)" }
  Chk 'T8-BYTES' (Get-FileHash $f8).Hash $h8
  Chk 'T8-NOBAK' (Baks $f8).Count 0
  # comments parse leniently -- still refused (a rewrite would drop them), with the entry to paste
  $f8b = Join-Path $tmp 't8b.json'; [IO.File]::WriteAllText($f8b, "{`n  // mine`n  `"servers`": {}`n}")
  $h8b = (Get-FileHash $f8b).Hash
  $r = Run @{ VSCode = $true; ConfigPath = $f8b }
  if ($r.Err -notmatch 'comments or trailing commas' -or $r.Err -notmatch '"servers": \{ "drag-lint":') { Fail 'T8b-MSG' "got: $($r.Err)" }
  Chk 'T8b-BYTES' (Get-FileHash $f8b).Hash $h8b
  # a non-object container is refused too
  $f8c = Join-Path $tmp 't8c.json'; [IO.File]::WriteAllText($f8c, '{ "servers": [] }')
  $r = Run @{ VSCode = $true; ConfigPath = $f8c }
  if ($r.Err -notmatch '"servers" is not a JSON object') { Fail 'T8c-MSG' "got: $($r.Err)" }

  # ---- T9 CLI mode, through a FAKE claude that logs its arguments
  Note 'T9 CLI mode (fake claude) ...'
  $log = Join-Path $tmp 'claude-args.log'
  $fake = Join-Path $tmp 'fake-claude.ps1'
  [IO.File]::WriteAllText($fake, "Add-Content -LiteralPath '$log' -Value (`$args -join ' ')`r`nexit 0`r`n")
  $f9 = Join-Path $tmp 't9.json'; [IO.File]::WriteAllText($f9, '{ "mcpServers": {} }')
  $r = Run @{ ClaudeCode = $true; ConfigPath = $f9; ClaudeCli = $fake; DbPath = $db1; DryRun = $true }
  Chk 'T9-DRYMODE' $r.Out[0].Mode 'cli'
  if (Test-Path -LiteralPath $log) { Fail 'T9-DRYRUN' 'dry-run ran the CLI' }
  $r = Run @{ ClaudeCode = $true; ConfigPath = $f9; ClaudeCli = $fake; DbPath = $db1 }
  Chk 'T9-ERR' $r.Err ''
  Chk 'T9-ACTION' $r.Out[0].Action 'added'
  Chk 'T9-LOG' ((Get-Content -LiteralPath $log) -join '#') "mcp add --scope user drag-lint -- $eng serve --db $db1"
  Chk 'T9-BAK' (Baks $f9).Count 1
  # an existing different entry: remove then add
  [IO.File]::WriteAllText($f9, "{ `"mcpServers`": { `"drag-lint`": { `"type`": `"stdio`", `"command`": `"old.exe`", `"args`": [] } } }")
  Remove-Item -LiteralPath $log
  $r = Run @{ ClaudeCode = $true; ConfigPath = $f9; ClaudeCli = $fake; DbPath = $db1 }
  Chk 'T9-UPD' $r.Out[0].Action 'updated'
  Chk 'T9-UPDLOG' ((Get-Content -LiteralPath $log) -join '#') "mcp remove --scope user drag-lint#mcp add --scope user drag-lint -- $eng serve --db $db1"

  # ---- T10 refusals before any write
  Note 'T10 refusals ...'
  $r = Run @{ ConfigPath = $f9 }
  if ($r.Err -notmatch 'name a target') { Fail 'T10-NOTARGET' "got: $($r.Err)" }
  $r = Run @{ All = $true; ConfigPath = $f9 }
  if ($r.Err -notmatch 'exactly one of') { Fail 'T10-ALLPATH' "got: $($r.Err)" }
  $r = Run @{ VSCode = $true; ConfigPath = (Join-Path $tmp 't10.json'); DbPath = (Join-Path $tmp 'nope.sqlite') }
  if ($r.Err -notmatch 'does not exist') { Fail 'T10-NODB' "got: $($r.Err)" }
  if (Test-Path -LiteralPath (Join-Path $tmp 't10.json')) { Fail 'T10-NOFILE' 'a refused run wrote the file' }

  # ---- the script itself: 7-bit ASCII + CRLF
  foreach ($f in $SCRIPT, $PSCommandPath) {
    $t = [IO.File]::ReadAllText($f)
    if ([regex]::IsMatch($t, '[^\x09\x0A\x0D\x20-\x7E]')) { Fail 'E-CHARSET' "$f has non-ASCII bytes" }
    if ([regex]::IsMatch($t, "(?<!\r)\n")) { Fail 'E-EOL' "$f has bare LF" }
  }
} finally {
  foreach ($r in $real) {
    $now = $(if (Test-Path -LiteralPath $r) { (Get-FileHash -LiteralPath $r).Hash } else { 'absent' })
    # ~\.claude.json is rewritten by any running Claude Code session, so a change there is
    # reported, not blamed: the CLI case uses a fake and every case passes -ConfigPath.
    if ($now -ne $realBefore[$r]) { Note "  NOTE: $r changed during the run (a running client rewrites it; this suite never writes it)" }
  }
  Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
}

if ($fail.Count) {
  Write-Host "FAIL -- $($fail.Count) check(s):"
  foreach ($f in $fail) { Write-Host "  $f" }
  exit 1
}
Write-Host 'PASS -- Test-McpConfig: T1-T10 (dry-run, empty/missing, merge, backup, idempotence, update, remove, malformed/comments, CLI via fake, refusals)'
exit 0
