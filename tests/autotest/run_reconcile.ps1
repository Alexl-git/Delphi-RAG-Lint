$Exe = . "$PSScriptRoot\_manifest_common.ps1"
$fx = "$PSScriptRoot\..\fixtures\reconcile"
$rep = & $Exe reconcile-project "$fx\App.dpr" 2>&1 | Out-String
Check 'reconcile exits 0'        ($LASTEXITCODE -eq 0)
Check 'missing uHelper'          ($rep -match 'MISSING[\s\S]*uHelper')
Check 'missing uFoo_OLD'         ($rep -match 'MISSING[\s\S]*uFoo_OLD_20230828')
Check 'extra uOrphan'            ($rep -match 'EXTRA[\s\S]*uOrphan')
Check 'stale uFoo_OLD'           ($rep -match 'STALE[\s\S]*uFoo_OLD_20230828')
Check 'stale names using unit'   ($rep -match 'uFoo_OLD_20230828.*uHelper')
Check 'dry-run wrote nothing'    (-not (Test-Path $fx\App.dpr.bak))

# FIX 2 regression: date-stamp stale heuristic (_YYYYMMDD via TRegEx)
# uData_20240101 is used by uHelper so it appears in the closure; its name
# matches _\d{8} -> must appear in STALE even without an _OLD substring.
Check 'stale uData_20240101'     ($rep -match 'STALE[\s\S]*uData_20240101')

# Task 2: --apply assertions (work in a temp copy so the repo fixture stays clean)
$work = "$env:TEMP\drag-lint-reconcile"
if (Test-Path $work) { Remove-Item -Recurse -Force $work }
Copy-Item -Recurse $fx $work
& $Exe reconcile-project "$work\App.dpr" --apply 2>&1 | Out-Null
Check 'apply exits 0'         ($LASTEXITCODE -eq 0)
Check 'dpr backup made'       (Test-Path $work\App.dpr.bak)
Check 'dproj backup made'     (Test-Path $work\App.dproj.bak)
$dpr = Get-Content "$work\App.dpr" -Raw
Check 'dpr now has uHelper'   ($dpr -match 'uHelper\s+in\s+''uHelper\.pas''')
Check 'dpr now has uFoo_OLD'  ($dpr -match 'uFoo_OLD_20230828\s+in\s+''uFoo_OLD_20230828\.pas''')
$dproj = Get-Content "$work\App.dproj" -Raw
Check 'dproj has uHelper ref' ($dproj -match 'DCCReference Include="uHelper\.pas"')
$rep2 = & $Exe reconcile-project "$work\App.dpr" 2>&1 | Out-String
Check 'reapply 0 missing'     ($rep2 -match 'MISSING \(0\)')
Check 'uOrphan untouched'     ($rep2 -match 'EXTRA[\s\S]*uOrphan')

# Task 3: --json assertions (use the read-only fixture, not the temp copy)
$j = & $Exe reconcile-project "$fx\App.dpr" --json 2>&1 | Out-String
Check 'json has missing array' ($j -match '"missing"\s*:\s*\[')
Check 'json has stale array'   ($j -match '"stale"\s*:\s*\[')
# Extract the JSON object from combined stdout+stderr (stderr may have advisory lines)
$jClean = [regex]::Match($j, '(?s)\{.*\}').Value
Check 'json parses'            ([bool]($jClean | ConvertFrom-Json))

# FIX 1 regression: EditDpr must not corrupt .dpr when a uses entry carries a
# brace comment containing ';' (e.g. uMain in 'uMain.pas' {Form: TBar; note}).
# Without the fix, Pos(';'...) hits the ';' inside the comment and the new
# unit gets spliced INSIDE the brace text, corrupting the file.
$work2 = "$env:TEMP\drag-lint-reconcile-brace"
if (Test-Path $work2) { Remove-Item -Recurse -Force $work2 }
New-Item -ItemType Directory -Force $work2 | Out-Null
# Minimal .dpr: uses clause with a brace comment that contains a semicolon.
$dprBrace = "program BraceApp;`r`n`r`nuses`r`n  uMain in 'uMain.pas' {Form: TBar; note};`r`n`r`nbegin`r`nend.`r`n"
[System.IO.File]::WriteAllText("$work2\BraceApp.dpr", $dprBrace, [System.Text.Encoding]::ASCII)
# Minimal .dproj listing only uMain.
$dprojBrace = "<?xml version=`"1.0`" encoding=`"utf-8`"?>`r`n<Project xmlns=`"http://schemas.microsoft.com/developer/msbuild/2003`">`r`n  <ItemGroup>`r`n    <DCCReference Include=`"uMain.pas`"/>`r`n  </ItemGroup>`r`n</Project>"
[System.IO.File]::WriteAllText("$work2\BraceApp.dproj", $dprojBrace, [System.Text.Encoding]::ASCII)
# Copy the .pas fixture files needed for the brace-comment test.
Copy-Item "$fx\uMain.pas"             $work2
Copy-Item "$fx\uHelper.pas"           $work2
Copy-Item "$fx\uFoo_OLD_20230828.pas" $work2
Copy-Item "$fx\uData_20240101.pas"    $work2
& $Exe reconcile-project "$work2\BraceApp.dpr" --apply 2>&1 | Out-Null
Check 'brace-comment apply exits 0'   ($LASTEXITCODE -eq 0)
$dprAfter = Get-Content "$work2\BraceApp.dpr" -Raw
# The brace comment must survive intact.
Check 'brace comment intact'          ($dprAfter -match '\{Form: TBar; note\}')
# uHelper must have been added (it is missing from the original .dpr).
Check 'brace test: uHelper added'     ($dprAfter -match 'uHelper\s+in\s+''uHelper\.pas''')
# The comment must not be split: verify its text appears unbroken in the output.
Check 'brace comment not split'       ($dprAfter -match '\{Form: TBar; note\}')

Write-Host ''
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
