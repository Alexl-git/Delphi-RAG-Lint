<#
  run_interface_dispatch_attribution.ps1 -- RB-5 (INBOX-untypable-receivers-brainstorm.md
  section 4; OWNER RULING 2026-09-16): an INTERFACE-dispatched call (`M: ICopy;
  M.TransferFile(..)`) is attributed to THE INTERFACE METHOD ONLY -- not fanned out to the
  implementors, not dropped. Implementors are reachable from it through dispatch_edges
  (kind 'implements'), a query, never extra call_edges rows.

  149 RB2 item 2 measured this FIXED-already on 1.48.0-alpha for every receiver shape below;
  this guard pins it. The dispatch kind is NOT a call_edges column: it is derived at read time
  (the target's parent symbol is an interface), documented in docs\wiki\Index-DB-Schema.md
  (call_edges), so no schema change was made (OWNER-QUESTIONS 149 RB2).

  Pins: A1 six interface-typed shapes -- local, parameter, field, a field of a DERIVED
  interface (ISub), a parenless function result, a `with` over an interface local -- bind
  certain to uRB5.ICopy.TransferFile with refs.symbol_id set, and no site of them has an edge
  to TAlpha / TBeta; A2 the derived dispatch kind is 'interface' for those six; A3 the
  implementors are a dispatch_edges query (TAlpha + TBeta, kind implements).
  POSITIVE CONTROL: A4 the CLASS-typed site `A.TransferFile` (A: TAlpha) binds
  uRB5.TAlpha.TransferFile and derives 'class' -- a guard that answered "interface" for
  every site fails here.
  Run from any CWD, pwsh 7. Pass -Exe with the engine under test.
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe",
  [string]$WorkDir = "C:\TEMP\draglint_intf_dispatch_$PID"
)
try {
$ErrorActionPreference = 'Stop'
$script:fail = $false
function Check($n,$ok,$d){
  Write-Host ("[{0}] {1}" -f (@('FAIL','PASS')[[int][bool]$ok]),$n) -ForegroundColor (@('Red','Green')[[int][bool]$ok])
  if(-not $ok){ if($d){ Write-Host "      $d" -ForegroundColor DarkGray }; $script:fail=$true }
}
function W($dir,$name,$t){ [IO.File]::WriteAllText((Join-Path $dir $name), (($t -replace "`r`n","`n") -replace "`n","`r`n"), [Text.Encoding]::ASCII) }

$exePath = (Resolve-Path $Exe).Path
if (Test-Path $WorkDir) { [IO.Directory]::Delete($WorkDir, $true) }
New-Item -ItemType Directory -Path $WorkDir | Out-Null

W $WorkDir 'uRB5.pas' @'
unit uRB5;
interface
type
  ICopy = interface
    ['{11111111-2222-3333-4444-555555555555}']
    function TransferFile(const S: string): Boolean;
  end;
  ISub = interface(ICopy)
    ['{11111111-2222-3333-4444-555555555556}']
    procedure Extra;
  end;
  TAlpha = class(TInterfacedObject, ICopy)
  public
    function TransferFile(const S: string): Boolean;
  end;
  TBeta = class(TInterfacedObject, ICopy)
  public
    function TransferFile(const S: string): Boolean;
  end;
  THost = class
  private
    FCopy: ICopy;
    FSub: ISub;
  public
    procedure Run(const AM: ICopy);
    function Get: ICopy;
  end;
implementation
function TAlpha.TransferFile(const S: string): Boolean; begin Result:= True; end;
function TBeta.TransferFile(const S: string): Boolean; begin Result:= False; end;
function THost.Get: ICopy; begin Result:= FCopy; end;
procedure THost.Run(const AM: ICopy);
var
  M: ICopy;
  A: TAlpha;
begin
  M:= AM;
  M.TransferFile('local');
  AM.TransferFile('param');
  FCopy.TransferFile('field');
  FSub.TransferFile('derived-intf');
  Get.TransferFile('result');
  A.TransferFile('class');
  with M do
    TransferFile('with');
end;
end.
'@
W $WorkDir 'RB5.dpr' @'
program RB5;
uses
  uRB5 in 'uRB5.pas';
begin
end.
'@

$db = Join-Path $WorkDir 'rb5.sqlite'
Push-Location C:\TEMP
& $exePath index --project (Join-Path $WorkDir 'RB5.dpr') --db $db 2>&1 | Out-Null
Check 'V index built' (Test-Path $db) $db
$raw = & $exePath sql --db $db --json --limit 200 --query "SELECT r.start_line, coalesce(r.receiver_text,''), coalesce(e.confidence,''), coalesce(s.qualified_name,''), CASE WHEN r.symbol_id = e.target_symbol_id THEN 1 ELSE 0 END, coalesce(p.kind,'') FROM refs r LEFT JOIN call_edges e ON e.ref_id = r.id LEFT JOIN symbols s ON s.id = e.target_symbol_id LEFT JOIN symbols p ON p.id = s.parent_id WHERE r.kind = 'call' AND r.name_text = 'TransferFile' ORDER BY r.start_line" | Out-String
$disp = & $exePath sql --db $db --json --limit 50 --query "SELECT i.qualified_name, d.kind FROM dispatch_edges d JOIN symbols b ON b.id = d.base_symbol_id JOIN symbols i ON i.id = d.impl_symbol_id WHERE b.qualified_name = 'uRB5.ICopy.TransferFile' ORDER BY 1" | Out-String
Pop-Location
$rows = foreach ($r in ($raw | ConvertFrom-Json).rows) { [pscustomobject]@{ Line=[int]$r[0]; Rcv=[string]$r[1]; Conf=[string]$r[2]; Target=[string]$r[3]; Sid=[int]$r[4]; ParentKind=[string]$r[5] } }
Check "V the seven sites were read ($(@($rows).Count))" (@($rows).Count -eq 7) $raw
$cls = @($rows | Where-Object { $_.Rcv -eq 'A' })
$intf = @($rows | Where-Object { $_.Rcv -ne 'A' })
Check "V six interface-shaped sites ($($intf.Count))" ($intf.Count -eq 6) $raw
foreach ($s in $intf) {
  $tag = if ($s.Rcv -eq '') { 'with M' } else { $s.Rcv }
  Check "A1 $tag (line $($s.Line)) -> certain uRB5.ICopy.TransferFile, refs.symbol_id set (got '$($s.Conf) $($s.Target) sid=$($s.Sid)')" ($s.Conf -eq 'certain' -and $s.Target -ceq 'uRB5.ICopy.TransferFile' -and $s.Sid -eq 1)
  $kind = if ($s.ParentKind -eq 'interface') { 'interface' } else { 'class' }
  Check "A2 $tag derived dispatch = interface (got '$kind')" ($kind -eq 'interface')
}
Check "A1 no interface-shaped site has an edge to an implementor" (@($intf | Where-Object { $_.Target -match 'TAlpha|TBeta' }).Count -eq 0)
$impl = @(($disp | ConvertFrom-Json).rows | ForEach-Object { "$([string]$_[0])/$([string]$_[1])" })
Check "A3 implementors are a dispatch_edges query: TAlpha + TBeta, implements (got '$($impl -join ', ')')" (($impl -join ',') -ceq 'uRB5.TAlpha.TransferFile/implements,uRB5.TBeta.TransferFile/implements') $disp
$c = $cls | Select-Object -First 1
$ckind = if ($c -and $c.ParentKind -eq 'interface') { 'interface' } else { 'class' }
Check "A4 POSITIVE CONTROL A.TransferFile (A: TAlpha) -> certain uRB5.TAlpha.TransferFile, dispatch class (got '$($c.Conf) $($c.Target) $ckind')" ($null -ne $c -and $c.Conf -eq 'certain' -and $c.Target -ceq 'uRB5.TAlpha.TransferFile' -and $ckind -eq 'class')

Write-Host ''
if ($script:fail) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'PASS' -ForegroundColor Green; exit 0
} finally {
  if (Test-Path -LiteralPath $WorkDir) { [IO.Directory]::Delete($WorkDir, $true) }
}
