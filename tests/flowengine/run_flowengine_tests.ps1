# Build + run the M2 flow-engine unit tests with a bare dcc64 (Win64) under the
# Embarcadero env. The exe parses real .pas via tree-sitter, so the two native
# DLLs (third_party\dll-win64) are prepended to PATH before the exe runs.
$rs   = 'C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\rsvars.bat'
$dir  = $PSScriptRoot
$root = (Resolve-Path (Join-Path $dir '..\..')).Path
$dll  = Join-Path $root 'third_party\dll-win64'

$ns  = 'System;Xml;Data;Datasnap;Web;Soap;Winapi;System.Win'
$out = cmd /c "call `"$rs`" && cd /d `"$dir`" && dcc64 -B -NS$ns -E`"$dir`" `"$dir\FlowEngineTests.dpr`"" 2>&1
$err = $out | Select-String -Pattern "\bError\b|E2\d{3}|F2\d{3}|Fatal"
if ($err) { Write-Host "BUILD FAILED:"; $err | Select-Object -First 20; exit 1 }

$env:PATH = "$dll;$env:PATH"
& "$dir\FlowEngineTests.exe"
exit $LASTEXITCODE
