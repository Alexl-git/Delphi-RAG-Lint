<#
  run_recv_intrinsic_latebound.ps1 -- spec 2026-11-06-recv-undecidable, classes D08 and D10,
  owner ruling 2026-11-08 (wave 147): BIND both, marked.

    D08 a dynamic-array constructor: `TBytes.Create(1, 2)`, `TArray<Integer>.Create(1)`.
        A compiler intrinsic -- no declaration exists. Bound to the synthetic built-in name
        System.@intrinsic.DynArray.Create, refs.external_kind = 'intrinsic'.
    D10 a call through an event property or procedural field: `B.OnClick(nil)`. Bound to the
        PROPERTY (field) by name, refs.external_kind = 'indirect' -- the routine behind it is
        chosen at run time, so it is never an edge to a routine.

  The resolve line `calls receivers:` counts them as `intrinsic` / `late-bound` (not in
  external-bound). find-callers on the property lists the firing site with mode `event`; an
  intrinsic row carries mode `built-in`. Controls: a library method binds with no kind
  (`B.Click`), a library class constructor too (`TStrX.Create`), an unknown type head stays
  unbound (`TNope.Create`), a non-Create member of a dynamic array type is not intrinsic
  (`TBytes.Nothing`), the member-access twin of `B.OnClick` keeps its plain property binding.
  Run from any CWD, pwsh 7.
#>[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe",
  [string]$WorkDir = "C:\TEMP\draglint_recv_intrinsic_$PID"
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
$lib = Join-Path $WorkDir 'lib'; $app = Join-Path $WorkDir 'app'
New-Item -ItemType Directory -Path $lib,$app | Out-Null

W $lib 'System.pas' @'
unit System;
interface
type
  TObject = class
  public
    constructor Create;
    procedure Free;
  end;
  TArray<T> = array of T;
implementation
constructor TObject.Create; begin end;
procedure TObject.Free; begin end;
end.
'@
W $lib 'System.SysUtils.pas' @'
unit System.SysUtils;
interface
type
  TBytes = TArray<Byte>;
implementation
end.
'@
W $lib 'Lib.Controls.pas' @'
unit Lib.Controls;
interface
type
  TNotifyEvent = procedure(Sender: TObject) of object;
  TButtonX = class(TObject)
  private
    FOnClick: TNotifyEvent;
  public
    FOnPing: TNotifyEvent;
    procedure Click;
    property OnClick: TNotifyEvent read FOnClick write FOnClick;
  end;
  TStrX = class(TObject)
  public
    constructor Create;
  end;
implementation
procedure TButtonX.Click; begin end;
constructor TStrX.Create; begin end;
end.
'@

W $app 'uGo.pas' @'
unit uGo;
interface
uses System.SysUtils, Lib.Controls;
procedure Go;
implementation
procedure Go;
var
  B: TButtonX;
begin
  TBytes.Create(1, 2);
  TArray<Integer>.Create(1);
  TBytes.Nothing;
  TNope.Create;
  B.OnClick(nil);
  B.FOnPing(nil);
  B.Click;
  TStrX.Create;
end;
end.
'@
W $app 'App.dpr' @'
program App;
uses
  uGo in 'uGo.pas';
begin
end.
'@

$libDb = Join-Path $WorkDir 'lib.sqlite'; $appDb = Join-Path $WorkDir 'app.sqlite'
Push-Location C:\TEMP
& $exePath index $lib --db $libDb 2>&1 | Out-Null
Check 'V library index built' (Test-Path $libDb) $libDb
$log = & $exePath index --project (Join-Path $app 'App.dpr') --db $appDb --library-db $libDb 2>&1 | Out-String
Check 'V app index built' (Test-Path $appDb) $appDb
$j = & $exePath sql --db $appDb --json --limit 2000 --query "SELECT '' p, r.receiver_text, r.name_text, coalesce(r.external_target,''), coalesce(t.qualified_name,''), r.kind, coalesce(r.external_kind,'') FROM refs r LEFT JOIN call_edges c ON c.ref_id = r.id LEFT JOIN symbols t ON t.id = c.target_symbol_id WHERE r.receiver_text <> '' AND r.kind IN ('call','member-access')" | Out-String | ConvertFrom-Json
$fc = & $exePath query find-callers --name OnClick --db $appDb --json 2>$null | Out-String
$cx = & $exePath context --task "modify uGo.Go" --db $appDb --format markdown 2>$null | Out-String
Pop-Location

