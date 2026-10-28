#Requires -Version 7
<#
  run_lsp_clear_diags_guard.ps1 -- the LSP server must CLEAR what it published.
  Without it VS Code keeps a closed or deleted file's warnings in Problems forever.

  PC   didOpen of a file with a with-statement finding -> non-empty publishDiagnostics
  A    didClose                                          -> publishDiagnostics, same uri string, empty array
  B    workspace/didChangeWatchedFiles type 3 (Deleted)  -> publishDiagnostics, same uri string, empty array
  NEG  workspace/didChangeWatchedFiles type 2 (Changed)  -> NO clearing publish for that uri

  RUN RED FIRST: on an engine without the fix A and B fail; PC and NEG pass.
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\drag-lint-lsp-cleardiag-$PID"
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
if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
$Exe = (Resolve-Path $Exe).Path
if (Test-Path $WorkDir) { [System.IO.Directory]::Delete($WorkDir, $true) }
New-Item -ItemType Directory -Force "$WorkDir\src" | Out-Null

$Src = (@(
  'unit uClear;', '', 'interface', '', 'procedure A(X: TObject);', '', 'implementation', '',
  'procedure A(X: TObject);', 'begin', '  with X do', '    Free;', 'end;', '', 'end.'
) -join "`r`n") + "`r`n"
$file = "$WorkDir\src\uClear.pas"
[System.IO.File]::WriteAllText($file, $Src, [System.Text.Encoding]::ASCII)
# A deliberately odd (but valid) uri spelling: the clearing publish must echo it verbatim.
$uri = 'file:///' + ($file -replace '\\', '/') -replace ' ', '%20'

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
# Runs a session: initialize, didOpen, then $Extra frames; returns the publishDiagnostics params in order.
function Run-Session($Extra) {
  $text = [System.IO.File]::ReadAllText($file)
  $msgs = (Frame @{ jsonrpc='2.0'; id=1; method='initialize'; params=@{ processId=$null; rootUri=$null; capabilities=@{} } }) +
          (Frame @{ jsonrpc='2.0'; method='initialized'; params=@{} }) +
          (Frame @{ jsonrpc='2.0'; method='textDocument/didOpen'; params=@{ textDocument=@{ uri=$uri; languageId='pascal'; version=1; text=$text } } })
  foreach ($e in $Extra) { $msgs += (Frame $e) }
  $msgs += (Frame @{ jsonrpc='2.0'; id=99; method='shutdown'; params=@{} }) + (Frame @{ jsonrpc='2.0'; method='exit'; params=@{} })
  $in = "$WorkDir\in.txt"; $so = "$WorkDir\out.txt"; $se = "$WorkDir\err.txt"
  [System.IO.File]::WriteAllText($in, $msgs, (New-Object System.Text.UTF8Encoding($false)))
  Start-Process $Exe -ArgumentList @('lsp') -WorkingDirectory $WorkDir -RedirectStandardInput $in `
    -RedirectStandardOutput $so -RedirectStandardError $se -NoNewWindow -Wait | Out-Null
  $frames = @(Read-Frames ([System.IO.File]::ReadAllText($so)))
  return @($frames | Where-Object { $_.method -eq 'textDocument/publishDiagnostics' } | ForEach-Object { $_.params })
}
function Empty-For($pubs, $u) { @($pubs | Where-Object { $_.uri -ceq $u -and @($_.diagnostics).Count -eq 0 }).Count }

Write-Host 'CASE A: didClose clears' -ForegroundColor Cyan
$a = Run-Session @(@{ jsonrpc='2.0'; method='textDocument/didClose'; params=@{ textDocument=@{ uri=$uri } } })
Check 'PC: didOpen publishes a non-empty diagnostics array' (@($a | Where-Object { @($_.diagnostics).Count -ge 1 }).Count -ge 1) "publishes=$($a.Count)"
Check 'A: didClose publishes an empty array for the same uri' ((Empty-For $a $uri) -ge 1)
Write-Host 'CASE B: didChangeWatchedFiles Deleted clears' -ForegroundColor Cyan
$b = Run-Session @(@{ jsonrpc='2.0'; method='workspace/didChangeWatchedFiles'; params=@{ changes=@(@{ uri=$uri; type=3 }) } })
Check 'B: type 3 publishes an empty array for the same uri' ((Empty-For $b $uri) -ge 1)
Write-Host 'CASE NEG: Changed (type 2) does not clear' -ForegroundColor Cyan
$n = Run-Session @(@{ jsonrpc='2.0'; method='workspace/didChangeWatchedFiles'; params=@{ changes=@(@{ uri=$uri; type=2 }) } })
Check 'NEG: type 2 publishes no empty array' ((Empty-For $n $uri) -eq 0)

if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
} finally {
  if (Test-Path $WorkDir) { try { [System.IO.Directory]::Delete($WorkDir, $true) } catch {} }
}