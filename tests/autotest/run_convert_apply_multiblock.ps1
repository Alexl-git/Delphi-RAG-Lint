<#
  run_convert_apply_multiblock.ps1 -- convert-apply validates each #convert
  block of a rule book against that block's OWN From/To property trees, and its
  freshness guard covers the same blocks (1.20.6-alpha, Task 2 + fix round 1:
  rulings R5/R6/R7). By default the blocks in scope are the ones this unit's
  .dfm instances convert through; --validate-all-blocks puts every block in
  scope.

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
    S  R5 scope: a block no instance converts through is NOT validated by
       default and is LISTED (text line + json blocks_not_validated[], an
       unresolved type named); --validate-all-blocks validates it and fails.
    G  R5 freshness scope: a stale unit behind an out-of-scope block does not
       warn by default and does not refuse a unit-rules --apply; it warns with
       --validate-all-blocks.
    T  R7: a BARE header builds a real tree (a bogus #link fails on its line),
       and a qualified type that does not exist fails on its #convert line.
    P  minor 5: a #mapping applied by two blocks of DIFFERENT types is checked
       against both (errors carry each block's suffix).
    C  minor 5 / R5: two blocks sharing a type build it ONCE, and the plan
       reuses validation's trees -- apply/1 trees_built = distinct types (3).
    I  R6: a .dfm holding an INHERITED object of a From type refuses the unit
       whole (unit rules too): exit 1, the reason, both files byte-identical.

  Fixture: LibAB, LibCD, LibG, MyForm + .dfm, InhForm + .dfm and Plain written fresh under a
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

  TSrcE = class(TPersistent)
  private
    FCaption: string;
  published
    property Caption: string read FCaption write FCaption;
  end;

  TSrcF = class(TPersistent)
  private
    FCaption: string;
  published
    property Caption: string read FCaption write FCaption;
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
    btn2: TSrcE;
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
  object btn2: TSrcE
    Caption = 'E'
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

Write-Ascii (P 'LibG.pas') @"
unit LibG;

interface

uses
  Classes;

type
  TSrcG = class(TPersistent)
  private
    FCaption: string;
  published
    property Caption: string read FCaption write FCaption;
  end;

implementation

end.
"@

Write-Ascii (P 'InhForm.pas') @"
unit InhForm;

interface

uses
  Classes, LibAB, MyForm;

type
  TInhForm = class(TMyForm)
  end;

implementation

{`$R *.dfm}

end.
"@

Write-Ascii (P 'InhForm.dfm') @"
inherited InhForm: TInhForm
  inherited btn1: TSrcA
    Caption = 'Inh'
  end
end
"@

Write-Ascii (P 'Plain.pas') @"
unit Plain;

interface

uses
  Classes;

implementation

end.
"@

# S: block 3 (line 10) has no instance and a bogus link; block 4 (line 12) names types no --db has.
Write-Ascii (P 'scope.rules') @"
#mapping KindMap from LibCD.TCKind to LibCD.TDstD
#mapping KindMap #when Kind = ckOne -> Mode = dmFirst
#mapping KindMap #else -> Mode = dmOther
#convert LibAB.TSrcA -> LibAB.TDstB, LibAB
#link Caption <- Caption
#link Down <- Down
#convert LibCD.TSrcC -> LibCD.TDstD, LibCD
#link Title <- Text
#apply KindMap
#convert LibAB.TSrcF -> LibAB.TDstB, LibAB
#link NoSuchDst <- NoSuchSrc
#convert LibX.TGhost -> LibX.TNone, LibX
"@

# G: block 2's type lives in LibG, which goes stale; nothing in MyForm/Plain uses it.
Write-Ascii (P 'gscope.rules') @"
#use NewU
#convert LibAB.TSrcA -> LibAB.TDstB, LibAB
#link Caption <- Caption
#convert LibG.TSrcG -> LibAB.TDstB, LibAB
"@

# T: a bare header with a bogus link on line 2; a qualified To type that does not exist.
Write-Ascii (P 'bare.rules') @"
#convert TSrcA -> TDstB, LibAB
#link Caption <- NoSuchProp
"@
Write-Ascii (P 'ghost.rules') @"
#convert LibAB.TSrcA -> LibAB.TNowhere, LibAB
#link Caption <- Caption
"@

# P: KindMap is applied by BOTH blocks. Line 2 is valid only in C/D, line 3 only in A/B.
Write-Ascii (P 'map2.rules') @"
#mapping KindMap from LibCD.TCKind to LibCD.TDstD
#mapping KindMap #when Kind = ckOne -> Mode = dmFirst
#mapping KindMap #when Caption = 'x' -> Caption = 'y'
#convert LibAB.TSrcA -> LibAB.TDstB, LibAB
#link Caption <- Caption
#apply KindMap
#convert LibCD.TSrcC -> LibCD.TDstD, LibCD
#link Title <- Text
#apply KindMap
"@

# C: two blocks share the To type TDstB (and btn1/btn2 convert through both).
Write-Ascii (P 'shared.rules') @"
#convert LibAB.TSrcA -> LibAB.TDstB, LibAB
#link Caption <- Caption
#convert LibAB.TSrcE -> LibAB.TDstB, LibAB
#link Caption <- Caption
"@

# I: an inherited object of a From type, plus a unit rule.
Write-Ascii (P 'inh.rules') @"
#unuse Classes
#convert LibAB.TSrcA -> LibAB.TDstB, LibAB
#link Caption <- Caption
"@

$db = P 'fx.sqlite'
$idx = & $Exe index $WorkDir --db $db 2>&1
Check 'V the fixture index was built' (($LASTEXITCODE -eq 0) -and (Test-Path $db)) "exit=$LASTEXITCODE; $($idx -join ' | ')"

function Apply([string]$Rules, [string[]]$Extra = @()) {
  $o = (& $Exe convert-apply --unit (P 'MyForm.pas') --rules (P $Rules) --db $db @Extra 2>&1) -join "`n"
  return [pscustomobject]@{ Code = $LASTEXITCODE; Out = $o }
}
function ErrLines([string]$s) { return ,@($s -split "`n" | Where-Object { $_ -match '^\s+line \d+: ' }) }
function ApplyTo([string]$Unit, [string]$Rules, [string[]]$Extra = @()) {
  $o = (& $Exe convert-apply --unit (P $Unit) --rules (P $Rules) --db $db @Extra 2>&1) -join "`n"
  return [pscustomobject]@{ Code = $LASTEXITCODE; Out = $o }
}
function Json([string]$s) {
  $a = $s.IndexOf('{'); $b = $s.LastIndexOf('}')
  if ($a -lt 0 -or $b -le $a) { return $null }
  try { return ($s.Substring($a, $b - $a + 1) | ConvertFrom-Json) } catch { return $null }
}

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

# ---- S: R5 scope -- out-of-scope blocks are listed, not validated ---------
$r = Apply 'scope.rules'
Check 'S1 default: blocks with no instance are not validated -> exit 0' ($r.Code -eq 0) $r.Out
Check 'S2 default: block 10 is listed as not validated' `
  ($r.Out -match [regex]::Escape('block 10 (LibAB.TSrcF -> LibAB.TDstB): not validated here (no instances in this unit)')) $r.Out
Check 'S3 default: block 12 is listed with both types unresolved' `
  ($r.Out -match [regex]::Escape('block 12 (LibX.TGhost -> LibX.TNone): not validated here (no instances in this unit) -- unresolved: LibX.TGhost, LibX.TNone')) $r.Out
$r = Apply 'scope.rules' @('--format', 'json')
$j = Json $r.Out
$nv = @($j.blocks_not_validated)
Check 'S4 json blocks_not_validated = lines 10 and 12, with from/to/unresolved' `
  (($null -ne $j) -and ($nv.Count -eq 2) -and ($nv[0].line -eq 10) -and ($nv[0].from -eq 'LibAB.TSrcF') -and ($nv[0].to -eq 'LibAB.TDstB') -and `
   (@($nv[0].unresolved).Count -eq 0) -and ($nv[1].line -eq 12) -and (@($nv[1].unresolved).Count -eq 2)) ($j.blocks_not_validated | ConvertTo-Json -Compress -Depth 4)
$r = Apply 'scope.rules' @('--validate-all-blocks')
$e = ErrLines $r.Out
Check 'S5 --validate-all-blocks exits 1' ($r.Code -eq 1) $r.Out
Check 'S6 --validate-all-blocks: the bogus link on line 11 fails (both sides)' `
  (@($e | Where-Object { $_ -match '^\s+line 11: link (To|From)Path not found' }).Count -eq 2) ($e -join ' | ')
Check 'S7 --validate-all-blocks: the unresolved types fail on line 12' `
  ((@($e | Where-Object { $_ -match '^\s+line 12: #convert From type not found in any --db: LibX\.TGhost' }).Count -eq 1) -and `
   (@($e | Where-Object { $_ -match '^\s+line 12: #convert To type not found in any --db: LibX\.TNone' }).Count -eq 1)) ($e -join ' | ')
Check 'S8 --validate-all-blocks lists nothing as not validated' (-not ($r.Out -match 'not validated here')) $r.Out

# ---- T: R7 -- no block passes silently on an unresolved type --------------
$r = Apply 'bare.rules'
$e = ErrLines $r.Out
Check 'T1 bare header + bogus link: exit 1, the link fails on line 2' `
  (($r.Code -eq 1) -and ($e.Count -eq 1) -and ($e[0] -match '^\s+line 2: link FromPath not found in --from tree: NoSuchProp')) $r.Out
$r = Apply 'ghost.rules'
$e = ErrLines $r.Out
Check 'T2 qualified type that does not exist: exit 1 on its #convert line 1' `
  (($r.Code -eq 1) -and ($e.Count -eq 1) -and ($e[0] -match '^\s+line 1: #convert To type not found in any --db: LibAB\.TNowhere$')) $r.Out

# ---- P: a mapping applied by two blocks of different types ----------------
$r = Apply 'map2.rules'
$e = ErrLines $r.Out
Check 'P1 exit 1 with exactly four errors' (($r.Code -eq 1) -and ($e.Count -eq 4)) ($e -join ' | ')
Check 'P2 line 2 (valid in C/D only) fails twice against block line 4 (TSrcA -> TDstB)' `
  (@($e | Where-Object { $_ -match '^\s+line 2: .*\(#convert line 4: LibAB\.TSrcA -> LibAB\.TDstB\)$' }).Count -eq 2) ($e -join ' | ')
Check 'P3 line 3 (valid in A/B only) fails twice against block line 7 (TSrcC -> TDstD)' `
  (@($e | Where-Object { $_ -match '^\s+line 3: .*\(#convert line 7: LibCD\.TSrcC -> LibCD\.TDstD\)$' }).Count -eq 2) ($e -join ' | ')

# ---- C: shared type built once; the plan reuses validation's trees --------
$r = Apply 'shared.rules' @('--format', 'json')
$j = Json $r.Out
Check 'C1 shared-type book dry run ok (json ok=true)' (($r.Code -eq 0) -and ($null -ne $j) -and $j.ok) $r.Out
Check 'C2 trees_built = 3 (TSrcA, TSrcE, TDstB once) across validation AND plan' `
  (($null -ne $j) -and ($j.trees_built -eq 3)) "trees_built=$(if ($j) { $j.trees_built } else { '<no json>' })"
Check 'C3 both instances converted' (($null -ne $j) -and (@($j.converted).Count -eq 2)) ($j.converted | ConvertTo-Json -Compress)

# ---- I: R6 -- an inherited object of a From type refuses the unit ---------
$hp = (Get-FileHash (P 'InhForm.pas')).Hash
$hd = (Get-FileHash (P 'InhForm.dfm')).Hash
$r = ApplyTo 'InhForm.pas' 'inh.rules' @('--apply', '--no-backup')
Check 'I1 --apply refuses: exit 1 with the R6 reason' `
  (($r.Code -eq 1) -and ($r.Out -match [regex]::Escape('ERROR: inherited instances of TSrcA are not converted yet -- unit not changed'))) $r.Out
Check 'I2 InhForm.pas and InhForm.dfm are byte-identical (the #unuse did not run)' `
  (((Get-FileHash (P 'InhForm.pas')).Hash -eq $hp) -and ((Get-FileHash (P 'InhForm.dfm')).Hash -eq $hd))
$r = ApplyTo 'InhForm.pas' 'inh.rules' @('--format', 'json')
$j = Json $r.Out
Check 'I3 json: ok=false, error names the inherited type' `
  (($r.Code -eq 1) -and ($null -ne $j) -and (-not $j.ok) -and ($j.error -eq 'inherited instances of TSrcA are not converted yet -- unit not changed')) $r.Out

# ---- G: R5 freshness scope ------------------------------------------------
Add-Content -LiteralPath (P 'LibG.pas') -Value '{ edited after indexing }' -Encoding ascii
$r = Apply 'gscope.rules'
Check 'G1 default: a stale unit behind an out-of-scope block does not warn' `
  (($r.Code -eq 0) -and -not ($r.Out -match 'freshness guard failed')) $r.Out
$r = Apply 'gscope.rules' @('--validate-all-blocks')
Check 'G2 --validate-all-blocks: it warns, naming LibG.pas' `
  (($r.Code -eq 0) -and ($r.Out -match 'WARNING: freshness guard failed') -and ($r.Out -match 'TSrcG: index is stale for .*LibG\.pas')) $r.Out
$r = ApplyTo 'Plain.pas' 'gscope.rules' @('--apply', '--no-backup')
Check 'G3 a unit-rules --apply is NOT refused over that stale type (exit 0, #use applied)' `
  (($r.Code -eq 0) -and ([IO.File]::ReadAllText((P 'Plain.pas')) -match 'NewU')) $r.Out

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
