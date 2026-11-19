<#
run_v152_BK-COLS2.ps1 -- 1.52 BK-COLS2 (backlog B40, B41, B45): lint findings, the DFM index and
check-init report CHARACTER (UTF-16) columns, never tree-sitter's UTF-8 BYTE columns.

Every fixture line under test carries `{~~~}` (three e-acute: three characters, six UTF-8 bytes)
BEFORE the construct, so a byte column lands 3 to the right of the character column. Each such line
has an ASCII twin (the positive control: its column must not move).

  C  B40 lint columns: AST rules (unused-local, raise-in-finally, with-statement, flow,
     multiple-statements-per-line), .scm query rules (empty-except, deprecated-rtl-function).
     The file is checked twice: BOM-less Windows-1252 and BOM-less UTF-8.
  F  B40 fixers read the finding's column on the decoded line: deprecated-rtl-function rewrites
     StrPas, multiple-statements-per-line splits the line -- on the non-ASCII line too.
  D  B41 the DFM index: string_literals dfm-type / dfm-prop columns after a non-ASCII object name
     and inside a non-ASCII string.
  H  B45 check-init: a read after non-ASCII text reports its character column; `@GCfg` after
     non-ASCII text in a UTF-8 .dpr is still an address-of writer (positive controls: the solver
     takes index columns, which EXTGAPS2 made characters).

