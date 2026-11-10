<#
  150 Y2 (G14): forms-csv / menu-tree read each form's .dfm tree from the index's
  dfm_nav_nodes / dfm_nav_props fact tables instead of re-parsing the .dfm text.

  Identity: for every form fixture (formsmap*, dispatch-forms, menutree,
  dfm-nonascii and a generated one with a UTF-8-BOM and a Windows-1252 .dfm,
  non-ASCII captions, '+' continued and #nnn strings, a multi-line set, a
  collection with items and a TAction), forms-csv (and menu-tree --with-dfm where
  a project has .dfm menus) prints byte-identical output on
    ON  = the table path (default)
    OFF = DRAGLINT_NO_FILE_FACTS=1, the text scan.
  The csv footer's time stamp is the only line excluded.

  Positive controls (fail on the base engine and when the table read is removed):
    ON1   ON runs print `[dfm-nav] table` (DRAGLINT_DEBUG=1) and no `[dfm-nav] text`.
    OFF1  OFF runs print `[dfm-nav] text` only.
    STALE a .dfm edited after the index is read from the text, and the output
          shows the edit (a stale index is not evidence).
    ABS   -BaseExe given: an index built by the base engine (no fact tables, or
          tables without rows) is answered by the text path, identically.
    U1/U2 the UTF-8-BOM form's menu path and the non-ASCII caption come out right
          (the text scan used to read a BOM file as ANSI: root lost, mojibake).

  Usage: pwsh -File tests/autotest/run_formsmap_dfm_nav_facts.ps1 -Exe <drag-lint.exe> [-BaseExe <old exe>]
#>
[CmdletBinding()]
param(
  [string] $Exe     = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
  [string] $BaseExe = '',
  [string] $WorkDir = "$env:TEMP\drag-lint-formsmap-navfacts-$PID"
)
$ErrorActionPreference = 'Stop'
$script:Failed = 0
$script:Passed = 0
function Check([string]$Name, [bool]$Ok, [string]$Detail = '') {
  if ($Ok) { $script:Passed++; Write-Host "  [PASS] $Name" -ForegroundColor Green }
  else     { $script:Failed++; Write-Host "  [FAIL] $Name $Detail" -ForegroundColor Red }
}
if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
$Exe = (Resolve-Path $Exe).Path
if (Test-Path $WorkDir) { [IO.Directory]::Delete($WorkDir, $true) }
New-Item -ItemType Directory $WorkDir | Out-Null
$fixRoot = (Resolve-Path "$PSScriptRoot\..\fixtures").Path

# ---- the generated fixture (non-ASCII bytes are written here, so the repo stays ASCII)
$gen = Join-Path $WorkDir 'navfx'
New-Item -ItemType Directory $gen | Out-Null
$utf8bom = New-Object System.Text.UTF8Encoding($true)
$ascii   = [Text.Encoding]::ASCII
$cp1252  = [Text.Encoding]::GetEncoding(1252)
function PutGen([string]$Name, [string]$Text, [Text.Encoding]$Enc) {
  [IO.File]::WriteAllText((Join-Path $gen $Name), $Text.Replace("`r`n", "`n").Replace("`n", "`r`n"), $Enc)
}
$OUml = [string][char]0x00D6; $UUml = [string][char]0x00DC; $uUml = [string][char]0x00FC; $De = [string][char]0x0414
PutGen 'NavFx.dpr' @'
program NavFx;
uses
  Vcl.Forms,
  uNavMain in 'uNavMain.pas' {frmNavMain},
  uNavChild in 'uNavChild.pas' {frmNavChild},
  uNavAnsi in 'uNavAnsi.pas' {frmNavAnsi};
begin
  Application.Initialize;
  Application.CreateForm(TfrmNavMain, frmNavMain);
  Application.Run;
end.
'@ $ascii
PutGen 'NavFx.dproj' @'
<Project xmlns="http://schemas.microsoft.com/developer/msbuild/2003">
  <PropertyGroup>
    <MainSource>NavFx.dpr</MainSource>
  </PropertyGroup>
  <ItemGroup>
    <DCCReference Include="uNavMain.pas"><Form>frmNavMain</Form><FormType>dfm</FormType></DCCReference>
    <DCCReference Include="uNavChild.pas"><Form>frmNavChild</Form><FormType>dfm</FormType></DCCReference>
    <DCCReference Include="uNavAnsi.pas"><Form>frmNavAnsi</Form><FormType>dfm</FormType></DCCReference>
  </ItemGroup>
</Project>
'@ $ascii
PutGen 'uNavMain.pas' @'
unit uNavMain;
interface
uses
  System.Classes, Vcl.Forms, Vcl.Menus, Vcl.StdCtrls, Vcl.ActnList, Vcl.ComCtrls, uNavChild, uNavAnsi;
