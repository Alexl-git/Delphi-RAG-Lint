<#
  run_convert_apply_inherited.ps1 -- C8 engine items N1, N3 and N5 (spec
  docs\superpowers\specs\2026-10-05-c8-inherited-instances-design.md).

  BEFORE (1.20.6, ruling R6): a unit whose .dfm held an `inherited` / `inline`
  object of a From type was refused WHOLE -- 'inherited instances of <T> are
  not converted yet -- unit not changed' -- so none of the unit's own
  components, code or unit rules converted.

  THE CONTRACT this guard pins:
    N1  the unit is NOT refused. Its own `object` instances convert as before
        (positive control btnOwn: .pas field retyped, .dfm re-emitted). Each
        inherited / inline instance of a From type is SKIPPED -- its .dfm lines
        are byte-identical -- and reported:
          * apply/1 `inherited[]`, one object per instance, keys exactly
            {name, type, line, ancestor_unit, ancestor_state, reason};
          * a `line N: warning: ...` line in warnings[] and in text mode;
          * an items[] mirror of kind `inherited-instance-skipped`
            (items.length = sum of the six arrays still holds).
    N1  the DECLARING ancestor is the nearest ancestor class whose .dfm opens
        the component with `object` -- found through the index's ancestor
        chain, several levels up when needed (MidForm only RE-OPENS btnA with
        `inherited`, so btnA's declaring ancestor is BaseForm, two levels up).
        A nested inherited block (btnN inside pnl) resolves the same way; a
        child of an `inline` frame resolves through the FRAME's class.
    N1  ancestor_state: `unconverted` (the ancestor still has the From type),
        `converted` (it has the block's To type -- still SKIPPED in N1, the
        reason says retyping is not supported yet).
    N3  `outside`: the ancestor chain leaves the --db (TExternalForm is in no
        index) -- skipped, never guessed; ancestor_unit is ''.
    N1  a unit whose only From-type instances are inherited converts nothing
        and exits 0 (component_part skipped-no-instances), even for a book
        with no unit rules.
    R26 still applies: a #unuse of the unit declaring the From type of an
        inherited instance refuses the unit (nothing written).
    N3  an ancestor whose .dfm is MISSING or BINARY stops the walk: outside,
        the reason names the file -- a farther ancestor is never credited.
        A declaring object of a third type is `mismatched` (ancestor_unit set).
    Also: an access site on a skipped inherited receiver stays byte-unchanged
        while a converted own instance's site is rewritten; --only filters
        inherited[]; names match case-insensitively (component, type, root
        class); the NEAREST `object` declarer wins; an inherited child under a
        new `object` parent still resolves through the root class.
    N5  info --json: capabilities.inherited_instances is the JSON literal true.

  Fixture written fresh under a $PID scratch folder and indexed into a scratch
  --db there. Nothing shared is touched. Run from any CWD, pwsh 7.
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\drag-lint-convert-apply-inherited-$PID"
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
    FTitle: string;
  published
    property Caption: string read FCaption write FCaption;
    property Title: string read FTitle write FTitle;
  end;

implementation

end.
'@

# ---- the chain: BaseForm declares, MidForm re-opens, ChildForm is converted --
Write-Ascii (P 'BaseForm.pas') @'
unit BaseForm;

interface

uses
  Classes, Forms, LibA;

type
  TBaseForm = class(TForm)
    btnA: TSrcA;
    pnl: TBox;
    btnN: TSrcA;
  end;

implementation

{$R *.dfm}

end.
'@
Write-Ascii (P 'BaseForm.dfm') @'
object BaseForm: TBaseForm
  object btnA: TSrcA
    Caption = 'A'
  end
  object pnl: TBox
    object btnN: TSrcA
      Caption = 'N'
    end
  end
end
'@

Write-Ascii (P 'MidForm.pas') @'
unit MidForm;

interface

uses
  Classes, Forms, LibA, BaseForm;

type
  TMidForm = class(TBaseForm)
  end;

implementation

{$R *.dfm}

end.
'@
Write-Ascii (P 'MidForm.dfm') @'
inherited MidForm: TMidForm
  inherited btnA: TSrcA
    Caption = 'mid'
  end
end
'@

Write-Ascii (P 'MyFrame.pas') @'
unit MyFrame;

interface

uses
  Classes, Forms, LibA;

type
  TMyFrame = class(TFrame)
    fbtn: TSrcA;
  end;

implementation

{$R *.dfm}

end.
'@
Write-Ascii (P 'MyFrame.dfm') @'
object MyFrame: TMyFrame
  object fbtn: TSrcA
    Caption = 'F'
  end
end
'@

Write-Ascii (P 'ChildForm.pas') @'
unit ChildForm;

interface

uses
  Classes, Forms, LibA, MidForm, MyFrame;

type
  TChildForm = class(TMidForm)
    btnOwn: TSrcA;
    frm1: TMyFrame;
  end;

implementation

{$R *.dfm}

end.
'@
Write-Ascii (P 'ChildForm.dfm') @'
inherited ChildForm: TChildForm
  inherited btnA: TSrcA
    Caption = 'child'
  end
  inherited pnl: TBox
    inherited btnN: TSrcA
      Caption = 'n2'
    end
  end
  object btnOwn: TSrcA
    Caption = 'own'
  end
  inline frm1: TMyFrame
    inherited fbtn: TSrcA
      Caption = 'f2'
    end
  end
end
'@

# ---- a CONVERTED ancestor ----------------------------------------------------
Write-Ascii (P 'ConvBase.pas') @'
unit ConvBase;

interface

uses
  Classes, Forms, LibB;

type
  TConvBase = class(TForm)
    cbtn: TDstB;
  end;

implementation

{$R *.dfm}

end.
'@
Write-Ascii (P 'ConvBase.dfm') @'
object ConvBase: TConvBase
  object cbtn: TDstB
    Caption = 'C'
  end
end
'@
Write-Ascii (P 'ConvChild.pas') @'
unit ConvChild;

interface

uses
  Classes, Forms, LibA, ConvBase;

type
  TConvChild = class(TConvBase)
  end;

implementation

{$R *.dfm}

end.
'@
Write-Ascii (P 'ConvChild.dfm') @'
inherited ConvChild: TConvChild
  inherited cbtn: TSrcA
    Caption = 'cc'
  end
end
'@

# ---- an ancestor OUTSIDE every --db ------------------------------------------
Write-Ascii (P 'OutChild.pas') @'
unit OutChild;

interface

uses
  Classes, Forms, LibA, ExternalForms;

type
  TOutChild = class(TExternalForm)
  end;

implementation

{$R *.dfm}

end.
'@
Write-Ascii (P 'OutChild.dfm') @'
inherited OutChild: TOutChild
  inherited xbtn: TSrcA
    Caption = 'x'
  end
end
'@

Write-Ascii (P 'plain.rules') @'
#convert LibA.TSrcA -> LibB.TDstB, LibB
#link Caption <- Caption
'@
Write-Ascii (P 'unuse.rules') @'
#unuse LibA
#convert LibA.TSrcA -> LibB.TDstB, LibB
#link Caption <- Caption
'@

# ---- (a) access sites: a SKIPPED inherited receiver vs a converted own one ---
Write-Ascii (P 'AccForm.pas') @'
unit AccForm;

interface

uses
  Classes, Forms, LibA, MidForm;

type
  TAccForm = class(TMidForm)
    accOwn: TSrcA;
    procedure Touch;
  end;

implementation

{$R *.dfm}

procedure TAccForm.Touch;
begin
  btnA.Caption := 'x';
  accOwn.Caption := 'y';
end;

end.
'@
Write-Ascii (P 'AccForm.dfm') @'
inherited AccForm: TAccForm
  inherited btnA: TSrcA
    Caption = 'acc'
  end
  object accOwn: TSrcA
    Caption = 'o'
  end
end
'@
Write-Ascii (P 'rename.rules') @'
#convert LibA.TSrcA -> LibB.TDstB, LibB
#link Title <- Caption
'@

# ---- (c) case variants: the component name, its type and the root class -----
Write-Ascii (P 'CaseForm.pas') @'
unit CaseForm;

interface

uses
  Classes, Forms, LibA, MidForm;

type
  TCaseForm = class(TMidForm)
  end;

implementation

{$R *.dfm}

end.
'@
Write-Ascii (P 'CaseForm.dfm') @'
inherited CaseForm: TCASEFORM
  inherited BTNA: tsrca
    Caption = 'case'
  end
end
'@

# ---- (d) declared with `object` at TWO levels: the NEAREST wins --------------
Write-Ascii (P 'Dup2Base.pas') @'
unit Dup2Base;

interface

uses
  Classes, Forms, LibB;

type
  TDup2Base = class(TForm)
    dup: TDstB;
  end;

implementation

{$R *.dfm}

end.
'@
Write-Ascii (P 'Dup2Base.dfm') @'
object Dup2Base: TDup2Base
  object dup: TDstB
    Caption = 'far'
  end
end
'@
Write-Ascii (P 'Dup2Mid.pas') @'
unit Dup2Mid;

interface

uses
  Classes, Forms, LibA, Dup2Base;

type
  TDup2Mid = class(TDup2Base)
  end;

implementation

{$R *.dfm}

end.
'@
Write-Ascii (P 'Dup2Mid.dfm') @'
inherited Dup2Mid: TDup2Mid
  object dup: TSrcA
    Caption = 'near'
  end
end
'@
Write-Ascii (P 'Dup2Child.pas') @'
unit Dup2Child;

interface

uses
  Classes, Forms, LibA, Dup2Mid;

type
  TDup2Child = class(TDup2Mid)
  end;

implementation

{$R *.dfm}

end.
'@
Write-Ascii (P 'Dup2Child.dfm') @'
inherited Dup2Child: TDup2Child
  inherited dup: TSrcA
    Caption = 'c'
  end
end
'@

# ---- (e) an inherited child re-parented under a NEW (object) parent ----------
Write-Ascii (P 'EForm.pas') @'
unit EForm;

interface

uses
  Classes, Forms, LibA, BaseForm;

type
  TEForm = class(TBaseForm)
    pnlNew: TBox;
  end;

implementation

{$R *.dfm}

end.
'@
Write-Ascii (P 'EForm.dfm') @'
inherited EForm: TEForm
  object pnlNew: TBox
    inherited btnA: TSrcA
      Caption = 'e'
    end
  end
end
'@

# ---- (f) an ancestor in the chain with NO .dfm, and one with a BINARY .dfm ---
Write-Ascii (P 'NoDfmMid.pas') @'
unit NoDfmMid;

interface

uses
  Classes, Forms, LibA, BaseForm;

type
  TNoDfmMid = class(TBaseForm)
  end;

implementation

end.
'@
Write-Ascii (P 'NoDfmChild.pas') @'
unit NoDfmChild;

interface

uses
  Classes, Forms, LibA, NoDfmMid;

type
  TNoDfmChild = class(TNoDfmMid)
  end;

implementation

{$R *.dfm}

end.
'@
Write-Ascii (P 'NoDfmChild.dfm') @'
inherited NoDfmChild: TNoDfmChild
  inherited btnA: TSrcA
    Caption = 'nd'
  end
end
'@
Write-Ascii (P 'BinMid.pas') @'
unit BinMid;

interface

uses
  Classes, Forms, LibA, BaseForm;

type
  TBinMid = class(TBaseForm)
  end;

implementation

{$R *.dfm}

end.
'@
# A compiled (binary) .dfm: the TPF0 filer signature, then streamed bytes.
[IO.File]::WriteAllBytes((P 'BinMid.dfm'), [byte[]](0x54,0x50,0x46,0x30,0x07,0x54,0x42,0x69,0x6E,0x4D,0x69,0x64,0x00,0x00))
Write-Ascii (P 'BinChild.pas') @'
unit BinChild;

interface

uses
  Classes, Forms, LibA, BinMid;

type
  TBinChild = class(TBinMid)
  end;

implementation

{$R *.dfm}

end.
'@
Write-Ascii (P 'BinChild.dfm') @'
inherited BinChild: TBinChild
  inherited btnA: TSrcA
    Caption = 'bd'
  end
end
'@

# ---- (g) the declaring ancestor has a THIRD type: mismatched -----------------
Write-Ascii (P 'MisBase.pas') @'
unit MisBase;

interface

uses
  Classes, Forms, LibA;

type
  TMisBase = class(TForm)
    mis: TBox;
  end;

implementation

{$R *.dfm}

end.
'@
Write-Ascii (P 'MisBase.dfm') @'
object MisBase: TMisBase
  object mis: TBox
  end
end
'@
Write-Ascii (P 'MisChild.pas') @'
unit MisChild;

interface

uses
  Classes, Forms, LibA, MisBase;

type
  TMisChild = class(TMisBase)
  end;

implementation

{$R *.dfm}

end.
'@
Write-Ascii (P 'MisChild.dfm') @'
inherited MisChild: TMisChild
  inherited mis: TSrcA
    Caption = 'm'
  end
end
'@

$db = P 'fx.sqlite'
$idx = & $Exe index $WorkDir --db $db 2>&1
Check 'V the fixture index was built' (($LASTEXITCODE -eq 0) -and (Test-Path $db)) "exit=$LASTEXITCODE; $($idx -join ' | ')"

function ApplyTo([string]$Unit, [string]$Rules, [string[]]$Extra = @()) {
  $o = (& $Exe convert-apply --unit (P $Unit) --rules (P $Rules) --db $db @Extra 2>&1) -join "`n"
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
function Inh($j, [string]$Name) { return @($j.inherited | Where-Object { $_.name -eq $Name }) }

$lnA = LineOf 'ChildForm.dfm' 'inherited btnA: TSrcA'
$lnN = LineOf 'ChildForm.dfm' 'inherited btnN: TSrcA'
$lnF = LineOf 'ChildForm.dfm' 'inherited fbtn: TSrcA'

# ---- N1: dry run on the chain unit -------------------------------------------
$r = ApplyTo 'ChildForm.pas' 'plain.rules' @('--format', 'json')
$j = Json $r.Out
Check 'A1 ChildForm is not refused: exit 0, ok=true, refused=false' `
  (($r.Code -eq 0) -and ($null -ne $j) -and $j.ok -and ($j.refused -eq $false)) $r.Out
Check 'A2 inherited[] holds exactly btnA, btnN, fbtn' `
  (($null -ne $j) -and (@($j.inherited).Count -eq 3) -and ((Inh $j 'btnA').Count -eq 1) -and `
   ((Inh $j 'btnN').Count -eq 1) -and ((Inh $j 'fbtn').Count -eq 1)) ($j.inherited | ConvertTo-Json -Compress)
$keys = if ($j -and @($j.inherited).Count -gt 0) { (@($j.inherited)[0].PSObject.Properties.Name) -join ',' } else { '' }
Check 'A3 each inherited[] object has exactly the keys name,type,line,ancestor_unit,ancestor_state,reason' `
  ($keys -eq 'name,type,line,ancestor_unit,ancestor_state,reason') $keys
$a = Inh $j 'btnA'
Check 'A4 plain inherited btnA: type TSrcA, its .dfm line, declared TWO levels up in BaseForm, unconverted' `
  (($a.Count -eq 1) -and ($a[0].type -eq 'TSrcA') -and ($a[0].line -eq $lnA) -and ($a[0].ancestor_unit -eq 'BaseForm') -and `
   ($a[0].ancestor_state -eq 'unconverted') -and ($a[0].reason -match 'BaseForm')) ($a | ConvertTo-Json -Compress)
$n = Inh $j 'btnN'
Check 'A5 nested inherited btnN (inside inherited pnl): BaseForm, unconverted, its own line' `
  (($n.Count -eq 1) -and ($n[0].line -eq $lnN) -and ($n[0].ancestor_unit -eq 'BaseForm') -and ($n[0].ancestor_state -eq 'unconverted')) ($n | ConvertTo-Json -Compress)
$f = Inh $j 'fbtn'
Check 'A6 inline frame child fbtn resolves through the FRAME class: MyFrame, unconverted' `
  (($f.Count -eq 1) -and ($f[0].line -eq $lnF) -and ($f[0].ancestor_unit -eq 'MyFrame') -and ($f[0].ancestor_state -eq 'unconverted')) ($f | ConvertTo-Json -Compress)
Check 'A7 positive control: the unit''s OWN instance btnOwn is converted (and only it)' `
  (($null -ne $j) -and (@($j.converted).Count -eq 1) -and ((@($j.converted) -join ' ') -match 'btnOwn')) ($j.converted | ConvertTo-Json -Compress)
Check 'A8 component_part is applied' (($null -ne $j) -and ($j.component_part -eq 'applied')) "$($j.component_part)"
$w = @($j.warnings | Where-Object { $_ -match '^line \d+: warning: ' -and $_ -match 'inherited' })
Check 'A9 warnings[] carries one "line N: warning:" per inherited instance, at its .dfm line' `
  (($w.Count -eq 3) -and (@($w | Where-Object { $_ -match "^line $lnA`: warning: .*btnA" }).Count -eq 1)) ($w -join ' | ')
$ik = @($j.items | Where-Object { $_.kind -eq 'inherited-instance-skipped' })
Check 'A10 items[] mirrors them as kind inherited-instance-skipped (field warnings, instance named)' `
  (($ik.Count -eq 3) -and (@($ik | Where-Object { $_.field -ne 'warnings' }).Count -eq 0) -and (@($ik | Where-Object { $_.instance -eq 'fbtn' }).Count -eq 1)) ($ik | ConvertTo-Json -Compress)
$sum = @($j.converted).Count + @($j.access_sites).Count + @($j.creator_sites).Count + @($j.todos).Count + @($j.reemit_notes).Count + @($j.warnings).Count
Check 'A11 invariant: items.length = sum of the six arrays' (($null -ne $j) -and (@($j.items).Count -eq $sum)) "items=$(@($j.items).Count) sum=$sum"

$r = ApplyTo 'ChildForm.pas' 'plain.rules'
Check 'A12 text mode: exit 0, no REFUSED line, a "line N: warning:" line naming btnA' `
  (($r.Code -eq 0) -and -not ($r.Out -match '(?m)^REFUSED') -and ($r.Out -match "(?m)^\s*line $lnA`: warning: .*btnA")) $r.Out

# ---- N1: --apply writes the own instance, leaves the inherited lines alone ----
$dfmBefore = [IO.File]::ReadAllLines((P 'ChildForm.dfm'))
$r = ApplyTo 'ChildForm.pas' 'plain.rules' @('--apply', '--no-backup')
$pas = [IO.File]::ReadAllText((P 'ChildForm.pas'))
$dfmAfter = [IO.File]::ReadAllText((P 'ChildForm.dfm'))
Check 'B1 --apply exits 0' ($r.Code -eq 0) $r.Out
Check 'B2 positive control: ChildForm.pas btnOwn retyped to TDstB, LibB added' `
  (($pas -match 'btnOwn: TDstB;') -and ($pas -match 'LibB')) $pas
Check 'B3 the .dfm now opens object btnOwn: TDstB' ($dfmAfter -match 'object btnOwn: TDstB') $dfmAfter
Check 'B4 the three inherited headers are untouched (still TSrcA)' `
  (($dfmAfter -match 'inherited btnA: TSrcA') -and ($dfmAfter -match 'inherited btnN: TSrcA') -and ($dfmAfter -match 'inherited fbtn: TSrcA')) $dfmAfter
Check 'B5 the inherited blocks'' own property lines are unchanged' `
  (($dfmAfter -match "Caption = 'child'") -and ($dfmAfter -match "Caption = 'n2'") -and ($dfmAfter -match "Caption = 'f2'")) $dfmAfter

# ---- N1: a CONVERTED ancestor -- still skipped, reason says why ---------------
$r = ApplyTo 'ConvChild.pas' 'plain.rules' @('--format', 'json')
$j = Json $r.Out
$c = if ($j) { Inh $j 'cbtn' } else { @() }
Check 'C1 ConvChild (only an inherited instance, book without unit rules): exit 0, ok, nothing converted' `
  (($r.Code -eq 0) -and ($null -ne $j) -and $j.ok -and (@($j.converted).Count -eq 0) -and ($j.edits_count -eq 0)) $r.Out
Check 'C2 component_part is skipped-no-instances' (($null -ne $j) -and ($j.component_part -eq 'skipped-no-instances')) "$($j.component_part)"
Check 'C3 cbtn: ancestor ConvBase, state converted, reason says it is not retyped yet' `
  (($c.Count -eq 1) -and ($c[0].ancestor_unit -eq 'ConvBase') -and ($c[0].ancestor_state -eq 'converted') -and `
   ($c[0].reason -match 'not (supported|retyped|converted) yet')) ($c | ConvertTo-Json -Compress)

# ---- N3: an ancestor OUTSIDE every --db ---------------------------------------
$r = ApplyTo 'OutChild.pas' 'plain.rules' @('--format', 'json')
$j = Json $r.Out
$x = if ($j) { Inh $j 'xbtn' } else { @() }
Check 'D1 OutChild: exit 0, xbtn reported outside with an empty ancestor_unit (never guessed)' `
  (($r.Code -eq 0) -and ($x.Count -eq 1) -and ($x[0].ancestor_state -eq 'outside') -and ($x[0].ancestor_unit -eq '')) $r.Out

# ---- R26 still guards the inherited instances --------------------------------
$hp = (Get-FileHash (P 'OutChild.pas')).Hash
$r = ApplyTo 'OutChild.pas' 'unuse.rules' @('--apply', '--no-backup', '--format', 'json')
$j = Json $r.Out
Check 'E1 #unuse LibA with an inherited TSrcA left: refused, R26 text, file untouched, inherited[] still reported' `
  (($r.Code -eq 1) -and ($null -ne $j) -and ($j.refused -eq $true) -and `
   ($j.reason -eq '#unuse LibA would leave 1 unconverted instance(s) of TSrcA -- unit not changed') -and `
   ((Get-FileHash (P 'OutChild.pas')).Hash -eq $hp) -and (@($j.inherited).Count -eq 1)) $r.Out

# ---- (b2) --only naming only an OWN instance excludes the inherited one ------
$r = ApplyTo 'AccForm.pas' 'rename.rules' @('--only', 'accOwn', '--format', 'json')
$j = Json $r.Out
Check 'H4 --only accOwn: exit 0, accOwn converted, btnA (inherited) EXCLUDED -- inherited[] is empty' `
  (($r.Code -eq 0) -and ($null -ne $j) -and $j.ok -and (@($j.converted).Count -eq 1) -and ((@($j.converted) -join ' ') -match 'accOwn') -and `
   (@($j.inherited).Count -eq 0) -and (@($j.items | Where-Object { $_.kind -eq 'inherited-instance-skipped' }).Count -eq 0)) $r.Out

