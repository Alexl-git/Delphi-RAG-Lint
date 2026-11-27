<#
  run_v156_HB4.ps1 -- 1.56 lane HB4: the verb `happens-before --a <event> --b <event>` (G-56) and
  its preset `randomize`.

  Indexes tests\fixtures\v156-hb4\main (one unit, one routine per case) and the three one-unit
  folders rnd-yes / rnd-no / rnd-may into scratch DBs and asks `happens-before --json`.

  POSITIVE CONTROL: the cases come in families that differ by ONE construct and must give
  DIFFERENT verdicts, so an engine that answers one verdict for everything (or the W2FRAME stub,
  which answers nothing) fails most of the checks:
    W1 write; read          YES      W2 read; write            NO       W3 ExtFill(G); read   MAY
    C1 Open; Work           YES      C2 Work; Open             NO       C3 if .. Open; Work   MAY
    S1 first -> second      YES      S2 second -> first        NO
    P1 Randomize; Random    YES      P2 Random only            NO       P3 two routines       MAY
  V1 checks the index really holds the unresolved ExtFill call W3 / W4 lean on.

    W   write: / read: events on a unit variable
          W1 write then read, one routine                      YES  same-routine
          W2 read then write                                   NO   b-first
          W3 the only writer is an unresolved call (ExtFill)   MAY  a-site-uncertain
          W4 read, then the unresolved call                    NO   b-first
          W5 write under a condition                           MAY  a-not-on-every-path
          W6 the write is in a callee that always performs it  YES  callee
          W7 the read is in a callee called after the write    YES  callers
          W8 nothing writes it                                 NO   a-never-happens
          D1 write + read at the top of an initialization      YES  check-init (the 1.52 solver)
    C   call: events                                           C1 YES, C2 NO, C3 MAY
    S   site: events (file:line)                               S1 YES, S2 NO
    P   --preset randomize (A = extcall:Randomize, B = extcall:Random)   P1 YES, P2 NO, P3 MAY
    X   exit codes: 0 YES, 1 NO / MAY, 2 usage, 3 unknown flag
    T   text output; --help

  -BaseExe <engine without the lane>: asserts THAT engine refuses the verb (the RED of the lane).

  Run from a NEUTRAL CWD (C:\TEMP), pwsh 7.
#>
[CmdletBinding()]
param([string]$Exe = '', [string]$BaseExe = '', [string]$WorkDir = '', [switch]$KeepScratch)

$ErrorActionPreference = 'Stop'
if ($PSVersionTable.PSVersion.Major -lt 7) { Write-Host 'run_v156_HB4: needs pwsh 7' -ForegroundColor Red; exit 2 }
$repo = (Resolve-Path "$PSScriptRoot\..\..").Path
if ($Exe -eq '') {
  $Exe = Join-Path $repo 'src\cli\Win64\Debug\drag-lint.exe'
  if (-not (Test-Path $Exe)) { $Exe = Join-Path $repo 'third_party\dll-win64\drag-lint.exe' }
}
if (-not (Test-Path $Exe)) { Write-Host "run_v156_HB4: no engine at $Exe" -ForegroundColor Red; exit 2 }
$fxSrc = Join-Path $repo 'tests\fixtures\v156-hb4'
if ($WorkDir -eq '') { $WorkDir = Join-Path $env:TEMP ('dl-v156-hb4-' + [Guid]::NewGuid().ToString('N').Substring(0, 8)) }
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
  Copy-Item (Join-Path $fxSrc "$Folder\*.pas") $fx -Force
  $db = Join-Path $WorkDir "hb4-$Folder.sqlite"
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

Write-Host "run_v156_HB4: engine $Exe"
Write-Host "run_v156_HB4: scratch $WorkDir"

# ---- RED of the lane, on request ------------------------------------------------------------
if ($BaseExe -ne '') {
  $b = Lane-Ask $BaseExe @('--a', 'write:GFwd', '--b', 'read:GFwd', '--db', (Join-Path $WorkDir 'none.sqlite'), '--json')
  Check 'BASE the engine without the lane does not know the verb' (($b.rc -ne 0) -and ($b.rc -ne 1) -and ($null -eq $b.j) -and ($b.err -match 'not built|[Uu]nknown')) "rc=$($b.rc) $($b.err.Trim())"
}

# ---- index ----------------------------------------------------------------------------------
$main = Lane-Index $Exe 'main'
Check 'I0 the main fixture indexes' ($main.rc -eq 0 -and (Test-Path $main.db)) "rc=$($main.rc)"
$db = $main.db
$unit = Join-Path $main.fx 'uHb4.pas'

