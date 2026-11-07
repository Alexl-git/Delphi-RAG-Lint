<#
  run_rename_form_component.ps1 -- E-RENAME-FORM-COMPONENT (wave 146): renaming a component rewrites its form.

  A published field of a form class is named by the form file too: `object Name: TType`, `inherited Name: TType`,
  `Prop = Name`, `Prop = DM.Name`. 1.44.1 refused every such rename (dfm-name-unbound, 29 of 67 Micronite refusals), also
  for a same-named component of an unrelated form. A partial rename compiles and leaves the field nil at run time, so the
  proof here is the load itself: a real VCL program creates every form and prints what the streaming bound.

  POSITIVE CONTROLS: pc1 hand-renames the field only: it compiles and the field stays nil at load, so the load proof can fail.
  n1-n4 still refuse: under an `inline`, a published property, a list value, a form whose root class is not indexed.
  RED on 1.44.1-alpha: f1 refuses dfm-name-unbound. Needs RAD Studio for the load proof; those cases SKIP without it.
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\drag-lint-rename-formcomp-$PID",
  [string]$RsVars  = 'C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\rsvars.bat'
)
$env:DRAGLINT_RENAME_TEST_UNGATED = '1' # the plan and bytes here; the load proof below builds on its own
$ErrorActionPreference = 'Continue'
$script:Failed = $false; $script:Passed = 0; $script:FailCount = 0
function Check($n, $ok, $d = '') {
  $s = if ($ok) { 'PASS' } else { 'FAIL' }; $c = if ($ok) { 'Green' } else { 'Red' }
  Write-Host ("  [{0}] {1}" -f $s, $n) -ForegroundColor $c
  if ($ok) { $script:Passed++ } else { $script:FailCount++; if ($d) { Write-Host "      $d" -ForegroundColor DarkGray }; $script:Failed = $true }
}
if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
$Exe = (Resolve-Path $Exe).Path
if (Test-Path $WorkDir) { [IO.Directory]::Delete($WorkDir, $true) }
$Src = Join-Path $WorkDir 'src'
New-Item -ItemType Directory -Force $Src | Out-Null
$Db = Join-Path $WorkDir 'fx.sqlite'
$Ascii = [Text.Encoding]::ASCII
function Crlf([string]$Body) { return ($Body -replace "`r`n", "`n" -replace "`n", "`r`n") }
$Files = @{}
$Files['FcMod.pas'] = @'
unit FcMod;

interface

uses
  System.Classes, Vcl.Menus;

type
  TFcMod = class(TDataModule)
    Pop: TPopupMenu;
  end;

implementation

{$R *.dfm}

end.
'@
$Files['FcMod.dfm'] = @'
object FcModule: TFcMod
  object Pop: TPopupMenu
  end
end
'@
$Files['FcMain.pas'] = @'
unit FcMain;

interface

uses
  System.Classes, Vcl.Controls, Vcl.Forms, Vcl.StdCtrls;

type
  TFcForm = class(TForm)
    BtnGo: TButton;
    Lbl: TLabel;
  private
    FWeight: Integer;
  published
    property Weight: Integer read FWeight write FWeight;
  end;

implementation

{$R *.dfm}

end.
'@
$Files['FcMain.dfm'] = @'
object FcForm: TFcForm
  Caption = 'BtnGo stays'
  PopupMenu = FcModule.Pop
  Weight = 3
  object BtnGo: TButton
    Caption = 'Go'
  end
  object Lbl: TLabel
    FocusControl = BtnGo
  end
end
'@
$Files['FcKid.pas'] = @'
unit FcKid;

interface

uses
  FcMain;

type
  TFcKid = class(TFcForm)
  end;

implementation

{$R *.dfm}

end.
'@
$Files['FcKid.dfm'] = @'
inherited FcKid: TFcKid
  inherited BtnGo: TButton
    Caption = 'Kid'
  end
end
'@
$Files['FcOther.pas'] = @'
unit FcOther;

interface

uses
  System.Classes, Vcl.Forms, Vcl.StdCtrls;

type
  TFcOther = class(TForm)
    BtnGo: TButton;
    Lbl2: TLabel;
  end;

implementation

{$R *.dfm}

end.
'@
$Files['FcOther.dfm'] = @'
object FcOther: TFcOther
  object BtnGo: TButton
    Caption = 'Other'
  end
  object Lbl2: TLabel
    FocusControl = BtnGo
  end
end
'@
$Files['FcFrame.pas'] = @'
unit FcFrame;

interface

uses
  System.Classes, Vcl.Forms, Vcl.StdCtrls;

type
  TFcFrame = class(TFrame)
    BtnF: TButton;
    BtnL: TButton;
  end;

implementation

{$R *.dfm}

end.
'@
$Files['FcFrame.dfm'] = @'
object FcFrame: TFcFrame
  object BtnF: TButton
    Caption = 'F'
  end
  object BtnL: TButton
    Caption = 'L'
  end
end
'@
$Files['FcHost.pas'] = @'
unit FcHost;

interface

uses
  System.Classes, Vcl.Forms, FcFrame;

