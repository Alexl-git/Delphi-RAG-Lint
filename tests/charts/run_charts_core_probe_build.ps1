<#
  run_charts_core_probe_build.ps1 -- build tests\charts\ChartsCoreProbe.dpr with dcc64 into
  charts\scratch\probe\ (scratch, not committed). Used by charts\src\Test-Parity.ps1 -Mode Core.

  The unit search path and namespaces are READ from src\cli\drag-lint.dproj through
  tests\autotest\lib\CliBuildPaths.ps1, so they cannot drift from the engine's own; the
  tree-sitter DLLs are staged beside the exe (units the probe pulls in import them implicitly).

  Usage: pwsh -File tests\charts\run_charts_core_probe_build.ps1 [-OutDir <folder>]
  Exit:  0 built (prints the exe path), 2 build failure.
#>
[CmdletBinding()]
param(
  [string]$Dpr    = "$PSScriptRoot\ChartsCoreProbe.dpr",
  [string]$OutDir = "$PSScriptRoot\..\..\charts\scratch\probe"
)
try {
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '..\autotest\lib\CliBuildPaths.ps1')

if (-not (Test-Path -LiteralPath $Dpr)) { Write-Host "FATAL: dpr not found: $Dpr" -ForegroundColor Red; exit 2 }
$Dpr    = (Resolve-Path -LiteralPath $Dpr).Path
$DprDir = Split-Path $Dpr -Parent
New-Item -ItemType Directory -Force $OutDir | Out-Null
$OutDir = (Resolve-Path -LiteralPath $OutDir).Path
$DcuDir = Join-Path $OutDir 'dcu'
New-Item -ItemType Directory -Force $DcuDir | Out-Null

$rs = 'C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\rsvars.bat'
if (-not (Test-Path -LiteralPath $rs)) { Write-Host "FATAL: rsvars not found: $rs" -ForegroundColor Red; exit 2 }

$cli = Get-CliDcc64Args
$bat = Join-Path $OutDir 'build.bat'
$lines = @(
  '@echo off',
  ('call "{0}"' -f $rs),
  ('cd /d "{0}"' -f $DprDir),
  ('dcc64 -B -NU"{1}" -E"{0}" {3} {4} {2}' -f $OutDir, $DcuDir, (Split-Path $Dpr -Leaf), $cli.UArg, $cli.NSArg),
  'echo BUILD_EXITCODE=%ERRORLEVEL%'
)
[IO.File]::WriteAllText($bat, (($lines -join "`r`n") + "`r`n"), [Text.Encoding]::ASCII)

$log = Join-Path $OutDir 'build.log'
$null = Start-Process cmd.exe -ArgumentList '/c', "`"$bat`"" -RedirectStandardOutput $log -RedirectStandardError "$log.err" -NoNewWindow -Wait -PassThru
$out = Get-Content -LiteralPath $log -Raw
if ($out -notmatch 'BUILD_EXITCODE=0') { Write-Host 'FATAL: probe compile failed' -ForegroundColor Red; Write-Host $out; exit 2 }

$exe = Join-Path $OutDir 'ChartsCoreProbe.exe'
if (-not (Test-Path -LiteralPath $exe)) { Write-Host "FATAL: exe not produced: $exe" -ForegroundColor Red; exit 2 }
$null = Copy-TreeSitterDlls -Dest $OutDir
Write-Output $exe
exit 0
} catch {
  Write-Host "FATAL: $($_.Exception.Message)" -ForegroundColor Red
  exit 2
}