# ---- V: vacuity -----------------------------------------------------------------------------
$ext = Lane-Sql $Exe $db "SELECT r.kind, r.symbol_id FROM refs r WHERE r.name_text = 'ExtFill'"
Check 'V1 the index holds two UNRESOLVED ExtFill refs' ((@($ext).Count -eq 2) -and (@($ext | Where-Object { $null -ne $_.symbol_id }).Count -eq 0)) "rows=$(@($ext).Count)"

# ---- W: write / read ------------------------------------------------------------------------
function Ask-Var([string]$Name) { return Lane-Ask $Exe @('--a', "write:uHb4.$Name", '--b', "read:uHb4.$Name", '--db', $db, '--json') }
$w1 = Ask-Var 'GFwd'
Check-Verdict 'W1 write then read in one routine' $w1 'YES' '' 'same-routine'
Check 'W1 the answer is proven and names both events' ($w1.j -and $w1.j.proven -eq $true -and $w1.j.a.event -eq 'write:uHb4.GFwd' -and $w1.j.b.event -eq 'read:uHb4.GFwd' -and @($w1.j.a.sites).Count -eq 1 -and @($w1.j.b.sites).Count -eq 1) ''
Check-Verdict 'W2 read then write (reversed)' (Ask-Var 'GRev') 'NO' 'b-first'
$w3 = Ask-Var 'GUnk'
Check-Verdict 'W3 across an unresolved call' $w3 'MAY' 'a-site-uncertain'
Check 'W3 is not proven' ($w3.j -and $w3.j.proven -eq $false) ''
Check-Verdict 'W4 read, then the unresolved call' (Ask-Var 'GUnkAfter') 'NO' 'b-first'
Check-Verdict 'W5 write under a condition' (Ask-Var 'GBr') 'MAY' 'a-not-on-every-path'
Check-Verdict 'W6 write inside a callee that always performs it' (Ask-Var 'GVia') 'YES' '' 'callee'
Check-Verdict 'W7 read inside a callee called after the write' (Ask-Var 'GCaller') 'YES' '' 'callers'
Check-Verdict 'W8 nothing writes it' (Ask-Var 'GNever') 'NO' 'a-never-happens'
Check-Verdict 'D1 initialization section: answered by the check-init solver' (Ask-Var 'GInit') 'YES' '' 'check-init'

# ---- C: call --------------------------------------------------------------------------------
function Ask-Call([string]$A, [string]$B) { return Lane-Ask $Exe @('--a', "call:uHb4.$A", '--b', "call:uHb4.$B", '--db', $db, '--json') }
Check-Verdict 'C1 Open1 then Work1' (Ask-Call 'Open1' 'Work1') 'YES' '' 'same-routine'
Check-Verdict 'C2 Work2 then Open2 (reversed)' (Ask-Call 'Open2' 'Work2') 'NO' 'b-first'
Check-Verdict 'C3 Open3 under a condition' (Ask-Call 'Open3' 'Work3') 'MAY' 'a-not-on-every-path'

# ---- S: site --------------------------------------------------------------------------------
$lines = [IO.File]::ReadAllLines($unit)
$first = 0; $second = 0
for ($i = 0; $i -lt $lines.Count; $i++) {
  if ($lines[$i] -match '\{SITE-FIRST\}') { $first = $i + 1 }
  if ($lines[$i] -match '\{SITE-SECOND\}') { $second = $i + 1 }
}
Check 'S0 the site markers are in the fixture' ($first -gt 0 -and $second -eq $first + 1) "first=$first second=$second"
Check-Verdict 'S1 site first -> second' (Lane-Ask $Exe @('--a', "site:uHb4.pas:$first", '--b', "site:uHb4.pas:$second", '--db', $db, '--json')) 'YES' '' 'same-routine'
Check-Verdict 'S2 site second -> first (reversed)' (Lane-Ask $Exe @('--a', "site:uHb4.pas:$second", '--b', "site:uHb4.pas:$first", '--db', $db, '--json')) 'NO' 'b-first'
Check-Verdict 'S3 mixed kinds: write:GFwd before the site of its read' (Lane-Ask $Exe @('--a', 'write:uHb4.GFwd', '--b', 'call:uHb4.Sink', '--db', $db, '--json')) 'MAY' ''