type
  TFcHost = class(TForm)
    Frm1: TFcFrame;
  end;

implementation

{$R *.dfm}

end.
'@
$Files['FcHost.dfm'] = @'
object FcHost: TFcHost
  inline Frm1: TFcFrame
    inherited BtnF: TButton
      Caption = 'Hosted'
    end
  end
end
'@
$Files['FcList.pas'] = @'
unit FcList;

interface

uses
  System.Classes, Vcl.Forms, Vcl.StdCtrls;

type
  TFcList = class(TForm)
    BtnI: TButton;
  end;

implementation

end.
'@
$Files['FcList.dfm'] = @'
object FcList: TFcList
  Things = (
    BtnI
    Other)
  object BtnI: TButton
  end
end
'@
function Reset-Fx {
  foreach ($k in $Files.Keys) { [IO.File]::WriteAllText((Join-Path $Src $k), (Crlf $Files[$k]), $Ascii) }
}
function Text-Of([string]$Name) { return [IO.File]::ReadAllText((Join-Path $Src $Name), $Ascii) }
function Index-Fx { $null | & $Exe index $Src --db $Db --library-db none --rebuild *> "$Db.log" }
function Plan-Symbol([string]$Q, [string]$To) {
  $o = ($null | & $Exe rename --kind symbol --name $Q --to $To --db $Db --library-db none --plan --json 2>$null | Out-String)
  $j = $null; try { $j = $o | ConvertFrom-Json } catch { }
  return @{ Raw = $o; Json = $j; Kinds = @($j.refusals | ForEach-Object { $_.kind }); Dfm = @($j.edits | Where-Object { $_.file -match '\.dfm$' }) }
}
function Apply-Symbol([string]$Q, [string]$To) {
  $o = ($null | & $Exe rename --kind symbol --name $Q --to $To --db $Db --library-db none --apply --no-backup 2>&1 | Out-String)
  return @{ Exit = $LASTEXITCODE; Out = $o }
}
$LoadDpr = @'
program FcLoad;
{$APPTYPE CONSOLE}
uses
  System.SysUtils, Vcl.Forms, FcMod, FcMain, FcKid, FcOther;
begin
  var M:= TFcMod.Create(Application);
  var F:= TFcForm.Create(Application);
  var K:= TFcKid.Create(Application);
  var O:= TFcOther.Create(Application);
  Writeln(F.Lbl.FocusControl.Name, ' ', K.Lbl.FocusControl.Name, ' ', O.Lbl2.FocusControl.Name);
  Writeln(F.PopupMenu.Name, ' ', M.ComponentCount, ' ', F.Weight);
  var Field:= F.FieldAddress('BtnRun');
  Writeln(if Field = nil then 'no-field' else if PPointer(Field)^ = nil then 'field-nil' else 'field-bound');
