<#
  run_convert_apply_descendants.ps1 -- convert-apply DESCENDANT WARNINGS
  (1.25.0, agreed with the converter team; ships before C8 N2).

  WHY: converting an ANCESTOR's `object X: TOld` to TNew leaves every
  descendant .dfm saying `inherited X: TOld` and every descendant's code
  untouched. VCL streaming then fails at load (EClassNotFound, or EReadError on
  an overridden property TNew lacks), and descendant code using TOld-only
  members no longer compiles. Until C8 N2 retypes them, the ancestor's run must
  SAY so. It is a WARNING: the unit is never refused because of it.

  THE CONTRACT this guard pins:
    * for each CONVERTED instance X, every descendant form / data-module class
      of the unit's root class (type_ancestors, transitively), and every form
      hosting that class as an `inline` frame, whose .dfm re-opens X
      (`inherited` / `inline`) or whose code references X, is reported:
        - text   'line N: warning: descendant <Unit> still streams <Name> as
                  <TOld> -- convert it next (needs C8 N2)', N = the line of X's
                  object block in the ANCESTOR .dfm;
        - apply/1 descendants[] {unit, name, type, line, reason}: line is the
                  descendant .dfm's inherited block, or the first code
                  reference when the .dfm does not re-open X; reason is
                  dfm | code | both;
        - items[] kind descendant-not-converted (field warnings).
    * a descendant re-opening only a DIFFERENT component is not reported;
    * a code use BOUND by the resolver (E5) to the ancestor field is reported
      (reason code); a descendant's OWN same-named field shadowing it is not;
    * an unrelated form with its own `object X`, or hosting an UNRELATED
      frame that re-opens a same-named X, is not reported;
    * --only filters descendants[] to the converted instances;
    * batch mode: each unit's apply/1 carries its own descendants[];
    * positive control: no descendants -> descendants[] = [] and no line;
    * info --json: capabilities.descendant_warnings is the JSON literal true.

  Fixture written fresh under a $PID scratch folder and indexed into a scratch
  --db there. Nothing shared is touched. Run from any CWD, pwsh 7.
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\drag-lint-convert-apply-descendants-$PID"
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

if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
$Exe = (Resolve-Path $Exe).Path
if (Test-Path $WorkDir) { Remove-Item -Recurse -Force $WorkDir }
New-Item -ItemType Directory $WorkDir | Out-Null

function Write-Ascii([string]$Path, [string]$Body) {
  $norm = $Body -replace "`r`n", "`n" -replace "`n", "`r`n"
  [System.IO.File]::WriteAllText($Path, $norm, [System.Text.Encoding]::ASCII)
}
function P([string]$n) { return (Join-Path $WorkDir $n) }

# ---- library types ---------------------------------------------------------
Write-Ascii (P 'LibA.pas') @'
unit LibA;

interface

uses
  Classes;

type
  TSrcA = class(TComponent)
  private
    FCaption: string;
  published
    property Caption: string read FCaption write FCaption;
  end;

  TBox = class(TComponent)
  end;

implementation

end.
'@
Write-Ascii (P 'LibB.pas') @'
unit LibB;

interface

uses
  Classes;

type
  TDstB = class(TComponent)
  private
    FCaption: string;
  published
    property Caption: string read FCaption write FCaption;
  end;

implementation

end.
'@

# ---- the ANCESTOR being converted ------------------------------------------
Write-Ascii (P 'AncForm.pas') @'
unit AncForm;

interface

uses
  Classes, Forms, LibA;

type
  TAncForm = class(TForm)
    btnX: TSrcA;
    btnY: TSrcA;
    pnl: TBox;
  end;

implementation

{$R *.dfm}

end.
'@
Write-Ascii (P 'AncForm.dfm') @'
object AncForm: TAncForm
  object btnX: TSrcA
    Caption = 'X'
  end
  object btnY: TSrcA
    Caption = 'Y'
  end
  object pnl: TBox
  end
end
'@

# ---- (1) a descendant re-opening btnX in its .dfm --------------------------
Write-Ascii (P 'Desc1.pas') @'
unit Desc1;

interface

uses
  Classes, Forms, LibA, AncForm;

type
  TDesc1 = class(TAncForm)
  end;

implementation

{$R *.dfm}

end.
'@
Write-Ascii (P 'Desc1.dfm') @'
inherited Desc1: TDesc1
  inherited btnX: TSrcA
    Caption = 'd1'
  end
end
'@

