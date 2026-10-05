<#
  run_convert_apply_stale_dfm.ps1 -- convert-apply refuses to splice a re-emitted
  object over .dfm lines that no longer hold the instance (1.20.6-alpha, Task 6).

  THE DEFECT: the .dfm span [StartLine..EndLine] comes from the INDEX. If the
  .dfm gained or lost a line after indexing, the splice would delete and replace
  the wrong lines and write a corrupt form.

  THE CONTRACT this guard pins:
    S  a line added ABOVE the instance after indexing: exit 1, REFUSED text line,
       json refused=true with reason "<name>: index is stale for this .dfm -- reindex",
       the .pas and .dfm byte-identical (--apply and dry run).
    N  a line added INSIDE the instance block (opener still on StartLine, the
       closing end no longer on EndLine): refused the same way.
    F  control: a fresh index converts, refused=false, and the .dfm changes.
    L  (fix wave) a block that LOST lines after indexing, so its recorded end
       line now holds the NEXT SIBLING's `end` at the same indent: refused (the
       old check accepted it and the splice deleted the sibling).
    T  (fix wave) the .dfm cut short after indexing, so the recorded span runs
       past its end: refused with the same reason (it used to skip the instance
       and convert the rest of the unit).
    B  (fix wave) btn1 vs btn10: the opener match is exact, not a prefix -- with
       the two blocks swapped after indexing, btn1's recorded line holds
       `object btn10:` and --only btn1 is refused, never spliced over btn10.

  Fixture written fresh under a $PID scratch folder with its own --db. Nothing
  shared is touched. Run from any CWD, pwsh 7.
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\drag-lint-convert-apply-stale-dfm-$PID"
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

$LibSrc = @'
unit LibAB;

interface

uses
  Classes;

type
  TSrcA = class(TPersistent)
  private
    FCaption: string;
    FHint: string;
    FTag: Integer;
  published
    property Caption: string read FCaption write FCaption;
    property Hint: string read FHint write FHint;
    property Tag: Integer read FTag write FTag;
  end;

  TDstB = class(TPersistent)
  private
    FCaption: string;
    FHint: string;
    FTag: Integer;
  published
    property Caption: string read FCaption write FCaption;
    property Hint: string read FHint write FHint;
    property Tag: Integer read FTag write FTag;
  end;

implementation

end.
'@
$FrmPas = @'
unit Frm;

interface

uses
  Classes, Forms, LibAB;

type
  TFrm = class(TForm)
    btn1: TSrcA;
  end;

implementation

{$R *.dfm}

end.
'@
$FrmDfm = @'
object Frm: TFrm
  object btn1: TSrcA
    Caption = 'Hi'
  end
end
'@
$Rules = @'
#convert LibAB.TSrcA -> LibAB.TDstB, LibAB
#link Caption <- Caption
'@
$Reason = 'btn1: index is stale for this .dfm -- reindex'

function NewFixture([string]$Sub, [string]$Pas = $FrmPas, [string]$Dfm = $FrmDfm) {
  $d = Join-Path $WorkDir $Sub
  New-Item -ItemType Directory $d | Out-Null
  Write-Ascii (Join-Path $d 'LibAB.pas') $LibSrc
  Write-Ascii (Join-Path $d 'Frm.pas') $Pas
  Write-Ascii (Join-Path $d 'Frm.dfm') $Dfm
  Write-Ascii (Join-Path $d 'b.rules') $Rules
  $db = Join-Path $d 'fx.sqlite'
  $idx = & $Exe index $d --db $db 2>&1
  if (($LASTEXITCODE -ne 0) -or -not (Test-Path $db)) { Check "V $Sub fixture index built" $false ($idx -join ' | ') }
  return $d
}
function Run([string]$Dir, [string[]]$Extra) {
  $o = (& $Exe convert-apply --unit (Join-Path $Dir 'Frm.pas') --rules (Join-Path $Dir 'b.rules') --db (Join-Path $Dir 'fx.sqlite') @Extra 2>&1) -join "`n"
  return [pscustomobject]@{ Code = $LASTEXITCODE; Out = $o }
}
function Json([string]$s) {
  $a = $s.IndexOf('{'); $b = $s.LastIndexOf('}')
  if ($a -lt 0 -or $b -le $a) { return $null }
  try { return ($s.Substring($a, $b - $a + 1) | ConvertFrom-Json) } catch { return $null }
}
function Hashes([string]$Dir) { return ((Get-FileHash (Join-Path $Dir 'Frm.pas')).Hash + (Get-FileHash (Join-Path $Dir 'Frm.dfm')).Hash) }

function CheckRefusal([string]$Tag, [string]$Dir, [string]$Why = $Reason, [string[]]$Only = @()) {
  $h = Hashes $Dir
  $r = Run $Dir (@('--apply', '--no-backup') + $Only)
  Check "$Tag`1 text --apply: exit 1, one 'REFUSED: <reason>' line, no ERROR: line" `
    (($r.Code -eq 1) -and (@($r.Out -split "`n" | Where-Object { $_ -match '^REFUSED: ' }).Count -eq 1) -and `
     ($r.Out -match ('(?m)^REFUSED: ' + [regex]::Escape($Why) + '\r?$')) -and -not ($r.Out -match '(?m)^ERROR:')) $r.Out
  $r = Run $Dir (@('--apply', '--no-backup', '--format', 'json') + $Only)
  $j = Json $r.Out
  Check "$Tag`2 json --apply: exit 1, ok=false, refused=true, reason matches" `
    (($r.Code -eq 1) -and ($null -ne $j) -and (-not $j.ok) -and ($j.refused -is [bool]) -and ($j.refused -eq $true) -and ($j.reason -eq $Why)) $r.Out
  Check "$Tag`3 .pas and .dfm byte-identical" ((Hashes $Dir) -eq $h)
  $r = Run $Dir (@('--format', 'json') + $Only)
  $j = Json $r.Out
  Check "$Tag`4 json dry run is refused too" (($r.Code -eq 1) -and ($null -ne $j) -and ($j.refused -eq $true)) $r.Out
}

