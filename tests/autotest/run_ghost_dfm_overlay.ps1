<#
  run_ghost_dfm_overlay.ps1 -- S0a of PLAN-ide-lsp-group-2026-08-30: pins the
  engine contract the plugin's ghost-DFM overlay relies on.

  THE CONTRACT. `ghost-check --overlays` compiles unsaved editor buffers. When the
  editor holds a modified .dfm (a component removed), the compiler does NOT cross-
  check the .pas field list against it, so a .dfm overlay ALONE reports nothing.
  The error only appears when the .pas overlay is sent TOO (field removed, body
  still reads Edit1 -> E2003). A client must therefore overlay BOTH files.

  CASES (real VCL form project, text .dfm, Edit1: TEdit):
    A  .dfm overlay alone                -> NO error (documents the caveat;
                                            if this ever reports one the contract changed)
    B  .dfm + .pas overlays              -> E2003 naming Edit1 IS reported
    C  unmodified .dfm + .pas as overlays-> no error (silence pair for B)
    D  after every case the real .pas/.dfm are byte- and FILETIME-exact and no
       _D-RAG folder appeared beside the project.

  POSITIVE CONTROL. ghost-check refuses an empty manifest, so "no overlay" cannot
  be run; case C (identity overlays) is the clean-compile control and case B in the
  SAME fixture is the firing control: B carries an Error AND a compiler hint
  (H2219), proving the compiler really ran on this fixture. Without B, C's empty
  result would be vacuous. If B does not report E2003 the engine contract is false:
  STOP, do not weaken this guard.

  Needs a working Delphi compiler (dcc64). Run from a NEUTRAL CWD, pwsh 7.
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
  [string]$WorkDir = ''
)
$ErrorActionPreference = 'Stop'
$script:Failed = $false
function Check($n, $ok, $d = '') {
  $s = if ($ok) { 'PASS' } else { 'FAIL' }
  $c = if ($ok) { 'Green' } else { 'Red' }
  Write-Host ("  [{0}] {1} {2}" -f $s, $n, $d) -ForegroundColor $c
  if (-not $ok) { $script:Failed = $true }
}

$exePath = (Resolve-Path $Exe).Path
if ($WorkDir -eq '') {
  $WorkDir = Join-Path ([IO.Path]::GetTempPath()) ("ghostdfm_" + [Guid]::NewGuid().ToString('N').Substring(0, 8))
}
New-Item -ItemType Directory -Path $WorkDir -Force | Out-Null
$Enc = [Text.Encoding]::ASCII
function J([string[]]$l) { ($l -join "`r`n") + "`r`n" }

# --- fixture: a REAL VCL form project ---------------------------------------
$dpr = J 'program GhostF;', '', 'uses', '  Vcl.Forms,', "  uForm in 'uForm.pas' {Form1};", '', '{$R *.res}', '',
         'begin', '  Application.Initialize;', '  Application.CreateForm(TForm1, Form1);', '  Application.Run;', 'end.'
$pas = J 'unit uForm;', '', 'interface', '', 'uses', '  System.Classes, Vcl.Forms, Vcl.StdCtrls;', '', 'type',
         '  TForm1 = class(TForm)', '    Edit1: TEdit;', '  private', '    function ReadIt: string;', '  end;', '',
         'var', '  Form1: TForm1;', '', 'implementation', '', '{$R *.dfm}', '', 'function TForm1.ReadIt: string;',
         'begin', '  Result := Edit1.Text;', 'end;', '', 'end.'
$dfm = J 'object Form1: TForm1', '  Left = 0', '  Top = 0', "  Caption = 'Form1'", '  ClientHeight = 100', '  ClientWidth = 200',
         '  object Edit1: TEdit', '    Left = 8', '    Top = 8', '    Width = 121', '    Height = 21', '    TabOrder = 0',
         '  end', 'end'