# ---- (2) a GRANDCHILD (two levels down), .dfm AND code ----------------------
Write-Ascii (P 'Grand.pas') @'
unit Grand;

interface

uses
  Classes, Forms, LibA, Desc1;

type
  TGrand = class(TDesc1)
    procedure Touch;
  end;

implementation

{$R *.dfm}

procedure TGrand.Touch;
begin
  btnX.Caption := 'g';
end;

end.
'@
Write-Ascii (P 'Grand.dfm') @'
inherited Grand: TGrand
  inherited btnX: TSrcA
    Caption = 'g'
  end
end
'@

# ---- (3) a descendant that uses btnX in CODE only ---------------------------
Write-Ascii (P 'CodeOnly.pas') @'
unit CodeOnly;

interface

uses
  Classes, Forms, LibA, AncForm;

type
  TCodeOnly = class(TAncForm)
    procedure Touch;
  end;

implementation

{$R *.dfm}

procedure TCodeOnly.Touch;
begin
  Tag := 1;
  btnX.Caption := 'c';
end;

end.
'@
Write-Ascii (P 'CodeOnly.dfm') @'
inherited CodeOnly: TCodeOnly
end
'@

# ---- (5) a descendant re-opening a DIFFERENT component (pnl) ----------------
Write-Ascii (P 'Other.pas') @'
unit Other;

interface

uses
  Classes, Forms, LibA, AncForm;

type
  TOther = class(TAncForm)
  end;

implementation

{$R *.dfm}

end.
'@
Write-Ascii (P 'Other.dfm') @'
inherited Other: TOther
  inherited pnl: TBox
  end
end
'@

# ---- (6) a descendant re-opening btnY only (for --only) ---------------------
Write-Ascii (P 'YForm.pas') @'
unit YForm;

interface

uses
  Classes, Forms, LibA, AncForm;

type
  TYForm = class(TAncForm)
  end;

implementation

{$R *.dfm}

end.
'@
Write-Ascii (P 'YForm.dfm') @'
inherited YForm: TYForm
  inherited btnY: TSrcA
    Caption = 'y2'
  end
end
'@

# ---- (4) an INLINE frame: FrameA is converted, HostForm hosts it ------------
Write-Ascii (P 'FrameA.pas') @'
unit FrameA;

interface

uses
  Classes, Forms, LibA;

type
  TFrameA = class(TFrame)
    fx: TSrcA;
  end;

implementation

{$R *.dfm}

end.
'@
Write-Ascii (P 'FrameA.dfm') @'
object FrameA: TFrameA
  object fx: TSrcA
    Caption = 'F'
  end
end
'@
Write-Ascii (P 'HostForm.pas') @'
unit HostForm;

interface

uses
  Classes, Forms, LibA, FrameA;

type
  THostForm = class(TForm)
    fr1: TFrameA;
  end;

implementation

{$R *.dfm}

end.
'@
Write-Ascii (P 'HostForm.dfm') @'
object HostForm: THostForm
  inline fr1: TFrameA
    inherited fx: TSrcA
      Caption = 'h'
    end
  end
end
'@

# ---- (8) a descendant whose OWN field btnX shadows the ancestor's ------------
Write-Ascii (P 'Shadow.pas') @'
unit Shadow;

interface

uses
  Classes, Forms, LibA, AncForm;

type
  TShadow = class(TAncForm)
    btnX: TSrcA;
    procedure Touch;
  end;

implementation

{$R *.dfm}

procedure TShadow.Touch;
begin
  btnX.Caption := 's';
end;

end.
'@
Write-Ascii (P 'Shadow.dfm') @'
inherited Shadow: TShadow
end
'@

# ---- (9) unrelated forms: an own `object btnX`, and an unrelated inline frame -
Write-Ascii (P 'Stranger.pas') @'
unit Stranger;

interface

uses
  Classes, Forms, LibA;

type
  TStranger = class(TForm)
    btnX: TSrcA;
  end;

implementation

{$R *.dfm}

end.
'@
Write-Ascii (P 'Stranger.dfm') @'
object Stranger: TStranger
  object btnX: TSrcA
    Caption = 'mine'
  end
end
'@
Write-Ascii (P 'ZFrame.pas') @'
unit ZFrame;

interface

uses
  Classes, Forms, LibA;

type
  TZFrame = class(TFrame)
    btnX: TSrcA;
  end;

implementation

{$R *.dfm}

end.
'@
Write-Ascii (P 'ZFrame.dfm') @'
object ZFrame: TZFrame
  object btnX: TSrcA
    Caption = 'z'
  end
