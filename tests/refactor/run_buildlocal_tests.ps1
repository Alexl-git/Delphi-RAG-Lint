# Build + run the BuildLocal console tests (bare dcc64, Win64). Needs the
# tree-sitter-delphi13 DLL on PATH -- copy it next to the exe.
# -U must list every dir in the transitive uses-closure: src\core's
# DRagLint.Core.Interfaces has used DRagLint.Preprocess.Types since 211b235
# ("wire preprocess into the indexer"), so src\preprocess is not optional --
# leaving it out is an F2613 at Core.Interfaces.pas(8), not a code defect.
$rs  = 'C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\rsvars.bat'
$dir = $PSScriptRoot
$repo = (Resolve-Path (Join-Path $dir "..\..")).Path
$out = cmd /c "call `"$rs`" && cd /d `"$dir`" && dcc64 -B -NSSystem -E`"$dir`" -U`"$repo\src\core;$repo\src\diagnostics;$repo\src\refactor;$repo\src\parser;$repo\src\preprocess;$repo\third_party\delphi-tree-sitter`" `"$dir\BuildLocalTests.dpr`"" 2>&1
$err = $out | Select-String -Pattern "\bError\b|E2\d{3}|F2\d{3}|Fatal"
if ($err) { Write-Host "BUILD FAILED:"; $err | Select-Object -First 12; exit 1 }
Copy-Item "$repo\third_party\dll-win64\tree-sitter-delphi13.dll" $dir -Force
Copy-Item "$repo\third_party\dll-win64\tree-sitter.dll" $dir -Force -ErrorAction SilentlyContinue
& "$dir\BuildLocalTests.exe"
exit $LASTEXITCODE
