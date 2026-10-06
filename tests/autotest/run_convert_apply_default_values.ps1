<#
  run_convert_apply_default_values.ps1 -- every value convert-apply writes into a
  .dfm LOADS (1.25.2-alpha).

  THE DEFECT (DMTEST's DMREADINGS, 1.25.0 and 1.25.1): the converted .dfm was
  refused by Delphi's reader ("Identifier expected", line 28). Two shapes, both
  from the RESOLVED-DEFAULT step (a #link'd source property absent from the
  block is written with its declared default):
    * `CachedUpdates = (False)]` -- Bde.DBTables declares
          [Default(False)]
          property CachedUpdates: Boolean ... default False;
      and the property's span starts at the ATTRIBUTE line; the default-clause
      reader took the attribute's `Default(` for the `default` directive.
    * `FieldDefs.Items.Attributes = []` -- a resolved default written to a path
      through a PUBLIC hop (`Items`, an indexed property; also `ParentDef`).
      The .dfm surface streams published properties only, so such a line is
      text the reader parses and the form then cannot load.

  THE CONTRACT this guard pins:
    D1 an attribute before a property never supplies its default: Flag is
       written `Flag = False` (the `default False` directive), not `(False)]`.
    D2 a resolved default is written only to a path whose every hop is
       PUBLISHED: nothing is written for Defs.Items.Size or Sub.Level.
    D3 one fixture per value kind goes through the LOAD round trip (tests\
       autotest\lib\DfmLoadCheck.ps1): resolved defaults -- Boolean, enum,
       set, negative Integer -- and streamed values carried verbatim -- float,
       a string with an embedded quote, a multi-line string, a #-coded char, a
       binary {...} payload, a collection.
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
  [string]$WorkDir = "C:\TEMP\draglint_convert_apply_default_values_$PID"
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

Write-Ascii (P 'LibA.pas') @'
unit LibA;

interface

uses
  System.Classes;

type
  TMyEnum = (meA, meB, meC);
  TMySet  = set of TMyEnum;

  TMyItem = class(TCollectionItem)
  private
    FName: string;
    FSize: Integer;
  published
    property Name: string read FName write FName;
    property Size: Integer read FSize write FSize default 0;
  end;

  TMyDefs = class(TCollection)
  private
    function GetItem(Index: Integer): TMyItem;
  public
    property Items[Index: Integer]: TMyItem read GetItem; default;
  end;

  TSubOpts = class(TPersistent)
  private
    FLevel: Integer;
  published
    property Level: Integer read FLevel write FLevel default 3;
  end;

  TBlob = class(TPersistent)
  end;

  TSrcVal = class(TComponent)
  private
    FFlag : Boolean;
    FMode : TMyEnum;
    FOpts : TMySet;
    FCount: Integer;
    FRatio: Double;
    FText : string;
    FMemo : string;
    FCh   : Char;
    FData : TBlob;
    FDefs : TMyDefs;
    FSub  : TSubOpts;
  public
    property Sub: TSubOpts read FSub write FSub;
  published
    [Default(False)]
    property Flag: Boolean read FFlag write FFlag default False;
    property Mode: TMyEnum read FMode write FMode default meB;
    property Opts: TMySet read FOpts write FOpts default [meA, meC];
    property Count: Integer read FCount write FCount default -1;
    property Ratio: Double read FRatio write FRatio;
    property Text: string read FText write FText;
    property Memo: string read FMemo write FMemo;
    property Ch: Char read FCh write FCh;
    property Data: TBlob read FData write FData;
    property Defs: TMyDefs read FDefs write FDefs;
  end;

implementation

function TMyDefs.GetItem(Index: Integer): TMyItem;
begin
  Result := TMyItem(inherited GetItem(Index));
end;

end.
'@
Write-Ascii (P 'LibB.pas') @'
unit LibB;

interface

uses
  System.Classes, LibA;

type
  TDstVal = class(TComponent)
  private
    FFlag : Boolean;
    FMode : TMyEnum;
    FOpts : TMySet;
    FCount: Integer;
    FRatio: Double;
    FText : string;
    FMemo : string;
    FCh   : Char;
    FData : TBlob;
    FDefs : TMyDefs;
    FSub  : TSubOpts;
  public
    property Sub: TSubOpts read FSub write FSub;
  published
    property Flag: Boolean read FFlag write FFlag;
    property Mode: TMyEnum read FMode write FMode;
    property Opts: TMySet read FOpts write FOpts;
    property Count: Integer read FCount write FCount;
    property Ratio: Double read FRatio write FRatio;
    property Text: string read FText write FText;
    property Memo: string read FMemo write FMemo;
    property Ch: Char read FCh write FCh;
    property Data: TBlob read FData write FData;
    property Defs: TMyDefs read FDefs write FDefs;
  end;

implementation

end.
'@

# AbsentDM: every defaulted property ABSENT -> resolved defaults are written.
Write-Ascii (P 'AbsentDM.pas') @'
unit AbsentDM;

interface

uses
  System.Classes, LibA;

type
  TAbsentDM = class(TDataModule)
    v: TSrcVal;
  end;

implementation

{$R *.dfm}

end.
'@
Write-Ascii (P 'AbsentDM.dfm') @'
object AbsentDM: TAbsentDM
  object v: TSrcVal
    Text = 'a'
  end
end
'@
# StreamedDM: every value kind PRESENT -> carried verbatim.
Write-Ascii (P 'StreamedDM.pas') @'
unit StreamedDM;

interface

uses
  System.Classes, LibA;

type
  TStreamedDM = class(TDataModule)
    v: TSrcVal;
  end;

implementation

{$R *.dfm}

end.
'@
Write-Ascii (P 'StreamedDM.dfm') @'
object StreamedDM: TStreamedDM
  object v: TSrcVal
    Flag = True
    Mode = meC
    Opts = [meB]
    Count = -42
    Ratio = 1.500000000000000000
    Text = 'it''s quoted'
    Memo =
      'first line'#13#10 +
      'second line'
    Ch = #39
    Data = {
      0A0B0C0D0E0F}
    Defs = <
      item
        Name = 'k'
        Size = 4
      end>
  end
end
'@

Write-Ascii (P 'values.rules') @'
#convert LibA.TSrcVal -> LibB.TDstVal, LibB
#link Flag <- Flag
#link Mode <- Mode
#link Opts <- Opts
#link Count <- Count
#link Ratio <- Ratio
#link Text <- Text
#link Memo <- Memo
#link Ch <- Ch
#link Data <- Data
#link Defs.Items.Name <- Defs.Items.Name
#link Defs.Items.Size <- Defs.Items.Size
#link Sub.Level <- Sub.Level
'@

$db = P 'fx.sqlite'
$idx = & $Exe index $WorkDir --db $db 2>&1
Check 'V the fixture index was built' (($LASTEXITCODE -eq 0) -and (Test-Path $db)) "exit=$LASTEXITCODE; $($idx -join ' | ')"
Check 'V the load checker is available (lib\DfmLoadCheck.ps1)' (Test-DfmLoadsChecker)

function ApplyTo([string]$Unit, [string[]]$Extra = @()) {
  $o = (& $Exe convert-apply --unit (P $Unit) --rules (P 'values.rules') --db $db @Extra 2>&1) -join "`n"
  return [pscustomobject]@{ Code = $LASTEXITCODE; Out = $o }
}

# ---- the guard itself: POSITIVE CONTROL -----------------------------------------
# Without a known-bad input failing, a green guard proves nothing.
Write-Ascii (P 'Bad1.dfm') @'
object Bad1: TBad1
  object t: TFDTable
    CachedUpdates = (False)]
  end