end
'@
Write-Ascii (P 'ZHost.pas') @'
unit ZHost;

interface

uses
  Classes, Forms, LibA, ZFrame;

type
  TZHost = class(TForm)
    zf: TZFrame;
  end;

implementation

{$R *.dfm}

end.
'@
Write-Ascii (P 'ZHost.dfm') @'
object ZHost: TZHost
  inline zf: TZFrame
    inherited btnX: TSrcA
      Caption = 'zh'
    end
  end
end
'@

# ---- (10) a descendant method whose LOCAL btnX shadows the field ------------
Write-Ascii (P 'LocalUse.pas') @'
unit LocalUse;

interface

uses
  Classes, Forms, LibA, AncForm;

type
  TLocalUse = class(TAncForm)
    procedure Touch;
  end;

implementation

{$R *.dfm}

procedure TLocalUse.Touch;
var
  btnX: TSrcA;
begin
  btnX := nil;
  btnX.Caption := 'l';
end;

end.
'@
Write-Ascii (P 'LocalUse.dfm') @'
inherited LocalUse: TLocalUse
end
'@

# ---- (11) a DIFFERENT class that shares a descendant's NAME (TDesc1), hosted
#           inline by an unrelated form re-opening btnX: matched by symbol,
#           not by name, so not reported ---------------------------------------
Write-Ascii (P 'OtherDesc1.pas') @'
unit OtherDesc1;

interface

uses
  Classes, Forms, LibA;

type
  TDesc1 = class(TFrame)
    btnX: TSrcA;
  end;

implementation

{$R *.dfm}

end.
'@
Write-Ascii (P 'OtherDesc1.dfm') @'
object Desc1F: TDesc1
  object btnX: TSrcA
    Caption = 'od'
  end
end
'@
Write-Ascii (P 'TwinHost.pas') @'
unit TwinHost;

interface

uses
  Classes, Forms, LibA, OtherDesc1;

type
  TTwinHost = class(TForm)
    od: TDesc1;
  end;

implementation

{$R *.dfm}

end.
'@
Write-Ascii (P 'TwinHost.dfm') @'
object TwinHost: TTwinHost
  inline od: TDesc1
    inherited btnX: TSrcA
      Caption = 'th'
    end
  end
end
'@

# ---- (7) positive control: no descendants -----------------------------------
Write-Ascii (P 'Lonely.pas') @'
unit Lonely;

interface

uses
  Classes, Forms, LibA;

type
  TLonely = class(TForm)
    btnL: TSrcA;
  end;

implementation

{$R *.dfm}

end.
'@
Write-Ascii (P 'Lonely.dfm') @'
object Lonely: TLonely
  object btnL: TSrcA
    Caption = 'L'
  end
end
'@

Write-Ascii (P 'plain.rules') @'
#convert LibA.TSrcA -> LibB.TDstB, LibB
#link Caption <- Caption
'@

$db = P 'fx.sqlite'
$idx = & $Exe index $WorkDir --db $db 2>&1
Check 'V the fixture index was built' (($LASTEXITCODE -eq 0) -and (Test-Path $db)) "exit=$LASTEXITCODE; $($idx -join ' | ')"

# The btnX code refs and what the resolver bound them to (E5, resolver 1.12:
# a bare read of an in-class or ancestor field binds). sql --json rows are
# POSITIONAL arrays -- read them by column index.
$q = "select f.path, r.symbol_id, s.qualified_name from refs r join files f on f.id = r.file_id " +
     "left join symbols s on s.id = r.symbol_id where r.name_text = 'btnX' and f.path like '%.pas'"
$sq = (& $Exe sql --db $db --query $q --json 2>$null) -join "`n"
$sj = try { $sq | ConvertFrom-Json } catch { $null }
function BoundOf([string]$Unit) {
  if ($null -eq $sj) { return '<no sql>' }
  foreach ($row in @($sj.rows)) { if ((Split-Path $row[0] -Leaf) -eq "$Unit.pas") { return "$($row[1])|$($row[2])" } }
  return '<no ref>'
}
$bCode   = BoundOf 'CodeOnly'
$bShadow = BoundOf 'Shadow'
Check 'V2 CodeOnly''s btnX ref is BOUND by the resolver to the ANCESTOR field (symbol_id non-null)' `
  ($bCode -match '^\d+\|AncForm\.TAncForm\.btnX$') "$bCode -- $sq"
Check 'V3 Shadow''s btnX ref is BOUND to its OWN field, not the ancestor''s' `
  ($bShadow -match '^\d+\|Shadow\.TShadow\.btnX$') "$bShadow -- $sq"

