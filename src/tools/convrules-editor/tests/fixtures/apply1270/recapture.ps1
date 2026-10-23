# Re-creates the apply/1 captures of the tiny "Fix" project (the C:\fix\ project of the 2026-10-11 captures,
# which is gone) from text, and re-runs the same convert-apply commands. N3, 2026-10-23.
#
# Usage: pwsh -NoProfile -File recapture.ps1 -Pin <pin dir> [-OutDir <dir>] [-Library <library-Win64.sqlite>]
#   -Pin      a pinned engine dir (third_party\engine-pinned\<version>-<stamp>): the exe, tree-sitter DLLs,
#             casts.castlib and rules\ are copied into a scratch STAGE; the pin itself and dll-win64 are never run.
#   -OutDir   where the captures are written (default: this folder, i.e. the checked-in fixtures).
#   -Library  the Win64 library index (read-only --db). Default: C:\Projects\.drag-lint\library-Win64.sqlite.
# The staged engine gets its OWN drag-lint.json (indexes.outDir = the scratch stage, no sections), so no real
# project DB is touched; each capture indexes Fix.dpr into its own scratch Fix.sqlite.
#
# Captured: apply-cast-site-1270, apply-uses-1270, apply-pas-uses-1270, apply-pas-uses-resolution-1282.
# NOT recaptured (their sources are not reproducible from text): apply-stripdb-1270 and apply-exit6-castlib-1280
# (ORM3 CLIENT dmToolStats.pas + convrules\BDE-to-FireDAC.rules), the *-1315 set (FixUnit/DescUnit of the
# drive-convert-tab fixture), apply-missing-fields-sample (hand-written).
# Normalisation (stdout otherwise verbatim): the scratch project dir -> C:\fix (JSON-escaped), uses_reindex.ms -> 0.
# Those are the only volatile fields; two runs are byte-identical.
param([Parameter(Mandatory = $true)][string]$Pin, [string]$OutDir = $PSScriptRoot,
      [string]$Library = 'C:\Projects\.drag-lint\library-Win64.sqlite')
$ErrorActionPreference = 'Stop'
function WriteAscii($path, $text) { [IO.File]::WriteAllText($path, ($text -replace "`r?`n", "`r`n"), [Text.ASCIIEncoding]::new()) }
if (-not (Test-Path -LiteralPath (Join-Path $Pin 'drag-lint.exe'))) { throw "no drag-lint.exe in $Pin" }
if (-not (Test-Path -LiteralPath $Library)) { throw "library index not found: $Library" }
$work = Join-Path ([IO.Path]::GetTempPath()) ('apply1270-recapture-' + [guid]::NewGuid().ToString('N'))
$stage = Join-Path $work 'stage'; [void][IO.Directory]::CreateDirectory($stage)
foreach ($f in Get-ChildItem -LiteralPath $Pin -File) { if ($f.Name -ne 'ConvRulesEditor.exe') { Copy-Item -LiteralPath $f.FullName -Destination $stage } }
if (Test-Path -LiteralPath (Join-Path $Pin 'rules')) { Copy-Item -LiteralPath (Join-Path $Pin 'rules') -Destination $stage -Recurse }
$idxDir = (Join-Path $stage 'idx') -replace '\\', '\\'
WriteAscii (Join-Path $stage 'drag-lint.json') ('{ "settings": { "currentProjectsIndexing": "perProject", "defaultPlatform": "Win64", "enginePath": "auto" }, "indexes": { "outDir": "' + $idxDir + '", "sections": [] } }')
$engine = Join-Path $stage 'drag-lint.exe'
$sha = (Get-FileHash -Algorithm SHA256 -LiteralPath $engine).Hash
$ver = (Get-Content -Raw -LiteralPath (Join-Path $Pin 'ENGINE-PIN.json') | ConvertFrom-Json).version_string
$pinName = Split-Path -Leaf $Pin

function RunEngine($cwd, [string[]]$a) {
  $psi = [Diagnostics.ProcessStartInfo]::new($engine)
  $psi.WorkingDirectory = $cwd; $psi.UseShellExecute = $false; $psi.RedirectStandardOutput = $true; $psi.RedirectStandardError = $true
  $psi.StandardOutputEncoding = [Text.Encoding]::UTF8
  foreach ($x in $a) { [void]$psi.ArgumentList.Add($x) }
  $p = [Diagnostics.Process]::Start($psi)
  $errTask = $p.StandardError.ReadToEndAsync()
  $out = $p.StandardOutput.ReadToEnd(); $p.WaitForExit()
  [pscustomobject]@{ Code = $p.ExitCode; Out = $out; Err = $errTask.Result }
}

