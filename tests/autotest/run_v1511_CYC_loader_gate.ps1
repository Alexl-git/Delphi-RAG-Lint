# run_v1511_CYC_loader_gate.ps1 -- lane v1511 CYC (T06), acceptance on a real application: `cycles --fix --hub-surface
# --apply` on a COPY of the Loader2019 sources (the I10 proof tree, 78-unit hub group) goes through the compile gate.
#
#   l0  dry run (--no-compile): exit 0, R3 plans group 1, 76 spokes, the group breaks, mechanical   (RED on 1.51.0: exit 2)
#   l1  --apply: exit 0; build 1 (`baseline build -- started`) and build 2 (`build after the edit -- started`) on stderr
#   l2  `Applied: ... compile ok`, the new Loader2019.Main.Hub.pas exists
#   l3  re-indexed: `Verified: the re-indexed cycles output matches the prediction`
#
# Needs: the pristine Loader copy (-LoaderSrc, default the I10 lane's), a platform library COPY (-LibraryDb), RAD Studio.
# Environment workarounds for building Loader2025 outside the IDE (I10 REPORT; no source file touched): Custom_Styles
# emptied in the COPY's .dproj, DCC_Namespace / DCC_UnitSearchPath through an --rsvars wrapper, the output folders made.
# SKIPs (exit 0) when the Loader copy, the library or rsvars.bat is missing. A run takes ~5 min (two full builds).
#
# Usage: pwsh -File run_v1511_CYC_loader_gate.ps1 -Exe <drag-lint.exe> -LibraryDb <library-Win32 COPY> [-WorkDir <dir>] [-KeepWorkDir]
param(
  [string]$Exe       = '',
  [string]$LoaderSrc = (Join-Path 'C:\' 'TEMP\claude\lanes\v151\I10\loader-base'),
  [string]$LibraryDb = '',
  [string]$WorkDir   = "$env:TEMP\drag-lint-v1511-cyc-loader-$PID",
  [string]$RsVars    = 'C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\rsvars.bat',
  [switch]$KeepWorkDir
)
# Defaults that need the script path are resolved HERE, not in param(): Windows PowerShell 5 run with
# -File leaves $PSScriptRoot/$MyInvocation empty inside an advanced script's param block (Repo became C:\).
if (-not $Exe) { $Exe = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe" }
$ErrorActionPreference = 'Stop'
$script:Failed = $false; $script:Passed = 0
function Check($n, $ok, $d = '') {
  $s = if ($ok) { 'PASS' } else { 'FAIL' }; $c = if ($ok) { 'Green' } else { 'Red' }
  Write-Host ("  [{0}] {1}" -f $s, $n) -ForegroundColor $c
  if ($ok) { $script:Passed++ } else { if ($d) { Write-Host "      $d" -ForegroundColor DarkGray }; $script:Failed = $true }
}
if (-not (Test-Path $RsVars)) { Write-Host "SKIP: no rsvars.bat ($RsVars)" -ForegroundColor Yellow; exit 0 }
if (-not (Test-Path (Join-Path $LoaderSrc 'Loader2025.dproj'))) { Write-Host "SKIP: no Loader copy at $LoaderSrc" -ForegroundColor Yellow; exit 0 }
if (($LibraryDb -eq '') -or -not (Test-Path $LibraryDb)) { Write-Host "SKIP: pass -LibraryDb <a COPY of library-Win32.sqlite>" -ForegroundColor Yellow; exit 0 }
if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
$Exe = (Resolve-Path $Exe).Path

New-Item -ItemType Directory -Force $WorkDir | Out-Null
try {
  $root = Join-Path $WorkDir 'loader'
  Copy-Item $LoaderSrc $root -Recurse
  $dproj = Join-Path $root 'Loader2025.dproj'
  $text = [IO.File]::ReadAllText($dproj)
  [IO.File]::WriteAllText($dproj, [regex]::Replace($text, '<Custom_Styles>.*?</Custom_Styles>', '<Custom_Styles></Custom_Styles>'), (New-Object Text.UTF8Encoding($true)))
  'DOC', 'DCU', 'EXE' | ForEach-Object { New-Item -ItemType Directory -Force (Join-Path $root "Win32\Debug\$_") | Out-Null }
  $wrap = Join-Path $WorkDir 'rsvars-loader.bat'
  $lines = @('@echo off', ('call "{0}"' -f $RsVars),
    'set DCC_Namespace=System.Win;Vcl.Imaging;Vcl.Touch;Vcl.Samples;Vcl.Shell;Web;Soap;Xml;Bde;Data.Win;Xml.Win',
    'set DCC_UnitSearchPath=C:\Projects\spring4d\Source')
  [IO.File]::WriteAllText($wrap, (($lines -join "`r`n") + "`r`n"), [Text.Encoding]::ASCII)
  $db = Join-Path $WorkDir 'loader.sqlite'
  Push-Location $WorkDir
  try {
    $null | & $Exe index --project $dproj --db $db --library-db $LibraryDb *> "$db.log"
    $common = @('cycles', '--fix', '--hub-surface', '--project', $dproj, '--db', $db, '--library-db', $LibraryDb, '--platform', 'win32', '--cycle', '1')
    $dry = ($null | & $Exe @common --no-compile --format text 2>$null | Out-String); $dryCode = $LASTEXITCODE
    $errFile = Join-Path $WorkDir 'apply.err'
    $app = ($null | & $Exe @common --apply --rsvars $wrap --build-timeout 1800 --format text 2> $errFile | Out-String); $appCode = $LASTEXITCODE
    $err = if (Test-Path $errFile) { [IO.File]::ReadAllText($errFile) } else { '' }
  } finally { Pop-Location }
  Check 'l0 dry run: R3 plans the 78-unit group, 76 spokes, the group breaks, mechanical   (RED on 1.51.0: exit 2)' (($dryCode -eq 0) -and
    $dry.Contains('## Group 1 (78 units): hub-surface recipe R3') -and ($dry -match '- spokes: 76 rewritten') -and
    $dry.Contains('- prediction: the group breaks') -and $dry.Contains('Verdict: mechanical')) "exit=$dryCode $dry"
  Check 'l1 --apply: exit 0, build 1 and build 2 both ran' (($appCode -eq 0) -and $err.Contains('baseline build -- started') -and
    $err.Contains('build after the edit -- started')) "exit=$appCode out=$app err=$err"
  Check 'l2 applied, compile ok, the new hub unit exists' (($app -match 'Applied: \d+ file\(s\) written, 1 new; compile ok') -and
    (Test-Path (Join-Path $root 'Loader2019.Main.Hub.pas'))) $app
  Check 'l3 re-indexed: the cycles output matches the prediction' ($app.Contains('Verified: the re-indexed `cycles` output matches the prediction')) $app
} finally {
  if (-not $KeepWorkDir) {
    Set-Location -LiteralPath $env:TEMP
    if (Test-Path -LiteralPath $WorkDir) { try { [IO.Directory]::Delete($WorkDir, $true) } catch { Write-Host "note: work dir not removed: $WorkDir" } }
  } else { Write-Host "work dir kept: $WorkDir" }
}
Write-Host ("{0} passed, failed={1}" -f $script:Passed, $script:Failed)
if ($script:Failed) { exit 1 } else { exit 0 }
