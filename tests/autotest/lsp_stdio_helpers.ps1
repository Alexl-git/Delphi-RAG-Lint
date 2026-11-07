# Shared helpers for the 145 lsp-lane stdio guards (dot-sourced). 7-bit ASCII, CRLF.
# Check / WriteAnsi / Frame / LspSession / PosParams. LspSession runs `lsp --db <db>` over redirected stdio,
# sends the given requests (ids 11..) between initialize and the closing request and returns
# @{ init; res = id -> ,@(result); err = id -> error }.
function Check($n, $ok, $d = '') {
  $s = if ($ok) { 'PASS' } else { 'FAIL' }
  $c = if ($ok) { 'Green' } else { 'Red' }
  Write-Host ("  [{0}] {1} {2}" -f $s, $n, $d) -ForegroundColor $c
  if (-not $ok) { $script:Failed = $true }
}
function WriteAnsi($path, $text) {
  $t = ($text -replace "`r`n", "`n") -replace "`n", "`r`n"
  [System.IO.File]::WriteAllText($path, $t, (New-Object System.Text.ASCIIEncoding))
}
function Frame($o) {
  $j = $o | ConvertTo-Json -Compress -Depth 20
  $n = [Text.Encoding]::UTF8.GetByteCount($j)
  return "Content-Length: $n`r`n`r`n$j"
}
function LspSession([string]$Exe, [string]$WorkDir, [string]$Db, [array]$Reqs) {
  $m  = Frame @{ jsonrpc='2.0'; id=1; method='initialize'; params=@{ processId=$null; rootUri=$null; capabilities=@{} } }
  $m += Frame @{ jsonrpc='2.0'; method='initialized'; params=@{} }
  $id = 10
  foreach ($q in $Reqs) { $id++; $m += Frame @{ jsonrpc='2.0'; id=$id; method=$q.method; params=$q.params } }
  $m += Frame @{ jsonrpc='2.0'; id=2; method='shutdown'; params=@{} }
  $inF  = Join-Path $WorkDir 'in.txt'
  $outF = Join-Path $WorkDir 'out.txt'
  [System.IO.File]::WriteAllText($inF, $m, (New-Object System.Text.ASCIIEncoding))
  Start-Process $Exe -ArgumentList @('lsp', '--db', $Db) -WorkingDirectory $WorkDir `
    -RedirectStandardInput $inF -RedirectStandardOutput $outF `
    -RedirectStandardError (Join-Path $WorkDir 'err.txt') -NoNewWindow -Wait | Out-Null
  $r = @{ init = $null; res = @{}; err = @{} }
  foreach ($mm in [regex]::Matches([System.IO.File]::ReadAllText($outF), '\{"jsonrpc".*?(?=Content-Length:|$)', 'Singleline')) {
    try { $o = $mm.Value.Trim() | ConvertFrom-Json } catch { continue }
    if ($o.id -eq 1) { $r.init = $o.result }
    if ($o.id -gt 10) {
      if ($null -ne $o.error) { $r.err[[int]$o.id] = $o.error }
      else { $r.res[[int]$o.id] = ,@($o.result) }
    }
  }
  return $r
}
function PosParams([string]$Uri, [int]$Line, [int]$Col) { @{ textDocument=@{ uri=$Uri }; position=@{ line=$Line; character=$Col } } }
# True when request $Id answered a JSON null (not [] and not an error): the single element is $null.
function IsNull($R, [int]$Id) { if (-not $R.res.ContainsKey($Id)) { return $false }; $x = @($R.res[$Id][0]); return ($x.Count -eq 1 -and $null -eq $x[0]) }
