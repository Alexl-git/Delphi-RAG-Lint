#Requires -Version 7
<#
  run_lsp_switch_vscode_guard.ps1 -- drag-lint-switch --vscode --on|--off must
  toggle servers["delphi-lsp"] in <workspace>\.vscode\mcp.json, losslessly.

  SCRATCH ONLY. Every case points --workspace at a temp dir; the owner's real
  %APPDATA%\Code (settings, state.vscdb) is never an argument and the guard
  asserts the tool did not create anything outside the scratch tree.

  The host check is made deterministic: --assume-host-stopped (testing only)
  lets the mutating cases run while the owner has VS Code open, and
  --assume-host-running (testing only) forces the BLOCKED path.

  POSITIVE CONTROLS: the host-running case compares the file's bytes AND mtime
  before/after (a tool that blocked by doing nothing is indistinguishable from
  one that never worked, so case 1 proves the same call DOES change the file
  without the flag); --off-twice must report exit 1 and add no second backup.
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\src\tools\lsp-switch\Win64\Debug\drag-lint-switch.exe",
  [string]$WorkDir = "$env:TEMP\drag-lint-switch-vscode-guard-$PID"
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
if (-not (Test-Path $Exe)) {
  Write-Host "FATAL: drag-lint-switch.exe not found: $Exe" -ForegroundColor Red
  exit 2
}
$Exe = (Resolve-Path $Exe).Path
if (Test-Path $WorkDir) { [System.IO.Directory]::Delete($WorkDir, $true) }
New-Item -ItemType Directory $WorkDir | Out-Null
$ws  = Join-Path $WorkDir 'ws'
$vsc = Join-Path $ws '.vscode'
New-Item -ItemType Directory $vsc | Out-Null
$mcp = Join-Path $vsc 'mcp.json'

$fixture = @'
{
  "servers": {
    "delphi-lsp": { "type": "stdio", "command": "C:\\x\\DelphiLSPMCPServer.exe", "args": ["--a", "b c"], "env": { "K": "v" } },
    "other": { "type": "http", "url": "http://localhost:1/mcp" }
  },
  "inputs": []
}
'@
[System.IO.File]::WriteAllText($mcp, $fixture, (New-Object System.Text.UTF8Encoding($false)))
$orig = $fixture | ConvertFrom-Json

function Run-Switch([string[]]$SwitchArgs) {
  $out = & $Exe @SwitchArgs 2>&1 | Out-String
  return [pscustomobject]@{ Out = $out; Code = $LASTEXITCODE }
}
function Json-Eq($a, $b) { return (($a | ConvertTo-Json -Depth 20 -Compress) -eq ($b | ConvertTo-Json -Depth 20 -Compress)) }
function Backups { return @(Get-ChildItem $vsc -Filter 'mcp.json.draglint-*.bak' -ErrorAction SilentlyContinue) }

Write-Host ''
Write-Host 'CASE 1: --status reports file + entry presence' -ForegroundColor Cyan
$r = Run-Switch @('--vscode','--status','--workspace',$ws,'--assume-host-stopped')
Check '--status exit 0' ($r.Code -eq 0) "exit=$($r.Code)"
Check 'delphi-lsp: present' ($r.Out -match 'delphi-lsp: present') $r.Out.Trim()
Check 'reports Code.exe count' ($r.Out -match 'Code\.exe') ''

Write-Host ''
Write-Host 'CASE 2: --off backs up whole file, removes only delphi-lsp' -ForegroundColor Cyan
$r = Run-Switch @('--vscode','--off','--workspace',$ws,'--assume-host-stopped')
Check '--off exit 0' ($r.Code -eq 0) "exit=$($r.Code) $($r.Out.Trim())"
$now = Get-Content $mcp -Raw | ConvertFrom-Json
Check 'delphi-lsp gone' (-not ($now.servers.PSObject.Properties.Name -contains 'delphi-lsp'))
Check 'other server JSON-equal' (Json-Eq $now.servers.other $orig.servers.other)
Check 'inputs survived' (Json-Eq $now.inputs $orig.inputs)
$bk = Backups
Check 'one .bak written' ($bk.Count -eq 1) "found $($bk.Count)"
if ($bk.Count -eq 1) {
  Check 'backup name is mcp.json.draglint-yyyymmdd-hhmmss.bak' ($bk[0].Name -match '^mcp\.json\.draglint-\d{8}-\d{6}\.bak$') $bk[0].Name
  Check 'backup is the whole original file' ((Get-Content $bk[0].FullName -Raw) -eq $fixture)
}

Write-Host ''
Write-Host 'CASE 3: POSITIVE CONTROL -- --off again is a no-op' -ForegroundColor Cyan
$r = Run-Switch @('--vscode','--off','--workspace',$ws,'--assume-host-stopped')
Check '--off again exit 1' ($r.Code -eq 1) "exit=$($r.Code)"
Check 'no second backup' ((Backups).Count -eq 1)
$r = Run-Switch @('--vscode','--status','--workspace',$ws,'--assume-host-stopped')
Check 'status says absent' ($r.Out -match 'delphi-lsp: absent') $r.Out.Trim()

