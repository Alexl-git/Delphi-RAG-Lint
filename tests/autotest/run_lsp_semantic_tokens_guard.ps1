<#
  run_lsp_semantic_tokens_guard.ps1 -- `textDocument/semanticTokens/full` (B5).

  WHAT THIS PINS (each part is a positive control: a handler answering
  {data: []} or a constant fails it):

    THE METHOD IS ANSWERED (RED before B5: -32601) and `initialize` advertises
    semanticTokensProvider with full = true and the legend in the EXACT order
    the unit fixes (a client decodes token types by index).

    The guard DECODES `data` (LSP relative 5-tuples) back to absolute
    (line, col, len, type, mods) and asserts, against positions computed HERE
    from the fixture text:
      - a `keyword` token at (0,0) len 4 (`unit`);
      - a `comment` token on the `// comment` line;
      - a `string` token of len 5 (`'abc'`, quotes included);
      - a `number` token of len 2 (`42`);
      - a `class` token at `TThing`'s declaration with the `declaration` bit;
      - a `method` token at `Thrice`'s declaration in the class;
      - every deltaLine >= 0, and deltaStart >= 0 on a same-line token;
      - no two tokens overlap;
      - a two-line { } comment is split into one comment token per line.
    An unknown file answers {data: []} (not an error).
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\drag-lint-semtok-$PID"
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
function WriteAnsi($path, $text) {
  $t = ($text -replace "`r`n", "`n") -replace "`n", "`r`n"
  [System.IO.File]::WriteAllText($path, $t, (New-Object System.Text.ASCIIEncoding))
}
function Frame($o) {
  $j = $o | ConvertTo-Json -Compress -Depth 10
  $n = [Text.Encoding]::UTF8.GetByteCount($j)
  return "Content-Length: $n`r`n`r`n$j"
}

if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
$Exe = (Resolve-Path $Exe).Path
if (Test-Path $WorkDir) { [System.IO.Directory]::Delete($WorkDir, $true) }
New-Item -ItemType Directory $WorkDir | Out-Null
$src = Join-Path $WorkDir 'src'; New-Item -ItemType Directory $src | Out-Null

$file = Join-Path $src 'uSem.pas'
WriteAnsi $file @'
unit uSem;
// comment line
interface

type
  TThing = class
  public
    function Thrice(AValue: Integer): Integer;
  end;

const
  CName = 'abc';

implementation

{ two-line
  comment }
function TThing.Thrice(AValue: Integer): Integer;
begin
  Result:= AValue * 3 + 42;
end;

end.
'@

$db = Join-Path $WorkDir 'sem.sqlite'
& $Exe index $src --db $db 2>&1 | Out-Null
Check 'fixture indexed' (Test-Path $db)

$lines = [System.IO.File]::ReadAllLines($file)
function LineOf([string]$pattern) {
  for ($i = 0; $i -lt $lines.Count; $i++) { if ($lines[$i] -match $pattern) { return $i } }
  return -1
}

$Legend = @('namespace','type','class','interface','enum','function','method','property','variable','parameter','keyword','comment','string','number','operator')
$TKeyword = 10; $TComment = 11; $TString = 12; $TNumber = 13; $TClass = 2; $TMethod = 6

$uri     = 'file:///' + ($file -replace '\\', '/')
$uriGone = 'file:///' + ((Join-Path $src 'NoSuchUnit.pas') -replace '\\', '/')
$m  = Frame @{ jsonrpc='2.0'; id=1; method='initialize'; params=@{ processId=$null; rootUri=$null; capabilities=@{} } }
$m += Frame @{ jsonrpc='2.0'; method='initialized'; params=@{} }
$m += Frame @{ jsonrpc='2.0'; id=11; method='textDocument/semanticTokens/full'; params=@{ textDocument=@{ uri=$uri } } }
$m += Frame @{ jsonrpc='2.0'; id=12; method='textDocument/semanticTokens/full'; params=@{ textDocument=@{ uri=$uriGone } } }
$m += Frame @{ jsonrpc='2.0'; id=2; method='shutdown'; params=@{} }
$inF  = Join-Path $WorkDir 'in.txt'
$outF = Join-Path $WorkDir 'out.txt'
[System.IO.File]::WriteAllText($inF, $m, (New-Object System.Text.ASCIIEncoding))
Start-Process $Exe -ArgumentList @('lsp', '--db', $db) -WorkingDirectory $WorkDir `
  -RedirectStandardInput $inF -RedirectStandardOutput $outF `
  -RedirectStandardError (Join-Path $WorkDir 'err.txt') -NoNewWindow -Wait | Out-Null
$init = $null; $res = @{}; $err = @{}
foreach ($mm in [regex]::Matches([System.IO.File]::ReadAllText($outF), '\{"jsonrpc".*?(?=Content-Length:|$)', 'Singleline')) {
  try { $o = $mm.Value.Trim() | ConvertFrom-Json } catch { continue }
  if ($o.id -eq 1) { $init = $o.result }
  if ($o.id -gt 10) {
    if ($null -ne $o.error) { $err[[int]$o.id] = $o.error } else { $res[[int]$o.id] = $o.result }
  }
}

