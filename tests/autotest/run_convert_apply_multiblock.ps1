<#
  run_convert_apply_multiblock.ps1 -- convert-apply validates EVERY #convert
  block of a rule book against that block's OWN From/To property trees, and its
  freshness guard covers every block's types (1.20.6-alpha, Task 2).

  THE DEFECT (converter team, INBOX-2026-09-29-converter-to-engine-convert-
  apply-bde-book-fails-validation). DoConvertApply took the From/To pair of the
  FIRST #convert block only (a `Break` in the header loop) and validated the
  whole book against those two trees; CheckFreshness had the same first-block
  loop. convrules\BDE-to-FireDAC.rules has ten blocks, so every #link and
  #mapping of blocks 2..10 was checked against TSession/TFDManager and the dry
  run failed with 540 "not found in --from/--to tree" lines, exit 1.

  THE CONTRACT this guard pins:
    M  a two-block book (TSrcA -> TDstB, TSrcC -> TDstD) whose block-2 links
       and a free #mapping applied by block 2 exist ONLY in TSrcC/TDstD dry-runs
       clean: exit 0, no "not found" line, both instances converted.
    B  a block-2 #link naming a path that exists only in BLOCK 1's trees fails,
       and cites its own line -- validation is per block, not against a union.
    W  a free #mapping whose #when path is missing from the applying block's
       From tree fails, citing the mapping line.
    O  a free #mapping applied by NO block is not tree-checked (its paths exist
       in no tree at all, and the book still validates).
    F  CheckFreshness covers block 2's types: after LibCD.pas (TSrcC/TDstD)
       changes on disk, a dry run WARNS naming it and --apply REFUSES (exit 1,
       unit untouched). Block 1's unit stays fresh throughout, so the old
       first-block-only check could not see this.

  Fixture: three units (LibAB, LibCD, MyForm + .dfm) written fresh under a
  $PID scratch folder and indexed into a scratch --db there. Nothing shared is
  touched. Run from any CWD, pwsh 7.

  The #convert headers are QUALIFIED (Unit.Type), as the real books are: a
  bare header builds no property tree, which silently skips every path check
  and would make the M/O arms pass vacuously.
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\drag-lint-convert-apply-multiblock-$PID"
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

Write-Ascii (P 'LibAB.pas') @'
unit LibAB;

interface

uses
  Classes;

type
  TSrcA = class(TPersistent)
  private
    FCaption: string;
    FDown: Boolean;
  published
    property Caption: string read FCaption write FCaption;
    property Down: Boolean read FDown write FDown;
  end;

  TDstB = class(TPersistent)
  private
    FCaption: string;
    FDown: Boolean;
  published
    property Caption: string read FCaption write FCaption;
    property Down: Boolean read FDown write FDown;
  end;

implementation

end.
'@

Write-Ascii (P 'LibCD.pas') @'
unit LibCD;

interface

uses
  Classes;

type
  TCKind = (ckOne, ckTwo);
  TDMode = (dmFirst, dmOther);

  TSrcC = class(TPersistent)
  private
    FText: string;
    FKind: TCKind;
  published
    property Text: string read FText write FText;
    property Kind: TCKind read FKind write FKind;
  end;

  TDstD = class(TPersistent)
  private
    FTitle: string;
    FMode: TDMode;
  published
    property Title: string read FTitle write FTitle;
    property Mode: TDMode read FMode write FMode;
  end;

implementation

end.
'@

Write-Ascii (P 'MyForm.pas') @'
unit MyForm;

interface

uses
  Classes, LibAB, LibCD;

type
  TMyForm = class(TForm)
    btn1: TSrcA;
    edt1: TSrcC;
  end;

implementation

{$R *.dfm}

end.
'@

Write-Ascii (P 'MyForm.dfm') @'
object MyForm: TMyForm
  object btn1: TSrcA
    Caption = 'Hi'
    Down = True
  end
  object edt1: TSrcC
    Text = 'T'
    Kind = ckOne
  end
end
'@

# M: block 2's links and the #mapping it applies exist ONLY in TSrcC/TDstD.
Write-Ascii (P 'good.rules') @'
#mapping KindMap from LibCD.TCKind to LibCD.TDstD
#mapping KindMap #when Kind = ckOne -> Mode = dmFirst
#mapping KindMap #else -> Mode = dmOther
#convert LibAB.TSrcA -> LibAB.TDstB, LibAB
#link Caption <- Caption
#link Down <- Down
#convert LibCD.TSrcC -> LibCD.TDstD, LibCD
#link Title <- Text
#apply KindMap
'@

# B: line 5 is valid in BLOCK 1's trees only -- it must still fail in block 2.
Write-Ascii (P 'bad-link.rules') @'
#convert LibAB.TSrcA -> LibAB.TDstB, LibAB
#link Caption <- Caption
#convert LibCD.TSrcC -> LibCD.TDstD, LibCD
#link Title <- Text
#link Down <- Down
'@

# W: the #when path on line 2 is missing from block 2's From tree (TSrcC).
Write-Ascii (P 'bad-map.rules') @'
#mapping KindMap from LibCD.TCKind to LibCD.TDstD
#mapping KindMap #when NoKind = ckOne -> Mode = dmFirst
#mapping KindMap #else -> Mode = dmOther
#convert LibAB.TSrcA -> LibAB.TDstB, LibAB
#link Caption <- Caption
#convert LibCD.TSrcC -> LibCD.TDstD, LibCD
#link Title <- Text
#apply KindMap
'@

