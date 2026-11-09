<#
  run_selector_chain_typing.ps1 -- receiver typing of selector chains and chain
  heads the resolver left untyped (lane 149-RB1 items 3-5).

  Sources: 146 b7 REPORT ("chain head at CallResolver ~7192 left alone": the
  selector-chain head did not read a class-level `var` field, D12), 146 b8 REPORT
  ("selector chains H.Get.Items[0].X: TypeMember does not step methods";
  "constructor in a chain TFoo.Create.Run stays unbound"), 146 b3 REPORT
  ("F()[0].X stays refused"; "IReadOnlyDictionary left out";
  "var X := Default(T) gives no static type").

  CASES (markers in the fixture; lines are read from it)
    S1 FArr[0].V             head = class-level `var` field (D12)        -> uS.TItem.V
    S2 H.Get.Items[0].V      parameterless METHOD hop inside a selector chain -> uS.TItem.V
    S3 TRunner.Create.Run    constructor hop (TObject.Create inherited)   -> uS.TRunner.Run (call edge)
    S3b TRunner2.Create.Run  a DECLARED argument-less constructor hop     -> uS.TRunner2.Run (call edge)
    S4 MakeItems()[0].V      call head, then a subscript                 -> uS.TItem.V
    S5 RD['a'].V             Spring IReadOnlyDictionary<string, TItem>   -> uS.TItem.V
    S6 Y.V, Y := Default(TRec) inline var typed by Default(T)          -> uS.TRec.V
    C5 D['a'].V              IDictionary control (green on the base)     -> uS.TItem.V
    N1 H.GetP.Items[0].V     the method NEEDS an argument: not a parenless call -> unbound
    N2 Q.Get.Items[0].V      Q of an unindexed type                      -> unbound

  `sql --json` rows are POSITIONAL arrays; Sql() maps them onto column names.
  Usage: pwsh -File tests\callresolve\run_selector_chain_typing.ps1 [-Exe <drag-lint.exe>]
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe",
  [string]$WorkDir = "C:\TEMP\draglint_selector_chain_$PID"
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
function W($p,$t){ [IO.File]::WriteAllText($p, (($t -replace "`r`n","`n") -replace "`n","`r`n"), [Text.Encoding]::ASCII) }

if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
$Exe = (Resolve-Path $Exe).Path
if (Test-Path $WorkDir) { [IO.Directory]::Delete($WorkDir, $true) }
New-Item -ItemType Directory $WorkDir | Out-Null

W (Join-Path $WorkDir 'uS.pas') @'
unit uS;

interface

uses
  Spring.Collections;

type
  TItem = class
  public
    V: Integer;
  end;

  TItems = array of TItem;

  TRec = record
    V: Integer;
  end;

  TBag = class
  public
    Items: TItems;
  end;

  THolder = class
  public
    function Get: TBag;
    function GetP(A: Integer): TBag;
  end;

  TRunner = class
  public
    procedure Run;
  end;

  TRunner2 = class
  public
    constructor Create;
    procedure Run;
  end;

  TOwner = class
  var
    FArr: TItems;
  public
    procedure Work(H: THolder; Q: TNotIndexed; D: IDictionary<string, TItem>;
      RD: IReadOnlyDictionary<string, TItem>);
  end;

function MakeItems: TItems;

implementation

function THolder.Get: TBag;
begin
  Result := nil;
end;

function THolder.GetP(A: Integer): TBag;
begin
  Result := nil;
end;

procedure TRunner.Run;
begin
end;

constructor TRunner2.Create;
begin
end;

procedure TRunner2.Run;
begin
end;

function MakeItems: TItems;
begin
  Result := nil;
end;

procedure TOwner.Work(H: THolder; Q: TNotIndexed; D: IDictionary<string, TItem>;
  RD: IReadOnlyDictionary<string, TItem>);
var
  X: Integer;
begin
  X := FArr[0].V; // S1
  X := H.Get.Items[0].V; // S2
  TRunner.Create.Run; // S3
  TRunner2.Create.Run; // S3b
  X := MakeItems()[0].V; // S4
  X := RD['a'].V; // S5
  var Y := Default(TRec);
  X := Y.V; // S6
  X := D['a'].V; // C5
  X := H.GetP.Items[0].V; // N1
  X := Q.Get.Items[0].V; // N2
  if X > 0 then
    Exit;
end;

end.
'@
W (Join-Path $WorkDir 'App.dpr') @'
program App;

uses
  uS in 'uS.pas';

begin
end.
'@