$dpr = @'
program Fix;

uses
  Vcl.Forms,
  Unit1 in 'Unit1.pas' {Form1};

begin
  Application.Initialize;
  Application.Run;
end.
'@
$head = @'
unit Unit1;

interface

uses
  Winapi.Windows, System.SysUtils, System.Classes, Vcl.Controls, Vcl.Forms,
  Vcl.Buttons;

type
  TForm1 = class(TForm)
'@
$mid = @'
    procedure FormCreate(Sender: TObject);
  end;

var Form1: TForm1;

implementation

{$R *.dfm}

procedure TForm1.FormCreate(Sender: TObject);
'@

$cases = @(
  @{ Out = 'apply-cast-site-1270.json'
     Note = 'Fix: Unit1 with BitBtn1: TBitBtn (code BitBtn1.Glyph.LoadFromFile at line 25) and SpeedButton1: TSpeedButton; Fix.rules = #unuse Vcl.Buttons + #convert TBitBtn -> TcxButton with #link OptionsImage.Glyph <- Glyph : AssignGraphic (tests\fixtures\glyph\BitBtn-glyph.rules without the G expression).'
     Rules = "// cast-site`n#unuse Vcl.Buttons`n#convert TBitBtn -> TcxButton`n#link OptionsImage.Glyph <- Glyph : AssignGraphic"
     Dfm = 'BitBtn1,SpeedButton1'
     Pas = "$head`n    BitBtn1: TBitBtn;`n    SpeedButton1: TSpeedButton;`n$mid`nbegin`n  // glyph`n  BitBtn1.Glyph.LoadFromFile('x.bmp');`n  BitBtn1.Caption := 'OK';`nend;`n`nend." }
  @{ Out = 'apply-uses-1270.json'
     Note = 'Fix: Unit1 with BitBtn1: TBitBtn and code using TBitBtnKind / bkOK; Fix.rules = #unuse Vcl.Buttons, #use Vcl.ExtCtrls, #convert TBitBtn -> TcxButton.'
     Rules = "// uses`n#unuse Vcl.Buttons`n#use Vcl.ExtCtrls`n#convert TBitBtn -> TcxButton"
     Dfm = 'BitBtn1'
     Pas = "$head`n    BitBtn1: TBitBtn;`n$mid`nvar`n  Count: Integer;`n  K: TBitBtnKind;`nbegin`n  K := bkOK;`n  BitBtn1.Caption := 'OK';`nend;`n`nend." }
  @{ Out = 'apply-pas-uses-1270.json'
     Note = 'Fix: Unit1 with BitBtn1: TBitBtn; FormCreate uses TBitBtnKind, bkOK, BitBtn1.Caption/Kind/NumGlyphs/Spacing/Click. Fix.rules = #unuse Vcl.Buttons, #convert Vcl.Buttons.TBitBtn -> Vcl.ExtCtrls.TPanel, #link Caption <- Caption, #link Font.Size <- Spacing.'
     Rules = "// pas-uses`n#unuse Vcl.Buttons`n#convert Vcl.Buttons.TBitBtn -> Vcl.ExtCtrls.TPanel`n#link Caption <- Caption`n#link Font.Size <- Spacing"
     Dfm = 'BitBtn1'
     Pas = "$head`n    BitBtn1: TBitBtn;`n$mid`nvar`n  Count: Integer;`n  K: TBitBtnKind;`nbegin`n  K := bkOK;`n  BitBtn1.Caption := 'OK';`n  BitBtn1.Kind := K;`n  BitBtn1.NumGlyphs := 2;`n  BitBtn1.Spacing := 6;`n  BitBtn1.Click;`nend;`n`nend." }
  @{ Out = 'apply-pas-uses-resolution-1282.json'
     Note = 'Fix: Unit1 with Label1: TLabel; its uses clause names NO StdCtrls unit (Winapi.Windows, System.SysUtils, System.Classes, Vcl.Graphics, Vcl.Controls, Vcl.Forms); FormCreate sets Label1.Caption and Label1.WordWrap. Fix.rules = #convert TLabel -> Vcl.ExtCtrls.TPanel (BARE From), #ignore Left.'
     Rules = "// resolution`n#convert TLabel -> Vcl.ExtCtrls.TPanel`n#ignore Left"
     Dfm = 'Label1'
     Pas = "unit Unit1;`n`ninterface`n`nuses`n  Winapi.Windows, System.SysUtils, System.Classes, Vcl.Graphics,`n  Vcl.Controls, Vcl.Forms;`n`ntype`n  TForm1 = class(TForm)`n    Label1: TLabel;`n$mid`nbegin`n  // text`n  Label1.Caption := 'Hello';`n  Label1.WordWrap := True;`nend;`n`nend." }
)

