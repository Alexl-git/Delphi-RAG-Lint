<#
  run_property_redeclare_accessor.ps1 -- E-USE-EDGES, the echo of a REDECLARED
  property: `property Val;` (a visibility change) has no read or write clause of
  its own, so the accessor lives on the nearest ancestor that declares it (use-edges
  design, section 6.1, "bare redeclaration").

  THE DEFECT: ResolveAccessor read only the declaration it was handed, found no
  clause, and recorded NO accessor. Every read through a descendant then left the
  getter with no caller and no call edge: `usages GetVal --rw` answered 0 readers
  with live readers in the tree.

  ALSO: `read FRec.Sub` (section 6.1, "record sub-field") echoes the leftmost field FRec.

  POSITIVE CONTROL: on the old engine the REDECLARED, PARTIAL and DOTTED checks are RED; the
  CONTROL checks are green on both engines, and find-callers on a redeclared property
  still answers with the redeclaration as the member.
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
$scratch = Join-Path C:\TEMP "draglint_prop_redeclare_$PID"
[void][IO.Directory]::CreateDirectory($scratch)
function W([string]$name, [string]$body) {
  [IO.File]::WriteAllText((Join-Path $scratch $name), ($body -replace "`r?`n", "`r`n"), [Text.Encoding]::ASCII)
}

W 'uProp.pas' @'
unit uProp;

interface

type
  TRec = record
    Sub: Integer;
  end;

  TBase = class
  private
    FRec: TRec;
    FField: Integer;
    FItems: array[0..3] of Integer;
    function GetVal: Integer;
    procedure SetVal(const AV: Integer);
    function GetItem(I: Integer): Integer;
    function GetItem2(I, J: Integer): Integer;
    procedure SetOther(const AV: Integer);
  protected
    property Val: Integer read GetVal write SetVal;
    property Fld: Integer read FField write FField;
    property Items[I: Integer]: Integer read GetItem;
    property Part: Integer read FField;
    property Plain: Integer read GetVal;
  public
    property Dot: Integer read FRec.Sub write FRec.Sub;
  end;

  TMid = class(TBase)
  public
    property Val;
    property Fld default 3;
    property Items;
    property Part write SetOther;
  end;

  TLeaf = class(TMid)
  public
    property Val;
    property Plain: Integer read FField;
  end;

  TNoAnc = class(TNotIndexedAnywhere)
  public
    property Lost;
  end;

implementation

function TBase.GetVal: Integer; begin Result:= 0; end;
procedure TBase.SetVal(const AV: Integer); begin end;
function TBase.GetItem(I: Integer): Integer; begin Result:= 0; end;
function TBase.GetItem2(I, J: Integer): Integer; begin Result:= 0; end;
procedure TBase.SetOther(const AV: Integer); begin end;

end.
'@

W 'uUse.pas' @'
unit uUse;

interface

uses uProp;

type
  TUse = class
  private
    FM: TMid;
    FL: TLeaf;
    FN: TNoAnc;
    FX: Integer;
  public
    procedure RedRead;
    procedure RedWrite;
    procedure RedTwice;
    procedure RedField;
    procedure RedIndex;
    procedure PartRead;
    procedure PartWrite;
    procedure ShadowRead;
    procedure LostRead;
    procedure DotRead;
    procedure DotWrite;
  end;

implementation

procedure TUse.RedRead; begin FX:= FM.Val; end;
procedure TUse.RedWrite; begin FM.Val:= 1; end;
procedure TUse.RedTwice; begin FX:= FL.Val; end;
procedure TUse.RedField; begin FX:= FM.Fld; end;
procedure TUse.RedIndex; begin FX:= FM.Items[0]; end;
procedure TUse.PartRead; begin FX:= FM.Part; end;
procedure TUse.PartWrite; begin FM.Part:= 1; end;
procedure TUse.ShadowRead; begin FX:= FL.Plain; end;
procedure TUse.LostRead; begin FX:= FN.Lost; end;
procedure TUse.DotRead; begin FX:= FM.Dot; end;
procedure TUse.DotWrite; begin FM.Dot:= 1; end;

