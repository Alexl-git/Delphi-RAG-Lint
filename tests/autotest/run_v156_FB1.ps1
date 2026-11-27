<#
  run_v156_FB1.ps1 -- 1.56 lane FB-1: the value charts `ask value-origin` / `ask value-use` over
  data_flows, the numeric VALUE rows of 1.56 (B3, data_flows.val_class) included.

  Indexes tests\fixtures\v156\FB-1 into a scratch DB and asks, reading the bundle's meta.json
  ("emitter" object) and graph.dot:
    P0  POSITIVE CONTROL of the fixture: the index holds value rows (val_class <> '') AND pre-1.56
        rows (val_class = ''), so a count of one set cannot pass on the other.
    A   value-origin of a Currency field: two float sources (step 1), their two parameters (step 2);
        ValueRows / FlowRows / per-class counts; every row clickable; the two parameters are reported
        as not followed (--depth).
    B   --depth 4 follows the parameter to its caller's argument, to the function result that feeds
        it and to that function's parameter; all six are value rows (a pre-1.56 row with a classed twin
        is drawn once). B4 = the positive control of FlowRows: a string field's one class-less row.
    C   value-use of an Integer field: a field, a by-name callee that is NOT in the index (drawn, not
        followed), a string field reached as int; step 2 reaches a Boolean field, a unit variable and
        a function result, all three as CURRENCY values: val_class is the class the value had where it
        first became a scalar (FTotal: Currency), so value-use tags a row '[currency value]' -- the
        class of the value, not the type of the far end. C7: a string compared gives a bool value row.
    D   a field assigned only from a literal: zero rows, and the focus SAYS why (write sites, no row).
    E   value-use of a parameter: the callee's parameter, then the callee's result.
    F   REFUSAL: value-origin of a procedure exits 1 and says so; no bundle answer.
    G   --cap 2: the third row is counted as hidden and the chart says so.
    H   (-BaseExe <an engine before 1.56>) an index WITHOUT value rows is answered, ValueTracking
        false, and the focus says numeric values are NOT tracked. Skipped (reported) without -BaseExe
        or when that engine already writes value rows.
  Positive control of the runner: run it with -Exe <an engine without the two questions> -- A FAILS.

  Needs Graphviz dot.exe (-Dot). Run from a NEUTRAL CWD (C:\TEMP), pwsh 7.
#>
[CmdletBinding()]
param([string]$Exe = '', [string]$BaseExe = '',
      [string]$Dot = 'C:\Projects\GraphWiz\Graphviz-16.1.0-win64\bin\dot.exe', [switch]$KeepScratch)

