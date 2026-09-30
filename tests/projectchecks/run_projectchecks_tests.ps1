# v0.65: build + run the project-membership parser/normalizer unit tests.
# Mirrors tests\searchparse\run_searchparse_tests.ps1: a bare dcc64 build of a
# console DUnit-free test program, then run it and propagate its exit code.
$rs = 'C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\rsvars.bat'
$dir = $PSScriptRoot
# Private DCU dir (-NU): a bare dcc64 writes each unit's DCU beside its source, i.e. under src\, where a battery-parallel run_legacy_cli_fixtures sees it.
New-Item -ItemType Directory -Force (Join-Path $dir '_dcu') | Out-Null
$out = cmd /c "call `"$rs`" && cd /d `"$dir`" && dcc64 -B -NU`"$dir\_dcu`" -E`"$dir`" `"$dir\ProjectChecksTests.dpr`"" 2>&1
$err = $out | Select-String -Pattern "\bError\b|E2\d{3}|F2\d{3}|Fatal"
if ($err) { Write-Host "BUILD FAILED:"; $err | Select-Object -First 10; exit 1 }
& "$dir\ProjectChecksTests.exe"
exit $LASTEXITCODE
