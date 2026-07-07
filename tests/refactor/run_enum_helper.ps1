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

# --- 6. (Task 6b) explicit_ordinals.pas: TSpec=(sp_Undefined=0, sp_Double=1,
# sp_Upper=2) -- explicit (sequential-looking but EXPLICIT) ordinals disable
# automatic enum RTTI; Resolve/Build must detect this and auto-fall-back to
# case-mode ToString/FromString even under the default tsmRtti. Reused by the
# unit-test harness below in addition to its Task-6 e2e use further down. ---
$dbOrdinalsUnit = Join-Path $WorkDir "explicit_ordinals_unit.sqlite"
$out6 = & $exe index (Join-Path $dir "explicit_ordinals.pas") --db $dbOrdinalsUnit 2>&1
if ($LASTEXITCODE -ne 0) { Write-Host "FAIL: index explicit_ordinals.pas (unit-test db)"; Write-Host $out6; exit 1 }

# --- build the DUnitX-style console test ---
$rs = 'C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\rsvars.bat'
$searchPath = "$repo\src\core;$repo\src\storage;$repo\src\query;$repo\src\index;$repo\src\preprocess;$repo\src\refactor"
$buildOut = cmd /c "call `"$rs`" && cd /d `"$PSScriptRoot`" && dcc64 -B -NSSystem -E`"$PSScriptRoot`" -U`"$searchPath`" `"$PSScriptRoot\EnumHelperTests.dpr`"" 2>&1
$err = $buildOut | Select-String -Pattern "\bError\b|E2\d{3}|F2\d{3}|Fatal"
if ($err) { Write-Host "BUILD FAILED:"; $err | Select-Object -First 12; exit 1 }

& "$PSScriptRoot\EnumHelperTests.exe" $dbSimple $dbAlready $dbSeparate $dbIfaceOnly $dbNoImpl $dbOrdinalsUnit
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

# =====================================================================
# Task 6: full 10-case spec suite (cases 2,3,5,7,9,10) + the build/
# round-trip acceptance gate (case 8) + the mandatory has_impl_uses
# fixture (Task 4 review gap). Each case gets its own temp source dir +
# temp DB so counts/state never cross-contaminate (Task 2 lesson).
# =====================================================================

# ----- case 2: explicit_ordinals.pas -- TSpec=(sp_Undefined=0, sp_Double=1, sp_Upper=2) -----
# FromByte case maps Ord(sp_Double)->sp_Double; else = first member (sp_Undefined); ToInteger=Ord.
$dbOrdinals = Join-Path $WorkDir "explicit_ordinals.sqlite"
& $exe index (Join-Path $dir "explicit_ordinals.pas") --db $dbOrdinals 2>&1 | Out-Null
$ordinalsDry = (& $exe create-enum-helper --qname TSpec --db $dbOrdinals 2>$null) -join "`n"
Assert "case2 explicit_ordinals: FromByte maps Ord(sp_Double) -> sp_Double" `
    ($ordinalsDry -match 'Ord\(sp_Double\):\s*Result\s*:=\s*sp_Double;')
Assert "case2 explicit_ordinals: else = first member (sp_Undefined)" `
    ($ordinalsDry -match "(?s)case AValue of.*else\s*\r?\n\s*Result := sp_Undefined;")