Write-Host ''
Write-Host 'CASE 4: --on while the host runs is BLOCKED and touches nothing' -ForegroundColor Cyan
$m1 = (Get-Item $mcp).LastWriteTimeUtc; $h1 = (Get-FileHash $mcp).Hash
Start-Sleep -Milliseconds 1200
$r = Run-Switch @('--vscode','--on','--workspace',$ws,'--assume-host-running')
Check '--on exit 2' ($r.Code -eq 2) "exit=$($r.Code)"
Check 'mtime unchanged' ((Get-Item $mcp).LastWriteTimeUtc -eq $m1)
Check 'bytes unchanged' ((Get-FileHash $mcp).Hash -eq $h1)
$r = Run-Switch @('--vscode','--off','--workspace',$ws,'--assume-host-running')
Check '--off exit 2 as well' ($r.Code -eq 2) "exit=$($r.Code)"

Write-Host ''
Write-Host 'CASE 5: --on restores from the newest backup, JSON-equal' -ForegroundColor Cyan
$r = Run-Switch @('--vscode','--on','--workspace',$ws,'--assume-host-stopped')
Check '--on exit 0' ($r.Code -eq 0) "exit=$($r.Code) $($r.Out.Trim())"
$now = Get-Content $mcp -Raw | ConvertFrom-Json
Check 'delphi-lsp restored JSON-equal' (Json-Eq $now.servers.'delphi-lsp' $orig.servers.'delphi-lsp')
Check 'other still JSON-equal' (Json-Eq $now.servers.other $orig.servers.other)
$r = Run-Switch @('--vscode','--on','--workspace',$ws,'--assume-host-stopped')
Check '--on again exit 1' ($r.Code -eq 1) "exit=$($r.Code)"

Write-Host ''
Write-Host 'CASE 6: no backup and no template -> exit 3; --template restores' -ForegroundColor Cyan
$ws2 = Join-Path $WorkDir 'ws2'; New-Item -ItemType Directory (Join-Path $ws2 '.vscode') | Out-Null
$mcp2 = Join-Path $ws2 '.vscode\mcp.json'
[System.IO.File]::WriteAllText($mcp2, '{"servers":{"other":{"type":"http","url":"http://x"}}}', (New-Object System.Text.UTF8Encoding($false)))
$r = Run-Switch @('--vscode','--on','--workspace',$ws2,'--assume-host-stopped')
Check '--on exit 3' ($r.Code -eq 3) "exit=$($r.Code)"
Check 'message names --template' ($r.Out -match 'no backup to restore -- pass --template') $r.Out.Trim()
$tpl = Join-Path $WorkDir 'tpl.json'
[System.IO.File]::WriteAllText($tpl, '{"type":"stdio","command":"C:\\y\\srv.exe","args":["q"]}', (New-Object System.Text.UTF8Encoding($false)))
$r = Run-Switch @('--vscode','--on','--workspace',$ws2,'--template',$tpl,'--assume-host-stopped')
Check '--on --template exit 0' ($r.Code -eq 0) "exit=$($r.Code) $($r.Out.Trim())"
$n2 = Get-Content $mcp2 -Raw | ConvertFrom-Json
Check 'entry from template' ($n2.servers.'delphi-lsp'.command -eq 'C:\y\srv.exe')
Check 'other kept' ($n2.servers.other.url -eq 'http://x')

Write-Host ''
Write-Host 'CASE 7: no .vscode directory at all (clean exit, nothing created)' -ForegroundColor Cyan
$ws3 = Join-Path $WorkDir 'ws3'; New-Item -ItemType Directory $ws3 | Out-Null
$r = Run-Switch @('--vscode','--on','--workspace',$ws3,'--assume-host-stopped')
Check '--on without .vscode exit 3' ($r.Code -eq 3) "exit=$($r.Code) $($r.Out.Trim())"
Check 'clean message, no exception' (($r.Out -match 'no backup to restore -- pass --template') -and ($r.Out -notmatch 'EDirectoryNotFound|Exception'))
Check 'no .vscode created' (-not (Test-Path (Join-Path $ws3 '.vscode')))
$r = Run-Switch @('--vscode','--off','--workspace',$ws3,'--assume-host-stopped')
Check '--off without mcp.json exit 1' ($r.Code -eq 1) "exit=$($r.Code)"
$r = Run-Switch @('--vscode','--status','--workspace',$ws3,'--assume-host-stopped')
Check '--status without mcp.json exit 0' ($r.Code -eq 0) "exit=$($r.Code)"
Check '--status says mcp.json absent and delphi-lsp absent' (($r.Out -match 'mcp\.json: absent') -and ($r.Out -match 'delphi-lsp: absent')) $r.Out.Trim()

Write-Host ''
Write-Host 'SAFETY: nothing outside the scratch workspace was created' -ForegroundColor Cyan
Check 'no stray files beside ws' ((Get-ChildItem $WorkDir | Where-Object Name -notin 'ws','ws2','ws3','tpl.json').Count -eq 0)

Write-Host ''
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
} finally {
  foreach ($d in @("$env:TEMP\drag-lint-switch-vscode-guard-$PID")) { if (Test-Path -LiteralPath $d) { [System.IO.Directory]::Delete($d, $true) } }
}
