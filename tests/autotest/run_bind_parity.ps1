<#
  run_bind_parity.ps1 -- E-BIND-PARITY-GUARD (backlog 2026-11-06).

  CONTRACT: a dotted call `Recv.M(...)` whose receiver has a declared type that owns (or
  inherits) a method named M must end with a call_edges row. An unbound site makes
  find-callers / impact / call-path / uses-audit answer SHORT, never visibly wrong.

  The fixture holds one class with Run/Next and every receiver shape the resolver is
  known to type: field, Self.field, property, public field, parameter, inherited-class
  parameter, class cast, Result, for-in variable, local, unit global, `with`.
  Every `.Run` call site in the fixture must bind to uA.TWorker.Run.

  KNOWN GAP (reported, not asserted): `FW.Next.Run` -- a call on a function RESULT that is
  itself a dotted call -- stays unbound. When it starts binding this guard prints
  "KNOWN GAP CLOSED": move ViaChain into the asserted list.

  POSITIVE CONTROL: ViaUnknown calls Run on a receiver of an undeclared type; it must stay
  unbound, and the checker, asked to assert it, must flag exactly that site. Without it a
  checker that matched nothing would pass vacuously.
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\drag-lint-bind-parity-$PID"
)
$ErrorActionPreference = 'Stop'
$script:Failed = $false
function Check($n, $ok, $d = '') {
  $s = if ($ok) { 'PASS' } else { 'FAIL' }
  Write-Host ("  [{0}] {1} {2}" -f $s, $n, $d) -ForegroundColor $(if ($ok) { 'Green' } else { 'Red' })
  if (-not $ok) { $script:Failed = $true }
}
if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
$Exe = (Resolve-Path $Exe).Path
try {
  [void][IO.Directory]::CreateDirectory($WorkDir)
  $text = @'
unit uA;

interface

type
  TWorker = class
    procedure Run;
    function Next: TWorker;
  end;

  TKid = class(TWorker)
  end;

  TOwner = class
  private
    FW: TWorker;
  public
    Pub: TWorker;
    property Prop: TWorker read FW;
    procedure ViaField;
    procedure ViaSelfField;
    procedure ViaProp;
    procedure ViaPub;
    procedure ViaParam(pW: TWorker);
    procedure ViaChain;
    procedure ViaInherited(pK: TKid);
    procedure ViaCast(pO: TObject);
    procedure ViaUnknown(pU: TNoSuchType);
    function ViaResult: TWorker;
    procedure ViaFor(const pL: array of TWorker);
  end;

var
  GW: TWorker;

procedure ViaLocal;
procedure ViaGlobal;
procedure ViaWith;

implementation

procedure TWorker.Run;
begin
end;

function TWorker.Next: TWorker;
begin
  Result := Self;
end;

procedure TOwner.ViaField;
begin
  FW.Run;
end;

procedure TOwner.ViaSelfField;
begin
  Self.FW.Run;
end;

procedure TOwner.ViaProp;
begin
  Prop.Run;
end;

procedure TOwner.ViaPub;
begin
  Pub.Run;
end;

procedure TOwner.ViaParam(pW: TWorker);
begin
  pW.Run;
end;

procedure TOwner.ViaChain;
begin
  FW.Next.Run;
end;

procedure TOwner.ViaInherited(pK: TKid);
begin
  pK.Run;
end;

procedure TOwner.ViaUnknown(pU: TNoSuchType);
begin
  pU.Run;
end;

procedure TOwner.ViaCast(pO: TObject);
begin
  TWorker(pO).Run;
end;

function TOwner.ViaResult: TWorker;
begin
  Result := FW;
  Result.Run;
end;

procedure TOwner.ViaFor(const pL: array of TWorker);
var
  W: TWorker;
begin
  for W in pL do
    W.Run;
end;

procedure ViaLocal;
var
  W: TWorker;
begin
  W := TWorker.Create;
  W.Run;
end;

procedure ViaGlobal;
begin
  GW.Run;
end;

procedure ViaWith;
var
  W: TWorker;
begin
  with W do
    Run;
end;

end.
'@
  [IO.File]::WriteAllText((Join-Path $WorkDir 'uA.pas'), ($text -replace "`r`n", "`n" -replace "`n", "`r`n"), [Text.Encoding]::ASCII)
  $db = Join-Path $WorkDir 'bp.sqlite'
  & $Exe index $WorkDir --db $db --quiet 2>&1 | Out-Null

  # Routine name -> bound target (or '-') for every call ref named Run; sql --json rows are positional.
  function Get-RunSites([string]$Db) {
    $q = "select en.name, ifnull((select group_concat(t.qualified_name) from call_edges e join symbols t on t.id=e.target_symbol_id where e.ref_id=r.id),'-') from refs r join symbols en on en.id=r.enclosing_symbol_id where r.kind='call' and r.name_text='Run' order by en.name"
    $j = (& $Exe sql --db $Db --query $q --json 2>$null | Out-String) | ConvertFrom-Json
    $h = [ordered]@{}
    foreach ($row in $j.rows) { $h[[string]$row[0]] = [string]$row[1] }
    return $h
  }

  $asserted = 'ViaCast','ViaField','ViaFor','ViaGlobal','ViaInherited','ViaLocal','ViaParam','ViaProp','ViaPub','ViaResult','ViaSelfField','ViaWith'
  $sites = Get-RunSites $db
  Write-Host 'dotted .Run call sites' -ForegroundColor Cyan
  Check 'the checker sees every routine (14 sites)' ($sites.Count -eq 14) "sites=$($sites.Count)"
  foreach ($r in $asserted) {
    Check "$r binds to uA.TWorker.Run" ($sites.Contains($r) -and $sites[$r] -ceq 'uA.TWorker.Run') "got=$($sites[$r])"
  }
  if ($sites.Contains('ViaChain') -and $sites['ViaChain'] -ne '-') { Write-Host '  KNOWN GAP CLOSED: ViaChain binds now; assert it.' -ForegroundColor Yellow }
  else { Write-Host '  known gap (not asserted): ViaChain  FW.Next.Run unbound' -ForegroundColor DarkYellow }

  Write-Host 'positive control: a receiver of unknown type must stay unbound, and the checker must say so' -ForegroundColor Cyan
  Check 'ViaUnknown (pU: TNoSuchType) is a Run site with NO edge' ($sites.Contains('ViaUnknown') -and ($sites['ViaUnknown'] -ceq '-')) "got=$($sites['ViaUnknown'])"
  $bad = @(($asserted + 'ViaUnknown') | Where-Object { -not ($sites.Contains($_) -and $sites[$_] -ceq 'uA.TWorker.Run') })
  Check 'the checker flags exactly that site when it is asserted' (($bad.Count -eq 1) -and ($bad[0] -ceq 'ViaUnknown')) "unbound=$($bad -join ',')"
} finally {
  if (Test-Path -LiteralPath $WorkDir) { try { [IO.Directory]::Delete($WorkDir, $true) } catch { Write-Host "WARN: could not remove $WorkDir" } }
}
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
