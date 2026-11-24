<#
  run_v154_FPBATCH2.ps1 -- v154 lane FPBATCH2: eight ORM3 false-positive classes (INBOX-orm3-server-153 batch 2).

  Each class: a fixture in the ORM3 shape that must stay QUIET, and a true-positive control in the same file
  that must still FIRE. A fixture line ending in `// TP` must carry a finding of the rule, every other line must
  carry none (exact set equality), so a rule switched off cannot pass and a rule left unchanged cannot pass.

    1 sql-injection-concat          digits-only splice (F:= IntToStr(Id); ... + F)  | parameter / compound / direct splice fire
    2 dataset-open-without-close    FDest.Active:= True on a class that is no TDataSet | TFDQuery-typed field fires
    3 read-never-assigned           global + field written only in a SIBLING project   | never written anywhere fires
    4 used-before-assignment        array filled in `for .. to High(x)`               | no store / store outside a loop fires
    6 duplicate-global-decl         message must not say "identical" when the signature names other declarations

  Class 8 (try-except-swallowed credits a field/global receiving E.Message) was BACKED OUT: it reversed owner ruling R22 (1.20.6);
  the patch is kept in C:\TEMP\claude\lanes\v154\FPBATCH2\class8.patch for the owner.
  Class 4 covers the ARRAY part only (a dynamic array is never reported at all, so a SetLength between loop and read has no control) (case-without-else is UNSURE in the triage and is not touched).
  Usage: pwsh -File tests\autotest\run_v154_FPBATCH2.ps1 [-Exe <engine>] [-Rules <rules dir>]
