<#
  run_convert_apply_atomic.ps1 -- nested converted instances, and an apply that
  is ALL-OR-NOTHING across the unit's .pas and .dfm (1.25.1-alpha).

  THE DEFECT (1.25.0 and before, found on DMTEST's DMREADINGS): a converted
  component that OWNS converted children -- a TTable with persistent TField
  objects nested in its .dfm block, each child a From type of its own #convert
  block -- was planned twice over: the parent's block was deleted and
  re-emitted (its re-emit already converts the nested children), AND each
  child's block, which lies inside the parent's, was deleted and re-emitted
  again. The edit applier saw overlapping delete ranges and refused the .dfm
  ("refused 74 edit(s) ... overlapping delete ranges") -- but the .pas had
  already been written and the run exited 0: a half-converted unit (fields
  retyped, the .dfm still streaming the old classes) reported as a success.

  THE CONTRACT this guard pins:
    (a) a nested child instance inside a converted parent gets ONE .dfm edit
        set: the parent's re-emit carries the converted child; the child keeps
        its .pas surfaces (field retype, uses). Dry run and --apply succeed;
        the .dfm holds exactly one block per instance, each with its To type;
        the result compiles with dcc64. The To unit is added once although
        two To types live in it, and an access site two blocks' identical #link
        both rewrite is rewritten once (it used to be spliced twice).
    (c) --only naming a parent converts its nested From-type children too
        -- the parent's re-emit converts them in the .dfm regardless, so their
        .pas declarations follow -- reported in apply/1 only_included[]
        {name, parent} and a text line '--only: <child> converts too --
        nested in <parent>'. Siblings outside the parent stay untouched.
    (e) a WRITE that fails after the writability pre-check (forced with the
        test seam DRAGLINT_TEST_FAIL_WRITE_AT=2: the second file write raises)
        is ROLLED BACK: exit 2, 'write failed for <unit>: ... -- rolled back,
        unit not changed', every file byte-identical -- restored from its .BCK,
        or under --no-backup from the bytes read before the write. A rollback
        that itself fails (DRAGLINT_TEST_FAIL_ROLLBACK=1) names the files it
        could not restore: '-- rollback FAILED for <file>: the unit may be
        PARTLY converted; ...'.
    Also: three-level nesting (table > field > field) and a parent holding a
    converted child beside a plain one.
    (b) an edit set the applier would refuse fails the WHOLE unit before
        anything is written -- dry run and --apply alike: ok=false, exit 1,
        error 'refused N edit(s) to <file> -- overlapping delete ranges ...
        -- unit not changed, nothing written'; the .pas and .dfm are
        byte-identical afterwards. In batch mode only that unit fails.
        (Forced here with a .dfm that declares one component name twice, so
        both instances resolve to the same indexed span.)

  Fixture written fresh under a $PID scratch folder and indexed into a scratch
  --db there. Nothing shared is touched. Run from any CWD, pwsh 7.
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
  [string]$WorkDir = "C:\TEMP\draglint_convert_apply_atomic_$PID",
  [string]$RsVars  = 'C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\rsvars.bat',
  [switch]$NoCompile
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
function Text([string]$n) { return [IO.File]::ReadAllText((P $n)) }
function Hash([string]$n) { return (Get-FileHash (P $n)).Hash }

Write-Ascii (P 'LibA.pas') @'
unit LibA;

interface

uses
  System.Classes;

type
  TSrcTable = class(TComponent)
  private
    FCaption: string;
  published
    property Caption: string read FCaption write FCaption;
  end;

  TSrcField = class(TComponent)
  private
    FCaption: string;
    FFlag: Boolean;
  published
    property Caption: string read FCaption write FCaption;
    property Flag: Boolean read FFlag write FFlag default True;
  end;

  { not in any #convert block: a child that stays as it is }
  TPlainChild = class(TComponent)
  private
    FCaption: string;
  published
    property Caption: string read FCaption write FCaption;
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
  TDstTable = class(TComponent)
  private
    FTitle: string;
  published
    property Title: string read FTitle write FTitle;
  end;

  TDstField = class(TComponent)
  private
    FTitle: string;
    FFlag2: Boolean;
  published
    property Title: string read FTitle write FTitle;
    property Flag2: Boolean read FFlag2 write FFlag2 default False;
  end;

implementation

end.
'@

# ---- (a) a DMREADINGS-shaped data module: tables owning converted fields ------
Write-Ascii (P 'NestDM.pas') @'
unit NestDM;

interface

uses
  System.Classes, LibA;

type
  TNestDM = class(TDataModule)
    tbl: TSrcTable;
    tblID: TSrcField;
    tblName: TSrcField;
    tbl2: TSrcTable;
    tbl2ID: TSrcField;
    procedure Touch;
  end;

implementation

{$R *.dfm}

procedure TNestDM.Touch;
begin
  tbl.Caption := tblID.Caption + tbl2ID.Caption;
end;

end.
'@
Write-Ascii (P 'NestDM.dfm') @'
object NestDM: TNestDM
  object tbl: TSrcTable
    Caption = 't'
    object tblID: TSrcField
      Caption = 'id'
    end
    object tblName: TSrcField
      Caption = 'name'
    end
  end
  object tbl2: TSrcTable
    Caption = 't2'
    object tbl2ID: TSrcField
      Caption = 'id2'
    end
  end
end
'@

# ---- (a2) THREE levels, and a mixed parent: a converted child beside a plain one --
Write-Ascii (P 'Nest3DM.pas') @'
unit Nest3DM;

interface

uses
  System.Classes, LibA;

type
  TNest3DM = class(TDataModule)
    tbl: TSrcTable;
    fld: TSrcField;
    sub: TSrcField;
    plain: TPlainChild;
  end;

implementation

{$R *.dfm}

end.
'@
Write-Ascii (P 'Nest3DM.dfm') @'
object Nest3DM: TNest3DM
  object tbl: TSrcTable
    Caption = 't'
    object fld: TSrcField
      Caption = 'f'
      object sub: TSrcField
        Caption = 's'
      end
    end
    object plain: TPlainChild
      Caption = 'p'
    end
  end
end
'@

# ---- (a3) ADJACENT converted blocks: each next block's insert lands on the line
# the previous block's delete ends on (1.25.2, the DMREADINGS misplacement) ------
$adjPas = "unit AdjDM;`n`ninterface`n`nuses`n  System.Classes, LibA;`n`ntype`n  TAdjDM = class(TDataModule)`n"
$adjDfm = "object AdjDM: TAdjDM`n"
for ($q = 1; $q -le 12; $q++) {
  $adjPas += "    t${q}: TSrcTable;`n    t${q}f: TSrcField;`n"
  $adjDfm += "  object t${q}: TSrcTable`n    Caption = 't$q'`n    object t${q}f: TSrcField`n      Caption = 'f$q'`n    end`n  end`n"
}
$adjPas += "  end;`n`nimplementation`n`n{`$R *.dfm}`n`nend.`n"
$adjDfm += "end`n"
Write-Ascii (P 'AdjDM.pas') $adjPas
Write-Ascii (P 'AdjDM.dfm') $adjDfm

# ---- (e) rollback: a write that fails after the pre-check -------------------------
foreach ($rb in 'RollA', 'RollB', 'RollC') {
  Write-Ascii (P "$rb.pas") @"
unit $rb;

interface

uses
  System.Classes, LibA;

type
  T$rb = class(TDataModule)
    rt: TSrcTable;
  end;

implementation

{`$R *.dfm}

end.
"@
  Write-Ascii (P "$rb.dfm") @"
object ${rb}: T$rb
  object rt: TSrcTable
    Caption = 'r'
  end
end
"@
}

# ---- (c) the same module for --only: NestOnly ------------------------------------
Write-Ascii (P 'NestOnly.pas') (([IO.File]::ReadAllText((P 'NestDM.pas'))) -replace 'NestDM', 'NestOnly')
Write-Ascii (P 'NestOnly.dfm') (([IO.File]::ReadAllText((P 'NestDM.dfm'))) -replace 'NestDM', 'NestOnly')

# ---- (b) a .dfm that names one component twice: two instances, one span -------
Write-Ascii (P 'DupForm.pas') @'
unit DupForm;

interface

uses
  System.Classes, LibA;

type
  TDupForm = class(TDataModule)
    dup: TSrcTable;
  end;

implementation

{$R *.dfm}

end.
'@
Write-Ascii (P 'DupForm.dfm') @'
object DupForm: TDupForm
  object dup: TSrcTable
    Caption = 'one'
  end
  object dup: TSrcTable
    Caption = 'two'
  end
end
'@

# a plain unit for the batch control
Write-Ascii (P 'PlainDM.pas') @'
unit PlainDM;

interface

uses
  System.Classes, LibA;

type
  TPlainDM = class(TDataModule)
    ptbl: TSrcTable;
  end;

implementation

{$R *.dfm}

end.
'@
Write-Ascii (P 'PlainDM.dfm') @'
object PlainDM: TPlainDM
  object ptbl: TSrcTable
    Caption = 'p'
  end
end
'@

Write-Ascii (P 'nest.rules') @'
#convert LibA.TSrcTable -> LibB.TDstTable, LibB
#link Title <- Caption
#convert LibA.TSrcField -> LibB.TDstField, LibB
#link Title <- Caption
#link Flag2 <- Flag
'@

$db = P 'fx.sqlite'
$idx = & $Exe index $WorkDir --db $db 2>&1
Check 'V the fixture index was built' (($LASTEXITCODE -eq 0) -and (Test-Path $db)) "exit=$LASTEXITCODE; $($idx -join ' | ')"

function ApplyTo([string[]]$Units, [string]$Rules, [string[]]$Extra = @()) {
  $a = @('convert-apply')
  foreach ($u in $Units) { $a += @('--unit', (P $u)) }
  $a += @('--rules', (P $Rules), '--db', $db) + $Extra
  $o = (& $Exe @a 2>&1) -join "`n"
  return [pscustomobject]@{ Code = $LASTEXITCODE; Out = $o }
}
function Json([string]$s) {
  $a = $s.IndexOf('{'); $b = $s.LastIndexOf('}')
  if ($a -lt 0 -or $b -le $a) { return $null }
  try { return ($s.Substring($a, $b - $a + 1) | ConvertFrom-Json) } catch { return $null }
}

# ---- (a) nested parent + children ----------------------------------------------
$r = ApplyTo @('NestDM.pas') 'nest.rules' @('--format', 'json')
$j = Json $r.Out
Check 'A1 NestDM dry run: exit 0, ok, all five instances converted' `
  (($r.Code -eq 0) -and ($null -ne $j) -and $j.ok -and (@($j.converted).Count -eq 5)) $r.Out
$r = ApplyTo @('NestDM.pas') 'nest.rules' @('--apply', '--no-backup')
$dfm = Text 'NestDM.dfm'
$pas = Text 'NestDM.pas'
Check 'A2 --apply: exit 0 and no refused edit set' (($r.Code -eq 0) -and -not ($r.Out -match 'refused \d+ edit')) $r.Out
Check 'A3 the .dfm holds each block once, each with its To type' `
  ((([regex]::Matches($dfm, 'object tbl: TDstTable')).Count -eq 1) -and (([regex]::Matches($dfm, 'object tblID: TDstField')).Count -eq 1) -and `
   (([regex]::Matches($dfm, 'object tblName: TDstField')).Count -eq 1) -and (([regex]::Matches($dfm, 'object tbl2: TDstTable')).Count -eq 1) -and `
   (([regex]::Matches($dfm, 'object tbl2ID: TDstField')).Count -eq 1) -and -not ($dfm -match 'TSrc')) $dfm
Check 'A4 the children stay nested in their parents, each written by its OWN re-emit (Flag2 = True resolved from TSrcField.Flag''s default -- the parent''s copy cannot resolve it)' `
  ($dfm.Contains("  object tbl: TDstTable`r`n    Title = 't'`r`n    object tblID: TDstField`r`n      Title = 'id'`r`n      Flag2 = True`r`n    end`r`n    object tblName: TDstField`r`n      Title = 'name'`r`n      Flag2 = True`r`n    end`r`n  end`r`n")) $dfm
Check 'A5 the .pas: every field retyped, LibB added ONCE, each access site rewritten ONCE (two blocks share #link Title <- Caption)' `
  (($pas -match 'tbl: TDstTable;') -and ($pas -match 'tblID: TDstField;') -and ($pas -match 'tblName: TDstField;') -and `
   ($pas -match 'tbl2ID: TDstField;') -and (([regex]::Matches($pas, '\bLibB\b')).Count -eq 1) -and ($pas -match 'tbl\.Title := tblID\.Title \+ tbl2ID\.Title;')) $pas

# ---- (a2) three levels and a mixed parent -----------------------------------------
$r = ApplyTo @('Nest3DM.pas') 'nest.rules' @('--apply', '--no-backup')
$dfm = Text 'Nest3DM.dfm'
$pas = Text 'Nest3DM.pas'
Check 'A6 three levels: tbl > fld > sub each converted once, the grandchild still inside the child, written by its own re-emit' `
  (($r.Code -eq 0) -and $dfm.Contains("  object tbl: TDstTable`r`n    Title = 't'`r`n    object fld: TDstField`r`n      Title = 'f'`r`n      Flag2 = True`r`n      object sub: TDstField`r`n        Title = 's'`r`n        Flag2 = True`r`n      end`r`n    end`r`n") -and `
   (([regex]::Matches($dfm, 'object sub:')).Count -eq 1)) ($r.Out + "`n" + $dfm)
Check 'A7 the mixed parent keeps its plain child verbatim beside the converted one; the .pas agrees' `
  ($dfm.Contains("    object plain: TPlainChild`r`n      Caption = 'p'`r`n    end`r`n  end`r`n") -and ($pas -match 'fld: TDstField;') -and ($pas -match 'sub: TDstField;') -and `
   ($pas -match 'plain: TPlainChild;')) ($dfm + "`n" + $pas)

# ---- (a3) twelve adjacent converted tables, each with a converted field ------------
$r = ApplyTo @('AdjDM.pas') 'nest.rules' @('--apply', '--no-backup')
$dfm = Text 'AdjDM.dfm'
$okAdj = $r.Code -eq 0
for ($q = 1; $q -le 12; $q++) {
  if (-not $dfm.Contains("  object t${q}: TDstTable`r`n    Title = 't$q'`r`n    object t${q}f: TDstField`r`n      Title = 'f$q'`r`n      Flag2 = True`r`n    end`r`n  end`r`n")) { $okAdj = $false }
}
Check 'A8 twelve ADJACENT converted blocks: each lands in its own place, intact, in order (insert-after-L before delete-ending-at-L)' `
  ($okAdj -and -not ($dfm -match 'TSrc')) ($r.Out + "`n" + $dfm)

# ---- (e) rollback ------------------------------------------------------------------
# DRAGLINT_TEST_FAIL_WRITE_AT=2 makes the applier's SECOND file write raise -- one
# file of the unit is already written by then.
$hp = Hash 'RollA.pas'; $hd = Hash 'RollA.dfm'
$env:DRAGLINT_TEST_FAIL_WRITE_AT = '2'
try { $r = ApplyTo @('RollA.pas') 'nest.rules' @('--apply') } finally { Remove-Item Env:\DRAGLINT_TEST_FAIL_WRITE_AT -ErrorAction SilentlyContinue }
Check 'E1 a write failing after the first file: exit 2, "rolled back, unit not changed"' `
  (($r.Code -eq 2) -and ($r.Out -match 'write failed for RollA\.pas: EInOutError: .* -- rolled back, unit not changed')) $r.Out
Check 'E2 ... both files byte-identical to the originals (restored from the .BCK backups)' (((Hash 'RollA.pas') -eq $hp) -and ((Hash 'RollA.dfm') -eq $hd)) $r.Out
$bcks = @(Get-ChildItem $WorkDir -Filter 'RollA.*.BCK*')
Check 'E3 ... the .BCK backups exist and equal the originals' `
  (($bcks.Count -eq 2) -and (@($bcks | Where-Object { (Get-FileHash $_.FullName).Hash -notin @($hp, $hd) }).Count -eq 0)) (($bcks | ForEach-Object Name) -join ', ')
$hp = Hash 'RollB.pas'; $hd = Hash 'RollB.dfm'
$env:DRAGLINT_TEST_FAIL_WRITE_AT = '2'
try { $r = ApplyTo @('RollB.pas') 'nest.rules' @('--apply', '--no-backup') } finally { Remove-Item Env:\DRAGLINT_TEST_FAIL_WRITE_AT -ErrorAction SilentlyContinue }
Check 'E4 --no-backup: rolled back from the bytes read before the write, both files byte-identical, exit 2' `
  (($r.Code -eq 2) -and ($r.Out -match 'rolled back, unit not changed') -and ((Hash 'RollB.pas') -eq $hp) -and ((Hash 'RollB.dfm') -eq $hd)) $r.Out
$env:DRAGLINT_TEST_FAIL_WRITE_AT = '2'; $env:DRAGLINT_TEST_FAIL_ROLLBACK = '1'
try { $r = ApplyTo @('RollC.pas') 'nest.rules' @('--apply') } finally {
  Remove-Item Env:\DRAGLINT_TEST_FAIL_WRITE_AT -ErrorAction SilentlyContinue; Remove-Item Env:\DRAGLINT_TEST_FAIL_ROLLBACK -ErrorAction SilentlyContinue }
Check 'E5 a rollback that itself fails: exit 2, "rollback FAILED for <the written file>", "PARTLY converted", the .BCK pointer' `
  (($r.Code -eq 2) -and ($r.Out -match 'rollback FAILED for .*RollC\.(pas|dfm): the unit may be PARTLY converted; restore it from the \.BCK backups')) $r.Out

# ---- (c) --only a parent: its nested children convert with it, .pas too ----------
$r = ApplyTo @('NestOnly.pas') 'nest.rules' @('--only', 'tbl', '--format', 'json')
$j = Json $r.Out
$inc = if ($j) { @($j.only_included | ForEach-Object { "$($_.name)<$($_.parent)" }) -join ',' } else { '' }
Check 'D1 --only tbl: only_matched [tbl], only_included [{tblID,tbl},{tblName,tbl}], 3 instances converted' `
  (($r.Code -eq 0) -and ($null -ne $j) -and ((@($j.only_matched) -join ',') -eq 'tbl') -and ($inc -eq 'tblID<tbl,tblName<tbl') -and (@($j.converted).Count -eq 3)) $r.Out
$r = ApplyTo @('NestOnly.pas') 'nest.rules' @('--only', 'tbl')
Check 'D2 text mode names each included child' `
  (($r.Code -eq 0) -and ($r.Out -match '(?m)^--only: tblID converts too -- nested in tbl') -and ($r.Out -match '(?m)^--only: tblName converts too -- nested in tbl')) $r.Out
$r = ApplyTo @('NestOnly.pas') 'nest.rules' @('--only', 'tbl', '--apply', '--no-backup')
$dfm = Text 'NestOnly.dfm'
$pas = Text 'NestOnly.pas'
Check 'D3 --apply --only tbl: .dfm AND .pas agree -- tbl, tblID, tblName converted; tbl2, tbl2ID untouched' `
  (($r.Code -eq 0) -and ($dfm -match 'object tblID: TDstField') -and ($pas -match 'tblID: TDstField;') -and ($pas -match 'tblName: TDstField;') -and `
   ($dfm -match 'object tbl2: TSrcTable') -and ($dfm -match 'object tbl2ID: TSrcField') -and ($pas -match 'tbl2ID: TSrcField;')) ($dfm + "`n" + $pas)

# ---- (b) all-or-nothing --------------------------------------------------------
$hp = Hash 'DupForm.pas'; $hd = Hash 'DupForm.dfm'
$r = ApplyTo @('DupForm.pas') 'nest.rules' @('--format', 'json')
$j = Json $r.Out
Check 'B1 dry run of a refused edit set: exit 1, ok=false, error names the refusal' `
  (($r.Code -eq 1) -and ($null -ne $j) -and ($j.ok -eq $false) -and ($j.error -match 'refused \d+ edit\(s\) to .*DupForm\.dfm -- overlapping delete ranges') -and `
   ($j.error -match 'unit not changed, nothing written')) $r.Out
$r = ApplyTo @('DupForm.pas') 'nest.rules' @('--apply', '--no-backup')
Check 'B2 --apply: exit 1, an ERROR line naming the refusal' `
  (($r.Code -eq 1) -and ($r.Out -match '(?m)^ERROR: .*overlapping delete ranges')) $r.Out
Check 'B3 --apply wrote NOTHING: .pas and .dfm byte-identical' (((Hash 'DupForm.pas') -eq $hp) -and ((Hash 'DupForm.dfm') -eq $hd)) $r.Out
$rec0 = if (Test-Path (P 'recovery.txt')) { Hash 'recovery.txt' } else { '' }   # (e) above leaves one
$r = ApplyTo @('DupForm.pas') 'nest.rules' @('--apply')
$rec1 = if (Test-Path (P 'recovery.txt')) { Hash 'recovery.txt' } else { '' }
Check 'B4 --apply with backups: still nothing written, no .BCK, no recovery record added' `
  (($r.Code -eq 1) -and ((Hash 'DupForm.pas') -eq $hp) -and ((Hash 'DupForm.dfm') -eq $hd) -and `
   (@(Get-ChildItem $WorkDir -Filter 'DupForm.*.BCK*').Count -eq 0) -and ($rec1 -eq $rec0)) $r.Out
$hq = Hash 'PlainDM.pas'
$r = ApplyTo @('DupForm.pas', 'PlainDM.pas') 'nest.rules' @('--apply', '--no-backup', '--format', 'json')
$j = Json $r.Out
$u = if ($j) { @($j.units) } else { @() }
Check 'B5 batch: only DupForm fails (exit 1), PlainDM is converted' `
  (($r.Code -eq 1) -and ($u.Count -eq 2) -and ($u[0].ok -eq $false) -and ($u[1].ok -eq $true) -and `
   ((Hash 'DupForm.pas') -eq $hp) -and ((Hash 'PlainDM.pas') -ne $hq) -and ((Text 'PlainDM.dfm') -match 'object ptbl: TDstTable')) $r.Out

# ---- the nested conversion compiles --------------------------------------------
if (-not $NoCompile) {
  $CRLF = "`r`n"
  [IO.File]::WriteAllText((P 'P.dpr'), (@('program P;', '', 'uses', '  NestDM, Nest3DM;', '', 'begin', 'end.') -join $CRLF) + $CRLF, [Text.Encoding]::ASCII)
  New-Item -ItemType Directory (P 'bin'), (P 'dcu') -Force | Out-Null
  $bat = P 'compile.bat'; $log = P 'compile.log'
  [IO.File]::WriteAllText($bat, (@('@echo off', "call `"$RsVars`"", "cd /d `"$WorkDir`"",
    "dcc64 -Q -B -NSSystem;Vcl;Winapi;System.Win -E`"$WorkDir\bin`" -NU`"$WorkDir\dcu`" P.dpr", 'echo BUILD_EXITCODE=%ERRORLEVEL%') -join $CRLF), [Text.Encoding]::ASCII)
  Start-Process cmd.exe -ArgumentList '/c', "`"$bat`"" -RedirectStandardOutput $log -RedirectStandardError "$log.err" -NoNewWindow -Wait | Out-Null
  $cl = Get-Content $log -Raw -ErrorAction SilentlyContinue
  $errLines = @(($cl -split "`r?`n") | Where-Object { $_ -match 'Error|Fatal' })
  Check 'C1 the converted NestDM and Nest3DM compile with dcc64' (($cl -match 'BUILD_EXITCODE=0') -and ($errLines.Count -eq 0)) ($errLines -join ' | ')
}

# ---- 1.25.2: the STANDING LOAD GUARD -- every .dfm this suite's --apply wrote
# goes through Delphi's own reader (lib\DfmLoadCheck.ps1). A dry run proves the
# PLAN, never the BYTES.
. (Join-Path $PSScriptRoot 'lib\DfmLoadCheck.ps1')
$loadFails = Test-DfmLoads @((P 'NestDM.dfm'), (P 'Nest3DM.dfm'), (P 'NestOnly.dfm'), (P 'PlainDM.dfm'), (P 'AdjDM.dfm'))
Check 'LOAD1 every .dfm --apply wrote LOADS (text -> binary -> text -> binary)' ($loadFails.Count -eq 0) ($loadFails -join ' | ')
Write-Host ''
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
} finally {
  foreach ($d23 in @("C:\TEMP\draglint_convert_apply_atomic_$PID")) { if (Test-Path -LiteralPath $d23) { Remove-Item -LiteralPath $d23 -Recurse -Force -ErrorAction SilentlyContinue } }
}
