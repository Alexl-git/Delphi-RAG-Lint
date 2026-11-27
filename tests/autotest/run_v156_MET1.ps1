#Requires -Version 7.3
<#
  run_v156_MET1.ps1 -- 1.56 lane MET-1: the `metrics` verb and the row API of DRagLint.Query.Metrics
  (gap-plan S3 + G-48; sections G-58 repeated parameter groups, G-59 one implementor / one descendant).

  Indexes tests\fixtures\v156-met1 (app\uMetCalc.pas, app\uMetShapes.pas, lib\uMetUtil.pas) into a
  scratch folder and checks:
    T1  every routine row carries the cyclomatic / body_loc of its symbol_facts row (read with `sql`)
    T2  unit rows are the sums of their routines (body_loc without nested routines)
    T3  class rows, T4 folder rows + total, T5 unit fan, T6 routine fan / nesting, T7 comment lines,
    T8  parameters
    T9  G-58 groups, T10 G-59 rows (each with the rows that must NOT be listed)
    T11 flags and refusals, T12 --in, T13 --save / --trend (one save: refused; two: deltas), T14 text,
    T15 two runs give the same bytes
  RED on an engine without the verb: T0 fails ("not built" / unknown verb) and the run stops there.
  POSITIVE CONTROLS: T1 demands a routine with cyclomatic > 1 (an all-zero table cannot pass), T9 and
  T10 demand the rows that exist beside the ones that must be absent, T13 demands a non-zero delta.

  Parameters: -Exe <engine> (default: src\cli\Win64\Debug\drag-lint.exe, else third_party\dll-win64),
              -KeepScratch.
  Exit 0 only when every check passed.
#>
[CmdletBinding()]
param([string]$Exe = '', [switch]$KeepScratch)