function Run([string[]]$Units, [string[]]$Extra = @()) {
  $a = @()
  foreach ($u in $Units) { $a += @('--unit', (P $u)) }
  $o = (& $Exe convert-apply @a --rules (P 'plain.rules') --db $db @Extra 2>&1) -join "`n"
  return [pscustomobject]@{ Code = $LASTEXITCODE; Out = $o }
}
function Json([string]$s) {
  $a = $s.IndexOf('{'); $b = $s.LastIndexOf('}')
  if ($a -lt 0 -or $b -le $a) { return $null }
  try { return ($s.Substring($a, $b - $a + 1) | ConvertFrom-Json) } catch { return $null }
}
function LineOf([string]$File, [string]$Needle) {
  $ls = [IO.File]::ReadAllLines((P $File))
  for ($i = 0; $i -lt $ls.Count; $i++) { if ($ls[$i].Trim() -eq $Needle) { return $i + 1 } }
  return -1
}
function Desc($j, [string]$Unit, [string]$Name) {
  return @($j.descendants | Where-Object { $_.unit -eq $Unit -and $_.name -eq $Name })
}

$ancX  = LineOf 'AncForm.dfm' 'object btnX: TSrcA'
$ancY  = LineOf 'AncForm.dfm' 'object btnY: TSrcA'
$d1X   = LineOf 'Desc1.dfm' 'inherited btnX: TSrcA'
$grX   = LineOf 'Grand.dfm' 'inherited btnX: TSrcA'
$coX   = LineOf 'CodeOnly.pas' "btnX.Caption := 'c';"
$yfY   = LineOf 'YForm.dfm' 'inherited btnY: TSrcA'
$frX   = LineOf 'FrameA.dfm' 'object fx: TSrcA'
$hoX   = LineOf 'HostForm.dfm' 'inherited fx: TSrcA'

# ---- AncForm, dry run, JSON --------------------------------------------------
$r = Run @('AncForm.pas') @('--format', 'json')
$j = Json $r.Out
Check 'A1 AncForm dry run: exit 0, ok, not refused, btnX and btnY converted' `
  (($r.Code -eq 0) -and ($null -ne $j) -and $j.ok -and ($j.refused -eq $false) -and (@($j.converted).Count -eq 2)) $r.Out
Check 'A2 descendants[] holds exactly Desc1/btnX, Grand/btnX, CodeOnly/btnX, YForm/btnY' `
  (($null -ne $j) -and (@($j.descendants).Count -eq 4) -and ((Desc $j 'Desc1' 'btnX').Count -eq 1) -and `
   ((Desc $j 'Grand' 'btnX').Count -eq 1) -and ((Desc $j 'CodeOnly' 'btnX').Count -eq 1) -and ((Desc $j 'YForm' 'btnY').Count -eq 1)) `
  ($j.descendants | ConvertTo-Json -Compress)
$keys = if ($j -and @($j.descendants).Count -gt 0) { (@($j.descendants)[0].PSObject.Properties.Name) -join ',' } else { '' }
Check 'A3 each descendants[] object has exactly the keys unit,name,type,line,reason' ($keys -eq 'unit,name,type,line,reason') $keys
$d = Desc $j 'Desc1' 'btnX'
Check 'A4 (1) Desc1 re-opens btnX in its .dfm: type TSrcA, line = its inherited block, reason dfm' `
  (($d.Count -eq 1) -and ($d[0].type -eq 'TSrcA') -and ($d[0].line -eq $d1X) -and ($d[0].reason -eq 'dfm')) ($d | ConvertTo-Json -Compress)
$d = Desc $j 'Grand' 'btnX'
Check 'A5 (2) grandchild Grand (two levels): .dfm line, reason both (it also uses btnX in code)' `
  (($d.Count -eq 1) -and ($d[0].line -eq $grX) -and ($d[0].reason -eq 'both')) ($d | ConvertTo-Json -Compress)
$d = Desc $j 'CodeOnly' 'btnX'
Check 'A6 (3) CodeOnly uses btnX in code only: line = first code reference, reason code' `
  (($d.Count -eq 1) -and ($d[0].line -eq $coX) -and ($d[0].reason -eq 'code')) ($d | ConvertTo-Json -Compress)
Check 'A7 (5) Other re-opens a DIFFERENT component (pnl): not reported' `
  (($null -ne $j) -and (@($j.descendants | Where-Object { $_.unit -eq 'Other' }).Count -eq 0)) ($j.descendants | ConvertTo-Json -Compress)
Check 'A7b (8) Shadow declares its OWN btnX and uses it: not reported' `
  (($null -ne $j) -and (@($j.descendants | Where-Object { $_.unit -eq 'Shadow' }).Count -eq 0)) ($j.descendants | ConvertTo-Json -Compress)
Check 'A7c (9) unrelated forms -- Stranger (own object btnX) and ZHost (inline TZFrame re-opening btnX) -- not reported' `
  (($null -ne $j) -and (@($j.descendants | Where-Object { $_.unit -in @('Stranger', 'ZHost', 'ZFrame') }).Count -eq 0)) ($j.descendants | ConvertTo-Json -Compress)
Check 'A7d (10) LocalUse reads and writes a LOCAL btnX: not reported' `
  (($null -ne $j) -and (@($j.descendants | Where-Object { $_.unit -eq 'LocalUse' }).Count -eq 0)) ($j.descendants | ConvertTo-Json -Compress)
Check 'A7e (11) TwinHost hosts an UNRELATED class named TDesc1 inline and re-opens btnX: not reported (owner matched by symbol)' `
  (($null -ne $j) -and (@($j.descendants | Where-Object { $_.unit -in @('TwinHost', 'OtherDesc1') }).Count -eq 0)) ($j.descendants | ConvertTo-Json -Compress)
$w = @($j.warnings | Where-Object { $_ -match '^line \d+: warning: descendant ' })
Check 'A8 warnings[] has the agreed text, N = the ANCESTOR .dfm line of the object block' `
  (($w.Count -eq 4) -and ($w -contains "line $ancX`: warning: descendant Desc1 still streams btnX as TSrcA -- convert it next (needs C8 N2)") -and `
   ($w -contains "line $ancY`: warning: descendant YForm still streams btnY as TSrcA -- convert it next (needs C8 N2)")) ($w -join ' | ')