type
  TfrmNavMain = class(TForm)
    mnuMain: TMainMenu;
    mnuFile: TMenuItem;
    mnuOpen: TMenuItem;
    alMain: TActionList;
    actAnsi: TAction;
    btnAnsi: TButton;
    sbMain: TStatusBar;
    procedure mnuOpenClick(Sender: TObject);
    procedure actAnsiExecute(Sender: TObject);
  end;
var
  frmNavMain: TfrmNavMain;
implementation
{$R *.dfm}
procedure TfrmNavMain.mnuOpenClick(Sender: TObject);
begin
  TfrmNavChild.Create(Self).ShowModal;
end;
procedure TfrmNavMain.actAnsiExecute(Sender: TObject);
begin
  TfrmNavAnsi.Create(Self).Show;
end;
end.
'@ $ascii
PutGen 'uNavMain.dfm' (@'
object frmNavMain: TfrmNavMain
  Left = 0
  Top = 0
  Caption = 'Hauptfenster '#220'bersicht'
  Menu = mnuMain
  object mnuMain: TMainMenu
    object mnuFile: TMenuItem
      Caption = '&Datei'
      object mnuOpen: TMenuItem
        Caption = '@O@&ffnen ' +
          '@D@a'
        OnClick = mnuOpenClick
      end
    end
  end
  object alMain: TActionList
    object actAnsi: TAction
      Caption = 'Gr@u@n &Ansicht'
      OnExecute = actAnsiExecute
    end
  end
  object btnAnsi: TButton
    Action = actAnsi
    Anchors = [akLeft,
      akTop]
  end
  object sbMain: TStatusBar
    Panels = <
      item
        Text = 'x = y'
        Width = 50
      end>
  end
end
'@).Replace('@O@', $OUml).Replace('@D@', $De).Replace('@u@', $uUml) $utf8bom
PutGen 'uNavChild.pas' @'
unit uNavChild;
interface
uses
  System.Classes, Vcl.Forms;
type
  TfrmNavChild = class(TForm)
  end;
var
  frmNavChild: TfrmNavChild;
implementation
{$R *.dfm}
end.
'@ $ascii
PutGen 'uNavChild.dfm' @'
object frmNavChild: TfrmNavChild
  Caption = 'Child'
end
'@ $ascii
PutGen 'uNavAnsi.pas' @'
unit uNavAnsi;
interface
uses
  System.Classes, Vcl.Forms, Vcl.StdCtrls;
type
  TfrmNavAnsi = class(TForm)
    btnOk: TButton;
    procedure btnOkClick(Sender: TObject);
  end;
var
  frmNavAnsi: TfrmNavAnsi;
implementation
{$R *.dfm}
procedure TfrmNavAnsi.btnOkClick(Sender: TObject);
begin
  Close;
end;
end.
'@ $ascii
PutGen 'uNavAnsi.dfm' (@'
object frmNavAnsi: TfrmNavAnsi
  Caption = '@U@ber (ANSI)'
  object btnOk: TButton
    Caption = '@U@bernehmen'
    OnClick = btnOkClick
  end
end
'@).Replace('@U@', $UUml) $cp1252

# ---- runner
function Run-Verb([string[]]$VerbArgs, [bool]$Off, [string]$Tag, [string]$UseExe = $Exe) {
  $o = Join-Path $WorkDir "$Tag-out.txt"
  $e = Join-Path $WorkDir "$Tag-err.txt"
  $env:DRAGLINT_DEBUG = '1'
  if ($Off) { $env:DRAGLINT_NO_FILE_FACTS = '1' } else { $env:DRAGLINT_NO_FILE_FACTS = $null }
  try {
    $p = Start-Process -FilePath $UseExe -ArgumentList $VerbArgs -NoNewWindow -Wait -PassThru `
      -RedirectStandardOutput $o -RedirectStandardError $e
  } finally {
    $env:DRAGLINT_DEBUG = $null
    $env:DRAGLINT_NO_FILE_FACTS = $null
  }
  $errText = if (Test-Path $e) { [IO.File]::ReadAllText($e) } else { '' }
  [pscustomobject]@{
    Code  = $p.ExitCode; Err = $errText
    Table = ([regex]::Matches($errText, '\[dfm-nav\] table ')).Count
    Text  = ([regex]::Matches($errText, '\[dfm-nav\] text ')).Count
    Out   = $o
  }
}
# The csv body without its footer (the footer carries a time stamp).
function CsvBody([string]$Path) {
  if (-not (Test-Path $Path)) { return '<no file>' }
  $t = [IO.File]::ReadAllText($Path)
  $i = $t.LastIndexOf('"# forms-csv algorithm')
  if ($i -lt 0) { return $t }
  return $t.Substring(0, $i)
}
function Forms-Csv([string]$Fx, [string]$Db, [string]$Proj, [bool]$Off, [string]$Tag, [string]$UseExe = $Exe) {
  $csv = Join-Path $WorkDir "$Tag.csv"
  $a = @('forms-csv', '--db', $Db, '--output', $csv)
  if ($Proj) { $a = @('forms-csv', '--project', $Proj, '--db', $Db, '--output', $csv) }
  $r = Run-Verb $a $Off $Tag $UseExe
  $r | Add-Member -NotePropertyName Body -NotePropertyValue (CsvBody $csv)
  $r
}

# ---- fixtures: copy each into the work dir (a scratch _D-RAG must not land in the repo)
$fixtures = @('formsmap', 'formsmap-scrub', 'formsmap-v4', 'formsmap-v6', 'formsmap-v8', 'formsmap-v9', 'dispatch-forms', 'menutree', 'dfm-nonascii')
$sets = @()
foreach ($f in $fixtures) {
  $dst = Join-Path $WorkDir "fx-$f"
  Copy-Item -LiteralPath (Join-Path $fixRoot $f) -Destination $dst -Recurse
  $sets += [pscustomobject]@{ Name = $f; Dir = $dst }
}
$sets += [pscustomobject]@{ Name = 'navfx'; Dir = $gen }

$navRes = $null
$script:TreeSets = 0
foreach ($s in $sets) {
  New-Item -ItemType Directory -Force (Join-Path $s.Dir '_D-RAG') | Out-Null
  [IO.File]::WriteAllText((Join-Path $s.Dir '_D-RAG\drag-lint-project.json'), '{ "ownRoots": ["."] }')
  $db = Join-Path $WorkDir "$($s.Name).sqlite"
  & $Exe index $s.Dir --db $db 2>&1 | Out-Null
  Check "$($s.Name) index exits 0" ($LASTEXITCODE -eq 0) "exit=$LASTEXITCODE"
  $proj = @(Get-ChildItem $s.Dir -Filter *.dproj | Select-Object -First 1 | ForEach-Object FullName)[0]
  $on  = Forms-Csv $s.Dir $db $proj $false "$($s.Name)-on"
  $off = Forms-Csv $s.Dir $db $proj $true  "$($s.Name)-off"
  Check "$($s.Name) forms-csv exits 0 on both paths" (($on.Code -eq 0) -and ($off.Code -eq 0)) "on=$($on.Code) off=$($off.Code)"
  Check "$($s.Name) ID forms-csv byte-identical ON vs OFF" ($on.Body -ceq $off.Body) "on=$($on.Body.Length) off=$($off.Body.Length) chars; diff: $WorkDir\$($s.Name)-on.csv vs -off.csv"
  if (($on.Table + $on.Text + $off.Table + $off.Text) -eq 0) {
    Write-Host "  [note] $($s.Name): forms-csv reads no .dfm tree here (no traced handler); identity only"
  } else {
    $script:TreeSets++
    Check "$($s.Name) ON1 trees read from the table" (($on.Table -gt 0) -and ($on.Text -eq 0)) "table=$($on.Table) text=$($on.Text)"
    Check "$($s.Name) OFF1 DRAGLINT_NO_FILE_FACTS=1 reads the text" (($off.Table -eq 0) -and ($off.Text -gt 0)) "table=$($off.Table) text=$($off.Text)"
  }
  if ($s.Name -eq 'navfx') { $navRes = $on }
  if ($proj -and @(Get-ChildItem $s.Dir -Filter *.dfm | Where-Object { [IO.File]::ReadAllText($_.FullName) -match 'TMainMenu|TdxBarManager|TPopupMenu' }).Count -gt 0) {
    $mOn  = Run-Verb @('menu-tree', '--project', $proj, '--db', $db, '--with-dfm', '--json') $false "$($s.Name)-mt-on"
    $mOff = Run-Verb @('menu-tree', '--project', $proj, '--db', $db, '--with-dfm', '--json') $true  "$($s.Name)-mt-off"
    $bOn  = [IO.File]::ReadAllText($mOn.Out); $bOff = [IO.File]::ReadAllText($mOff.Out)
    Check "$($s.Name) ID menu-tree --with-dfm byte-identical ON vs OFF" (($mOn.Code -eq $mOff.Code) -and ($bOn -ceq $bOff) -and ($bOn.Length -gt 0)) "code $($mOn.Code)/$($mOff.Code) len $($bOn.Length)/$($bOff.Length)"
    Check "$($s.Name) ON1 menu-tree reads the table" (($mOn.Table -gt 0) -and ($mOn.Text -eq 0)) "table=$($mOn.Table) text=$($mOn.Text)"
  }
}

Check "forms-csv read .dfm trees in at least 7 fixture sets (not vacuous)" ($script:TreeSets -ge 7) "sets=$($script:TreeSets)"

# ---- U1 / U2: the UTF-8-BOM form decoded properly (row of the child form)
$hdr = '#,Form,Unit,How to open,Click,Control type,Handler,Opened by,Modal,Before you start,Other ways in,Confidence,Tester result,Notes'
$navLines = @($navRes.Body -split "`r`n" | Where-Object { $_ -ne '' })
$rows = @($navLines[1..($navLines.Count - 1)] | ConvertFrom-Csv -Header ($hdr -split ','))
$child = $rows | Where-Object { $_.Form -ceq 'frmNavChild' } | Select-Object -First 1
$ansi  = $rows | Where-Object { $_.Form -ceq 'frmNavAnsi'  } | Select-Object -First 1
# forms-csv writes every non-ASCII char as \uXXXX (lowercase hex).
$wantChild = 'Main menu: Datei > \u00d6ffnen \u0414a'
Check 'U1 child form opened by the UTF-8-BOM menu path' (($null -ne $child) -and ($child.'How to open' -ceq $wantChild)) "want [$wantChild] got [$($child.'How to open')]"
Check 'U2 action caption decoded from the UTF-8-BOM .dfm' (($null -ne $ansi) -and ($ansi.'How to open' -clike '*Gr\u00fcn Ansicht*')) "got [$($ansi.'How to open')]"

# ---- U3: menu-tree --with-dfm shows the UTF-8-BOM form's menu (base: the BOM file gave no root)
$u3 = Run-Verb @('menu-tree', '--project', (Join-Path $gen 'NavFx.dproj'), '--db', (Join-Path $WorkDir 'navfx.sqlite'), '--with-dfm') $false 'u3'
$u3Out = [IO.File]::ReadAllText($u3.Out)
Check 'U3 menu-tree --with-dfm lists the UTF-8-BOM form menu' (($u3.Code -eq 0) -and ($u3Out -match 'Datei')) "code=$($u3.Code) out=[$u3Out]"

# ---- STALE: edit the cp1252 .dfm after the index; the table must not answer it
$navDb = Join-Path $WorkDir 'navfx.sqlite'
$mainDfm = Join-Path $gen 'uNavMain.dfm'
$txt = [IO.File]::ReadAllText($mainDfm, $utf8bom)
[IO.File]::WriteAllText($mainDfm, $txt.Replace('&Datei', '&Datei2'), $utf8bom)
(Get-Item $mainDfm).LastWriteTimeUtc = (Get-Date).ToUniversalTime().AddMinutes(5)
$sOn  = Forms-Csv $gen $navDb (Join-Path $gen 'NavFx.dproj') $false 'stale-on'
$sOff = Forms-Csv $gen $navDb (Join-Path $gen 'NavFx.dproj') $true  'stale-off'
Check 'STALE edited .dfm read from text on the default path' (@([regex]::Matches($sOn.Err, '\[dfm-nav\] text [^\r\n]*uNavMain\.dfm')).Count -gt 0) $sOn.Err
Check 'STALE output shows the edit and equals the text path' (($sOn.Body -match 'Datei2') -and ($sOn.Body -ceq $sOff.Body))

# ---- ABS: an index without the fact rows (built by the base engine) falls back
if ($BaseExe -and (Test-Path $BaseExe)) {
  $absDir = Join-Path $WorkDir 'abs'
  Copy-Item -LiteralPath (Join-Path $fixRoot 'formsmap-v6') -Destination $absDir -Recurse
  $absDb = Join-Path $WorkDir 'abs.sqlite'
  & $BaseExe index $absDir --db $absDb 2>&1 | Out-Null
  $aOn  = Forms-Csv $absDir $absDb (Join-Path $absDir 'Demo6.dproj') $false 'abs-on'
  $aOff = Forms-Csv $absDir $absDb (Join-Path $absDir 'Demo6.dproj') $true  'abs-off'
  Check 'ABS base-engine index answered by the text path' (($aOn.Table -eq 0) -and ($aOn.Text -gt 0)) "table=$($aOn.Table) text=$($aOn.Text)"
  Check 'ABS output identical to the text path' (($aOn.Code -eq 0) -and ($aOn.Body -ceq $aOff.Body))
}

Write-Host ("run_formsmap_dfm_nav_facts: {0} passed, {1} failed" -f $script:Passed, $script:Failed)
if ($script:Failed -eq 0) { [IO.Directory]::Delete($WorkDir, $true); exit 0 }
Write-Host "work dir kept: $WorkDir"
exit 1