$ErrorActionPreference = 'Stop'
if ($PSVersionTable.PSVersion.Major -lt 7) { Write-Host 'run_v156_FB1: needs pwsh 7' -ForegroundColor Red; exit 2 }
$repo = (Resolve-Path "$PSScriptRoot\..\..").Path
if ($Exe -eq '') {
  $Exe = Join-Path $repo 'src\cli\Win64\Debug\drag-lint.exe'
  if (-not (Test-Path $Exe)) { $Exe = Join-Path $repo 'third_party\dll-win64\drag-lint.exe' }
}
if (-not (Test-Path $Exe)) { Write-Host "run_v156_FB1: no engine at $Exe" -ForegroundColor Red; exit 2 }
if (-not (Test-Path $Dot)) { Write-Host "run_v156_FB1: no dot.exe at $Dot (pass -Dot)" -ForegroundColor Red; exit 2 }
$fxSrc = Join-Path $repo 'tests\fixtures\v156\FB-1'
$work  = Join-Path $env:TEMP ('dl-v156-fb1-' + [Guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Force $work | Out-Null

$script:fail = 0
$script:pass = 0
$script:skip = 0
function Check([string]$Name, [bool]$Ok, [string]$Detail = '') {
  if ($Ok) { $script:pass++; Write-Host "  PASS  $Name  $Detail" -ForegroundColor Green }
  else     { $script:fail++; Write-Host "  FAIL  $Name  $Detail" -ForegroundColor Red }
}

# Runs the engine with an argument list; returns exit code, stdout, stderr. No PowerShell fallback may answer.
function Lane-Run([string]$With, [string[]]$Arguments) {
  $psi = [Diagnostics.ProcessStartInfo]::new($With)
  foreach ($a in $Arguments) { $psi.ArgumentList.Add($a) }
  $psi.RedirectStandardOutput = $true; $psi.RedirectStandardError = $true; $psi.UseShellExecute = $false
  $psi.WorkingDirectory = $work
  $psi.Environment['DRAGLINT_ASK_REPORT'] = Join-Path $work 'no-such-Ask-Report.ps1'
  $psi.Environment['DRAGLINT_DOT'] = $Dot
  $p = [Diagnostics.Process]::Start($psi)
  $o = $p.StandardOutput.ReadToEndAsync(); $e = $p.StandardError.ReadToEndAsync(); $p.WaitForExit()
  return @{ Exit = $p.ExitCode; Out = $o.Result; Err = $e.Result }
}

# Copies the fixture into its own folder and indexes it; returns the folder (project Fb1.dproj, DB fb1.sqlite).
function Lane-Index([string]$Name, [string]$With) {
  $dir = Join-Path $work $Name
  New-Item -ItemType Directory -Force $dir | Out-Null
  Copy-Item (Join-Path $fxSrc '*') $dir -Recurse
  $r = Lane-Run $With @('index', '--project', (Join-Path $dir 'Fb1.dproj'), '--db', (Join-Path $dir 'fb1.sqlite'))
  if (-not (Test-Path (Join-Path $dir 'fb1.sqlite'))) { Write-Host "  index failed ($Name): exit=$($r.Exit) $($r.Err)" -ForegroundColor Red }
  return $dir
}

# One SELECT -> the first column of the first row ('' when the query fails).
function Lane-Scalar([string]$Dir, [string]$Query) {
  $r = Lane-Run $Exe @('sql', '--query', $Query, '--db', (Join-Path $Dir 'fb1.sqlite'), '--json')
  if ($r.Exit -ne 0) { return '' }
  try { $j = $r.Out | ConvertFrom-Json } catch { return '' }
  if (@($j.rows).Count -eq 0) { return '' }
  return "$(@($j.rows)[0][0])"
}

# Asks one question; returns exit, stdout, stderr, the emitter object of meta.json and the text of graph.dot.
$script:askNo = 0
function Lane-Ask([string]$Dir, [string]$Question, [string]$Target, [string[]]$More = @()) {
  $script:askNo++
  $out = Join-Path $work ("ask{0}" -f $script:askNo)
  $a = @('ask', $Question, '--target', $Target, '--project', (Join-Path $Dir 'Fb1.dproj'), '--db', (Join-Path $Dir 'fb1.sqlite'),
         '--plain', '--out-root', $out) + $More
  $r = Lane-Run $Exe $a
  $r.Emitter = $null; $r.DotText = ''
  $meta = @(Get-ChildItem $out -Recurse -Filter 'meta.json' -ErrorAction SilentlyContinue)
  if ($meta.Count -gt 0) {
    try { $r.Emitter = (Get-Content -Raw $meta[0].FullName | ConvertFrom-Json).emitter } catch { $r.Emitter = $null }
    $g = Join-Path $meta[0].DirectoryName 'graph.dot'
    if (Test-Path $g) { $r.DotText = Get-Content -Raw $g }
  }
  return $r
}
function F($R, [string]$Name) { if ($null -eq $R.Emitter) { return $null } return $R.Emitter.$Name }
function Edges([string]$DotText) { return @([regex]::Matches($DotText, '(?m)^\s+\S+ -> \S+ \[')).Count }

try {
  $fx = Lane-Index 'fx' $Exe
  $valueRows = Lane-Scalar $fx "SELECT COUNT(*) FROM data_flows WHERE val_class <> ''"
  $flowRows  = Lane-Scalar $fx "SELECT COUNT(*) FROM data_flows WHERE val_class = ''"
  Check 'P0 the fixture index holds value rows AND pre-1.56 rows' (($valueRows -match '^\d+$') -and ([int]$valueRows -gt 0) -and ([int]$flowRows -gt 0)) "value=$valueRows flow=$flowRows"

  Write-Host 'A  value-origin of a Currency field'
  $r = Lane-Ask $fx 'value-origin' 'uFb1.TOrder.FTotal'
  Check 'A1 answered, exit 0' (($r.Exit -eq 0) -and ($r.Out -match '(?m)^COMMAND value-origin ')) "exit=$($r.Exit) err=$($r.Err)"
  Check 'A2 step 1 = the two fields of the product' ((F $r 'Step1') -eq 2) "Step1=$(F $r 'Step1')"
  Check 'A3 four rows, all four VALUE rows, no pre-1.56 row' (((F $r 'Rows') -eq 4) -and ((F $r 'ValueRows') -eq 4) -and ((F $r 'FlowRows') -eq 0)) "Rows=$(F $r 'Rows') Value=$(F $r 'ValueRows') Flow=$(F $r 'FlowRows')"
  Check 'A4 classes follow the declarations: 2 float (FPrice, pPrice), 2 int (FQty, pQty)' (((F $r 'FloatRows') -eq 2) -and ((F $r 'IntRows') -eq 2)) "float=$(F $r 'FloatRows') int=$(F $r 'IntRows')"
  Check 'A5 the index tracks values; every row clickable' (((F $r 'ValueTracking') -eq $true) -and ((F $r 'AllClickable') -eq $true)) "tracking=$(F $r 'ValueTracking') clickable=$(F $r 'AllClickable')"
  Check 'A6 the two parameters are reported as not followed' ((F $r 'Unfollowed') -eq 2 -and $r.DotText -match 'stopped after 2 steps: 2 ends not followed') "Unfollowed=$(F $r 'Unfollowed')"
  Check 'A7 rows name the far end and its class' (($r.DotText -match 'TOrder\.FQty  \[int\]') -and ($r.DotText -match 'TOrder\.SetQty\(pQty\)  \[int\]')) ''
  Check 'A8 one edge per row, pointing at the selection' (((Edges $r.DotText) -eq 4) -and ($r.DotText -match '(?m)^\s+t1:p1 -> focus ')) "edges=$(Edges $r.DotText)"
  Check 'A9 no not-tracked note on a tracking index' ($r.DotText -notmatch 'NOT tracked') ''

  Write-Host 'B  --depth 4 crosses the call'
  $r = Lane-Ask $fx 'value-origin' 'uFb1.TOrder.FTotal' @('--depth', '4')
  Check 'B1 six rows' ((F $r 'Rows') -eq 6) "Rows=$(F $r 'Rows')"
  Check 'B2 the caller''s argument is the result of Twice, then its parameter' (($r.DotText -match 'result of Twice') -and ($r.DotText -match 'Twice\(pN\)  \[int\]')) ''
  Check 'B3 all six are ValueRows: the pre-1.56 row of Twice has a classed twin and is drawn once' (((F $r 'FlowRows') -eq 0) -and ((F $r 'ValueRows') -eq 6)) "Flow=$(F $r 'FlowRows') Value=$(F $r 'ValueRows')"
  $r = Lane-Ask $fx 'value-origin' 'uFb1.TOrder.FName'
  Check 'B4 POSITIVE CONTROL of FlowRows: a string field has one row, without a class' (((F $r 'Rows') -eq 1) -and ((F $r 'FlowRows') -eq 1) -and ((F $r 'ValueRows') -eq 0) -and ($r.DotText -notmatch 'pName\)  \[')) "Rows=$(F $r 'Rows') Flow=$(F $r 'FlowRows') Value=$(F $r 'ValueRows')"

  Write-Host 'C  value-use of an Integer field'
  $r = Lane-Ask $fx 'value-use' 'uFb1.TOrder.FQty'
  Check 'C1 answered, exit 0' (($r.Exit -eq 0) -and ($r.Out -match '(?m)^COMMAND value-use ')) "exit=$($r.Exit) err=$($r.Err)"
  Check 'C2 step 1 = FTotal, FLabel, the IntToStr argument' ((F $r 'Step1') -eq 3) "Step1=$(F $r 'Step1')"
  Check 'C3 six rows, all value rows (IntToStr argument and GLastTotal have classed twins)' (((F $r 'Rows') -eq 6) -and ((F $r 'ValueRows') -eq 6) -and ((F $r 'FlowRows') -eq 0)) "Rows=$(F $r 'Rows') Value=$(F $r 'ValueRows') Flow=$(F $r 'FlowRows')"
  Check 'C4 step 2: three CURRENCY values (FTotal is Currency) reach a Boolean field, a unit variable and a result; the tag says VALUE, never the Boolean field''s type' (((F $r 'BoolRows') -eq 0) -and ((F $r 'CurrencyRows') -eq 3) -and ($r.DotText -match 'TOrder\.FPaid  \[currency value\]') -and ($r.DotText -notmatch 'TOrder\.FPaid  \[(currency|bool)\]') -and ($r.DotText -match 'result of TOrder\.Total  \[currency value\]')) "bool=$(F $r 'BoolRows') currency=$(F $r 'CurrencyRows')"
  Check 'C5 a callee outside the index is drawn by name and not followed' ($r.DotText -match 'argument 1 of IntToStr \(not in this index\)' -and $r.DotText -match 'not followed') ''
  Check 'C6 edges point away from the selection' ($r.DotText -match '(?m)^\s+focus -> t1:p1 ') ''
  $r = Lane-Ask $fx 'value-use' 'uFb1.TOrder.FName'
  Check 'C7 a string compared: one BOOL value row beside the int result and two class-less rows' (((F $r 'Rows') -eq 4) -and ((F $r 'BoolRows') -eq 1) -and ((F $r 'IntRows') -eq 1) -and ((F $r 'FlowRows') -eq 2) -and ($r.DotText -match 'TOrder\.FPaid  \[bool value\]')) "Rows=$(F $r 'Rows') bool=$(F $r 'BoolRows') int=$(F $r 'IntRows') Flow=$(F $r 'FlowRows')"

  Write-Host 'D  a field assigned only from a literal'
  $r = Lane-Ask $fx 'value-origin' 'uFb1.TOrder.FRate'
  Check 'D1 answered with zero rows' (($r.Exit -eq 0) -and ((F $r 'Step1') -eq 0) -and ((F $r 'Rows') -eq 0)) "exit=$($r.Exit) Step1=$(F $r 'Step1')"
  Check 'D2 the focus says why: a write site and no row' ($r.DotText -match 'no source row: 1 write site in the index') ''

  Write-Host 'E  value-use of a parameter'
  $r = Lane-Ask $fx 'value-use' 'uFb1.Feed.pCount'
  Check 'E1 the callee''s parameter, then the callee''s result' (((F $r 'Step1') -eq 1) -and ((F $r 'Rows') -eq 2) -and ($r.DotText -match 'Twice\(pN\)  \[int value\]') -and ($r.DotText -match 'result of Twice  \[int value\]')) "Step1=$(F $r 'Step1') Rows=$(F $r 'Rows')"

  Write-Host 'F  refusal'
  $r = Lane-Ask $fx 'value-origin' 'uFb1.Feed'
  Check 'F1 a procedure has no value: exit 1, and the answer says so' (($r.Exit -eq 1) -and (($r.Out + $r.Err) -match 'is a procedure: it returns no value')) "exit=$($r.Exit)"
  Check 'F2 no chart was answered' ($null -eq $r.Emitter) ''

  Write-Host 'G  --cap'
  $r = Lane-Ask $fx 'value-use' 'uFb1.TOrder.FQty' @('--cap', '2')
  Check 'G1 step 1 still counts three, one is hidden and said' (((F $r 'Step1') -eq 3) -and ((F $r 'Hidden') -ge 1) -and ($r.DotText -match '\+1 more row not drawn')) "Step1=$(F $r 'Step1') Hidden=$(F $r 'Hidden')"

  Write-Host 'H  an index without value rows'
  if (($BaseExe -eq '') -or -not (Test-Path $BaseExe)) {
    $script:skip++; Write-Host '  SKIP  H needs -BaseExe <an engine before 1.56>' -ForegroundColor Yellow
  } else {
    $old = Lane-Index 'old' $BaseExe
    $oldValue = Lane-Scalar $old "SELECT COUNT(*) FROM data_flows WHERE val_class <> ''"
    if (($oldValue -match '^\d+$') -and ([int]$oldValue -gt 0)) {
      $script:skip++; Write-Host "  SKIP  H: -BaseExe already writes value rows ($oldValue)" -ForegroundColor Yellow
    } else {
      $r = Lane-Ask $old 'value-origin' 'uFb1.TOrder.FTotal'
      Check 'H1 answered, exit 0' ($r.Exit -eq 0) "exit=$($r.Exit) err=$($r.Err)"
      Check 'H2 ValueTracking false, no value row counted' (((F $r 'ValueTracking') -eq $false) -and ((F $r 'ValueRows') -eq 0)) "tracking=$(F $r 'ValueTracking') Value=$(F $r 'ValueRows')"
      Check 'H3 the focus says numeric values are NOT tracked' ($r.DotText -match 'values are NOT tracked in this index') ''
      Check 'H4 a zero-row answer there is not passed off as evidence' (((F $r 'Step1') -ne 0) -or ($r.DotText -match 'not evidence here')) "Step1=$(F $r 'Step1')"
    }
  }
} finally {
  if ((-not $KeepScratch) -and (Test-Path $work)) { [IO.Directory]::Delete($work, $true) }
}
Write-Host ("run_v156_FB1: {0} passed, {1} failed, {2} skipped" -f $script:pass, $script:fail, $script:skip)
if ($script:fail -gt 0) { Write-Host 'FAIL run_v156_FB1' -ForegroundColor Red; exit 1 }
Write-Host 'PASS run_v156_FB1' -ForegroundColor Green