$ik = @($j.items | Where-Object { $_.kind -eq 'descendant-not-converted' })
Check 'A9 items[] mirrors them as kind descendant-not-converted (field warnings, instance named)' `
  (($ik.Count -eq 4) -and (@($ik | Where-Object { $_.field -ne 'warnings' }).Count -eq 0) -and (@($ik | Where-Object { $_.instance -eq 'btnY' }).Count -eq 1)) ($ik | ConvertTo-Json -Compress)
$sum = @($j.converted).Count + @($j.access_sites).Count + @($j.creator_sites).Count + @($j.todos).Count + @($j.reemit_notes).Count + @($j.warnings).Count
Check 'A10 invariant: items.length = sum of the six arrays' (($null -ne $j) -and (@($j.items).Count -eq $sum)) "items=$(@($j.items).Count) sum=$sum"

# ---- text mode -------------------------------------------------------------
$r = Run @('AncForm.pas')
Check 'B1 text mode: exit 0, the Desc1 warning line printed' `
  (($r.Code -eq 0) -and ($r.Out -match "(?m)^\s*line $ancX`: warning: descendant Desc1 still streams btnX as TSrcA -- convert it next \(needs C8 N2\)")) $r.Out

# ---- (6) --only filters descendants[] --------------------------------------
$r = Run @('AncForm.pas') @('--only', 'btnX', '--format', 'json')
$j = Json $r.Out
Check 'C1 --only btnX: exit 0, YForm/btnY EXCLUDED, the three btnX descendants kept' `
  (($r.Code -eq 0) -and ($null -ne $j) -and (@($j.descendants).Count -eq 3) -and (@($j.descendants | Where-Object { $_.name -ne 'btnX' }).Count -eq 0)) `
  ($j.descendants | ConvertTo-Json -Compress)
$r = Run @('AncForm.pas') @('--only', 'btnY', '--format', 'json')
$j = Json $r.Out
Check 'C2 --only btnY: only YForm/btnY, at its .dfm line' `
  (($r.Code -eq 0) -and ($null -ne $j) -and (@($j.descendants).Count -eq 1) -and ((Desc $j 'YForm' 'btnY').Count -eq 1) -and `
   ((Desc $j 'YForm' 'btnY')[0].line -eq $yfY)) ($j.descendants | ConvertTo-Json -Compress)

