<#
  run_v156_HB5.ps1 -- 1.56 lane HB5: `happens-before` grows program-level order, three presets and
  the call-graph pre-check.

  Indexes the one-program folders of tests\fixtures\v156-hb5 into scratch DBs and asks
  `happens-before --json`.

  POSITIVE CONTROL: every family is a set of twins that differ by ONE construct and must give
  DIFFERENT verdicts, so an engine that answers one verdict for everything fails:
    O  program order (proof program-order, HbOrderSolve)
         O1 ord-yes        Randomize; RunGame   in the program block          YES
         O2 ord-no         RunGame; Randomize                                 NO   b-first
         O3 ord-may        if .. then Randomize; RunGame                      MAY
         O4 ord-init       Randomize in an initialization section             YES
         O5 ord-init-late  Random runs from an EARLIER initialization         NO   b-first
         O6 / O7           the same order through site: and call: events      YES / NO
    R  --preset before-app-run --a <event>   (B = app-run:*)
         R1 bar-yes  LoadConfig; Application.Run     YES
         R2 bar-no   Application.Run; LoadConfig     NO
         R3 bar-may  if .. then LoadConfig; Run      MAY  a-not-on-every-path
    F  --preset format-settings   (A = extwrite:FormatSettings, B = extcall: of the RTL formatters)
         F1 fs-yes YES   F2 fs-no NO a-never-happens   F3 fs-may MAY
    K  pre-check
         K1 pre      no routine that performs A reaches B: MAY with ZERO routine bodies solved
         K2 pre-ctl  the twin where Boot calls both: the pre-check must not refute -> YES
  V* check the index holds what the cases lean on.

  -BaseExe <engine at the HB4 commit>: asserts THAT engine answers MAY for O1, does not know the
  presets and solves routine bodies for K1 (the RED of the lane).

  Run from a NEUTRAL CWD (C:\TEMP), pwsh 7.
#>
[CmdletBinding()]
param([string]$Exe = '', [string]$BaseExe = '', [string]$WorkDir = '', [switch]$KeepScratch)

$ErrorActionPreference = 'Stop'
if ($PSVersionTable.PSVersion.Major -lt 7) { Write-Host 'run_v156_HB5: needs pwsh 7' -ForegroundColor Red; exit 2 }
$repo = (Resolve-Path "$PSScriptRoot\..\..").Path
if ($Exe -eq '') {
  $Exe = Join-Path $repo 'src\cli\Win64\Debug\drag-lint.exe'
  if (-not (Test-Path $Exe)) { $Exe = Join-Path $repo 'third_party\dll-win64\drag-lint.exe' }
}
if (-not (Test-Path $Exe)) { Write-Host "run_v156_HB5: no engine at $Exe" -ForegroundColor Red; exit 2 }
$fxSrc = Join-Path $repo 'tests\fixtures\v156-hb5'
if ($WorkDir -eq '') { $WorkDir = Join-Path $env:TEMP ('dl-v156-hb5-' + [Guid]::NewGuid().ToString('N').Substring(0, 8)) }
New-Item -ItemType Directory -Force $WorkDir | Out-Null

$script:fail = 0
$script:pass = 0
function Check([string]$Name, [bool]$Ok, [string]$Detail = '') {
  if ($Ok) { $script:pass++; Write-Host "  PASS  $Name  $Detail" -ForegroundColor Green }
  else     { $script:fail++; Write-Host "  FAIL  $Name  $Detail" -ForegroundColor Red }
}

# One SELECT -> array of PSCustomObject (rows of `sql --json` are POSITIONAL; mapped onto columns[].name).
function Lane-Sql([string]$Engine, [string]$Db, [string]$Query) {
  $raw = & { $ErrorActionPreference = 'Continue'; & $Engine sql --query $Query --db $Db --json --limit 1000 2>$null }
  if ($LASTEXITCODE -ne 0 -or -not $raw) { return ,@() }
  try { $j = ($raw -join "`n") | ConvertFrom-Json | ForEach-Object { $_ } } catch { return ,@() }
  $cols = @($j.columns | ForEach-Object { if ($_ -is [string]) { $_ } else { $_.name } })
  $out = New-Object System.Collections.Generic.List[object]
  foreach ($r in @($j.rows)) {
    $o = [ordered]@{}
    for ($i = 0; $i -lt $cols.Count; $i++) { $o[$cols[$i]] = $r[$i] }
    $out.Add([pscustomobject]$o)
  }
  return ,$out.ToArray()
}

