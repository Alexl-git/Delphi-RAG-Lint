# Build + run the M2 flow-engine unit tests with a bare dcc64 (Win64) under the
# Embarcadero env. The exe parses real .pas via tree-sitter, so the two native
# DLLs (third_party\dll-win64) are prepended to PATH before the exe runs.
$rs   = 'C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\rsvars.bat'
$dir  = $PSScriptRoot
$root = (Resolve-Path (Join-Path $dir '..\..')).Path
$dll  = Join-Path $root 'third_party\dll-win64'

$ns  = 'System;Xml;Data;Datasnap;Web;Soap;Winapi;System.Win'

# UNIT SEARCH PATH, added 2026-08-31. FlowEngineTests.dpr names each unit with an
# explicit `in '...'` path, which works only while every unit it TRANSITIVELY
# reaches is also named there. f1a7973 added `DRagLint.Preprocess` and
# `DRagLint.Preprocess.Types` to DRagLint.Diagnostics.ParseCache's INTERFACE
# uses -- the lint walk now preprocesses -- and this runner went red with
# `F2613 Unit not found` at ParseCache.pas(7). It stayed red because the battery
# scheduled that night never ran.
#
# A search path is the right fix rather than chasing the closure into the .dpr:
# the next unit the engine adds to a shared dependency would break this again,
# and the .dpr's job is to name the test's OWN units, not to mirror the engine's
# internal graph. src\preprocess also brings Lexer/Expr/Tolerance, which are
# reached only from implementation sections.
$usp = @(
  '..\..\src\preprocess'
  '..\..\src\core'
  '..\..\src\analysis'
  '..\..\src\diagnostics'
  '..\..\third_party\delphi-tree-sitter'
) -join ';'
$out = cmd /c "call `"$rs`" && cd /d `"$dir`" && dcc64 -B -NS$ns -U`"$usp`" -E`"$dir`" `"$dir\FlowEngineTests.dpr`"" 2>&1
$err = $out | Select-String -Pattern "\bError\b|E2\d{3}|F2\d{3}|Fatal"
if ($err) { Write-Host "BUILD FAILED:"; $err | Select-Object -First 20; exit 1 }

$env:PATH = "$dll;$env:PATH"
& "$dir\FlowEngineTests.exe"
exit $LASTEXITCODE