# ---- (a) access sites ----------------------------------------------------------
# The Touch body, with the converted own instance's line masked, must be
# byte-identical before and after: every byte of the inherited receiver's
# access site, and of everything around it, survives the --apply.
function TouchRegionHash([string]$File) {
  $ls = [IO.File]::ReadAllLines((P $File))
  $a = [array]::IndexOf($ls, 'procedure TAccForm.Touch;')
  if ($a -lt 0) { return '<no Touch>' }
  $b = $a; while ($b -lt $ls.Count -and $ls[$b] -ne 'end;') { $b++ }
  $region = @($ls[$a..$b] | ForEach-Object { if ($_ -match '\baccOwn\.') { '<own>' } else { $_ } }) -join "`r`n"
  $sha = [Security.Cryptography.SHA256]::Create()
  try { return [BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::ASCII.GetBytes($region))) } finally { $sha.Dispose() }
}
$touch0 = TouchRegionHash 'AccForm.pas'
$r = ApplyTo 'AccForm.pas' 'rename.rules' @('--apply', '--no-backup')
$acc = [IO.File]::ReadAllText((P 'AccForm.pas'))
Check 'G1 --apply on AccForm exits 0' ($r.Code -eq 0) $r.Out
Check 'G2 positive control: the converted own instance''s access site IS rewritten (accOwn.Title)' `
  (($acc -match "accOwn\.Title := 'y';") -and -not ($acc -match 'accOwn\.Caption')) $acc
Check 'G3 the Touch body is byte-identical apart from the own instance''s line (btnA.Caption untouched)' `
  (($touch0 -ne '<no Touch>') -and ((TouchRegionHash 'AccForm.pas') -eq $touch0)) $acc

