#Requires -Version 7
<#
  run_lsp_hover_directives_no_doc_guard.ps1 -- LSP task C3.

  The LSP hover only built Phase-2 fact lines (Directives:, Complexity:, ...)
  when the symbol had a doc row (`if Doc.HasContent`). An UNDOCUMENTED routine
  declared `procedure VirtStd; virtual; stdcall;` therefore showed no Directives line
  in the IDE although the index stores them and the CLI `hover` prints them.

  ORDER: (1) PREMISE -- CLI hover prints the Directives line, so the index has
  the facts (else the guard would test the wrong layer). (2) LSP hover on the
  undocumented V contains it. (3) NEGATIVE CONTROL -- hover on undocumented
  Plain does NOT. (4) POSITIVE CONTROL -- a DOCUMENTED symbol still shows the
  same line (the unchanged doc path).

  RED (pre-change engine): check (2) fails; (1), (3), (4) pass.
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\drag-lint-hover-dir-nodoc-guard-$PID"
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
function Frame($obj) {
  $j = $obj | ConvertTo-Json -Compress -Depth 12
  $n = [System.Text.Encoding]::UTF8.GetByteCount($j)
  return "Content-Length: $n`r`n`r`n$j"
}
if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
$Exe = (Resolve-Path $Exe).Path
if (Test-Path $WorkDir) { [System.IO.Directory]::Delete($WorkDir, $true) }
New-Item -ItemType Directory $WorkDir | Out-Null
$src = Join-Path $WorkDir 'src'
New-Item -ItemType Directory $src | Out-Null

$text = @'
unit uHovNoDoc;

interface

type
  TKit = class(TObject)
  public
    procedure VirtStd; virtual; stdcall;
    procedure Plain;
    /// <summary>A documented virtual routine.</summary>
    procedure Documented; virtual;
    procedure Ovl(A: Integer); overload; virtual; stdcall;
    procedure Ovl(const S: string); overload; virtual; stdcall;
  end;

implementation

procedure TKit.VirtStd;
begin
end;

procedure TKit.Plain;
begin
end;

procedure TKit.Documented;
begin
end;

procedure TKit.Ovl(A: Integer);
begin
end;

procedure TKit.Ovl(const S: string);
begin
end;

end.
'@
$file = Join-Path $src 'uHovNoDoc.pas'
WriteAnsi $file $text
$db = Join-Path $WorkDir 'hov.sqlite'
$null = & $Exe index $src --db $db 2>$null
Check 'index exits 0' ($LASTEXITCODE -eq 0) "exit=$LASTEXITCODE"

Write-Host ''
Write-Host 'PREMISE: the index holds the facts (CLI hover)' -ForegroundColor Cyan
$cli = (& $Exe hover --qname uHovNoDoc.TKit.VirtStd --db $db --format md 2>$null) -join "`n"
Check 'CLI hover on V prints Directives: virtual; stdcall' ($cli -match 'Directives: virtual; stdcall') "got: [$cli]"

