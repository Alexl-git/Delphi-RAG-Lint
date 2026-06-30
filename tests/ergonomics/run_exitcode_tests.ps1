# Build + run the --fail-on exit-code policy unit tests (bare dcc64, Win64).
$rs  = 'C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\rsvars.bat'
$dir = $PSScriptRoot
$out = cmd /c "call `"$rs`" && cd /d `"$dir`" && dcc64 -B -E`"$dir`" `"$dir\ExitCodeTests.dpr`"" 2>&1
$err = $out | Select-String -Pattern "\bError\b|E2\d{3}|F2\d{3}|Fatal"
if ($err) { Write-Host "BUILD FAILED:"; $err | Select-Object -First 10; exit 1 }
& "$dir\ExitCodeTests.exe"
exit $LASTEXITCODE
