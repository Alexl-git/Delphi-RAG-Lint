$ErrorActionPreference='Stop'
$proj = "$PSScriptRoot\..\..\src\config\drag-lint-config.dproj"
$rs = 'C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\rsvars.bat'
cmd /c "call `"$rs`" && msbuild /t:Build /p:Config=Debug /p:Platform=Win64 `"$proj`"" | Out-Null
if ($LASTEXITCODE -ne 0) { Write-Host 'FAIL: build' -ForegroundColor Red; exit 1 }
$exe = Get-ChildItem "$PSScriptRoot\..\..\src\config" -Recurse -Filter drag-lint-config.exe | Select-Object -First 1
if (-not $exe) { Write-Host 'FAIL: no exe' -ForegroundColor Red; exit 1 }
$v = & $exe.FullName --version 2>&1 | Out-String
if ($v -match 'drag-lint-config') { Write-Host "PASS ($($v.Trim()))" -ForegroundColor Green; exit 0 } else { Write-Host "FAIL: --version => $v" -ForegroundColor Red; exit 1 }
