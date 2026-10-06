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
  published
    property Caption: string read FCaption write FCaption;
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

# ---- N5: the capability --------------------------------------------------------
$o = (& $Exe info --json 2>$null) -join "`n"
$ij = Json $o
Check 'F1 info --json: capabilities.inherited_instances is the JSON literal true' `
  (($null -ne $ij) -and ($ij.capabilities.inherited_instances -is [bool]) -and ($ij.capabilities.inherited_instances -eq $true)) $o

Write-Host ''
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
} finally {
  foreach ($d23 in @("$env:TEMP\drag-lint-convert-apply-inherited-$PID")) { if (Test-Path -LiteralPath $d23) { Remove-Item -LiteralPath $d23 -Recurse -Force -ErrorAction SilentlyContinue } }
}
