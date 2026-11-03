<#
  run_convert_apply_ancestor_order.ps1 -- 1.42 CONVAPPLY-INHERITED (INBOX
  2026-09-30 #9; owner ruling Q5 2026-10-28: strict ancestor-first).

  BEFORE (1.23.0 .. 1.41): a convert-apply batch ran its --unit list in
  command-line order. A descendant whose inherited / inline .dfm objects are
  declared by an ancestor unit of the SAME run was planned before that
  ancestor was written, so its objects were skipped `ancestor_state
  unconverted` -- the run converted the ancestor a moment later and left the
  descendant streaming the old class (DMTEST: dmCPData inherits its BDE
  components from the base data module).

  THE CONTRACT this guard pins:
    order   the batch RUNS ancestor-first: a unit runs after every unit of the
            run that declares one of its inherited / inline objects (form
            ancestry and inline frames alike); --apply retypes the descendants.
    report  apply-batch/1 units[] stays in --unit order (the converter matches
            it by position, ConvRules.ConvertBatch.BatchUnitsMatch).
    text    a reordered batch prints one line 'convert-apply: units run
            ancestor-first: <names>'; a list already ancestor-first prints none.
    Positive control: the same run with the descendant listed FIRST fails the
            'order' checks on a 1.41 exe (descendants skipped, unconverted).

  Fixture written fresh under a $PID scratch folder, indexed into a scratch
  --db there. Nothing shared is touched. pwsh 7.
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
  [string]$WorkDir = "C:\TEMP\draglint_convert_apply_ancestor_order_$PID"
)
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
if (Test-Path $WorkDir) { [IO.Directory]::Delete($WorkDir, $true) }
[void][IO.Directory]::CreateDirectory($WorkDir)

function Write-Ascii([string]$Path, [string]$Body) {
  $norm = $Body -replace "`r`n", "`n" -replace "`n", "`r`n"
  [IO.File]::WriteAllText($Path, $norm, [Text.Encoding]::ASCII)
}

$Files = @{
'CvLib.pas' = @'
unit CvLib;
interface
uses System.Classes;
type
  TOldQuery = class(TComponent)
  private
    FSql: string;
  published
    property Sql: string read FSql write FSql;
  end;
  TNewQuery = class(TComponent)
  private
    FSql: string;
  published
    property Sql: string read FSql write FSql;
  end;
  TOldField = class(TComponent)
  private
    FSize: Integer;
  published
    property Size: Integer read FSize write FSize;
  end;
  TNewField = class(TComponent)
  private
    FSize: Integer;
  published
    property Size: Integer read FSize write FSize;
  end;
implementation
end.
'@
'CvBase.pas' = @'
unit CvBase;
interface
uses System.Classes, CvLib;
type
  TCvBase = class(TComponent)
  public
    Q: TOldQuery;
    F: TOldField;
  end;
implementation
end.
'@
'CvBase.dfm' = @'
object CvBase: TCvBase
  object Q: TOldQuery
    Sql = 'select 1'
  end
  object F: TOldField
    Size = 4
  end
end
'@
'CvChild.pas' = @'
unit CvChild;
interface
uses System.Classes, CvLib, CvBase;
type
  TCvChild = class(TCvBase)
  end;
implementation
end.
'@
'CvChild.dfm' = @'
inherited CvChild: TCvChild
  inherited Q: TOldQuery
    Sql = 'select 2'
  end
  inherited F: TOldField [1]
    Size = 8
  end
end
'@
'CvFrame.pas' = @'
unit CvFrame;
interface
uses System.Classes, CvLib;
type
  TCvFrame = class(TComponent)
  public
    Q: TOldQuery;
  end;
implementation
end.
'@
'CvFrame.dfm' = @'
object CvFrame: TCvFrame
  object Q: TOldQuery
    Sql = 'select 3'
  end
end
'@
'CvForm.pas' = @'
unit CvForm;
interface
uses System.Classes, CvLib, CvFrame;
type
  TCvForm = class(TComponent)
  public
    Fr1: TCvFrame;
  end;
implementation
end.
'@
'CvForm.dfm' = @'
object CvForm: TCvForm
  inline Fr1: TCvFrame
    inherited Q: TOldQuery
      Sql = 'select 4'
    end
  end
end
'@
'book.rules' = @'
#convert CvLib.TOldField -> CvLib.TNewField, CvLib
#link Size <- Size

#convert CvLib.TOldQuery -> CvLib.TNewQuery, CvLib
#link Sql <- Sql
'@
}

