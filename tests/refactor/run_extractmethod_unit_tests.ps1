# Build + run the Extract Method console tests (bare dcc64, Win64). Needs the
# tree-sitter-delphi13 DLL on PATH -- copy it next to the exe.
$rs  = 'C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\rsvars.bat'
$dir = $PSScriptRoot
$repo = (Resolve-Path (Join-Path $dir "..\..")).Path
$out = cmd /c "call `"$rs`" && cd /d `"$dir`" && dcc64 -B -NSSystem -E`"$dir`" -U`"$repo\src\core;$repo\src\diagnostics;$repo\src\refactor;$repo\src\parser;$repo\src\analysis;$repo\third_party\delphi-tree-sitter`" `"$dir\ExtractMethodTests.dpr`"" 2>&1
$err = $out | Select-String -Pattern "\bError\b|E2\d{3}|F2\d{3}|Fatal"
if ($err) { Write-Host "BUILD FAILED:"; $err | Select-Object -First 12; exit 1 }
Copy-Item "$repo\third_party\dll-win64\tree-sitter-delphi13.dll" $dir -Force
Copy-Item "$repo\third_party\dll-win64\tree-sitter.dll" $dir -Force -ErrorAction SilentlyContinue
& "$dir\ExtractMethodTests.exe"
exit $LASTEXITCODE
