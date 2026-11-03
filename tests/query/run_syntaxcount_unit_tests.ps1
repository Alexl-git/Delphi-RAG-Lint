# GAP-SYNTAXQ: build + run the syntax-count console tests (bare dcc64, Win64).
# Needs the tree-sitter DLLs next to the exe. -U lists the transitive uses-closure
# of DRagLint.Query.SyntaxCount (ParseCache -> core, preprocess; the verb -> storage).
$rs  = 'C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\rsvars.bat'
$dir = $PSScriptRoot
$repo = (Resolve-Path (Join-Path $dir "..\..")).Path
# Private DCU dir (-NU): a bare dcc64 would write DCUs beside the sources under src\.
New-Item -ItemType Directory -Force (Join-Path $dir '_dcu') | Out-Null
$units = @('core','diagnostics','parser','preprocess','query','storage','analysis','resolver','sql','config','doc','lint','output','index','project','context','refactor','report','workspace','forms','charts','mcp','lsp','cli','tools') | ForEach-Object { Join-Path $repo "src\$_" }
$units += Join-Path $repo 'third_party\delphi-tree-sitter'
$u = ($units -join ';')
$out = cmd /c "call `"$rs`" && cd /d `"$dir`" && dcc64 -B -NU`"$dir\_dcu`" -NSSystem;Winapi;System.Win;Data;Data.Win;FireDAC -E`"$dir`" -U`"$u`" `"$dir\SyntaxCountTests.dpr`"" 2>&1
$err = $out | Select-String -Pattern "\bError\b|E2\d{3}|F2\d{3}|Fatal"
if ($err) { Write-Host "BUILD FAILED:"; $err | Select-Object -First 12; exit 1 }
Copy-Item "$repo\third_party\dll-win64\tree-sitter-delphi13.dll" $dir -Force
Copy-Item "$repo\third_party\dll-win64\tree-sitter.dll" $dir -Force -ErrorAction SilentlyContinue
& "$dir\SyntaxCountTests.exe"
exit $LASTEXITCODE