end.
'@
# Compiles FcLoad against the fixture and runs it; the output, or the exception that killed it.
function Load-Proof([string]$Tag) {
  $dir = Join-Path $WorkDir "load-$Tag"
  New-Item -ItemType Directory -Force $dir | Out-Null
  foreach ($k in 'FcMod', 'FcMain', 'FcKid', 'FcOther') { Copy-Item (Join-Path $Src "$k.pas"), (Join-Path $Src "$k.dfm") $dir }
  [IO.File]::WriteAllText((Join-Path $dir 'FcLoad.dpr'), (Crlf $LoadDpr), $Ascii)
  $bat = "$dir.bat"
  [IO.File]::WriteAllText($bat, "@echo off`r`ncall `"$RsVars`"`r`ncd /D `"$dir`"`r`ndcc64 -B -Q `"-NSSystem;Winapi;Vcl;Vcl.Imaging;Data`" FcLoad.dpr`r`nexit /b %ERRORLEVEL%`r`n", $Ascii)
  $p = Start-Process cmd.exe -ArgumentList "/c `"$bat`"" -Wait -PassThru -NoNewWindow -RedirectStandardOutput "$dir.log" -RedirectStandardError "$dir.err"
  if ($p.ExitCode -ne 0) { return @{ Built = $false; Out = (Get-Content "$dir.log" -Tail 8 | Out-String); Exit = -1 } }
  $o = (& (Join-Path $dir 'FcLoad.exe') 2>&1 | Out-String)
  return @{ Built = $true; Out = $o; Exit = $LASTEXITCODE }
}
Reset-Fx
Push-Location $WorkDir
try {
  Index-Fx
  Write-Host 'A component: the owning form, its descendant, and nobody else' -ForegroundColor Cyan
  $p = Plan-Symbol 'FcMain.TFcForm.BtnGo' 'BtnRun'
  Check 'f1 0 undecided' ($p.Json -and @($p.Json.refusals).Count -eq 0) $p.Raw
  Check 'f1 3 form edits: object, Prop = Name, inherited' ($p.Dfm.Count -eq 3) $p.Raw
  $a = Apply-Symbol 'FcMain.TFcForm.BtnGo' 'BtnRun'
  Check 'f2 applies, exit 0' ($a.Exit -eq 0) $a.Out
  $m = Text-Of 'FcMain.dfm'
  Check 'f2 object header' ($m -match 'object BtnRun: TButton') $m
  Check 'f2 property value' ($m -match 'FocusControl = BtnRun') $m
  Check 'f2 a string stays' ($m -match "Caption = 'BtnGo stays'") $m
  Check 'f2 descendant inherited header' ((Text-Of 'FcKid.dfm') -match 'inherited BtnRun: TButton') (Text-Of 'FcKid.dfm')
  Check 'f2 the field' ((Text-Of 'FcMain.pas') -match 'BtnRun: TButton;') (Text-Of 'FcMain.pas')
  Check 'f3 the unrelated form is byte-identical' ((Text-Of 'FcOther.dfm') -ceq (Crlf $Files['FcOther.dfm']))
  Check 'f3 the unrelated unit is byte-identical' ((Text-Of 'FcOther.pas') -ceq (Crlf $Files['FcOther.pas']))

  Index-Fx
  Write-Host 'A data module''s component named from another form' -ForegroundColor Cyan
  $p = Plan-Symbol 'FcMod.TFcMod.Pop' 'PopX'
  Check 'f4 0 undecided, 2 form edits' ($p.Json -and @($p.Json.refusals).Count -eq 0 -and $p.Dfm.Count -eq 2) $p.Raw
  $a = Apply-Symbol 'FcMod.TFcMod.Pop' 'PopX'
  Check 'f4 applies, Prop = Owner.Name followed' ($a.Exit -eq 0 -and (Text-Of 'FcMain.dfm') -match 'PopupMenu = FcModule\.PopX') $a.Out

  if (Test-Path $RsVars) {
    Write-Host 'The load proof: a real program creates every form' -ForegroundColor Cyan
    $l = Load-Proof 'after'
    Check 'f5 builds' $l.Built $l.Out
    Check 'f5 every form loads; each FocusControl and the cross-form menu bound' ($l.Exit -eq 0 -and $l.Out -match 'BtnRun BtnRun BtnGo' -and $l.Out -match 'PopX 1 3' -and $l.Out -match 'field-bound') $l.Out
    Reset-Fx
    # pc1: the partial rename the proof exists to catch.
    $f = Join-Path $Src 'FcMain.pas'
    [IO.File]::WriteAllText($f, ((Text-Of 'FcMain.pas') -replace 'BtnGo: TButton', 'BtnRun: TButton'), $Ascii)
    $l = Load-Proof 'partial'
    Check 'pc1 a field renamed without its form compiles' $l.Built $l.Out
    Check 'pc1 and the field is nil at run time' ($l.Out -match 'field-nil') $l.Out
  } else { Write-Host 'SKIP: no rsvars.bat, no load proof' -ForegroundColor Yellow }

  Reset-Fx
  Index-Fx
  Write-Host 'Negative controls: what the shape cannot tell apart still refuses' -ForegroundColor Cyan
  $p = Plan-Symbol 'FcFrame.TFcFrame.BtnF' 'BtnZ'
  Check 'n1 a frame''s component overridden under an inline: [dfm-name-unbound]' ($p.Kinds -contains 'dfm-name-unbound') $p.Raw
  $p = Plan-Symbol 'FcFrame.TFcFrame.BtnL' 'BtnM'
  Check 'n1b its sibling, not overridden there, is proved' ($p.Json -and @($p.Json.refusals).Count -eq 0 -and $p.Dfm.Count -eq 1) $p.Raw
  $p = Plan-Symbol 'FcMain.TFcForm.Weight' 'Heft'
  Check 'n2 a published property stays refused: [dfm-name-unbound]' ($p.Kinds -contains 'dfm-name-unbound') $p.Raw
  $p = Plan-Symbol 'FcList.TFcList.BtnI' 'BtnJ'
  Check 'n3 a list value: [dfm-name-unbound]' ($p.Kinds -contains 'dfm-name-unbound') $p.Raw
  [IO.File]::WriteAllText((Join-Path $Src 'Stray.dfm'), (Crlf "object Stray: TNobodyKnows`n  object BtnGo: TButton`n  end`nend`n"), $Ascii)
  Index-Fx
  $p = Plan-Symbol 'FcMain.TFcForm.BtnGo' 'BtnRun'
  $strayIn = (& $Exe sql --db $Db --query "select count(*) from files where path like '%Stray.dfm'" --json 2>$null | Out-String | ConvertFrom-Json).rows[0][0]
  if ([int]$strayIn -gt 0) {
    Check 'n4 a form whose root class is not indexed: [dfm-name-unbound]' ($p.Kinds -contains 'dfm-name-unbound') $p.Raw
  } else { Write-Host '  [INFO] n4 an orphan .dfm is not indexed: not reachable' }
} finally { Pop-Location }
Write-Host ("run_rename_form_component: {0} pass, {1} fail" -f $script:Passed, $script:FailCount)
if ($script:Failed) { Write-Host 'FAILED' -ForegroundColor Red; exit 1 }
Write-Host 'ALL PASS' -ForegroundColor Green
exit 0
