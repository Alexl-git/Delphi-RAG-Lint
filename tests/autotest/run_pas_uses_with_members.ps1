<#
  run_pas_uses_with_members.ps1 -- T-16 (BACKLOG-INDEX A9) pin: convert-apply
  pas_uses[] rows for members reached through a `with` block, and the
  classification of a member an RTL ancestor declares.

  Pins (2026-10-25, lane X3):
    * W1-W3 a member reached through `with pic1 do` (single statement and
      begin..end; a call and an assignment) is listed on its pas_uses row with
      the with-body line, beside the plain site (fixed by 8d33c68d G10 for
      #migrate; this guard covers the rows with NO #migrate: unmapped/mapped).
      Positive control: run against an engine before 8d33c68d (e.g. a
      1.31.4 backup) and W1/W2/W3 go red -- the with-body lines are missing.
    * R1 a member declared by an RTL ancestor (TComponent.Tag) with ONLY the
      project --db is resolution member-not-found with an EMPTY kind -- never a
      guessed kind. Classifying it needs the platform library as a second --db
      (by design: an explicit --db list is strict; the convrules editor passes
      the libraries). With -LibDb, L1 asserts same-name / System.Classes.
  Not extraction: the index already holds every site; this is the
  convert-apply report.
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
  [string]$WorkDir = "C:\TEMP\draglint_pas_uses_with_$PID",
  [string]$LibDb   = ''
)
try {
$ErrorActionPreference = 'Continue'
$script:fail = $false
function Check($n,$ok,$d=''){
  Write-Host ("[{0}] {1}" -f (@('FAIL','PASS')[[int][bool]$ok]),$n) -ForegroundColor (@('Red','Green')[[int][bool]$ok])
  if(-not $ok){ if($d){ Write-Host "      $d" -ForegroundColor DarkGray }; $script:fail=$true }
}
if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
$Exe = (Resolve-Path $Exe).Path
New-Item -ItemType Directory $WorkDir -Force | Out-Null
function P([string]$n) { return (Join-Path $WorkDir $n) }
function W([string]$n, [string]$t) { [IO.File]::WriteAllText((P $n), (($t -replace "`r`n","`n") -replace "`n","`r`n"), [Text.Encoding]::ASCII) }
W 'LibBase.pas' @'
unit LibBase;

interface

uses
  Classes;

type
  TPicBase = class(TComponent)
  private
    FTag2: Integer;
  public
    procedure Refresh(A: Integer; const B: string);
  published
    property Tag2: Integer read FTag2 write FTag2;
  end;

implementation

procedure TPicBase.Refresh(A: Integer; const B: string);
begin
end;

end.
'@
W 'LibOld.pas' @'
unit LibOld;

interface

uses
  Classes, LibBase;

const
  OLD_MAX = 5;

type
  TSrcPic = class(TPersistent)
  private
    FData: string;
  published
    property Data: string read FData write FData;
  end;

  TOldMid = class(TPicBase)
  public
    procedure MidOnly;
  end;

  TPicOld = class(TOldMid)
  private
    FPicture: TSrcPic;
    FCaption: string;
    FOnPaint: TNotifyEvent;
  public
    procedure DoOld(X: Integer);
    function OldOnly: Integer;
  published
    property Picture: TSrcPic read FPicture write FPicture;
    property Caption: string read FCaption write FCaption;
    property OnPaint: TNotifyEvent read FOnPaint write FOnPaint;
  end;

function OldGlobal(A: Integer): Integer;

implementation

procedure TOldMid.MidOnly;
begin
end;

procedure TPicOld.DoOld(X: Integer);
begin
end;

function TPicOld.OldOnly: Integer;
begin
  Result:= 0;
end;

function OldGlobal(A: Integer): Integer;
begin
  Result:= A;
end;

end.
'@
W 'LibNew.pas' @'
unit LibNew;

interface

uses
  Classes, LibBase;

type
  TDstGlyph = class(TPersistent)
  private
    FData: string;
  published
    property Data: string read FData write FData;
  end;

  TPicNew = class(TPicBase)
  private
    FGlyph: TDstGlyph;
    FCaption: string;
  published
    property Glyph: TDstGlyph read FGlyph write FGlyph;
    property Caption: string read FCaption write FCaption;
  end;

implementation

end.
'@

# Line numbers are asserted below -- keep the body as is.
W 'WForm.pas' @"
unit WForm;

interface

uses
  Classes, LibBase, LibOld;

type
  TWForm = class(TComponent)
    pic1: TPicOld;
    procedure Run;
  end;

implementation

{`$R *.dfm}

procedure TWForm.Run;
begin
  pic1.DoOld(1);
  with pic1 do
    DoOld(2);
  with pic1 do
  begin
    MidOnly;
    Caption := 'y';
  end;
  pic1.Tag := 1;
end;

end.
"@
W 'WForm.dfm' "object WForm: TWForm`n  object pic1: TPicOld`n    Caption = 'p'`n  end`nend`n"
W 'P.dpr' "program P;`n`nuses`n  LibBase, LibOld, LibNew, WForm;`n`nbegin`nend.`n"
W 'w.rules' "#convert TPicOld -> TPicNew`n#link Caption <- Caption`n"

$db = P 'fx.sqlite'
& $Exe index --project (P 'P.dpr') --db $db 2>&1 | Out-Null
Check 'V the fixture PROJECT index was built' (Test-Path $db)

function J([string[]]$Dbs) {
  $a = @('convert-apply', '--unit', (P 'WForm.pas'), '--rules', (P 'w.rules'), '--format', 'json')
  foreach ($d in $Dbs) { $a += @('--db', $d) }
  $o = (& $Exe @a 2>$null) -join "`n"
  $code = $LASTEXITCODE
  $j = $null; try { $j = $o.Substring($o.IndexOf('{')) | ConvertFrom-Json } catch {}
  return [pscustomobject]@{ Code = $code; Out = $o; J = $j }
}
function Row($r, [string]$Member) {
  if ($null -eq $r.J -or $null -eq $r.J.pas_uses) { return $null }
  return @($r.J.pas_uses | Where-Object { $_.instance -eq 'pic1' -and $_.member -eq $Member }) | Select-Object -First 1
}
function Lines($row) { if ($null -eq $row) { return '<none>' }; return (@($row.lines) -join ',') }
function Show($row) { if ($null -eq $row) { return '<no row>' }; return ($row | ConvertTo-Json -Compress -Depth 4) }

$r = J @($db)
Check 'S0 dry run exits 0 and carries pas_uses[]' (($r.Code -eq 0) -and ($null -ne $r.J) -and ($null -ne $r.J.pas_uses)) $r.Out
$doOld = Row $r 'DoOld'
Check 'C1 POSITIVE CONTROL: the plain site pic1.DoOld(1) is on the DoOld row (line 20)' (@($doOld.lines) -contains 20) (Show $doOld)
Check 'W1 with pic1 do DoOld(2): the with-body line 22 is on the same row -- lines 20,22, unmapped, resolved' `
  (((Lines $doOld) -eq '20,22') -and ($doOld.status -eq 'unmapped') -and ($doOld.resolution -eq 'resolved')) (Show $doOld)
$mid = Row $r 'MidOnly'
Check 'W2 with pic1 do begin MidOnly: line 25, declared_in TOldMid, unmapped' `
  (((Lines $mid) -eq '25') -and ($mid.declared_in -eq 'TOldMid') -and ($mid.status -eq 'unmapped')) (Show $mid)
$cap = Row $r 'Caption'
Check 'W3 with pic1 do begin Caption := : line 26, status mapped (#link Caption <- Caption)' `
  (((Lines $cap) -eq '26') -and ($cap.status -eq 'mapped')) (Show $cap)
$tag = Row $r 'Tag'
Check 'R1 project --db only: pic1.Tag (TComponent, RTL) is member-not-found with an EMPTY kind, line 28' `
  (((Lines $tag) -eq '28') -and ($tag.resolution -eq 'member-not-found') -and ([string]::IsNullOrEmpty($tag.kind))) (Show $tag)
if ($LibDb) {
  $rl = J @($db, $LibDb)
  $tagL = Row $rl 'Tag'
  Check 'L1 + the platform library --db: pic1.Tag is same-name, property, declaring_unit System.Classes' `
    (($tagL.status -eq 'same-name') -and ($tagL.kind -eq 'property') -and ($tagL.declaring_unit -eq 'System.Classes')) (Show $tagL)
} else {
  Write-Host '[SKIP] L1 (pass -LibDb <library-Win64.sqlite> to classify the RTL member)'
}

Write-Host ''
if ($script:fail) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'PASS' -ForegroundColor Green; exit 0
} finally {
  if (Test-Path -LiteralPath $WorkDir) { Remove-Item -LiteralPath $WorkDir -Recurse -Force -ErrorAction SilentlyContinue }
}