$prov = $init.capabilities.semanticTokensProvider
Check 'initialize advertises semanticTokensProvider.full = true' ($null -ne $prov -and $prov.full -eq $true)
$gotTypes = if ($null -ne $prov) { @($prov.legend.tokenTypes) -join ',' } else { '' }
Check 'legend.tokenTypes in the exact order' ($gotTypes -eq ($Legend -join ',')) "got=$gotTypes"
$gotMods = if ($null -ne $prov) { @($prov.legend.tokenModifiers) -join ',' } else { '' }
Check 'legend.tokenModifiers = [declaration]' ($gotMods -eq 'declaration') "got=$gotMods"
Check 'the method is answered (not -32601)' ($res.ContainsKey(11)) $(if ($err.Count) { "error=" + (($err.Values | ForEach-Object { $_.code }) -join ',') } else { '' })
if (-not $res.ContainsKey(11)) { Write-Host 'FAIL -- nothing to assert against.' -ForegroundColor Red; exit 1 }

$data = @($res[11].data)
Check 'data is a multiple of 5 and non-empty' ($data.Count -gt 0 -and ($data.Count % 5) -eq 0) "count=$($data.Count)"
$toks = New-Object System.Collections.Generic.List[object]
$ln = 0; $col = 0; $deltasOk = $true
for ($i = 0; $i + 4 -lt $data.Count; $i += 5) {
  $dl = [int]$data[$i]; $ds = [int]$data[$i + 1]
  if ($dl -lt 0 -or ($dl -eq 0 -and $ds -lt 0) -or ($dl -gt 0 -and $ds -lt 0)) { $deltasOk = $false }
  if ($dl -gt 0) { $ln += $dl; $col = $ds } else { $col += $ds }
  $toks.Add([pscustomobject]@{ line=$ln; col=$col; len=[int]$data[$i + 2]; type=[int]$data[$i + 3]; mods=[int]$data[$i + 4] })
}
Check 'every delta is non-negative' $deltasOk
$overlap = $false
for ($i = 1; $i -lt $toks.Count; $i++) {
  $a = $toks[$i - 1]; $b = $toks[$i]
  if ($a.line -eq $b.line -and $b.col -lt ($a.col + $a.len)) { $overlap = $true }
}
Check 'no two tokens overlap' (-not $overlap)
function Has($pred) { return @($toks | Where-Object $pred).Count -gt 0 }

Check 'keyword token at (0,0) len 4 (unit)' (Has { $_.line -eq 0 -and $_.col -eq 0 -and $_.len -eq 4 -and $_.type -eq $TKeyword })
$lCom = LineOf '^// comment line'
Check 'comment token on the comment line' (Has { $_.line -eq $lCom -and $_.col -eq 0 -and $_.type -eq $TComment }) "line=$lCom"
$lStr = LineOf "CName = 'abc'"
Check 'string token of len 5 at the literal' (Has { $_.line -eq $lStr -and $_.col -eq $lines[$lStr].IndexOf("'") -and $_.len -eq 5 -and $_.type -eq $TString })
$lNum = LineOf '\+ 42;'
Check 'number token of len 2 at 42' (Has { $_.line -eq $lNum -and $_.col -eq $lines[$lNum].IndexOf('42') -and $_.len -eq 2 -and $_.type -eq $TNumber })
$lCls = LineOf '^\s*TThing = class'
Check 'class token at TThing with the declaration bit' (Has { $_.line -eq $lCls -and $_.col -eq $lines[$lCls].IndexOf('TThing') -and $_.len -eq 6 -and $_.type -eq $TClass -and ($_.mods -band 1) -eq 1 }) "line=$lCls"
$lMth = LineOf '^\s*function Thrice'
Check 'method token at Thrice in the class declaration' (Has { $_.line -eq $lMth -and $_.col -eq $lines[$lMth].IndexOf('Thrice') -and $_.len -eq 6 -and $_.type -eq $TMethod -and ($_.mods -band 1) -eq 1 }) "line=$lMth"

$lTwo = LineOf '^\{ two-line'
Check 'multi-line comment split per line (2 tokens, full line widths)' ((Has { $_.line -eq $lTwo -and $_.col -eq 0 -and $_.len -eq $lines[$lTwo].Length -and $_.type -eq $TComment }) -and (Has { $_.line -eq ($lTwo + 1) -and $_.col -eq 0 -and $_.len -eq $lines[$lTwo + 1].Length -and $_.type -eq $TComment })) "line=$lTwo"
$gone = $res[12]
Check 'unknown file answers {data: []} (not an error)' ($res.ContainsKey(12) -and -not $err.ContainsKey(12) -and $null -ne $gone -and @($gone.data).Count -eq 0 -and ($gone.PSObject.Properties.Name -contains 'data'))

if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'PASS' -ForegroundColor Green
exit 0
} finally {
  if (Test-Path $WorkDir) { try { [System.IO.Directory]::Delete($WorkDir, $true) } catch { } }
}
