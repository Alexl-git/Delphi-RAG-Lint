# v0.65: build + run the project-membership parser/normalizer unit tests.
# Mirrors tests\searchparse\run_searchparse_tests.ps1: a bare dcc64 build of a
# console DUnit-free test program, then run it and propagate its exit code.
$rs = 'C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\rsvars.bat'
$dir = $PSScriptRoot
$out = cmd /c "call `"$rs`" && cd /d `"$dir`" && dcc64 -B -E`"$dir`" `"$dir\ProjectChecksTests.dpr`"" 2>&1
$err = $out | Select-String -Pattern "\bError\b|E2\d{3}|F2\d{3}|Fatal"
if ($err) { Write-Host "BUILD FAILED:"; $err | Select-Object -First 10; exit 1 }
& "$dir\ProjectChecksTests.exe"
exit $LASTEXITCODE
