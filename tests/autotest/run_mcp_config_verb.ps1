<#
  run_mcp_config_verb.ps1 -- `drag-lint mcp-config`, the verb that replaced
  charts\src\Set-DragLintMcpConfig.ps1 (retired), run ONLY against scratch copies.

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

  Cases (each also asserts a GOLDEN pair, <case>-PARITY-ACTION and <case>-PARITY-TREE: the Action
  word(s) and the parsed tree that the retired Set-DragLintMcpConfig.ps1 produced in its FILE-EDIT
  mode on the same input, measured green against the script on 2026-10-14 and frozen here when it
  was deleted; numbers compare as their text):
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
                  no backup; an HTTP entry with a bearer token in headers/url: refused, Before reads
                  (not ours), the token absent from stdout/stderr (text, --json, update and remove)
    MC-HEADERS    an ours entry with headers + a string env: updated, both masked *** in Before/After, the
                  secrets absent from stdout/stderr (text, --json, --dry-run); expected tree
    MC-COMMENTS-RM  --remove on a commented file: "Delete the ... entry by hand", no (none) paste hint
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
    MC-CURSOR     item 8: --cursor / --all: ~\.cursor\mcp.json (home-dir) absent -> skipped, present -> added with the\n                  VS Code entry under "mcpServers", unchanged on rerun, --remove --json reports Target Cursor\n    MC-JSON       --json: one array, one object per target, the documented fields
    MC-REAL       the real files (see above)

  Exit: 0 all PASS, 1 any FAIL, 2 setup.
