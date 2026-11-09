<#
  run_bare_call_own_uses.ps1 -- wave-146 x4 incidental (149 RB2 item 3): on ORM3 CLIENT the
  bare calls IntToStr (155), FreeAndNil (99) and UpperCase (50) had 0 external_target while
  Format bound 2035 times.

  THE DEFECT: TCallResolver.FileUsesUnits hands the library oracle the file's own uses PLUS
  the uses of every .dpr in the index. The CLIENT .dpr lists the EurekaLog units (EMemLeaks,
  ELowLevel, EResLeaks ...), which declare their own IntToStr / FreeAndNil / UpperCase, so
  BindBare saw two visible free routines of the name and answered ambiguous for every unit
  of the project -- although no unit that calls them uses a EurekaLog unit. A unit sees the
  units ITS uses clauses name (and System), never what the program file uses.

  THE FIX: BindBare decides on the file's own uses + System / SysInit first; only when that
  finds no routine at all does it fall back to the old, program-wide set (kept so a uses
  list the parser read short -- an {$IFDEF} branch, an include -- binds as before).

  Pins: A1 uOwn (uses System.SysUtils; the .dpr uses ELeaks) IntToStr / UpperCase /
  FreeAndNil -> System.SysUtils.*. CONTROLS: A2 uBoth uses System.SysUtils AND ELeaks: IntToStr
  stays unbound (two visible units declare it -- the tie is not this guard's to break);
  A3 uFall uses neither, LeakOnly (declared only in ELeaks, which the .dpr uses) still binds
  through the fallback; A4 Format, never in ELeaks, binds on both engines.
  A5: the same rule for a library TYPE tie (TLibraryOracle.Pick, OwnUses): B: TBox with Lib.Box in the
  file's uses and ELeaks (also declaring TBox) only in the .dpr -> Lib.Box.TBox.Go.
  POSITIVE CONTROL: on 1.48.0-alpha A1 (3 FAIL) and A5 are RED, A2-A4 are green.
  Run from any CWD, pwsh 7. Pass -Exe with the engine under test.
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe",
  [string]$WorkDir = "C:\TEMP\draglint_bare_own_uses_$PID"
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
W $lib 'System.SysUtils.pas' @'
unit System.SysUtils;
interface
function IntToStr(Value: Integer): string; overload;
function IntToStr(Value: Int64): string; overload;
function UpperCase(const S: string): string;
procedure FreeAndNil(var Obj);
function Format(const F: string; const Args: array of const): string;
implementation
function IntToStr(Value: Integer): string; begin Result:= ''; end;
function IntToStr(Value: Int64): string; begin Result:= ''; end;
function UpperCase(const S: string): string; begin Result:= S; end;
procedure FreeAndNil(var Obj); begin end;
function Format(const F: string; const Args: array of const): string; begin Result:= F; end;
end.
'@
W $lib 'ELeaks.pas' @'
unit ELeaks;
interface
function IntToStr(Value: Integer): string;
function UpperCase(const S: string): string;
procedure FreeAndNil(var Obj);
procedure LeakOnly;
type
  TBox = class
  public
    procedure Go;
  end;
implementation
procedure TBox.Go; begin end;
function IntToStr(Value: Integer): string; begin Result:= ''; end;
function UpperCase(const S: string): string; begin Result:= S; end;
procedure FreeAndNil(var Obj); begin end;
procedure LeakOnly; begin end;
end.
'@

W $lib 'Lib.Box.pas' @'
unit Lib.Box;
interface
type
  TBox = class
  public
    procedure Go;
  end;
implementation
procedure TBox.Go; begin end;
end.
'@
W $app 'uTyped.pas' @'
unit uTyped;
interface
uses Lib.Box;
procedure GoTyped;
implementation
procedure GoTyped;
var
  B: TBox;
begin
  B.Go;
end;
end.
'@
W $app 'uOwn.pas' @'
unit uOwn;
interface
uses System.SysUtils;
procedure GoOwn;
implementation
procedure GoOwn;
var
  O: TObject;
  S: string;
begin
  S:= IntToStr(1);
  S:= UpperCase(S);
  S:= Format(S, [1]);
  FreeAndNil(O);
end;
end.
'@
W $app 'uBoth.pas' @'
unit uBoth;
interface
uses System.SysUtils, ELeaks;
procedure GoBoth;
implementation
procedure GoBoth;
var
  S: string;
begin
  S:= IntToStr(2);
end;
end.
'@
W $app 'uFall.pas' @'
unit uFall;
interface
procedure GoFall;
implementation
procedure GoFall;
begin
  LeakOnly;
end;
end.
'@
W $app 'App.dpr' @'
program App;
uses
  ELeaks,
  uOwn in 'uOwn.pas',
  uBoth in 'uBoth.pas',
  uFall in 'uFall.pas',
  uTyped in 'uTyped.pas';
begin
end.
'@

$libDb = Join-Path $WorkDir 'lib.sqlite'; $appDb = Join-Path $WorkDir 'app.sqlite'
Push-Location C:\TEMP
& $exePath index $lib --db $libDb 2>&1 | Out-Null
Check 'V library index built' (Test-Path $libDb) $libDb
& $exePath index --project (Join-Path $app 'App.dpr') --db $appDb --library-db $libDb 2>&1 | Out-Null
Check 'V app index built' (Test-Path $appDb) $appDb
$raw = & $exePath sql --db $appDb --json --limit 2000 --query "SELECT f.path, r.name_text, coalesce(r.external_target,'') FROM refs r JOIN files f ON f.id = r.file_id WHERE r.kind = 'call' AND coalesce(r.receiver_text,'') = ''" | Out-String
Pop-Location
$j = $raw | ConvertFrom-Json
$rows = foreach ($r in $j.rows) { [pscustomobject]@{ File=[IO.Path]::GetFileNameWithoutExtension([string]$r[0]); Name=[string]$r[1]; Ext=[string]$r[2] } }
Check "V the sites were read ($(@($rows).Count))" (@($rows).Count -ge 6) $raw
$rawT = & $exePath sql --db $appDb --json --limit 50 --query "SELECT coalesce(r.external_target,'') FROM refs r JOIN files f ON f.id = r.file_id WHERE r.kind = 'call' AND r.receiver_text = 'B' AND r.name_text = 'Go'" | Out-String
$extT = [string](@(($rawT | ConvertFrom-Json).rows) | Select-Object -First 1 | ForEach-Object { $_[0] })
function Site($file,$name){ @($rows | Where-Object { $_.File -eq $file -and $_.Name -eq $name }) | Select-Object -First 1 }

foreach ($n in 'IntToStr','UpperCase','FreeAndNil') {
  $s = Site 'uOwn' $n
  Check "A1 uOwn $n -> System.SysUtils.$n although the .dpr uses ELeaks (got '$($s.Ext)')" ($null -ne $s -and $s.Ext -ceq "System.SysUtils.$n")
}
$s = Site 'uBoth' 'IntToStr'
Check "A2 CONTROL uBoth IntToStr stays unbound: System.SysUtils and ELeaks are both in ITS uses (got '$($s.Ext)')" ($null -ne $s -and $s.Ext -eq '')
$s = Site 'uFall' 'LeakOnly'
Check "A3 CONTROL uFall LeakOnly still binds ELeaks.LeakOnly through the program-wide fallback (got '$($s.Ext)')" ($null -ne $s -and $s.Ext -ceq 'ELeaks.LeakOnly')
$s = Site 'uOwn' 'Format'
Check "A4 CONTROL uOwn Format -> System.SysUtils.Format (got '$($s.Ext)')" ($null -ne $s -and $s.Ext -ceq 'System.SysUtils.Format')

Check "A5 uTyped B.Go (B: TBox; uses Lib.Box, the .dpr uses ELeaks which also declares TBox) -> Lib.Box.TBox.Go (got '$extT')" ($extT -ceq 'Lib.Box.TBox.Go')

Write-Host ''
if ($script:fail) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'PASS' -ForegroundColor Green; exit 0
} finally {
  if (Test-Path -LiteralPath $WorkDir) { [IO.Directory]::Delete($WorkDir, $true) }
}