# Two identical trees: 'run' (descendants listed FIRST) and 'ok' (already ancestor-first).
foreach ($t in 'run', 'ok') {
  $d = Join-Path $WorkDir $t
  [void][IO.Directory]::CreateDirectory($d)
  foreach ($k in $Files.Keys) { Write-Ascii (Join-Path $d $k) $Files[$k] }
  & $Exe index $d --db (Join-Path $WorkDir "$t.sqlite") *> (Join-Path $WorkDir "$t-index.log")
}
$R = Join-Path $WorkDir 'run'
$O = Join-Path $WorkDir 'ok'
$CmdUnits = @("$R\CvChild.pas", "$R\CvForm.pas", "$R\CvBase.pas", "$R\CvFrame.pas")
$UArgs = @(); foreach ($u in $CmdUnits) { $UArgs += @('--unit', $u) }

Write-Host '== dry run (descendants first): report order'
$dry = & $Exe convert-apply @UArgs --rules "$R\book.rules" --db "$WorkDir\run.sqlite" --format json 2>$null | Out-String
$jd = $null; try { $jd = $dry | ConvertFrom-Json } catch {}
Check 'report.dry.json' ($null -ne $jd) $dry.Substring(0, [Math]::Min(300, $dry.Length))
$paths = @($jd.units | ForEach-Object { [IO.Path]::GetFileName($_.unit) })
Check 'report.units.in.cmd.order' (($paths -join ',') -eq 'CvChild.pas,CvForm.pas,CvBase.pas,CvFrame.pas') ($paths -join ',')

Write-Host '== --apply (descendants first)'
$app = & $Exe convert-apply @UArgs --rules "$R\book.rules" --db "$WorkDir\run.sqlite" --apply --no-backup --format json 2>$null | Out-String
$ja = $null; try { $ja = $app | ConvertFrom-Json } catch {}
Check 'apply.json' ($null -ne $ja)
$paths = @($ja.units | ForEach-Object { [IO.Path]::GetFileName($_.unit) })
Check 'report.apply.units.in.cmd.order' (($paths -join ',') -eq 'CvChild.pas,CvForm.pas,CvBase.pas,CvFrame.pas') ($paths -join ',')
$child = $ja.units | Where-Object { $_.unit -like '*CvChild.pas' }
$form  = $ja.units | Where-Object { $_.unit -like '*CvForm.pas' }
$inhC = @($child.inherited | ForEach-Object { "$($_.name):$($_.action):$($_.ancestor_state)" }) -join ' '
$inhF = @($form.inherited  | ForEach-Object { "$($_.name):$($_.action):$($_.ancestor_state)" }) -join ' '
Check 'order.child.inherited.retyped' ($inhC -eq 'Q:retyped:converted F:retyped:converted') $inhC
Check 'order.inline.frame.child.retyped' ($inhF -eq 'Q:retyped:converted') $inhF
$cd = [IO.File]::ReadAllText("$R\CvChild.dfm")
Check 'order.child.dfm.Q' ($cd -match 'inherited Q: TNewQuery') $cd
Check 'order.child.dfm.F.keeps.index' ($cd -match 'inherited F: TNewField \[1\]') $cd
$fd = [IO.File]::ReadAllText("$R\CvForm.dfm")
Check 'order.form.dfm.inline.Q' ($fd -match 'inherited Q: TNewQuery') $fd
Check 'order.ancestors.converted' (([IO.File]::ReadAllText("$R\CvBase.dfm") -match 'object Q: TNewQuery') -and
                                   ([IO.File]::ReadAllText("$R\CvFrame.dfm") -match 'object Q: TNewQuery'))

Write-Host '== text mode: order note'
$OkUnits = @('--unit', "$O\CvBase.pas", '--unit', "$O\CvFrame.pas", '--unit', "$O\CvChild.pas", '--unit', "$O\CvForm.pas")
$txtOk = & $Exe convert-apply @OkUnits --rules "$O\book.rules" --db "$WorkDir\ok.sqlite" 2>$null | Out-String
Check 'text.ordered.list.no.note' (($txtOk -notmatch 'units run ancestor-first') -and ($txtOk -match 'batch: 4 unit')) ($txtOk.Substring(0, [Math]::Min(300, $txtOk.Length)))
$Rev = @('--unit', "$O\CvChild.pas", '--unit', "$O\CvBase.pas")
$txtRev = & $Exe convert-apply @Rev --rules "$O\book.rules" --db "$WorkDir\ok.sqlite" 2>$null | Out-String
Check 'text.reordered.note' ($txtRev -match 'convert-apply: units run ancestor-first: CvBase\.pas, CvChild\.pas') ($txtRev.Substring(0, [Math]::Min(300, $txtRev.Length)))

if (-not $script:Failed) { try { [IO.Directory]::Delete($WorkDir, $true) } catch {} }
if ($script:Failed) { Write-Host 'RESULT: FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'RESULT: PASS' -ForegroundColor Green
exit 0