function Lane-Index([string]$Engine, [string]$Folder) {
  $fx = Join-Path $WorkDir "fx-$Folder"
  New-Item -ItemType Directory -Force $fx | Out-Null
  Copy-Item (Join-Path $fxSrc "$Folder\*") $fx -Force
  $db = Join-Path $WorkDir "hb5-$Folder.sqlite"
  $log = Join-Path $WorkDir "index-$Folder.log"
  & { $ErrorActionPreference = 'Continue'; & $Engine index $fx --db $db *> $log }
  return @{ rc = $LASTEXITCODE; db = $db; fx = $fx }
}

# happens-before -> @{ rc; out (stdout lines); err (stderr text); j (parsed JSON or $null) }
function Lane-Ask([string]$Engine, [string[]]$VerbArgs) {
  $errFile = Join-Path $WorkDir 'stderr.txt'
  $raw = & { $ErrorActionPreference = 'Continue'; & $Engine happens-before @VerbArgs 2>$errFile }
  $rc = $LASTEXITCODE
  $j = $null
  if ($raw) { try { $j = (($raw -join "`n") | ConvertFrom-Json | ForEach-Object { $_ }) } catch { $j = $null } }
  $err = if (Test-Path $errFile) { [IO.File]::ReadAllText($errFile) } else { '' }
  return [pscustomobject]@{ rc = $rc; out = @($raw); err = $err; j = $j }
}

# One verdict check: verdict, exit code and (optional) reason / method code.
function Check-Verdict([string]$Name, $Ans, [string]$Verdict, [string]$Reason = '', [string]$Method = '') {
  $v = if ($Ans.j) { [string]$Ans.j.verdict } else { '(no JSON)' }
  $wantRc = if ($Verdict -eq 'YES') { 0 } else { 1 }
  $reasons = @(if ($Ans.j) { $Ans.j.reasons } else { @() })
  $methods = @(if ($Ans.j) { $Ans.j.methods } else { @() })
  $ok = ($v -eq $Verdict) -and ($Ans.rc -eq $wantRc)
  if ($Reason -ne '') { $ok = $ok -and ($reasons -contains $Reason) }
  if ($Method -ne '') { $ok = $ok -and ($methods -contains $Method) }
  $want = "want $Verdict rc=$wantRc" + $(if ($Reason) { " reason $Reason" } else { '' }) + $(if ($Method) { " method $Method" } else { '' })
  Check $Name $ok "verdict=$v rc=$($Ans.rc) reasons=[$($reasons -join ',')] methods=[$($methods -join ',')] ($want) $($Ans.err.Trim())"
}

Write-Host "run_v156_HB5: engine $Exe"
Write-Host "run_v156_HB5: scratch $WorkDir"

function Ask-Preset([string]$Engine, [string]$Folder, [string[]]$More) {
  $ix = Lane-Index $Engine $Folder
  if ($ix.rc -ne 0) { Check "I $Folder indexes" $false "rc=$($ix.rc)" }
  return [pscustomobject]@{ ix = $ix; a = (Lane-Ask $Engine (@($More) + @('--db', $ix.db, '--json'))) }
}
$rnd = @('--preset', 'randomize')
$bar = @('--preset', 'before-app-run', '--a', 'call:uCfg.LoadConfig')
$fs = @('--preset', 'format-settings')

# ---- RED of the lane, on request ------------------------------------------------------------
if ($BaseExe -ne '') {
  $b = Ask-Preset $BaseExe 'ord-yes' $rnd
  Check-Verdict 'BASE O1 the HB4 engine cannot order the program block: MAY' $b.a 'MAY'
  $b = Ask-Preset $BaseExe 'bar-yes' $bar
  Check 'BASE R1 the HB4 engine does not know --preset before-app-run' ($b.a.rc -eq 2 -and $null -eq $b.a.j) "rc=$($b.a.rc) $($b.a.err.Trim())"
  $b = Ask-Preset $BaseExe 'fs-yes' $fs
  Check 'BASE F1 the HB4 engine does not know --preset format-settings' ($b.a.rc -eq 2 -and $null -eq $b.a.j) "rc=$($b.a.rc)"
  $b = Ask-Preset $BaseExe 'pre' $rnd
  Check 'BASE K1 the HB4 engine solves routine bodies for the unreachable case' ($b.a.j -and [int]$b.a.j.budget.routines -gt 0 -and @($b.a.j.limits) -notcontains 'pre-check') "routines=$($b.a.j.budget.routines)"
}

