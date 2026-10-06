<#
  run_convert_apply_semantics.ps1 -- four SILENT behaviour breaks in
  convert-apply, found by a real-data sweep of DMTEST with engine 1.25.2
  (1.26.1-alpha).

  F1 #ignore SCOPE. A rule book carried every #convert block's rules into
     every block: BDE-to-FireDAC.rules' `#ignore ReadOnly` in the TDatabase
     block suppressed the TTable block's `#link UpdateOptions.ReadOnly <-
     ReadOnly` and the TAutoIncField block's `#link ReadOnly <- ReadOnly`, so
     33 read-only tables and fields converted WRITABLE. The same book-wide
     lookup let the FIRST #link for a path win in every block, so a field's
     ReadOnly would have gone to the table's UpdateOptions.ReadOnly.
     Contract: #link / #ignore / #default / #remove / #apply belong to their
     own #convert block (plus the file-scope rules before the first #convert).
  F2 a TARGET'S REDECLARED DEFAULT. A resolved default is the source's
     declared default; when the target class redeclares the same inherited
     property with its own default (TFDAutoIncField: AutoGenerateValue default
     arAutoInc), writing the shared ancestor's value (arNone) switched the
     target's behaviour off. Contract: the most-derived declaration wins -- a
     resolved default is NOT written when the target inherits the class that
     declares the source's default and redeclares it; it IS written when the
     source redeclared it itself (the source's real value) and when both share
     one declaration (D3 of 1.20.6 unchanged).
  F6 DESIGNER POSITION. `Left` / `Top` on a non-visual component are written by
     TComponent.DefineProperties (DesignInfo), not published properties, so no
     rule could name them and they were dropped (90 components). Contract:
     carried unless a rule of the block names them.
  F4 ParamData. TQuery / TStoredProc stream their parameters through the
     DefineProperties pseudo-property `ParamData = < item ... >`, which no
     #link names, so every query lost its parameters (15 on DMTEST).
     Contract: ParamData is the streamed form of `Params`; each item member is
     mapped through the block's `#link Params.Items.<X>` rules, else carried
     when the target's Params item has the same member with the same type,
     else NOT carried and reported item by item.

  Every written .dfm goes through tests\autotest\lib\DfmLoadCheck.ps1.
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
  [string]$WorkDir = "C:\TEMP\draglint_convert_apply_semantics_$PID"
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

if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
$Exe = (Resolve-Path $Exe).Path
if (Test-Path $WorkDir) { Remove-Item -Recurse -Force $WorkDir }
New-Item -ItemType Directory $WorkDir | Out-Null

function Write-Ascii([string]$Path, [string]$Body) {
  $norm = $Body -replace "`r`n", "`n" -replace "`n", "`r`n"
  [System.IO.File]::WriteAllText($Path, $norm, [System.Text.Encoding]::ASCII)
}
function P([string]$n) { return (Join-Path $WorkDir $n) }

Write-Ascii (P 'LibS.pas') @'
unit LibS;

interface

uses
  System.Classes;

type
  TGenKind  = (gkNone, gkAuto, gkMan);
  TFlagKind = (fa, fb);
  TFlagSet  = set of TFlagKind;
  TPKind    = (pkUnknown, pkInput, pkOutput);

  TOpts = class(TPersistent)
  private
    FReadOnly: Boolean;
  published
    property ReadOnly: Boolean read FReadOnly write FReadOnly default False;
  end;

  TSrcDb = class(TComponent)
  private
    FReadOnly: Boolean;
    FHost    : string;
  published
    property ReadOnly: Boolean read FReadOnly write FReadOnly default False;
    property Host: string read FHost write FHost;
  end;

  TSrcTbl = class(TComponent)
  private
    FReadOnly: Boolean;
    FNote    : string;
  published
    property ReadOnly: Boolean read FReadOnly write FReadOnly default False;
    property Note: string read FNote write FNote;
  end;

  TBaseFld = class(TComponent)
  private
    FReadOnly: Boolean;
    FGen     : TGenKind;
    FFlags   : TFlagSet;
    FLevel   : Integer;
  published
    property ReadOnly: Boolean read FReadOnly write FReadOnly default False;
    property Gen: TGenKind read FGen write FGen default gkNone;
    property Flags: TFlagSet read FFlags write FFlags default [fa, fb];
    property Level: Integer read FLevel write FLevel default 3;
  end;

  TSrcAuto = class(TBaseFld)
  end;

  TSrcOwn = class(TBaseFld)
  published
    property Gen default gkMan;
  end;

  TSrcParam = class(TCollectionItem)
  private
    FName : string;
    FKind : TPKind;
    FValue: Variant;
    FSize : Integer;
  published
    property Name: string read FName write FName;
    property ParamType: TPKind read FKind write FKind default pkUnknown;
    property Value: Variant read FValue write FValue;
    property Size: Integer read FSize write FSize default 0;
  end;

  TSrcParams = class(TCollection)
  private
    function GetItem(Index: Integer): TSrcParam;
  public
    property Items[Index: Integer]: TSrcParam read GetItem; default;
  end;

  TSrcQry = class(TComponent)
  private
    FParams: TSrcParams;
    FSQL   : string;
  published
    property Params: TSrcParams read FParams write FParams stored False;
    property SQL: string read FSQL write FSQL;
  end;

implementation

function TSrcParams.GetItem(Index: Integer): TSrcParam;
begin
  Result := TSrcParam(inherited GetItem(Index));
end;

end.
'@
Write-Ascii (P 'LibT.pas') @'
unit LibT;

interface

uses
  System.Classes, LibS;

type
  TDstConn = class(TComponent)
  private
    FHost: string;
  published
    property Host: string read FHost write FHost;
  end;

  TDstTbl = class(TComponent)
  private
    FOpts: TOpts;
    FNote: string;
  published
    property UpdateOptions: TOpts read FOpts write FOpts;
    property Note: string read FNote write FNote;
  end;

  TDstAuto = class(TBaseFld)
  published
    property Gen default gkAuto;
    property Flags default [fa];
  end;

  TDstParam = class(TCollectionItem)
  private
    FName : string;
    FKind : TPKind;
    FValue: Variant;
  published
    property Name: string read FName write FName;
    property Kind: TPKind read FKind write FKind default pkUnknown;
    property Value: Variant read FValue write FValue;
  end;

  TDstParams = class(TCollection)
  private
    function GetItem(Index: Integer): TDstParam;
  public
    property Items[Index: Integer]: TDstParam read GetItem; default;
  end;

  TDstQry = class(TComponent)
  private
    FParams: TDstParams;
    FSQL   : string;
  published
    property Params: TDstParams read FParams write FParams stored False;
    property SQL: string read FSQL write FSQL;
  end;

implementation

function TDstParams.GetItem(Index: Integer): TDstParam;
begin
  Result := TDstParam(inherited GetItem(Index));
end;

end.
'@

Write-Ascii (P 'SemDM.pas') @'
unit SemDM;

interface

uses
  System.Classes, LibS;

type
  TSemDM = class(TDataModule)
    db: TSrcDb;
    tbl: TSrcTbl;
    fldA: TSrcAuto;
    fldO: TSrcOwn;
    qry: TSrcQry;
  end;

implementation

{$R *.dfm}

end.
'@
$SemDfm = @'
object SemDM: TSemDM
  object db: TSrcDb
    ReadOnly = True
    Host = 'h'
    Left = 24
    Top = 16
  end
  object tbl: TSrcTbl
    ReadOnly = True
    Note = 'n'
    Left = 120
    Top = 16
  end
  object fldA: TSrcAuto
    ReadOnly = True
  end
  object fldO: TSrcOwn
    ReadOnly = True
  end
  object qry: TSrcQry
    SQL = 'select 1'
    ParamData = <
      item
        Name = 'ID'
        ParamType = pkInput
        Value = 0
      end
      item
        Name = 'CODE'
        ParamType = pkInput
        Size = 4
        Value = 'ab'
      end>
    Left = 200
    Top = 64
  end
end
'@
Write-Ascii (P 'SemDM.dfm') $SemDfm

# Block order is load-bearing: the TSrcDb block's #ignore ReadOnly comes
# FIRST, then two blocks that #link ReadOnly to DIFFERENT targets.
Write-Ascii (P 'sem.rules') @'
#convert LibS.TSrcDb -> LibT.TDstConn, LibT
#link Host <- Host
#ignore ReadOnly

#convert LibS.TSrcTbl -> LibT.TDstTbl, LibT
#link UpdateOptions.ReadOnly <- ReadOnly
#ignore Note

#convert LibS.TSrcAuto -> LibT.TDstAuto, LibT
#link ReadOnly <- ReadOnly
#link Gen <- Gen
#link Flags <- Flags
#link Level <- Level

#convert LibS.TSrcOwn -> LibT.TDstAuto, LibT
#link ReadOnly <- ReadOnly
#link Gen <- Gen

#convert LibS.TSrcQry -> LibT.TDstQry, LibT
#link SQL <- SQL
#link Params.Items.Name <- Params.Items.Name
#link Params.Items.Kind <- Params.Items.ParamType
#link Params.Items.Value <- Params.Items.Value
'@

$db = P 'fx.sqlite'
$idx = & $Exe index $WorkDir --db $db 2>&1
Check 'V the fixture index was built' (($LASTEXITCODE -eq 0) -and (Test-Path $db)) "exit=$LASTEXITCODE; $($idx -join ' | ')"
Check 'V the load checker is available (lib\DfmLoadCheck.ps1)' (Test-DfmLoadsChecker)

$o = (& $Exe convert-apply --unit (P 'SemDM.pas') --rules (P 'sem.rules') --db $db --format json 2>&1) -join "`n"
$j = $null; try { $j = $o.Substring($o.IndexOf('{')) | ConvertFrom-Json } catch {}
Check 'A0 dry run parses as apply/1 JSON' ($null -ne $j) $o
$r = (& $Exe convert-apply --unit (P 'SemDM.pas') --rules (P 'sem.rules') --db $db --apply --no-backup 2>&1) -join "`n"
Check 'A1 --apply exits 0' ($LASTEXITCODE -eq 0) $r
$t = [IO.File]::ReadAllText((P 'SemDM.dfm'))

function BlockOf([string]$Text, [string]$Name) {
  $m = [regex]::Match($Text, "(?ms)^  object $Name\b.*?^  end\r?$")
  if ($m.Success) { return $m.Value } else { return '' }
}
$bDb = BlockOf $t 'db'; $bTbl = BlockOf $t 'tbl'; $bA = BlockOf $t 'fldA'; $bO = BlockOf $t 'fldO'; $bQ = BlockOf $t 'qry'

# ---- F1 ---------------------------------------------------------------------
Check 'F1a positive control: the TSrcDb block''s OWN #ignore ReadOnly still suppresses (no ReadOnly on db)' `
  (($bDb -match 'object db: TDstConn') -and -not ($bDb -match 'ReadOnly')) $bDb
Check 'F1b another block''s #ignore does NOT suppress: tbl keeps UpdateOptions.ReadOnly = True' `
  ($bTbl -match '(?m)^\s+UpdateOptions\.ReadOnly = True\r?$') $bTbl
Check 'F1c the TSrcAuto block''s OWN #link wins: fldA gets ReadOnly = True, not UpdateOptions.ReadOnly' `
  (($bA -match '(?m)^\s+ReadOnly = True\r?$') -and -not ($bA -match 'UpdateOptions')) $bA
Check 'F1d a #ignore of one block is not reported as ignored for another (tbl Note: its own #ignore, nothing dropped)' `
  (-not ($bTbl -match 'Note') -and -not (@($j.warnings | Where-Object { $_ -match 'ReadOnly' }).Count)) (($j.warnings -join ' | ') + ' || ' + $bTbl)

# ---- F2 ---------------------------------------------------------------------
Check 'F2a the target''s redeclared default wins: fldA has no Gen = gkNone and no Flags line' `
  (-not ($bA -match 'Gen =') -and -not ($bA -match 'Flags =')) $bA
Check 'F2b a SHARED declaration is still written (D3): fldA Level = 3' ($bA -match '(?m)^\s+Level = 3\r?$') $bA
Check 'F2c a default the SOURCE redeclared is the source''s real value and is written: fldO Gen = gkMan' `
  ($bO -match '(?m)^\s+Gen = gkMan\r?$') $bO
Check 'F2d the skipped default is REPORTED, not silent (reemit note names Gen and Flags on fldA)' `
  (@($j.reemit_notes | Where-Object { $_ -match '^fldA: .*Gen.*Flags|^fldA: .*Flags.*Gen' }).Count -eq 1) ($j.reemit_notes -join ' | ')

# ---- F6 ---------------------------------------------------------------------
Check 'F6a Left/Top carried on a converted non-visual component (db, tbl, qry)' `
  (($bDb -match '(?m)^\s+Left = 24\r?$') -and ($bDb -match '(?m)^\s+Top = 16\r?$') -and `
   ($bTbl -match '(?m)^\s+Left = 120\r?$') -and ($bQ -match '(?m)^\s+Left = 200\r?$') -and ($bQ -match '(?m)^\s+Top = 64\r?$')) ($bDb + $bTbl + $bQ)
Check 'F6b Left/Top are not reported as unlinked' `
  (-not (@($j.unlinked | Where-Object { "$_" -match '\bLeft\b|\bTop\b' }).Count)) (($j.unlinked | ConvertTo-Json -Compress -Depth 4))

# ---- F4 ---------------------------------------------------------------------
Check 'F4a ParamData carried: both items, Name and Value kept' `
  (($bQ -match 'ParamData = <') -and ($bQ -match "Name = 'ID'") -and ($bQ -match "Name = 'CODE'") -and ($bQ -match "Value = 'ab'") -and ($bQ -match 'Value = 0')) $bQ
Check 'F4b an item member is mapped through the block''s renaming #link Params.Items.Kind <- Params.Items.ParamType' `
  ((([regex]::Matches($bQ, '(?m)^\s+Kind = pkInput\r?$')).Count -eq 2) -and -not ($bQ -match 'ParamType')) $bQ
Check 'F4c a member the target item lacks (Size) is NOT carried' (-not ($bQ -match 'Size =')) $bQ
Check 'F4d ... and is REPORTED item by item (item 2 CODE: Size = 4)' `
  (@($j.reemit_notes + $j.warnings | Where-Object { $_ -match 'ParamData item 2 \(CODE\): Size = 4 not carried' }).Count -ge 1) (($j.reemit_notes + $j.warnings) -join ' | ')
Check 'F4e ParamData is no longer reported unlinked' `
  (-not (@($j.unlinked | Where-Object { "$_" -match 'ParamData' }).Count)) (($j.unlinked | ConvertTo-Json -Compress -Depth 4))

# ---- load -------------------------------------------------------------------
$fails = Test-DfmLoads @((P 'SemDM.dfm'))
Check 'L the converted .dfm LOADS (text -> binary -> text -> binary)' ($fails.Count -eq 0) ($fails -join ' | ')

Write-Host ''
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
} finally {
  foreach ($d23 in @("C:\TEMP\draglint_convert_apply_semantics_$PID")) { if (Test-Path -LiteralPath $d23) { Remove-Item -LiteralPath $d23 -Recurse -Force -ErrorAction SilentlyContinue } }
}
