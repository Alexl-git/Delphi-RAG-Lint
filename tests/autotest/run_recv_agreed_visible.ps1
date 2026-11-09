<#
  run_recv_agreed_visible.ps1 -- spec 2026-11-06-recv-undecidable, wave-146 b7 leftover
  (`List.Free` on TAccountList = TList<TAccountInfo>, ORM3 OperatorList.pas):
  a type name with several library candidates answers when every candidate gives the SAME
  member (b7's AgreedMember) -- but it asked EVERY candidate in the library, so one the file
  cannot see (a third TList, in a unit nobody uses, whose parent no store holds) vetoed it.
  A unit the file does not use cannot be what the name means.

  Pins: uses Lib.A + Lib.B (two visible TList, both reach TObject.Free) -> L.Free binds
  System.TObject.Free although Lib.C's TList (unknown parent) exists; controls: with Lib.C
  also used the veto stands (unbound); a member the visible candidates disagree on
  (`L.Add`, declared differently in Lib.A and Lib.B) stays unbound.
  Run from any CWD, pwsh 7.
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe",
  [string]$WorkDir = "C:\TEMP\draglint_recv_agreed_$PID"
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
    procedure Free;
  end;
implementation
procedure TObject.Free; begin end;
end.
'@
W $lib 'Lib.A.pas' @'
unit Lib.A;
interface
type
  TList = class
  public
    procedure Add(P: Pointer);
  end;
implementation
procedure TList.Add(P: Pointer); begin end;
end.
'@
W $lib 'Lib.B.pas' @'
unit Lib.B;
interface
type
  TList = class(TObject)
  public
    procedure Add(const S: string);
  end;
implementation
procedure TList.Add(const S: string); begin end;
end.
'@
W $lib 'Lib.C.pas' @'
unit Lib.C;
interface
type
  TList = class(TMissingBase)
  end;
implementation
end.
'@

W $lib 'Lib.G.pas' @'
unit Lib.G;
interface
type
  TList<T> = class(TObject)
  public
    procedure Add(const V: T);
  end;
implementation
procedure TList<T>.Add(const V: T); begin end;
end.
'@

W $app 'uSee.pas' @'
unit uSee;
interface
uses Lib.A, Lib.B;
procedure GoSee;
implementation
procedure GoSee;
var
  L: TList;
begin
  L.Free;
  L.Add(nil);
end;
end.
'@
W $app 'uAll.pas' @'
unit uAll;
interface
uses Lib.A, Lib.B, Lib.C;
procedure GoAll;
implementation
procedure GoAll;
var
  L: TList;
begin
  L.Free;
end;
end.
'@
W $app 'uAlias.pas' @'
unit uAlias;
interface
uses Lib.A, Lib.G;
type
  TAccList = TList<Integer>;
procedure GoAlias;
implementation
procedure GoAlias;
var
  L: TAccList;
begin
  L.Free;
  L.Add(1);
end;
end.
'@
W $app 'App.dpr' @'
program App;
uses
  uSee in 'uSee.pas',
  uAll in 'uAll.pas',
  uAlias in 'uAlias.pas';
begin
end.
'@

$libDb = Join-Path $WorkDir 'lib.sqlite'; $appDb = Join-Path $WorkDir 'app.sqlite'
Push-Location C:\TEMP
& $exePath index $lib --db $libDb 2>&1 | Out-Null
Check 'V library index built' (Test-Path $libDb) $libDb
& $exePath index --project (Join-Path $app 'App.dpr') --db $appDb --library-db $libDb 2>&1 | Out-Null
Check 'V app index built' (Test-Path $appDb) $appDb
$j = & $exePath sql --db $appDb --json --limit 2000 --query "SELECT '' p, f.path, r.receiver_text, r.name_text, coalesce(r.external_target,'') FROM refs r JOIN files f ON f.id = r.file_id WHERE r.kind = 'call' AND r.receiver_text <> ''" | Out-String | ConvertFrom-Json
Pop-Location

$rows = foreach ($r in $j.rows) { [pscustomobject]@{ File=[IO.Path]::GetFileNameWithoutExtension([string]$r[1]); Rcv=[string]$r[2]; Name=[string]$r[3]; Ext=[string]$r[4] } }
Check "V the sites were read ($(@($rows).Count))" (@($rows).Count -ge 5)
function Site($file,$rcv,$name){ @($rows | Where-Object { $_.File -eq $file -and $_.Rcv -eq $rcv -and $_.Name -eq $name }) | Select-Object -First 1 }
$s = Site 'uSee' 'L' 'Free'
Check "A1 uSee L.Free -> System.TObject.Free (got '$($s.Ext)')" ($null -ne $s -and $s.Ext -ceq 'System.TObject.Free')
$s = Site 'uAll' 'L' 'Free'
Check "A2 CONTROL uAll L.Free stays unbound: the visible Lib.C TList has an unknown parent (got '$($s.Ext)')" ($null -ne $s -and $s.Ext -eq '')
$s = Site 'uSee' 'L' 'Add'
Check "A3 CONTROL uSee L.Add stays unbound: the visible candidates disagree (got '$($s.Ext)')" ($null -ne $s -and $s.Ext -eq '')

$s = Site 'uAlias' 'L' 'Free'
Check "A4 uAlias L.Free on a generic alias (TAccList = TList<Integer>, no ancestor row) -> System.TObject.Free (got '$($s.Ext)')" ($null -ne $s -and $s.Ext -ceq 'System.TObject.Free')
$s = Site 'uAlias' 'L' 'Add'
Check "A5 CONTROL uAlias L.Add stays unbound: Lib.A and Lib.G disagree (got '$($s.Ext)')" ($null -ne $s -and $s.Ext -eq '')

Write-Host ''
if ($script:fail) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'PASS' -ForegroundColor Green; exit 0
} finally {
  if (Test-Path -LiteralPath "C:\TEMP\draglint_recv_agreed_$PID") { [IO.Directory]::Delete("C:\TEMP\draglint_recv_agreed_$PID", $true) }
}
