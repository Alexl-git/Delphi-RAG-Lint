#Requires -Version 7
<#
  run_lsp_active_stores_guard.ps1 -- LSP-1 STORES (owner ruling D1): every LSP answer
  comes from the ACTIVE context's DB set (its project DB + its platform's library DB),
  like the Delphi IDE -- including draglint.showCallers and the --full-rules lint child,
  which used to consult EVERY store opened at startup.

  Fixture: one SHARED unit (S\uShared.pas, `uses uOnlyA`) indexed into BOTH project DBs.
    A.sqlite = A\ (uOnlyA, uCallA calls Shared) + S\      B.sqlite = B\ (uCallB calls Shared) + S\
    library-Win64.sqlite = lib\
  S\S.dlcontext.json names project S.dpr, platform Win64 and projectDb = B.sqlite, so the
  ACTIVE context of uShared.pas is project B. Session: lsp --full-rules --db A --db B --db lib.

  CALL  showCallers on Shared -> callers from B only (uCallB); uCallA (project A) absent
  LINT  didSave with --full-rules -> used-unit-not-resolvable for uOnlyA (it exists only in A;
        a child given the startup list A+B+lib resolves it and the finding vanishes)
  Positive controls: uCallB answers (callers run at all); empty-procedure-body is published by
  the full-rules child (the child ran at all).
  RUN RED FIRST on a build without the fix: CALL and LINT fail.
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\drag-lint-lsp-active-stores-$PID"
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
foreach ($d in 'A', 'B', 'S', 'lib') { New-Item -ItemType Directory -Force "$WorkDir\$d" | Out-Null }
$env:DRAGLINT_CONTEXT_DEFAULTS = "$WorkDir\no-defaults.json"   # never the user's real file

Write-Ascii "$WorkDir\A\uOnlyA.pas" (Lines @('unit uOnlyA;', 'interface', 'procedure OnlyA;', 'implementation', 'procedure OnlyA;', 'begin', 'end;', 'end.'))
Write-Ascii "$WorkDir\S\uShared.pas" (Lines @('unit uShared;', 'interface', 'uses uOnlyA;', 'procedure Shared;', 'implementation', 'procedure Shared;', 'begin', 'end;', 'end.'))
Write-Ascii "$WorkDir\A\uCallA.pas" (Lines @('unit uCallA;', 'interface', 'procedure CallA;', 'implementation', 'uses uShared;', 'procedure CallA;', 'begin', '  Shared;', 'end;', 'end.'))
Write-Ascii "$WorkDir\B\uCallB.pas" (Lines @('unit uCallB;', 'interface', 'procedure CallB;', 'implementation', 'uses uShared;', 'procedure CallB;', 'begin', '  Shared;', 'end;', 'end.'))
Write-Ascii "$WorkDir\lib\uLib.pas" (Lines @('unit uLib;', 'interface', 'procedure LibOnly;', 'implementation', 'procedure LibOnly;', 'begin', 'end;', 'end.'))
Write-Ascii "$WorkDir\S\S.dpr" (Lines @('program S;', 'uses uShared;', 'begin', 'end.'))

$dbA = "$WorkDir\A.sqlite"; $dbB = "$WorkDir\B.sqlite"; $dbL = "$WorkDir\library-Win64.sqlite"
& $Exe index "$WorkDir\S" --db $dbA 2>&1 | Out-Null
& $Exe index "$WorkDir\A" --db $dbA 2>&1 | Out-Null
& $Exe index "$WorkDir\S" --db $dbB 2>&1 | Out-Null
& $Exe index "$WorkDir\B" --db $dbB 2>&1 | Out-Null
& $Exe index "$WorkDir\lib" --db $dbL 2>&1 | Out-Null
Check 'SETUP: three fixture indexes built' ((Test-Path $dbA) -and (Test-Path $dbB) -and (Test-Path $dbL))
Write-Ascii "$WorkDir\S\S.dlcontext.json" ((@{ schema = 1; project = "$WorkDir\S\S.dpr"; platform = 'Win64'; config = 'Debug'
  projectDb = $dbB; source = @{ file = "$WorkDir\S\S.dpr"; sha1 = '' } } | ConvertTo-Json -Depth 5))

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

