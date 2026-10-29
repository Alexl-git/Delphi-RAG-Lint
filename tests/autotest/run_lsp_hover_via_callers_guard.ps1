#Requires -Version 7
<#
  run_lsp_hover_via_callers_guard.ps1 -- the LSP caller answers count the sites
  that reach a method ONLY through the interface it implements (RB-5, 1.38).

  THE GAP. 1.38 taught `query find-callers --resolved` to list, under an
  implementing method, the sites that call it through its interface ("via
  IFoo.Bar dispatch"). The LSP did not follow: draglint/hoverBundle asked
  ResolvedCallersForName WITHOUT the dispatch arm, so every resolved row named
  the INTERFACE method as its target. The IDE popup picks the rows whose
  target_qname is the hovered method, found none, and -- because the name
  resolves elsewhere -- showed "0 callers" for a method that is called twice.

  WHAT THIS PINS (inline fixture: TWorker.DoWork reached only via IWorker;
  TWorker.Direct called once through a class-typed receiver as the control)
    FC    find-callers --resolved --json: N rows target TWorker.DoWork, all via
          IWorker.DoWork (the reference count everything below must agree with).
    HB1   hoverBundle on TWorker.DoWork: resolvedCallers rows targeting it = N >= 1.
    HB2   ...each carries via = uViaWork.IWorker.DoWork and via_kind = interface.
    HB3   POSITIVE CONTROL: hoverBundle on TWorker.Direct lists its 1 direct row
          with NO via key -- the dispatch arm adds, it does not relabel.
    CC1   draglint/callerCounts reports N on TWorker.DoWork's declaration line.

  Usage: pwsh -File tests\autotest\run_lsp_hover_via_callers_guard.ps1 [-Exe <drag-lint.exe>]
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\drag-lint-hover-via-$PID"
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

$workFile = Join-Path $src 'uViaWork.pas'
WriteAnsi $workFile @'
unit uViaWork;

interface

type
  IWorker = interface
    ['{6B1E2C30-0000-4000-8000-00000000C001}']
    procedure DoWork(const A: Integer);
  end;

  TWorker = class(TInterfacedObject, IWorker)
  public
    procedure DoWork(const A: Integer);
    procedure Direct;
  end;

implementation

procedure TWorker.DoWork(const A: Integer);
begin
end;

procedure TWorker.Direct;
begin
end;

end.
'@
WriteAnsi (Join-Path $src 'uViaUse.pas') @'
unit uViaUse;

interface

uses uViaWork;

procedure UseOne(const W: IWorker);
procedure UseTwo;
procedure UseClass(const C: TWorker);

implementation

procedure UseOne(const W: IWorker);
begin
  W.DoWork(1);
end;

procedure UseTwo;
var
  W: IWorker;
begin
  W:= TWorker.Create;
  W.DoWork(2);
end;

procedure UseClass(const C: TWorker);
begin
  C.Direct;
end;

end.
'@

$db = Join-Path $WorkDir 'via.sqlite'
& $Exe index $src --db $db 2>&1 | Out-Null
Check 'fixture indexed' (Test-Path $db)

$IMPL  = 'uViaWork.TWorker.DoWork'
$IFACE = 'uViaWork.IWorker.DoWork'
$DIRECT = 'uViaWork.TWorker.Direct'

$jraw = (& $Exe query find-callers --name DoWork --resolved --json --db $db 2>$null) -join "`n"
$fc = @($jraw.Substring($jraw.IndexOf('[')) | ConvertFrom-Json)
$fcImpl = @($fc | Where-Object { $_.target_qname -eq $IMPL })
$N = $fcImpl.Count
Check 'FC find-callers --resolved: TWorker.DoWork has >= 1 caller, all via IWorker' `
  (($N -ge 1) -and (@($fcImpl | Where-Object { $_.via -ne $IFACE }).Count -eq 0)) "N=$N"

$lines = [System.IO.File]::ReadAllLines($workFile)
function LineOf([string]$Needle) {
  for ($i = 0; $i -lt $lines.Count; $i++) { if ($lines[$i].Trim() -eq $Needle) { return $i } }
  throw "fixture line not found: $Needle"
}
$implLine   = LineOf 'procedure TWorker.DoWork(const A: Integer);'
$directLine = LineOf 'procedure TWorker.Direct;'
$declLine   = -1
for ($i = 0; $i -lt $lines.Count; $i++) { if ($lines[$i] -match '^\s+procedure DoWork\(' -and $i -gt (LineOf 'TWorker = class(TInterfacedObject, IWorker)')) { $declLine = $i; break } }

# One server run: hoverBundle on both methods, then callerCounts for the unit.
$uri = 'file:///' + ($workFile -replace '\\', '/')
$m  = Frame @{ jsonrpc='2.0'; id=1; method='initialize'; params=@{ processId=$null; rootUri=$null; capabilities=@{} } }
$m += Frame @{ jsonrpc='2.0'; method='initialized'; params=@{} }
$m += Frame @{ jsonrpc='2.0'; id=2; method='draglint/hoverBundle'
               params=@{ textDocument=@{ uri=$uri }; position=@{ line=$implLine; character=($lines[$implLine].IndexOf('DoWork') + 1) } } }
$m += Frame @{ jsonrpc='2.0'; id=3; method='draglint/hoverBundle'
               params=@{ textDocument=@{ uri=$uri }; position=@{ line=$directLine; character=($lines[$directLine].IndexOf('Direct') + 1) } } }
$m += Frame @{ jsonrpc='2.0'; id=4; method='draglint/callerCounts'; params=@{ textDocument=@{ uri=$uri } } }
$m += Frame @{ jsonrpc='2.0'; id=5; method='shutdown'; params=@{} }
$inF  = Join-Path $WorkDir 'in.txt'
$outF = Join-Path $WorkDir 'out.txt'
[System.IO.File]::WriteAllText($inF, $m, (New-Object System.Text.ASCIIEncoding))
Start-Process $Exe -ArgumentList @('lsp', '--db', $db) -WorkingDirectory $WorkDir `
  -RedirectStandardInput $inF -RedirectStandardOutput $outF `
  -RedirectStandardError (Join-Path $WorkDir 'err.txt') -NoNewWindow -Wait | Out-Null
$byId = @{}
foreach ($mm in [regex]::Matches([System.IO.File]::ReadAllText($outF), '\{"jsonrpc".*?(?=Content-Length:|$)', 'Singleline')) {
  try { $o = $mm.Value.Trim() | ConvertFrom-Json } catch { continue }
  if ($null -ne $o.id) { $byId[[int]$o.id] = $o }
}

$hb = $byId[2]
Check 'HB answered' ($null -ne $hb -and $null -ne $hb.result)
$rows = @(if ($hb) { $hb.result.resolvedCallers | Where-Object { $_.target_qname -eq $IMPL } })
Check 'HB1 hoverBundle: resolved rows for TWorker.DoWork = find-callers' (($rows.Count -ge 1) -and ($rows.Count -eq $N)) "rows=$($rows.Count) N=$N"
Check 'HB2 each row names via IWorker.DoWork, via_kind interface' `
  (($rows.Count -ge 1) -and (@($rows | Where-Object { $_.via -ne $IFACE -or $_.via_kind -ne 'interface' }).Count -eq 0))

$hd = $byId[3]
$drows = @(if ($hd) { $hd.result.resolvedCallers | Where-Object { $_.target_qname -eq $DIRECT } })
Check 'HB3 control: TWorker.Direct has its 1 direct row, no via key' `
  (($drows.Count -eq 1) -and (@($drows | Where-Object { $_.PSObject.Properties.Name -contains 'via' }).Count -eq 0)) "rows=$($drows.Count)"

$cc = $byId[4]
$counts = @(if ($cc) { $cc.result.counts })
$hit = @($counts | Where-Object { $_.line -eq $declLine -or $_.line -eq $implLine })
Check 'CC1 callerCounts on TWorker.DoWork = find-callers' `
  (($hit.Count -ge 1) -and (@($hit | Where-Object { [int]$_.count -ne $N }).Count -eq 0)) "got=$(($hit | ForEach-Object { $_.count }) -join ',') N=$N"

if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
} finally {
  if (Test-Path -LiteralPath $WorkDir) { [System.IO.Directory]::Delete($WorkDir, $true) }
}
