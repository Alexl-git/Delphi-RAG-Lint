# drag-lint forms-csv MULTI-DB regression test. Proves a form reachable ONLY
# via a launch-body that lives in a SECOND index (COMMON) prints DEAD when
# only the CLIENT db is indexed/passed, and RESOLVES to its real chain once
# both the CLIENT and COMMON dbs are passed together.
#
# Pattern replicated from tests/fixtures/formsmap-v4 (frmRoot4 -> 'Plan' ->
# frmDirect4 via interface IThingPlan4 dispatch), but split across TWO
# directories/dbs instead of one:
#   CLIENT: root form + button OnClick dispatches through IPlanIntfMulti to a
#           concrete class -- the concrete launch body is NOT here.
#   COMMON: the concrete class implementing IPlanIntfMulti, whose method body
#           constructs the target form (TfrmPlanEditMulti).
#
# Usage: pwsh -File tests/autotest/run_formsmap_multidb.ps1 [-Exe <path>]
[CmdletBinding()]
param(
    [string] $Exe     = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
    [string] $WorkDir = "$env:TEMP\drag-lint-formsmap-multidb"
)
$ErrorActionPreference = 'Stop'
$script:Failed = $false
function Check([string]$Name, [bool]$Ok, [string]$Detail = '') {
    $status = if ($Ok) {'PASS'} else {'FAIL'}
    $color  = if ($Ok) {'Green'} else {'Red'}
    Write-Host ("  [{0}] {1} {2}" -f $status, $Name, $Detail) -ForegroundColor $color
    if (-not $Ok) { $script:Failed = $true }
}
if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
if (Test-Path $WorkDir) { Remove-Item -Recurse -Force $WorkDir }
New-Item -ItemType Directory $WorkDir | Out-Null

# --- CLIENT: root form (frmRootMulti) + target form (frmPlanEditMulti) + the
# shared interface decl. The root's button dispatches through the interface;
# the concrete implementation (and its launch body) live only in COMMON. ---
$client = "$WorkDir\client"
New-Item -ItemType Directory $client | Out-Null

@'
unit uPlanIntfMulti;
interface
type
  IPlanMulti = interface
    ['{9C1D2E30-5F4A-4B6C-8D2E-3F4A5B6C7D8E}']
    procedure EditForm;
  end;
implementation
end.
'@ | Set-Content "$client\uPlanIntfMulti.pas" -Encoding ascii

@'
unit uRootMulti;
interface
uses Vcl.Forms, Vcl.StdCtrls, uPlanIntfMulti;
type
  TfrmRootMulti = class(TForm)
    btnPlan: TButton;
    procedure btnPlanClick(Sender: TObject);
  end;
var frmRootMulti: TfrmRootMulti;
implementation
uses uPlansMulti;
{$R *.dfm}
procedure TfrmRootMulti.btnPlanClick(Sender: TObject);
var
  APlan: IPlanMulti;
begin
  APlan := TDirectPlanMulti.Create;
  APlan.EditForm;
end;
end.
'@ | Set-Content "$client\uRootMulti.pas" -Encoding ascii

@'
object frmRootMulti: TfrmRootMulti
  Left = 0
  Top = 0
  Caption = 'RootMulti'
  ClientHeight = 200
  ClientWidth = 300
  object btnPlan: TButton
    Left = 8
    Top = 8
    Width = 75
    Height = 25
    Caption = 'Plan'
    OnClick = btnPlanClick
  end
end
'@ | Set-Content "$client\uRootMulti.dfm" -Encoding ascii

@'
unit uPlanEditMulti;
interface
uses Vcl.Forms;
type
  TfrmPlanEditMulti = class(TForm)
  end;
implementation
{$R *.dfm}
end.
'@ | Set-Content "$client\uPlanEditMulti.pas" -Encoding ascii

@'
object frmPlanEditMulti: TfrmPlanEditMulti
  Left = 0
  Top = 0
  Caption = 'PlanEditMulti'
  ClientHeight = 150
  ClientWidth = 250
end
'@ | Set-Content "$client\uPlanEditMulti.dfm" -Encoding ascii

