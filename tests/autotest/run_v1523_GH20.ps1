<#
  run_v1523_GH20.ps1 -- GitHub #20: the MCP tool get_impact walked only the last qname segment
  (FindTransitiveCallers) and answered for a qname that names no symbol; the CLI `impact` was
  fixed for #14 (resolved callers walk).
  Fixture (same as run_v152_GH14): Shapes.TCircle.Draw / Shapes.TSquare.Draw; Painter + AnsiPainter
  call TCircle.Draw, SquarePainter calls TSquare.Draw, Client calls PaintCircle.
  1. get_impact Shapes.TCircle.Draw depth 1 = 2 callers / 2 units (was 3/3), equal to the CLI.
  2. depth 2 equals the CLI's depth-2 numbers (positive control: the walk still goes up).
  3. a qname that names no symbol answers isError true (was isError false with callers).
  Run from a NEUTRAL CWD, pwsh 7.
#>
[CmdletBinding()]
param([string]$Exe = '')
# Defaults that need the script path are resolved HERE, not in param(): Windows PowerShell 5 run with
# -File leaves $PSScriptRoot/$MyInvocation empty inside an advanced script's param block (Repo became C:\).
if (-not $Exe) { $Exe = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe" }
$ErrorActionPreference = 'Stop'
$script:fail = $false
function Check($n, $ok, $d) {
  Write-Host ("[{0}] {1}" -f (@('FAIL', 'PASS')[[int][bool]$ok]), $n)
  if (-not $ok) { if ($d) { Write-Host "      $d" }; $script:fail = $true }
}
$exe = (Resolve-Path $Exe).Path
$work = Join-Path ([IO.Path]::GetTempPath()) ("dl_gh20_" + [guid]::NewGuid().ToString('N').Substring(0, 8))
$fx = Join-Path $work 'fx'
[void][IO.Directory]::CreateDirectory($fx)
function W($n, $t) { [IO.File]::WriteAllText((Join-Path $fx $n), ($t -replace "`r?`n", "`r`n"), [Text.Encoding]::ASCII) }
W 'Shapes.pas' @'
unit Shapes;
interface
type
  TCircle = class
  public
    procedure Draw;
  end;
  TSquare = class
  public
    procedure Draw;
  end;
implementation
procedure TCircle.Draw; begin end;
procedure TSquare.Draw; begin end;
end.
'@
W 'Painter.pas' @'
unit Painter;
interface
uses Shapes;
procedure PaintCircle(C: TCircle);
implementation
procedure PaintCircle(C: TCircle); begin C.Draw; end;
end.
'@
W 'AnsiPainter.pas' @'
unit AnsiPainter;
interface
uses Shapes;
procedure PaintAnsi(C: TCircle);
implementation
procedure PaintAnsi(C: TCircle); begin C.Draw; end;
end.
'@
W 'SquarePainter.pas' @'
unit SquarePainter;
interface
uses Shapes;
procedure PaintSquare(S: TSquare);
implementation
procedure PaintSquare(S: TSquare); begin S.Draw; end;
end.
'@
W 'Client.pas' @'
unit Client;
interface
uses Shapes, Painter;
procedure Go;
implementation
procedure Go; var C: TCircle; begin C := TCircle.Create; PaintCircle(C); end;
end.
'@
$db = Join-Path $work 'fx.sqlite'
function Invoke-Serve([string[]]$Requests, [string]$Tag) {
  $in = Join-Path $work "$Tag.in.jsonl"; $out = Join-Path $work "$Tag.out.jsonl"; $err = Join-Path $work "$Tag.err.txt"
  $all = @('{"jsonrpc":"2.0","id":0,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"t","version":"1"}}}') + $Requests
  [IO.File]::WriteAllText($in, (($all -join "`n") + "`n"), [Text.Encoding]::ASCII)
  $p = Start-Process $exe -ArgumentList 'serve', '--db', "`"$db`"" -WorkingDirectory $work `
         -RedirectStandardInput $in -RedirectStandardOutput $out -RedirectStandardError $err -NoNewWindow -PassThru; $null = $p.Handle
  if (-not $p.WaitForExit(60000)) { $p.Kill() }
  $replies = @{}
  foreach ($line in (Get-Content $out -ErrorAction SilentlyContinue)) {
    if ($line.Trim() -eq '') { continue }
    try { $j = $line | ConvertFrom-Json | ForEach-Object { $_ } } catch { continue }
    if ($null -ne $j.id) { $replies[[string]$j.id] = $j }
  }
  $replies
}
function Call([int]$Id, [string]$Tool, [hashtable]$Arguments) {
  (@{ jsonrpc = '2.0'; id = $Id; method = 'tools/call'; params = @{ name = $Tool; arguments = $Arguments } } | ConvertTo-Json -Compress -Depth 6)
}
function Text($Reply) { if ($Reply -and $Reply.result -and $Reply.result.content.Count -gt 0) { [string]$Reply.result.content[0].text } else { '' } }
Push-Location $work
try {
  & { $ErrorActionPreference = 'Continue'; & $exe index $fx --db $db *> $null }
  Check 'fixture indexed' ($LASTEXITCODE -eq 0 -and (Test-Path $db)) "exit $LASTEXITCODE"
  $r = Invoke-Serve @(
    (Call 1 'get_impact' @{ qname = 'Shapes.TCircle.Draw'; depth = 1 }),
    (Call 2 'get_impact' @{ qname = 'Shapes.TCircle.Draw'; depth = 2 }),
    (Call 3 'get_impact' @{ qname = 'NoSuchUnit.TNothing.Draw'; depth = 1 }),
    (Call 4 'get_impact' @{ qname = 'Shapes.TSquare.Draw'; depth = 1 })
  ) 'gh20'
  function Lv($rep, $i) { try { $p = (Text $rep) | ConvertFrom-Json | ForEach-Object { $_ }; $p.levels[$i] } catch { $null } }
  $l1 = Lv $r['1'] 0
  Check 'MCP get_impact TCircle.Draw depth 1 = 2 callers / 2 units' ($l1 -and $l1.callers -eq 2 -and $l1.units -eq 2) (Text $r['1'])
  Check 'MCP get_impact TSquare.Draw depth 1 = 1 caller / 1 unit' ((Lv $r['4'] 0) -and (Lv $r['4'] 0).callers -eq 1) (Text $r['4'])
  # the CLI at depth 2 is the reference for the MCP depth 2
  $cj = (& { $ErrorActionPreference = 'Continue'; & $exe impact --qname Shapes.TCircle.Draw --depth 2 --format json --db $db 2>$null } | Out-String)
  $cp = try { $cj | ConvertFrom-Json | ForEach-Object { $_ } } catch { $null }
  $m2 = Text $r['2']; $mp = try { $m2 | ConvertFrom-Json | ForEach-Object { $_ } } catch { $null }
  $same = $cp -and $mp -and (@($cp.levels).Count -eq @($mp.levels).Count) -and (@($cp.levels).Count -ge 2)
  if ($same) { for ($i = 0; $i -lt @($cp.levels).Count; $i++) { if ($cp.levels[$i].callers -ne $mp.levels[$i].callers -or $cp.levels[$i].units -ne $mp.levels[$i].units) { $same = $false } } }
  Check 'MCP depth 2 levels equal the CLI impact levels (and there are 2)' $same "cli=$($cj.Trim()) mcp=$m2"
  Check 'MCP get_impact for a qname naming no symbol: isError true' ($r['3'] -and $r['3'].result.isError -eq $true) ($r['3'] | ConvertTo-Json -Depth 6 -Compress)
  Check 'MCP get_impact unknown qname: no callers reported' ((Text $r['3']) -notmatch '"callers":\s*[1-9]') (Text $r['3'])
}
finally {
  Pop-Location
  try { [IO.Directory]::Delete($work, $true) } catch { }
}
if ($script:fail) { Write-Host 'FAIL'; exit 1 }
Write-Host 'PASS'; exit 0
