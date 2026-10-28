#Requires -Version 7
<#
  run_lsp_semantic_tokens_lone_cr_guard.ps1 -- semantic tokens must sit on the
  line/column an LSP client counts (LSP: CR, LF and CRLF are each a line end).

  THE DEFECT THIS PINS (LSP backlog C16):
    NormalizeLoneCR is length-preserving (lone CR -> LF, same byte offsets), but
    the tree is parsed from the NORMALISED text while Feature.SemanticTokens built
    its byte->line/col map (and the declaration line split) from the RAW bytes,
    where only LF ends a line. Every token after a lone CR then landed one line
    too high per lone CR, against both the client and the index.

  SPEC: the same program written with lone-CR line ends (L1..L5) and with CRLF
  line ends yields the IDENTICAL decoded token list (positive control: tokens
  exist), and `begin` is on line 6.
  Run from any CWD, pwsh 7.
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\drag-lint-lsp-c16-$PID"
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
New-Item -ItemType Directory -Force $WorkDir | Out-Null

$lines = @('unit uCr;', 'interface', 'procedure P;', 'implementation', 'procedure P;', 'begin', 'end;', 'end.')
function WriteFixture($dir, $seps) {   # $seps[i] = separator after line i+1
  New-Item -ItemType Directory -Force $dir | Out-Null
  $sb = New-Object System.Text.StringBuilder
  for ($i = 0; $i -lt $lines.Count; $i++) { [void]$sb.Append($lines[$i]); [void]$sb.Append($seps[$i]) }
  $f = Join-Path $dir 'uCr.pas'
  [System.IO.File]::WriteAllBytes($f, [System.Text.Encoding]::ASCII.GetBytes($sb.ToString()))
  return $f
}
$CR = "`r"; $CRLF = "`r`n"
$fCr   = WriteFixture (Join-Path $WorkDir 'cr')   @($CRLF, $CRLF, $CR, $CR, $CR, $CRLF, $CRLF, $CRLF)
$fCrlf = WriteFixture (Join-Path $WorkDir 'crlf') @($CRLF, $CRLF, $CRLF, $CRLF, $CRLF, $CRLF, $CRLF, $CRLF)
$raw = [System.IO.File]::ReadAllBytes($fCr)
Check 'fixture holds lone CRs (bytes)' (@(0..($raw.Length-2) | Where-Object { $raw[$_] -eq 13 -and $raw[$_+1] -ne 10 }).Count -eq 3)

# ---------- LSP plumbing ----------
function Frame($o) {
  $j = $o | ConvertTo-Json -Depth 20 -Compress
  return "Content-Length: $([System.Text.Encoding]::UTF8.GetByteCount($j))`r`n`r`n$j"
}
# One session per fixture; returns the semantic-token result.
function LspTokens([string]$File, [string]$Db) {
  $uri = 'file:///' + ($File -replace '\\', '/')
  $td = @{ uri = $uri }
  $m  = Frame @{ jsonrpc='2.0'; id=1; method='initialize'; params=@{ processId=$null; rootUri=$null; capabilities=@{} } }
  $m += Frame @{ jsonrpc='2.0'; method='initialized'; params=@{} }
  $m += Frame @{ jsonrpc='2.0'; id=11; method='textDocument/semanticTokens/full'; params=@{ textDocument=$td } }
  $m += Frame @{ jsonrpc='2.0'; id=2; method='shutdown'; params=@{} }
  $m += Frame @{ jsonrpc='2.0'; method='exit'; params=@{} }
  $inF = Join-Path $WorkDir 'in.txt'; $outF = Join-Path $WorkDir 'out.txt'
  [System.IO.File]::WriteAllText($inF, $m, (New-Object System.Text.ASCIIEncoding))
  Start-Process $Exe -ArgumentList @('lsp', '--db', $Db) -WorkingDirectory $WorkDir `
    -RedirectStandardInput $inF -RedirectStandardOutput $outF `
    -RedirectStandardError (Join-Path $WorkDir 'err.txt') -NoNewWindow -Wait | Out-Null
  $out = [System.IO.File]::ReadAllText($outF)
  $i = 0
  while ($true) {
    $mm = [regex]::Match($out.Substring($i), 'Content-Length:\s*(\d+)\r\n\r\n')
    if (-not $mm.Success) { break }
    $start = $i + $mm.Index + $mm.Length; $len = [int]$mm.Groups[1].Value
    if ($start + $len -gt $out.Length) { break }
    $o = $out.Substring($start, $len) | ConvertFrom-Json
    if ($null -ne $o.id -and [int]$o.id -eq 11) { return $o.result }
    $i = $start + $len
  }
  return $null
}
# Decoded tokens -> 'line:col:len:type' strings (absolute, 1-based line).
function Decode($r) {
  $res = @(); if ($null -eq $r) { return ,$res }
  $data = @($r.data); $ln = 0; $col = 0
  for ($k = 0; $k + 4 -lt $data.Count; $k += 5) {
    if ([int]$data[$k] -ne 0) { $col = 0 }
    $ln += [int]$data[$k]; $col += [int]$data[$k+1]
    $res += ('{0}:{1}:{2}:{3}' -f ($ln + 1), $col, $data[$k+2], $data[$k+3])
  }
  return ,$res
}
$tokens = @{}
foreach ($v in 'cr', 'crlf') {
  $dir = Join-Path $WorkDir $v
  $db = Join-Path $WorkDir "$v.sqlite"
  & $Exe index $dir --db $db 2>&1 | Out-Null
  if (-not (Test-Path $db)) { Write-Host "FATAL: $v fixture not indexed" -ForegroundColor Red; exit 2 }
  $tokens[$v] = Decode (LspTokens (Join-Path $dir 'uCr.pas') $db)
}
$a = $tokens['cr']; $b = $tokens['crlf']
Check 'CRLF control: tokens are produced' ($b.Count -gt 5) ("n=" + $b.Count)
Check 'CRLF control: begin keyword on line 6' (@($b | Where-Object { $_ -like '6:0:5:*' }).Count -eq 1) ($b -join ' ')
Check 'lone-CR file: begin keyword on line 6' (@($a | Where-Object { $_ -like '6:0:5:*' }).Count -eq 1) ($a -join ' ')
Check 'lone-CR file: token list identical to the CRLF file' (($a -join ' ') -eq ($b -join ' ')) ("cr=[" + ($a -join ' ') + "] crlf=[" + ($b -join ' ') + "]")

Write-Host ''
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
} finally {
  if (Test-Path -LiteralPath $WorkDir) { Remove-Item -LiteralPath $WorkDir -Recurse -Force -ErrorAction SilentlyContinue }
}
