<#
  run_recv_intrinsic_latebound.ps1 -- spec 2026-11-06-recv-undecidable, classes D08 and D10:
  dotted calls that have NO routine to bind to, reported by name instead of as plain misses.

    D08 a dynamic-array constructor: `TBytes.Create(1, 2)`, `TArray<Integer>.Create(1)`.
        A compiler intrinsic -- no declaration exists. Counted as `intrinsic`.
    D10 a call through an event property: `B.OnClick(nil)`. The routine behind it is chosen
        at run time. Counted as `late-bound`.

  CLASSIFY ONLY: the resolve line `calls receivers: ...` gains the two counters; no stored
  row changes (the sites stay with no edge and no external target -- asserted). Controls: a
  library method binds (`B.Click`), a library class constructor binds (`TStrX.Create`), an
  unknown type head stays `no-type` and is not counted intrinsic (`TNope.Create`), a field of a
  procedural type is late-bound too (`B.FOnPing`), a non-Create member of a dynamic array type
  is not intrinsic (`TBytes.Nothing`).
  Run from any CWD, pwsh 7.
#>
[CmdletBinding()]
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
$j = & $exePath sql --db $appDb --json --limit 2000 --query "SELECT '' p, r.receiver_text, r.name_text, coalesce(r.external_target,''), coalesce(t.qualified_name,'') FROM refs r LEFT JOIN call_edges c ON c.ref_id = r.id LEFT JOIN symbols t ON t.id = c.target_symbol_id WHERE r.kind = 'call' AND r.receiver_text <> ''" | Out-String | ConvertFrom-Json
Pop-Location

$line = @($log -split "`r?`n" | Where-Object { $_ -match 'calls\s+receivers:' }) | Select-Object -First 1
Check 'V the resolve receivers line was printed' ($null -ne $line) ''
$intr = if ($line -match 'intrinsic (\d+)') { [int]$Matches[1] } else { -1 }
$late = if ($line -match 'late-bound (\d+)') { [int]$Matches[1] } else { -1 }
Check "D08 intrinsic = 2 (TBytes.Create, TArray<Integer>.Create; not TBytes.Nothing, not TNope.Create) -- got $intr" ($intr -eq 2) $line
Check "D10 late-bound = 2 (B.OnClick property, B.FOnPing field) -- got $late" ($late -eq 2) $line

$rows = foreach ($r in $j.rows) { [pscustomobject]@{ Rcv=[string]$r[1]; Name=[string]$r[2]; Ext=[string]$r[3]; Edge=[string]$r[4] } }
Check "V the sites were read ($(@($rows).Count))" (@($rows).Count -ge 8)
function Site($rcv,$name){ @($rows | Where-Object { $_.Rcv -eq $rcv -and $_.Name -eq $name }) | Select-Object -First 1 }
function None($id,$rcv,$name){
  $s = Site $rcv $name
  Check "$id $rcv.$name stays unbound -- classify only (got ext='$($s.Ext)' edge='$($s.Edge)')" ($null -ne $s -and $s.Ext -eq '' -and $s.Edge -eq '')
}
function Ext($id,$rcv,$name,$want){
  $s = Site $rcv $name
  Check "$id CONTROL $rcv.$name -> external $want (got ext='$($s.Ext)' edge='$($s.Edge)')" ($null -ne $s -and $s.Ext -ceq $want -and $s.Edge -eq '')
}
None 'D08a' 'TBytes' 'Create'
None 'D08b' 'TArray<Integer>' 'Create'
None 'D10a' 'B' 'OnClick'
None 'D10b' 'B' 'FOnPing'
Ext  'C1' 'B' 'Click' 'Lib.Controls.TButtonX.Click'
Ext  'C2' 'TStrX' 'Create' 'Lib.Controls.TStrX.Create'

Write-Host ''
if ($script:fail) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'PASS' -ForegroundColor Green; exit 0
} finally {
  if (Test-Path -LiteralPath "C:\TEMP\draglint_recv_intrinsic_$PID") { [IO.Directory]::Delete("C:\TEMP\draglint_recv_intrinsic_$PID", $true) }
}