#>
[CmdletBinding()]
param(
  [string]$Exe    = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe",
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

$Secret = 'S3cr3t-Value-MCV'
$stamp  = '{0}-{1}' -f (Get-Date -Format 'yyyyMMddHHmmss'), $PID
$Work   = Join-Path ([IO.Path]::GetTempPath()) "drag-lint-mcp-config-guard-$stamp"
$Bin    = Join-Path $Work 'bin'
$EDir   = Join-Path $Work 'e'      # the engine's copies
New-Item -ItemType Directory -Force $Bin, $EDir | Out-Null
$Eng = Join-Path $Bin 'drag-lint.exe'; [IO.File]::WriteAllText($Eng, 'dummy')
$Db1 = Join-Path $Bin 'One.sqlite';    [IO.File]::WriteAllText($Db1, 'dummy')
$Db2 = Join-Path $Bin 'Two.sqlite';    [IO.File]::WriteAllText($Db2, 'dummy')

# ---- the real files: fingerprint now, compare in finally ------------------------------------
$RealClaude = Join-Path $env:USERPROFILE '.claude.json'
$RealVSCode = Join-Path $env:APPDATA 'Code\User\mcp.json'
$RealCursor = Join-Path $env:USERPROFILE '.cursor\mcp.json'
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
$PrevCcd = $env:CLAUDE_CONFIG_DIR
# the user's own CLAUDE_CONFIG_DIR, when set, is where Claude Code really keeps its file: fingerprinted too
$RealCcd = $(if ($PrevCcd) { Join-Path $PrevCcd '.claude.json' } else { '' })
$RealBefore = @{
  ClaudePrint = Get-Print $RealClaude; ClaudeServers = Get-ServersText $RealClaude
  VSCodePrint = Get-Print $RealVSCode; CursorPrint = Get-Print $RealCursor
  ClaudeSibs  = (Get-Siblings $RealClaude) -join '|'; VSCodeSibs = (Get-Siblings $RealVSCode) -join '|'
  CcdPrint    = $(if ($RealCcd) { Get-Print $RealCcd } else { '' })
  CcdServers  = $(if ($RealCcd) { Get-ServersText $RealCcd } else { '' })
  CcdSibs     = $(if ($RealCcd) { (Get-Siblings $RealCcd) -join '|' } else { '' })
}
Remove-Item Env:\CLAUDE_CONFIG_DIR -ErrorAction SilentlyContinue

# ---- runners ---------------------------------------------------------------------------------
# The engine. Refuses any command line that could reach a default (real) file.
function Invoke-McpConfig([string[]]$A) {
  $hasPath = $A -contains '--config-path'
  $hasDirs = ($A -contains '--home-dir') -and ($A -contains '--appdata-dir')
  $usage   = ($A | Where-Object { $_ -in '--claude-code', '--vscode', '--cursor', '--all' }).Count -eq 0 -or ($A -contains '--bogus')
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
function Get-Tree([string]$Path) {
  if (-not (Test-Path -LiteralPath $Path)) { return $null }
  # a nested command's output is passed through, not re-enumerated
  Get-TextTree ([IO.File]::ReadAllText($Path))
}
# the tree of a text (the same rules as Get-Tree; $null text = no file)
function Get-TextTree($t) {
  if ($null -eq $t) { return $null }
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
# seed the input into e\<name>; $Text = $null means "no file"
function Set-Pair([string]$Name, $Text, [switch]$Bom) {
  $p = Join-Path $EDir $Name
  Get-ChildItem -LiteralPath $EDir -Filter "$Name*" -ErrorAction SilentlyContinue | Remove-Item -Force
  if ($null -ne $Text) { [IO.File]::WriteAllText($p, $Text, [Text.UTF8Encoding]::new([bool]$Bom)) }
  [pscustomobject]@{ E = $p }
}
function Get-Fixture([string]$Name) { [IO.File]::ReadAllText((Join-Path $Fixtures $Name)) -replace "`r`n", "`n" }
function Get-Baks([string]$Path) { @(Get-ChildItem -LiteralPath (Split-Path -Parent $Path) -Filter "$(Split-Path -Leaf $Path).bak-*" -ErrorAction SilentlyContinue) }
function Get-Tmps([string]$Path) { @(Get-ChildItem -LiteralPath (Split-Path -Parent $Path) -Filter "$(Split-Path -Leaf $Path).tmp-*" -ErrorAction SilentlyContinue) }
function Get-Hash([string]$Path) { if (Test-Path -LiteralPath $Path) { (Get-FileHash -LiteralPath $Path).Hash } else { 'absent' } }
# PARITY, GOLDEN: the Action words and the parsed tree the retired Set-DragLintMcpConfig.ps1 gave on
# the same input (frozen from its last green parity run, 2026-10-14). $ScriptActions is the script's
# comma-joined Action list ('refused' where it threw); $Path the engine's file, $null = no tree check;
# $ScriptTree the script's resulting tree ($null = no file / blank).
function Check-Parity([string]$Case, $Run, [string]$ScriptActions, $Path, $ScriptTree) {
  $ea = $(if ($Run.Code -ne 0 -and (Get-Actions $Run.Out).Count -eq 0) { @('refused') } else { Get-Actions $Run.Out })
  # the script stopped at its first refusal; the engine reports 'refused' per target -- compare the words
  Check "$Case-PARITY-ACTION" (($ea -join ',') -ceq $ScriptActions) "engine=$($ea -join ',') script(golden)=$ScriptActions"
  if ($Path) { Check "$Case-PARITY-TREE" (Test-SameTree (Get-Tree $Path) $ScriptTree) '' }
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
  Check-Parity 'MC-NODB' $r 'refused' $p.E $null

  # ---- MC-ADD-MISS ---------------------------------------------------------------------------
  $p = Set-Pair 'add-missing.json' $null
  $r = Invoke-McpConfig @('--vscode', '--config-path', $p.E, '--engine', $Eng, '--db', $Db1)
  Check 'MC-ADD-MISS' (($r.Code -eq 0) -and ((Get-Actions $r.Out) -join ',') -ceq 'added') "exit=$($r.Code) $($r.Err)"
  Check 'MC-ADD-MISS-NOBAK' ((Get-Baks $p.E).Count -eq 0) ''
  $bytes = $(if (Test-Path -LiteralPath $p.E) { [IO.File]::ReadAllBytes($p.E) } else { [byte[]]@() })
  Check 'MC-ADD-MISS-NOBOM' (($bytes.Length -gt 0) -and -not ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF)) ''
  Check 'MC-ADD-MISS-TREE' (Test-SameTree (Get-Tree $p.E) (Get-Expected 'add-missing.vscode.expected.json')) ''
  Check 'MC-ADD-MISS-CRLF' (($bytes.Length -gt 0) -and ([Text.Encoding]::UTF8.GetString($bytes) -notmatch "(?<!`r)`n")) 'a new file is written CRLF'
  Check-Parity 'MC-ADD-MISS' $r 'added' $p.E (Get-Expected 'add-missing.vscode.expected.json')

  # ---- MC-ADD-EMPTY --------------------------------------------------------------------------
  $in = Get-Fixture 'empty-object.json'
  $p = Set-Pair 'empty.json' $in
  $r = Invoke-McpConfig @('--claude-code', '--config-path', $p.E, '--engine', $Eng)
  Check 'MC-ADD-EMPTY' (($r.Code -eq 0) -and ((Get-Actions $r.Out) -join ',') -ceq 'added') "exit=$($r.Code) $($r.Err)"
  Check 'MC-ADD-EMPTY-TREE' (Test-SameTree (Get-Tree $p.E) (Get-Expected 'empty-object.claude.expected.json')) ''
  $bk = Get-Baks $p.E
  Check 'MC-ADD-EMPTY-BAK' (($bk.Count -eq 1) -and ([IO.File]::ReadAllText($bk[0].FullName) -ceq $in)) "backups=$($bk.Count)"
  Check-Parity 'MC-ADD-EMPTY' $r 'added' $p.E (Get-Expected 'empty-object.claude.expected.json')

  # ---- MC-ADD-BLANK --------------------------------------------------------------------------
  $p = Set-Pair 'blank.json' ''
  $r = Invoke-McpConfig @('--vscode', '--config-path', $p.E, '--engine', $Eng)
  Check 'MC-ADD-BLANK' (($r.Code -eq 0) -and ((Get-Actions $r.Out) -join ',') -ceq 'added') "exit=$($r.Code) $($r.Err)"
  Check-Parity 'MC-ADD-BLANK' $r 'added' $p.E (Get-Expected 'add-blank.vscode.expected.json')

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
  Check-Parity 'MC-DRYRUN' (Invoke-McpConfig @('--claude-code', '--config-path', $p.E, '--engine', $Eng, '--db', $Db1, '--dry-run')) 'would-added' $p.E (Get-TextTree $in)

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
  Check-Parity 'MC-BESIDE' $r 'added' $p.E (Get-Expected 'beside-other.claude.expected.json')

  # ---- MC-UNCHANGED --------------------------------------------------------------------------
  $h = Get-Hash $p.E; $m = (Get-Item -LiteralPath $p.E).LastWriteTimeUtc
  Start-Sleep -Milliseconds 1100
  $r = Invoke-McpConfig @('--claude-code', '--config-path', $p.E, '--engine', $Eng, '--db', $Db1)
  Check 'MC-UNCHANGED' (($r.Code -eq 0) -and ((Get-Actions $r.Out) -join ',') -ceq 'unchanged') "exit=$($r.Code)"
  Check 'MC-UNCHANGED-NOWRITE' (((Get-Hash $p.E) -eq $h) -and ((Get-Item -LiteralPath $p.E).LastWriteTimeUtc -eq $m) -and (Get-Baks $p.E).Count -eq 1) ''
  Check-Parity 'MC-UNCHANGED' $r 'unchanged' $p.E (Get-Expected 'beside-other.claude.expected.json')

  # ---- MC-REMOVE / MC-ABSENT -----------------------------------------------------------------
  Start-Sleep -Milliseconds 1100     # a distinct backup name
  $r = Invoke-McpConfig @('--claude-code', '--config-path', $p.E, '--remove')
  Check 'MC-REMOVE' (($r.Code -eq 0) -and ((Get-Actions $r.Out) -join ',') -ceq 'removed') "exit=$($r.Code) $($r.Err)"
  Check 'MC-REMOVE-TREE' (Test-SameTree (Get-Tree $p.E) $orig) 'only our entry went'
  Check-Parity 'MC-REMOVE' $r 'removed' $p.E $orig
  $h = Get-Hash $p.E; $nb = (Get-Baks $p.E).Count
  $r = Invoke-McpConfig @('--claude-code', '--config-path', $p.E, '--remove')
  Check 'MC-ABSENT' (($r.Code -eq 0) -and ((Get-Actions $r.Out) -join ',') -ceq 'absent' -and ((Get-Hash $p.E) -eq $h) -and ((Get-Baks $p.E).Count -eq $nb)) "exit=$($r.Code)"
  Check-Parity 'MC-ABSENT' $r 'absent' $p.E $orig

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
  Check-Parity 'MC-UPDATE' $r 'updated' $p.E (Get-Expected 'user-env.claude.expected.json')

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
    Check-Parity $case $r 'refused' $p.E (Get-TextTree (Get-Fixture $fx))
  }

  # ---- MC-NOLEAK: a refused foreign entry's body is never printed; headers / non-object env masked --------
  $tok = 'TOPSECRET'
  $p = Set-Pair 'foreign-http.json' (Get-Fixture 'not-ours-http.json')
  $h = Get-Hash $p.E
  $outs = New-Object System.Collections.Generic.List[string]
  foreach ($extra in @(@(), @('--json'), @('--remove'), @('--remove', '--json'))) {
    $r = Invoke-McpConfig (@('--vscode', '--config-path', $p.E, '--engine', $Eng) + $extra)
    Check "MC-NOTOURS-HTTP $($extra -join ' ')" ($r.Code -eq 1) "exit=$($r.Code)"
    $outs.Add($r.Out); $outs.Add($r.Err)
  }
  Check 'MC-NOTOURS-NOLEAK' (@($outs | Where-Object { $_ -and $_.Contains($tok) }).Count -eq 0) 'the foreign entry''s token / url never reach stdout or stderr (text, --json)'
  Check 'MC-NOTOURS-BEFORE' ($outs[0] -match '(?m)^Before: \(not ours\)') 'Before is (not ours), never the body'
  Check 'MC-NOTOURS-HTTP-NOWRITE' (((Get-Hash $p.E) -eq $h) -and ((Get-Baks $p.E).Count -eq 0)) ''
  Check-Parity 'MC-NOTOURS-HTTP' (Invoke-McpConfig @('--vscode', '--config-path', $p.E, '--engine', $Eng)) 'refused' $p.E (Get-TextTree (Get-Fixture 'not-ours-http.json'))
  $p = Set-Pair 'ours-http.json' (Get-Fixture 'ours-http.json')
  $outs.Clear()
  foreach ($extra in @(@('--dry-run'), @('--dry-run', '--json'), @())) {
    $r = Invoke-McpConfig (@('--vscode', '--config-path', $p.E, '--engine', $Eng) + $extra)
    $outs.Add($r.Out); $outs.Add($r.Err)
  }
  Check 'MC-HEADERS' (($r.Code -eq 0) -and ((Get-Actions $r.Out) -join ',') -ceq 'updated') "exit=$($r.Code) $($r.Err)"
  Check 'MC-HEADERS-MASK' (($r.Out -match '(?m)^Before: .*"Authorization":"\*\*\*".*"env":"\*\*\*"') -and ($r.Out -match '(?m)^After : .*"Authorization":"\*\*\*".*"env":"\*\*\*"')) 'headers values and a string env read ***'
  Check 'MC-HEADERS-NOLEAK' (@($outs | Where-Object { $_ -and ($_.Contains($tok) -or $_.Contains('ENVSECRET')) }).Count -eq 0) 'text, --json and --dry-run'
  Check 'MC-HEADERS-TREE' (Test-SameTree (Get-Tree $p.E) (Get-Expected 'ours-http.vscode.expected.json')) 'type/command replaced in place, args appended, headers + env kept'
  Check-Parity 'MC-HEADERS' $r 'updated' $p.E (Get-Expected 'ours-http.vscode.expected.json')
  # --remove on a commented file: the advice is to delete the entry, not to paste "(none)"
  $p = Set-Pair 'comments-rm.json' (Get-Fixture 'comments.json')
  $r = Invoke-McpConfig @('--vscode', '--config-path', $p.E, '--remove')
  Check 'MC-COMMENTS-RM' (($r.Code -eq 1) -and ($r.Err -match 'Delete the "drag-lint" entry under "servers" by hand instead') -and ($r.Err -notmatch '\(none\)')) "err=$($r.Err.Trim())"

  # ---- MC-EOL (CRLF) / MC-BOM ----------------------------------------------------------------
  $in = (Get-Fixture 'beside-other.json') -replace "`n", "`r`n"
  $p = Set-Pair 'crlf.json' $in
  $r = Invoke-McpConfig @('--claude-code', '--config-path', $p.E, '--engine', $Eng, '--db', $Db1)
  $txt = $(if (Test-Path -LiteralPath $p.E) { [IO.File]::ReadAllText($p.E) } else { '' })
  Check 'MC-EOL-CRLF' (($r.Code -eq 0) -and $txt.Contains("`r`n") -and ($txt -notmatch "(?<!`r)`n")) 'a CRLF file stays CRLF'
  Check-Parity 'MC-EOL-CRLF' $r 'added' $p.E (Get-Expected 'beside-other.claude.expected.json')
  $p = Set-Pair 'bom.json' (Get-Fixture 'empty-object.json') -Bom
  $r = Invoke-McpConfig @('--vscode', '--config-path', $p.E, '--engine', $Eng)
  $bytes = $(if (Test-Path -LiteralPath $p.E) { [IO.File]::ReadAllBytes($p.E) } else { [byte[]]@(0xEF, 0xBB) })
  Check 'MC-BOM' (($r.Code -eq 0) -and ((Get-Actions $r.Out) -join ',') -ceq 'added' -and -not ($bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB)) "exit=$($r.Code)"
  Check-Parity 'MC-BOM' $r 'added' $p.E (Get-Expected 'add-blank.vscode.expected.json')

  # ---- MC-ALL-SKIP / MC-DOTCLAUDE / MC-CCD (scratch home + appdata; CLAUDE_CONFIG_DIR unset) --
  $eh = Join-Path $Work 'e-home'; $ea = Join-Path $Work 'e-appdata'
  New-Item -ItemType Directory -Force $eh, $ea | Out-Null
  $r = Invoke-McpConfig @('--all', '--home-dir', $eh, '--appdata-dir', $ea, '--engine', $Eng)
  Check 'MC-ALL-SKIP' (($r.Code -eq 0) -and ((Get-Actions $r.Out) -join ',') -ceq 'skipped,skipped,skipped') "exit=$($r.Code) $((Get-Actions $r.Out) -join ',')"
  Check 'MC-ALL-SKIP-NOFILE' (-not (Test-Path -LiteralPath (Join-Path $eh '.claude.json')) -and -not (Test-Path -LiteralPath (Join-Path $ea 'Code')) -and -not (Test-Path -LiteralPath (Join-Path $eh '.cursor'))) ''
  # (the golden words are the retired script's two targets plus Cursor, which is new: skipped like VS Code)
Check-Parity 'MC-ALL-SKIP' $r 'skipped,skipped,skipped' $null $null
  $r = Invoke-McpConfig @('--claude-code', '--home-dir', $eh, '--appdata-dir', $ea, '--engine', $Eng)
  Check 'MC-NAMED-NOTINSTALLED' (($r.Code -eq 2) -and ($r.Err -match 'is the client installed')) "exit=$($r.Code)"
  Check-Parity 'MC-NAMED-NOTINSTALLED' $r 'refused' $null $null
  New-Item -ItemType Directory -Force (Join-Path $eh '.claude') | Out-Null
  $r = Invoke-McpConfig @('--all', '--home-dir', $eh, '--appdata-dir', $ea, '--engine', $Eng)
  Check 'MC-DOTCLAUDE' (($r.Code -eq 0) -and ((Get-Actions $r.Out) -join ',') -ceq 'added,skipped,skipped' -and ($r.Out -match [regex]::Escape("Path  : $(Join-Path $eh '.claude.json')"))) "$((Get-Actions $r.Out) -join ',')"
  Check-Parity 'MC-DOTCLAUDE' $r 'added,skipped,skipped' (Join-Path $eh '.claude.json') (Get-Expected 'empty-object.claude.expected.json')
  $ccdE = Join-Path $Work 'e-ccd'
  New-Item -ItemType Directory -Force $ccdE | Out-Null
  try {
    $env:CLAUDE_CONFIG_DIR = $ccdE
    $r = Invoke-McpConfig @('--claude-code', '--home-dir', (Join-Path $Work 'none-home'), '--appdata-dir', $ea, '--engine', $Eng)
    Check 'MC-CCD' (($r.Code -eq 0) -and ($r.Out -match [regex]::Escape("Path  : $(Join-Path $ccdE '.claude.json')")) -and (Test-Path -LiteralPath (Join-Path $ccdE '.claude.json'))) "exit=$($r.Code) $($r.Err)"
    Check-Parity 'MC-CCD' $r 'added' (Join-Path $ccdE '.claude.json') (Get-Expected 'empty-object.claude.expected.json')
  } finally {
    Remove-Item Env:\CLAUDE_CONFIG_DIR -ErrorAction SilentlyContinue
  }

  # ---- MC-CURSOR (item 8): ~\.cursor\mcp.json, container "mcpServers", the VS Code entry shape ------
  # absent -> skipped under --all (MC-ALL-SKIP above, with a home that has no .cursor); present -> added.
  $ch = Join-Path $Work 'e-home-cursor'
  New-Item -ItemType Directory -Force $ch | Out-Null
  $cf = Join-Path $ch '.cursor\mcp.json'
  $r = Invoke-McpConfig @('--all', '--home-dir', $ch, '--appdata-dir', $ea, '--engine', $Eng, '--db', $Db1)
  Check 'MC-CURSOR-CONTROL-ABSENT' (($r.Code -eq 0) -and ((Get-Actions $r.Out) -join ',') -ceq 'skipped,skipped,skipped' -and -not (Test-Path -LiteralPath (Join-Path $ch '.cursor'))) "$((Get-Actions $r.Out) -join ',')"
  New-Item -ItemType Directory -Force (Join-Path $ch '.cursor') | Out-Null
  $r = Invoke-McpConfig @('--all', '--home-dir', $ch, '--appdata-dir', $ea, '--engine', $Eng, '--db', $Db1)
  Check 'MC-CURSOR-ADDED' (($r.Code -eq 0) -and ((Get-Actions $r.Out) -join ',') -ceq 'skipped,skipped,added' -and ($r.Out -match [regex]::Escape("Path  : $cf"))) "exit=$($r.Code) $((Get-Actions $r.Out) -join ',')"
  Check 'MC-CURSOR-TREE' (Test-SameTree (Get-Tree $cf) (Get-Expected 'cursor-add.expected.json')) ''
  $before = Get-Hash $cf
  $r = Invoke-McpConfig @('--cursor', '--home-dir', $ch, '--appdata-dir', $ea, '--engine', $Eng, '--db', $Db1)
  Check 'MC-CURSOR-UNCHANGED' (($r.Code -eq 0) -and ((Get-Actions $r.Out) -join ',') -ceq 'unchanged' -and ((Get-Hash $cf) -eq $before)) "$((Get-Actions $r.Out) -join ',')"
  $r = Invoke-McpConfig @('--cursor', '--home-dir', $ch, '--appdata-dir', $ea, '--engine', $Eng, '--db', $Db1, '--remove', '--dry-run')
  Check 'MC-CURSOR-DRYRUN-REMOVE' (($r.Code -eq 0) -and ((Get-Actions $r.Out) -join ',') -ceq 'would-removed' -and ((Get-Hash $cf) -eq $before)) "$((Get-Actions $r.Out) -join ',')"
  $r = Invoke-McpConfig @('--cursor', '--home-dir', $ch, '--appdata-dir', $ea, '--engine', $Eng, '--json', '--remove')
  $j = $(try { @($r.Out | ConvertFrom-Json -NoEnumerate) } catch { @() })
  $ok = ($r.Code -eq 0) -and ($j.Count -eq 1) -and ($j[0].Count -eq 1) -and ($j[0][0].Target -eq 'Cursor') -and ($j[0][0].Action -eq 'removed') -and
        ($j[0][0].Path -eq $cf) -and ($j[0][0].Error -eq '') -and ($j[0][0].ExitCode -eq 0)
  Check 'MC-CURSOR-JSON-REMOVE' $ok "out=$($r.Out)"
  $r = Invoke-McpConfig @('--cursor', '--vscode', '--config-path', (Join-Path $Work 'x.json'))
  Check 'MC-CURSOR-CONFIGPATH-ONE' (($r.Code -eq 2) -and ($r.Err -match 'exactly one of')) "exit=$($r.Code)"
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
  Check 'MC-REAL-CURSOR' ((Get-Print $RealCursor) -eq $RealBefore.CursorPrint) "$RealCursor byte-identical (or absent both times)"
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
  if ($RealCcd) {
    $okCcd = ((Get-Print $RealCcd) -eq $RealBefore.CcdPrint) -or ((Get-ServersText $RealCcd) -ceq $RealBefore.CcdServers)
    Check 'MC-REAL-CCD' ($okCcd -and (((Get-Siblings $RealCcd) -join '|') -eq $RealBefore.CcdSibs)) `
      "$RealCcd (your CLAUDE_CONFIG_DIR) unchanged or its mcpServers identical; no .bak-*/.tmp-* beside it"
  }
  Remove-Item -LiteralPath $Work -Recurse -Force -ErrorAction SilentlyContinue
}

if ($script:Failed) { Write-Host 'FAIL -- run_mcp_config_verb' -ForegroundColor Red; exit 1 }
Write-Host 'PASS -- run_mcp_config_verb' -ForegroundColor Green
exit 0