end.
'@

Push-Location C:\TEMP
try {
  $db = Join-Path $scratch 'r.sqlite'
  & $exePath index $scratch --db $db *> (Join-Path $scratch 'i.log')
  $q = "SELECT enc.name AS site, r.name_text AS member, ma.mode AS mode, m.qualified_name AS bound, ma.accessor_kind AS kind, a.qualified_name AS accessor " +
       "FROM refs r JOIN symbols enc ON enc.id = r.enclosing_symbol_id " +
       "LEFT JOIN member_accesses ma ON ma.ref_id = r.id LEFT JOIN symbols m ON m.id = ma.member_symbol_id " +
       "LEFT JOIN symbols a ON a.id = ma.accessor_symbol_id WHERE r.kind = 'member-access'"
  $j = & $exePath sql --db $db --query $q --json | Out-String | ConvertFrom-Json
  $cols = @($j.columns | ForEach-Object { $_.name })
  $m = @{}
  foreach ($row in $j.rows) {
    $o = @{}; for ($i = 0; $i -lt $cols.Count; $i++) { $o[$cols[$i]] = $row[$i] }
    $m[[string]$o['site']] = $o
  }
  Check 'shape: the access map is populated' ($m.Count -ge 8) "rows=$($m.Count)"
  function Acc([string]$label, [string]$site, [string]$member, [string]$mode, [string]$accessor) {
    $e = $m[$site]
    if ($null -eq $e) { Check $label $false "no ref from $site"; return }
    $ok = ($e['bound'] -eq $member) -and ($e['mode'] -eq $mode) -and ([string]$e['accessor'] -eq $accessor)
    Check $label $ok "got member=$($e['bound']) mode=$($e['mode']) accessor=$($e['accessor'])"
  }
  Acc 'REDECLARED: read echoes the ancestor getter'     'RedRead'  'uProp.TMid.Val'   'read'  'uProp.TBase.GetVal'
  Acc 'REDECLARED: write echoes the ancestor setter'    'RedWrite' 'uProp.TMid.Val'   'write' 'uProp.TBase.SetVal'
  Acc 'REDECLARED: two levels up'                       'RedTwice' 'uProp.TLeaf.Val'  'read'  'uProp.TBase.GetVal'
  Acc 'REDECLARED: a default clause, field accessor'    'RedField' 'uProp.TMid.Fld'   'read'  'uProp.TBase.FField'
  Acc 'REDECLARED: an indexed property keeps its arity' 'RedIndex' 'uProp.TMid.Items' 'read'  'uProp.TBase.GetItem'
  Acc 'PARTIAL: the read clause is inherited'           'PartRead' 'uProp.TMid.Part'  'read'  'uProp.TBase.FField'
  Acc 'DOTTED: a read echoes the leftmost field'        'DotRead'  'uProp.TBase.Dot'  'read'  'uProp.TBase.FRec'
  Acc 'DOTTED: a write echoes the leftmost field'       'DotWrite' 'uProp.TBase.Dot'  'write' 'uProp.TBase.FRec'
  Acc 'CONTROL: the write clause is its own'          'PartWrite' 'uProp.TMid.Part' 'write' 'uProp.TBase.SetOther'
  Acc 'CONTROL: a full redeclaration shadows'           'ShadowRead' 'uProp.TLeaf.Plain' 'read' 'uProp.TBase.FField'
  Acc 'CONTROL: no ancestor declares it, no accessor'   'LostRead' 'uProp.TNoAnc.Lost' 'read' ''

  $c = & $exePath query find-callers --name GetVal --resolved --db $db *>&1 | Out-String
  Check 'END TO END: find-callers GetVal lists the redeclared reads' (($c -match 'RedRead') -and ($c -match 'RedTwice')) ($c -replace '\s+', ' ')
} finally {
  Pop-Location
  if (Test-Path -LiteralPath $scratch) { [IO.Directory]::Delete($scratch, $true) }
}
if ($script:fail) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