$clientDpr = "$client\ClientMulti.dpr"
@'
program ClientMulti;
uses
  Vcl.Forms,
  uRootMulti in 'uRootMulti.pas' {frmRootMulti},
  uPlanIntfMulti in 'uPlanIntfMulti.pas',
  uPlanEditMulti in 'uPlanEditMulti.pas' {frmPlanEditMulti};

begin
  Application.Initialize;
  Application.CreateForm(TfrmRootMulti, frmRootMulti);
  Application.Run;
end.
'@ | Set-Content $clientDpr -Encoding ascii

$clientDproj = "$client\ClientMulti.dproj"
@'
<Project xmlns="http://schemas.microsoft.com/developer/msbuild/2003">
  <PropertyGroup>
    <MainSource>ClientMulti.dpr</MainSource>
  </PropertyGroup>
  <ItemGroup>
    <DCCReference Include="uRootMulti.pas"><Form>frmRootMulti</Form><FormType>dfm</FormType></DCCReference>
    <DCCReference Include="uPlanIntfMulti.pas"/>
    <DCCReference Include="uPlanEditMulti.pas"><Form>frmPlanEditMulti</Form><FormType>dfm</FormType></DCCReference>
  </ItemGroup>
</Project>
'@ | Set-Content $clientDproj -Encoding ascii

# --- COMMON: the concrete class implementing IPlanMulti; its EditForm body
# constructs frmPlanEditMulti. This is the ONLY launch body for that form. ---
$common = "$WorkDir\common"
New-Item -ItemType Directory $common | Out-Null

@'
unit uPlansMulti;
interface
uses uPlanIntfMulti;
type
  TDirectPlanMulti = class(TInterfacedObject, IPlanMulti)
    procedure EditForm;
  end;
implementation
uses uPlanEditMulti;
procedure TDirectPlanMulti.EditForm;
begin
  TfrmPlanEditMulti.Create(nil).ShowModal;
end;
end.
'@ | Set-Content "$common\uPlansMulti.pas" -Encoding ascii

$clientDb = "$WorkDir\client.sqlite"
$commonDb = "$WorkDir\common.sqlite"

& $Exe index $client --db $clientDb 2>&1 | Out-Null
Check 'client db indexed exits 0' ($LASTEXITCODE -eq 0)
& $Exe index $common --db $commonDb 2>&1 | Out-Null
Check 'common db indexed exits 0' ($LASTEXITCODE -eq 0)
Check 'dbs built' ((Test-Path $clientDb) -and (Test-Path $commonDb))

function Invoke-FormsCsv([string[]]$Dbs) {
    $dbArgs = @()
    foreach ($d in $Dbs) { $dbArgs += @('--db', $d) }
    return (& $Exe forms-csv --project $clientDproj @dbArgs --root TfrmRootMulti 2>&1) -join "`n"
}

# 1. CLIENT-only: frmPlanEditMulti's only launch body lives in COMMON, which is
#    not indexed here, so no caller is found at all -> DEAD FORM.
$only = Invoke-FormsCsv @($clientDb)
Check 'client-only shows PlanEditMulti as DEAD (no callers)' `
    (($only -match 'PlanEditMulti') -and ($only -match 'DEAD FORM')) $only

# 2. CLIENT + COMMON: the caller-search scope now spans both dbs, so
#    TDirectPlanMulti.EditForm's body is found and the chain resolves back to
#    frmRootMulti via the 'Plan' button caption.
$both = Invoke-FormsCsv @($clientDb, $commonDb)
Check 'multi-db resolves PlanEditMulti chain' ($both -match 'PlanEditMulti') $both
Check 'chain carries Plan caption' ($both -match "'Plan'") $both
$planEditRow = ($both -split "`n") | Where-Object { $_ -match 'PlanEditMulti' }
Check 'multi-db PlanEditMulti NOT dead' (-not ($planEditRow -match 'DEAD FORM')) $both

# 3. Provenance/version footer present in the --out file.
$outFile = "$WorkDir\out.csv"
& $Exe forms-csv --project $clientDproj --db $clientDb --db $commonDb --root TfrmRootMulti --out $outFile 2>&1 | Out-Null
Check 'forms-csv (multi-db, --out) exits 0' ($LASTEXITCODE -eq 0)
$outContent = Get-Content $outFile -Raw
Check 'footer has forms-csv algorithm version' ($outContent -match 'forms-csv algorithm v')

Write-Host ''
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