$db = Join-Path $WorkDir 'App.sqlite'
& $Exe index --project (Join-Path $WorkDir 'App.dpr') --db $db 2>&1 | Out-Null
Check 'V the fixture index was built' (Test-Path $db) $db

function Sql([string]$Q) {
  $j = & $Exe sql --db $db --json --limit 1000 --query $Q 2>$null | ConvertFrom-Json
  if ($null -eq $j) { return ,@() }
  $cols = @($j.columns | ForEach-Object { $_.name })
  $out = @()
  foreach ($row in $j.rows) {
    $o = [ordered]@{}
    for ($i = 0; $i -lt $cols.Count; $i++) { $o[$cols[$i]] = $row[$i] }
    $out += [pscustomobject]$o
  }
  return ,$out
}
function LineOfMarker([string]$File, [string]$Marker) {
  $ls = [IO.File]::ReadAllLines((Join-Path $WorkDir $File))
  for ($i = 0; $i -lt $ls.Count; $i++) { if ($ls[$i] -match ('// ' + [regex]::Escape($Marker) + '$')) { return $i + 1 } }
  return -1
}
function RefAt([string]$Marker, [string]$Kind, [string]$Name) {
  $ln = LineOfMarker 'uS.pas' $Marker
  $q = "SELECT r.id, r.receiver_text AS rt, r.receiver_type_text AS rtt, s.qualified_name AS sq, " +
       "(SELECT t.qualified_name FROM call_edges ce JOIN symbols t ON t.id = ce.target_symbol_id WHERE ce.ref_id = r.id) AS tq " +
       "FROM refs r JOIN files f ON f.id = r.file_id LEFT JOIN symbols s ON s.id = r.symbol_id " +
       "WHERE r.kind = '$Kind' AND r.name_text = '$Name' AND r.start_line = $ln AND f.path LIKE '%\uS.pas'"
  return ,(Sql $q)
}

$pos = @(
  @{ M = 'S1'; K = 'member-access'; N = 'V';   Q = 'uS.TItem.V';   Why = 'class-level var head (D12)' },
  @{ M = 'S2'; K = 'member-access'; N = 'V';   Q = 'uS.TItem.V';   Why = 'parameterless method hop in a selector chain' },
  @{ M = 'S3'; K = 'call';          N = 'Run'; Q = 'uS.TRunner.Run'; Why = 'inherited TObject.Create hop in a chain' },
  @{ M = 'S3b'; K = 'call';         N = 'Run'; Q = 'uS.TRunner2.Run'; Why = 'declared argument-less constructor hop' },
  @{ M = 'S4'; K = 'member-access'; N = 'V';   Q = 'uS.TItem.V';   Why = 'call head then a subscript' },
  @{ M = 'S5'; K = 'member-access'; N = 'V';   Q = 'uS.TItem.V';   Why = 'IReadOnlyDictionary element' },
  @{ M = 'S6'; K = 'member-access'; N = 'V';   Q = 'uS.TRec.V';    Why = 'inline var := Default(T)' },
  @{ M = 'C5'; K = 'member-access'; N = 'V';   Q = 'uS.TItem.V';   Why = 'IDictionary control' })
foreach ($c in $pos) {
  $r = RefAt $c.M $c.K $c.N
  $got = if ($c.K -eq 'call') { $r[0].tq } else { $r[0].sq }
  Check ("{0}  {1} binds {2} ({3})" -f $c.M, $c.N, $c.Q, $c.Why) `
    (($r.Count -eq 1) -and ($got -eq $c.Q)) ("rows=$($r.Count) rt=$($r[0].rt) rtt=$($r[0].rtt) sq=$($r[0].sq) tq=$($r[0].tq)")
}
foreach ($n in @(@{ M = 'N1'; Why = 'GetP needs an argument' }, @{ M = 'N2'; Why = 'Q has an unindexed type' })) {
  $r = RefAt $n.M 'member-access' 'V'
  Check ("{0}  V stays unbound: {1}" -f $n.M, $n.Why) `
    (($r.Count -eq 1) -and ($null -eq $r[0].sq)) ("rows=$($r.Count) rt=$($r[0].rt) rtt=$($r[0].rtt) sq=$($r[0].sq)")
}

Write-Host ''
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'PASS' -ForegroundColor Green; exit 0
} finally {
  foreach ($d23 in @("C:\TEMP\draglint_selector_chain_$PID")) { if (Test-Path -LiteralPath $d23) { [IO.Directory]::Delete($d23, $true) } }
}
