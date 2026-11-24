<#
  run_shared_unit_addproject.ps1 -- TSharedUnit.AddProject must return the edited text (the same variable was the const AText and the out ANewText).
  Builds and runs tests\SharedUnitAddProjectTests.dpr over src\lint + src\core. Usage: pwsh -File tests\autotest\run_shared_unit_addproject.ps1
#>
[CmdletBinding()]
param([string]$WorkDir = "$env:TEMP\drag-lint-sharedadd-$PID")
$ErrorActionPreference = 'Stop'
$Repo = (Resolve-Path "$PSScriptRoot\..\..").Path
$rs = 'C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\rsvars.bat'
if (-not (Test-Path $rs)) { Write-Host "FATAL: rsvars not found: $rs" -ForegroundColor Red; exit 2 }
if (Test-Path $WorkDir) { [IO.Directory]::Delete($WorkDir, $true) }
$dcu = Join-Path $WorkDir 'dcu'
[void][IO.Directory]::CreateDirectory($dcu)
$bat = Join-Path $WorkDir 'build.bat'
$lines = @('@echo off', ('call "{0}"' -f $rs), ('cd /d "{0}\tests"' -f $Repo),
           ('dcc64 -B -Q -E"{0}" -N0"{1}" -U"{2}\src\lint;{2}\src\core" SharedUnitAddProjectTests.dpr' -f $WorkDir, $dcu, $Repo),
           'echo BUILD_EXITCODE=%ERRORLEVEL%')
[IO.File]::WriteAllText($bat, (($lines -join "`r`n") + "`r`n"), [Text.Encoding]::ASCII)
$log = Join-Path $WorkDir 'build.log'
[void](Start-Process cmd.exe -ArgumentList '/c', "`"$bat`"" -RedirectStandardOutput $log -RedirectStandardError "$log.err" -NoNewWindow -Wait -PassThru)
$b = Get-Content $log -Raw
if ($b -notmatch 'BUILD_EXITCODE=0') { Write-Host $b; Write-Host 'FATAL: compile failed' -ForegroundColor Red; exit 2 }
$r = & { $ErrorActionPreference = 'Continue'; & (Join-Path $WorkDir 'SharedUnitAddProjectTests.exe') 2>&1 | ForEach-Object { "$_" } } | Out-String
$rc = $LASTEXITCODE
Write-Host $r.TrimEnd()
if ($rc -ne 0) { Write-Host "FAILED: exit $rc" -ForegroundColor Red; exit 1 }
Write-Host 'PASSED'
