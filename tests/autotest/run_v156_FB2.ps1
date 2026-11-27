<#
  run_v156_FB2.ps1 -- 1.56 lane FB-2: happens-before phase 3 -- check-init reads the index's
  indirect-call edges (indirect_edges, lane EXT-C2) and stored must-write facts
  (symbol_facts.must_writes, lane EXT-C1), and keeps its 1.55 argument events on a numeric target
  (data_flows.val_class, lane EXT-B1; REQUESTS line 47).

  Indexes tests\fixtures\v156-fb2 (three units) into a scratch DB and asks `check-init --json`.
  Every SET case has a twin that differs by one construct and must stay MAY-BE-UNSET with a named
  reason, so a stub engine that answers one verdict for everything fails half of the checks.

    I   indirect edges (uFb2Ind.pas). A routine that reads a unit variable and is only NAMED as a
        value (callback argument, procedural variable, event property) was an escaped root in 1.55
        (MAY-BE-UNSET, escaped-routine + indirect-call). With edges it runs only where its slot is
        called:
          I1 callback argument, called after the write        SET + relied-on-indirect-edges
          I2 twin: called before the write                    MAY-BE-UNSET, no escaped-routine
          I3 twin: the slot is also copied away               MAY-BE-UNSET, escaped-routine
          I4 unit-level procedural variable                   SET + relied-on-indirect-edges
          I5 twin: two-line binding, the index has no edge    MAY-BE-UNSET, escaped-routine
          I6 event property over a field, fired after write   SET + relied-on-indirect-edges
          I7 callback that writes before it reads             SET, NOT relied-on-indirect-edges
    F   must-write facts (uFb2Fields.pas), --max-routines 2 on a class with 10 methods:
          F1 FList, set by Init (fact: must_writes = FList)   SET, not exhausted (1.55: budget)
          F2 twin FCount, set under a condition               MAY-BE-UNSET + ctor-misses-field,
                                                              not budget
    A   numeric by-ref argument (uFb2Arg.pas): the writers of GTotal are the var arguments of the
        two Fill calls and its uses the two plain reads, as in 1.55 -- the VALUE row of
        `Show(Seen)` (source GTotal, no read of it on that line) is not an argument event.
    D   the same on a copy of the index that also holds rows with the 1.56 source kinds `dsfield`
        (lane EXT-B3) and `except` (lane EXT-B2) named like the target: they are no argument events.
        The rows are written with python (sqlite3); without python D0 FAILS, it does not skip.
    V   vacuity: the index really holds indirect_edges rows, the must_writes fact of Init and a
        VALUE row for GTotal -- without them I / F / A would pass or fail for the wrong reason.

  -BaseExe <engine without the lane>: prints what THAT engine answers for the I1 / I4 / I6 / F1 / A
  cases (the RED of the lane) and asserts it differs; optional.

  Run from a NEUTRAL CWD (C:\TEMP), pwsh 7.
#>
[CmdletBinding()]
param([string]$Exe = '', [string]$BaseExe = '', [string]$WorkDir = '', [switch]$KeepScratch)

$ErrorActionPreference = 'Stop'
if ($PSVersionTable.PSVersion.Major -lt 7) { Write-Host 'run_v156_FB2: needs pwsh 7' -ForegroundColor Red; exit 2 }
$repo = (Resolve-Path "$PSScriptRoot\..\..").Path
if ($Exe -eq '') {
  $Exe = Join-Path $repo 'src\cli\Win64\Debug\drag-lint.exe'
  if (-not (Test-Path $Exe)) { $Exe = Join-Path $repo 'third_party\dll-win64\drag-lint.exe' }
}
if (-not (Test-Path $Exe)) { Write-Host "run_v156_FB2: no engine at $Exe" -ForegroundColor Red; exit 2 }
$fxSrc = Join-Path $repo 'tests\fixtures\v156-fb2'
if ($WorkDir -eq '') { $WorkDir = Join-Path $env:TEMP ('dl-v156-fb2-' + [Guid]::NewGuid().ToString('N').Substring(0, 8)) }
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

# check-init --json -> the answer object, or $null (exit 2 / no JSON).
function Lane-Answer([string]$Engine, [string]$Db, [string]$Target, [string[]]$More = @()) {
  $raw = & { $ErrorActionPreference = 'Continue'; & $Engine check-init $Target --db $Db --json @More 2>$null }
  if (-not $raw) { return $null }
  try { return (($raw -join "`n") | ConvertFrom-Json | ForEach-Object { $_ }) } catch { return $null }
}

