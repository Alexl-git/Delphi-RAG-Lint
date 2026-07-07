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

# --- 4. (Task 4) interface_only.pas: enum in interface, EMPTY implementation ---
$dbIfaceOnly = Join-Path $WorkDir "interface_only.sqlite"
$out4 = & $exe index (Join-Path $dir "interface_only.pas") --db $dbIfaceOnly 2>&1
if ($LASTEXITCODE -ne 0) { Write-Host "FAIL: index interface_only.pas"; Write-Host $out4; exit 1 }

# --- 5. (Task 4) no_impl_fragment.pas: enum, NO 'implementation' keyword at all ---
$dbNoImpl = Join-Path $WorkDir "no_impl.sqlite"
$out5 = & $exe index (Join-Path $dir "no_impl_fragment.pas") --db $dbNoImpl 2>&1
if ($LASTEXITCODE -ne 0) { Write-Host "FAIL: index no_impl_fragment.pas"; Write-Host $out5; exit 1 }

# --- build the DUnitX-style console test ---
$rs = 'C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\rsvars.bat'
$searchPath = "$repo\src\core;$repo\src\storage;$repo\src\query;$repo\src\index;$repo\src\preprocess;$repo\src\refactor"
$buildOut = cmd /c "call `"$rs`" && cd /d `"$PSScriptRoot`" && dcc64 -B -NSSystem -E`"$PSScriptRoot`" -U`"$searchPath`" `"$PSScriptRoot\EnumHelperTests.dpr`"" 2>&1
$err = $buildOut | Select-String -Pattern "\bError\b|E2\d{3}|F2\d{3}|Fatal"
if ($err) { Write-Host "BUILD FAILED:"; $err | Select-Object -First 12; exit 1 }

& "$PSScriptRoot\EnumHelperTests.exe" $dbSimple $dbAlready $dbSeparate $dbIfaceOnly $dbNoImpl
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

# =====================================================================
# Task 5: CLI verbs `create-enum-helper` + `helpers-of` (e2e, dry-run/
# json/apply/idempotent/refuse/usage), mirroring run_extract_method.ps1's
# Test-Compiles dcc64 gate + Assert helper.
# =====================================================================
$fail = 0
function Assert($n,$c){ if($c){Write-Host "PASS  $n"}else{Write-Host "FAIL  $n" -ForegroundColor Red;$script:fail++} }

function Test-Compiles($PasFile) {
    $rs = 'C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\rsvars.bat'
    $fileDir = Split-Path -Parent $PasFile
    $out = cmd /c "call `"$rs`" && cd /d `"$fileDir`" && dcc64 -B `"$PasFile`"" 2>&1
    $err = $out | Select-String -Pattern "\bError\b|E2\d{3}|F2\d{3}|Fatal"
    return -not $err
}

# ----- create-enum-helper --json: action=built, edits count -----
$json1 = & $exe create-enum-helper --qname TColor --db $dbSimple --json 2>$null | ConvertFrom-Json
Assert "create-enum-helper json: action=built"      ($json1.action -eq 'built')
Assert "create-enum-helper json: qname/file present" ($json1.qname -eq 'TColor' -and $null -ne $json1.file)
Assert "create-enum-helper json: edits count = 2"    ($json1.edits -eq 2)
Assert "create-enum-helper json: applied=false (no --apply)" ($json1.applied -eq $false)

# ----- dry-run (no --json): preview shows the helper decl -----
$dry1 = (& $exe create-enum-helper --qname TColor --db $dbSimple 2>$null) -join "`n"
Assert "create-enum-helper dry-run mentions TColorHelper" ($dry1 -match 'TColorHelper')

# ----- --apply --no-backup: writes into a temp copy; result compiles (dcc64) -----
$applyDir = Join-Path $WorkDir "apply_simple"
New-Item -ItemType Directory $applyDir | Out-Null
Copy-Item (Join-Path $dir "simple.pas") $applyDir
$applyPas = Join-Path $applyDir "simple.pas"
$dbApply  = Join-Path $WorkDir "apply_simple.sqlite"
& $exe index $applyPas --db $dbApply 2>&1 | Out-Null
& $exe create-enum-helper --qname TColor --db $dbApply --apply --no-backup 2>$null | Out-Null
Assert "create-enum-helper apply: exit 0" ($LASTEXITCODE -eq 0)
$appliedSrc = Get-Content $applyPas -Raw
Assert "create-enum-helper apply: decl inserted"  ($appliedSrc -match 'TColorHelper = record helper for TColor')
Assert "create-enum-helper apply: no .bak written with --no-backup" (-not (Test-Path "$applyPas.bak"))
Assert "create-enum-helper apply result compiles (dcc64)" (Test-Compiles $applyPas)