Assert "case2 explicit_ordinals: ToInteger returns Ord(Self)" `
    ($ordinalsDry -match '(?s)function TSpecHelper\.ToInteger: Integer;.*Result := Ord\(Self\);')

# ----- case 3: NegativeOrdinal.pas -- TTEST=(Elem1=-2, Elem2=0, Elem3) -----
# One-Byte-template rule: FromByte/FromInteger is a plain `case` with ONE arm
# per real member (Elem1 included -- it is a real named member like any
# other; the template never special-cases negative/gapped ordinals), NO
# ShortInt variant text, no source-ordinal read.
# Compile-gate note: Delphi only emits automatic enum RTTI when the ordinals
# are the sequential-from-0 default; TTEST's explicit, non-sequential,
# negative-starting ordinals genuinely DISABLE default RTTI (verified via an
# isolated probe: E2134 "has no type info" on GetEnumName/TypeInfo for this
# exact shape, reproduced even with plain positive non-sequential ordinals --
# it is the explicit-assignment-breaks-the-0-based-default rule, not
# negativity specifically). So the round-trip COMPILE assertion below uses
# --tostring case (the generator's own documented non-RTTI escape hatch) --
# this is what a real caller must choose for such an enum; the point of this
# case is the Byte/case-idiom collapse, not RTTI on a non-RTTI-able enum.
$dbNeg = Join-Path $WorkDir "negative_ordinal.sqlite"
$negSrcDir = Join-Path $WorkDir "negative_ordinal_src"
New-Item -ItemType Directory $negSrcDir | Out-Null
Copy-Item (Join-Path $dir "NegativeOrdinal.pas") $negSrcDir
$negPas = Join-Path $negSrcDir "NegativeOrdinal.pas"
& $exe index $negSrcDir --db $dbNeg 2>&1 | Out-Null
$negDry = (& $exe create-enum-helper --qname TTEST --db $dbNeg 2>$null) -join "`n"
Assert "case3 negative_ordinal: case has arm for Elem1 (real member, incl. negative ordinal)" `
    ($negDry -match 'Ord\(Elem1\):\s*Result\s*:=\s*Elem1;')
Assert "case3 negative_ordinal: case over real members (Elem2)" ($negDry -match 'Ord\(Elem2\):\s*Result\s*:=\s*Elem2;')
Assert "case3 negative_ordinal: case over real members (Elem3)" ($negDry -match 'Ord\(Elem3\):\s*Result\s*:=\s*Elem3;')
Assert "case3 negative_ordinal: else = first member (Elem1)" `
    ($negDry -match "(?s)case AValue of.*else\s*\r?\n\s*Result := Elem1;")
Assert "case3 negative_ordinal: no ShortInt variant text" (-not ($negDry -match 'ShortInt'))
& $exe create-enum-helper --qname TTEST --db $dbNeg --apply --no-backup --tostring case 2>$null | Out-Null
Assert "case3 negative_ordinal: applied result (--tostring case) compiles (dcc64)" (Test-Compiles $negPas)
$negApplied = Get-Content $negPas -Raw
Assert "case3 negative_ordinal: applied text has no ShortInt variant" (-not ($negApplied -match 'ShortInt'))
# Scope the "no source-ordinal read" check to the GENERATED helper block only
# (from '{ TTESTHelper }' onward) -- the enum's own decl line (untouched
# user source, line 4) legitimately still reads 'Elem1 = -2'; the point is
# that the GENERATOR never echoes/reads that literal into its own output.
$negHelperBlock = $negApplied.Substring($negApplied.IndexOf('{ TTESTHelper }'))
Assert "case3 negative_ordinal: generated helper block has no source-ordinal literal (-2)" `
    (-not ($negHelperBlock -match '-2'))

# ----- case 5: doc_interleaved.pas -- {$REGION}/{$ENDREGION} + /// doc lines between members -----
# Generated helper members must equal the REAL enum members (noise skipped
# via the v0.92 preprocessor); no stRegion/stEndregion-style bogus members.
$dbDoc = Join-Path $WorkDir "doc_interleaved.sqlite"
& $exe index (Join-Path $dir "doc_interleaved.pas") --db $dbDoc 2>&1 | Out-Null
$docJson = & $exe create-enum-helper --qname TStage --db $dbDoc --json 2>$null | ConvertFrom-Json
Assert "case5 doc_interleaved: action=built" ($docJson.action -eq 'built')
$docDry = (& $exe create-enum-helper --qname TStage --db $dbDoc 2>$null) -join "`n"
Assert "case5 doc_interleaved: FromByte has stPending arm" ($docDry -match 'Ord\(stPending\):\s*Result\s*:=\s*stPending;')
Assert "case5 doc_interleaved: FromByte has stRunning arm" ($docDry -match 'Ord\(stRunning\):\s*Result\s*:=\s*stRunning;')
Assert "case5 doc_interleaved: FromByte has stDone arm"    ($docDry -match 'Ord\(stDone\):\s*Result\s*:=\s*stDone;')
Assert "case5 doc_interleaved: exactly 3 real members (no noise members; FromByte+FromInteger = 6 arms)" `
    (([regex]::Matches($docDry, 'Ord\(st\w+\):')).Count -eq 6)

# ----- case 7: descriptions_reuse.pas -- enum + <Enum>Descriptions array -----
# A ToDescription method is generated reusing the const array.
$dbDesc = Join-Path $WorkDir "descriptions_reuse.sqlite"
& $exe index (Join-Path $dir "descriptions_reuse.pas") --db $dbDesc 2>&1 | Out-Null
$descDry = (& $exe create-enum-helper --qname TSignalColor --db $dbDesc 2>$null) -join "`n"
Assert "case7 descriptions_reuse: ToDescription declared"        ($descDry -match 'function ToDescription: string;')
Assert "case7 descriptions_reuse: body indexes TSignalColorDescriptions" `
    ($descDry -match 'Result := TSignalColorDescriptions\[Self\];')

# ----- case 9: placement -- decl immediately after enum decl; bodies in impl -----
# (interface_only.pas already exists from Task 4 -- assert placement here too.)
# Copied to a filename matching its `unit InterfaceOnly;` clause (dcc64
# requires filename == unit identifier to compile standalone -- E1038
# otherwise; the repo fixture keeps its Task-4 snake_case filename since it
# is only ever indexed there, never compiled).
$dbPlace = Join-Path $WorkDir "placement_interface_only.sqlite"
$placeSrcDir = Join-Path $WorkDir "placement_interface_only_src"
New-Item -ItemType Directory $placeSrcDir | Out-Null
Copy-Item (Join-Path $dir "interface_only.pas") (Join-Path $placeSrcDir "InterfaceOnly.pas")
$placePas = Join-Path $placeSrcDir "InterfaceOnly.pas"
& $exe index $placeSrcDir --db $dbPlace 2>&1 | Out-Null
& $exe create-enum-helper --qname TSignal --db $dbPlace --apply --no-backup 2>$null | Out-Null
$placedSrc = Get-Content $placePas -Raw
Assert "case9 placement: decl inserted immediately after enum decl (same type section)" `
    ($placedSrc -match '(?s)TSignal = \(sgRed, sgYellow, sgGreen\);\s*\r?\n\s*\r?\n\s*TSignalHelper = record helper for TSignal')
