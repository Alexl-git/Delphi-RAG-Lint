<#
  run_mcp_get_impact_qname.ps1 -- the MCP tool get_impact walks the qname it is
  given, as `impact --qname` does.

  WHY. get_impact passed only the qname's LAST segment to FindTransitiveCallers,
  so `uLib.TA.Run` walked every routine named Run -- TA.Run's caller and TB.Run's
  alike. FindTransitiveCallers takes a qualified name (every overload of it) and
  walks the resolved call graph from there.

  Checks:
    Q1  get_impact uLib.TA.Run (depth 1) counts its one caller, not every Run
    Q2  CONTROL: `impact --qname uLib.TA.Run --depth 1` (CLI) agrees

  Run from a NEUTRAL CWD, pwsh 7.
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe",
  [string]$WorkDir = "C:\TEMP\draglint_mcp_impact_$PID"
)
try {
$ErrorActionPreference = 'Stop'; $fail = $false
function Check($n, $ok, $d) {
  Write-Host ("[{0}] {1}" -f (@('FAIL', 'PASS')[[int][bool]$ok]), $n) -ForegroundColor (@('Red', 'Green')[[int][bool]$ok])
  if (-not $ok) { if ($d) { Write-Host "      $d" -ForegroundColor DarkGray }; $script:fail = $true }
}
function Write-Ascii($p, $t) { [System.IO.File]::WriteAllText($p, (($t -replace "`r`n", "`n") -replace "`n", "`r`n"), [System.Text.Encoding]::ASCII) }

$exePath = (Resolve-Path $Exe).Path
if (Test-Path $WorkDir) { Remove-Item $WorkDir -Recurse -Force }
$src = Join-Path $WorkDir 'src'
New-Item -ItemType Directory -Force $src | Out-Null

Write-Ascii (Join-Path $src 'uLib.pas') @'
unit uLib;

interface

type
  TA = class
  public
    procedure Run;
  end;

  TB = class
  public
    procedure Run;
  end;

implementation

procedure TA.Run;
begin
end;

procedure TB.Run;
begin
end;

end.
'@
Write-Ascii (Join-Path $src 'uUse.pas') @'
unit uUse;

interface

uses
  uLib;

procedure CallA;
procedure CallB;

implementation

procedure CallA;
var
  A: TA;
begin
  A:= TA.Create;
  A.Run;
end;

procedure CallB;
var
  B: TB;
begin
  B:= TB.Create;
  B.Run;
end;

end.
'@
Write-Ascii (Join-Path $src 'P.dpr') @'
program P;

uses
  uLib in 'uLib.pas',
  uUse in 'uUse.pas';

begin
end.
'@
$db = Join-Path $WorkDir 'p.sqlite'
$env:DRAGLINT_RULE_CACHE = '0'
$idx = & $exePath index --project (Join-Path $src 'P.dpr') --db $db 2>&1 | Out-String
$env:DRAGLINT_RULE_CACHE = $null
Check 'SANITY: fixture indexed' ($LASTEXITCODE -eq 0) $idx

$in  = Join-Path $WorkDir 'in.jsonl'
$out = Join-Path $WorkDir 'out.jsonl'
$req = @(
  '{"jsonrpc":"2.0","id":0,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"t","version":"1"}}}',
  '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"get_impact","arguments":{"qname":"uLib.TA.Run","depth":"1"}}}'
)
[IO.File]::WriteAllText($in, (($req -join "`n") + "`n"), [Text.Encoding]::ASCII)
$p = Start-Process $exePath -ArgumentList 'serve', '--db', "`"$db`"" -WorkingDirectory $WorkDir `
       -RedirectStandardInput $in -RedirectStandardOutput $out -RedirectStandardError (Join-Path $WorkDir 'err.txt') -NoNewWindow -PassThru
if (-not $p.WaitForExit(60000)) { $p.Kill() }
$text = ''
foreach ($line in (Get-Content $out -ErrorAction SilentlyContinue)) {
  try { $j = $line | ConvertFrom-Json } catch { continue }
  if ($j.id -eq 1 -and $j.result) { $text = [string]$j.result.content[0].text }
}
$total = if ($text -match '"callers"\s*:\s*(\d+)') { [int]$Matches[1] } else { -1 }
Check 'Q1 get_impact uLib.TA.Run counts its one caller, not every Run' ($total -eq 1) $text

$cli = & $exePath impact --qname uLib.TA.Run --depth 1 --db $db --format json 2>$null | Out-String
$cliTotal = if ($cli -match '"callers"\s*:\s*(\d+)') { [int]$Matches[1] } else { -1 }
Check 'Q2 CONTROL: the CLI impact --qname agrees' ($cliTotal -eq $total) "cli=$cliTotal mcp=$total"
}
finally {
  $env:DRAGLINT_RULE_CACHE = $null
  if ($WorkDir -and (Test-Path $WorkDir)) { Remove-Item $WorkDir -Recurse -Force -ErrorAction SilentlyContinue }
}
if ($fail) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
