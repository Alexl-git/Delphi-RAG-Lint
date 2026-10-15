<#
  run_mcp_config_verb.ps1 -- `drag-lint mcp-config`, the verb that replaces
  charts\src\Set-DragLintMcpConfig.ps1, run ONLY against scratch copies.

  THE REAL FILES ARE NEVER TOUCHED. Every engine run goes through Invoke-McpConfig, which refuses
  to start unless the command line carries --config-path, or BOTH --home-dir and --appdata-dir
  pointed into the scratch folder; CLAUDE_CONFIG_DIR is removed from this process for the whole run
  (the verb would otherwise prefer it to --home-dir) and only ever set to a scratch folder. The real
  %USERPROFILE%\.claude.json and %APPDATA%\Code\User\mcp.json are fingerprinted before and after:
  mcp.json must be byte-identical (or absent both times). ~\.claude.json is rewritten by every
  running Claude Code session, this one included, so a byte change there is not by itself this
  suite's doing: it must then still carry an IDENTICAL "mcpServers" object, and no .bak-* / .tmp-*
  file may have appeared beside either real file.

  Env VALUES are secrets: the seeded API_KEY value must never reach stdout or stderr (text, --json,
  --dry-run) while the key and *** do.

  Cases (each also runs Set-DragLintMcpConfig.ps1 in its FILE-EDIT mode -- -ConfigPath / -HomeDir /
  -AppDataDir plus -NoCli, so the script never looks for or runs `claude` -- on a second copy and
  asserts the same Action word and the same parsed tree: PARITY, transitional while the script
  exists; numbers compare as their text):
    MC-USAGE      no target / unknown flag / flag without value / --all with --config-path / bad
                  --name: usage on stderr, exit 2
    MC-NODB       --db that does not exist: exit 2, nothing written
    MC-ADD-MISS   add to a missing file (VS Code, --db): added, no backup, no BOM, expected tree
    MC-ADD-EMPTY  add to {} (Claude Code): added, env {}, backup == input bytes, expected tree
    MC-ADD-BLANK  add to a 0-byte file: added
    MC-BESIDE     add beside another server: the other server, the numbers' text (1.50, a 20-digit
                  integer) and the LF style kept; backup == input bytes; no .tmp- left; expected tree
    MC-UNCHANGED  second run: unchanged, bytes + mtime same, no new backup
    MC-DRYRUN     --dry-run: would-added, nothing written, no backup
    MC-UPDATE     an entry with a user env + extra key: updated, both kept, args replaced; Before /
                  After show "API_KEY":"***"; the secret is absent from stdout/stderr in text,
                  --json and --dry-run runs; expected tree
    MC-REMOVE     remove: only our entry goes (tree == the input fixture); then MC-ABSENT: absent,
                  no write, no backup
    MC-NOTOURS    an entry running other.exe: update and remove both refused (exit 1), bytes same,
                  no backup
    MC-COMMENTS   // comment: refused with the paste hint; MC-TRAILING trailing commas: same message;
    MC-INVALID    not JSON: "is not valid JSON"; MC-CONTAINER "servers": []; MC-TOPARRAY []:
                  all exit 1, bytes same, no backup
    MC-EOL        a CRLF file stays CRLF (no bare LF); an LF file stays LF (in MC-BESIDE)
    MC-BOM        BOM input: the rewrite carries no BOM
    MC-ALL-SKIP   --all, neither client installed (scratch home/appdata): both skipped, exit 0,
                  nothing created; --claude-code by name: exit 2
    MC-DOTCLAUDE  <home>\.claude exists: --all adds Claude Code at <home>\.claude.json, VS Code
                  skipped; MC-CCD CLAUDE_CONFIG_DIR (scratch) wins over --home-dir
    MC-ENGINE     no --engine: the command is the running exe's full path
    MC-JSON       --json: one array, one object per target, the documented fields
    MC-REAL       the real files (see above)

  Exit: 0 all PASS, 1 any FAIL, 2 setup.
#>
[CmdletBinding()]
param(
  [string]$Exe    = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe",
  [string]$Script = "$PSScriptRoot\..\..\charts\src\Set-DragLintMcpConfig.ps1",
  [string]$Fixtures = "$PSScriptRoot\..\fixtures\mcp-config"
)
$ErrorActionPreference = 'Stop'
$script:Failed = $false
function Check($n, $ok, $d = '') {
  $s = if ($ok) { 'PASS' } else { 'FAIL' }
  $c = if ($ok) { 'Green' } else { 'Red' }
  Write-Host ("  [{0}] {1} {2}" -f $s, $n, $d) -ForegroundColor $c
  if (-not $ok) { $script:Failed = $true }
}

foreach ($p in @($Exe, $Fixtures)) {
  if (-not (Test-Path -LiteralPath $p)) { Write-Host "SETUP: not found: $p" -ForegroundColor Red; exit 2 }
}
$Exe      = (Resolve-Path -LiteralPath $Exe).ProviderPath
$Fixtures = (Resolve-Path -LiteralPath $Fixtures).ProviderPath
$HaveScript = Test-Path -LiteralPath $Script
if ($HaveScript) { $Script = (Resolve-Path -LiteralPath $Script).ProviderPath }