function Lane-Index([string]$Engine, [string]$Tag) {
  $fx = Join-Path $WorkDir "fx-$Tag"
  New-Item -ItemType Directory -Force $fx | Out-Null
  Copy-Item (Join-Path $fxSrc '*.pas') $fx -Force
  $db = Join-Path $WorkDir "fb2-$Tag.sqlite"
  $log = Join-Path $WorkDir "index-$Tag.log"
  & { $ErrorActionPreference = 'Continue'; & $Engine index $fx --db $db *> $log }
  return @{ rc = $LASTEXITCODE; db = $db; fx = $fx }
}

# The one judged use of a target: verdict + reasons + why, as the checks read them.
function Use-Of($Answer) {
  if ($null -eq $Answer) { return [pscustomobject]@{ verdict = '(no answer)'; reasons = @(); why = ''; n = 0 } }
  $uses = @($Answer.uses)
  $u = if ($uses.Count -gt 0) { $uses[0] } else { $null }
  return [pscustomobject]@{
    verdict = [string]$Answer.verdict
    reasons = @(if ($u) { $u.reasons } else { @() }) + @($Answer.reasons) | Where-Object { $_ } | Select-Object -Unique
    why     = if ($u) { [string]$u.why } else { '' }
    n       = $uses.Count
  }
}
function Show($U) { return "verdict=$($U.verdict) reasons=[$(@($U.reasons) -join ',')]" }

Write-Host '== run_v156_FB2: check-init on indirect edges, must-write facts and value rows ==' -ForegroundColor Cyan
$ix = Lane-Index $Exe 'lane'
Check 'index of the fixture exits 0' ($ix.rc -eq 0) "rc=$($ix.rc)"
$db = $ix.db

# ---- V: the facts the cases stand on ------------------------------------------------------------
$edges = Lane-Sql $Exe $db "SELECT t.name AS target, e.kind FROM indirect_edges e JOIN symbols t ON t.id = e.target_symbol_id WHERE e.ref_id IS NOT NULL ORDER BY t.name"
$edgeNames = @($edges | ForEach-Object { $_.target })
Check 'V1 indirect_edges holds the edges of UseCfg1 / UseCfg4 / Tick' (($edgeNames -contains 'UseCfg1') -and ($edgeNames -contains 'UseCfg4') -and ($edgeNames -contains 'Tick')) "targets=$($edgeNames -join ',')"
Check 'V2 no edge for the two-line binding of UseCfg5 (the I5 twin stands on it)' (-not ($edgeNames -contains 'UseCfg5')) ''
$mw = Lane-Sql $Exe $db "SELECT s.name, f.must_writes FROM symbol_facts f JOIN symbols s ON s.id = f.symbol_id WHERE s.qualified_name LIKE 'uFb2Fields.TFbBig.Init%' ORDER BY s.name"
$mwInit = @($mw | Where-Object { $_.name -eq 'Init' })
$mwMaybe = @($mw | Where-Object { $_.name -eq 'InitMaybe' })
Check 'V3 must_writes of TFbBig.Init is FList' (($mwInit.Count -eq 1) -and ($mwInit[0].must_writes -eq 'FList')) "rows=$($mwInit.Count) value=$(if ($mwInit.Count) { $mwInit[0].must_writes })"
Check 'V4 must_writes of TFbBig.InitMaybe is empty (conditional write)' (($mwMaybe.Count -eq 1) -and ([string]$mwMaybe[0].must_writes -eq '')) ''
$vr = Lane-Sql $Exe $db "SELECT d.val_class, d.dst_line FROM data_flows d WHERE d.dst_kind = 'arg' AND d.src_name = 'GTotal' ORDER BY d.dst_line, d.val_class"
Check 'V5 data_flows holds a VALUE arg row for GTotal (val_class <> empty)' (@($vr | Where-Object { [string]$_.val_class -ne '' }).Count -ge 1) "rows=$(@($vr).Count)"