Usage: pwsh -File tests/autotest/run_v152_BK-COLS2.ps1 [-Exe <path>]
#>
[CmdletBinding()]
param(
  [string]$Exe     = '',
  [string]$WorkDir = "$env:TEMP\drag-lint-v152-bkcols2-$PID"
)
# Defaults that need the script path are resolved HERE, not in param(): Windows PowerShell 5 run with
# -File leaves $PSScriptRoot/$MyInvocation empty inside an advanced script's param block (Repo became C:\).
if (-not $Exe) { $Exe = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe" }
$ErrorActionPreference = 'Stop'
$script:Pass = 0; $script:Fail = 0
function Check([string]$Name, [bool]$Ok, [string]$Detail = '') {
  if ($Ok) { $script:Pass++; Write-Host "  [PASS] $Name" -ForegroundColor Green }
  else     { $script:Fail++; Write-Host "  [FAIL] $Name  $Detail" -ForegroundColor Red }
}
$Cp1252 = [System.Text.Encoding]::GetEncoding(1252)
$Utf8   = New-Object System.Text.UTF8Encoding($false)
$Eacute = [string][char]0xE9
function WriteText([string]$Path, [string]$Text, $Enc) {
  [IO.File]::WriteAllBytes($Path, $Enc.GetBytes(($Text -replace "`r?`n", "`r`n").Replace('~', $Eacute)))
}
function ReadLines([string]$Path) { return ,($Cp1252.GetString([IO.File]::ReadAllBytes($Path)) -split "`r`n") }

if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
$Exe = (Resolve-Path $Exe).Path
if (Test-Path $WorkDir) { [IO.Directory]::Delete($WorkDir, $true) }
New-Item -ItemType Directory $WorkDir | Out-Null

$Unit = @'
unit uBk;

interface

procedure P1;
procedure P2(const S: string);

implementation

uses SysUtils, Windows;

var
  GCount: Integer;
  GTotal: Integer;

procedure P1;
var
  {~~~} Unused1: Integer;
  Unused2: Integer;
  L: TStringList;
begin
  try
  finally
    {~~~} raise Exception.Create('x');
  end;
  try
  finally
    raise Exception.Create('y');
  end;
  {~~~} with L do Clear;
  with L do Clear;
  {~~~} L.Free; L.Clear;
  L.Free; L.Clear;
  try {~~~} except end;
  try except end;
end;

procedure P2(const S: string);
begin
  {~~~} if S = '' then Exit; Writeln(StrPas(PChar(S)));
  if S = '' then Exit; Writeln(StrPas(PChar(S)));
end;

end.
'@

# ---------------------------------------------------------------- C: lint columns
# line, rule, expected start col, expected end col (0 = not asserted); the ASCII twins are the controls
$Cases = @(
  @{ L = 18; R = 'unused-local';                 S = 9;  E = 16 }, @{ L = 19; R = 'unused-local';                 S = 3;  E = 10 },
  @{ L = 24; R = 'raise-in-finally';             S = 11; E = 16 }, @{ L = 28; R = 'raise-in-finally';             S = 5;  E = 10 },
  @{ L = 30; R = 'with-statement';               S = 9;  E = 25 }, @{ L = 31; R = 'with-statement';               S = 3;  E = 19 },
  @{ L = 30; R = 'used-before-assignment';       S = 14; E = 0  }, @{ L = 31; R = 'used-before-assignment';       S = 8;  E = 0  },
  @{ L = 32; R = 'multiple-statements-per-line'; S = 17; E = 25 }, @{ L = 33; R = 'multiple-statements-per-line'; S = 11; E = 19 },
  @{ L = 34; R = 'empty-except';                 S = 13; E = 19 }, @{ L = 35; R = 'empty-except';                 S = 7;  E = 13 },
  @{ L = 40; R = 'deprecated-rtl-function';      S = 38; E = 54 }, @{ L = 41; R = 'deprecated-rtl-function';      S = 32; E = 48 }
)
foreach ($enc in @(@{ N = 'cp1252'; E = $Cp1252 }, @{ N = 'utf8'; E = $Utf8 })) {
  Write-Host "== C ($($enc.N)): lint finding columns are characters" -ForegroundColor Cyan
  $d = Join-Path $WorkDir "c-$($enc.N)"; New-Item -ItemType Directory $d | Out-Null
  $f = Join-Path $d 'uBk.pas'; WriteText $f $Unit $enc.E
  $db = Join-Path $d 'c.sqlite'
  & { $ErrorActionPreference = 'Continue'; & $Exe index $d --db $db 2>&1 | ForEach-Object { "$_" } } | Out-Null
  $raw = & { $ErrorActionPreference = 'Continue'; & $Exe lint $f --db $db --enable magic-literal,multiple-statements-per-line,commented-out-code --json 2>$null } | Out-String
  $all = @(); try { $all = @(($raw | ConvertFrom-Json | ForEach-Object { $_ }) | ForEach-Object { $_ }) } catch { $all = @() }
  Check "C0 ($($enc.N)): lint --json answered" ($all.Count -ge 10) "count=$($all.Count)"
  foreach ($c in $Cases) {
    $hit = @($all | Where-Object { ([int]$_.start_line -eq $c.L) -and ($_.rule -eq $c.R) })
    $got = if ($hit.Count -gt 0) { "$($hit[0].start_col)-$($hit[0].end_col)" } else { 'none' }
    $ok = ($hit.Count -gt 0) -and ([int]$hit[0].start_col -eq $c.S) -and (($c.E -eq 0) -or ([int]$hit[0].end_col -eq $c.E))
    $want = if ($c.E -eq 0) { "$($c.S)" } else { "$($c.S)-$($c.E)" }
    Check "C ($($enc.N)) $($c.R) line $($c.L) at $want" $ok "got $got"
  }
}

# ---------------------------------------------------------------- F: fixers
Write-Host '== F: fixers edit at the character column' -ForegroundColor Cyan
foreach ($fx in @(
    @{ R = 'deprecated-rtl-function';      Ok = { param($ls) ($ls[39] -like '*Writeln(string(PChar(S)));') -and ($ls[40] -like '*Writeln(string(PChar(S)));') } },
    @{ R = 'multiple-statements-per-line'; Ok = { param($ls) (@($ls | Where-Object { $_ -match '^\s*L\.Clear;$' }).Count -eq 2) -and (@($ls | Where-Object { $_ -match '^\s*Writeln\(StrPas' }).Count -eq 2) } })) {
  $d = Join-Path $WorkDir "f-$($fx.R)"; New-Item -ItemType Directory $d | Out-Null
  $f = Join-Path $d 'uBk.pas'; WriteText $f $Unit $Cp1252
  $db = Join-Path $d 'f.sqlite'
  & { $ErrorActionPreference = 'Continue'; & $Exe index $d --db $db 2>&1 | ForEach-Object { "$_" } } | Out-Null
  $o = & { $ErrorActionPreference = 'Continue'; & $Exe lint-all --db $db --rule $fx.R --enable $fx.R --fix --apply --no-compile-gate --quiet 2>&1 | ForEach-Object { "$_" } } | Out-String
  $ls = ReadLines $f
  Check "F $($fx.R): the non-ASCII line and its ASCII twin are both fixed" (& $fx.Ok $ls) (($ls[31..42] -join ' | ') + " :: $($o.Trim())")
  Check "F $($fx.R): the non-ASCII text survives" (@($ls | Where-Object { $_.Contains("{$Eacute$Eacute$Eacute}") }).Count -eq 6) "lines with the marker: $(@($ls | Where-Object { $_.Contains($Eacute) }).Count)"
}

# ---------------------------------------------------------------- D: DFM index columns
Write-Host '== D: DFM index columns are characters' -ForegroundColor Cyan
$dD = Join-Path $WorkDir 'dfm'; New-Item -ItemType Directory $dD | Out-Null
WriteText (Join-Path $dD 'uFrm.pas') @'
unit uFrm;

interface

uses Classes, Controls, StdCtrls, Forms;

type
  TFrm = class(TForm)
    L~~~bel1: TLabel;
    Btn1: TButton;
    procedure Btn1Click(Sender: TObject);
  end;

implementation

{$R *.dfm}

procedure TFrm.Btn1Click(Sender: TObject);
begin
end;

end.
'@ $Cp1252
WriteText (Join-Path $dD 'uFrm.dfm') @'
object Frm: TFrm
  Caption = 'x'
  object L~~~bel1: TLabel
    Caption = '~~~'
  end
  object Btn1: TButton
    Caption = 'B'
    OnClick = Btn1Click
  end
end
'@ $Cp1252
$dbD = Join-Path $dD 'd.sqlite'
& { $ErrorActionPreference = 'Continue'; & $Exe index $dD --db $dbD 2>&1 | ForEach-Object { "$_" } } | Out-Null
$q = "SELECT l.kind, l.text, l.start_line, l.start_col, l.end_col FROM string_literals l JOIN files f ON f.id = l.file_id WHERE f.path LIKE '%.dfm' ORDER BY l.start_line"
$rawD = & { $ErrorActionPreference = 'Continue'; & $Exe sql --db $dbD --query $q --json 2>$null } | Out-String
$rowsD = @(); try { $jD = $rawD | ConvertFrom-Json | ForEach-Object { $_ }; $rowsD = @($jD.rows) } catch { $rowsD = @() }
function DRow([int]$Line, [string]$Kind) { return ,@($rowsD | Where-Object { ([int]$_[2] -eq $Line) -and ($_[0] -eq $Kind) }) }
foreach ($c in @(
    @{ L = 3; K = 'dfm-type'; S = 20; E = 26; W = 'TLabel after the non-ASCII object name' },
    @{ L = 4; K = 'dfm-prop'; S = 15; E = 20; W = 'non-ASCII string value ends at its character column' },
    @{ L = 6; K = 'dfm-type'; S = 16; E = 23; W = 'control: TButton on an ASCII line' })) {
  $r = DRow $c.L $c.K
  $got = if ($r.Count -gt 0) { "$($r[0][3])-$($r[0][4])" } else { "none (rows=$($rowsD.Count))" }
  Check "D line $($c.L) $($c.K) at $($c.S)-$($c.E): $($c.W)" (($r.Count -gt 0) -and ([int]$r[0][3] -eq $c.S) -and ([int]$r[0][4] -eq $c.E)) "got $got"
}

# ---------------------------------------------------------------- H: check-init
Write-Host '== H: check-init sites are character columns (positive controls)' -ForegroundColor Cyan
$fxH = Join-Path $PSScriptRoot '..\fixtures\happens-before\handlers-order'
$dH = Join-Path $WorkDir 'hb'; New-Item -ItemType Directory $dH | Out-Null
Copy-Item (Join-Path $fxH '*') $dH -Force
$dpr = Join-Path $dH 'HandlersOrder.dpr'
$t = [IO.File]::ReadAllText($dpr).Replace("begin`r`n  Application.Initialize;", "var`r`n  PCfg: Pointer;`r`n`r`nbegin`r`n  {~~~} PCfg:= @GCfg;`r`n  Application.Initialize;")
WriteText $dpr $t $Utf8
$main = Join-Path $dH 'hoMain.pas'
$mt = $Cp1252.GetString([IO.File]::ReadAllBytes($main)).Replace('  Tag:= GCfg;  // USE-CLICK', '  {~~~} Tag:= GCfg;  // USE-CLICK')
WriteText $main $mt $Cp1252
$dbH = Join-Path $dH 'h.sqlite'
& { $ErrorActionPreference = 'Continue'; & $Exe index $dH --db $dbH 2>&1 | ForEach-Object { "$_" } } | Out-Null
$rawH = & { $ErrorActionPreference = 'Continue'; & $Exe check-init hoData.GCfg --db $dbH --json 2>$null } | Out-String
$jH = $null; try { $jH = $rawH | ConvertFrom-Json | ForEach-Object { $_ } } catch { $jH = $null }
$useLine = [Array]::IndexOf((ReadLines $main), "  {$Eacute$Eacute$Eacute} Tag:= GCfg;  // USE-CLICK") + 1
$u = @(@($jH.uses) | Where-Object { ((Split-Path $_.file -Leaf) -eq 'hoMain.pas') -and ([int]$_.line -eq $useLine) })
Check "H1 the read after non-ASCII text (hoMain.pas:$useLine) is at character column 15" (($u.Count -eq 1) -and ([int]$u[0].col -eq 15)) "got $(if ($u.Count) { $u[0].col } else { 'none' })"
$w = @(@($jH.writers) | Where-Object { ((Split-Path $_.file -Leaf) -eq 'HandlersOrder.dpr') -and ($_.how -eq 'address-of') })
Check 'H2 @GCfg after non-ASCII text in a UTF-8 .dpr is an address-of writer at character column 17' (($w.Count -eq 1) -and ([int]$w[0].col -eq 17)) "got $(if ($w.Count) { "$($w[0].line):$($w[0].col)" } else { 'none' })"

Write-Host ''
Write-Host "v152 BK-COLS2: $script:Pass pass, $script:Fail fail" -ForegroundColor $(if ($script:Fail) { 'Red' } else { 'Green' })
if (Test-Path $WorkDir) { try { [IO.Directory]::Delete($WorkDir, $true) } catch { } }
exit $(if ($script:Fail) { 1 } else { 0 })