# ---- (b) --only naming an inherited instance ---------------------------------
$h0 = (Get-FileHash (P 'ChildForm.pas')).Hash
$r = ApplyTo 'ChildForm.pas' 'plain.rules' @('--only', 'btnA', '--format', 'json')
$j = Json $r.Out
Check 'H1 --only btnA: exit 0, ok, nothing converted, no edits' `
  (($r.Code -eq 0) -and ($null -ne $j) -and $j.ok -and (@($j.converted).Count -eq 0) -and ($j.edits_count -eq 0)) $r.Out
Check 'H2 --only btnA: inherited[] reports btnA alone' `
  (($null -ne $j) -and (@($j.inherited).Count -eq 1) -and (@($j.inherited)[0].name -eq 'btnA')) ($j.inherited | ConvertTo-Json -Compress)
Check 'H3 the dry run wrote nothing' ((Get-FileHash (P 'ChildForm.pas')).Hash -eq $h0)

# ---- (c) case variants ---------------------------------------------------------
$r = ApplyTo 'CaseForm.pas' 'plain.rules' @('--format', 'json')
$j = Json $r.Out
$c = if ($j) { @($j.inherited) } else { @() }
Check 'I1 BTNA: tsrca under root TCASEFORM: one entry, BaseForm, unconverted' `
  (($r.Code -eq 0) -and ($c.Count -eq 1) -and ($c[0].name -eq 'BTNA') -and ($c[0].type -eq 'tsrca') -and `
   ($c[0].ancestor_unit -eq 'BaseForm') -and ($c[0].ancestor_state -eq 'unconverted')) $r.Out

