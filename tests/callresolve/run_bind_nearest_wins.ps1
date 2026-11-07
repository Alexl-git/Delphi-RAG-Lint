<#
  run_bind_nearest_wins.ps1 -- E-BIND-NEAREST-WINS: on an inheritance chain the
  NEAREST declaration of a method decides, the way the compiler's lookup does,
  so a descendant-typed receiver binds the nearest override as `certain` instead
  of `ambiguous`.

  THE DEFECT: LookupMethodOnType added the type's own method and every ancestor's
  same-named one to one candidate list, and PickFromMatches reads two candidates
  as ambiguous. `FMid.M`, with TMid.M overriding TBase.M, already pointed at
  TMid.M but said `ambiguous`, so it earned no refs.symbol_id and every
  certain-only consumer (rename proof, effects, taint) dropped the site.

  POSITIVE CONTROL: on the old engine the OVERRIDE, REINTRODUCE, OVERLOAD-OVERRIDE,
  INTERFACE-CHAIN and PARENLESS checks are RED; the CONTROL checks are green on
  both engines. A real tie must stay ambiguous: nearest-wins removes SHADOWED
  candidates, it never picks between candidates at one level.

  Run from a NEUTRAL CWD. Pass -Exe with the engine under test.
#>
param([string]$Exe = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe")
$ErrorActionPreference = 'Stop'
$script:fail = $false
function Check([string]$n, [bool]$ok, [string]$d = '') {
  $s = if ($ok) { 'PASS' } else { 'FAIL' }; $c = if ($ok) { 'Green' } else { 'Red' }
  Write-Host ("  [{0}] {1} {2}" -f $s, $n, $d) -ForegroundColor $c
  if (-not $ok) { $script:fail = $true }
}
if (-not (Test-Path $Exe)) { Write-Host "FATAL: engine not found: $Exe" -ForegroundColor Red; exit 2 }
$exePath = (Resolve-Path $Exe).Path
$scratch = Join-Path C:\TEMP "draglint_bind_nearest_$PID"
[void][IO.Directory]::CreateDirectory($scratch)
function W([string]$name, [string]$body) {
  [IO.File]::WriteAllText((Join-Path $scratch $name), ($body -replace "`r?`n", "`r`n"), [Text.Encoding]::ASCII)
}

W 'uChain.pas' @'
unit uChain;

interface

type
  TBase = class
  public
    procedure M; virtual;
    function FnP: Integer; virtual;
    procedure R(AV: Integer); virtual;
    procedure Ov(AV: Integer); overload; virtual;
    procedure Ov(const S: string); overload; virtual;
    procedure Ren(AV: Integer); overload; virtual;
    procedure Ren(const S: string); overload; virtual;
    procedure Hid(AV, BV: Integer); virtual;
    procedure Sib(AV: Integer); overload; virtual;
    procedure Sib(const S: string); overload; virtual;
  end;

  TMid = class(TBase)
  public
    procedure M; override;
    function FnP: Integer; override;
    procedure R(AV: Integer); reintroduce;
    procedure Ov(AV: Integer); overload; override;
    procedure Ren(BV: Integer); overload; override;
    procedure Hid(AV: Integer); reintroduce;
    procedure Sib(AV: Integer); override;
    procedure BareCaller;
  end;

  TLeaf = class(TMid)
  end;

  TTie = class
  public
    procedure Tie(const A: TObject); overload;
    procedure Tie(const B: IInterface); overload;
  end;

  IBaseI = interface
    procedure Q;
  end;

  IDerI = interface(IBaseI)
    procedure Q;
  end;

  IA = interface
    procedure Z;
  end;

  IB = interface
    procedure Z;
  end;

  TUnk = class(TNotIndexedAnywhere, IA, IB)
  end;

implementation

procedure TBase.M; begin end;
function TBase.FnP: Integer; begin Result:= 0; end;
procedure TBase.R(AV: Integer); begin end;
procedure TBase.Ov(AV: Integer); begin end;
procedure TBase.Ov(const S: string); begin end;
procedure TBase.Ren(AV: Integer); begin end;
procedure TBase.Ren(const S: string); begin end;
procedure TBase.Hid(AV, BV: Integer); begin end;
procedure TBase.Sib(AV: Integer); begin end;
procedure TBase.Sib(const S: string); begin end;
procedure TMid.M; begin end;
function TMid.FnP: Integer; begin Result:= 1; end;
procedure TMid.R(AV: Integer); begin end;
procedure TMid.Ov(AV: Integer); begin end;
procedure TMid.Ren(BV: Integer); begin end;
procedure TMid.Hid(AV: Integer); begin end;
procedure TMid.Sib(AV: Integer); begin end;
procedure TMid.BareCaller;
begin
  M;
end;
procedure TTie.Tie(const A: TObject); begin end;
procedure TTie.Tie(const B: IInterface); begin end;

end.
'@

W 'uSite.pas' @'
unit uSite;

interface

uses uChain;

type
  TSite = class
  private
    FB: TBase;
    FM: TMid;
    FL: TLeaf;
    FT: TTie;
    FD: IDerI;
    FU: TUnk;
    FX: Integer;
    function Unknowable: TObject;
  public
    procedure CtlBase;
    procedure OvrMid;
    procedure OvrLeaf;
    procedure ReInt;
    procedure OvInt;
    procedure OvStr;
    procedure RenInt;
    procedure HidTwo;
    procedure SibStr;
    procedure SibInt;
    procedure TieCall;
    procedure IfaceChain;
    procedure IfaceSiblings;
    procedure Parenless;
  end;

implementation

function TSite.Unknowable: TObject; begin Result:= nil; end;
procedure TSite.CtlBase; begin FB.M; end;
procedure TSite.OvrMid; begin FM.M; end;
procedure TSite.OvrLeaf; begin FL.M; end;
procedure TSite.ReInt; begin FM.R(1); end;
procedure TSite.OvInt; begin FL.Ov(1); end;
procedure TSite.OvStr; begin FL.Ov('x'); end;
procedure TSite.RenInt; begin FL.Ren(1); end;
procedure TSite.HidTwo; begin FM.Hid(1, 2); end;
procedure TSite.SibStr; begin FM.Sib('x'); end;
procedure TSite.SibInt; begin FM.Sib(1); end;
procedure TSite.TieCall; begin FT.Tie(nil); end;
procedure TSite.IfaceChain; begin FD.Q; end;
procedure TSite.IfaceSiblings; begin FU.Z; end;
procedure TSite.Parenless; begin FX:= FM.FnP; end;

end.
'@

Push-Location C:\TEMP
try {
  $db = Join-Path $scratch 'n.sqlite'
  & $exePath index $scratch --db $db *> (Join-Path $scratch 'i.log')
  $q = "SELECT enc.name AS site, ce.confidence AS conf, t.qualified_name AS target, b.qualified_name AS bound " +
       "FROM call_edges ce JOIN refs r ON r.id = ce.ref_id JOIN symbols enc ON enc.id = r.enclosing_symbol_id " +
       "JOIN symbols t ON t.id = ce.target_symbol_id LEFT JOIN symbols b ON b.id = r.symbol_id"
  $raw = & $exePath sql --db $db --query $q --json | Out-String
  $j = $raw | ConvertFrom-Json
  $cols = @($j.columns | ForEach-Object { $_.name })
  $edges = @{}
  foreach ($row in $j.rows) {
    $o = @{}; for ($i = 0; $i -lt $cols.Count; $i++) { $o[$cols[$i]] = $row[$i] }
    $edges[[string]$o['site']] = $o
  }
  Check 'shape: the edge map is populated' ($edges.Count -ge 10) "rows=$($edges.Count)"
  function Edge([string]$label, [string]$site, [string]$conf, [string]$target) {
    $e = $edges[$site]
    if ($null -eq $e) { Check $label $false "no edge from $site"; return }
    Check $label (($e['conf'] -eq $conf) -and ($e['target'] -eq $target)) "got $($e['conf']) $($e['target'])"
    if ($conf -eq 'certain') {
      Check "$label -- refs.symbol_id earned" ($e['bound'] -eq $target) "got '$($e['bound'])'"
    } else {
      Check "$label -- no refs.symbol_id" ([string]::IsNullOrEmpty([string]$e['bound'])) "got '$($e['bound'])'"
    }
  }
  # The fix.
  Edge 'OVERRIDE: own override beats the ancestor'       'OvrMid'     'certain' 'uChain.TMid.M'
  Edge 'OVERRIDE: inherited nearest override wins'       'OvrLeaf'    'certain' 'uChain.TMid.M'
  Edge 'REINTRODUCE: hides the ancestor'                 'ReInt'      'certain' 'uChain.TMid.R'
  Edge 'OVERLOAD-OVERRIDE: the overridden twin is gone'  'OvInt'      'certain' 'uChain.TMid.Ov'
  Edge 'INTERFACE-CHAIN: redeclared on the descendant'   'IfaceChain' 'certain' 'uChain.IDerI.Q'
  Edge 'PARENLESS: a dotted function read'               'Parenless'  'certain' 'uChain.TMid.FnP'
  Edge 'PARENLESS: a bare call inside the class'         'BareCaller' 'certain' 'uChain.TMid.M'
  # dcc (run_bind_nearest_dcc.ps1, case D): an override with NO overload directive does not hide the sibling overload.
  Edge 'OVERRIDE-NO-OVERLOAD: the sibling stays reachable'  'SibStr' 'certain' 'uChain.TBase.Sib'
  Edge 'OVERRIDE-NO-OVERLOAD: the int call takes the override' 'SibInt' 'certain' 'uChain.TMid.Sib'
  # Controls: must not move.
  Edge 'CONTROL: a base receiver binds the base'         'CtlBase'    'certain' 'uChain.TBase.M'
  Edge 'CONTROL: the sibling overload stays reachable'   'OvStr'      'certain' 'uChain.TBase.Ov'
  Edge 'CONTROL: nearest does not fit, arity decides'    'HidTwo'     'certain' 'uChain.TBase.Hid'
  Edge 'CONTROL: a same-level overload tie stays ambiguous' 'TieCall' 'ambiguous' 'uChain.TTie.Tie'
  # Sibling interfaces are no chain: neither is nearer than the other.
  $z = $edges['IfaceSiblings']
  Check 'CONTROL: sibling interfaces stay ambiguous' (($null -ne $z) -and ($z['conf'] -eq 'ambiguous')) "got $($z['conf']) $($z['target'])"
  # Documented limit: a renamed parameter is not recognised as the same signature.
  Edge 'LIMIT: an override with a renamed parameter stays ambiguous' 'RenInt' 'ambiguous' 'uChain.TMid.Ren'
} finally {
  Pop-Location
  if (Test-Path -LiteralPath $scratch) { [IO.Directory]::Delete($scratch, $true) }
}
if ($script:fail) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
