<#
  run_convert_apply_only_type.ps1 -- convert-apply --only-type T1,T2 (wave 148 CV, the
  converter's C12 ask N5).

  --only-type takes BARE TYPE names: every instance of those #convert From types is
  converted, nested and inline objects included, so a form scope needs no name list and
  cannot go stale between the editor's .dfm read and the engine's splice. Case-
  insensitive. Exclusive with --only (exit 2). A type naming no #convert From type
  converts nothing (the same exit 1 "no convertible instances" as --only naming nothing, N3f) and is reported in only_unmatched[] (spelled as given). Capability
  info --json capabilities.only_type.

  Fixture is built here: two #convert blocks (TSrcBtn, TSrcLbl), a form with btnOne,
  btnTwo, lblOne and btnIn nested in a pnl, so the type filter is told apart from a
  name filter and from no filter (positive control: no filter converts all four).
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
  [string]$WorkDir = "C:\TEMP\draglint_convert_apply_only_type_$PID"
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
if (Test-Path $WorkDir) { Remove-Item -Recurse -Force $WorkDir }
New-Item -ItemType Directory $WorkDir -Force | Out-Null
function W([string]$n,[string]$t){ [IO.File]::WriteAllText((Join-Path $WorkDir $n), ($t -replace "`r?`n","`r`n"), [Text.Encoding]::ASCII) }
W 'LibT.pas' @'
unit LibT;

interface

uses
  Classes;

type
  TSrcBtn = class(TPersistent)
  private
    FCaption: string;
  published
    property Caption: string read FCaption write FCaption;
  end;

  TSrcLbl = class(TPersistent)
  private
    FCaption: string;
  published
    property Caption: string read FCaption write FCaption;
  end;

  TDstBtn = class(TSrcBtn);
  TDstLbl = class(TSrcLbl);

implementation

end.
'@
W 'TForm1.pas' @'
unit TForm1;

interface

uses
  Classes, LibT;

type
  TTForm1 = class(TComponent)
    btnOne: TSrcBtn;
    btnTwo: TSrcBtn;
    lblOne: TSrcLbl;
    btnIn: TSrcBtn;
  end;

implementation

{$R *.dfm}

end.
'@
W 'TForm1.dfm' @'
object TForm1: TTForm1
  object btnOne: TSrcBtn
    Caption = 'One'
  end
  object btnTwo: TSrcBtn
    Caption = 'Two'
  end
  object lblOne: TSrcLbl
    Caption = 'L'
  end
  object pnl: TComponent
    object btnIn: TSrcBtn
      Caption = 'In'
    end
  end
end
'@
W 'two.rules' @'
#convert TSrcBtn -> TDstBtn
#link Caption <- Caption
#convert TSrcLbl -> TDstLbl
#link Caption <- Caption
'@
$db = Join-Path $WorkDir 'fx.sqlite'
& $Exe index $WorkDir --db $db 2>&1 | Out-Null
Check 'V the fixture index was built' (Test-Path $db)
function P([string]$n) { return (Join-Path $WorkDir $n) }
function Apply([string[]]$Extra = @()) {
  $o = (& $Exe @(@('convert-apply', '--unit', (P 'TForm1.pas'), '--rules', (P 'two.rules'), '--db', $db, '--format', 'json') + $Extra) 2>&1) -join "`n"
  return [pscustomobject]@{ Code = $LASTEXITCODE; Out = $o }
}
function Json([string]$s) {
  $a = $s.IndexOf('{'); $b = $s.LastIndexOf('}')
  if ($a -lt 0 -or $b -le $a) { return $null }
  try { return ($s.Substring($a, $b - $a + 1) | ConvertFrom-Json) } catch { return $null }
}
function Arr($v) { return ((@($v) | ForEach-Object { [string]$_ }) -join ',') }

$r = Apply @(); $j = Json $r.Out
Check 'C0 control, no filter: exit 0, all four instances convert' (($r.Code -eq 0) -and ($null -ne $j) -and (@($j.converted).Count -eq 4)) $r.Out

$r = Apply @('--only-type', 'TSrcLbl'); $j = Json $r.Out
Check 'T1 --only-type TSrcLbl: exit 0, only lblOne converts' `
  (($r.Code -eq 0) -and ($null -ne $j) -and (@($j.converted).Count -eq 1) -and ($j.converted[0] -match 'lblOne') -and (@($j.only_unmatched).Count -eq 0)) $r.Out

$r = Apply @('--only-type', 'TSrcBtn'); $j = Json $r.Out
Check 'T2 --only-type TSrcBtn: exit 0, btnOne btnTwo and nested btnIn convert (3), no label' `
  (($r.Code -eq 0) -and ($null -ne $j) -and (@($j.converted).Count -eq 3) -and (@($j.converted | Where-Object { $_ -match 'lblOne' }).Count -eq 0) -and (@($j.converted | Where-Object { $_ -match 'btnIn' }).Count -eq 1)) $r.Out

$r = Apply @('--only-type', 'tsrclbl,TSrcBtn'); $j = Json $r.Out
Check 'T3 --only-type tsrclbl,TSrcBtn (case-insensitive, two types): all four convert' `
  (($r.Code -eq 0) -and ($null -ne $j) -and (@($j.converted).Count -eq 4)) $r.Out

$before = [IO.File]::ReadAllText((P 'TForm1.dfm'))
$r = Apply @('--only-type', 'TNoSuch'); $j = Json $r.Out
Check 'T4 --only-type TNoSuch: nothing converts (the zero-instance exit 1, as --only Nope), only_unmatched = [TNoSuch]' `
  (($r.Code -eq 1) -and ($null -ne $j) -and (@($j.converted).Count -eq 0) -and ((Arr $j.only_unmatched) -eq 'TNoSuch')) $r.Out
$r = Apply @('--only-type', 'TSrcLbl,TNoSuch'); $j = Json $r.Out
Check 'T5 --only-type TSrcLbl,TNoSuch: lblOne converts, only_unmatched = [TNoSuch]' `
  (($r.Code -eq 0) -and ($null -ne $j) -and (@($j.converted).Count -eq 1) -and ((Arr $j.only_unmatched) -eq 'TNoSuch')) $r.Out

$r = Apply @('--only-type', 'TSrcLbl', '--only', 'btnOne')
Check 'T6 --only-type with --only: exit 2' ($r.Code -eq 2) $r.Out

$j = Json ((& $Exe info --json 2>&1) -join "`n")
Check 'T7 info --json: capabilities.only_type is JSON true' `
  (($null -ne $j) -and ($j.capabilities.only_type -is [bool]) -and ($j.capabilities.only_type -eq $true))

$r = Apply @('--only-type', 'TSrcLbl', '--apply'); $j = Json $r.Out
$dfm = [IO.File]::ReadAllText((P 'TForm1.dfm'))
Check 'T8 --apply --only-type TSrcLbl: dfm has lblOne: TDstLbl and every TSrcBtn untouched' `
  (($r.Code -eq 0) -and ($dfm -match 'lblOne: TDstLbl') -and ($dfm -match 'btnOne: TSrcBtn') -and ($dfm -match 'btnIn: TSrcBtn') -and ($dfm -match 'btnTwo: TSrcBtn')) $dfm

Write-Host ''
if ($script:fail) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'PASS' -ForegroundColor Green; exit 0
} finally {
  foreach ($d23 in @("C:\TEMP\draglint_convert_apply_only_type_$PID")) { if (Test-Path -LiteralPath $d23) { Remove-Item -LiteralPath $d23 -Recurse -Force -ErrorAction SilentlyContinue } }
}