# ---- (d) nearest `object` declarer wins ---------------------------------------
$r = ApplyTo 'Dup2Child.pas' 'plain.rules' @('--format', 'json')
$j = Json $r.Out
$c = if ($j) { @($j.inherited) } else { @() }
Check 'J1 dup declared in Dup2Mid (TSrcA) and Dup2Base (TDstB): the NEAREST, Dup2Mid, unconverted' `
  (($c.Count -eq 1) -and ($c[0].ancestor_unit -eq 'Dup2Mid') -and ($c[0].ancestor_state -eq 'unconverted')) $r.Out

# ---- (e) inherited child under a new parent -----------------------------------
$r = ApplyTo 'EForm.pas' 'plain.rules' @('--format', 'json')
$j = Json $r.Out
$c = if ($j) { @($j.inherited) } else { @() }
Check 'K1 btnA re-parented under object pnlNew: still resolved through the root class, BaseForm, unconverted' `
  (($r.Code -eq 0) -and ($c.Count -eq 1) -and ($c[0].ancestor_unit -eq 'BaseForm') -and ($c[0].ancestor_state -eq 'unconverted')) $r.Out

# ---- (f) an ancestor with no readable text .dfm stops the walk -----------------
$r = ApplyTo 'NoDfmChild.pas' 'plain.rules' @('--format', 'json')
$j = Json $r.Out
$c = if ($j) { @($j.inherited) } else { @() }
Check 'L1 NoDfmMid has no .dfm: outside, ancestor_unit "", reason names NoDfmMid.dfm and "missing" -- BaseForm is NOT credited' `
  (($c.Count -eq 1) -and ($c[0].ancestor_state -eq 'outside') -and ($c[0].ancestor_unit -eq '') -and `
   ($c[0].reason -match 'NoDfmMid\.dfm') -and ($c[0].reason -match 'missing')) $r.Out