end
'@
Write-Ascii (P 'Bad2.dfm') @'
object Bad2: TBad2
  object t: TFDTable
    object f: TIntegerField
    end
    Active = False
  end
end
'@
Write-Ascii (P 'Bad3.dfm') @'
object Bad3: TBad3
  object t: TFDTable
    FieldDefs.Items.Attributes = []
  end
end
'@
$pc = Test-DfmLoads @((P 'Bad1.dfm'), (P 'Bad2.dfm'), (P 'Bad3.dfm'))
Check 'G1 positive control: the 1.25.1 value shape ''CachedUpdates = (False)]'' FAILS the load guard' `
  (@($pc | Where-Object { $_ -match 'Bad1\.dfm' }).Count -eq 1) ($pc -join ' | ')
Check 'G2 positive control: a property AFTER a nested object FAILS the load guard' `
  (@($pc | Where-Object { $_ -match 'Bad2\.dfm' }).Count -eq 1) ($pc -join ' | ')
# The guard's stated LIMIT, pinned so nobody reads more into it: a dotted name
# through a non-published member PARSES -- only a load against the real classes
# rejects it. D2 below is what guards that shape.
Check 'G3 limit, pinned: ''FieldDefs.Items.Attributes = []'' PARSES (caught by D2, not by the load guard)' `
  (@($pc | Where-Object { $_ -match 'Bad3\.dfm' }).Count -eq 0) ($pc -join ' | ')

# ---- resolved defaults --------------------------------------------------------
$r = ApplyTo 'AbsentDM.pas' @('--format', 'json')
$jd = $null; try { $jd = $r.Out.Substring($r.Out.IndexOf('{')) | ConvertFrom-Json } catch {}
Check 'D2b a default NOT written for a non-published path is REPORTED: one reemit note, count and paths' `
  (($null -ne $jd) -and (@($jd.reemit_notes | Where-Object { $_ -match '^v: 2 resolved default\(s\) not written -- Defs\.Items\.Size, Sub\.Level: the path runs through a non-published member' }).Count -eq 1)) ($jd.reemit_notes -join ' | ')
