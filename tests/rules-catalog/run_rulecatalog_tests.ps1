# Build + run the rule-catalog console unit tests (bare dcc64, Win64).
$rs  = 'C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\rsvars.bat'
$dir = $PSScriptRoot
$src = Join-Path (Split-Path (Split-Path $dir)) 'src'
# -U: self-contained unit path (src\lint), so a clean tree without stale DCUs next to the sources compiles; DCUs go only to _dcu.
# Private DCU dir (-NU): a bare dcc64 writes each unit's DCU beside its source, i.e. under src\, where a battery-parallel run_legacy_cli_fixtures sees it.
New-Item -ItemType Directory -Force (Join-Path $dir '_dcu') | Out-Null
$out = cmd /c "call `"$rs`" && cd /d `"$dir`" && dcc64 -B -U`"$src\lint`" -I`"$src\lint`" -NU`"$dir\_dcu`" -E`"$dir`" `"$dir\RuleCatalogTests.dpr`"" 2>&1
$err = $out | Select-String -Pattern "\bError\b|E2\d{3}|F2\d{3}|Fatal"
if ($err) { Write-Host "BUILD FAILED:"; $err | Select-Object -First 10; exit 1 }
& "$dir\RuleCatalogTests.exe"
exit $LASTEXITCODE
