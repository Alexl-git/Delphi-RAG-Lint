<#
  run_recv_helper_receivers.ps1 -- spec 2026-11-06-recv-undecidable, classes D01 and D05:
  dotted calls on a LIBRARY or BUILT-IN type that only a HELPER answers.

    D01 a PROJECT helper written for a library type: `TMemIniFileHelper = class helper for
        TMemINIFile` (note the case) makes `LIni.ReadBoolean` a call of the helper's method.
        The answer is a LOCAL edge (the helper is the project's), never an external name.
    D05 a LIBRARY helper of a built-in type: `S.Split` on a string is TStringHelper.Split,
        `B.ToString` on a Boolean TBooleanHelper.ToString, and a chain steps through a
        helper function's result (`S.Trim.LastIndexOf`).

  Delphi's rules the controls pin: a helper is in scope only where its unit is used (or in
  its own unit); only ONE helper per type is active, so two visible helpers decline; a helper
  in an implementation section is invisible elsewhere; a member the helper lacks is still the
  type's own (`LIni.ReadInteger` stays the library's); a name nobody declares stays unbound.
  Reads refs.external_target and call_edges from a fixture DB. Run from any CWD, pwsh 7.
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe",
  [string]$WorkDir = "C:\TEMP\draglint_recv_helper_$PID"
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
type
  TStringHelper = record helper for string
  public
    function Split(const C: Char): Integer;
    function Trim: string;
    function LastIndexOf(const S: string): Integer;
  end;
  TBooleanHelper = record helper for Boolean
  public
    function ToString: string;
  end;
implementation
function TStringHelper.Split(const C: Char): Integer; begin Result := 0; end;
function TStringHelper.Trim: string; begin Result := ''; end;
function TStringHelper.LastIndexOf(const S: string): Integer; begin Result := 0; end;
function TBooleanHelper.ToString: string; begin Result := ''; end;
end.
'@
W $lib 'Other.Helpers.pas' @'
unit Other.Helpers;
interface
type
  TOtherStringHelper = record helper for string
  public
    function Split(const C: Char): Integer;
  end;
implementation
function TOtherStringHelper.Split(const C: Char): Integer; begin Result := 0; end;
end.
'@
W $lib 'System.IniFiles.pas' @'
unit System.IniFiles;
interface
type
  TCustomIniFile = class
  public
    function ReadInteger(const S, I: string; D: Integer): Integer;
  end;
  TMemIniFile = class(TCustomIniFile)
  public
    function ReadString(const S, I, D: string): string;
  end;
implementation
function TCustomIniFile.ReadInteger(const S, I: string; D: Integer): Integer; begin Result := D; end;
function TMemIniFile.ReadString(const S, I, D: string): string; begin Result := D; end;
end.
'@

W $app 'uIniHelp.pas' @'
unit uIniHelp;
interface
uses System.IniFiles;
type
  TMemIniFileHelper = class helper for TMemINIFile
  public
    function ReadBoolean(const S, I: string; D: Boolean): Boolean;
  end;
procedure UseOwn;
implementation
function TMemIniFileHelper.ReadBoolean(const S, I: string; D: Boolean): Boolean; begin Result := D; end;
procedure UseOwn;
var
  LIni: TMemIniFile;
begin
  LIni.ReadBoolean('a', 'b', False);
end;
end.
'@
W $app 'uIniHelp2.pas' @'
unit uIniHelp2;
interface
uses System.IniFiles;
type
  TMemIniFileHelper2 = class helper for TMemIniFile
  public
    function ReadBoolean(const S, I: string; D: Boolean): Boolean;
  end;
implementation
function TMemIniFileHelper2.ReadBoolean(const S, I: string; D: Boolean): Boolean; begin Result := D; end;
end.
'@
W $app 'uIniHidden.pas' @'
unit uIniHidden;
interface
uses System.IniFiles;
procedure Nothing;
implementation
type
  TMemIniFileHelperImpl = class helper for TMemIniFile
  public
    function ReadHidden: Boolean;
  end;
function TMemIniFileHelperImpl.ReadHidden: Boolean; begin Result := False; end;
procedure Nothing; begin end;
end.
'@
W $app 'uD01.pas' @'
unit uD01;
interface
uses System.IniFiles, uIniHelp, uIniHidden;
procedure GoIni;
implementation
procedure GoIni;
var
  LIni: TMemIniFile;
begin
  LIni.ReadBoolean('a', 'b', False);
  LIni.ReadInteger('a', 'b', 0);
  LIni.ReadString('a', 'b', '');
  LIni.ReadHidden;
  LIni.NoSuchIni;
end;
end.
'@
W $app 'uD01No.pas' @'
unit uD01No;
interface
uses System.IniFiles;
procedure GoIniNo;
implementation
procedure GoIniNo;
var
  LIni: TMemIniFile;
begin
  LIni.ReadBoolean('a', 'b', False);
end;
end.
'@
W $app 'uD01Two.pas' @'
unit uD01Two;
interface
uses System.IniFiles, uIniHelp, uIniHelp2;
procedure GoIniTwo;
implementation
procedure GoIniTwo;
var
  LIni: TMemIniFile;
begin
  LIni.ReadBoolean('a', 'b', False);
end;
end.
'@
W $app 'uD05.pas' @'
unit uD05;
interface
uses System.SysUtils;
procedure GoStr;
implementation
procedure GoStr;
var
  S: string;
  B: Boolean;