$r = ApplyTo 'AbsentDM.pas' @('--apply', '--no-backup')
$t = [IO.File]::ReadAllText((P 'AbsentDM.dfm'))
Check 'A0 --apply exits 0' ($r.Code -eq 0) $r.Out
Check 'D1 the attribute [Default(False)] does not supply the default: Flag = False' `
  (($t -match '(?m)^\s+Flag = False\r?$') -and -not ($t -match '\(False\)')) $t
Check 'D1b enum, set and negative Integer defaults written as declared' `
  (($t -match '(?m)^\s+Mode = meB\r?$') -and ($t -match '(?m)^\s+Opts = \[meA, meC\]\r?$') -and ($t -match '(?m)^\s+Count = -1\r?$')) $t
Check 'D2 nothing written through a non-published hop: no Defs.Items.* line, no Sub.Level line' `
  (-not ($t -match 'Defs\.Items\.') -and -not ($t -match 'Sub\.Level')) $t
$fails = Test-DfmLoads @((P 'AbsentDM.dfm'))
Check 'D3a the resolved-default .dfm LOADS (text -> binary -> text -> binary)' ($fails.Count -eq 0) ($fails -join ' | ')

# ---- streamed values ------------------------------------------------------------
$r = ApplyTo 'StreamedDM.pas' @('--apply', '--no-backup')
$t = [IO.File]::ReadAllText((P 'StreamedDM.dfm'))
Check 'S0 --apply exits 0, object v: TDstVal' (($r.Code -eq 0) -and ($t -match 'object v: TDstVal')) $r.Out
Check 'S1 every value kind carried verbatim: float, quoted string, multi-line string, #39, binary, collection' `
  (($t -match 'Ratio = 1\.500000000000000000') -and ($t -match "Text = 'it''s quoted'") -and ($t -match "'first line'#13#10 \+") -and `
   ($t -match 'Ch = #39') -and ($t -match '0A0B0C0D0E0F') -and ($t -match "Name = 'k'") -and ($t -match 'Opts = \[meB\]') -and ($t -match 'Count = -42')) $t
$fails = Test-DfmLoads @((P 'StreamedDM.dfm'))
Check 'D3b the streamed-values .dfm LOADS' ($fails.Count -eq 0) ($fails -join ' | ')

Write-Host ''
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
} finally {
  foreach ($d23 in @("C:\TEMP\draglint_convert_apply_default_values_$PID")) { if (Test-Path -LiteralPath $d23) { Remove-Item -LiteralPath $d23 -Recurse -Force -ErrorAction SilentlyContinue } }
}
