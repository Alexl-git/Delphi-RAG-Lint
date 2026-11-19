<#
  run_v152_GH15.ps1 -- GitHub #15: `context` on a form event handler listed the DFM binding of EVERY
  form whose DFM says `OnShow = FormShow`, matched by handler name only.
  Fixture: TFormA / TFormB (unrelated, both TForm) and TFormA2 = class(TFormA) with an inherited DFM.
  1. context FormA.TFormA.FormShow lists FormA.dfm and FormA2.dfm (a descendant), NOT FormB.dfm.
  2. context FormB.TFormB.FormShow lists FormB.dfm only.
  3. control: a DFM whose root class the index does not know is kept (cannot tell = keep).
  Run from a NEUTRAL CWD, pwsh 7.
#>
[CmdletBinding()]
param([string]$Exe = '')
# Defaults that need the script path are resolved HERE, not in param(): Windows PowerShell 5 run with
# -File leaves $PSScriptRoot/$MyInvocation empty inside an advanced script's param block (Repo became C:\).
if (-not $Exe) { $Exe = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe" }
$ErrorActionPreference = 'Stop'
$script:fail = $false
function Check($n, $ok, $d) {
  Write-Host ("[{0}] {1}" -f (@('FAIL', 'PASS')[[int][bool]$ok]), $n)
  if (-not $ok) { if ($d) { Write-Host "      $d" }; $script:fail = $true }
}
$exe = (Resolve-Path $Exe).Path
$work = Join-Path ([IO.Path]::GetTempPath()) ("dl_gh15_" + [guid]::NewGuid().ToString('N').Substring(0, 8))
$fx = Join-Path $work 'fx'
[void][IO.Directory]::CreateDirectory($fx)
function W($n, $t) { [IO.File]::WriteAllText((Join-Path $fx $n), ($t -replace "`r?`n", "`r`n"), [Text.Encoding]::ASCII) }
foreach ($x in 'A', 'B') {
  W "Form$x.pas" @"
unit Form$x;
interface
uses Forms;
type
  TForm$x = class(TForm)
    procedure FormShow(Sender: TObject);
  end;
implementation
{`$R *.dfm}
procedure TForm$x.FormShow(Sender: TObject); begin end;
end.
"@
  W "Form$x.dfm" @"
object Form${x}: TForm$x
  Left = 0
  Top = 0
  Caption = 'Form$x'
  OnShow = FormShow
end
"@
}
W 'FormA2.pas' @'
unit FormA2;
interface
uses Forms, FormA;
type
  TFormA2 = class(TFormA)
  end;
implementation
{$R *.dfm}
end.
'@
W 'FormA2.dfm' @'
inherited FormA2: TFormA2
  Caption = 'FormA2'
  OnShow = FormShow
end
'@
# a DFM with no matching unit in the index: its root class is unknown, so it must be kept
W 'Orphan.dfm' @'
object Orphan: TOrphanForm
  Caption = 'Orphan'
  OnShow = FormShow
end
'@
$db = Join-Path $work 'fx.sqlite'
Push-Location $work
try {
  & { $ErrorActionPreference = 'Continue'; & $exe index $fx --db $db *> $null }
  Check 'fixture indexed' ($LASTEXITCODE -eq 0 -and (Test-Path $db)) "exit $LASTEXITCODE"

  $a = (& { $ErrorActionPreference = 'Continue'; & $exe context --task "modify FormA.TFormA.FormShow" --format md --max-callers 20 --db $db 2>&1 | ForEach-Object { "$_" } } | Out-String)
  $callersA = ([regex]::Matches($a, '(?m)^- .*?\\(\w+)\.dfm:') | ForEach-Object { $_.Groups[1].Value }) -join ','
  Check 'TFormA.FormShow: FormA.dfm listed' ($callersA -match '\bFormA\b') $callersA
  Check 'TFormA.FormShow: FormA2.dfm (descendant) listed' ($callersA -match '\bFormA2\b') $callersA
  Check 'TFormA.FormShow: FormB.dfm NOT listed' ($callersA -notmatch '\bFormB\b') $callersA
  Check 'control: unknown root class (Orphan.dfm) kept' ($callersA -match '\bOrphan\b') $callersA

  $b = (& { $ErrorActionPreference = 'Continue'; & $exe context --task "modify FormB.TFormB.FormShow" --format md --max-callers 20 --db $db 2>&1 | ForEach-Object { "$_" } } | Out-String)
  $callersB = ([regex]::Matches($b, '(?m)^- .*?\\(\w+)\.dfm:') | ForEach-Object { $_.Groups[1].Value }) -join ','
  Check 'TFormB.FormShow: FormB.dfm listed, FormA / FormA2 not' (($callersB -match '\bFormB\b') -and ($callersB -notmatch '\bFormA2?\b')) $callersB
}
finally {
  Pop-Location
  try { [IO.Directory]::Delete($work, $true) } catch { }
}
if ($script:fail) { Write-Host 'FAIL'; exit 1 }
Write-Host 'PASS'; exit 0