begin
  S.Split(',');
  S.Trim.LastIndexOf('x');
  B.ToString;
  S.NoSuchStr;
end;
end.
'@
W $app 'uD05No.pas' @'
unit uD05No;
interface
procedure GoStrNo;
implementation
procedure GoStrNo;
var
  S: string;
begin
  S.Split(',');
end;
end.
'@
W $app 'uD05Two.pas' @'
unit uD05Two;
interface
uses System.SysUtils, Other.Helpers;
procedure GoStrTwo;
implementation
procedure GoStrTwo;
var
  S: string;
begin
  S.Split(',');
end;
end.
'@
W $app 'App.dpr' @'
program App;
uses
  uIniHelp in 'uIniHelp.pas',
  uIniHelp2 in 'uIniHelp2.pas',
  uIniHidden in 'uIniHidden.pas',
  uD01 in 'uD01.pas',
  uD01No in 'uD01No.pas',
  uD01Two in 'uD01Two.pas',
  uD05 in 'uD05.pas',
  uD05No in 'uD05No.pas',
  uD05Two in 'uD05Two.pas';
begin
end.
'@

$libDb = Join-Path $WorkDir 'lib.sqlite'; $appDb = Join-Path $WorkDir 'app.sqlite'
Push-Location C:\TEMP
& $exePath index $lib --db $libDb 2>&1 | Out-Null
Check 'V library index built' (Test-Path $libDb) $libDb
& $exePath index --project (Join-Path $app 'App.dpr') --db $appDb --library-db $libDb 2>&1 | Out-Null
Check 'V app index built' (Test-Path $appDb) $appDb
$j = & $exePath sql --db $appDb --json --limit 2000 --query "SELECT '' p, r.start_line, r.receiver_text, r.name_text, coalesce(r.external_target,''), coalesce(t.qualified_name,''), f.path FROM refs r JOIN files f ON f.id = r.file_id LEFT JOIN call_edges c ON c.ref_id = r.id LEFT JOIN symbols t ON t.id = c.target_symbol_id WHERE r.kind = 'call' AND r.receiver_text <> ''" | Out-String | ConvertFrom-Json
Pop-Location

$rows = foreach ($r in $j.rows) { [pscustomobject]@{ File=[IO.Path]::GetFileNameWithoutExtension([string]$r[6]); Rcv=[string]$r[2]; Name=[string]$r[3]; Ext=[string]$r[4]; Edge=[string]$r[5] } }
Check "V the sites were read ($(@($rows).Count))" (@($rows).Count -ge 14)
function Site($file,$rcv,$name){ @($rows | Where-Object { $_.File -eq $file -and $_.Rcv -eq $rcv -and $_.Name -eq $name }) | Select-Object -First 1 }
function Ext($id,$file,$rcv,$name,$want){
  $s = Site $file $rcv $name
  Check "$id $file $rcv.$name -> external $want (got ext='$($s.Ext)' edge='$($s.Edge)')" ($null -ne $s -and $s.Ext -ceq $want -and $s.Edge -eq '')
}
function Edge($id,$file,$rcv,$name,$want){
  $s = Site $file $rcv $name
  Check "$id $file $rcv.$name -> local edge $want (got ext='$($s.Ext)' edge='$($s.Edge)')" ($null -ne $s -and $s.Edge -ceq $want -and $s.Ext -eq '')
}
function None($id,$file,$rcv,$name){
  $s = Site $file $rcv $name
  Check "$id CONTROL $file $rcv.$name stays unbound (got ext='$($s.Ext)' edge='$($s.Edge)')" ($null -ne $s -and $s.Ext -eq '' -and $s.Edge -eq '')
}

# ---- D01: a project helper on a library type ----
Edge 'D01a' 'uD01'      'LIni' 'ReadBoolean' 'uIniHelp.TMemIniFileHelper.ReadBoolean'
Edge 'D01b' 'uIniHelp'  'LIni' 'ReadBoolean' 'uIniHelp.TMemIniFileHelper.ReadBoolean'
Ext  'D01c' 'uD01'      'LIni' 'ReadInteger' 'System.IniFiles.TCustomIniFile.ReadInteger'
Ext  'D01d' 'uD01'      'LIni' 'ReadString'  'System.IniFiles.TMemIniFile.ReadString'
None 'D01e' 'uD01'      'LIni' 'ReadHidden'
None 'D01f' 'uD01'      'LIni' 'NoSuchIni'
None 'D01g' 'uD01No'    'LIni' 'ReadBoolean'
None 'D01h' 'uD01Two'   'LIni' 'ReadBoolean'

# ---- D05: a library helper on a built-in type ----
Ext  'D05a' 'uD05'    'S'      'Split'       'System.SysUtils.TStringHelper.Split'
Ext  'D05b' 'uD05'    'S.Trim' 'LastIndexOf' 'System.SysUtils.TStringHelper.LastIndexOf'
Ext  'D05c' 'uD05'    'B'      'ToString'    'System.SysUtils.TBooleanHelper.ToString'
None 'D05d' 'uD05'    'S'      'NoSuchStr'
None 'D05e' 'uD05No'  'S'      'Split'
None 'D05f' 'uD05Two' 'S'      'Split'

Write-Host ''
if ($script:fail) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'PASS' -ForegroundColor Green; exit 0
} finally {
  if (Test-Path -LiteralPath "C:\TEMP\draglint_recv_helper_$PID") { [IO.Directory]::Delete("C:\TEMP\draglint_recv_helper_$PID", $true) }
}
