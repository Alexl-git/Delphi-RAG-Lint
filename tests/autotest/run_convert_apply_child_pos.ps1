<#
  run_convert_apply_child_pos.ps1 -- a re-emitted .dfm header keeps its `[n]`
  child-position marker (1.26.5-alpha).

  THE DEFECT (1.26.2 acceptance run, DMTEST copies): every header the re-emit
  wrote lost its marker -- `inherited tblX: TStringField [5]` came out as
  `inherited tblX: TStringField` (PathToData 77 -> 0 markers, dmDrawData
  45 -> 0). The marker is the ffChildPos filer flag: TReader.ReadComponent
  calls Parent.SetChildOrder(Result, Position) with it, so without it a
  dataset's Fields load in a DIFFERENT ORDER -- and code using Fields[i] or
  field order breaks without a word.

  THE CONTRACT this guard pins:
    P1 a RETYPED inherited table (C8 N2) keeps the markers of its nested
       blocks: `object tblN: TStringField [0]`, `inherited tblB: ... [1]`.
    P2 an OWN instance re-emitted in a descendant keeps its own header's
       marker: `object own2: TFDTable [0]`.
    P3 a retyped child of an `inline` frame keeps its marker, and the
       frame's own header line is untouched.
    P4 after a REAL VCL load of the chain (lib\DfmChainLoad.ps1: ancestor +
       descendant into one root, FireDAC / BDE classes registered) the
       converted table's Fields come up in the ORIGINAL order.
    P5 positive control: the same converted .dfm with its markers stripped
       loads in a different order -- the load really sees the marker.
    Every written .dfm goes through lib\DfmLoadCheck.ps1.
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
  [string]$WorkDir = "C:\TEMP\draglint_convert_apply_child_pos_$PID"
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
. (Join-Path $PSScriptRoot 'lib\DfmChainLoad.ps1')

if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
$Exe = (Resolve-Path $Exe).Path
if (Test-Path $WorkDir) { Remove-Item -Recurse -Force $WorkDir }
New-Item -ItemType Directory $WorkDir | Out-Null

function Write-Ascii([string]$Path, [string]$Body) {
  $norm = $Body -replace "`r`n", "`n" -replace "`n", "`r`n"
  [System.IO.File]::WriteAllText($Path, $norm, [System.Text.Encoding]::ASCII)
}
function P([string]$n) { return (Join-Path $WorkDir $n) }
function Text([string]$n) { return [IO.File]::ReadAllText((P $n)) }

# The fixture's classes carry the REAL names, so the real loader (P4/P5)
# instantiates real BDE / FireDAC / Data.DB classes from the converted text.
Write-Ascii (P 'LibA.pas') @'
unit LibA;

interface

uses
  System.Classes;

type
  TTable = class(TComponent)
  end;

  TStringField = class(TComponent)
  private
    FFieldName: string;
    FDisplayLabel: string;
  published
    property FieldName: string read FFieldName write FFieldName;
    property DisplayLabel: string read FDisplayLabel write FDisplayLabel;
  end;

implementation

end.
'@
Write-Ascii (P 'LibB.pas') @'
unit LibB;

interface

uses
  System.Classes;

type
  TFDTable = class(TComponent)
  end;

implementation

end.
'@

Write-Ascii (P 'CPBase.pas') @'
unit CPBase;

interface

uses
  System.Classes, LibA;

type
  TCPBase = class(TDataModule)
    tbl: TTable;
    tblA: TStringField;
    tblB: TStringField;
  end;

implementation

{$R *.dfm}

end.
'@
Write-Ascii (P 'CPBase.dfm') @'
object CPBase: TCPBase
  object tbl: TTable
    object tblA: TStringField
      FieldName = 'A'
    end
    object tblB: TStringField
      FieldName = 'B'
    end
  end
end
'@
Write-Ascii (P 'CPChild.pas') @'
unit CPChild;

interface

uses
  System.Classes, LibA, CPBase;

type
  TCPChild = class(TCPBase)
    tblN: TStringField;
    own2: TTable;
  end;

implementation

{$R *.dfm}

end.
'@
Write-Ascii (P 'CPChild.dfm') @'
inherited CPChild: TCPChild
  inherited tbl: TTable
    object tblN: TStringField [0]
      FieldName = 'N'
    end
    inherited tblB: TStringField [1]
      DisplayLabel = 'bee'
    end
  end
  object own2: TTable [0]
  end
end
'@

# ---- an inline frame whose child is retyped --------------------------------------
Write-Ascii (P 'CPFrame.pas') @'
unit CPFrame;

interface

uses
  System.Classes, Vcl.Forms, LibB;

type
  TCPFrame = class(TFrame)
    fq: TFDTable;
    fz: TFDTable;
  end;

implementation

{$R *.dfm}

end.
'@
Write-Ascii (P 'CPFrame.dfm') @'
object CPFrame: TCPFrame
  object fq: TFDTable
  end
  object fz: TFDTable
  end
