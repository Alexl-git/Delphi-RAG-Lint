#Requires -Version 7
<#
  run_lsp_code_lens_guard.ps1 -- `textDocument/codeLens` (B4).

  WHAT THIS PINS, and why each part is here rather than "it returned something":

    THE METHOD IS ANSWERED (RED before B4: -32601 method not found) and
    `initialize` advertises codeLensProvider = {resolveProvider: false}.

    THE COUNTS ARE RIGHT (positive control). Fixture call graph: Thrice x3,
    Once x1, Never x0 -> lenses titled '3 callers', '1 caller' (singular),
    '0 callers'. A handler returning a constant or zero fails.

    LINES ARE 0-BASED, computed here FROM THE FIXTURE TEXT (the routines'
    interface declaration lines); range start == end, character 0.

    THE COMMAND CONTRACT with B6: command.command = draglint.showCallers and
    command.arguments = [uri, line] where line equals the lens line.

    ROUTINES ONLY: no lens on the field / property lines.

    AN UNKNOWN FILE answers [] (not an error).
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\drag-lint-codelens-$PID"
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

$file = Join-Path $src 'uLens.pas'
WriteAnsi $file @'
unit uLens;

interface

type
  TThing = class
  private
    FCount: Integer;
  public
    procedure Thrice;
    procedure Once;
    procedure Never;
    property Count: Integer read FCount write FCount;
  end;

procedure Driver;

implementation

procedure TThing.Thrice;
begin
end;

procedure TThing.Once;
begin
end;

procedure TThing.Never;
begin
end;

procedure Driver;
var
  T: TThing;
begin
  T := TThing.Create;
  T.Thrice;
  T.Thrice;
  T.Thrice;
  T.Once;
end;

end.
'@

$db = Join-Path $WorkDir 'lens.sqlite'
& $Exe index $src --db $db 2>&1 | Out-Null
Check 'fixture indexed' (Test-Path $db)

$lines = [System.IO.File]::ReadAllLines($file)
function LineOf([string]$pattern) {
  for ($i = 0; $i -lt $lines.Count; $i++) { if ($lines[$i] -match $pattern) { return $i } }
  return -1
}

function Session([string]$uri) {
  $m  = Frame @{ jsonrpc='2.0'; id=1; method='initialize'; params=@{ processId=$null; rootUri=$null; capabilities=@{} } }
  $m += Frame @{ jsonrpc='2.0'; method='initialized'; params=@{} }
  $m += Frame @{ jsonrpc='2.0'; id=2; method='textDocument/codeLens'; params=@{ textDocument=@{ uri=$uri } } }
  $m += Frame @{ jsonrpc='2.0'; id=3; method='shutdown'; params=@{} }
  $inF  = Join-Path $WorkDir 'in.txt'
  $outF = Join-Path $WorkDir 'out.txt'
  [System.IO.File]::WriteAllText($inF, $m, (New-Object System.Text.ASCIIEncoding))
  Start-Process $Exe -ArgumentList @('lsp', '--db', $db) -WorkingDirectory $WorkDir `
    -RedirectStandardInput $inF -RedirectStandardOutput $outF `
    -RedirectStandardError (Join-Path $WorkDir 'err.txt') -NoNewWindow -Wait | Out-Null
  $r = @{ init = $null; lens = $null; err = $null }
  foreach ($mm in [regex]::Matches([System.IO.File]::ReadAllText($outF), '\{"jsonrpc".*?(?=Content-Length:|$)', 'Singleline')) {
    try { $o = $mm.Value.Trim() | ConvertFrom-Json } catch { continue }
    if ($o.id -eq 1) { $r.init = $o.result }
    if ($o.id -eq 2) {
      if ($null -ne $o.error) { $r.err = $o.error }
      else { $r.lens = ,@($o.result) }   # ,@() keeps an empty [] distinct from "no answer"
    }
  }
  return $r
}

$uri = 'file:///' + ($file -replace '\\', '/')
$r = Session $uri
$cap = $r.init.capabilities.codeLensProvider
Check 'initialize advertises codeLensProvider {resolveProvider:false}' ($null -ne $cap -and $cap.resolveProvider -eq $false) "caps=$($r.init.capabilities | ConvertTo-Json -Compress -Depth 3)"
Check 'the method answered (not -32601)' ($null -ne $r.lens) $(if ($r.err) { "error=$($r.err.code) $($r.err.message)" } else { '' })
if ($null -eq $r.lens) { Write-Host 'FAIL -- nothing to assert against.' -ForegroundColor Red; exit 1 }

$lens = @($r.lens[0])
Check 'exactly four lenses: the three methods plus Driver (routines only)' ($lens.Count -eq 4) "got=$($lens.Count)"
$want = @{ 'procedure Thrice;' = '3 callers'; 'procedure Once;' = '1 caller'; 'procedure Never;' = '0 callers' }
foreach ($k in $want.Keys) {
  $ln = LineOf ('^\s*' + [regex]::Escape($k))
  $l = @($lens | Where-Object { $_.range.start.line -eq $ln }) | Select-Object -First 1
  Check "lens on the '$k' declaration line ($ln)" ($null -ne $l)
  if ($null -eq $l) { continue }
  Check "title of '$k' is '$($want[$k])'" ($l.command.title -eq $want[$k]) "got=$($l.command.title)"
  Check "range of '$k' is zero-width at character 0" ($l.range.start.character -eq 0 -and $l.range.end.character -eq 0 -and $l.range.end.line -eq $ln)
  Check "command of '$k' is draglint.showCallers" ($l.command.command -eq 'draglint.showCallers')
  $a = @($l.command.arguments)
  Check "arguments of '$k' = [uri, line]" ($a.Count -eq 2 -and $a[1] -eq $ln -and ([string]$a[0]) -like 'file:*uLens.pas') "got=$($a -join '|')"
}
$fieldLn = LineOf '^\s*FCount: Integer;'
$propLn  = LineOf '^\s*property Count'
Check 'no lens on the field or property line' (-not (@($lens | Where-Object { $_.range.start.line -in @($fieldLn, $propLn) }).Count))

$r2 = Session 'file:///c%3A/no/such/dir/Nope.pas'
Check 'unknown URI answers [] (not an error)' ($null -ne $r2.lens -and @($r2.lens[0]).Count -eq 0 -and $null -eq $r2.err) $(if ($r2.err) { "error=$($r2.err.code)" } else { '' })

if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'PASS' -ForegroundColor Green
exit 0
} finally {
  if (Test-Path $WorkDir) { try { [System.IO.Directory]::Delete($WorkDir, $true) } catch { } }
}
