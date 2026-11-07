<#
  run_parenless_chain_bind.ps1 -- lane 146 b8.

  CONTRACT: in a plain dotted receiver the resolver walks (`H.Get.Next`), a segment that is no
  field or property but a method of the current type stands for that method's RESULT when the
  method is callable with no arguments and is the single certain candidate. Every later hop
  then binds and gets a ref_types row, exactly as if the segment had been written `Get()`.

  A wrong binding is worse than none, so the walk must still DECLINE on: a method that needs an
  argument, a procedure, an override pair, a function of an unknown type. A field or property of
  the name beats the method. A dotted type name (`uChainB.TThing.Make`) keeps its old answer.

  POSITIVE CONTROL: on the base engine (-Exe <base>) the parenless "binds" checks FAIL and every
  "declines" check passes. ViaParens (`H.Get().Next`) binds on either engine: if it failed, the
  checker would be reading nothing. Rows are read through columns[].name, never by position.
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\drag-lint-parenless-chain-$PID"
)
$ErrorActionPreference = 'Stop'
$script:Failed = $false
$script:Count = 0
function Check($n, $ok, $d = '') {
  $script:Count++
  $s = if ($ok) { 'PASS' } else { 'FAIL' }
  Write-Host ("  [{0}] {1} {2}" -f $s, $n, $d) -ForegroundColor $(if ($ok) { 'Green' } else { 'Red' })
  if (-not $ok) { $script:Failed = $true }
}
if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
$Exe = (Resolve-Path $Exe).Path
try {
  [void][IO.Directory]::CreateDirectory($WorkDir)
  $b = @'
unit uChainB;

interface

type
  TThing = class
    class function Make: TThing;
  end;

implementation

class function TThing.Make: TThing; begin Result := nil; end;

end.
'@
  $a = @'
unit uChainA;

interface

uses uChainB;

type
  TOther = class
    procedure Run;
  end;

  TWorker = class
    procedure Run;
    procedure Fill(pN: Integer);
    function Next: TWorker;
    function Defaulted(pN: Integer = 0): TWorker;
    function NeedsArg(pN: Integer): TWorker;
    function Lost: TNoSuchType;
    function Over: TWorker; overload;
    function Over(pN: Integer): TOther; overload;
    procedure Proc;
    function Virt: TWorker; virtual;
    function Sibling: TOther;
  end;

  TKid = class(TWorker)
    function Virt: TWorker; override;
  end;

  THider = class(TWorker)
  public
    Sibling: TWorker;
  end;

  TGet = class
    procedure Run;
  end;

  THolder = class
  private
    FW: TWorker;
    FK: TKid;
    FH: THider;
  public
    function Get: TWorker;
    function TGet: TWorker;
    procedure ViaParens;
    procedure ViaBare;
    procedure ViaTwo;
    procedure ViaEmptyCall;
    procedure ViaFill;
    procedure ViaField;
    procedure ViaHead;
    procedure ViaWith;
    procedure ViaDefaulted;
    procedure ViaOverload;
    procedure ViaNeedsArg;
    procedure ViaProc;
    procedure ViaLost;
    procedure ViaOverride;
    procedure ViaFieldWins;
    procedure ViaDottedType;
    procedure ViaNameIsAType;
  end;

implementation

procedure TOther.Run; begin end;
procedure TWorker.Run; begin end;
procedure TWorker.Fill(pN: Integer); begin end;
function TWorker.Next: TWorker; begin Result := Self; end;
function TWorker.Defaulted(pN: Integer): TWorker; begin Result := Self; end;
function TWorker.NeedsArg(pN: Integer): TWorker; begin Result := Self; end;
function TWorker.Lost: TNoSuchType; begin end;
function TWorker.Over: TWorker; begin Result := Self; end;
function TWorker.Over(pN: Integer): TOther; begin Result := nil; end;
procedure TWorker.Proc; begin end;
function TWorker.Virt: TWorker; begin Result := Self; end;
function TWorker.Sibling: TOther; begin Result := nil; end;
function TKid.Virt: TWorker; begin Result := Self; end;
procedure TGet.Run; begin end;
function THolder.Get: TWorker; begin Result := FW; end;
function THolder.TGet: TWorker; begin Result := FW; end;

procedure THolder.ViaParens;
var H: THolder; X: TObject;
begin
  X := H.Get().Next;
end;

procedure THolder.ViaBare;
var H: THolder; X: TObject;
begin
  X := H.Get.Next;
end;

procedure THolder.ViaTwo;
var H: THolder; X: TObject;
begin
  X := H.Get.Next.Next;
end;

procedure THolder.ViaEmptyCall;
var H: THolder; X: TObject;
begin
  X := H.Get.Next();
end;

procedure THolder.ViaFill;
var H: THolder;
begin
  H.Get.Next.Fill(1);
end;

procedure THolder.ViaField;
begin
  FW.Next.Run;
end;

procedure THolder.ViaHead;
begin
  Get.Next.Run;
end;

procedure THolder.ViaWith;
var H: THolder;
begin
  with H do Get.Next.Run;
end;

procedure THolder.ViaDefaulted;
begin
  FW.Defaulted.Run;
end;

procedure THolder.ViaOverload;
begin
  FW.Over.Run;
end;

procedure THolder.ViaNeedsArg;
begin
  FW.NeedsArg.Run;
end;

procedure THolder.ViaProc;
begin
  FW.Proc.Run;
end;

procedure THolder.ViaLost;
begin
  FW.Lost.Run;
end;

procedure THolder.ViaOverride;
begin
  FK.Virt.Run;
end;

procedure THolder.ViaFieldWins;
begin
  FH.Sibling.Run;
end;

procedure THolder.ViaDottedType;
begin
  uChainB.TThing.Make;
end;

procedure THolder.ViaNameIsAType;
var H: THolder;
begin
  H.TGet.Run;
end;

end.
'@
  [IO.File]::WriteAllText("$WorkDir\uChainA.pas", ($a -replace "`r?`n", "`r`n") + "`r`n")
  [IO.File]::WriteAllText("$WorkDir\uChainB.pas", ($b -replace "`r?`n", "`r`n") + "`r`n")
  $db = "$WorkDir\t.sqlite"
  Push-Location $WorkDir
  try { & $Exe index $WorkDir --db $db *>&1 | Out-Null } finally { Pop-Location }
  Check 'index ran' (Test-Path $db)

  $q = "select e.qualified_name as encl, r.kind, r.name_text as name, r.receiver_text as rcv, " +
       "coalesce(t.qualified_name,'-') as target, coalesce(ty.type_qname,'-') as typ, coalesce(s.qualified_name,'-') as sym " +
       "from refs r join symbols e on e.id = r.enclosing_symbol_id " +
       "left join call_edges ce on ce.ref_id = r.id left join symbols t on t.id = ce.target_symbol_id " +
       "left join symbols s on s.id = r.symbol_id and r.symbol_id > 0 left join ref_types ty on ty.ref_id = r.id " +
       "where r.receiver_text is not null and r.receiver_text <> '' order by r.start_line, r.start_col"
  $j = & $Exe sql --db $db --query $q --json | Out-String | ConvertFrom-Json
  $names = @($j.columns | ForEach-Object { $_.name })
  $rows = foreach ($r in $j.rows) {
    $o = [ordered]@{}
    for ($i = 0; $i -lt $names.Count; $i++) { $o[$names[$i]] = $r[$i] }
    [pscustomobject]$o
  }
  Check 'rows read' ($rows.Count -gt 20) "rows=$($rows.Count)"

  # The row of site <via>, hop <name>, receiver <rcv>: a bound row wins over its unbound twin.
  function Hop($via, $name, $rcv) {
    $hit = @($rows | Where-Object { $_.encl -like "*.$via" -and $_.name -eq $name -and $_.rcv -eq $rcv })
    $bound = @($hit | Where-Object { $_.sym -ne '-' })
    if ($bound.Count -gt 0) { $bound[0] } elseif ($hit.Count -gt 0) { $hit[0] } else { $null }
  }
  function Binds($via, $name, $rcv, $want, $typ = '') {
    $h = Hop $via $name $rcv
    $got = if ($h) { $h.sym } else { '<no ref>' }
    Check "$via binds $rcv.$name" ($h -and $got -eq $want) "got $got"
    if ($typ -ne '') {
      $gt = if ($h) { $h.typ } else { '<no ref>' }
      Check "$via types $rcv.$name" ($gt -eq $typ) "got $gt"
    }
  }
  function Declines($via, $name, $rcv) {
    $h = Hop $via $name $rcv
    Check "$via declines $rcv.$name" ($h -and $h.sym -eq '-' -and $h.target -eq '-') "got $(if ($h) { $h.sym } else { '<no ref>' })"
  }

  Binds 'ViaParens'      'Next' 'H.Get()'        'uChainA.TWorker.Next' 'uChainA.TWorker'
  Binds 'ViaBare'        'Next' 'H.Get'          'uChainA.TWorker.Next' 'uChainA.TWorker'
  Binds 'ViaTwo'         'Next' 'H.Get'          'uChainA.TWorker.Next' 'uChainA.TWorker'
  Binds 'ViaTwo'         'Next' 'H.Get.Next'     'uChainA.TWorker.Next' 'uChainA.TWorker'
  Binds 'ViaEmptyCall'   'Next' 'H.Get'          'uChainA.TWorker.Next' 'uChainA.TWorker'
  Binds 'ViaFill'        'Next' 'H.Get'          'uChainA.TWorker.Next' 'uChainA.TWorker'
  Binds 'ViaFill'        'Fill' 'H.Get.Next'     'uChainA.TWorker.Fill'
  Binds 'ViaField'       'Run'  'FW.Next'        'uChainA.TWorker.Run'
  Binds 'ViaHead'        'Run'  'Get.Next'       'uChainA.TWorker.Run'
  Binds 'ViaWith'        'Run'  'Get.Next'       'uChainA.TWorker.Run'
  Binds 'ViaDefaulted'   'Run'  'FW.Defaulted'   'uChainA.TWorker.Run'
  Binds 'ViaOverload'    'Run'  'FW.Over'        'uChainA.TWorker.Run'
  Binds 'ViaFieldWins'   'Run'  'FH.Sibling'     'uChainA.TWorker.Run'
  Binds 'ViaDottedType'  'Make' 'uChainB.TThing' 'uChainB.TThing.Make'
  Binds 'ViaNameIsAType' 'Run'  'H.TGet'         'uChainA.TWorker.Run'

  Declines 'ViaNeedsArg' 'Run' 'FW.NeedsArg'
  Declines 'ViaProc'     'Run' 'FW.Proc'
  Declines 'ViaLost'     'Run' 'FW.Lost'
  Declines 'ViaOverride' 'Run' 'FK.Virt'
}
finally {
  if (Test-Path $WorkDir) { [IO.Directory]::Delete($WorkDir, $true) }
}
Write-Host ("run_parenless_chain_bind: {0} checks" -f $script:Count)
if ($script:Failed) { Write-Host 'run_parenless_chain_bind: FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'run_parenless_chain_bind: PASS' -ForegroundColor Green
exit 0