function DfmText($names, $withCaption) {
  # Per-class property sets: the engine's reemit_notes of the 2026-10-11 captures fix them (TBitBtn: Left Top Width
  # Height TabOrder dropped, Caption carried; TLabel: Left ignored, only Caption dropped).
  $s = "object Form1: TForm1`n  Left = 0`n  Top = 0`n  Caption = 'Form1'`n  ClientHeight = 300`n  ClientWidth = 400`n  OnCreate = FormCreate`n"
  $i = 0
  foreach ($n in $names -split ',') {
    if ($n -like 'Label*') { $t = 'TLabel'; $props = "Left = 8`n    Caption = 'Hello'" }
    elseif ($n -like 'Speed*') { $t = 'TSpeedButton'; $props = "Left = $(8 + 100 * $i)`n    Top = 8`n    Width = 75`n    Height = 25" }
    else { $t = 'TBitBtn'; $props = "Left = $(8 + 100 * $i)`n    Top = 8`n    Width = 75`n    Height = 25`n    TabOrder = $i"; if ($withCaption) { $props += "`n    Caption = '$n'" } }
    $s += "  object ${n}: $t`n    $props`n  end`n"
    $i++
  }
  $s + 'end'
}
[void][IO.Directory]::CreateDirectory($OutDir)
foreach ($c in $cases) {
  $dir = Join-Path $work ($c.Out -replace '\.json$', '')
  [void][IO.Directory]::CreateDirectory($dir)
  WriteAscii (Join-Path $dir 'Fix.dpr') $dpr
  WriteAscii (Join-Path $dir 'Unit1.pas') $c.Pas
  WriteAscii (Join-Path $dir 'Unit1.dfm') (DfmText $c.Dfm ($c.Rules -like '*#link Caption*'))
  WriteAscii (Join-Path $dir 'Fix.rules') $c.Rules
  Copy-Item -LiteralPath (Join-Path $stage 'casts.castlib') -Destination $dir
  $ix = RunEngine $dir @('index', '--project', 'Fix.dpr', '--db', 'Fix.sqlite')
  if ($ix.Code -ne 0) { throw "index failed ($($ix.Code)) for $($c.Out): $($ix.Err) $($ix.Out)" }
  $r = RunEngine $dir @('convert-apply', '--unit', 'Unit1.pas', '--rules', 'Fix.rules', '--db', 'Fix.sqlite', '--db', $Library,
                        '--castlib', 'casts.castlib', '--apply', '--format', 'json')
  $json = $r.Out.Trim()
  if (-not $json.StartsWith('{')) { throw "no JSON from convert-apply for $($c.Out) (exit $($r.Code)): $($r.Err) $json" }
  $dirEsc = $dir -replace '\\', '\\'
  $json = $json.Replace($dirEsc, 'C:\\fix')
  $json = [regex]::Replace($json, '("uses_reindex":\{[^}]*"ms":)\d+', '${1}0')
  $note = "RECAPTURE by recapture.ps1 (engine $ver pin $pinName sha256 $sha, exit code $($r.Code)). stdout only. Command: index --project Fix.dpr --db Fix.sqlite, then convert-apply --unit Unit1.pas --rules Fix.rules --db Fix.sqlite --db library-Win64.sqlite --castlib casts.castlib --apply --format json. $($c.Note) Temp paths replaced by C:\fix\; uses_reindex.ms zeroed." -replace '\\', '\\'
  $out = '{"_note":"' + $note + '",' + $json.Substring(1) + "`r`n"
  [IO.File]::WriteAllText((Join-Path $OutDir $c.Out), $out, [Text.ASCIIEncoding]::new())
  Write-Host ("{0}: exit {1}, {2} chars" -f $c.Out, $r.Code, $out.Length)
}
Write-Host "scratch kept at $work"