Assert "case9 placement: bodies land right after 'implementation' (populates empty impl)" `
    ($placedSrc -match '(?s)implementation\s*\r?\n\s*\r?\n\s*uses System\.TypInfo;\s*\r?\n\s*\r?\n\s*\{ TSignalHelper \}')
Assert "case9 placement: applied result compiles (dcc64)" (Test-Compiles $placePas)

# ----- case 10: CLI/IDE parity -- Build called twice with identical args -> identical edits -----
# The CLI verb and the IDE menu both call TEnumHelperRefactoring.Build only
# (design Section 4); running the CLI verb twice against an unmodified DB
# (dry-run, no --apply) is the cheapest proof both callers get the SAME text.
$dbParity = Join-Path $WorkDir "parity.sqlite"
& $exe index (Join-Path $dir "simple.pas") --db $dbParity 2>&1 | Out-Null
$parity1 = (& $exe create-enum-helper --qname TColor --db $dbParity 2>$null) -join "`n"
$parity2 = (& $exe create-enum-helper --qname TColor --db $dbParity 2>$null) -join "`n"
Assert "case10 parity: repeated Build calls produce identical dry-run text" ($parity1 -ceq $parity2)
$parityJson1 = & $exe create-enum-helper --qname TColor --db $dbParity --json 2>$null
$parityJson2 = & $exe create-enum-helper --qname TColor --db $dbParity --json 2>$null
Assert "case10 parity: repeated Build calls produce identical json" ($parityJson1 -ceq $parityJson2)

# =====================================================================
# Case 8 -- THE ACCEPTANCE GATE: apply the helper to a temp copy of
# simple.pas, dcc64-compile a console program that USES it and asserts
# round-trips, and RUN the resulting exe -- exit 0 required. Text-matching
# alone (as above) is not sufficient; this is the real gate per the spec.
# =====================================================================
$gateDir = Join-Path $WorkDir "gate_simple"
New-Item -ItemType Directory $gateDir | Out-Null
Copy-Item (Join-Path $dir "simple.pas") $gateDir
Copy-Item (Join-Path $dir "RoundTripSimple.dpr") $gateDir
$gatePas = Join-Path $gateDir "simple.pas"
$dbGate  = Join-Path $WorkDir "gate_simple.sqlite"
& $exe index $gatePas --db $dbGate 2>&1 | Out-Null
& $exe create-enum-helper --qname TColor --db $dbGate --apply --no-backup 2>$null | Out-Null
Assert "case8 gate: create-enum-helper apply exit 0" ($LASTEXITCODE -eq 0)
Assert "case8 gate: applied simple.pas compiles standalone (dcc64)" (Test-Compiles $gatePas)