# ---- (4) an inline frame ----------------------------------------------------
$r = Run @('FrameA.pas') @('--format', 'json')
$j = Json $r.Out
$d = if ($j) { Desc $j 'HostForm' 'fx' } else { @() }
Check 'D1 FrameA: HostForm hosts it inline and re-opens fx -- reported, its .dfm line, reason dfm' `
  (($r.Code -eq 0) -and ($d.Count -eq 1) -and ($d[0].line -eq $hoX) -and ($d[0].reason -eq 'dfm') -and (@($j.descendants).Count -eq 1)) $r.Out
Check 'D2 its warning line names the frame .dfm line' `
  (($null -ne $j) -and (@($j.warnings) -contains "line $frX`: warning: descendant HostForm still streams fx as TSrcA -- convert it next (needs C8 N2)")) ($j.warnings -join ' | ')

# ---- (7) positive control: no descendants -----------------------------------
$r = Run @('Lonely.pas') @('--format', 'json')
$j = Json $r.Out
Check 'E1 Lonely: exit 0, btnL converted, descendants[] PRESENT and empty, no descendant warning/item' `
  (($r.Code -eq 0) -and ($null -ne $j) -and (@($j.converted).Count -eq 1) -and ($j.PSObject.Properties.Name -contains 'descendants') -and `
   (@($j.descendants).Count -eq 0) -and (@($j.warnings | Where-Object { $_ -match 'descendant' }).Count -eq 0) -and `
   (@($j.items | Where-Object { $_.kind -eq 'descendant-not-converted' }).Count -eq 0)) $r.Out
$r = Run @('Lonely.pas')
Check 'E2 Lonely text mode: no descendant line' (($r.Code -eq 0) -and -not ($r.Out -match 'warning: descendant')) $r.Out

# ---- batch: each unit carries its own descendants[] -------------------------
$r = Run @('AncForm.pas', 'FrameA.pas', 'Lonely.pas') @('--format', 'json')
$j = Json $r.Out
$u = if ($j) { @($j.units) } else { @() }
Check 'F1 batch: apply-batch/1, three units, descendants[] per unit = 4 / 1 / 0' `
  (($r.Code -eq 0) -and ($null -ne $j) -and ($j.schema -eq 'apply-batch/1') -and ($u.Count -eq 3) -and `
   (@($u[0].descendants).Count -eq 4) -and (@($u[1].descendants).Count -eq 1) -and (@($u[1].descendants)[0].unit -eq 'HostForm') -and `
   ($u[2].PSObject.Properties.Name -contains 'descendants') -and (@($u[2].descendants).Count -eq 0)) $r.Out

# ---- --apply: still a warning, never a refusal ------------------------------
$r = Run @('AncForm.pas') @('--apply', '--no-backup', '--format', 'json')
$j = Json $r.Out
Check 'G1 --apply: exit 0, ok, AncForm.dfm converted, descendants[] still 4' `
  (($r.Code -eq 0) -and ($null -ne $j) -and $j.ok -and ($j.refused -eq $false) -and (@($j.descendants).Count -eq 4) -and `
   ([IO.File]::ReadAllText((P 'AncForm.dfm')) -match 'object btnX: TDstB')) $r.Out
Check 'G2 descendants are NOT edited (Desc1.dfm still streams btnX as TSrcA)' `
  ([IO.File]::ReadAllText((P 'Desc1.dfm')) -match 'inherited btnX: TSrcA')

# ---- the capability --------------------------------------------------------
$o = (& $Exe info --json 2>$null) -join "`n"
$ij = Json $o
Check 'H1 info --json: capabilities.descendant_warnings is the JSON literal true' `
  (($null -ne $ij) -and ($ij.capabilities.descendant_warnings -is [bool]) -and ($ij.capabilities.descendant_warnings -eq $true)) $o

# ---- 1.25.2: the STANDING LOAD GUARD -- every .dfm this suite's --apply wrote
# goes through Delphi's own reader (lib\DfmLoadCheck.ps1). A dry run proves the
# PLAN, never the BYTES.
. (Join-Path $PSScriptRoot 'lib\DfmLoadCheck.ps1')
$loadFails = Test-DfmLoads @((P 'AncForm.dfm'))
Check 'LOAD1 every .dfm --apply wrote LOADS (text -> binary -> text -> binary)' ($loadFails.Count -eq 0) ($loadFails -join ' | ')
Write-Host ''
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
} finally {
  foreach ($d23 in @("$env:TEMP\drag-lint-convert-apply-descendants-$PID")) { if (Test-Path -LiteralPath $d23) { Remove-Item -LiteralPath $d23 -Recurse -Force -ErrorAction SilentlyContinue } }
}
