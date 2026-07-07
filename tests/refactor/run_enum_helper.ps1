# EnumHelper RESOLVE stage: build + run EnumHelperTests.dpr against three
# fixture DBs, each built by the real drag-lint exe (so Members ordering and
# EnumEndLine/EnumEndCol come from real parse positions, and HasHelper comes
# from a real ResolveHelpers pass -- see StorageHelperEdgesTests.dpr for the
# hand-built-row alternative used elsewhere; this refactoring needs the real
# parser). Task 2 covers RESOLVE only; GENERATE/PLACE fixtures + assertions
# are added by later tasks on this same script.
[CmdletBinding()]
param(
    [string] $Exe = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe",
    [string] $WorkDir = "$env:TEMP\drag-lint-enumhelper"
)
$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
$exe  = (Resolve-Path $Exe).Path
$dir  = Join-Path $PSScriptRoot "fixtures\enumhelper"

if (-not (Test-Path $exe)) { Write-Host "FATAL: exe not found: $exe" -ForegroundColor Red; exit 2 }
if (Test-Path $WorkDir) { Remove-Item -Recurse -Force $WorkDir }
New-Item -ItemType Directory $WorkDir | Out-Null

# --- 1. simple.pas: enum with no helper, no descriptions array ---
$dbSimple = Join-Path $WorkDir "simple.sqlite"
$out1 = & $exe index (Join-Path $dir "simple.pas") --db $dbSimple 2>&1
if ($LASTEXITCODE -ne 0) { Write-Host "FAIL: index simple.pas"; Write-Host $out1; exit 1 }

# --- 2. already_has_helper.pas: enum + its helper + descriptions, same unit ---
$dbAlready = Join-Path $WorkDir "already.sqlite"
$out2 = & $exe index (Join-Path $dir "already_has_helper.pas") --db $dbAlready 2>&1
if ($LASTEXITCODE -ne 0) { Write-Host "FAIL: index already_has_helper.pas"; Write-Host $out2; exit 1 }

# --- 3. separate-unit case: Mode.pas (enum) + ModeHelperUnit.pas (helper) ---
$sepSrc = Join-Path $WorkDir "separate_src"
New-Item -ItemType Directory $sepSrc | Out-Null
Copy-Item (Join-Path $dir "Mode.pas") $sepSrc
Copy-Item (Join-Path $dir "ModeHelperUnit.pas") $sepSrc
$dbSeparate = Join-Path $WorkDir "separate.sqlite"
$out3 = & $exe index $sepSrc --db $dbSeparate 2>&1
if ($LASTEXITCODE -ne 0) { Write-Host "FAIL: index separate-unit fixtures"; Write-Host $out3; exit 1 }

# --- build the DUnitX-style console test ---
$rs = 'C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\rsvars.bat'
$searchPath = "$repo\src\core;$repo\src\storage;$repo\src\query;$repo\src\index;$repo\src\preprocess;$repo\src\refactor"
$buildOut = cmd /c "call `"$rs`" && cd /d `"$PSScriptRoot`" && dcc64 -B -NSSystem -E`"$PSScriptRoot`" -U`"$searchPath`" `"$PSScriptRoot\EnumHelperTests.dpr`"" 2>&1
$err = $buildOut | Select-String -Pattern "\bError\b|E2\d{3}|F2\d{3}|Fatal"
if ($err) { Write-Host "BUILD FAILED:"; $err | Select-Object -First 12; exit 1 }

& "$PSScriptRoot\EnumHelperTests.exe" $dbSimple $dbAlready $dbSeparate
exit $LASTEXITCODE