$rsPath = 'C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\rsvars.bat'
$gateBuildOut = cmd /c "call `"$rsPath`" && cd /d `"$gateDir`" && dcc64 -B `"RoundTripSimple.dpr`"" 2>&1
$gateBuildErr = $gateBuildOut | Select-String -Pattern "\bError\b|E2\d{3}|F2\d{3}|Fatal"
if ($gateBuildErr) {
    Write-Host "FAIL  case8 gate: RoundTripSimple.dpr compiles" -ForegroundColor Red
    $gateBuildErr | Select-Object -First 12
    $script:fail++
} else {
    Write-Host "PASS  case8 gate: RoundTripSimple.dpr compiles"
}
$gateExePath = Join-Path $gateDir "RoundTripSimple.exe"
if (Test-Path $gateExePath) {
    $gateRunOut = & $gateExePath 2>&1
    Write-Host ($gateRunOut -join "`n")
    Assert "case8 gate: round-trip asserter exits 0 (ALL asserts passed)" ($LASTEXITCODE -eq 0)
} else {
    Assert "case8 gate: RoundTripSimple.exe was produced" $false
}

# =====================================================================
# Mandatory Task-6 addition (Task 4 review gap): HasImplUses.pas has a
# PRE-EXISTING implementation 'uses System.SysUtils;' clause. Applying the
# RTTI helper (needs System.TypInfo) must merge into that existing uses
# clause (not add a second/duplicate uses clause), place bodies AFTER it
# (no E2029), compile, and round-trip -- proven by actually compiling +
# running the companion asserter program, not just text-matching.
# Filename matches the `unit HasImplUses;` clause (dcc64 requires this to
# compile standalone -- E1038 otherwise).
# =====================================================================
$implUsesDir = Join-Path $WorkDir "gate_has_impl_uses"
New-Item -ItemType Directory $implUsesDir | Out-Null
Copy-Item (Join-Path $dir "HasImplUses.pas") $implUsesDir
Copy-Item (Join-Path $dir "RoundTripImplUses.dpr") $implUsesDir
$implUsesPas = Join-Path $implUsesDir "HasImplUses.pas"
$dbImplUses  = Join-Path $WorkDir "gate_has_impl_uses.sqlite"
& $exe index $implUsesPas --db $dbImplUses 2>&1 | Out-Null
& $exe create-enum-helper --qname TShade --db $dbImplUses --apply --no-backup 2>$null | Out-Null
Assert "has_impl_uses gate: create-enum-helper apply exit 0" ($LASTEXITCODE -eq 0)
$implUsesApplied = Get-Content $implUsesPas -Raw
Assert "has_impl_uses gate: System.TypInfo merged into the EXISTING uses clause" `
    ($implUsesApplied -match 'uses\s*\r?\n\s*System\.SysUtils\s*,\s*System\.TypInfo;')
Assert "has_impl_uses gate: exactly ONE implementation uses clause (no duplicate)" `
    (([regex]::Matches($implUsesApplied, '(?m)^uses\s*$')).Count -eq 1)
Assert "has_impl_uses gate: applied unit compiles standalone (dcc64)" (Test-Compiles $implUsesPas)

$implUsesBuildOut = cmd /c "call `"$rsPath`" && cd /d `"$implUsesDir`" && dcc64 -B `"RoundTripImplUses.dpr`"" 2>&1
$implUsesBuildErr = $implUsesBuildOut | Select-String -Pattern "\bError\b|E2\d{3}|F2\d{3}|Fatal"
if ($implUsesBuildErr) {
    Write-Host "FAIL  has_impl_uses gate: RoundTripImplUses.dpr compiles (no E2029)" -ForegroundColor Red
    $implUsesBuildErr | Select-Object -First 12
    $script:fail++
} else {
    Write-Host "PASS  has_impl_uses gate: RoundTripImplUses.dpr compiles (no E2029)"
}
$implUsesExePath = Join-Path $implUsesDir "RoundTripImplUses.exe"
if (Test-Path $implUsesExePath) {
    $implUsesRunOut = & $implUsesExePath 2>&1
    Write-Host ($implUsesRunOut -join "`n")
    Assert "has_impl_uses gate: round-trip asserter exits 0 (ALL asserts passed)" ($LASTEXITCODE -eq 0)
} else {
    Assert "has_impl_uses gate: RoundTripImplUses.exe was produced" $false
}