#>
[CmdletBinding()]
param(
  [string]$Exe     = '',
  [string]$Rules   = '',
  [string]$WorkDir = ''
)
$ErrorActionPreference = 'Stop'
if (-not $Rules)   { $Rules   = (Resolve-Path "$PSScriptRoot\..\..\rules").Path }
if (-not $Exe)     { $Exe     = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe" }
if (-not $WorkDir) { $WorkDir = "$env:TEMP\drag-lint-v154-fpbatch2-$PID" }
$script:Failed = $false
function Check([string]$Name, [bool]$Ok, [string]$Detail = '') {
  $s = if ($Ok) { 'PASS' } else { 'FAIL' }
  Write-Host ("  [{0}] {1} {2}" -f $s, $Name, $(if ($Ok) { '' } else { $Detail })) -ForegroundColor $(if ($Ok) { 'Green' } else { 'Red' })
  if (-not $Ok) { $script:Failed = $true }
}
function Write-Ascii([string]$Path, [string]$Body) {
  [IO.File]::WriteAllText($Path, ($Body -replace "`r?`n", "`r`n"), [Text.Encoding]::ASCII)
}
function Get-Findings($Raw) {
  $txt = ($Raw | ForEach-Object { "$_" }) -join "`n"
  $b = $txt.IndexOf('[')
  if ($b -lt 0) { return ,@() }
  try { return ,@($txt.Substring($b) | ConvertFrom-Json | ForEach-Object { $_ }) } catch { return ,@() }
}
function Run-Lint([string]$File, [string]$Rule, [string[]]$Extra = @()) {
  $raw = & { $ErrorActionPreference = 'Continue'; & $Exe lint $File --json --quiet --rules-dir $Rules --rule $Rule @Extra 2>&1 | ForEach-Object { "$_" } }
  return Get-Findings $raw
}
function Lines-Of($Findings, [string]$Rule) {
  return ((@($Findings | Where-Object { $_.rule -eq $Rule } | ForEach-Object { [int]$_.start_line } | Sort-Object -Unique)) -join ',')
}
function Marker-Lines([string]$File, [string]$Marker) {
  $n = 0; $res = @()
  foreach ($l in [IO.File]::ReadAllLines($File)) { $n++; if ($l -match ('//\s*' + $Marker + '\b')) { $res += $n } }
  return ($res -join ',')
}
function Check-Exact([string]$Title, $Findings, [string]$Rule, [string]$File) {
  $want = Marker-Lines $File 'TP'
  $nx = Marker-Lines $File 'TPNEXT'
  if ($nx) { $want = ((@($nx -split ',' | ForEach-Object { [int]$_ + 1 }) + @($want -split ',' | Where-Object { $_ })) | Sort-Object { [int]$_ }) -join ',' }
  $got  = Lines-Of $Findings $Rule
  Check "$Title (fires exactly on the TP lines)" ($got -eq $want) "want [$want] got [$got]"
}

if (-not (Test-Path $Exe)) { Write-Host "FATAL: engine not found: $Exe" -ForegroundColor Red; exit 2 }
$Exe = (Resolve-Path $Exe).Path
[void][IO.Directory]::CreateDirectory($WorkDir)
try {

# ---------------------------------------------------------------- 1 sql-injection-concat
Write-Host 'class 1: sql-injection-concat' -ForegroundColor Cyan
$f1 = Join-Path $WorkDir 'uSql1.pas'
Write-Ascii $f1 @'
unit uSql1;

interface

implementation

uses System.SysUtils;

procedure FpDigitsOnly(Id: Integer);
var
  F, S: string;
begin
  F:= IntToStr(Id);
  S:= 'DELETE FROM T WHERE ID=' + F;
end;

procedure FpTwoDigitAssignments(Id, Jd: Integer; Flag: Boolean);
var
  F, S: string;
begin
  if Flag then F:= IntToStr(Id) else F:= IntToStr(Jd);
  S:= 'DELETE FROM T WHERE ID=' + F;
end;

procedure TpParameterViaLocal(AParam: string);
var
  F, S: string;
begin
  F:= AParam;
  S:= 'DELETE FROM T WHERE ID=' + F; // TP
end;

procedure TpCompoundAppend(Id: Integer; AParam: string);
var
  F, S: string;
begin
  F:= IntToStr(Id);
  F:= F + AParam;
  S:= 'DELETE FROM T WHERE ID=' + F; // TP
end;

procedure TpDirectParameter(AParam: string);
var
  S: string;
begin
  S:= 'DELETE FROM T WHERE NAME=' + AParam; // TP
end;

procedure TpNeverAssigned;
var
  F, S: string;
begin
  S:= 'DELETE FROM T WHERE ID=' + F; // TP
end;

procedure TpReassignedFromParamInBranch(Id: Integer; Flag: Boolean; AParam: string);
var
  F, S: string;
begin
  F:= IntToStr(Id);
  if Flag then F:= AParam;
  S:= 'DELETE FROM T WHERE ID=' + F; // TP
end;

procedure Mutate(var AText: string);
begin
  AText:= AText + 'x';
end;

procedure TpPassedAsVar(Id: Integer);
var
  F, S: string;
begin
  F:= IntToStr(Id);
  Mutate(F);
  S:= 'DELETE FROM T WHERE ID=' + F; // TP
end;

procedure FpUnrelatedCall(Id: Integer; AText: string);
var
  F, S: string;
begin
  F:= IntToStr(Id);
  Mutate(AText);
  S:= 'DELETE FROM T WHERE ID=' + F;
end;

{ FIXA (v154 review): the report covers the WHOLE + chain, and every way another value reaches F. }
procedure TpChainTail(Id: Integer; AUser: string);
var
  F, S: string;
begin
  F:= IntToStr(Id);
  S:= 'SELECT * FROM T WHERE ID=' + F + ' AND N=''' + AUser; // TP
end;

procedure TpChainTailClosed(Id: Integer; AUser: string);
var
  F, S: string;
begin
  F:= IntToStr(Id);
  S:= 'SELECT * FROM T WHERE ID=' + F + ' AND N=''' + AUser + ''''; // TP
end;

procedure TpChainInParens(Id: Integer; AUser: string);
var
  F, S: string;
begin
  F:= IntToStr(Id);
  S:= AUser + ('SELECT * FROM T WHERE ID=' + F); // TP
end;

procedure TpChainCallTail(Id: Integer; AUser: string);
var
  F, S: string;
begin
  F:= IntToStr(Id);
  S:= 'SELECT * FROM T WHERE ID=' + F + ' AND N=' + Trim(AUser); // TP
end;

procedure FpChainAllSafe(Id, Jd: Integer);
var
  F, S: string;
begin
  F:= IntToStr(Id);
  S:= 'SELECT * FROM T WHERE ID=' + F + ' AND J=' + IntToStr(Jd) + sLineBreak + (' ORDER BY ' + F);
end;

procedure TpForIn(Id: Integer; const AList: TArray<string>);
var
  F, S: string;
begin
  F:= IntToStr(Id);
  for F in AList do
    S:= 'DELETE FROM T WHERE ID=' + F; // TP
end;

procedure TpForVarInShadow(Id: Integer; const AList: TArray<string>);
var
  F, S: string;
begin
  F:= IntToStr(Id);
  for var F in AList do
    S:= 'DELETE FROM T WHERE ID=' + F; // TP
end;

procedure FpForTo(N: Integer);
var
  F, S: string;
  I: Integer;
begin
  for I:= 0 to N do
  begin
    F:= IntToStr(I);
    S:= 'DELETE FROM T WHERE ID=' + F;
  end;
end;

procedure TpInlineShadow(Id: Integer; AUser: string);
var
  F, S: string;
begin
  F:= IntToStr(Id);
  if F <> '' then
  begin
    var F: string:= AUser;
    S:= 'DELETE FROM T WHERE ID=' + F; // TP
  end;
end;

procedure FpInlineVar(Id: Integer);
var
  S: string;
begin
  var F:= IntToStr(Id);
  S:= 'DELETE FROM T WHERE ID=' + F;
end;

procedure TpInlineVarUser(AUser: string);
var
  S: string;
begin
  var F:= AUser;
  S:= 'DELETE FROM T WHERE ID=' + F; // TP
end;

procedure TpInlineVarOutOfScope(Id: Integer);
var
  S: string;
begin
  if Id > 0 then
  begin
    var F:= IntToStr(Id);
  end;
  S:= 'DELETE FROM T WHERE ID=' + F; // TP
end;

procedure TpLambdaParam(Id: Integer);
var
  F, S: string;
  P: TProc<string>;
begin
  F:= IntToStr(Id);
  P:= procedure(F: string)
    begin
      S:= 'DELETE FROM T WHERE ID=' + F; // TP
    end;
end;

procedure TpVarParam(var F: string);
var
  S: string;
begin
  F:= IntToStr(1);
  S:= 'DELETE FROM T WHERE ID=' + F; // TP
end;

procedure TpOutArgOfMethod(Id: Integer; AObj: TFiller);
var
  F, S: string;
begin
  F:= IntToStr(Id);
  AObj.Fill(F);
  S:= 'DELETE FROM T WHERE ID=' + F; // TP
end;

procedure TpElementStore(Id: Integer; AChar: Char);
var
  F, S: string;
begin
  F:= IntToStr(Id);
  F[1]:= AChar;
  S:= 'DELETE FROM T WHERE ID=' + F; // TP
end;

procedure TpAddressTaken(Id: Integer);
var
  F, S: string;
  P: PString;
begin
  F:= IntToStr(Id);
  P:= @F;
  S:= 'DELETE FROM T WHERE ID=' + F; // TP
end;
end.
'@
Check-Exact 'sql-injection-concat' (Run-Lint $f1 'sql-injection-concat') 'sql-injection-concat' $f1

# ---------------------------------------------------------------- 4 used-before-assignment (arrays)
Write-Host 'class 4: used-before-assignment (array filled in a High() loop)' -ForegroundColor Cyan
$f4 = Join-Path $WorkDir 'uUba4.pas'
Write-Ascii $f4 @'
unit uUba4;

interface

implementation

{ INT3: the ORM3 shape fills over ANOTHER array (PlanCols); an empty PlanCols stores nothing, so the read is a true
  positive (the rule cannot see the read loop has the same bound). Only a bound over the read array itself is exempt. }
procedure TpFilledOverOtherHigh(const PlanCols: TArray<Integer>);
var
  Fields: array[0..3] of TObject;
  I, J: Integer;
begin
  for I:= 0 to High(PlanCols) do
    Fields[I]:= TObject(PlanCols[I]);
  for J:= 0 to High(PlanCols) do
    Writeln(Integer(Fields[J])); // TP
end;

procedure FpFilledUpToHighOfItself;
var
  Fields: array[0..3] of TObject;
  I: Integer;
begin
  for I:= 0 to High(Fields) do
    Fields[I]:= nil;
  Writeln(Integer(Fields[0]));
end;

procedure FpFilledUpToLength;
var
  Fields: array[0..3] of TObject;
  I: Integer;
begin
  for I:= 0 to Length(Fields) - 1 do
    Fields[I]:= nil;
  Writeln(Integer(Fields[0]));
end;

procedure TpFilledOverOtherLength(const PlanCols: TArray<Integer>);
var
  Fields: array[0..3] of TObject;
  I: Integer;
begin
  for I:= 0 to Length(PlanCols) - 1 do
    Fields[I]:= TObject(PlanCols[I]);
  Writeln(Integer(Fields[0])); // TP
end;

procedure TpNoStoreAnywhere;
var
  Fields: array[0..3] of TObject;
begin
  Writeln(Integer(Fields[0])); // TP
end;

procedure TpStoreOutsideLoop(Flag: Boolean);
var
  Fields: array[0..3] of TObject;
begin
  if Flag then
    Fields[0]:= nil;
  Writeln(Integer(Fields[1])); // TP
end;

procedure TpStoreIsAfterTheRead(const PlanCols: TArray<Integer>);
var
  Fields: array[0..3] of TObject;
  I: Integer;
begin
  Writeln(Integer(Fields[0])); // TP
  for I:= 0 to High(PlanCols) do
    Fields[I]:= nil;
end;

procedure TpLoopOverOtherArrayStoresThirdArray(const PlanCols: TArray<Integer>);
var
  Fields, Others: array[0..3] of TObject;
  I: Integer;
begin
  for I:= 0 to High(PlanCols) do
    Others[I]:= nil;
  Writeln(Integer(Fields[0])); // TP
end;

procedure TpSkipBeforeStore(const PlanCols: TArray<Integer>);
var
  Fields: array[0..3] of TObject;
  I: Integer;
begin
  for I:= 0 to High(PlanCols) do
  begin
    if PlanCols[I] = 0 then Continue;
    Fields[I]:= nil;
  end;
  Writeln(Integer(Fields[0])); // TP
end;

procedure TpBreakBeforeStore(const PlanCols: TArray<Integer>);
var
  Fields: array[0..3] of TObject;
  I: Integer;
begin
  for I:= 0 to High(PlanCols) do
  begin
    if PlanCols[I] = 0 then Break;
    Fields[I]:= nil;
  end;
  Writeln(Integer(Fields[0])); // TP
end;

procedure TpStoreOnlyInsideIf(const PlanCols: TArray<Integer>);
var
  Fields: array[0..3] of TObject;
  I: Integer;
begin
  for I:= 0 to High(PlanCols) do
    if PlanCols[I] <> 0 then
      Fields[I]:= nil;
  Writeln(Integer(Fields[0])); // TP
end;

procedure TpReadInsideLoopBeforeStore(const PlanCols: TArray<Integer>);
var
  Fields: array[0..3] of TObject;
  I: Integer;
begin
  for I:= 0 to High(PlanCols) do
  begin
    Writeln(Integer(Fields[I])); // TP
    Fields[I]:= nil;
  end;
end;

{ FIXA (v154 review): the filling loop must dominate the read. No fixture for a loop in a nested routine: a local that
  a nested routine captures is never reported, loop or not. }
procedure TpLoopInsideIf(Flag: Boolean; const PlanCols: TArray<Integer>);
var
  Fields: array[0..3] of TObject;
  I: Integer;
begin
  if Flag then
    for I:= 0 to High(PlanCols) do
      Fields[I]:= nil;
  Writeln(Integer(Fields[0])); // TP
end;

procedure TpLoopInsideIfBlock(Flag: Boolean; const PlanCols: TArray<Integer>);
var
  Fields: array[0..3] of TObject;
  I: Integer;
begin
  if Flag then
  begin
    for I:= 0 to High(PlanCols) do
      Fields[I]:= nil;
  end;
  Writeln(Integer(Fields[0])); // TP
end;

procedure TpLoopInTheOtherBranch(Flag: Boolean; const PlanCols: TArray<Integer>);
var
  Fields: array[0..3] of TObject;
  I: Integer;
begin
  if Flag then
  begin
    for I:= 0 to High(PlanCols) do
      Fields[I]:= nil;
  end
  else
    Writeln(Integer(Fields[0])); // TP
end;

procedure TpLoopInCaseBranch(Kind: Integer; const PlanCols: TArray<Integer>);
var
  Fields: array[0..3] of TObject;
  I: Integer;
begin
  case Kind of
    1: for I:= 0 to High(PlanCols) do
         Fields[I]:= nil;
  end;
  Writeln(Integer(Fields[0])); // TP
end;

procedure FpReadInsideLaterIf(Flag: Boolean; const PlanCols: TArray<Integer>);
var
  Fields: array[0..3] of TObject;
  I: Integer;
begin
  for I:= 0 to High(Fields) do
    Fields[I]:= nil;
  if Flag then
  begin
    Writeln(Integer(Fields[0]));
  end;
end;

procedure FpLoopInPlainBlock(const PlanCols: TArray<Integer>);
var
  Fields: array[0..3] of TObject;
  I: Integer;
begin
  begin
    for I:= 0 to High(Fields) do
      Fields[I]:= nil;
  end;
  Writeln(Integer(Fields[0]));
end;

procedure FpBothInOneBranch(Flag: Boolean; const PlanCols: TArray<Integer>);
var
  Fields: array[0..3] of TObject;
  I: Integer;
begin
  if Flag then
  begin
    for I:= 0 to High(Fields) do
      Fields[I]:= nil;
    Writeln(Integer(Fields[0]));
  end;
end;

procedure FpTryBodyThenFinally(const PlanCols: TArray<Integer>);
var
  Fields: array[0..3] of TObject;
  I: Integer;
begin
  try
    for I:= 0 to High(Fields) do
      Fields[I]:= nil;
    Writeln(Integer(Fields[0]));
  finally
    Writeln(0);
  end;
end;

end.
'@
Check-Exact 'used-before-assignment arrays' (Run-Lint $f4 'used-before-assignment') 'used-before-assignment' $f4

# ---------------------------------------------------------------- 2 dataset-open-without-close (needs the ancestry index)
Write-Host 'class 2: dataset-open-without-close (Active arm)' -ForegroundColor Cyan
$d2 = Join-Path $WorkDir 'c2'; [void][IO.Directory]::CreateDirectory($d2)
Write-Ascii (Join-Path $d2 'uDs2.pas') @'
unit uDs2;

interface

uses
  FireDAC.Comp.Client;

type
  /// A log destination with an Active flag, nothing to do with a dataset.
  TFakeDest = class
  public
    Active: Boolean;
  end;

  THolder = class
  private
    FDest: TFakeDest;
    FQry : TFDQuery;
  public
    procedure FpPortActive;
    procedure TpRealQueryActive;
  end;

implementation

procedure THolder.FpPortActive;
begin
  FDest.Active:= True;
end;

procedure THolder.TpRealQueryActive;
begin
  FQry.Active:= True; // TP
end;

end.
'@
$db2 = Join-Path $WorkDir 'c2.sqlite'
& { $ErrorActionPreference = 'Continue'; & $Exe index $d2 --db $db2 --quiet 2>&1 | ForEach-Object { "$_" } } | Out-Null
Check 'class 2 scratch index built' (Test-Path $db2)
$cfgEmpty = Join-Path $WorkDir 'empty.json'
[IO.File]::WriteAllText($cfgEmpty, '{}')
$u2 = Join-Path $d2 'uDs2.pas'
Check-Exact 'dataset-open-without-close (lint <file> with the index)' (Run-Lint $u2 'dataset-open-without-close' @('--db', $db2, '--config', $cfgEmpty, '--library-db', 'none')) 'dataset-open-without-close' $u2

# ---------------------------------------------------------------- 6 duplicate-global-decl message
Write-Host 'class 6: duplicate-global-decl wording' -ForegroundColor Cyan
$d6 = Join-Path $WorkDir 'c6'; [void][IO.Directory]::CreateDirectory($d6)
Write-Ascii (Join-Path $d6 'uDupA.pas') @'
unit uDupA;

interface

const
  Z14_MAX = 4;

type
  TRecDiff = record
    Letter: string;
  end;
  TTableDiff = array [1..Z14_MAX] of TRecDiff;
  TPlainArr = array [1..3] of Integer;
  TSizeArr = array [1..10] of Integer;

implementation

end.
'@
Write-Ascii (Join-Path $d6 'uDupB.pas') @'
unit uDupB;

interface

const
  Z14_MAX = 4;

type
  TRecDiff = record
    Letter: Integer;
  end;
  TTableDiff = array [1..Z14_MAX] of TRecDiff;
  TPlainArr = array [1..3] of Integer;
  TSizeArr = array [1..20] of Integer;

implementation

end.
'@
$db6 = Join-Path $WorkDir 'c6.sqlite'
& { $ErrorActionPreference = 'Continue'; & $Exe index $d6 --db $db6 --quiet 2>&1 | ForEach-Object { "$_" } } | Out-Null
Check 'class 6 scratch index built' (Test-Path $db6)
$all6 = Get-Findings (& { $ErrorActionPreference = 'Continue'; & $Exe lint-all --db $db6 --config $cfgEmpty --json --quiet --rules-dir $Rules --library-db none 2>&1 | ForEach-Object { "$_" } })
function Dup-For([string]$Name) { return @($all6 | Where-Object { $_.rule -eq 'duplicate-global-decl' -and $_.message -match ('^' + [regex]::Escape($Name) + '\b') }) }
$tbl = Dup-For 'TTableDiff'; $rec = Dup-For 'TRecDiff'; $pl = Dup-For 'TPlainArr'
Check 'TTableDiff is still reported' ($tbl.Count -ge 1) "got $($tbl.Count)"
Check 'TTableDiff (names TRecDiff, Z14_MAX) does NOT claim the declarations are identical' `
  (($tbl.Count -ge 1) -and (-not (($tbl | ForEach-Object { $_.message }) -join ' ' -match 'identical,')) -and ((($tbl | ForEach-Object { $_.message }) -join ' ') -match 'NOT compared')) (($tbl | ForEach-Object { $_.message }) -join ' | ')
$recMsg = ($rec | ForEach-Object { $_.message }) -join ' | '
Check 'TRecDiff (record body is not compared at all) does NOT claim the declarations are identical' ((@($rec).Count -ge 1) -and ($recMsg -notmatch 'identical,') -and ($recMsg -match 'NOT compared')) $recMsg
$sz = Dup-For 'TSizeArr'
$szMsg = ($sz | ForEach-Object { $_.message }) -join ' | '
Check 'CONTROL: TSizeArr (1..10 against 1..20) still says DECLARATIONS DIFFER' ((@($sz).Count -ge 1) -and ($szMsg -match 'DECLARATIONS DIFFER')) $szMsg
Check 'CONTROL: TPlainArr (builtin element type, same text) still says identical' `
  (($pl.Count -ge 1) -and ((($pl | ForEach-Object { $_.message }) -join ' ') -match 'identical,') -and (-not (($pl | ForEach-Object { $_.message }) -join ' ' -match 'NOT compared'))) (($pl | ForEach-Object { $_.message }) -join ' | ')

# ---------------------------------------------------------------- 3 read-never-assigned (sibling stores)
Write-Host 'class 3: read-never-assigned (shared unit, sibling project writes)' -ForegroundColor Cyan
$sh = Join-Path $WorkDir 'shared'; $p1 = Join-Path $WorkDir 'P1'; $p2 = Join-Path $WorkDir 'P2'
foreach ($d in $sh, $p1, $p2) { [void][IO.Directory]::CreateDirectory($d) }
Write-Ascii (Join-Path $sh 'Shared.Cfg.pas') @'
unit Shared.Cfg;

interface

type
  TSettings = class
  public
    FWrittenInP2: Integer;
    FNeverWritten: Integer;
  end;

var
  GWrittenInP2: Integer;
  GNeverWritten: Integer;

procedure ShowAll(pS: TSettings);

implementation

procedure ShowAll(pS: TSettings);
var
  X: Integer;
begin
  { an assignment, not Writeln: with no platform library an unknown callee counts as a possible write }
  X:= GWrittenInP2 + GNeverWritten + pS.FWrittenInP2 + pS.FNeverWritten;
end;

end.
'@
Write-Ascii (Join-Path $p1 'P1Main.pas') @'
unit P1Main;

interface

procedure RunOne;

implementation

uses Shared.Cfg;

procedure RunOne;
begin
end;

end.
'@
Write-Ascii (Join-Path $p2 'P2Main.pas') @'
unit P2Main;

interface

procedure RunTwo;

implementation

uses Shared.Cfg;

procedure RunTwo;
var
  S: TSettings;
begin
  S:= TSettings.Create;
  GWrittenInP2:= 1;
  S.FWrittenInP2:= 2;
end;

end.
'@
foreach ($pj in @(@('P1', $p1, 'P1Main'), @('P2', $p2, 'P2Main'))) {
  $n = $pj[0]; $dir = $pj[1]; $mu = $pj[2]
  Write-Ascii (Join-Path $dir "$n.dpr") "program $n;`nuses`n  Shared.Cfg in '..\shared\Shared.Cfg.pas',`n  $mu in '$mu.pas';`nbegin`nend.`n"
  Write-Ascii (Join-Path $dir "$n.dproj") @"
<Project xmlns="http://schemas.microsoft.com/developer/msbuild/2003">
  <PropertyGroup><MainSource>$n.dpr</MainSource></PropertyGroup>
  <ItemGroup>
    <DelphiCompile Include="$n.dpr"><MainSource>MainSource</MainSource></DelphiCompile>
    <DCCReference Include="..\shared\Shared.Cfg.pas"/>
    <DCCReference Include="$mu.pas"/>
  </ItemGroup>
</Project>
"@
}
$dbP1 = Join-Path $WorkDir 'P1.sqlite'; $dbP2 = Join-Path $WorkDir 'P2.sqlite'
$manifest = Join-Path $WorkDir 'drag-lint.json'
Write-Ascii $manifest (@'
{
  "settings": { "defaultPlatform": "Win64" },
  "indexes": {
    "outDir": "OUTDIR",
    "sections": [
      { "name": "P1", "include": ["ONEDIR"] },
      { "name": "P2", "include": ["TWODIR"] }
    ]
  }
}
'@ -replace 'OUTDIR', ($WorkDir -replace '\\', '\\') -replace 'ONEDIR', ($p1 -replace '\\', '\\') -replace 'TWODIR', ($p2 -replace '\\', '\\'))
& { $ErrorActionPreference = 'Continue'; & $Exe index --project "$p1\P1.dproj" --db $dbP1 --quiet 2>&1 | ForEach-Object { "$_" } } | Out-Null
Check 'index P1' ($LASTEXITCODE -eq 0) "exit=$LASTEXITCODE"
& { $ErrorActionPreference = 'Continue'; & $Exe index --project "$p2\P2.dproj" --db $dbP2 --quiet 2>&1 | ForEach-Object { "$_" } } | Out-Null
Check 'index P2' ($LASTEXITCODE -eq 0) "exit=$LASTEXITCODE"
$out3 = Join-Path $WorkDir 'lintall3.txt'
$o3 = (& { $ErrorActionPreference = 'Continue'; & $Exe lint-all --output $out3 --db $dbP1 --config $manifest --rules-dir $Rules --enable read-never-assigned --quiet 2>&1 | ForEach-Object { "$_" } }) -join "`n"
if (Test-Path $out3) { $o3 += "`n" + [IO.File]::ReadAllText($out3) }
$rna = @($o3 -split "`r?`n" | Where-Object { $_ -match 'read-never-assigned' })
Check 'POSITIVE CONTROL: GNeverWritten (written in no project) IS reported' (@($rna | Where-Object { $_ -match 'GNeverWritten' }).Count -ge 1) ($rna -join ' | ')
Check 'POSITIVE CONTROL: field FNeverWritten IS reported' (@($rna | Where-Object { $_ -match 'FNeverWritten' }).Count -ge 1) ($rna -join ' | ')
Check 'GWrittenInP2 (written only in sibling P2) is NOT reported' (@($rna | Where-Object { $_ -match 'GWrittenInP2' }).Count -eq 0) ($rna -join ' | ')
Check 'FWrittenInP2 (written only in sibling P2) is NOT reported' (@($rna | Where-Object { $_ -match 'FWrittenInP2' }).Count -eq 0) ($rna -join ' | ')

Write-Host ''
if ($script:Failed) { Write-Host 'v154 FPBATCH2: FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'v154 FPBATCH2: PASS' -ForegroundColor Green
exit 0
} finally {
  if (($WorkDir -like "$env:TEMP\drag-lint-v154-fpbatch2-*") -and (Test-Path -LiteralPath $WorkDir)) { [IO.Directory]::Delete($WorkDir, $true) }
}