$Secret = 'S3cr3t-Value-MCV'
$stamp  = '{0}-{1}' -f (Get-Date -Format 'yyyyMMddHHmmss'), $PID
$Work   = Join-Path ([IO.Path]::GetTempPath()) "drag-lint-mcp-config-guard-$stamp"
$Bin    = Join-Path $Work 'bin'
$EDir   = Join-Path $Work 'e'      # the engine's copies
$SDir   = Join-Path $Work 's'      # the script's copies (parity)
New-Item -ItemType Directory -Force $Bin, $EDir, $SDir | Out-Null
$Eng = Join-Path $Bin 'drag-lint.exe'; [IO.File]::WriteAllText($Eng, 'dummy')
$Db1 = Join-Path $Bin 'One.sqlite';    [IO.File]::WriteAllText($Db1, 'dummy')
$Db2 = Join-Path $Bin 'Two.sqlite';    [IO.File]::WriteAllText($Db2, 'dummy')

# ---- the real files: fingerprint now, compare in finally ------------------------------------
$RealClaude = Join-Path $env:USERPROFILE '.claude.json'
$RealVSCode = Join-Path $env:APPDATA 'Code\User\mcp.json'
function Get-Print([string]$Path) {
  if (-not (Test-Path -LiteralPath $Path)) { return 'absent' }
  (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash
}
function Get-Siblings([string]$Path) {
  $dir = Split-Path -Parent $Path
  if (-not (Test-Path -LiteralPath $dir)) { return @() }
  $leaf = Split-Path -Leaf $Path
  @(Get-ChildItem -LiteralPath $dir -File -ErrorAction SilentlyContinue |
      Where-Object { $_.Name -like "$leaf.bak-*" -or $_.Name -like "$leaf.tmp-*" } | ForEach-Object Name) | Sort-Object
}
function Get-ServersText([string]$Path) {
  if (-not (Test-Path -LiteralPath $Path)) { return 'absent' }
  try {
    $n = [System.Text.Json.Nodes.JsonNode]::Parse([IO.File]::ReadAllText($Path))
    $s = $n['mcpServers']
    if ($null -eq $s) { 'none' } else { $s.ToJsonString() }
  } catch { 'unparsable' }
}
$RealBefore = @{
  ClaudePrint = Get-Print $RealClaude; ClaudeServers = Get-ServersText $RealClaude
  VSCodePrint = Get-Print $RealVSCode
  ClaudeSibs  = (Get-Siblings $RealClaude) -join '|'; VSCodeSibs = (Get-Siblings $RealVSCode) -join '|'
}
$PrevCcd = $env:CLAUDE_CONFIG_DIR
Remove-Item Env:\CLAUDE_CONFIG_DIR -ErrorAction SilentlyContinue

# ---- runners ---------------------------------------------------------------------------------
# The engine. Refuses any command line that could reach a default (real) file.
function Invoke-McpConfig([string[]]$A) {
  $hasPath = $A -contains '--config-path'
  $hasDirs = ($A -contains '--home-dir') -and ($A -contains '--appdata-dir')
  $usage   = ($A | Where-Object { $_ -in '--claude-code', '--vscode', '--all' }).Count -eq 0 -or ($A -contains '--bogus')
  if (-not ($hasPath -or $hasDirs -or $usage)) { throw "GUARD BUG: engine run without --config-path or scratch dirs: $($A -join ' ')" }
  foreach ($flag in '--config-path', '--home-dir', '--appdata-dir') {
    $i = [array]::IndexOf($A, $flag)
    if ($i -ge 0 -and -not ([IO.Path]::GetFullPath($A[$i + 1]).StartsWith($Work, [StringComparison]::OrdinalIgnoreCase))) {
      throw "GUARD BUG: $flag outside the scratch folder: $($A[$i + 1])"
    }
  }
  if ($env:CLAUDE_CONFIG_DIR -and -not $env:CLAUDE_CONFIG_DIR.StartsWith($Work, [StringComparison]::OrdinalIgnoreCase)) {
    throw "GUARD BUG: CLAUDE_CONFIG_DIR points outside the scratch folder"
  }
  $errFile = Join-Path $Work 'stderr.txt'
  $out = & $Exe mcp-config @A 2> $errFile
  $code = $LASTEXITCODE
  [pscustomobject]@{ Code = $code; Out = (@($out) -join "`n"); Err = [IO.File]::ReadAllText($errFile) }
}
# The engine's text block for one target -> Action of the first (or the named) block
function Get-Actions([string]$Out) {
  @([regex]::Matches($Out, '(?m)^Action: (\S+)') | ForEach-Object { $_.Groups[1].Value })
}
# The script, FILE-EDIT mode only (-NoCli; -ConfigPath or scratch -HomeDir/-AppDataDir). Returns Actions or 'refused'.
function Invoke-Script([hashtable]$P) {
  if (-not $HaveScript) { return $null }
  $P = $P.Clone(); $P.NoCli = $true
  if (-not $P.ContainsKey('Engine')) { $P.Engine = $Eng }
  if (-not $P.ContainsKey('ConfigPath')) {
    if (-not ($P.ContainsKey('HomeDir') -and $P.ContainsKey('AppDataDir'))) { throw 'GUARD BUG: script run without -ConfigPath or scratch dirs' }
  }
  try { $o = & $Script @P 6>$null; [pscustomobject]@{ Actions = @($o | ForEach-Object Action); Err = '' } }
  catch { [pscustomobject]@{ Actions = @('refused'); Err = $_.Exception.Message } }
}

function Get-Tree([string]$Path) {
  if (-not (Test-Path -LiteralPath $Path)) { return $null }
  $t = [IO.File]::ReadAllText($Path)
  if ([string]::IsNullOrWhiteSpace($t.TrimStart([char]0xFEFF))) { return $null }
  # a file the refusal cases leave unparsable compares as its raw text
  try { $n = [System.Text.Json.Nodes.JsonNode]::Parse($t) } catch { return ('RAW:' + $t) }
  # the unary comma: a JsonObject is IEnumerable, and a bare return would be enumerated into its pairs
  , $n
}
# deep compare, member order significant, numbers compared as their text, strings as values
function Test-SameTree($A, $B) {
  if ($null -eq $A -or $null -eq $B) { return ($null -eq $A) -and ($null -eq $B) }
  if ($A -is [string] -or $B -is [string]) { return ($A -is [string]) -and ($B -is [string]) -and ($A -ceq $B) }
  if ($A -is [System.Text.Json.Nodes.JsonObject]) {
    if ($B -isnot [System.Text.Json.Nodes.JsonObject] -or $A.Count -ne $B.Count) { return $false }
    $ka = @($A | ForEach-Object Key); $kb = @($B | ForEach-Object Key)
    for ($i = 0; $i -lt $ka.Count; $i++) {
      if ($ka[$i] -cne $kb[$i]) { return $false }
      if (-not (Test-SameTree $A[$ka[$i]] $B[$kb[$i]])) { return $false }
    }
    return $true
  }
  if ($A -is [System.Text.Json.Nodes.JsonArray]) {
    if ($B -isnot [System.Text.Json.Nodes.JsonArray] -or $A.Count -ne $B.Count) { return $false }
    for ($i = 0; $i -lt $A.Count; $i++) { if (-not (Test-SameTree $A[$i] $B[$i])) { return $false } }
    return $true
  }
  if ($B -is [System.Text.Json.Nodes.JsonObject] -or $B -is [System.Text.Json.Nodes.JsonArray]) { return $false }
  $va = $A.GetValueKind(); $vb = $B.GetValueKind()
  if ($va -ne $vb) { return $false }
  if ($va -eq [System.Text.Json.JsonValueKind]::String) { return $A.GetValue[string]() -ceq $B.GetValue[string]() }
  $A.ToJsonString() -ceq $B.ToJsonString()
}
# an expected-tree fixture with {{ENGINE}} / {{DB1}} / {{DB2}} filled in (JSON-escaped)
function Get-Expected([string]$Name) {
  $t = [IO.File]::ReadAllText((Join-Path $Fixtures $Name))
  foreach ($kv in @(@('{{ENGINE}}', $Eng), @('{{DB1}}', $Db1), @('{{DB2}}', $Db2))) { $t = $t.Replace($kv[0], $kv[1].Replace('\', '\\')) }
  # the unary comma: a JsonObject is IEnumerable, and a bare return would be enumerated into its pairs
  , [System.Text.Json.Nodes.JsonNode]::Parse($t)
}
# seed the same input into e\<name> and s\<name>; $Text = $null means "no file"
function Set-Pair([string]$Name, $Text, [switch]$Bom) {
  foreach ($d in $EDir, $SDir) {
    $p = Join-Path $d $Name
    Get-ChildItem -LiteralPath $d -Filter "$Name*" -ErrorAction SilentlyContinue | Remove-Item -Force
    if ($null -ne $Text) { [IO.File]::WriteAllText($p, $Text, [Text.UTF8Encoding]::new([bool]$Bom)) }
  }
  [pscustomobject]@{ E = (Join-Path $EDir $Name); S = (Join-Path $SDir $Name) }
}
function Get-Fixture([string]$Name) { [IO.File]::ReadAllText((Join-Path $Fixtures $Name)) -replace "`r`n", "`n" }
function Get-Baks([string]$Path) { @(Get-ChildItem -LiteralPath (Split-Path -Parent $Path) -Filter "$(Split-Path -Leaf $Path).bak-*" -ErrorAction SilentlyContinue) }
function Get-Tmps([string]$Path) { @(Get-ChildItem -LiteralPath (Split-Path -Parent $Path) -Filter "$(Split-Path -Leaf $Path).tmp-*" -ErrorAction SilentlyContinue) }
function Get-Hash([string]$Path) { if (Test-Path -LiteralPath $Path) { (Get-FileHash -LiteralPath $Path).Hash } else { 'absent' } }
# PARITY: same Action words, same parsed tree on the two copies
function Check-Parity([string]$Case, $Eng, $Scr, $Pair) {
  if ($null -eq $Scr) { Write-Host "  [SKIP] $Case-PARITY (script gone: $Script)" -ForegroundColor DarkGray; return }
  $ea = $(if ($Eng.Code -ne 0 -and (Get-Actions $Eng.Out).Count -eq 0) { @('refused') } else { Get-Actions $Eng.Out })
  # the script stops at its first refusal; the engine reports 'refused' per target -- compare the words
  Check "$Case-PARITY-ACTION" (($ea -join ',') -ceq ($Scr.Actions -join ',')) "engine=$($ea -join ',') script=$($Scr.Actions -join ',') $($Scr.Err)"
  if ($Pair) { Check "$Case-PARITY-TREE" (Test-SameTree (Get-Tree $Pair.E) (Get-Tree $Pair.S)) '' }
}

try {
  Write-Host 'mcp-config verb guard' -ForegroundColor Cyan

  # ---- MC-USAGE ------------------------------------------------------------------------------
  $r = Invoke-McpConfig @()
  Check 'MC-USAGE-NOTARGET' (($r.Code -eq 2) -and ($r.Err -match 'name a target') -and ($r.Err -match 'usage:')) "exit=$($r.Code)"
  $r = Invoke-McpConfig @('--bogus')
  Check 'MC-USAGE-FLAG' (($r.Code -eq 2) -and ($r.Err -match 'unknown flag: --bogus')) "exit=$($r.Code)"
  $u = Set-Pair 'usage.json' $null
  $r = Invoke-McpConfig @('--vscode', '--config-path', $u.E, '--name')
  Check 'MC-USAGE-NOVALUE' (($r.Code -eq 2) -and ($r.Err -match '--name needs a value')) "exit=$($r.Code)"
  $r = Invoke-McpConfig @('--all', '--config-path', $u.E)
  Check 'MC-USAGE-ALLPATH' (($r.Code -eq 2) -and ($r.Err -match 'exactly one of')) "exit=$($r.Code)"
  $r = Invoke-McpConfig @('--vscode', '--config-path', $u.E, '--name', 'bad name!')
  Check 'MC-USAGE-NAME' (($r.Code -eq 2) -and ($r.Err -match 'must be letters, digits')) "exit=$($r.Code)"
  Check 'MC-USAGE-NOFILE' (-not (Test-Path -LiteralPath $u.E)) ''

  # ---- MC-NODB -------------------------------------------------------------------------------
  $p = Set-Pair 'nodb.json' $null
  $missing = Join-Path $Bin 'nope.sqlite'
  $r = Invoke-McpConfig @('--vscode', '--config-path', $p.E, '--engine', $Eng, '--db', $missing)
  Check 'MC-NODB' (($r.Code -eq 2) -and ($r.Err -match 'does not exist') -and -not (Test-Path -LiteralPath $p.E)) "exit=$($r.Code)"
  $s = Invoke-Script @{ VSCode = $true; ConfigPath = $p.S; DbPath = $missing }
  Check-Parity 'MC-NODB' $r $s $p

  # ---- MC-ADD-MISS ---------------------------------------------------------------------------
  $p = Set-Pair 'add-missing.json' $null
  $r = Invoke-McpConfig @('--vscode', '--config-path', $p.E, '--engine', $Eng, '--db', $Db1)
  Check 'MC-ADD-MISS' (($r.Code -eq 0) -and ((Get-Actions $r.Out) -join ',') -ceq 'added') "exit=$($r.Code) $($r.Err)"
  Check 'MC-ADD-MISS-NOBAK' ((Get-Baks $p.E).Count -eq 0) ''
  $bytes = $(if (Test-Path -LiteralPath $p.E) { [IO.File]::ReadAllBytes($p.E) } else { [byte[]]@() })
  Check 'MC-ADD-MISS-NOBOM' (($bytes.Length -gt 0) -and -not ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF)) ''
  Check 'MC-ADD-MISS-TREE' (Test-SameTree (Get-Tree $p.E) (Get-Expected 'add-missing.vscode.expected.json')) ''
  Check 'MC-ADD-MISS-CRLF' (($bytes.Length -gt 0) -and ([Text.Encoding]::UTF8.GetString($bytes) -notmatch "(?<!`r)`n")) 'a new file is written CRLF'
  $s = Invoke-Script @{ VSCode = $true; ConfigPath = $p.S; DbPath = $Db1 }
  Check-Parity 'MC-ADD-MISS' $r $s $p

  # ---- MC-ADD-EMPTY --------------------------------------------------------------------------
  $in = Get-Fixture 'empty-object.json'
  $p = Set-Pair 'empty.json' $in
  $r = Invoke-McpConfig @('--claude-code', '--config-path', $p.E, '--engine', $Eng)
  Check 'MC-ADD-EMPTY' (($r.Code -eq 0) -and ((Get-Actions $r.Out) -join ',') -ceq 'added') "exit=$($r.Code) $($r.Err)"
  Check 'MC-ADD-EMPTY-TREE' (Test-SameTree (Get-Tree $p.E) (Get-Expected 'empty-object.claude.expected.json')) ''
  $bk = Get-Baks $p.E
  Check 'MC-ADD-EMPTY-BAK' (($bk.Count -eq 1) -and ([IO.File]::ReadAllText($bk[0].FullName) -ceq $in)) "backups=$($bk.Count)"
  $s = Invoke-Script @{ ClaudeCode = $true; ConfigPath = $p.S }
  Check-Parity 'MC-ADD-EMPTY' $r $s $p

  # ---- MC-ADD-BLANK --------------------------------------------------------------------------
  $p = Set-Pair 'blank.json' ''
  $r = Invoke-McpConfig @('--vscode', '--config-path', $p.E, '--engine', $Eng)
  Check 'MC-ADD-BLANK' (($r.Code -eq 0) -and ((Get-Actions $r.Out) -join ',') -ceq 'added') "exit=$($r.Code) $($r.Err)"
  $s = Invoke-Script @{ VSCode = $true; ConfigPath = $p.S }
  Check-Parity 'MC-ADD-BLANK' $r $s $p

  # ---- MC-DRYRUN -----------------------------------------------------------------------------
  $in = Get-Fixture 'beside-other.json'
  $p = Set-Pair 'dry.json' $in
  $h = Get-Hash $p.E
  $r = Invoke-McpConfig @('--claude-code', '--config-path', $p.E, '--engine', $Eng, '--db', $Db1, '--dry-run')
  Check 'MC-DRYRUN' (($r.Code -eq 0) -and ((Get-Actions $r.Out) -join ',') -ceq 'would-added' -and ((Get-Hash $p.E) -eq $h) -and (Get-Baks $p.E).Count -eq 0) "exit=$($r.Code)"
  Check 'MC-DRYRUN-AFTER' ($r.Out -match '(?m)^After : \{.*"--db"') 'prints the entry it would write'
  $p2 = Set-Pair 'dry-missing.json' $null
  $r = Invoke-McpConfig @('--vscode', '--config-path', $p2.E, '--engine', $Eng, '--dry-run')
  Check 'MC-DRYRUN-MISSING' (($r.Code -eq 0) -and -not (Test-Path -LiteralPath $p2.E)) ''
  $s = Invoke-Script @{ ClaudeCode = $true; ConfigPath = $p.S; DbPath = $Db1; DryRun = $true }
  Check-Parity 'MC-DRYRUN' (Invoke-McpConfig @('--claude-code', '--config-path', $p.E, '--engine', $Eng, '--db', $Db1, '--dry-run')) $s $p

  # ---- MC-BESIDE (+ LF kept, backup bytes, no .tmp-) -----------------------------------------
  $in = Get-Fixture 'beside-other.json'
  $p = Set-Pair 'beside.json' $in
  $r = Invoke-McpConfig @('--claude-code', '--config-path', $p.E, '--engine', $Eng, '--db', $Db1)
  Check 'MC-BESIDE' (($r.Code -eq 0) -and ((Get-Actions $r.Out) -join ',') -ceq 'added') "exit=$($r.Code) $($r.Err)"
  $after = Get-Tree $p.E
  $orig  = [System.Text.Json.Nodes.JsonNode]::Parse($in)
  Check 'MC-BESIDE-OTHER' (Test-SameTree $after['mcpServers']['keep-me'] $orig['mcpServers']['keep-me']) 'the other server is unchanged'
  foreach ($k in 'numStartups', 'big', 'name', 'projects') { Check "MC-BESIDE-KEEP-$k" (Test-SameTree $after[$k] $orig[$k]) '' }
  $txt = $(if (Test-Path -LiteralPath $p.E) { [IO.File]::ReadAllText($p.E) } else { '' })
  Check 'MC-BESIDE-NUMTEXT' (($txt -match '"numStartups": 1\.50') -and ($txt -match '12345678901234567890')) 'number text kept'
  Check 'MC-EOL-LF' (-not $txt.Contains("`r`n")) 'an LF file stays LF'
  Check 'MC-BESIDE-TREE' (Test-SameTree $after (Get-Expected 'beside-other.claude.expected.json')) ''
  $bk = Get-Baks $p.E
  Check 'MC-BESIDE-BAK' (($bk.Count -eq 1) -and ([IO.File]::ReadAllText($bk[0].FullName) -ceq $in)) "backups=$($bk.Count)"
  Check 'MC-BESIDE-NOTMP' ((Get-Tmps $p.E).Count -eq 0) ''
  $s = Invoke-Script @{ ClaudeCode = $true; ConfigPath = $p.S; DbPath = $Db1 }
  Check-Parity 'MC-BESIDE' $r $s $p

  # ---- MC-UNCHANGED --------------------------------------------------------------------------
  $h = Get-Hash $p.E; $m = (Get-Item -LiteralPath $p.E).LastWriteTimeUtc
  Start-Sleep -Milliseconds 1100
  $r = Invoke-McpConfig @('--claude-code', '--config-path', $p.E, '--engine', $Eng, '--db', $Db1)
  Check 'MC-UNCHANGED' (($r.Code -eq 0) -and ((Get-Actions $r.Out) -join ',') -ceq 'unchanged') "exit=$($r.Code)"
  Check 'MC-UNCHANGED-NOWRITE' (((Get-Hash $p.E) -eq $h) -and ((Get-Item -LiteralPath $p.E).LastWriteTimeUtc -eq $m) -and (Get-Baks $p.E).Count -eq 1) ''
  $s = Invoke-Script @{ ClaudeCode = $true; ConfigPath = $p.S; DbPath = $Db1 }
  Check-Parity 'MC-UNCHANGED' $r $s $p

  # ---- MC-REMOVE / MC-ABSENT -----------------------------------------------------------------
  Start-Sleep -Milliseconds 1100     # a distinct backup name
  $r = Invoke-McpConfig @('--claude-code', '--config-path', $p.E, '--remove')
  Check 'MC-REMOVE' (($r.Code -eq 0) -and ((Get-Actions $r.Out) -join ',') -ceq 'removed') "exit=$($r.Code) $($r.Err)"
  Check 'MC-REMOVE-TREE' (Test-SameTree (Get-Tree $p.E) $orig) 'only our entry went'
  $s = Invoke-Script @{ ClaudeCode = $true; ConfigPath = $p.S; Remove = $true }
  Check-Parity 'MC-REMOVE' $r $s $p
  $h = Get-Hash $p.E; $nb = (Get-Baks $p.E).Count
  $r = Invoke-McpConfig @('--claude-code', '--config-path', $p.E, '--remove')
  Check 'MC-ABSENT' (($r.Code -eq 0) -and ((Get-Actions $r.Out) -join ',') -ceq 'absent' -and ((Get-Hash $p.E) -eq $h) -and ((Get-Baks $p.E).Count -eq $nb)) "exit=$($r.Code)"
  $s = Invoke-Script @{ ClaudeCode = $true; ConfigPath = $p.S; Remove = $true }
  Check-Parity 'MC-ABSENT' $r $s $p

  # ---- MC-UPDATE (user env kept, values masked everywhere) -----------------------------------
  $in = Get-Fixture 'user-env.json'
  $p = Set-Pair 'update.json' $in
  $outs = New-Object System.Collections.Generic.List[string]
  $r = Invoke-McpConfig @('--claude-code', '--config-path', $p.E, '--engine', $Eng, '--db', $Db2, '--dry-run')
  $outs.Add($r.Out); $outs.Add($r.Err)
  $r = Invoke-McpConfig @('--claude-code', '--config-path', $p.E, '--engine', $Eng, '--db', $Db2, '--dry-run', '--json')
  $outs.Add($r.Out); $outs.Add($r.Err)
  $r = Invoke-McpConfig @('--claude-code', '--config-path', $p.E, '--engine', $Eng, '--db', $Db2)
  $outs.Add($r.Out); $outs.Add($r.Err)
  Check 'MC-UPDATE' (($r.Code -eq 0) -and ((Get-Actions $r.Out) -join ',') -ceq 'updated') "exit=$($r.Code) $($r.Err)"
  Check 'MC-UPDATE-MASK' (($r.Out -match '(?m)^Before: .*"API_KEY":"\*\*\*"') -and ($r.Out -match '(?m)^After : .*"API_KEY":"\*\*\*"')) 'Before/After show the key, value ***'
  Check 'MC-UPDATE-TREE' (Test-SameTree (Get-Tree $p.E) (Get-Expected 'user-env.claude.expected.json')) 'env + timeout kept, args replaced'
  $leaks = @($outs | Where-Object { $_ -and $_.Contains($Secret) })
  Check 'MC-UPDATE-NOLEAK' ($leaks.Count -eq 0) 'the env value never reaches stdout/stderr (text, --json, --dry-run)'
  $s = Invoke-Script @{ ClaudeCode = $true; ConfigPath = $p.S; DbPath = $Db2 }
  Check-Parity 'MC-UPDATE' $r $s $p

  # ---- refusals: nothing written, no backup --------------------------------------------------
  foreach ($c in @(
      @('MC-NOTOURS',    'not-ours.json',        @(),            "runs 'C:\\x\\other\.exe', not drag-lint\.exe, so it is not this verb's to update"),
      @('MC-NOTOURS-RM', 'not-ours.json',        @('--remove'),  "not this verb's to remove"),
      @('MC-COMMENTS',   'comments.json',        @(),            'comments or trailing commas.*Add this entry by hand instead:\s+"servers": \{ "drag-lint": \{"type":"stdio"'),
      @('MC-TRAILING',   'trailing-commas.json', @(),            'comments or trailing commas'),
      @('MC-INVALID',    'invalid.json',         @(),            'is not valid JSON, so nothing was written'),
      @('MC-CONTAINER',  'container-array.json', @(),            '"servers" is not a JSON object'),
      @('MC-TOPARRAY',   'top-array.json',       @(),            'top level is not a JSON object'))) {
    $case, $fx, $extra, $rx = $c
    $p = Set-Pair "$case.json" (Get-Fixture $fx)
    $h = Get-Hash $p.E
    $r = Invoke-McpConfig (@('--vscode', '--config-path', $p.E, '--engine', $Eng) + $extra)
    Check $case (($r.Code -eq 1) -and ([regex]::IsMatch($r.Err, $rx, 'Singleline'))) "exit=$($r.Code) err=$($r.Err.Trim())"
    Check "$case-NOWRITE" (((Get-Hash $p.E) -eq $h) -and ((Get-Baks $p.E).Count -eq 0) -and ((Get-Tmps $p.E).Count -eq 0)) ''
    $sp = @{ VSCode = $true; ConfigPath = $p.S }
    if ($extra -contains '--remove') { $sp.Remove = $true }
    $s = Invoke-Script $sp
    Check-Parity $case $r $s $p
  }

  # ---- MC-EOL (CRLF) / MC-BOM ----------------------------------------------------------------
  $in = (Get-Fixture 'beside-other.json') -replace "`n", "`r`n"
  $p = Set-Pair 'crlf.json' $in
  $r = Invoke-McpConfig @('--claude-code', '--config-path', $p.E, '--engine', $Eng, '--db', $Db1)
  $txt = $(if (Test-Path -LiteralPath $p.E) { [IO.File]::ReadAllText($p.E) } else { '' })
  Check 'MC-EOL-CRLF' (($r.Code -eq 0) -and $txt.Contains("`r`n") -and ($txt -notmatch "(?<!`r)`n")) 'a CRLF file stays CRLF'
  $s = Invoke-Script @{ ClaudeCode = $true; ConfigPath = $p.S; DbPath = $Db1 }
  Check-Parity 'MC-EOL-CRLF' $r $s $p
  $p = Set-Pair 'bom.json' (Get-Fixture 'empty-object.json') -Bom
  $r = Invoke-McpConfig @('--vscode', '--config-path', $p.E, '--engine', $Eng)
  $bytes = $(if (Test-Path -LiteralPath $p.E) { [IO.File]::ReadAllBytes($p.E) } else { [byte[]]@(0xEF, 0xBB) })
  Check 'MC-BOM' (($r.Code -eq 0) -and ((Get-Actions $r.Out) -join ',') -ceq 'added' -and -not ($bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB)) "exit=$($r.Code)"
  $s = Invoke-Script @{ VSCode = $true; ConfigPath = $p.S }
  Check-Parity 'MC-BOM' $r $s $p

  # ---- MC-ALL-SKIP / MC-DOTCLAUDE / MC-CCD (scratch home + appdata; CLAUDE_CONFIG_DIR unset) --
  foreach ($side in 'e', 's') {
    New-Item -ItemType Directory -Force (Join-Path $Work "$side-home"), (Join-Path $Work "$side-appdata") | Out-Null
  }
  $eh = Join-Path $Work 'e-home'; $ea = Join-Path $Work 'e-appdata'
  $sh = Join-Path $Work 's-home'; $sa = Join-Path $Work 's-appdata'
  $r = Invoke-McpConfig @('--all', '--home-dir', $eh, '--appdata-dir', $ea, '--engine', $Eng)
  Check 'MC-ALL-SKIP' (($r.Code -eq 0) -and ((Get-Actions $r.Out) -join ',') -ceq 'skipped,skipped') "exit=$($r.Code) $((Get-Actions $r.Out) -join ',')"
  Check 'MC-ALL-SKIP-NOFILE' (-not (Test-Path -LiteralPath (Join-Path $eh '.claude.json')) -and -not (Test-Path -LiteralPath (Join-Path $ea 'Code'))) ''
  $s = Invoke-Script @{ All = $true; HomeDir = $sh; AppDataDir = $sa }
  Check-Parity 'MC-ALL-SKIP' $r $s $null
  $r = Invoke-McpConfig @('--claude-code', '--home-dir', $eh, '--appdata-dir', $ea, '--engine', $Eng)
  Check 'MC-NAMED-NOTINSTALLED' (($r.Code -eq 2) -and ($r.Err -match 'is the client installed')) "exit=$($r.Code)"
  $s = Invoke-Script @{ ClaudeCode = $true; HomeDir = $sh; AppDataDir = $sa }
  Check-Parity 'MC-NAMED-NOTINSTALLED' $r $s $null
  New-Item -ItemType Directory -Force (Join-Path $eh '.claude'), (Join-Path $sh '.claude') | Out-Null
  $r = Invoke-McpConfig @('--all', '--home-dir', $eh, '--appdata-dir', $ea, '--engine', $Eng)
  Check 'MC-DOTCLAUDE' (($r.Code -eq 0) -and ((Get-Actions $r.Out) -join ',') -ceq 'added,skipped' -and ($r.Out -match [regex]::Escape("Path  : $(Join-Path $eh '.claude.json')"))) "$((Get-Actions $r.Out) -join ',')"
  $s = Invoke-Script @{ All = $true; HomeDir = $sh; AppDataDir = $sa }
  Check-Parity 'MC-DOTCLAUDE' $r $s ([pscustomobject]@{ E = (Join-Path $eh '.claude.json'); S = (Join-Path $sh '.claude.json') })
  $ccdE = Join-Path $Work 'e-ccd'; $ccdS = Join-Path $Work 's-ccd'
  New-Item -ItemType Directory -Force $ccdE, $ccdS | Out-Null
  try {
    $env:CLAUDE_CONFIG_DIR = $ccdE
    $r = Invoke-McpConfig @('--claude-code', '--home-dir', (Join-Path $Work 'none-home'), '--appdata-dir', $ea, '--engine', $Eng)
    Check 'MC-CCD' (($r.Code -eq 0) -and ($r.Out -match [regex]::Escape("Path  : $(Join-Path $ccdE '.claude.json')")) -and (Test-Path -LiteralPath (Join-Path $ccdE '.claude.json'))) "exit=$($r.Code) $($r.Err)"
    $env:CLAUDE_CONFIG_DIR = $ccdS
    $s = Invoke-Script @{ ClaudeCode = $true; HomeDir = (Join-Path $Work 'none-home'); AppDataDir = $sa }
    Check-Parity 'MC-CCD' $r $s ([pscustomobject]@{ E = (Join-Path $ccdE '.claude.json'); S = (Join-Path $ccdS '.claude.json') })
  } finally {
    Remove-Item Env:\CLAUDE_CONFIG_DIR -ErrorAction SilentlyContinue
  }

  # ---- MC-ENGINE / MC-JSON -------------------------------------------------------------------
  $p = Set-Pair 'engine.json' $null
  $r = Invoke-McpConfig @('--vscode', '--config-path', $p.E)
  $cmd = $(try { (Get-Tree $p.E)['servers']['drag-lint']['command'].GetValue[string]() } catch { '' })
  Check 'MC-ENGINE' (($r.Code -eq 0) -and ($cmd -ieq $Exe)) "command=$cmd"
  $p = Set-Pair 'json.json' (Get-Fixture 'empty-object.json')
  $r = Invoke-McpConfig @('--vscode', '--config-path', $p.E, '--engine', $Eng, '--json')
  $j = $(try { @($r.Out | ConvertFrom-Json -NoEnumerate) } catch { @() })
  $ok = ($r.Code -eq 0) -and ($j.Count -eq 1) -and ($j[0].Count -eq 1)
  if ($ok) {
    $o = $j[0][0]
    $ok = ($o.Target -eq 'VSCode') -and ($o.Action -eq 'added') -and ($o.Path -eq $p.E) -and ($o.Backup -like "$($p.E).bak-*") -and
          ($o.Before -eq '(none)') -and ($o.After -like '{"type":"stdio"*') -and ($o.Error -eq '') -and ($o.ExitCode -eq 0)
  }
  Check 'MC-JSON' $ok "out=$($r.Out)"
} finally {
  if ($null -ne $PrevCcd) { $env:CLAUDE_CONFIG_DIR = $PrevCcd } else { Remove-Item Env:\CLAUDE_CONFIG_DIR -ErrorAction SilentlyContinue }
  # ---- MC-REAL -------------------------------------------------------------------------------
  Check 'MC-REAL-VSCODE' ((Get-Print $RealVSCode) -eq $RealBefore.VSCodePrint) "$RealVSCode byte-identical (or absent both times)"
  $cNow = Get-Print $RealClaude
  if ($cNow -eq $RealBefore.ClaudePrint) {
    Check 'MC-REAL-CLAUDE' $true "$RealClaude byte-identical (or absent both times)"
  } else {
    Check 'MC-REAL-CLAUDE' ((Get-ServersText $RealClaude) -ceq $RealBefore.ClaudeServers) `
      "$RealClaude changed during the run (a running Claude Code session rewrites it); its mcpServers object is identical"
  }
  Check 'MC-REAL-NOSIBLINGS' ((((Get-Siblings $RealClaude) -join '|') -eq $RealBefore.ClaudeSibs) -and (((Get-Siblings $RealVSCode) -join '|') -eq $RealBefore.VSCodeSibs)) `
    'no .bak-* / .tmp-* appeared beside the real files'
  Remove-Item -LiteralPath $Work -Recurse -Force -ErrorAction SilentlyContinue
}

if ($script:Failed) { Write-Host 'FAIL -- run_mcp_config_verb' -ForegroundColor Red; exit 1 }
Write-Host 'PASS -- run_mcp_config_verb' -ForegroundColor Green
exit 0