# ---- I: indirect edges --------------------------------------------------------------------------
$set = 'relied-on-indirect-edges'
foreach ($c in @(
    @{ id = 'I1'; target = 'uFb2Ind.GCfg1'; what = 'callback argument called after the write' },
    @{ id = 'I4'; target = 'uFb2Ind.GCfg4'; what = 'unit-level procedural variable' },
    @{ id = 'I6'; target = 'uFb2Ind.GCfg6'; what = 'event property over a field' })) {
  $u = Use-Of (Lane-Answer $Exe $db $c.target)
  Check "$($c.id) $($c.what): SET" ($u.verdict -eq 'SET') (Show $u)
  Check "$($c.id) the SET names what it relied on ($set)" ((@($u.reasons) -contains $set) -and ($u.why -match 'runs only through')) "why=$($u.why)"
}
$u7 = Use-Of (Lane-Answer $Exe $db 'uFb2Ind.GCfg7')
Check 'I7 a use proven inside its own routine relies on no edge: SET without relied-on-indirect-edges' (($u7.verdict -eq 'SET') -and (-not (@($u7.reasons) -contains $set))) (Show $u7)
$u2 = Use-Of (Lane-Answer $Exe $db 'uFb2Ind.GCfg2')
Check 'I2 twin (callback runs before the write): MAY-BE-UNSET' ($u2.verdict -eq 'MAY-BE-UNSET') (Show $u2)
Check 'I2 judged through the slot call, not as an escaped root' (-not (@($u2.reasons) -contains 'escaped-routine')) (Show $u2)
$u3 = Use-Of (Lane-Answer $Exe $db 'uFb2Ind.GCfg3')
Check 'I3 twin (slot copied away): MAY-BE-UNSET + escaped-routine' (($u3.verdict -eq 'MAY-BE-UNSET') -and (@($u3.reasons) -contains 'escaped-routine')) (Show $u3)
Check 'I3 the answer says why the edge was not enough' ($u3.why -match 'read as a value') "why=$($u3.why)"
$u5 = Use-Of (Lane-Answer $Exe $db 'uFb2Ind.GCfg5')
Check 'I5 twin (no edge for the binding): MAY-BE-UNSET + escaped-routine' (($u5.verdict -eq 'MAY-BE-UNSET') -and (@($u5.reasons) -contains 'escaped-routine')) (Show $u5)
Check 'I5 the answer says why (no indirect-call edge)' ($u5.why -match 'no indirect-call edge') "why=$($u5.why)"

# ---- F: must-write facts ------------------------------------------------------------------------
$budget = @('--max-routines', '2')
$f1 = Lane-Answer $Exe $db 'uFb2Fields.TFbBig.FList' $budget
$f1v = if ($f1) { [string]$f1.verdict } else { '(no answer)' }
Check 'F1 FList with --max-routines 2: SET' ($f1v -eq 'SET') "verdict=$f1v reasons=[$(if ($f1) { @($f1.reasons) -join ',' })]"
Check 'F1 one flow graph only: the constructor (Init is proven by its fact, no other method has a writer)' (($null -ne $f1) -and (-not $f1.budget.exhausted) -and ($f1.budget.routines -eq 1)) "routines=$(if ($f1) { $f1.budget.routines })"
$f2 = Lane-Answer $Exe $db 'uFb2Fields.TFbBig.FCount' $budget
$f2v = if ($f2) { [string]$f2.verdict } else { '(no answer)' }
$f2r = @(if ($f2) { @($f2.reasons) + @($f2.uses | ForEach-Object { $_.reasons }) } else { @() }) | Where-Object { $_ } | Select-Object -Unique
Check 'F2 twin FCount (conditional writer): MAY-BE-UNSET + ctor-misses-field' (($f2v -eq 'MAY-BE-UNSET') -and (@($f2r) -contains 'ctor-misses-field')) "verdict=$f2v reasons=[$($f2r -join ',')]"
Check 'F2 not a budget answer' (($null -ne $f2) -and (-not $f2.budget.exhausted) -and (-not (@($f2r) -contains 'budget'))) "routines=$(if ($f2) { $f2.budget.routines })"

# ---- A: numeric by-ref argument -----------------------------------------------------------------
function Arg-Shape([string]$Engine, [string]$Db) {
  $a = Lane-Answer $Engine $Db 'uFb2Arg.GTotal'
  $w = @(if ($a) { $a.writers } else { @() })
  $u = @(if ($a) { $a.uses } else { @() })
  return [pscustomobject]@{
    verdict = if ($a) { [string]$a.verdict } else { '(no answer)' }
    writers = (@($w | ForEach-Object { "$($_.line):$($_.how)" }) -join ',')
    uses    = (@($u | ForEach-Object { $_.line }) -join ',')
  }
}
$argSrc = Join-Path $ix.fx 'uFb2Arg.pas'
$fill = @(Select-String -Path $argSrc -Pattern '^\s*Fill\(GTotal\);' | ForEach-Object { $_.LineNumber })
$seen = (Select-String -Path $argSrc -Pattern '^\s*Seen := GTotal;' | Select-Object -First 1).LineNumber
$show = (Select-String -Path $argSrc -Pattern '^\s*Show\(GTotal\);' | Select-Object -First 1).LineNumber
$wantW = "$($fill[0]):var-arg,$($fill[1]):var-arg"
$wantU = "$seen,$show"
$as = Arg-Shape $Exe $db
Check 'A1 the writers of GTotal are the var arguments of the two Fill calls' (($fill.Count -eq 2) -and ($as.writers -eq $wantW)) "writers=$($as.writers) expected=$wantW"
Check 'A2 the uses are `Seen := GTotal` and `Show(GTotal)`' ($as.uses -eq $wantU) "uses=$($as.uses) expected=$wantU"
Check 'A3 GTotal is SET' ($as.verdict -eq 'SET') "verdict=$($as.verdict)"