# ---- O: program order -----------------------------------------------------------------------
$o1 = Ask-Preset $Exe 'ord-yes' $rnd
$v = Lane-Sql $Exe $o1.ix.db "SELECT r.name_text, r.enclosing_symbol_id FROM refs r WHERE r.name_text = 'Randomize' AND r.symbol_id IS NULL"
Check 'V1 ord-yes: the Randomize ref sits in the program block (no enclosing routine)' ((@($v).Count -eq 1) -and ($null -eq $v[0].enclosing_symbol_id)) "rows=$(@($v).Count)"
Check-Verdict 'O1 Randomize; RunGame in the program block' $o1.a 'YES' '' 'program-order'
$o2 = Ask-Preset $Exe 'ord-no' $rnd
Check-Verdict 'O2 RunGame; Randomize (twin of O1, statements swapped)' $o2.a 'NO' 'b-first' 'program-order'
$o3 = Ask-Preset $Exe 'ord-may' $rnd
Check-Verdict 'O3 if .. then Randomize; RunGame (twin of O1, conditional)' $o3.a 'MAY'
$o4 = Ask-Preset $Exe 'ord-init' $rnd
Check-Verdict 'O4 Randomize in an initialization section, Random from the program block' $o4.a 'YES' '' 'program-order'
$o5 = Ask-Preset $Exe 'ord-init-late' $rnd
Check-Verdict 'O5 Random runs from an EARLIER initialization (twin of O4)' $o5.a 'NO' 'b-first' 'program-order'
$dpr = Join-Path $o1.ix.fx 'OrdYes.dpr'
$a = Lane-Ask $Exe @('--a', "site:${dpr}:10", '--b', 'call:uOrdGame.RunGame', '--db', $o1.ix.db, '--json')
Check-Verdict 'O6 site: (the Randomize line) before call:RunGame' $a 'YES' '' 'program-order'
$a = Lane-Ask $Exe @('--a', 'call:uOrdGame.RunGame', '--b', "site:${dpr}:10", '--db', $o1.ix.db, '--json')
Check-Verdict 'O7 the same two events the other way round' $a 'NO' 'b-first' 'program-order'
$sec = Join-Path $o4.ix.fx 'uSeed.pas'
$a = Lane-Ask $Exe @('--a', "site:${sec}:10", '--b', 'extcall:Random', '--db', $o4.ix.db, '--json')
Check-Verdict 'O8 site: of a line in an initialization section is placed by its section' $a 'YES' '' 'program-order'

# ---- R: --preset before-app-run -------------------------------------------------------------
$r1 = Ask-Preset $Exe 'bar-yes' $bar
Check-Verdict 'R1 LoadConfig; Application.Run' $r1.a 'YES' '' 'program-order'
Check 'R1b the answer names the preset and B = app-run:* with one site' ($r1.a.j -and $r1.a.j.preset -eq 'before-app-run' -and $r1.a.j.b.event -eq 'app-run:*' -and @($r1.a.j.b.sites).Count -eq 1) "b=$($r1.a.j.b.event)"
$r2 = Ask-Preset $Exe 'bar-no' $bar
Check-Verdict 'R2 Application.Run; LoadConfig (twin of R1, statements swapped)' $r2.a 'NO' 'b-first' 'program-order'
$r3 = Ask-Preset $Exe 'bar-may' $bar
Check-Verdict 'R3 if .. then LoadConfig; Application.Run (twin of R1, conditional)' $r3.a 'MAY' 'a-not-on-every-path'
$x = Lane-Ask $Exe @('--preset', 'before-app-run', '--db', $r1.ix.db)
Check 'R4 before-app-run without --a -> exit 2' ($x.rc -eq 2 -and $x.err -match '--a') "rc=$($x.rc)"
$x = Lane-Ask $Exe @('--preset', 'before-app-run', '--a', 'call:uCfg.LoadConfig', '--b', 'extcall:Random', '--db', $r1.ix.db)
Check 'R5 before-app-run with --b -> exit 2' ($x.rc -eq 2) "rc=$($x.rc)"
$x = Lane-Ask $Exe @('--preset', 'randomize', '--a', 'call:uCfg.LoadConfig', '--db', $r1.ix.db)
Check 'R6 a preset that names both events still refuses --a -> exit 2' ($x.rc -eq 2 -and $x.err -match 'both events') "rc=$($x.rc)"
$a = Lane-Ask $Exe @('--a', 'call:uCfg.LoadConfig', '--b', 'app-run:BarYes', '--db', $r1.ix.db, '--json')
Check-Verdict 'R7 the event app-run:<program> by name' $a 'YES' '' 'program-order'
$x = Lane-Ask $Exe @('--a', 'call:uCfg.LoadConfig', '--b', 'app-run:NoSuchProgram', '--db', $r1.ix.db)
Check 'R8 app-run: of a program the index does not hold -> exit 2' ($x.rc -eq 2 -and $x.err -match 'no program') "rc=$($x.rc)"
$a = Lane-Ask $Exe @('--preset', 'before-app-run', '--a', 'extcall:Randomize', '--db', $o1.ix.db, '--json')
Check-Verdict 'R9 a program without Application.Run: nothing to judge' $a 'MAY' 'no-b-site'