$lines = $text -split "`r?`n"
function Col0([string]$needle, [string]$word) {
  for ($i = 0; $i -lt $lines.Count; $i++) {
    if ($lines[$i] -like $needle) { return @($i, ($lines[$i].IndexOf($word) + 1)) }
  }
  return @(0, 0)
}
function Invoke-Hover([int]$Line0, [int]$Char0) {
  $uri = 'file:///' + ($file -replace '\\', '/')
  $msgs  = Frame @{ jsonrpc = '2.0'; id = 1; method = 'initialize'; params = @{ processId = $null; rootUri = $null; capabilities = @{} } }
  $msgs += Frame @{ jsonrpc = '2.0'; method = 'initialized'; params = @{} }
  $msgs += Frame @{ jsonrpc = '2.0'; method = 'textDocument/didOpen';
                    params = @{ textDocument = @{ uri = $uri; languageId = 'pascal'; version = 1; text = [System.IO.File]::ReadAllText($file) } } }
  $msgs += Frame @{ jsonrpc = '2.0'; id = 2; method = 'textDocument/hover';
                    params = @{ textDocument = @{ uri = $uri }; position = @{ line = $Line0; character = $Char0 } } }
  $msgs += Frame @{ jsonrpc = '2.0'; id = 3; method = 'shutdown'; params = @{} }
  $inF = Join-Path $WorkDir 'in.txt'; $outF = Join-Path $WorkDir 'out.txt'; $errF = Join-Path $WorkDir 'err.txt'
  [System.IO.File]::WriteAllText($inF, $msgs, (New-Object System.Text.ASCIIEncoding))
  Start-Process $Exe -ArgumentList @('lsp', '--db', $db) -WorkingDirectory $WorkDir `
    -RedirectStandardInput $inF -RedirectStandardOutput $outF -RedirectStandardError $errF -NoNewWindow -Wait | Out-Null
  $raw = [System.IO.File]::ReadAllText($outF)
  foreach ($m in [regex]::Matches($raw, '\{"jsonrpc".*?(?=Content-Length:|$)', 'Singleline')) {
    try { $o = $m.Value.Trim() | ConvertFrom-Json } catch { continue }
    if ($o.id -eq 2) { if ($null -eq $o.result) { return '' } else { return [string]$o.result.contents.value } }
  }
  return '<NO REPLY>'
}

Write-Host ''
Write-Host 'LSP hover' -ForegroundColor Cyan
$p = Col0 '*procedure VirtStd; virtual; stdcall;*' 'VirtStd;'
$hv = Invoke-Hover $p[0] $p[1]
Check 'LSP hover on undocumented V contains Directives: virtual; stdcall' ($hv -match 'Directives: virtual; stdcall') "got: [$hv]"
Check 'LSP hover on V still names the symbol (control: reply is a real hover)' ($hv -match 'TKit\.VirtStd') "got: [$hv]"
$p = Col0 '*procedure Plain;*' 'Plain'
$hp = Invoke-Hover $p[0] $p[1]
Check 'NEGATIVE: hover on Plain has NO Directives:' (($hp -match 'TKit\.Plain') -and ($hp -notmatch 'Directives:')) "got: [$hp]"
$p = Col0 '*procedure Documented; virtual;*' 'Documented'
$hd = Invoke-Hover $p[0] $p[1]
Check 'POSITIVE: documented symbol still shows Directives: virtual' ($hd -match 'Directives: virtual') "got: [$hd]"

# ---- T5 (group-4 lane T): C3 facts block only when exactly ONE symbol matches ----
# Both Ovl overloads carry `virtual; stdcall`, so a hover that built the facts from the first
# match would print `Directives:`. The merged multi-overload hover must not (the facts of one
# overload would be presented as the facts of the name). Control: the same directives on the
# single-symbol VirtStd DO print (checked above), and the hover is a real one (names Ovl).
$p = Col0 '*procedure Ovl(A: Integer);*' 'Ovl'
$ho = Invoke-Hover $p[0] $p[1]
Check 'T5 CONTROL: hover on the overloaded name is a real hover (names TKit.Ovl)' ($ho -match 'TKit\.Ovl') "got: [$ho]"
Check 'T5 multi-overload hover has NO Directives: block (facts only for exactly one symbol)' ($ho -notmatch 'Directives:') "got: [$ho]"
$p = Col0 '*procedure Ovl(const S: string);*' 'Ovl'
$ho2 = Invoke-Hover $p[0] $p[1]
Check 'T5 hover on the second overload also has NO Directives: block' (($ho2 -match 'TKit\.Ovl') -and ($ho2 -notmatch 'Directives:')) "got: [$ho2]"

if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'PASS' -ForegroundColor Green
exit 0
} finally {
  if ($WorkDir -and (Test-Path $WorkDir)) { try { [System.IO.Directory]::Delete($WorkDir, $true) } catch { $null = $_ } }
}