$file = "$WorkDir\S\uShared.pas"
$u = Uri $file
$msgs = (Frame @{ jsonrpc = '2.0'; id = 1; method = 'initialize'; params = @{ processId = $null; rootUri = $null; capabilities = @{} } }) +
        (Frame @{ jsonrpc = '2.0'; method = 'initialized'; params = @{} }) +
        (Frame @{ jsonrpc = '2.0'; method = 'textDocument/didOpen'; params = @{ textDocument = @{ uri = $u; languageId = 'pascal'; version = 1; text = [System.IO.File]::ReadAllText($file) } } })
# Shared is declared on 0-based line 3 (interface) and 5 (implementation); ask both.
$msgs += (Frame @{ jsonrpc = '2.0'; id = 10; method = 'workspace/executeCommand'; params = @{ command = 'draglint.showCallers'; arguments = @($u, 3) } })
$msgs += (Frame @{ jsonrpc = '2.0'; id = 11; method = 'workspace/executeCommand'; params = @{ command = 'draglint.showCallers'; arguments = @($u, 5) } })
$msgs += (Frame @{ jsonrpc = '2.0'; method = 'textDocument/didSave'; params = @{ textDocument = @{ uri = $u } } })
$msgs += (Frame @{ jsonrpc = '2.0'; id = 99; method = 'shutdown'; params = @{} }) + (Frame @{ jsonrpc = '2.0'; method = 'exit'; params = @{} })
$in = "$WorkDir\in.txt"; $so = "$WorkDir\out.txt"; $se = "$WorkDir\err.txt"
[System.IO.File]::WriteAllText($in, $msgs, (New-Object System.Text.UTF8Encoding($false)))
Start-Process $Exe -ArgumentList @('lsp', '--full-rules', '--db', $dbA, '--db', $dbB, '--db', $dbL) -WorkingDirectory $WorkDir `
  -RedirectStandardInput $in -RedirectStandardOutput $so -RedirectStandardError $se -NoNewWindow -Wait | Out-Null
$frames = @(Read-Frames ([System.IO.File]::ReadAllText($so)))

Write-Host 'CALL: showCallers answers from the active project only' -ForegroundColor Cyan
$uris = @()
foreach ($id in 10, 11) {
  $r = @($frames | Where-Object { $_.id -eq $id })
  if ($r.Count -gt 0 -and $null -ne $r[0].result) { $uris += @($r[0].result | ForEach-Object { [string]$_.uri }) }
}
Check 'PC: uCallB (active project B) is a caller' (@($uris | Where-Object { $_ -match 'uCallB' }).Count -ge 1) ($uris -join ', ')
Check 'CALL: uCallA (project A) is NOT a caller' (@($uris | Where-Object { $_ -match 'uCallA' }).Count -eq 0) ($uris -join ', ')

Write-Host 'LINT: the full-rules child lints against the active context set only' -ForegroundColor Cyan
$codes = @($frames | Where-Object { $_.method -eq 'textDocument/publishDiagnostics' } | Select-Object -Last 1 |
  ForEach-Object { $_.params.diagnostics } | ForEach-Object { [string]$_.code })
Check 'PC: the full-rules child ran (empty-procedure-body published)' ($codes -contains 'empty-procedure-body') ($codes -join ', ')
Check 'LINT: uOnlyA (only in project A) is unresolvable under project B' ($codes -contains 'used-unit-not-resolvable') ($codes -join ', ')

if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
} finally {
  $env:DRAGLINT_CONTEXT_DEFAULTS = $null
  if (Test-Path $WorkDir) { try { [System.IO.Directory]::Delete($WorkDir, $true) } catch {} }
}