# ----- idempotency: reindex the applied file, run again -> action=exists, NO change -----
& $exe index $applyPas --db $dbApply 2>&1 | Out-Null
$beforeSecondRun = Get-Content $applyPas -Raw
$json2 = & $exe create-enum-helper --qname TColor --db $dbApply --apply --no-backup --json 2>$null | ConvertFrom-Json
Assert "idempotent 2nd run: action=exists"   ($json2.action -eq 'exists')
Assert "idempotent 2nd run: applied=false"   ($json2.applied -eq $false)
Assert "idempotent 2nd run: nonzero exit"    ($LASTEXITCODE -ne 0)
$afterSecondRun = Get-Content $applyPas -Raw
Assert "idempotent 2nd run: file byte-identical (no change)" ($afterSecondRun -ceq $beforeSecondRun)

# ----- refuse: helper already exists (already_has_helper.pas fixture) -----
& $exe create-enum-helper --qname TStatus --db $dbAlready --json 2>$null | Out-Null
Assert "refuse (exists fixture): nonzero exit" ($LASTEXITCODE -ne 0)
$existsJson = & $exe create-enum-helper --qname TStatus --db $dbAlready --json 2>$null | ConvertFrom-Json
Assert "refuse (exists fixture): action=exists" ($existsJson.action -eq 'exists')

# ----- refuse: no implementation section (no_impl_fragment.pas has TFlag, no 'implementation' keyword) -----
$noImplErr = (& $exe create-enum-helper --qname TFlag --db $dbNoImpl 2>&1) -join "`n"
Assert "refuse (no-impl fixture): nonzero exit" ($LASTEXITCODE -ne 0)
$noImplJson = & $exe create-enum-helper --qname TFlag --db $dbNoImpl --json 2>$null | ConvertFrom-Json
Assert "refuse (no-impl fixture): action=no_impl_section" ($noImplJson.action -eq 'no_impl_section')
Assert "refuse (no-impl fixture): message mentions implementation" ($noImplErr -match 'implementation')

# ----- refuse: TNope not found -----
$nopeOut = (& $exe create-enum-helper --qname TNope --db $dbSimple 2>&1) -join "`n"
Assert "not-found: nonzero exit" ($LASTEXITCODE -ne 0)
Assert "not-found: message mentions not found" ($nopeOut -match 'not found')

# ----- usage error: missing --qname -----
& $exe create-enum-helper --db $dbSimple 2>$null | Out-Null
Assert "usage error: missing --qname exits nonzero" ($LASTEXITCODE -ne 0)

# ----- --methods subset: only tobyte,frombyte -> 2 methods in decl, no ToString/FromString -----
$dbMethods = Join-Path $WorkDir "methods_subset.sqlite"
$methodsDir = Join-Path $WorkDir "methods_subset_src"
New-Item -ItemType Directory $methodsDir | Out-Null
Copy-Item (Join-Path $dir "simple.pas") $methodsDir
& $exe index $methodsDir --db $dbMethods 2>&1 | Out-Null
$subsetDry = (& $exe create-enum-helper --qname TColor --db $dbMethods --methods tobyte,frombyte 2>$null) -join "`n"
Assert "methods subset: ToByte present"     ($subsetDry -match 'function ToByte')
Assert "methods subset: FromByte present"   ($subsetDry -match 'class function FromByte')
Assert "methods subset: ToString absent"    (-not ($subsetDry -match 'function ToString'))

# ----- --tostring case: emits a case statement, not RTTI GetEnumName -----
$dbCase = Join-Path $WorkDir "tostring_case.sqlite"
$caseDir = Join-Path $WorkDir "tostring_case_src"
New-Item -ItemType Directory $caseDir | Out-Null
Copy-Item (Join-Path $dir "simple.pas") $caseDir
& $exe index $caseDir --db $dbCase 2>&1 | Out-Null
$caseDry = (& $exe create-enum-helper --qname TColor --db $dbCase --methods tostring --tostring case 2>$null) -join "`n"
Assert "tostring=case: emits case statement" ($caseDry -match 'case Self of')
Assert "tostring=case: no RTTI GetEnumName"   (-not ($caseDry -match 'GetEnumName'))

# ----- helpers-of: existing helper (already_has_helper.pas) -----
$hoJson = & $exe helpers-of TStatus --db $dbAlready --json 2>$null | ConvertFrom-Json
Assert "helpers-of json: at least one edge" ($hoJson.Count -ge 1)
Assert "helpers-of json: helper/target/unit fields" ($null -ne $hoJson[0].helper -and $hoJson[0].target -eq 'TStatus' -and $null -ne $hoJson[0].unit)

$hoText = (& $exe helpers-of TStatus --db $dbAlready 2>$null) -join "`n"
Assert "helpers-of text: mentions TStatusHelper" ($hoText -match 'TStatusHelper')

# ----- helpers-of: no helper -> empty result, exit 0 -----
$hoNone = & $exe helpers-of TColor --db $dbSimple --json 2>$null | ConvertFrom-Json
Assert "helpers-of json: no edges for TColor in simple db" (($null -eq $hoNone) -or ($hoNone.Count -eq 0))
Assert "helpers-of: exit 0 even with zero edges" ($LASTEXITCODE -eq 0)

Write-Host ""
if ($fail -gt 0) { Write-Host "enum-helper CLI: $fail FAIL"; exit 1 } else { Write-Host "enum-helper CLI: all pass"; exit 0 }