$realPas  = Join-Path $WorkDir 'uForm.pas'
$realDfm  = Join-Path $WorkDir 'uForm.dfm'
[IO.File]::WriteAllText((Join-Path $WorkDir 'GhostF.dpr'), $dpr, $Enc)
[IO.File]::WriteAllText($realPas, $pas, $Enc)
[IO.File]::WriteAllText($realDfm, $dfm, $Enc)
[IO.File]::WriteAllText((Join-Path $WorkDir 'GhostF.dproj'), @"
<Project xmlns="http://schemas.microsoft.com/developer/msbuild/2003">
  <PropertyGroup><MainSource>GhostF.dpr</MainSource><DCC_DcuOutput>.\`$(Platform)\`$(Config)\DCU</DCC_DcuOutput></PropertyGroup>
  <ItemGroup><DCCReference Include="uForm.pas"><Form>Form1</Form></DCCReference></ItemGroup>
</Project>
"@, $Enc)
$dprojPath = Join-Path $WorkDir 'GhostF.dproj'

# overlays: dfm-only (Edit1 object removed), pas-deleted (field removed, body still uses Edit1)
$ovDfm = Join-Path $WorkDir 'dfm-only.dfm'
$ovPas = Join-Path $WorkDir 'pas-deleted.pas'
[IO.File]::WriteAllText($ovDfm, ($dfm -replace '(?s)  object Edit1.*?  end\r\n', ''), $Enc)
[IO.File]::WriteAllText($ovPas, $pas.Replace("    Edit1: TEdit;`r`n", ''), $Enc)
Check 'overlay dfm-only really lacks Edit1' ((Get-Content $ovDfm -Raw) -notmatch 'Edit1') ''
Check 'overlay pas-deleted really lacks the field but still reads Edit1.Text' `
  (((Get-Content $ovPas -Raw) -notmatch 'Edit1: TEdit') -and ((Get-Content $ovPas -Raw) -match 'Edit1\.Text')) ''

function Get-Stamp([string]$p) {
  $fi = Get-Item -LiteralPath $p
  [pscustomobject]@{ Sha = (Get-FileHash -LiteralPath $p -Algorithm SHA256).Hash; Ft = $fi.LastWriteTimeUtc.ToFileTimeUtc() }
}
$s0Pas = Get-Stamp $realPas
$s0Dfm = Get-Stamp $realDfm

function Invoke-Case([string]$Tag, [string[]]$Pairs) {
  $m = Join-Path $WorkDir "$Tag.txt"
  [IO.File]::WriteAllText($m, (($Pairs | ForEach-Object { $_ }) -join "`r`n") + "`r`n", $Enc)
  $out = Join-Path $WorkDir "$Tag.out"
  $p = Start-Process $exePath -ArgumentList @('ghost-check', $dprojPath, '--overlays', $m, '--platform', 'win64', '--format', 'json') `
         -WorkingDirectory $WorkDir -NoNewWindow -PassThru -Wait -RedirectStandardOutput $out -RedirectStandardError "$out.err"
  $raw = Get-Content -LiteralPath $out -Raw
  $json = if ($raw -match '(?s)(\[.*\])') { $Matches[1] } else { '[]' }
  $items = @($json | ConvertFrom-Json)
  [pscustomobject]@{ Items = $items; Errors = @($items | Where-Object { $_.severity -eq 'Error' }); Raw = $raw; Exit = $p.ExitCode }
}
function Check-Untouched([string]$Tag) {
  $p = Get-Stamp $realPas; $d = Get-Stamp $realDfm
  Check "$Tag D: real .pas byte- and FILETIME-exact" (($p.Sha -eq $s0Pas.Sha) -and ($p.Ft -eq $s0Pas.Ft)) ''
  Check "$Tag D: real .dfm byte- and FILETIME-exact" (($d.Sha -eq $s0Dfm.Sha) -and ($d.Ft -eq $s0Dfm.Ft)) ''
  # The engine creates an EMPTY _D-RAG dir (observed 2026-10-23); the contract is that it holds no FILES (no journal/backup).
  Check "$Tag D: no file appeared under _D-RAG (an empty dir is tolerated)" (@(Get-ChildItem -LiteralPath (Join-Path $WorkDir '_D-RAG') -Recurse -File -Force -ErrorAction SilentlyContinue).Count -eq 0) ''
}

Write-Host ''
Write-Host 'CASE A -- .dfm overlay ALONE: the compiler does not cross-check, NO error (caveat pinned)' -ForegroundColor Cyan
$ra = Invoke-Case 'A' @("$realDfm`t$ovDfm")
Check 'A: no Error reported (if one appears the contract changed: update the plugin plan)' ($ra.Errors.Count -eq 0) $ra.Raw
Check-Untouched 'A'

Write-Host ''
Write-Host 'CASE B -- .dfm + .pas overlays: E2003 naming Edit1 IS reported (FIRING control)' -ForegroundColor Cyan
$rb = Invoke-Case 'B' @("$realDfm`t$ovDfm", "$realPas`t$ovPas")
$e = @($rb.Errors | Where-Object { $_.code -eq 'E2003' -and $_.message -match 'Edit1' })
Check 'B: an E2003 Undeclared identifier naming Edit1 is reported' ($e.Count -ge 1) $rb.Raw
Check 'B: it is located in uForm.pas' (($e.Count -ge 1) -and ($e[0].file -like '*uForm.pas')) ''
Check 'B: the compiler really ran on this fixture (a compiler hint is also present)' `
  (@($rb.Items | Where-Object { $_.code -match '^H' }).Count -ge 1) 'proves C below is not vacuous'
Check-Untouched 'B'

Write-Host ''
Write-Host 'CASE C -- unmodified .dfm + .pas as overlays: clean (silence pair for B)' -ForegroundColor Cyan
$rc = Invoke-Case 'C' @("$realDfm`t$realDfm", "$realPas`t$realPas")
Check 'C: no Error reported' ($rc.Errors.Count -eq 0) $rc.Raw
Check-Untouched 'C'

try { [IO.Directory]::Delete($WorkDir, $true) } catch { }

Write-Host ''
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }