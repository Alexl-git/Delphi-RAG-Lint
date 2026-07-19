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

# Task 3: --json assertions (use the read-only fixture, not the temp copy).
# Capture STDOUT ONLY (2>$null): the engine emits a "(loaded defaults ...)"
# advisory to stderr that can interleave mid-JSON under 2>&1 and break parsing.
# Real consumers read stdout, which is clean JSON.
$j = & $Exe reconcile-project "$fx\App.dpr" --json 2>$null | Out-String
Check 'json has missing array' ($j -match '"missing"\s*:\s*\[')
Check 'json has stale array'   ($j -match '"stale"\s*:\s*\[')
Check 'json parses'            ([bool]($j | ConvertFrom-Json))

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

# Task 3 (coherence): with --db, reconcile HEALS the index+findings for the
# project's members without editing the .dpr. Pre-seed a DB that is missing one
# unit (and its sibling .dfm); after reconcile --db, both must have a files row.
# This is the discriminating proof of the fix (the motivating VARINSPCODE bug:
# an edited project member with no files row -> findings can't attach).
# Needs Python (stdlib sqlite3) to inspect the DB -- skip-not-fail if absent.
$py = 'C:\Python314\python.exe'
if (Test-Path $py) {
  $enc = [System.Text.Encoding]::ASCII
  $cx  = "$env:TEMP\drag-lint-reconcile-coherence"
  if (Test-Path $cx) { Remove-Item -Recurse -Force $cx }
  New-Item -ItemType Directory -Force $cx | Out-Null

  # Fixture: App.dpr lists two project units; uForm has a sibling uForm.dfm.
  [System.IO.File]::WriteAllText("$cx\App.dpr",
    "program App;`r`n`r`nuses`r`n  uMain in 'uMain.pas',`r`n  uForm in 'uForm.pas';`r`n`r`nbegin`r`nend.`r`n", $enc)
  [System.IO.File]::WriteAllText("$cx\uMain.pas",
    "unit uMain;`r`ninterface`r`nuses uForm;`r`nimplementation`r`nend.`r`n", $enc)
  [System.IO.File]::WriteAllText("$cx\uForm.pas",
    "unit uForm;`r`ninterface`r`nimplementation`r`nend.`r`n", $enc)
  [System.IO.File]::WriteAllText("$cx\uForm.dfm",
    "object frmForm: TfrmForm`r`n  Left = 0`r`n  Top = 0`r`nend`r`n", $enc)
  $dprojX = "<?xml version=`"1.0`" encoding=`"utf-8`"?>`r`n<Project xmlns=`"http://schemas.microsoft.com/developer/msbuild/2003`">`r`n  <ItemGroup>`r`n    <DCCReference Include=`"uMain.pas`"/>`r`n    <DCCReference Include=`"uForm.pas`"/>`r`n  </ItemGroup>`r`n</Project>"
  [System.IO.File]::WriteAllText("$cx\App.dproj", $dprojX, $enc)

  # Python helper: prints 1 iff a files row exists whose path ends with <needle>.
  $pyBody = "import sqlite3, sys`n" +
            "con = sqlite3.connect(sys.argv[1])`n" +
            "n = con.execute(`"SELECT COUNT(*) FROM files WHERE path LIKE ?`", ('%' + sys.argv[2],)).fetchone()[0]`n" +
            "print(1 if n > 0 else 0)`n"
  [System.IO.File]::WriteAllText("$cx\hasfile.py", $pyBody, $enc)
  function Coh-HasFile([string]$db, [string]$needle) {
    $r = (& $py "$cx\hasfile.py" $db $needle 2>$null | Out-String).Trim()
    return ($r -eq '1')
  }

  # Two independently-seeded DBs (uMain only) so the text run and the --json run
  # each see the incoherent baseline (the text run heals its own DB).
  $cdb  = "$cx\cohere.sqlite"
  $cdb2 = "$cx\cohere2.sqlite"
  & $Exe index "$cx\uMain.pas" --db $cdb  2>$null | Out-Null
  & $Exe index "$cx\uMain.pas" --db $cdb2 2>$null | Out-Null

  # Baseline: uForm.pas / uForm.dfm are NOT in the seeded DB yet.
  Check 'coh: uForm.pas absent pre-reconcile' (-not (Coh-HasFile $cdb 'uForm.pas'))
  Check 'coh: uForm.dfm absent pre-reconcile' (-not (Coh-HasFile $cdb 'uForm.dfm'))
  Check 'coh: uMain.pas present pre-reconcile' (Coh-HasFile $cdb 'uMain.pas')

  # Text run: reconcile with --db, NO --apply. stderr -> $null (advisory noise).
  $ctext = & $Exe reconcile-project "$cx\App.dpr" --db $cdb 2>$null | Out-String
  Check 'coh: reconcile --db exits 0'         ($LASTEXITCODE -eq 0)
  Check 'coh: coherence line incoherent>=1'   ($ctext -match 'coherence:.*incoherent=[1-9]')

  # THE fix (scan outcome -- independent of whether msbuild/dcc could compile):
  # the previously-absent unit AND its .dfm now have files rows.
  Check 'coh: uForm.pas now indexed'          (Coh-HasFile $cdb 'uForm.pas')
  Check 'coh: uForm.dfm now indexed'          (Coh-HasFile $cdb 'uForm.dfm')
  Check 'coh: uMain.pas still indexed'        (Coh-HasFile $cdb 'uMain.pas')

  # --db without --apply must NOT edit/back-up the project file.
  Check 'coh: no App.dpr.bak (no --apply)'    (-not (Test-Path "$cx\App.dpr.bak"))

  # JSON run (fresh DB): one valid JSON object with coherence.incoherent >= 1.
  $cjson = & $Exe reconcile-project "$cx\App.dpr" --db $cdb2 --json 2>$null | Out-String
  $cobj = $null
  try { $cobj = $cjson | ConvertFrom-Json } catch { $cobj = $null }
  Check 'coh: --json parses as one object'    ($null -ne $cobj)
  Check 'coh: json coherence.incoherent>=1'   ($null -ne $cobj -and $null -ne $cobj.coherence -and [int]$cobj.coherence.incoherent -ge 1)
  # JSON stays a superset of the original report (missing/stale still present).
  Check 'coh: json still has missing/stale'   ($null -ne $cobj -and $null -ne $cobj.missing -and $null -ne $cobj.stale)
}
else {
  Write-Host '  [SKIP] coherence DB-phase (Python not found at C:\Python314)' -ForegroundColor Yellow
}

Write-Host ''
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