$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path "$PSScriptRoot\..\..").Path
if ($Exe -eq '') {
  $Exe = Join-Path $repo 'src\cli\Win64\Debug\drag-lint.exe'
  if (-not (Test-Path $Exe)) { $Exe = Join-Path $repo 'third_party\dll-win64\drag-lint.exe' }
}
if (-not (Test-Path $Exe)) { Write-Host "run_v156_MET1: no engine at $Exe" -ForegroundColor Red; exit 2 }
$fxSrc = Join-Path $repo 'tests\fixtures\v156-met1'
$work  = Join-Path $env:TEMP ('dl-v156-met1-' + [Guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Force $work | Out-Null

$script:fail = 0
$script:pass = 0
function Check([string]$Name, [bool]$Ok, [string]$Detail = '') {
  if ($Ok) { $script:pass++; Write-Host "  PASS  $Name  $Detail" -ForegroundColor Green }
  else     { $script:fail++; Write-Host "  FAIL  $Name  $Detail" -ForegroundColor Red }
}
function Finish {
  Write-Host ("SUMMARY run_v156_MET1 pass={0} fail={1}" -f $script:pass, $script:fail)
  if (-not $KeepScratch) { try { [IO.Directory]::Delete($work, $true) } catch { } } else { Write-Host "scratch: $work" }
  if ($script:fail -eq 0) { Write-Host 'V156 MET1: PASS' -ForegroundColor Green; exit 0 }
  Write-Host 'V156 MET1: FAIL' -ForegroundColor Red; exit 1
}
# Runs the engine; returns @{ rc; out (stdout text); err (stderr text) }.
function Lane-Run([string[]]$EngineArgs) {
  $o = Join-Path $work 'stdout.txt'; $e = Join-Path $work 'stderr.txt'
  & { $ErrorActionPreference = 'Continue'; & $Exe @EngineArgs 1> $o 2> $e }
  $rc = $LASTEXITCODE
  return @{ rc = $rc; out = [string](Get-Content -Raw $o); err = [string](Get-Content -Raw $e) }
}
# One SELECT -> array of PSCustomObject (sql --json rows are positional: map them onto the column names).
function Lane-Sql([string]$Db, [string]$Query) {
  $r = Lane-Run @('sql', '--query', $Query, '--db', $Db, '--json', '--limit', '100000')
  if ($r.rc -ne 0 -or -not $r.out) { return ,@() }
  $j = $r.out | ConvertFrom-Json
  $cols = @($j.columns | ForEach-Object { if ($_ -is [string]) { $_ } else { $_.name } })
  $out = New-Object System.Collections.Generic.List[object]
  foreach ($row in @($j.rows)) {
    $o = [ordered]@{}
    for ($i = 0; $i -lt $cols.Count; $i++) { $o[$cols[$i]] = $row[$i] }
    $out.Add([pscustomobject]$o)
  }
  return ,$out.ToArray()
}
function Row($Rows, [string]$Name) { return @($Rows | Where-Object { $_.name -eq $Name }) | Select-Object -First 1 }

Write-Host "run_v156_MET1: engine $Exe" -ForegroundColor Cyan
$fx = Join-Path $work 'fx'; Copy-Item -Recurse $fxSrc $fx
$db = Join-Path $work 'fx.sqlite'
& { $ErrorActionPreference = 'Continue'; & $Exe index $fx --db $db *> (Join-Path $work 'index.log') }
$facts = Lane-Sql $db "SELECT s.id, s.qualified_name AS qn, f.cyclomatic, f.body_loc, p.kind AS pkind, fl.path FROM symbol_facts f JOIN symbols s ON s.id = f.symbol_id JOIN files fl ON fl.id = s.file_id LEFT JOIN symbols p ON p.id = s.parent_id"
Check 'VACUITY the fixture was indexed and has routine facts' ($facts.Count -eq 16) "(symbol_facts rows $($facts.Count), want 16)"

# ---- T0 the verb answers ---------------------------------------------------------------
$r = Lane-Run @('metrics', '--db', $db, '--json')
$m = $null
if ($r.rc -eq 0 -and $r.out) { try { $m = $r.out | ConvertFrom-Json } catch { $m = $null } }
Check 'T0 metrics --json answers with schema metrics/1' (($null -ne $m) -and ($m.schema -eq 'metrics/1')) "(rc $($r.rc); stderr: $(($r.err + '').Trim()))"
if ($null -eq $m) { Finish }

# ---- T1 routine rows == symbol_facts ---------------------------------------------------
$bad = 0
foreach ($f in $facts) {
  $row = @($m.routines | Where-Object { $_.symbol_id -eq $f.id })
  if (($row.Count -ne 1) -or ($row[0].cyclomatic -ne $f.cyclomatic) -or ($row[0].body_loc -ne $f.body_loc) -or ($row[0].name -ne $f.qn)) { $bad++ }
}
Check 'T1 every symbol_facts routine has one row with its cyclomatic and body_loc' (($bad -eq 0) -and (@($m.routines).Count -eq $facts.Count)) "(mismatches $bad, rows $(@($m.routines).Count))"
$clamp = Row $m.routines 'uMetUtil.Clamp'
Check 'T1 POSITIVE CONTROL Clamp has cyclomatic > 1 and body_loc > 1' (($null -ne $clamp) -and ($clamp.cyclomatic -gt 1) -and ($clamp.body_loc -gt 1)) "(cyclomatic $($clamp.cyclomatic), body_loc $($clamp.body_loc))"
Check 'T1 a routine row covers itself' (($clamp.routines -eq 1) -and ($clamp.level -eq 'routine') -and ($clamp.cyclomatic_max -eq $clamp.cyclomatic) -and ($clamp.parent -eq 'uMetUtil') -and ($clamp.line -gt 1)) "(parent $($clamp.parent), line $($clamp.line))"

# ---- T2 unit rows ----------------------------------------------------------------------
$calcFacts = @($facts | Where-Object { $_.path -like '*uMetCalc.pas' })
$sumCyc  = ($calcFacts | Measure-Object -Property cyclomatic -Sum).Sum
$maxCyc  = ($calcFacts | Measure-Object -Property cyclomatic -Maximum).Maximum
$sumBody = ($calcFacts | Where-Object { $_.pkind -notin 'function', 'procedure', 'method' } | Measure-Object -Property body_loc -Sum).Sum
$calc = Row $m.units 'uMetCalc'
Check 'T2 three unit rows, by name' ((@($m.units).name -join ',') -eq 'uMetCalc,uMetShapes,uMetUtil') "($(@($m.units).name -join ','))"
Check 'T2 uMetCalc = sum of its 7 routines' (($calc.routines -eq 7) -and ($calc.cyclomatic -eq $sumCyc) -and ($calc.cyclomatic_max -eq $maxCyc)) "(routines $($calc.routines), cyclomatic $($calc.cyclomatic) want $sumCyc, max $($calc.cyclomatic_max) want $maxCyc)"
Check 'T2 unit body_loc leaves the nested routine out' (($calc.body_loc -eq $sumBody) -and ($sumBody -lt ($calcFacts | Measure-Object -Property body_loc -Sum).Sum)) "(body_loc $($calc.body_loc) want $sumBody)"
Check 'T2 unit lines = the file length' ($calc.lines -eq @(Get-Content (Join-Path $fx 'app\uMetCalc.pas')).Count) "(lines $($calc.lines))"

# ---- T3 class rows ---------------------------------------------------------------------
$cls = @($m.classes)
$shapes = Row $m.units 'uMetShapes'
Check 'T3 ten class rows, two of them interfaces' (($cls.Count -eq 10) -and ($shapes.classes -eq 10) -and ($shapes.interfaces -eq 2)) "(rows $($cls.Count), unit classes $($shapes.classes), interfaces $($shapes.interfaces))"
$circle = Row $cls 'uMetShapes.TCircle'
Check 'T3 TCircle covers its two routines and has two declared ancestors' (($circle.routines -eq 2) -and ($circle.fan_out -eq 2) -and ($circle.parent -eq 'uMetShapes') -and ($circle.kind -eq 'class')) "(routines $($circle.routines), fan_out $($circle.fan_out))"
Check 'T3 class fan_in = heirs in the index' (((Row $cls 'uMetShapes.IShape').fan_in -eq 2) -and ((Row $cls 'uMetShapes.TMulti').fan_in -eq 2) -and ((Row $cls 'uMetShapes.TBase').fan_in -eq 1) -and ((Row $cls 'uMetShapes.TLeaf').fan_in -eq 0)) "(IShape $((Row $cls 'uMetShapes.IShape').fan_in), TMulti $((Row $cls 'uMetShapes.TMulti').fan_in), TBase $((Row $cls 'uMetShapes.TBase').fan_in))"

# ---- T4 folder rows and the total ------------------------------------------------------
$fo = @($m.folders)
$app = $fo | Where-Object { $_.name -like '*\app' } | Select-Object -First 1
$lib = $fo | Where-Object { $_.name -like '*\lib' } | Select-Object -First 1
Check 'T4 two folder rows: app (2 units), lib (1 unit)' (($fo.Count -eq 2) -and ($app.units -eq 2) -and ($lib.units -eq 1) -and ($app.routines -eq 14) -and ($lib.routines -eq 2)) "(folders $($fo.Count), app units $($app.units) routines $($app.routines), lib units $($lib.units))"
Check 'T4 folder fan: lib is used by two outside units, app uses one outside unit' (($lib.fan_in -eq 2) -and ($lib.fan_out -eq 0) -and ($app.fan_out -eq 1) -and ($app.fan_in -eq 0)) "(lib in $($lib.fan_in) out $($lib.fan_out); app in $($app.fan_in) out $($app.fan_out))"
Check 'T4 total row: 3 units, 16 routines, fan not measured (null)' (($m.total.units -eq 3) -and ($m.total.routines -eq 16) -and ($m.total.classes -eq 10) -and ($null -eq $m.total.fan_in) -and ($m.total.level -eq 'total')) "(units $($m.total.units), routines $($m.total.routines))"

# ---- T5 unit fan -----------------------------------------------------------------------
$util = Row $m.units 'uMetUtil'
Check 'T5 unit fan from the uses clauses' (($util.fan_in -eq 2) -and ($util.fan_out -eq 0) -and ($shapes.fan_out -eq 2) -and ($shapes.fan_in -eq 0) -and ($calc.fan_in -eq 1) -and ($calc.fan_out -eq 1)) "(uMetUtil in $($util.fan_in) out $($util.fan_out); uMetShapes out $($shapes.fan_out); uMetCalc in $($calc.fan_in) out $($calc.fan_out))"

# ---- T6 routine fan and nesting --------------------------------------------------------
$step = Row $m.routines 'uMetCalc.SumEven.Step'
$sum  = Row $m.routines 'uMetCalc.SumEven'
$area = Row $m.routines 'uMetCalc.RectArea'
Check 'T6 the nested routine is marked and names its enclosing routine' (($step.nested -eq $true) -and ($step.parent -eq 'uMetCalc.SumEven') -and ($sum.nested -eq $false)) "(nested $($step.nested), parent $($step.parent))"
Check 'T6 routine fan = distinct callers / callees' (($clamp.fan_in -eq 2) -and ($area.fan_in -eq 2) -and ($sum.fan_out -eq 1) -and ($step.fan_out -eq 1) -and ($step.fan_in -eq 1)) "(Clamp in $($clamp.fan_in), RectArea in $($area.fan_in), SumEven out $($sum.fan_out), Step in $($step.fan_in) out $($step.fan_out))"
$method = Row $m.routines 'uMetShapes.TCircle.Area'
Check 'T6 a method names its class as parent' ($method.parent -eq 'uMetShapes.TCircle') "(parent $($method.parent))"

# ---- T7 comment lines ------------------------------------------------------------------
Check 'T7 comment lines inside a body, and in the whole unit' (($clamp.comment_lines -eq 1) -and ($sum.comment_lines -eq 1) -and ($method.comment_lines -eq 1) -and ($area.comment_lines -eq 0) -and ($util.comment_lines -eq 5)) "(Clamp $($clamp.comment_lines), SumEven $($sum.comment_lines), TCircle.Area $($method.comment_lines), uMetUtil $($util.comment_lines) want 5)"

# ---- T8 parameters ---------------------------------------------------------------------
Check 'T8 params: routine count, unit maximum' (($clamp.params -eq 3) -and ($area.params -eq 4) -and ($calc.params -eq 4) -and ($util.params -eq 3)) "(Clamp $($clamp.params), RectArea $($area.params), uMetCalc $($calc.params))"

# ---- T9 G-58 repeated parameter groups -------------------------------------------------
$pg = @($m.param_groups)
$g3 = $pg | Where-Object { @($_.params).Count -eq 3 } | Select-Object -First 1
$g4 = $pg | Where-Object { @($_.params).Count -eq 4 } | Select-Object -First 1
Check 'T9 POSITIVE CONTROL the group of three parameters in four routines is listed first' (($pg.Count -eq 2) -and (@($pg[0].params) -join '|') -eq 'pleft: integer|ptop: integer|pwidth: integer' -and (@($pg[0].routines).name -join ',') -eq 'uMetCalc.RectArea,uMetCalc.RectClampedArea,uMetCalc.RectIsWide,uMetCalc.RectRight') "(groups $($pg.Count); first: $(@($pg[0].params) -join '|') in $(@($pg[0].routines).Count))"
Check 'T9 the wider group of four parameters is one row with three routines' (($null -ne $g4) -and (@($g4.params) -contains 'pheight: integer') -and (@($g4.routines).Count -eq 3) -and (@($g4.routines).name -notcontains 'uMetCalc.RectRight')) "(routines $(@($g4.routines).Count))"
$inGroups = @($pg | ForEach-Object { $_.routines } | ForEach-Object { $_.name })
Check 'T9 PairOnly (two shared parameters) and Clamp (one routine) are in no group' (($inGroups -notcontains 'uMetCalc.PairOnly') -and ($inGroups -notcontains 'uMetUtil.Clamp') -and ($g3.routines[0].line -gt 0) -and ($g3.routines[0].file -like '*uMetCalc.pas')) ''

# ---- T10 G-59 one implementor / one descendant -----------------------------------------
$sh = @($m.single_heirs)
$only = $sh | Where-Object { $_.name -eq 'uMetShapes.IOnly' } | Select-Object -First 1
$base = $sh | Where-Object { $_.name -eq 'uMetShapes.TBase' } | Select-Object -First 1
Check 'T10 POSITIVE CONTROL IOnly <- TOnlyImpl and TBase <- TLeaf are listed' (($null -ne $only) -and ($only.kind -eq 'interface') -and ($only.heir -eq 'uMetShapes.TOnlyImpl') -and ($null -ne $base) -and ($base.kind -eq 'class') -and ($base.heir -eq 'uMetShapes.TLeaf') -and ($base.heir_line -gt $base.line)) "(rows $($sh.Count))"
Check 'T10 IShape (two implementors) and TMulti (two descendants) are not listed' (($sh.Count -eq 2) -and (@($sh.name) -notcontains 'uMetShapes.IShape') -and (@($sh.name) -notcontains 'uMetShapes.TMulti')) "($(@($sh.name) -join ','))"

# ---- T11 flags and refusals ------------------------------------------------------------
$r = Lane-Run @('metrics', '--db', $db, '--json', '--level', 'unit,folder')
$lv = $r.out | ConvertFrom-Json
$names = @($lv.PSObject.Properties.Name)
Check 'T11 --level unit,folder writes those arrays only (total and sections stay)' (($names -contains 'units') -and ($names -contains 'folders') -and ($names -notcontains 'routines') -and ($names -notcontains 'classes') -and ($names -contains 'total') -and ($names -contains 'param_groups')) "($($names -join ','))"
$r = Lane-Run @('metrics', '--db', $db, '--level', 'module')
Check 'T11 an unknown --level is refused (exit 2, nothing on stdout)' (($r.rc -eq 2) -and (($r.out + '').Trim() -eq '') -and ($r.err -match 'unknown --level "module"')) "(rc $($r.rc))"
$r = Lane-Run @('metrics', '--db', $db, '--bogus')
Check 'T11 an unknown flag is exit 3' ($r.rc -eq 3) "(rc $($r.rc))"
$r = Lane-Run @('metrics', '--json')
Check 'T11 no --db is exit 2' (($r.rc -eq 2) -and ($r.err -match '--db')) "(rc $($r.rc))"
$r = Lane-Run @('metrics', '--db', (Join-Path $work 'absent.sqlite'))
Check 'T11 a missing index is exit 2, named, nothing on stdout' (($r.rc -eq 2) -and ($r.err -match 'index not found') -and (($r.out + '').Trim() -eq '')) "(rc $($r.rc))"

# ---- T12 --in --------------------------------------------------------------------------
$r = Lane-Run @('metrics', '--db', $db, '--json', '--in', (Join-Path $fx 'app'))
$in = $r.out | ConvertFrom-Json
Check 'T12 --in <folder> keeps that folder (fan still counted over the index)' ((@($in.units).Count -eq 2) -and ($in.total.units -eq 2) -and (@($in.folders).Count -eq 1) -and (@($in.routines).Count -eq 14) -and ((Row $in.units 'uMetCalc').fan_out -eq 1)) "(units $(@($in.units).Count), routines $(@($in.routines).Count))"

# ---- T13 --save / --trend --------------------------------------------------------------
$hist = $db + '.metrics.jsonl'
$r = Lane-Run @('metrics', '--db', $db, '--trend')
Check 'T13 --trend with no snapshot is refused and says it needs two' (($r.rc -eq 2) -and ($r.err -match 'needs two saved snapshots') -and ($r.err -match 'holds 0') -and (($r.out + '').Trim() -eq '')) "(rc $($r.rc))"
$r = Lane-Run @('metrics', '--db', $db, '--save', '--in', (Join-Path $fx 'app'))
Check 'T13 --save with --in is refused, nothing is written' (($r.rc -eq 2) -and (-not (Test-Path $hist))) "(rc $($r.rc))"
$hashBefore = (Get-FileHash $db).Hash
$r = Lane-Run @('metrics', '--db', $db, '--save', '--json')
$hashAfter = (Get-FileHash $db).Hash
Check 'T13 --save appends one snapshot line beside the index and still prints the rows' (($r.rc -eq 0) -and (Test-Path $hist) -and (@(Get-Content $hist).Count -eq 1) -and (($r.out | ConvertFrom-Json).schema -eq 'metrics/1')) "(rc $($r.rc))"
Check 'T13 --save does not write the index' ($hashBefore -eq $hashAfter) ''
$r = Lane-Run @('metrics', '--db', $db, '--trend')
Check 'T13 --trend with ONE save says it needs two' (($r.rc -eq 2) -and ($r.err -match 'needs two saved snapshots') -and ($r.err -match 'holds 1')) "(rc $($r.rc); $(($r.err + '').Trim()))"
# a new routine in uMetUtil, re-index, second save
$utilPath = Join-Path $fx 'lib\uMetUtil.pas'
$src = [IO.File]::ReadAllText($utilPath)
$add = "function Twice(pValue: Integer): Integer;`r`nbegin`r`n  if pValue > 0 then`r`n    Result:= pValue * 2`r`n  else`r`n    Result:= 0;`r`nend;`r`n`r`nend."
$at = $src.LastIndexOf('end.')
[IO.File]::WriteAllText($utilPath, $src.Substring(0, $at) + $add + "`r`n", [Text.Encoding]::ASCII)
& { $ErrorActionPreference = 'Continue'; & $Exe index $fx --db $db *> (Join-Path $work 'index2.log') }
$r = Lane-Run @('metrics', '--db', $db, '--save', '--trend', '--json')
$t = $null; try { $t = $r.out | ConvertFrom-Json } catch { }
Check 'T13 second --save, then --trend answers (schema metrics-trend/1, 2 snapshots)' (($r.rc -eq 0) -and ($null -ne $t) -and ($t.schema -eq 'metrics-trend/1') -and ($t.snapshots -eq 2) -and (@(Get-Content $hist).Count -eq 2)) "(rc $($r.rc); $(($r.err + '').Trim()))"
if ($null -ne $t) {
  $tu = @($t.units)
  Check 'T13 POSITIVE CONTROL the total gained one routine and its cyclomatic value' (($t.total.routines.delta -eq 1) -and ($t.total.routines.from -eq 16) -and ($t.total.routines.to -eq 17) -and ($t.total.cyclomatic.delta -ge 2)) "(routines delta $($t.total.routines.delta), cyclomatic delta $($t.total.cyclomatic.delta))"
  Check 'T13 only the changed unit is listed; the other two are counted as unchanged' (($tu.Count -eq 1) -and ($tu[0].name -eq 'uMetUtil') -and ($tu[0].status -eq 'changed') -and ($tu[0].numbers.routines.delta -eq 1) -and ($t.units_unchanged -eq 2)) "(listed $($tu.Count), unchanged $($t.units_unchanged))"
} else { Check 'T13 POSITIVE CONTROL the total gained one routine and its cyclomatic value' $false '(no trend document)'; Check 'T13 only the changed unit is listed; the other two are counted as unchanged' $false '' }
$r = Lane-Run @('metrics', '--db', $db, '--trend')
Check 'T13 --trend as text names both numbers' (($r.rc -eq 0) -and ($r.out -match 'total routines 16 -> 17 \(\+1\)') -and ($r.out -match 'changed uMetUtil:') -and ($r.out -match 'unchanged units: 2')) "(rc $($r.rc))"
[IO.File]::AppendAllText($hist, "not a snapshot`r`n")
$r = Lane-Run @('metrics', '--db', $db, '--trend')
Check 'T13 a damaged history file is exit 1 and names the line' (($r.rc -eq 1) -and ($r.err -match 'line 3 of the history file')) "(rc $($r.rc))"

# ---- T14 text --------------------------------------------------------------------------
$r = Lane-Run @('metrics', '--db', $db, '--top', '2')
Check 'T14 text: total line, cut tables, both sections' (($r.rc -eq 0) -and ($r.out -match 'total: 3 unit\(s\), 10 class\(es\) of which 2 interface\(s\), 17 routine\(s\)') -and ($r.out -match 'routines: 17, the 2 with the highest cyclomatic value') -and ($r.out -match 'repeated parameter groups') -and ($r.out -match 'interface\s+uMetShapes\.IOnly') -and ($r.out -match 'one implementor / one descendant \(counted inside this index\): 2')) "(rc $($r.rc))"
$r0 = Lane-Run @('metrics', '--db', $db, '--top', '0', '--level', 'routine')
Check 'T14 --top 0 lists every routine' (($r0.rc -eq 0) -and ($r0.out -match 'routines: 17\r?\n') -and (@($r0.out -split "`n" | Where-Object { $_ -match 'uMet\w+\.pas:\d+\s*$' -and $_ -match '^\s+\d+\s+\d+\s+1\s' }).Count -eq 17)) "(rc $($r0.rc))"

# ---- T15 determinism -------------------------------------------------------------------
$a = (Lane-Run @('metrics', '--db', $db, '--json')).out
$b = (Lane-Run @('metrics', '--db', $db, '--json')).out
Check 'T15 two runs give the same bytes' (($a -eq $b) -and ($a.Length -gt 1000)) "(length $($a.Length))"

Finish