$line = @($log -split "`r?`n" | Where-Object { $_ -match 'calls\s+receivers:' }) | Select-Object -First 1
Check 'V the resolve receivers line was printed' ($null -ne $line) ''
$intr = if ($line -match 'intrinsic (\d+)') { [int]$Matches[1] } else { -1 }
$late = if ($line -match 'late-bound (\d+)') { [int]$Matches[1] } else { -1 }
Check "D08 intrinsic = 2 (TBytes.Create, TArray<Integer>.Create; not TBytes.Nothing, not TNope.Create) -- got $intr" ($intr -eq 2) $line
Check "D10 late-bound = 2 (B.OnClick property, B.FOnPing field) -- got $late" ($late -eq 2) $line

$rows = foreach ($r in $j.rows) { [pscustomobject]@{ Rcv=[string]$r[1]; Name=[string]$r[2]; Ext=[string]$r[3]; Edge=[string]$r[4]; Kind=[string]$r[5]; XK=[string]$r[6] } }
Check "V the sites were read ($(@($rows).Count))" (@($rows).Count -ge 8)
function Site($rcv,$name,$kind){ @($rows | Where-Object { $_.Rcv -eq $rcv -and $_.Name -eq $name -and $_.Kind -eq $kind }) | Select-Object -First 1 }
function Bound($id,$rcv,$name,$want,$xk){
  $s = Site $rcv $name 'call'
  Check "$id $rcv.$name -> external $want, kind '$xk' (got ext='$($s.Ext)' kind='$($s.XK)' edge='$($s.Edge)')" ($null -ne $s -and $s.Ext -ceq $want -and $s.XK -eq $xk -and $s.Edge -eq '')
}
function None($id,$rcv,$name){
  $s = Site $rcv $name 'call'
  Check "$id CONTROL $rcv.$name stays unbound (got ext='$($s.Ext)' kind='$($s.XK)')" ($null -ne $s -and $s.Ext -eq '' -and $s.XK -eq '' -and $s.Edge -eq '')
}
Bound 'D08a' 'TBytes' 'Create' 'System.@intrinsic.DynArray.Create' 'intrinsic'
Bound 'D08b' 'TArray<Integer>' 'Create' 'System.@intrinsic.DynArray.Create' 'intrinsic'
Bound 'D10a' 'B' 'OnClick' 'Lib.Controls.TButtonX.OnClick' 'indirect'
Bound 'D10b' 'B' 'FOnPing' 'Lib.Controls.TButtonX.FOnPing' 'indirect'
Bound 'C1' 'B' 'Click' 'Lib.Controls.TButtonX.Click' ''
Bound 'C2' 'TStrX' 'Create' 'Lib.Controls.TStrX.Create' ''
None  'C3' 'TNope' 'Create'
None  'C4' 'TBytes' 'Nothing'
$m = Site 'B' 'OnClick' 'member-access'
Check "C5 CONTROL B.OnClick member-access twin keeps the plain property binding (got ext='$($m.Ext)' kind='$($m.XK)')" ($null -ne $m -and $m.Ext -ceq 'Lib.Controls.TButtonX.OnClick' -and $m.XK -eq '')
Check "F1 find-callers --name OnClick lists the firing site with mode event" ($fc -match '"mode"\s*:\s*"event"') ($fc.Substring(0,[Math]::Min(400,$fc.Length)))
$lc = @($cx -split "`r?`n" | Where-Object { $_ -match '^Library calls:' }) | Select-Object -First 1
Check "F2 context labels the built-in and the event (got '$lc')" ($lc -match 'System\.@intrinsic\.DynArray\.Create \(built-in\)' -and $lc -match 'TButtonX\.OnClick \(event\)' -and $lc -notmatch 'TButtonX\.Click \(')
Write-Host ''
if ($script:fail) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'PASS' -ForegroundColor Green; exit 0
} finally {
  if (Test-Path -LiteralPath "C:\TEMP\draglint_recv_intrinsic_$PID") { [IO.Directory]::Delete("C:\TEMP\draglint_recv_intrinsic_$PID", $true) }
}