# ---- D: 1.56 source kinds that are no read of the target ------------------------------------------
# Lanes EXT-B3 / EXT-B2 emit data_flows rows with src_kind 'dsfield' / 'except'. This branch's indexer
# does not, so the rows are written into a COPY of the index: the VALUE row of `Show(Seen)` again,
# with val_class '' and each of the two source kinds, named like the target.
$dsDb = Join-Path $WorkDir 'fb2-ds.sqlite'
Copy-Item $db $dsDb -Force
$py = Join-Path $WorkDir 'add_rows.py'
@'
import sqlite3, sys
c = sqlite3.connect(sys.argv[1])
cols = [r[1] for r in c.execute("PRAGMA table_info(data_flows)")]
row = c.execute("SELECT * FROM data_flows WHERE dst_kind = 'arg' AND src_name = 'GTotal' AND val_class <> '' LIMIT 1").fetchone()
n = 0
if row:
    for kind in ('dsfield', 'except'):
        d = dict(zip(cols, row))
        d['val_class'] = ''
        d['src_kind'] = kind
        d['src_index'] = d['src_index'] + 100 + n
        c.execute("INSERT INTO data_flows(%s) VALUES (%s)" % (', '.join(cols), ', '.join('?' * len(cols))), [d[k] for k in cols])
        n += 1
c.commit()
print(n)
'@ | Set-Content -Path $py -Encoding ascii
$added = & { $ErrorActionPreference = 'Continue'; & python $py $dsDb 2>$null }
Check 'D0 two rows (src_kind dsfield / except, source named GTotal, val_class empty) written into the copy' ("$added".Trim() -eq '2') "python printed '$added' (needs python with sqlite3)"
$ds = Arg-Shape $Exe $dsDb
Check 'D1 a dsfield / except source named like the target is no argument event: writers unchanged' ($ds.writers -eq $wantW) "writers=$($ds.writers) expected=$wantW"
Check 'D2 uses unchanged' ($ds.uses -eq $wantU) "uses=$($ds.uses) expected=$wantU"

# ---- RED of the lane, on request ----------------------------------------------------------------
if ($BaseExe -ne '') {
  Write-Host "-- base engine $BaseExe (the lane's RED) --" -ForegroundColor Cyan
  $bx = Lane-Index $BaseExe 'base'
  foreach ($t in @('uFb2Ind.GCfg1', 'uFb2Ind.GCfg4', 'uFb2Ind.GCfg6')) {
    $b = Use-Of (Lane-Answer $BaseExe $bx.db $t)
    Check "BASE $t is not SET without the lane" ($b.verdict -ne 'SET') (Show $b)
  }
  $bf = Lane-Answer $BaseExe $bx.db 'uFb2Fields.TFbBig.FList' $budget
  Check 'BASE FList with --max-routines 2 is a budget answer without the lane' (($null -ne $bf) -and ($bf.verdict -ne 'SET')) "verdict=$(if ($bf) { $bf.verdict }) exhausted=$(if ($bf) { $bf.budget.exhausted })"
  $bs = Arg-Shape $BaseExe $bx.db
  Check 'BASE GTotal events differ without the lane (a value row read as an argument row)' (($bs.writers -ne $wantW) -or ($bs.uses -ne $wantU)) "writers=$($bs.writers) uses=$($bs.uses)"
}

if (-not $KeepScratch) { try { [IO.Directory]::Delete($WorkDir, $true) } catch { } }
Write-Host ("== run_v156_FB2: {0} PASS, {1} FAIL ==" -f $script:pass, $script:fail) -ForegroundColor $(if ($script:fail) { 'Red' } else { 'Green' })
exit $(if ($script:fail) { 1 } else { 0 })
