<#
  run_convert_apply_semantics_controls.ps1 -- the controls behind the 1.26.1
  convert-apply semantics fixes (run_convert_apply_semantics.ps1 holds the
  defect fixtures themselves).

  F4 a converted ParamData LOADS into the REAL FireDAC classes
     (lib\FireDacLoad.ps1): Params.Count and each Name / DataType / ParamType /
     Value after TReader.ReadRootComponent; positive control: a malformed item
     member fails that load.
  F1 rule scope, the controls:
     (a) a #mapping #apply'd inside a block takes effect in that block only;
     (b) a FILE-SCOPE rule (before the first #convert) applies in every block;
     (c)+(d) on the .pas side a file-scope #link -- one with NO preceding
         #convert, the case NamesForLink reads as block 0 -- rewrites every
         converted instance's sites, one edit each.
  F6 a VISUAL component whose Left/Top are PUBLISHED: with #link Left/Top they
     appear exactly once; without, the DesignInfo fallback does NOT carry them
     (the rules decide, and they are reported unlinked). A non-visual
     component's Left/Top are still carried.
  F2 the target's chain spans THREE units (LibS -> LibM -> LibT) and the
     redeclared default still wins, and so it does through a GENERIC ancestor
     (TGenBase<Integer>, G1).

  Every written .pas compiles with dcc64; every written .dfm goes through
  DfmLoadCheck.
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
  [string]$WorkDir = "C:\TEMP\draglint_convert_apply_semantics_controls_$PID",
  [switch]$Keep
)
try {
$ErrorActionPreference = 'Continue'
$script:Failed = $false
function Check($n, $ok, $d = '') {
  $s = if ($ok) { 'PASS' } else { 'FAIL' }
  $c = if ($ok) { 'Green' } else { 'Red' }
  Write-Host ("  [{0}] {1}" -f $s, $n) -ForegroundColor $c
  if (-not $ok) { if ($d) { Write-Host "      $d" -ForegroundColor DarkGray }; $script:Failed = $true }
}
. (Join-Path $PSScriptRoot 'lib\DfmLoadCheck.ps1')
. (Join-Path $PSScriptRoot 'lib\FireDacLoad.ps1')

if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
$Exe = (Resolve-Path $Exe).Path
if (Test-Path $WorkDir) { Remove-Item -Recurse -Force $WorkDir }
New-Item -ItemType Directory $WorkDir | Out-Null

function Write-Ascii([string]$Path, [string]$Body) {
  $norm = $Body -replace "`r`n", "`n" -replace "`n", "`r`n"
  [System.IO.File]::WriteAllText($Path, $norm, [System.Text.Encoding]::ASCII)
}
function P([string]$n) { return (Join-Path $WorkDir $n) }
function BlockOf([string]$Text, [string]$Name) {
  $m = [regex]::Match($Text, "(?ms)^  object $Name\b.*?^  end\r?$")
  if ($m.Success) { return $m.Value } else { return '' }
}

# ---- fixture: classes ---------------------------------------------------------
Write-Ascii (P 'LibS.pas') @'
unit LibS;

interface

uses
  System.Classes;

type
  TGenKind = (gkNone, gkAuto, gkMan);

  TSrcDb = class(TComponent)
  private
    FMode: TGenKind;
    FHint: string;
  published
    property Mode: TGenKind read FMode write FMode default gkNone;
    property Hint: string read FHint write FHint;
  end;

  TSrcTbl = class(TComponent)
  private
    FMode: TGenKind;
    FHint: string;
  published
    property Mode: TGenKind read FMode write FMode default gkNone;
    property Hint: string read FHint write FHint;
  end;

  TSrcLbl = class(TComponent)
  private
    FLeft   : Integer;
    FTop    : Integer;
    FCaption: string;
  published
    property Left: Integer read FLeft write FLeft;
    property Top: Integer read FTop write FTop;
    property Caption: string read FCaption write FCaption;
  end;

  TSrcLblN = class(TSrcLbl)
  end;

  TBaseFld = class(TComponent)
  private
    FGen: TGenKind;
  published
    property Gen: TGenKind read FGen write FGen default gkNone;
  end;

  TSrcAuto = class(TBaseFld)
  end;

  TGenBase<T> = class(TComponent)
  private
    FGen: TGenKind;
  published
    property Gen: TGenKind read FGen write FGen default gkNone;
  end;

  TSrcG = class(TGenBase<Integer>)
  end;

implementation

end.
'@
Write-Ascii (P 'LibM.pas') @'
unit LibM;

interface

uses
  System.Classes, LibS;

type
  TMidFld = class(TBaseFld)
  end;

implementation

end.
'@
Write-Ascii (P 'LibT.pas') @'
unit LibT;

interface

uses
  System.Classes, LibS, LibM;

type
  TDstConn = class(TComponent)
  private
    FKind  : TGenKind;
    FRemark: string;
  published
    property Kind: TGenKind read FKind write FKind default gkNone;
    property Remark: string read FRemark write FRemark;
  end;

  TDstTbl = class(TComponent)
  private
    FKind  : TGenKind;
    FRemark: string;
  published
    property Kind: TGenKind read FKind write FKind default gkNone;
    property Remark: string read FRemark write FRemark;
  end;

  TDstLbl = class(TComponent)
  private
    FLeft   : Integer;
    FTop    : Integer;
    FCaption: string;
  published
    property Left: Integer read FLeft write FLeft;
    property Top: Integer read FTop write FTop;
    property Caption: string read FCaption write FCaption;
  end;

  TDstAuto2 = class(TMidFld)
  published
    property Gen default gkAuto;
  end;

  TDstG = class(TGenBase<Integer>)
  published
    property Gen default gkAuto;
  end;

implementation

end.
'@

Write-Ascii (P 'ScopeDM.pas') @'
unit ScopeDM;

interface

uses
  System.Classes, LibS;

type
  TScopeDM = class(TDataModule)
    db: TSrcDb;
    tbl: TSrcTbl;
    lbl: TSrcLbl;
    lbn: TSrcLblN;
    fa: TSrcAuto;
    fg: TSrcG;
  public
    procedure Touch;
  end;

implementation

{$R *.dfm}

procedure TScopeDM.Touch;
begin
  db.Hint := 'x';
  tbl.Hint := 'y';
end;

end.
'@
Write-Ascii (P 'ScopeDM.dfm') @'
object ScopeDM: TScopeDM
  object db: TSrcDb
    Mode = gkAuto
    Hint = 'dh'
    Left = 10
    Top = 20
  end
  object tbl: TSrcTbl
    Mode = gkAuto
    Hint = 'th'
  end
  object lbl: TSrcLbl
    Left = 5
    Top = 6
    Caption = 'a'
  end
  object lbn: TSrcLblN
    Left = 7
    Top = 8
    Caption = 'b'
  end
  object fa: TSrcAuto
  end
  object fg: TSrcG
  end
end
'@

# The FIRST line is file scope: no #convert precedes it.
Write-Ascii (P 'scope.rules') @'
#link Remark <- Hint

#convert LibS.TSrcDb -> LibT.TDstConn, LibT
#mapping M from LibS.TGenKind to LibT.TDstConn
#mapping M #when Mode = gkAuto -> Kind = gkMan
#mapping M #else -> Kind = gkNone
#apply M

#convert LibS.TSrcTbl -> LibT.TDstTbl, LibT
#ignore Mode

#convert LibS.TSrcLbl -> LibT.TDstLbl, LibT
#link Left <- Left
#link Top <- Top
#link Caption <- Caption

#convert LibS.TSrcLblN -> LibT.TDstLbl, LibT
#link Caption <- Caption

#convert LibS.TSrcAuto -> LibT.TDstAuto2, LibT
#link Gen <- Gen

#convert LibS.TSrcG -> LibT.TDstG, LibT
#link Gen <- Gen
'@

# ---- fixture: a TQuery with three parameters -> TFDQuery ------------------------
# Stand-in declarations with the REAL member names and types (the index is the
# fixture folder); the load below uses the real FireDAC classes.
Write-Ascii (P 'BdeStub.pas') @'
unit BdeStub;

interface

uses
  System.Classes, Data.DB;

type
  TQParam = class(TCollectionItem)
  private
    FName     : string;
    FDataType : TFieldType;
    FParamType: TParamType;
    FValue    : Variant;
  published
    property DataType: TFieldType read FDataType write FDataType default ftUnknown;
    property Name: string read FName write FName;
    property ParamType: TParamType read FParamType write FParamType default ptUnknown;
    property Value: Variant read FValue write FValue;
  end;

  TQParams = class(TCollection)
  private
    function GetItem(Index: Integer): TQParam;
  public
    property Items[Index: Integer]: TQParam read GetItem; default;
  end;

  TQuery = class(TComponent)
  private
    FParams: TQParams;
  published
    property Params: TQParams read FParams write FParams stored False;
  end;

implementation

function TQParams.GetItem(Index: Integer): TQParam;
begin
  Result := TQParam(inherited GetItem(Index));
end;

end.
'@
Write-Ascii (P 'FdStub.pas') @'
unit FdStub;

interface

uses
  System.Classes, Data.DB;

type
  TFDParam = class(TCollectionItem)
  private
    FName     : string;
    FDataType : TFieldType;
    FParamType: TParamType;
    FValue    : Variant;
    FSize     : Integer;
  published
    property Name: string read FName write FName;
    property DataType: TFieldType read FDataType write FDataType default ftUnknown;
    property ParamType: TParamType read FParamType write FParamType default ptUnknown;
    property Size: Integer read FSize write FSize default 0;
    property Value: Variant read FValue write FValue;
  end;

  TFDParams = class(TCollection)
  private
    function GetItem(Index: Integer): TFDParam;
  public
    property Items[Index: Integer]: TFDParam read GetItem; default;
  end;

  TFDQuery = class(TComponent)
  private
    FParams: TFDParams;
  published
    property Params: TFDParams read FParams write FParams stored False;
  end;

implementation

function TFDParams.GetItem(Index: Integer): TFDParam;
begin
  Result := TFDParam(inherited GetItem(Index));
end;

end.
'@
Write-Ascii (P 'ParDM.pas') @'
unit ParDM;

interface

uses
  System.Classes, BdeStub;

type
  TParDM = class(TDataModule)
    qry: TQuery;
  end;

implementation

{$R *.dfm}

end.
'@
Write-Ascii (P 'ParDM.dfm') @'
object ParDM: TParDM
  object qry: TQuery
    ParamData = <
      item
        DataType = ftString
        Name = 'CODE'
        ParamType = ptInput
        Value = 'ab'
      end
      item
        DataType = ftInteger
        Name = 'ID'
        ParamType = ptInput
        Value = 7
      end
      item
        DataType = ftFloat
        Name = 'RATE'
        ParamType = ptInputOutput
      end>
  end
end
'@
Write-Ascii (P 'par.rules') @'
#convert BdeStub.TQuery -> FdStub.TFDQuery, FdStub
#link Params.Items.Name <- Params.Items.Name
#link Params.Items.DataType <- Params.Items.DataType
#link Params.Items.ParamType <- Params.Items.ParamType
#link Params.Items.Value <- Params.Items.Value
'@

$db = P 'fx.sqlite'
$idx = & $Exe index $WorkDir --db $db 2>&1
Check 'V the fixture index was built' (($LASTEXITCODE -eq 0) -and (Test-Path $db)) "exit=$LASTEXITCODE; $($idx -join ' | ')"
Check 'V the load checker is available (lib\DfmLoadCheck.ps1)' (Test-DfmLoadsChecker)
Check 'V the FireDAC loader is available (lib\FireDacLoad.ps1)' (Test-FireDacLoader)

# ---- F4: the real FireDAC load --------------------------------------------------
$r = (& $Exe convert-apply --unit (P 'ParDM.pas') --rules (P 'par.rules') --db $db --apply --no-backup 2>&1) -join "`n"
Check 'F4-0 --apply exits 0' ($LASTEXITCODE -eq 0) $r
$fd = Invoke-FireDacLoad @((P 'ParDM.dfm'))
Check 'F4-1 the converted ParDM.dfm loads into real FireDAC classes with no reader error' `
  ((@($fd | Where-Object { $_ -match '^FAIL ' }).Count -eq 0) -and (@($fd | Where-Object { $_ -match '^DONE ParDM\.dfm errors=0' }).Count -eq 1)) ($fd -join ' | ')
Check 'F4-2 TFDQuery qry has Params.Count = 3' (@($fd | Where-Object { $_ -eq 'PARAMS ParDM.dfm qry 3' }).Count -eq 1) ($fd -join ' | ')
Check 'F4-3 param 0: CODE ftString ptInput ab' (@($fd | Where-Object { $_ -eq 'PARAM ParDM.dfm qry 0 Name=CODE DataType=ftString ParamType=ptInput Value=ab' }).Count -eq 1) ($fd -join ' | ')
Check 'F4-4 param 1: ID ftInteger ptInput 7' (@($fd | Where-Object { $_ -eq 'PARAM ParDM.dfm qry 1 Name=ID DataType=ftInteger ParamType=ptInput Value=7' }).Count -eq 1) ($fd -join ' | ')
Check 'F4-5 param 2: RATE ftFloat ptInputOutput, no value' (@($fd | Where-Object { $_ -eq 'PARAM ParDM.dfm qry 2 Name=RATE DataType=ftFloat ParamType=ptInputOutput Value=' }).Count -eq 1) ($fd -join ' | ')
# Positive control: the same file with one item member TFDParam does not have.
$bad = ([IO.File]::ReadAllText((P 'ParDM.dfm'))) -replace "(?m)^(\s+)Name = 'ID'\r?$", "`$1Name = 'ID'`r`n`$1Bogus = 1"
[IO.File]::WriteAllText((P 'ParBad.dfm'), $bad, [Text.Encoding]::ASCII)
$fdb = Invoke-FireDacLoad @((P 'ParBad.dfm'))
Check 'F4-6 positive control: a malformed ParamData item (Bogus = 1) FAILS the real load' `
  (@($fdb | Where-Object { $_ -match '^FAIL ParBad\.dfm: .*Bogus' }).Count -ge 1) ($fdb -join ' | ')

# ---- F1 / F6 / F2 on ScopeDM -----------------------------------------------------
$o = (& $Exe convert-apply --unit (P 'ScopeDM.pas') --rules (P 'scope.rules') --db $db --format json 2>&1) -join "`n"
$j = $null; try { $j = $o.Substring($o.IndexOf('{')) | ConvertFrom-Json } catch {}
Check 'S0 dry run: apply/1 JSON, ok' (($null -ne $j) -and $j.ok) $o
$r = (& $Exe convert-apply --unit (P 'ScopeDM.pas') --rules (P 'scope.rules') --db $db --apply --no-backup 2>&1) -join "`n"
Check 'S1 --apply exits 0' ($LASTEXITCODE -eq 0) $r
$t  = [IO.File]::ReadAllText((P 'ScopeDM.dfm'))
$ps = [IO.File]::ReadAllText((P 'ScopeDM.pas'))
$bDb = BlockOf $t 'db'; $bTbl = BlockOf $t 'tbl'; $bLbl = BlockOf $t 'lbl'; $bLbn = BlockOf $t 'lbn'; $bFa = BlockOf $t 'fa'; $bFg = BlockOf $t 'fg'

Check 'F1a the #mapping #apply''d in the TSrcDb block fires there: db Kind = gkMan' ($bDb -match '(?m)^\s+Kind = gkMan\r?$') $bDb
Check 'F1a ... and NOT in the TSrcTbl block: tbl has no Kind' (($bTbl -match 'object tbl: TDstTbl') -and -not ($bTbl -match 'Kind')) $bTbl
Check 'F1b the file-scope #link Remark <- Hint applies in every block: db and tbl' `
  (($bDb -match "(?m)^\s+Remark = 'dh'\r?$") -and ($bTbl -match "(?m)^\s+Remark = 'th'\r?$")) ($bDb + $bTbl)
$sites = @($j.items | Where-Object { $_.kind -eq 'access-site-rewritten' })
Check 'F1c/d the file-scope (no preceding #convert) #link rewrites EVERY instance''s .pas site, once each' `
  (($sites.Count -eq 2) -and ($ps -match 'db\.Remark := ''x'';') -and ($ps -match 'tbl\.Remark := ''y'';') -and -not ($ps -match '\.Hint')) (($sites | ForEach-Object text) -join ' | ')

$cnt = { param($b, $n) ([regex]::Matches($b, "(?m)^\s+$n = ")).Count }
Check 'F6a visual (published Left/Top) with #link: exactly one Left = 5 and one Top = 6' `
  (((& $cnt $bLbl 'Left') -eq 1) -and ((& $cnt $bLbl 'Top') -eq 1) -and ($bLbl -match '(?m)^\s+Left = 5\r?$') -and ($bLbl -match '(?m)^\s+Top = 6\r?$')) $bLbl
Check 'F6b visual with NO #link: the DesignInfo fallback does not carry them' `
  ((($bLbn -match "Caption = 'b'")) -and ((& $cnt $bLbn 'Left') -eq 0) -and ((& $cnt $bLbn 'Top') -eq 0)) $bLbn
Check 'F6c ... they are reported unlinked instead (rules decide)' `
  ((@($j.unlinked | Where-Object { $_.from_type -eq 'TSrcLblN' -and $_.path -in 'Left', 'Top' }).Count -eq 2)) (($j.unlinked | ConvertTo-Json -Compress -Depth 4))
Check 'F6d non-visual control: db keeps Left = 10, Top = 20 once each' `
  (((& $cnt $bDb 'Left') -eq 1) -and ((& $cnt $bDb 'Top') -eq 1) -and ($bDb -match 'Left = 10') -and ($bDb -match 'Top = 20')) $bDb

Check 'F2a target chain over THREE units (LibT.TDstAuto2 -> LibM.TMidFld -> LibS.TBaseFld): no Gen written on fa' `
  (($bFa -match 'object fa: TDstAuto2') -and -not ($bFa -match 'Gen =')) $bFa
Check 'F2b ... and the skip is reported' (@($j.reemit_notes | Where-Object { $_ -match '^fa: 1 resolved default\(s\) not written -- Gen: TDstAuto2 redeclares' }).Count -eq 1) ($j.reemit_notes -join ' | ')
# G1 a GENERIC ancestor: TGenBase<Integer> resolves in the class chain (the
# index names it LibS.TGenBase), so TDstG's redeclaration is proven more
# derived and the source's gkNone is not written -- the same rule as F2a.
Check 'G1 generic ancestor (TDstG = class(TGenBase<Integer>)): no Gen written on fg, and reported' `
  (($bFg -match 'object fg: TDstG') -and -not ($bFg -match 'Gen =') -and `
   (@($j.reemit_notes | Where-Object { $_ -match '^fg: 1 resolved default\(s\) not written -- Gen: TDstG redeclares' }).Count -eq 1)) ($bFg + ' || ' + ($j.reemit_notes -join ' | '))

$fails = Test-DfmLoads @((P 'ScopeDM.dfm'), (P 'ParDM.dfm'))
Check 'L the converted .dfm files LOAD (text -> binary -> text -> binary)' ($fails.Count -eq 0) ($fails -join ' | ')

$RsVars = 'C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\rsvars.bat'
$CRLF = "`r`n"
[IO.File]::WriteAllText((P 'P.dpr'), (@('program P;', '', 'uses', '  LibS, LibM, LibT, BdeStub, FdStub, ScopeDM, ParDM;', '', 'begin', 'end.') -join $CRLF) + $CRLF, [Text.Encoding]::ASCII)
New-Item -ItemType Directory (P 'bin'), (P 'dcu') -Force | Out-Null
$bat = P 'compile.bat'; $log = P 'compile.log'
[IO.File]::WriteAllText($bat, (@('@echo off', "call `"$RsVars`"", "cd /d `"$WorkDir`"",
  "dcc64 -Q -B -NSSystem;Data -E`"$WorkDir\bin`" -NU`"$WorkDir\dcu`" P.dpr", 'echo BUILD_EXITCODE=%ERRORLEVEL%') -join $CRLF), [Text.Encoding]::ASCII)
Start-Process cmd.exe -ArgumentList '/c', "`"$bat`"" -RedirectStandardOutput $log -RedirectStandardError "$log.err" -NoNewWindow -Wait | Out-Null
$cl = Get-Content $log -Raw -ErrorAction SilentlyContinue
$errLines = @(($cl -split "`r?`n") | Where-Object { $_ -match 'Error|Fatal' })
Check 'C the converted ScopeDM and ParDM compile with dcc64 (private -E/-NU)' (($cl -match 'BUILD_EXITCODE=0') -and ($errLines.Count -eq 0)) ($errLines -join ' | ')

Write-Host ''
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
} finally {
  if (-not $Keep) { foreach ($d23 in @("C:\TEMP\draglint_convert_apply_semantics_controls_$PID")) { if (Test-Path -LiteralPath $d23) { Remove-Item -LiteralPath $d23 -Recurse -Force -ErrorAction SilentlyContinue } } }
}