# ---- P: preset randomize --------------------------------------------------------------------
foreach ($p in @(@('rnd-yes', 'YES', '', 'P1 Randomize then Random in one routine'),
                 @('rnd-no', 'NO', 'a-never-happens', 'P2 Random without any Randomize'),
                 @('rnd-may', 'MAY', 'a-in-other-routine', 'P3 Randomize and Random in two unordered routines'))) {
  $ix = Lane-Index $Exe $p[0]
  $a = Lane-Ask $Exe @('--preset', 'randomize', '--db', $ix.db, '--json')
  Check-Verdict "$($p[3])" $a $p[1] $p[2]
  Check "$($p[3].Substring(0, 2)) the answer names the preset and its two events" ($a.j -and $a.j.preset -eq 'randomize' -and $a.j.a.event -eq 'extcall:Randomize' -and $a.j.b.event -eq 'extcall:Random') ''
}

# ---- X: usage and exit codes ----------------------------------------------------------------
$x = Lane-Ask $Exe @('--b', 'read:uHb4.GFwd', '--db', $db)
Check 'X1 --a missing -> exit 2, nothing on stdout' ($x.rc -eq 2 -and @($x.out).Count -eq 0 -and $x.err -match '--a') "rc=$($x.rc)"
$x = Lane-Ask $Exe @('--a', 'frob:uHb4.GFwd', '--b', 'read:uHb4.GFwd', '--db', $db)
Check 'X2 unknown event kind -> exit 2, names the kinds' ($x.rc -eq 2 -and $x.err -match 'write:' -and $x.err -match 'site:') "rc=$($x.rc)"
$x = Lane-Ask $Exe @('--a', 'write:uHb4.GNoSuch', '--b', 'read:uHb4.GFwd', '--db', $db)
Check 'X3 unknown target -> exit 2' ($x.rc -eq 2 -and @($x.out).Count -eq 0) "rc=$($x.rc) $($x.err.Trim())"
$x = Lane-Ask $Exe @('--preset', 'no-such-preset', '--db', $db)
Check 'X4 unknown preset -> exit 2, lists randomize' ($x.rc -eq 2 -and $x.err -match 'randomize') "rc=$($x.rc)"
$x = Lane-Ask $Exe @('--preset', 'randomize', '--a', 'write:uHb4.GFwd', '--db', $db)
Check 'X5 --preset with --a -> exit 2' ($x.rc -eq 2) "rc=$($x.rc)"
$x = Lane-Ask $Exe @('--a', 'write:uHb4.GFwd', '--b', 'read:uHb4.GFwd', '--db', $db, '--frobnicate')
Check 'X6 unknown flag -> exit 3' ($x.rc -eq 3 -and $x.err -match 'frobnicate') "rc=$($x.rc)"
$x = Lane-Ask $Exe @('--a', 'write:uHb4.GFwd', '--b', 'read:uHb4.GFwd', '--db', (Join-Path $WorkDir 'missing.sqlite'))
Check 'X7 missing --db file -> exit 2' ($x.rc -eq 2 -and @($x.out).Count -eq 0) "rc=$($x.rc)"
$x = Lane-Ask $Exe @('--a', 'call:uHb4.NoSuchRoutine', '--b', 'call:uHb4.Work1', '--db', $db)
Check 'X8 call: of a routine the index does not hold -> exit 2, points at extcall:' ($x.rc -eq 2 -and $x.err -match 'extcall:') "rc=$($x.rc)"

# ---- T: text and help -----------------------------------------------------------------------
$t = Lane-Ask $Exe @('--a', 'write:uHb4.GFwd', '--b', 'read:uHb4.GFwd', '--db', $db)
$text = $t.out -join "`n"
Check 'T1 text: header, verdict line, one B row' ($t.rc -eq 0 -and $text -match '(?m)^happens-before\s' -and $text -match '(?m)^verdict\s+YES' -and $text -match 'uHb4\.pas:\d+:\d+') ''
$t = Lane-Ask $Exe @('--a', 'write:uHb4.GUnk', '--b', 'read:uHb4.GUnk', '--db', $db)
Check 'T2 text of a MAY names the unresolved call site' ($t.rc -eq 1 -and ($t.out -join "`n") -match '(?m)^verdict\s+MAY' -and ($t.out -join "`n") -match 'ExtFill') ''
$h = Lane-Ask $Exe @('--help')
Check 'T3 --help prints the usage with every event kind and the preset' ($h.rc -eq 0 -and ($h.out -join "`n") -match '--a' -and ($h.out -join "`n") -match 'extcall:' -and ($h.out -join "`n") -match 'randomize') "rc=$($h.rc)"

if (-not $KeepScratch) { try { [IO.Directory]::Delete($WorkDir, $true) } catch { } }
Write-Host ("run_v156_HB4: {0} passed, {1} failed" -f $script:pass, $script:fail) -ForegroundColor $(if ($script:fail -eq 0) { 'Green' } else { 'Red' })
exit $(if ($script:fail -eq 0) { 0 } else { 1 })