$r = ApplyTo 'BinChild.pas' 'plain.rules' @('--format', 'json')
$j = Json $r.Out
$c = if ($j) { @($j.inherited) } else { @() }
Check 'L2 BinMid.dfm is binary: outside, ancestor_unit "", reason names BinMid.dfm and "binary"' `
  (($c.Count -eq 1) -and ($c[0].ancestor_state -eq 'outside') -and ($c[0].ancestor_unit -eq '') -and `
   ($c[0].reason -match 'BinMid\.dfm') -and ($c[0].reason -match 'binary')) $r.Out

# ---- (g) mismatched ------------------------------------------------------------
$r = ApplyTo 'MisChild.pas' 'plain.rules' @('--format', 'json')
$j = Json $r.Out
$c = if ($j) { @($j.inherited) } else { @() }
Check 'M1 MisBase declares mis as TBox: mismatched, ancestor_unit MisBase, reason names TBox' `
  (($r.Code -eq 0) -and ($c.Count -eq 1) -and ($c[0].ancestor_state -eq 'mismatched') -and ($c[0].ancestor_unit -eq 'MisBase') -and `
   ($c[0].reason -match 'TBox')) $r.Out

# ---- N5: the capability --------------------------------------------------------
$o = (& $Exe info --json 2>$null) -join "`n"
$ij = Json $o
Check 'F1 info --json: capabilities.inherited_instances is the JSON literal true' `
  (($null -ne $ij) -and ($ij.capabilities.inherited_instances -is [bool]) -and ($ij.capabilities.inherited_instances -eq $true)) $o

# ---- 1.25.2: the STANDING LOAD GUARD -- every .dfm this suite's --apply wrote
# goes through Delphi's own reader (lib\DfmLoadCheck.ps1). A dry run proves the
# PLAN, never the BYTES.
. (Join-Path $PSScriptRoot 'lib\DfmLoadCheck.ps1')
$loadFails = Test-DfmLoads @((P 'ChildForm.dfm'), (P 'AccForm.dfm'))
Check 'LOAD1 every .dfm --apply wrote LOADS (text -> binary -> text -> binary)' ($loadFails.Count -eq 0) ($loadFails -join ' | ')
Write-Host ''
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
} finally {
  foreach ($d23 in @("$env:TEMP\drag-lint-convert-apply-inherited-$PID")) { if (Test-Path -LiteralPath $d23) { Remove-Item -LiteralPath $d23 -Recurse -Force -ErrorAction SilentlyContinue } }
}
