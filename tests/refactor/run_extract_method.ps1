# drag-lint extract-method e2e: dry-run / --json / --apply / refuse, plus
# compile-verification of the applied result (mirrors run_rename_param.ps1
# for the single-file --file style and run_buildlocal_tests.ps1 for the
# dcc64 compile-check invocation).
param([string]$Exe = "third_party\dll-win64\drag-lint.exe")
$ErrorActionPreference = "Stop"
$repo = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
Set-Location $repo
$exe = (Resolve-Path $Exe).Path
$dir = Join-Path $PSScriptRoot "extractmethod"
$fail = 0
function Assert($n,$c){ if($c){Write-Host "PASS  $n"}else{Write-Host "FAIL  $n" -ForegroundColor Red;$script:fail++} }

function Test-Compiles($PasFile) {
    $rs = 'C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\rsvars.bat'
    $fileDir = Split-Path -Parent $PasFile
    $out = cmd /c "call `"$rs`" && cd /d `"$fileDir`" && dcc64 -B `"$PasFile`"" 2>&1
    $err = $out | Select-String -Pattern "\bError\b|E2\d{3}|F2\d{3}|Fatal"
    return -not $err
}

# ----- dry-run: preview shows the new signature -----
$basic = Join-Path $dir "Basic.pas"
$dry = (& $exe extract-method --file $basic --from-line 8 --to-line 9 --name Extracted --dry-run 2>$null) -join "`n"
Assert "dry-run preview mentions the new method name" ($dry -match 'Extracted')

# ----- --json: parseable edit array -----
$json = & $exe extract-method --file $basic --from-line 8 --to-line 9 --name Extracted --json 2>$null | ConvertFrom-Json
Assert "json edit set non-empty" ($json.Count -ge 1)
Assert "json edit has file/line/text fields" ($null -ne $json[0].file -and $null -ne $json[0].line -and $null -ne $json[0].text)

# ----- --apply: file now contains the call + the new method; compiles -----
$tmp = Join-Path $env:TEMP "extractmethod_apply_basic"
if (Test-Path $tmp) { Remove-Item $tmp -Recurse -Force }
New-Item -ItemType Directory -Path $tmp | Out-Null
Copy-Item $basic (Join-Path $tmp "Basic.pas")
$t = Join-Path $tmp "Basic.pas"
& $exe extract-method --file $t --from-line 8 --to-line 9 --name Extracted --apply --no-backup 2>$null | Out-Null
$after = Get-Content $t -Raw
Assert "apply inserted the new method"     ($after -match 'procedure Extracted\(a: Integer\)')
Assert "apply replaced the run with a call" ($after -match 'Extracted\(a\);')
Assert "apply: no .bak written with --no-backup" (-not (Test-Path "$t.bak"))
Assert "apply result compiles (dcc64)" (Test-Compiles $t)

# ----- backup: .bak created unless --no-backup -----
$tmp2 = Join-Path $env:TEMP "extractmethod_apply_backup"
if (Test-Path $tmp2) { Remove-Item $tmp2 -Recurse -Force }
New-Item -ItemType Directory -Path $tmp2 | Out-Null
Copy-Item $basic (Join-Path $tmp2 "Basic.pas")
$t2 = Join-Path $tmp2 "Basic.pas"
& $exe extract-method --file $t2 --from-line 8 --to-line 9 --name Extracted --apply 2>$null | Out-Null
Assert "apply without --no-backup writes a .bak" (Test-Path "$t2.bak")

# ----- CARRIED FIXTURE #1: a run-defined local read AFTER the selection.
# The engine's ClassifyVars refuses when a second (non-output) run-defined
# local is still referenced outside the run ("used outside the selection")
# rather than silently dropping it -- see DRagLint.Refactor.ExtractMethod.pas
# VarUsedOutsideRun. In ReadAfter.pas, `sum` becomes the single Result
# (read at line 10, live-out) but `t` is reassigned at line 11 (an
# out-of-run assignment target, so VarUsedOutsideRun flags it even though
# it is not live-out) -> Build refuses. -----
$readAfter = Join-Path $dir "ReadAfter.pas"
$raOut = (& $exe extract-method --file $readAfter --from-line 8 --to-line 9 --name Extracted --dry-run 2>&1) -join "`n"
Assert "carried#1: refuses (nonzero exit)" ($LASTEXITCODE -ne 0)
Assert "carried#1: reason says used outside the selection" ($raOut -match 'used outside the selection')

# ----- CARRIED FIXTURE #2: var section declares ONLY internals across
# MULTIPLE lines (all moved into the new method) -- after --apply the
# orphan `var` keyword line must be gone and the file must compile. -----
$multiVar = Join-Path $dir "MultiVar.pas"
$tmp3 = Join-Path $env:TEMP "extractmethod_apply_multivar"
if (Test-Path $tmp3) { Remove-Item $tmp3 -Recurse -Force }
New-Item -ItemType Directory -Path $tmp3 | Out-Null
Copy-Item $multiVar (Join-Path $tmp3 "MultiVar.pas")
$t3 = Join-Path $tmp3 "MultiVar.pas"
& $exe extract-method --file $t3 --from-line 10 --to-line 12 --name Inner --apply --no-backup 2>$null | Out-Null
$after3 = Get-Content $t3 -Raw
Assert "carried#2: orphan 'var' keyword removed from caller" `
    (-not ([regex]::Match($after3, 'procedure P\(a: Integer\);\s*var\s*begin')).Success)
Assert "carried#2: new method still declares t and u"  ($after3 -match 'procedure Inner\(a: Integer\)')
Assert "carried#2: caller body reduced to the call"     ($after3 -match 'Inner\(a\);')
Assert "carried#2: apply result compiles (dcc64)" (Test-Compiles $t3)

# ----- refuse fixture: nonzero exit + reason on stderr -----
$refuse = Join-Path $dir "Refuse.pas"
$refOut = (& $exe extract-method --file $refuse --from-line 8 --to-line 11 --name Nope --dry-run 2>&1) -join "`n"
Assert "refuse: nonzero exit"                ($LASTEXITCODE -ne 0)
Assert "refuse: reason mentions single routine" ($refOut -match 'single routine')

# ----- usage error: missing required args -----
& $exe extract-method --file $basic 2>$null | Out-Null
Assert "usage error: missing --from-line/--to-line/--name exits nonzero" ($LASTEXITCODE -ne 0)

Write-Host ""
if ($fail -gt 0) { Write-Host "extract-method: $fail FAIL"; exit 1 } else { Write-Host "extract-method: all pass"; exit 0 }