# =====================================================================
# Task 6b: THE AUTO-FALLBACK ACCEPTANCE GATE. explicit_ordinals.pas's TSpec
# has every member on an explicit ordinal (sp_Undefined=0, sp_Double=1,
# sp_Upper=2) -- Delphi therefore emits NO automatic RTTI for it. Apply
# create-enum-helper WITH NO --tostring FLAG AT ALL (the real CLI default,
# tsmRtti) -- before Task 6b this produced GetEnumName/GetEnumValue calls
# that FAILED TO COMPILE (E2134 "Type has no type info"); the generator must
# now silently fall back to case-mode and the result must compile + round-
# trip, proven the same way as case8/has_impl_uses: actually dcc64-compile a
# companion asserter program and RUN it (text-matching alone is not the
# gate). Filename matches the `unit ExplicitOrdinals;` clause (dcc64
# requires this to compile standalone -- E1038 otherwise).
# =====================================================================
$ordinalsDefaultDir = Join-Path $WorkDir "gate_ordinals_default"
New-Item -ItemType Directory $ordinalsDefaultDir | Out-Null
Copy-Item (Join-Path $dir "explicit_ordinals.pas") (Join-Path $ordinalsDefaultDir "ExplicitOrdinals.pas")
Copy-Item (Join-Path $dir "RoundTripOrdinalsDefault.dpr") $ordinalsDefaultDir
$ordinalsDefaultPas = Join-Path $ordinalsDefaultDir "ExplicitOrdinals.pas"
$dbOrdinalsDefault  = Join-Path $WorkDir "gate_ordinals_default.sqlite"
& $exe index $ordinalsDefaultPas --db $dbOrdinalsDefault 2>&1 | Out-Null
# NOTE: no --tostring flag here at all -- this is the point of the gate.
& $exe create-enum-helper --qname TSpec --db $dbOrdinalsDefault --apply --no-backup 2>$null | Out-Null
Assert "ordinals-default gate: create-enum-helper apply exit 0" ($LASTEXITCODE -eq 0)
$ordinalsDefaultApplied = Get-Content $ordinalsDefaultPas -Raw
Assert "ordinals-default gate: auto-fell-back to case-mode (no GetEnumName in applied text)" `
    (-not ($ordinalsDefaultApplied -match 'GetEnumName'))
Assert "ordinals-default gate: no System.TypInfo uses clause added (NeedsTypInfo=False)" `
    (-not ($ordinalsDefaultApplied -match 'System\.TypInfo'))
Assert "ordinals-default gate: applied result compiles (dcc64)" (Test-Compiles $ordinalsDefaultPas)

$ordinalsDefaultBuildOut = cmd /c "call `"$rsPath`" && cd /d `"$ordinalsDefaultDir`" && dcc64 -B `"RoundTripOrdinalsDefault.dpr`"" 2>&1
$ordinalsDefaultBuildErr = $ordinalsDefaultBuildOut | Select-String -Pattern "\bError\b|E2\d{3}|F2\d{3}|Fatal"
if ($ordinalsDefaultBuildErr) {
    Write-Host "FAIL  ordinals-default gate: RoundTripOrdinalsDefault.dpr compiles" -ForegroundColor Red
    $ordinalsDefaultBuildErr | Select-Object -First 12
    $script:fail++
} else {
    Write-Host "PASS  ordinals-default gate: RoundTripOrdinalsDefault.dpr compiles"
}
$ordinalsDefaultExePath = Join-Path $ordinalsDefaultDir "RoundTripOrdinalsDefault.exe"
if (Test-Path $ordinalsDefaultExePath) {
    $ordinalsDefaultRunOut = & $ordinalsDefaultExePath 2>&1
    Write-Host ($ordinalsDefaultRunOut -join "`n")
    Assert "ordinals-default gate: round-trip asserter exits 0 (ALL asserts passed)" ($LASTEXITCODE -eq 0)
} else {
    Assert "ordinals-default gate: RoundTripOrdinalsDefault.exe was produced" $false
}

Write-Host ""
if ($fail -gt 0) { Write-Host "enum-helper CLI: $fail FAIL"; exit 1 } else { Write-Host "enum-helper CLI: all pass"; exit 0 }
