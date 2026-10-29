# run_taint_library.ps1 -- taint wave lane T2 (2026-10-27): the taint walk crosses into the
# LIBRARY store (plan docs\superpowers\plans\2026-10-27-taint-interprocedural-plan.md section 9).
#
# A mini library tests\lint-project\taint-lib\lib\uMiniRtl.pas (MyTrim returns its parameter,
# MyQuote returns it quoted, GetLine(out S) fills S from ParamStr) is indexed into a temp LIBRARY
# db; the project tests\lint-project\taint-lib\proj\uUseLib.pas calls all three and passes the
# results to GDb.ExecSQL. lint-all takes its library store as a SECOND --db (SplitConsumerDbs in
# DoLintAll; it does NOT read --library-db), lint <file> takes --library-db (LintLibraryDb). Both are
# pointed at the temp db so the run never opens the machine's real library index.
#
# Two index modes for the PROJECT: with `--library-db <tmpLib>` (refs.external_target filled) and
# without (the walk binds unresolved calls to the library by name). Both must give:
#   * a hit through MyTrim (a library routine whose own Result row derives from its parameter),
#   * a hit through GetLine (a library out-parameter fed by a source),
#   * a hit through MyQuote while it is uncatalogued (its facts propagate), and NO hit once a temp
#     config names it a sql sanitizer -- the stop, and its own positive control.
# -Mode fixture (default until T1 is merged) inserts the data_flows rows with fixture_rows.py.
#
# Usage: pwsh -File tests\autotest\run_taint_library.ps1 [-Exe <drag-lint.exe>] [-Mode fixture|real]
param([string]$Exe = '', [ValidateSet('fixture', 'real')][string]$Mode = 'fixture')
$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
if ($Exe -eq '') { $Exe = Join-Path $repo 'third_party\dll-win64\drag-lint.exe' }
$exePath = (Resolve-Path $Exe).Path
$libFx  = Join-Path $repo 'tests\lint-project\taint-lib\lib'
$projFx = Join-Path $repo 'tests\lint-project\taint-lib\proj'
$rowsPy = Join-Path $repo 'tests\lint-project\taint\fixture_rows.py'
$tmp    = Join-Path $env:TEMP "taint_library_$PID"
[void][IO.Directory]::CreateDirectory($tmp)
$lib    = Join-Path $tmp 'lib.sqlite'
$empty  = Join-Path $tmp 'empty.json'
$quote  = Join-Path $tmp 'quote-sanitizer.json'
[IO.File]::WriteAllText($empty, '{}')
[IO.File]::WriteAllText($quote, '{"taint": {"sanitizers": [{"name": "MyQuote", "sanitizes": ["sql"]}]}}')

$fail = 0
function Check([string]$Name, [bool]$Ok, [string]$Detail = '') {
  if ($Ok) { Write-Host "PASS  $Name" } else { Write-Host "FAIL  $Name  $Detail"; $script:fail++ }
}
function TaintFindings([string[]]$CliArgs) {
  $raw = & $exePath @CliArgs 2>$null
  $txt = ($raw -join "`n"); $b = $txt.IndexOf('[')
  $all = @(); if ($b -ge 0) { try { $all = @($txt.Substring($b) | ConvertFrom-Json) } catch { $all = @() } }
  return ,@($all | Where-Object { $_.rule -eq 'taint-sql-injection' })
}
function Line([string]$Anchor) {
  $ls = Get-Content (Join-Path $projFx 'uUseLib.pas')
  for ($i = 0; $i -lt $ls.Count; $i++) { if ($ls[$i].Contains($Anchor)) { return $i + 1 } }
  return -1
}

Push-Location $env:TEMP
try {
  & $exePath index $libFx --db $lib 2>&1 | Out-Null
  if ($Mode -eq 'fixture') {
    $n = (& python -I $rowsPy $lib $libFx minirtl 2>&1) -join ' '
    Check 'library rows inserted' ($n -eq '3') "fixture_rows.py said: $n"
  }
  $trimLine  = Line 'MyTrim(ParamStr(1))'
  $quoteLine = Line 'MyQuote(ParamStr(1))'
  $lineLine  = Line 'GDb.ExecSQL(S)'
  foreach ($idxMode in @('with-library-db', 'without-library-db')) {
    $db = Join-Path $tmp "proj-$idxMode.sqlite"
    if ($idxMode -eq 'with-library-db') { & $exePath index $projFx --db $db --library-db $lib 2>&1 | Out-Null }
    else { & $exePath index $projFx --db $db 2>&1 | Out-Null }
    if ($Mode -eq 'fixture') {
      $n = (& python -I $rowsPy $db $projFx uselib 2>&1) -join ' '
      Check "[$idxMode] project rows inserted" ($n -eq '5') "fixture_rows.py said: $n"
    }
    $f = TaintFindings @('lint-all', '--db', $db, '--db', $lib, '--json', '--quiet', '--config', $empty)
    $f | ForEach-Object { Write-Host ("  [{0}] {1}:{2} {3}" -f $idxMode, (Split-Path $_.file_path -Leaf), $_.start_line, $_.message) }
    $t = @($f | Where-Object { $_.start_line -eq $trimLine })
    Check "[$idxMode] hit through library MyTrim (line $trimLine)" ($t.Count -eq 1) "got $($t.Count)"
    if ($t.Count -eq 1) {
      Check "[$idxMode]   path names the library hop" (@($t[0].path | Where-Object { $_.note -match 'through MyTrim' }).Count -eq 1) (@($t[0].path | ForEach-Object { $_.note }) -join ' > ')
    }
    Check "[$idxMode] hit through library out param GetLine (line $lineLine)" (@($f | Where-Object { $_.start_line -eq $lineLine }).Count -eq 1)
    Check "[$idxMode] uncatalogued MyQuote propagates (line $quoteLine)" (@($f | Where-Object { $_.start_line -eq $quoteLine }).Count -eq 1)
    $g = TaintFindings @('lint-all', '--db', $db, '--db', $lib, '--json', '--quiet', '--config', $quote)
    Check "[$idxMode] MyQuote named a sql sanitizer in config -> stop (line $quoteLine)" (@($g | Where-Object { $_.start_line -eq $quoteLine }).Count -eq 0) "got $(@($g | Where-Object { $_.start_line -eq $quoteLine }).Count)"
    Check "[$idxMode]   the sanitizer stops only MyQuote (MyTrim still hits)" (@($g | Where-Object { $_.start_line -eq $trimLine }).Count -eq 1)
  }
}
finally {
  Pop-Location
  try { [IO.Directory]::Delete($tmp, $true) } catch { }
}
if ($fail -eq 0) { Write-Host "run_taint_library ($Mode): ALL PASS"; exit 0 }
Write-Host "run_taint_library ($Mode): $fail FAILED"; exit 1
