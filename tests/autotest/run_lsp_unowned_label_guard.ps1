#Requires -Version 7
<#
  run_lsp_unowned_label_guard.ps1 -- publishDiagnostics for a file NO open store
  owns carries source "drag-lint (unowned)", so the reader can see the findings
  are not backed by a project index (e.g. another team's worktree copy).

  CASE A  owned file (indexed in --db)         -> source "drag-lint" (positive control)
  CASE B  copy of a unit outside any index     -> source "drag-lint (unowned)"
  PC      both publish at least one with-statement finding (a guard that sees no
          diagnostics passes vacuously).

  RUN RED FIRST: on an engine without the label, CASE B fails; A and PC pass.
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\drag-lint-lsp-unowned-$PID"
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
if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
$Exe = (Resolve-Path $Exe).Path
if (Test-Path $WorkDir) { [System.IO.Directory]::Delete($WorkDir, $true) }
New-Item -ItemType Directory -Force "$WorkDir\owned", "$WorkDir\loose" | Out-Null

$Src = (@(
  'unit uUnowned;', '', 'interface', '', 'procedure A(X: TObject);', '', 'implementation', '',
  'procedure A(X: TObject);', 'begin', '  with X do', '    Free;', 'end;', '', 'end.'
) -join "`r`n") + "`r`n"
$ownedFile = "$WorkDir\owned\uUnowned.pas"
$looseFile = "$WorkDir\loose\uUnowned.pas"
Write-Ascii $ownedFile $Src
Write-Ascii $looseFile $Src
$db = "$WorkDir\owned.sqlite"
& $Exe index "$WorkDir\owned" --db $db 2>&1 | Out-Null
Check 'SETUP: owned index built' (Test-Path $db)

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
function Get-Sources([string]$PasFile) {
  $uri  = 'file:///' + ($PasFile -replace '\\', '/')
  $text = [System.IO.File]::ReadAllText($PasFile)
  $msgs = (Frame @{ jsonrpc='2.0'; id=1; method='initialize'; params=@{ processId=$null; rootUri=$null; capabilities=@{} } }) +
          (Frame @{ jsonrpc='2.0'; method='initialized'; params=@{} }) +
          (Frame @{ jsonrpc='2.0'; method='textDocument/didOpen'; params=@{ textDocument=@{ uri=$uri; languageId='pascal'; version=1; text=$text } } }) +
          (Frame @{ jsonrpc='2.0'; id=99; method='shutdown'; params=@{} }) +
          (Frame @{ jsonrpc='2.0'; method='exit'; params=@{} })
  $in = "$WorkDir\in.txt"; $so = "$WorkDir\out.txt"; $se = "$WorkDir\err.txt"
  [System.IO.File]::WriteAllText($in, $msgs, (New-Object System.Text.UTF8Encoding($false)))
  Start-Process $Exe -ArgumentList @('lsp', '--db', $db) -WorkingDirectory $WorkDir -RedirectStandardInput $in `
    -RedirectStandardOutput $so -RedirectStandardError $se -NoNewWindow -Wait | Out-Null
  $frames = @(Read-Frames ([System.IO.File]::ReadAllText($so)))
  $pubs = @($frames | Where-Object { $_.method -eq 'textDocument/publishDiagnostics' })
  if ($pubs.Count -eq 0) { return @() }
  return @($pubs[-1].params.diagnostics | Where-Object { $_.code -eq 'with-statement' } | ForEach-Object { [string]$_.source })
}

Write-Host 'CASE A: owned file keeps the normal source' -ForegroundColor Cyan
$a = Get-Sources $ownedFile
Check 'PC: owned file publishes a with-statement finding' ($a.Count -ge 1) "sources=[$($a -join ',')]"
Check 'A: every source is exactly "drag-lint"' ($a.Count -ge 1 -and @($a | Where-Object { $_ -ne 'drag-lint' }).Count -eq 0)
Write-Host 'CASE B: unowned file is labelled' -ForegroundColor Cyan
$b = Get-Sources $looseFile
Check 'PC: unowned file publishes a with-statement finding' ($b.Count -ge 1) "sources=[$($b -join ',')]"
Check 'B: every source is "drag-lint (unowned)"' ($b.Count -ge 1 -and @($b | Where-Object { $_ -ne 'drag-lint (unowned)' }).Count -eq 0)

if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
} finally {
  if (Test-Path $WorkDir) { try { [System.IO.Directory]::Delete($WorkDir, $true) } catch {} }
}