# ---- F: --preset format-settings ------------------------------------------------------------
$f1 = Ask-Preset $Exe 'fs-yes' $fs
$v = Lane-Sql $Exe $f1.ix.db "SELECT r.kind, r.symbol_id FROM refs r WHERE r.name_text = 'FormatSettings' AND r.kind IN ('write', 'write-through')"
Check 'V2 fs-yes: the index holds one UNRESOLVED write(-through) ref of FormatSettings' ((@($v).Count -eq 1) -and ($null -eq $v[0].symbol_id)) "rows=$(@($v).Count)"
Check-Verdict 'F1 FormatSettings.X:= ..; FloatToStr' $f1.a 'YES' '' 'same-routine'
Check 'F1b A = extwrite:FormatSettings, limit matched-by-name' ($f1.a.j -and $f1.a.j.a.event -eq 'extwrite:FormatSettings' -and @($f1.a.j.limits) -contains 'matched-by-name') "a=$($f1.a.j.a.event)"
$f2 = Ask-Preset $Exe 'fs-no' $fs
Check-Verdict 'F2 nothing writes FormatSettings (twin of F1)' $f2.a 'NO' 'a-never-happens'
$f3 = Ask-Preset $Exe 'fs-may' $fs
Check-Verdict 'F3 the write is in another routine (twin of F1)' $f3.a 'MAY'
$a = Lane-Ask $Exe @('--a', 'extwrite:FormatSettings', '--b', 'extcall:StrToFloat, SysUtils.FloatToStr', '--db', $f1.ix.db, '--json')
Check-Verdict 'F4 extwrite: and an extcall: name list as plain events' $a 'YES' '' 'same-routine'
Check 'F4b the list is normalised: extcall:StrToFloat,FloatToStr' ($a.j -and $a.j.b.event -eq 'extcall:StrToFloat,FloatToStr') "b=$($a.j.b.event)"
$a = Lane-Ask $Exe @('--a', 'extwrite:FormatSettings', '--b', 'extcall:StrToFloat', '--db', $f1.ix.db, '--json')
Check-Verdict 'F5 a list that leaves the one call out has no B site' $a 'MAY' 'no-b-site'

# ---- K: pre-check ---------------------------------------------------------------------------
$k1 = Ask-Preset $Exe 'pre' $rnd
Check-Verdict 'K1 no routine that performs A reaches B' $k1.a 'MAY' 'a-in-other-routine'
Check 'K1b answered by the pre-check: limit pre-check, 0 routine bodies solved' ($k1.a.j -and @($k1.a.j.limits) -contains 'pre-check' -and [int]$k1.a.j.budget.routines -eq 0 -and @($k1.a.j.judged | Where-Object { $_.why -match '^pre-check' }).Count -eq 1) "limits=[$(@($k1.a.j.limits) -join ',')] routines=$($k1.a.j.budget.routines)"
$k2 = Ask-Preset $Exe 'pre-ctl' $rnd
Check-Verdict 'K2 Boot calls SeedIt, then Roll (twin of K1): the pre-check must not refute' $k2.a 'YES'
Check 'K2b no pre-check limit on the twin' ($k2.a.j -and @($k2.a.j.limits) -notcontains 'pre-check') "limits=[$(@($k2.a.j.limits) -join ',')]"

# ---- T: help --------------------------------------------------------------------------------
$h = Lane-Ask $Exe @('--help')
$help = $h.out -join "`n"
Check 'T1 --help lists the three presets and the new event kinds' ($h.rc -eq 0 -and $help -match 'randomize' -and $help -match 'before-app-run' -and $help -match 'format-settings' -and $help -match 'extwrite:' -and $help -match 'app-run:' -and $help -match 'program-order') "rc=$($h.rc)"

if (-not $KeepScratch) { try { [IO.Directory]::Delete($WorkDir, $true) } catch { } }
Write-Host ("run_v156_HB5: {0} passed, {1} failed" -f $script:pass, $script:fail) -ForegroundColor $(if ($script:fail -eq 0) { 'Green' } else { 'Red' })
exit $(if ($script:fail -eq 0) { 0 } else { 1 })