end
'@
Write-Ascii (P 'CPHost.pas') @'
unit CPHost;

interface

uses
  System.Classes, Vcl.Forms, CPFrame;

type
  TCPHost = class(TForm)
    frm: TCPFrame;
  end;

implementation

{$R *.dfm}

end.
'@
Write-Ascii (P 'CPHost.dfm') @'
object CPHost: TCPHost
  inline frm: TCPFrame [0]
    inherited fz: TTable [0]
    end
  end
end
'@

Write-Ascii (P 'cp.rules') @'
#convert LibA.TTable -> LibB.TFDTable, LibB
'@

$origBase  = P 'orig-CPBase.dfm';  Copy-Item (P 'CPBase.dfm')  $origBase
$origChild = P 'orig-CPChild.dfm'; Copy-Item (P 'CPChild.dfm') $origChild

$db = P 'fx.sqlite'
$idx = & $Exe index $WorkDir --db $db 2>&1
Check 'V the fixture index was built' (($LASTEXITCODE -eq 0) -and (Test-Path $db)) "exit=$LASTEXITCODE; $($idx -join ' | ')"
Check 'V the chain loader is available (lib\DfmChainLoad.ps1)' (Test-DfmChainLoader)

function ApplyTo([string]$Unit, [string[]]$Extra = @()) {
  $o = (& $Exe convert-apply --unit (P $Unit) --rules (P 'cp.rules') --db $db @Extra 2>&1) -join "`n"
  return [pscustomobject]@{ Code = $LASTEXITCODE; Out = $o }
}

# ancestor first, then reindex, then the descendant
$r = ApplyTo 'CPBase.pas' @('--apply', '--no-backup')
Check 'A1 CPBase (ancestor) converted: exit 0, object tbl: TFDTable' (($r.Code -eq 0) -and ((Text 'CPBase.dfm') -match 'object tbl: TFDTable')) $r.Out
$idx = & $Exe index $WorkDir --db $db 2>&1
$r = ApplyTo 'CPChild.pas' @('--apply', '--no-backup')
$t = Text 'CPChild.dfm'
Check 'A2 CPChild --apply: exit 0, tbl retyped (inherited tbl: TFDTable)' (($r.Code -eq 0) -and ($t -match '(?m)^  inherited tbl: TFDTable\r?$')) ($r.Out + "`n" + $t)
Check 'P1 the retyped table keeps its nested markers: object tblN ... [0], inherited tblB ... [1]' `
  (($t -match '(?m)^    object tblN: TStringField \[0\]\r?$') -and ($t -match '(?m)^    inherited tblB: TStringField \[1\]\r?$')) $t
Check 'P2 an own instance re-emitted in the descendant keeps its marker: object own2: TFDTable [0]' `
  ($t -match '(?m)^  object own2: TFDTable \[0\]\r?$') $t
$r = ApplyTo 'CPHost.pas' @('--apply', '--no-backup')
$h = Text 'CPHost.dfm'
Check 'P3 inline frame: its retyped child keeps [0], the frame header line is untouched' `
  (($r.Code -eq 0) -and ($h -match '(?m)^    inherited fz: TFDTable \[0\]\r?$') -and ($h -match '(?m)^  inline frm: TCPFrame \[0\]\r?$')) ($r.Out + "`n" + $h)

# ---- the real load -----------------------------------------------------------------
$orig = Get-DfmFieldOrder "$origBase+$origChild" 'tbl'
$conv = Get-DfmFieldOrder "$(P 'CPBase.dfm')+$(P 'CPChild.dfm')" 'tbl'
Check 'P4 real VCL load: the converted chain''s tbl.Fields come up in the ORIGINAL order' (($orig -eq 'N B A') -and ($conv -eq $orig)) "orig=[$orig] conv=[$conv]"
$stripped = P 'stripped-CPChild.dfm'
Write-Ascii $stripped ((Text 'CPChild.dfm') -replace ' \[\d+\]', '')
$strip = Get-DfmFieldOrder "$(P 'CPBase.dfm')+$stripped" 'tbl'
Check 'P5 positive control: the same .dfm with its markers stripped loads in a DIFFERENT order' ($strip -ne $orig) "orig=[$orig] stripped=[$strip]"

$loadFails = Test-DfmLoads @((P 'CPBase.dfm'), (P 'CPChild.dfm'), (P 'CPHost.dfm'))
Check 'LOAD1 every .dfm --apply wrote LOADS (text -> binary -> text -> binary)' ($loadFails.Count -eq 0) ($loadFails -join ' | ')

Write-Host ''
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
} finally {
  foreach ($d23 in @("C:\TEMP\draglint_convert_apply_child_pos_$PID")) { if (Test-Path -LiteralPath $d23) { Remove-Item -LiteralPath $d23 -Recurse -Force -ErrorAction SilentlyContinue } }
}