# O: Orphan is applied by no block; its paths exist in no tree at all.
Write-Ascii (P 'orphan.rules') @'
#mapping Orphan from LibX.TNope to LibX.TNowhere
#mapping Orphan #when NoSuchSrc = x -> NoSuchDst = y
#convert LibAB.TSrcA -> LibAB.TDstB, LibAB
#link Caption <- Caption
#convert LibCD.TSrcC -> LibCD.TDstD, LibCD
#link Title <- Text
'@

# F: block 2 carries no links, so the book validates on the old code too and
# the freshness arm isolates CheckFreshness.
Write-Ascii (P 'fresh.rules') @'
#convert LibAB.TSrcA -> LibAB.TDstB, LibAB
#link Caption <- Caption
#convert LibCD.TSrcC -> LibCD.TDstD, LibCD
'@

$db = P 'fx.sqlite'
$idx = & $Exe index $WorkDir --db $db 2>&1
Check 'V the fixture index was built' (($LASTEXITCODE -eq 0) -and (Test-Path $db)) "exit=$LASTEXITCODE; $($idx -join ' | ')"

function Apply([string]$Rules, [string[]]$Extra = @()) {
  $o = (& $Exe convert-apply --unit (P 'MyForm.pas') --rules (P $Rules) --db $db @Extra 2>&1) -join "`n"
  return [pscustomobject]@{ Code = $LASTEXITCODE; Out = $o }
}
function ErrLines([string]$s) { return ,@($s -split "`n" | Where-Object { $_ -match '^\s+line \d+: ' }) }

# ---- M: every block against its own trees ---------------------------------
$r = Apply 'good.rules'
Check 'M1 two-block book dry run exits 0' ($r.Code -eq 0) $r.Out
Check 'M2 no "not found in" line anywhere' (-not ($r.Out -match 'not found in')) $r.Out
Check 'M3 both blocks'' instances are converted (2 instance(s) converted)' `
  ($r.Out -match [regex]::Escape('2 instance(s) converted')) $r.Out

# ---- B: a block-1-only path in block 2 fails on its own line --------------
$r = Apply 'bad-link.rules'
$e = ErrLines $r.Out
Check 'B1 bad block-2 link exits 1' ($r.Code -eq 1) $r.Out
Check 'B2 exactly two rule errors, both on line 5 (the bad link), none on line 4' `
  (($e.Count -eq 2) -and (@($e | Where-Object { $_ -notmatch '^\s+line 5: ' }).Count -eq 0)) ($e -join ' | ')
Check 'B3 the FromPath error names Down' `
  (@($e | Where-Object { $_ -match 'link FromPath not found in --from tree: Down' }).Count -eq 1) ($e -join ' | ')
Check 'B4 the ToPath error names Down' `
  (@($e | Where-Object { $_ -match 'link ToPath not found in --to tree: Down' }).Count -eq 1) ($e -join ' | ')

# ---- W: a free mapping is checked against the block that applies it -------
$r = Apply 'bad-map.rules'
$e = ErrLines $r.Out
Check 'W1 bad #when path in an applied mapping exits 1' ($r.Code -eq 1) $r.Out
Check 'W2 exactly one rule error, on the mapping line 2, naming NoKind' `
  (($e.Count -eq 1) -and ($e[0] -match '^\s+line 2: mapping KindMap #when path not found in --from tree: NoKind \(#convert line 6: LibCD\.TSrcC -> LibCD\.TDstD\)$')) ($e -join ' | ')

# ---- O: a mapping applied by no block is not tree-checked -----------------
$r = Apply 'orphan.rules'
Check 'O1 book with an unapplied mapping exits 0' ($r.Code -eq 0) $r.Out
Check 'O2 no "not found in" line for the unapplied mapping' (-not ($r.Out -match 'not found in')) $r.Out

# ---- F: freshness covers block 2's types ----------------------------------
$r = Apply 'fresh.rules'
Check 'F0 control: freshly indexed, no freshness warning' (($r.Code -eq 0) -and -not ($r.Out -match 'freshness guard failed')) $r.Out
Add-Content -LiteralPath (P 'LibCD.pas') -Value '{ edited after indexing }' -Encoding ascii
$h0 = (Get-FileHash (P 'MyForm.pas')).Hash
$r = Apply 'fresh.rules'
Check 'F1 dry run warns that block 2''s unit is stale' `
  (($r.Code -eq 0) -and ($r.Out -match 'WARNING: freshness guard failed') -and ($r.Out -match 'TSrcC: index is stale for .*LibCD\.pas') -and `
   ($r.Out -match 'TDstD: index is stale for .*LibCD\.pas')) $r.Out
$r = Apply 'fresh.rules' @('--apply', '--no-backup')
Check 'F2 --apply refuses (exit 1, freshness guard) on block 2''s stale unit' `
  (($r.Code -eq 1) -and ($r.Out -match 'refusing to --apply') -and ($r.Out -match 'LibCD\.pas')) $r.Out
Check 'F3 the refused --apply wrote nothing' ((Get-FileHash (P 'MyForm.pas')).Hash -eq $h0)
Check 'F4 block 1''s fresh unit is not reported' (-not ($r.Out -match 'LibAB\.pas')) $r.Out

Write-Host ''
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
} finally {
  # D23: this run's scratch is $PID-suffixed; remove it so per-run folders do not pile up in TEMP.
  foreach ($d23 in @("$env:TEMP\drag-lint-convert-apply-multiblock-$PID")) { if (Test-Path -LiteralPath $d23) { Remove-Item -LiteralPath $d23 -Recurse -Force -ErrorAction SilentlyContinue } }
}