# ---- S: a line added ABOVE the instance after indexing ----------------------
$d = NewFixture 's'
$dfm = Join-Path $d 'Frm.dfm'
$t = [IO.File]::ReadAllText($dfm).Replace("object Frm: TFrm`r`n", "object Frm: TFrm`r`n  Left = 1`r`n")
[IO.File]::WriteAllText($dfm, $t, [Text.Encoding]::ASCII)
CheckRefusal 'S' $d

# ---- N: a line added INSIDE the instance block -------------------------------
$d = NewFixture 'n'
$dfm = Join-Path $d 'Frm.dfm'
$t = [IO.File]::ReadAllText($dfm).Replace("  object btn1: TSrcA`r`n", "  object btn1: TSrcA`r`n    Tag = 1`r`n")
[IO.File]::WriteAllText($dfm, $t, [Text.Encoding]::ASCII)
CheckRefusal 'N' $d

# ---- F: control -- fresh index still converts --------------------------------
$d = NewFixture 'f'
$h = Hashes $d
$r = Run $d @('--apply', '--no-backup', '--format', 'json')
$j = Json $r.Out
Check 'F1 fresh: exit 0, ok=true, refused=false, converted' `
  (($r.Code -eq 0) -and ($null -ne $j) -and $j.ok -and ($j.refused -eq $false) -and (@($j.converted).Count -eq 1)) $r.Out
Check 'F2 fresh: the .dfm now holds the To type' ([IO.File]::ReadAllText((Join-Path $d 'Frm.dfm')) -match 'TDstB')

# ---- L: a block that LOST lines, its recorded end now on the sibling's end ---
# btnA was indexed at 2..6; three property lines go, so it really ends at 3 and
# the 3-line sibling btnB moves up to 4..6 -- line 6 is btnB's `end`, at btnA's
# indent. Only the FIRST same-indent `end` after the opener is btnA's own.
$PasAB = @'
unit Frm;

interface

uses
  Classes, Forms, LibAB;

type
  TFrm = class(TForm)
    btnA: TSrcA;
    btnB: TDstB;
  end;

implementation

{$R *.dfm}

end.
'@
$DfmAB = @'
object Frm: TFrm
  object btnA: TSrcA
    Caption = 'A'
    Hint = 'h'
    Tag = 1
  end
  object btnB: TDstB
    Caption = 'B'
  end
end
'@
$d = NewFixture 'l' $PasAB $DfmAB
$dfm = Join-Path $d 'Frm.dfm'
$t = [IO.File]::ReadAllText($dfm).Replace("    Caption = 'A'`r`n    Hint = 'h'`r`n    Tag = 1`r`n", '')
[IO.File]::WriteAllText($dfm, $t, [Text.Encoding]::ASCII)
CheckRefusal 'L' $d 'btnA: index is stale for this .dfm -- reindex'
Check 'L5 the sibling btnB block is still in the .dfm' ([IO.File]::ReadAllText($dfm) -match "(?m)^  object btnB: TDstB\r?$")

# ---- T: the .dfm cut short after indexing (span past end of file) ------------
$d = NewFixture 't'
$dfm = Join-Path $d 'Frm.dfm'
[IO.File]::WriteAllText($dfm, "object Frm: TFrm`r`n  object btn1: TSrcA`r`n", [Text.Encoding]::ASCII)
CheckRefusal 'T' $d

# ---- B: btn1 vs btn10 -- the name match is exact, not a prefix ---------------
$Pas110 = @'
unit Frm;

interface

uses
  Classes, Forms, LibAB;

type
  TFrm = class(TForm)
    btn1: TSrcA;
    btn10: TSrcA;
  end;

implementation

{$R *.dfm}

end.
'@
$Dfm110 = @'
object Frm: TFrm
  object btn1: TSrcA
    Caption = 'One'
  end
  object btn10: TSrcA
    Caption = 'Ten'
  end
end
'@
$Dfm110Swapped = @'
object Frm: TFrm
  object btn10: TSrcA
    Caption = 'Ten'
  end
  object btn1: TSrcA
    Caption = 'One'
  end
end
'@
$d = NewFixture 'b' $Pas110 $Dfm110
Write-Ascii (Join-Path $d 'Frm.dfm') $Dfm110Swapped
CheckRefusal 'B' $d $Reason @('--only', 'btn1')

Write-Host ''
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
} finally {
  foreach ($d23 in @("$env:TEMP\drag-lint-convert-apply-stale-dfm-$PID")) { if (Test-Path -LiteralPath $d23) { Remove-Item -LiteralPath $d23 -Recurse -Force -ErrorAction SilentlyContinue } }
}
