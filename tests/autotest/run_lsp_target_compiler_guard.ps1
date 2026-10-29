#Requires -Version 7
<#
  run_lsp_target_compiler_guard.ps1 -- 1.38 lane LSP-TARGET: the LSP gates its lint
  diagnostics by the file's TARGET COMPILER, resolved exactly as the CLI does
  (DRagLint.Lint.TargetCompiler.ResolveTargetCompiler): --target-compiler at startup
  > lint config target_compiler > project context targetCompiler (client
  initializationOptions / draglint.setContext, else .dlcontext.json) > 37.

  Probe rule: is-not-operator (modernize, needs_compiler 37, on by default). Its
  finding is published at target 37 and NOT at an older target (10.3 = 33).

  Fixture (all under $WorkDir; DRAGLINT_CONTEXT_DEFAULTS points at a fixture path):
    loose\uT.pas            `if not (X is TObject) then` -- no project anywhere
    cfg\uT.pas + drag-lint-lint.json {"target_compiler": "10.3"}
    L\L.dpr + L.dlcontext.json {targetCompiler "10.3"} + uT.pas (no .dproj)

  DEF   default session                         -> finding published (positive control)
  INIT  initializationOptions.targetCompiler 10.3 -> no finding
  SET   draglint.setContext {targetCompiler 10.3} after didOpen -> re-published without it
  CTX   .dlcontext.json targetCompiler 10.3      -> no finding
  CFG   drag-lint-lint.json target_compiler 10.3 -> no finding; it beats the client's 13
  START lsp --target-compiler 10.3               -> no finding; 13 at startup beats the client's 10.3
  BAD   targetCompiler "Delphi99"                -> finding published (default 37) + notice

  RUN RED FIRST on an engine without the wiring: INIT, SET, CTX, CFG, START and BAD's
  notice fail; DEF and the "beats" positive controls pass.
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\drag-lint-lsp-target-$PID"
)
try {
$ErrorActionPreference = 'Stop'
$script:Failed = $false
function Check($n, $ok, $d = '') {
  $s = if ($ok) { 'PASS' } else { 'FAIL' }
  $c = if ($ok) { 'Green' } else { 'Red' }
  Write-Host ("  [{0}] {1} {2}" -f $s, $n, $d) -ForegroundColor $c
  if (-not $ok) { $script:Failed = $true }
}
function Write-Ascii($p, $t) { [System.IO.File]::WriteAllText($p, $t, [System.Text.Encoding]::ASCII) }
function Lines([string[]]$a) { ($a -join "`r`n") + "`r`n" }
if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
$Exe = (Resolve-Path $Exe).Path
if (Test-Path $WorkDir) { [System.IO.Directory]::Delete($WorkDir, $true) }
foreach ($d in 'loose', 'cfg', 'L') { New-Item -ItemType Directory -Force "$WorkDir\$d" | Out-Null }
$env:DRAGLINT_CONTEXT_DEFAULTS = "$WorkDir\no-defaults.json"   # never the user's real file

$unit = Lines @('unit uT;', 'interface', 'procedure Probe(X: TObject);', 'implementation',
  'procedure Probe(X: TObject);', 'begin', '  if not (X is TObject) then', '    Exit;', 'end;', 'end.')
foreach ($d in 'loose', 'cfg', 'L') { Write-Ascii "$WorkDir\$d\uT.pas" $unit }
Write-Ascii "$WorkDir\cfg\drag-lint-lint.json" '{ "target_compiler": "10.3" }'
Write-Ascii "$WorkDir\L\L.dpr" (Lines @('program L;', 'uses uT;', 'begin', 'end.'))
Write-Ascii "$WorkDir\L\L.dlcontext.json" ((@{ schema = 1; project = "$WorkDir\L\L.dpr"; platform = 'Win64'; config = 'Debug'
  targetCompiler = '10.3'; source = @{ file = "$WorkDir\L\L.dpr"; sha1 = '' } } | ConvertTo-Json -Depth 5))

$db = "$WorkDir\fixture.sqlite"
& $Exe index "$WorkDir\loose" --db $db 2>&1 | Out-Null
Check 'SETUP: fixture index built' (Test-Path $db)

function Uri($p) { 'file:///' + ($p -replace '\\', '/') }
function Frame($obj) {
  $j = $obj | ConvertTo-Json -Depth 20 -Compress
  return "Content-Length: $([System.Text.Encoding]::UTF8.GetByteCount($j))`r`n`r`n$j"
}
function Read-Frames([string]$Out) {
  $res = @(); $i = 0
  while ($true) {
    $m = [regex]::Match($Out.Substring($i), 'Content-Length:\s*(\d+)\r\n\r\n')
    if (-not $m.Success) { break }
    $start = $i + $m.Index + $m.Length
    $len = [int]$m.Groups[1].Value
    if ($start + $len -gt $Out.Length) { break }
    $res += ($Out.Substring($start, $len) | ConvertFrom-Json)
    $i = $start + $len
  }
  return $res
}
# One session: open $file, optional extra frames after didOpen; returns the is-not-operator
# count of the LAST publishDiagnostics for the file, the draglint/context notices and showMessages.
function Session($file, $initOptions = $null, [object[]]$extra = @(), [string[]]$startArgs = @()) {
  $u = Uri $file
  $init = @{ processId = $null; rootUri = $null; capabilities = @{} }
  if ($initOptions) { $init.initializationOptions = $initOptions }
  $msgs = (Frame @{ jsonrpc = '2.0'; id = 1; method = 'initialize'; params = $init }) +
          (Frame @{ jsonrpc = '2.0'; method = 'initialized'; params = @{} }) +
          (Frame @{ jsonrpc = '2.0'; method = 'textDocument/didOpen'; params = @{ textDocument = @{ uri = $u; languageId = 'pascal'; version = 1; text = [System.IO.File]::ReadAllText($file) } } })
  foreach ($x in $extra) { $msgs += (Frame $x) }
  $msgs += (Frame @{ jsonrpc = '2.0'; id = 99; method = 'shutdown'; params = @{} }) + (Frame @{ jsonrpc = '2.0'; method = 'exit'; params = @{} })
  $in = "$WorkDir\in.txt"; $so = "$WorkDir\out.txt"; $se = "$WorkDir\err.txt"
  [System.IO.File]::WriteAllText($in, $msgs, (New-Object System.Text.UTF8Encoding($false)))
  Start-Process $Exe -ArgumentList (@('lsp', '--db', $db) + $startArgs) -WorkingDirectory $WorkDir `
    -RedirectStandardInput $in -RedirectStandardOutput $so -RedirectStandardError $se -NoNewWindow -Wait | Out-Null
  $frames = @(Read-Frames ([System.IO.File]::ReadAllText($so)))
  $pubs = @($frames | Where-Object { $_.method -eq 'textDocument/publishDiagnostics' -and $_.params.uri -eq $u })
  $last = if ($pubs.Count -gt 0) { $pubs[-1] } else { $null }
  $n = if ($last) { @($last.params.diagnostics | Where-Object { $_.code -eq 'is-not-operator' }).Count } else { -1 }
  return @{ IsNot = $n; Pubs = $pubs.Count
    Notices  = @($frames | Where-Object { $_.method -eq 'draglint/context' } | ForEach-Object { [string]$_.params.notice })
    Messages = @($frames | Where-Object { $_.method -eq 'window/showMessage' } | ForEach-Object { [string]$_.params.message }) }
}

$loose = "$WorkDir\loose\uT.pas"
Write-Host 'DEF: default target 37 -> the modernize finding is published' -ForegroundColor Cyan
$s = Session $loose
Check 'DEF (PC): is-not-operator published at 37' ($s.IsNot -eq 1) "count=$($s.IsNot)"

Write-Host 'INIT: initializationOptions.targetCompiler' -ForegroundColor Cyan
$s = Session $loose -initOptions @{ targetCompiler = '10.3' }
Check 'INIT: 10.3 drops is-not-operator' ($s.IsNot -eq 0) "count=$($s.IsNot)"
$s = Session $loose -initOptions @{ targetCompiler = '13' }
Check 'INIT (PC): 13 keeps is-not-operator' ($s.IsNot -eq 1) "count=$($s.IsNot)"

Write-Host 'SET: draglint.setContext after didOpen re-publishes under the new target' -ForegroundColor Cyan
$set = @{ jsonrpc = '2.0'; id = 5; method = 'workspace/executeCommand'
  params = @{ command = 'draglint.setContext'; arguments = @(@{ targetCompiler = '10.3' }) } }
$s = Session $loose -extra @($set)
Check 'SET: re-published (2 publishes)' ($s.Pubs -ge 2) "pubs=$($s.Pubs)"
Check 'SET: last publish has no is-not-operator' ($s.IsNot -eq 0) "count=$($s.IsNot)"

Write-Host 'CTX: .dlcontext.json targetCompiler' -ForegroundColor Cyan
$s = Session "$WorkDir\L\uT.pas"
Check 'CTX: 10.3 from L.dlcontext.json drops is-not-operator' ($s.IsNot -eq 0) "count=$($s.IsNot)"

Write-Host 'CFG: drag-lint-lint.json target_compiler (beats the context)' -ForegroundColor Cyan
$s = Session "$WorkDir\cfg\uT.pas"
Check 'CFG: config 10.3 drops is-not-operator' ($s.IsNot -eq 0) "count=$($s.IsNot)"
$s = Session "$WorkDir\cfg\uT.pas" -initOptions @{ targetCompiler = '13' }
Check 'CFG: config 10.3 beats the client''s 13' ($s.IsNot -eq 0) "count=$($s.IsNot)"

Write-Host 'START: lsp --target-compiler (beats config + context)' -ForegroundColor Cyan
$s = Session $loose -startArgs @('--target-compiler', '10.3')
Check 'START: --target-compiler 10.3 drops is-not-operator' ($s.IsNot -eq 0) "count=$($s.IsNot)"
$s = Session $loose -initOptions @{ targetCompiler = '10.3' } -startArgs @('--target-compiler', '13')
Check 'START: --target-compiler 13 beats the client''s 10.3' ($s.IsNot -eq 1) "count=$($s.IsNot)"

Write-Host 'BAD: an invalid target is named, never guessed; the default applies' -ForegroundColor Cyan
$s = Session $loose -initOptions @{ targetCompiler = 'Delphi99' }
Check 'BAD (PC): is-not-operator published at the default 37' ($s.IsNot -eq 1) "count=$($s.IsNot)"
Check 'BAD: draglint/context notice names the target' (@($s.Notices | Where-Object { $_ -match 'target' -and $_ -match 'Delphi99' }).Count -ge 1) ($s.Notices -join ' | ')
Check 'BAD: showMessage names the target, once' (@($s.Messages | Where-Object { $_ -match 'Delphi99' }).Count -eq 1) ($s.Messages -join ' | ')

if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
} finally {
  $env:DRAGLINT_CONTEXT_DEFAULTS = $null
  if (Test-Path $WorkDir) { try { [System.IO.Directory]::Delete($WorkDir, $true) } catch {} }
}
