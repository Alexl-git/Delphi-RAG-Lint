<#
  Test-ExceptionPathsHelpers.ps1 -- measures the INDEX-WIDE numbers behind the
  exception-paths chart (PLAN-last-four-verbs Task 1) and RETURNS them. It
  asserts nothing: Test-Emitters.ps1 pins every number with its own codes
  (A-EP0-*), the Test-Task0Helpers.ps1 precedent.

  Two populations, measured the way the chart uses them:

    * the name-filtered CANDIDATE refs (Get-ExceptionIndexStats) -- what the
      focus box prints as "approximately N raise sites / M handlers";
    * the SOURCE-ONLY rows (Get-ExceptionSourceRows) inside every INDEXED impl
      span -- bare `except`, `raise;`, `raise <var>` -- which carry no ref and so
      can only ever be `[inferred]`.

  A line belongs to its INNERMOST span (a nested routine's statements are the
  nested routine's), so each statement is counted once. Lines outside every
  span are not scanned: P6's 11 raises inside a never-defined
  `{$IFDEF M2022_REFERENCE}` sit where the index has no routine at all.

  Nothing here writes to a database.
#>
[CmdletBinding()]
param(
  [string] $DbCli  = (Join-Path $PSScriptRoot '..\scratch\db\CLIENT-Micronite2027.sqlite'),
  [string] $Engine = 'C:\Projects\Delphi-RAG-lint-wt\archify-ir\third_party\dll-win64\drag-lint.exe'
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Emit-Common.ps1')

$DbPath = Get-CloneDb $DbCli
$res = [ordered]@{}

# ---- 1. the candidate refs (the focus box's index-wide line) ---------------------
$st = Get-ExceptionIndexStats
$res.Candidates     = $st.Candidates
$res.Raise          = $st.Raise
$res.Handle         = $st.Handle
$res.Dropped        = $st.Dropped
$res.Stale          = $st.Stale
$res.RaiseRoutines  = $st.RaiseRoutines
$res.HandleRoutines = $st.HandleRoutines

# ---- 2. the source-only rows inside every indexed impl span -----------------------
# ONE row per file (group_concat), not one per span: 11,007 spans would be 62
# paged engine calls; ~560 files is four.
$spans = Get-AllIndexRows @"
SELECT f.path AS path,
       group_concat(s.id || ':' || s.impl_start_line || ':' || s.impl_end_line, ',') AS spans,
       COUNT(*) AS n
  FROM symbols s JOIN files f ON f.id = s.file_id
 WHERE s.impl_start_line > 0 AND s.impl_end_line >= s.impl_start_line
 GROUP BY f.path
"@ 'f.path'

$count = @{}
foreach ($k in 'bare-except', 'on-except', 'reraise', 'raise-var', 'raise-create', 'raise-other') { $count[$k] = 0 }
$bareRoutines = @{}
$spanTotal = 0; $staleFiles = 0
$tryDecided = 0; $tryUndecided = New-Object System.Collections.ArrayList
foreach ($f in $spans) {
  $spanTotal += [int]$f.n
  $list = @(([string]$f.spans -split ',') | ForEach-Object {
    $a = $_ -split ':'
    [pscustomobject]@{ Id = [int]$a[0]; From = [int]$a[1]; To = [int]$a[2] }
  })
  $lo = ($list | Measure-Object -Property From -Minimum).Minimum
  $hi = ($list | Measure-Object -Property To -Maximum).Maximum
  # innermost owner per line: widest spans first, narrower ones overwrite
  $owner = New-Object 'int[]' ($hi + 2)
  foreach ($s in ($list | Sort-Object @{ E = { $_.To - $_.From }; Descending = $true })) {
    for ($ln = $s.From; $ln -le $s.To; $ln++) { $owner[$ln] = $s.Id }
  }
  $scan = Get-ExceptionSourceRows ([string]$f.path) $lo $hi
  if ($scan.Stale) { $staleFiles++; continue }
  # the try-block nesting scan (R10), on every span of every fresh file
  $stripped = Get-StrippedSourceLines ([string]$f.path)
  foreach ($s in $list) {
    $tb = Get-TryBlocks $stripped $s.From $s.To
    if ($tb.Decided) { $tryDecided++ } else { [void]$tryUndecided.Add("$([IO.Path]::GetFileName([string]$f.path)):$($s.From)") }
  }
  foreach ($r in $scan.Rows) {
    if ($owner[$r.Line] -eq 0) { continue }
    $count[$r.Kind]++
    if ($r.Kind -eq 'bare-except') { $bareRoutines[$owner[$r.Line]] = $true }
  }
}
$res.Spans          = $spanTotal
$res.SpanFiles      = $spans.Count
$res.SpanStaleFiles = $staleFiles
$res.BareExcept     = $count['bare-except']
$res.OnExcept       = $count['on-except']
$res.Reraise        = $count['reraise']
$res.RaiseVar       = $count['raise-var']
$res.RaiseCreate    = $count['raise-create']
$res.RaiseOther     = $count['raise-other']
$res.BareRoutines   = $bareRoutines.Count
$res.TryDecided     = $tryDecided
$res.TryUndecided   = (@($tryUndecided) | Sort-Object) -join ','

# ---- 3. focused checks: the classifier's multi-line fallback (fix round 1, finding 4)
# Synthetic Get-SourceContext results, so each case isolates ONE rule.
function Ctx($before, $prev, $after = ' do') {
  [pscustomobject]@{ Stale = $false; Token = 'EFoo'; Before = $before; After = $after; PrevLine = $prev }
}
$cls = [ordered]@{
  'on E: split'        = @((Ctx '        E: ' 'except on'), 'type_use', 'handle')   # `on` / `E: EFoo do`
  'on split, no var'   = @((Ctx '        ' 'except on'), 'type_use', 'handle')      # `on` / `EFoo do`
  'on E: whole prev'   = @((Ctx '   ' 'except on E:'), 'type_use', 'handle')       # `on E:` / `EFoo do`
  'same line'          = @((Ctx '  on E: ' 'except'), 'type_use', 'handle')
  'label is not on'    = @((Ctx '  X: ' 'Foo;'), 'type_use', 'other')              # `X:` after a statement
  'is-test'            = @((Ctx '  if E is ' 'begin'), 'type_use', 'other')
  'var decl'           = @((Ctx '  X: ' 'var'), 'type_use', 'other')
  'raise split'        = @((Ctx '    ' '  raise' '.Create(''x'')'), 'read', 'raise')
  'raise of a var'     = @((Ctx '  raise ' 'begin' ';'), 'read', 'other')
}
$bad = New-Object System.Collections.ArrayList
foreach ($k in $cls.Keys) {
  $got = Get-ExceptionRefClass $cls[$k][0] $cls[$k][1]
  if ($got -ne $cls[$k][2]) { [void]$bad.Add("[$k] expected $($cls[$k][2]) got $got") }
}
$res.ClassifierFailures = $bad.ToArray()

# ---- 4. focused checks: the try-block nesting scan (R10) ------------------------------
function Blk($tb) {
  (@($tb.Blocks | Sort-Object Try | ForEach-Object {
    "$([Math]::Floor($_.Try / 100000))/$(if ($_.Except) { [Math]::Floor($_.Except / 100000) } else { '-' })/$(if ($_.Finally) { [Math]::Floor($_.Finally / 100000) } else { '-' })/$([Math]::Floor($_.End / 100000)):$(@($_.On).Count)"
  })) -join ' '
}
$scans = [ordered]@{
  'nested try in try' = @(@('procedure X;', 'begin', '  try', '    try', '      A;', '    except', '      on E: EFoo do B;', '      on E: Exception do C;', '    end;', '  finally', '    D;', '  end;', 'end;'),
                          'True|3/-/10/12:0 4/6/-/9:2')
  'case and record'   = @(@('procedure X;', 'type TR = record case Integer of 0: (A: Integer); end;', 'begin', '  case Y of 1: Z; end;', '  try A; except B; end;', 'end;'),
                          'True|5/5/-/5:0')
  'asm body'          = @(@('procedure X;', 'asm', '  MOV EAX, 1 { try }', 'end;'), 'True|')
  'unbalanced end'    = @(@('procedure X;', 'begin', 'end;', 'end;'), 'False|')
  'finally w/o try'   = @(@('procedure X;', 'begin', '  finally', 'end;'), 'False|')
  'dotted end'        = @(@('procedure X;', 'begin', '  try R.End := 1; except end;', 'end;'), 'True|3/3/-/3:0')
}
$bad = New-Object System.Collections.ArrayList
foreach ($k in $scans.Keys) {
  $lines = [string[]]$scans[$k][0]
  $tb = Get-TryBlocks $lines 1 $lines.Count
  $got = "$($tb.Decided)|$(Blk $tb)"
  if ($got -ne $scans[$k][1]) { [void]$bad.Add("[$k] expected '$($scans[$k][1])' got '$got'") }
}
$res.TryScanFailures = $bad.ToArray()

# ---- 5. focused checks: does a handler re-raise? (R10) ------------------------------
# Synthetic first -- each case one rule -- then the REAL handlers the gate's
# A-EP6/A-EP7 rows depend on, read from the clone's own (fresh) source.
function PosOf([string[]] $L, [int] $Line, [string] $Tok) { $Line * 100000 + $L[$Line - 1].IndexOf($Tok) + 1 }
$syn = [string[]]@('procedure X;', 'begin', '  try', '    A;', '  except',
                   '    on E: EFoo do begin Log; raise; end;',
                   '    on F: EBar do raise F;',
                   '    on G: EBaz do raise EQux.Create(1);',
                   '    on H: EQuux do raise G;',
                   '  end;', '  try B; except Log; raise; end;', '  try C; except Log; end;', 'end;')
$stb = Get-TryBlocks $syn 1 $syn.Count
$cases = [ordered]@{
  'raise; in begin..end'   = @(6, 'EFoo', $false, $true)
  'raise of own variable'  = @(7, 'EBar', $false, $true)
  'raise of a NEW object'  = @(8, 'EBaz', $false, $false)
  'raise of ANOTHER var'   = @(9, 'EQuux', $false, $false)
  'bare except, raise;'    = @(11, 'except', $true, $true)
  'bare except, swallows'  = @(12, 'except', $true, $false)
}
$bad = New-Object System.Collections.ArrayList
foreach ($k in $cases.Keys) {
  $c = $cases[$k]
  $pos = PosOf $syn $c[0] $c[1]
  $blk = Find-HandlerBlock $stb $pos
  $got = $(if ($blk) { Test-HandlerReraises $syn $blk $pos $c[2] } else { 'no block' })
  if ("$got" -ne "$($c[3])") { [void]$bad.Add("[$k] expected $($c[3]) got $got") }
}
$real = [ordered]@{
  'LoadAll:532'               = @('uJobList.ViewModel.TJobListViewModel.LoadAll', 532, 'EDatabaseError', $true)
  'ApplyRawPayload:579'       = @('uJobList.ViewModel.TJobListViewModel.ApplyRawPayload', 579, 'EDatabaseError', $true)
  'LoadAllAsync:632'          = @('uJobList.ViewModel.TJobListViewModel.LoadAllAsync', 632, 'Exception', $false)
  'AutoTestSetupDefaults:466' = @('uAutoTest.AutoTestSetupDefaults', 466, 'Exception', $false)
}
foreach ($k in $real.Keys) {
  $c = $real[$k]
  $s = Invoke-IndexQuery "SELECT s.impl_start_line AS a, s.impl_end_line AS b, f.path AS path FROM symbols s JOIN files f ON f.id = s.file_id WHERE s.qualified_name = '$($c[0])'"
  $L = Get-StrippedSourceLines ([string]$s[0].path)
  if (-not (Test-SourceFresh ([string]$s[0].path))) { [void]$bad.Add("[$k] source is stale"); continue }
  $tb = Get-TryBlocks $L ([int]$s[0].a) ([int]$s[0].b)
  $pos = PosOf $L $c[1] $c[2]
  $blk = $(if ($tb.Decided) { Find-HandlerBlock $tb $pos } else { $null })
  $got = $(if ($blk) { Test-HandlerReraises $L $blk $pos $false } else { 'no block' })
  if ("$got" -ne "$($c[3])") { [void]$bad.Add("[$k] expected $($c[3]) got $got") }
}
$res.ReraiseFailures = $bad.ToArray()

# ---- 6. column base: refs.start_col vs the nesting scan (fix round 2) ---------------
# Both are 1-based: the scan's position is m.Index + 1 over the stripped line
# (Latin-1, one byte one column), refs.start_col is 1-based (P10). It matters
# only when a call and its try/except share a line -- LoadAllAsync:632 is exactly
# that: `procedure begin try if Ok then ApplyRawPayload(RspPayload); except ...`.
# Returns "<ref col>/<scan col of the name>/<try col>/<inside>".
$la = Invoke-IndexQuery @"
SELECT r.start_line AS l, r.start_col AS c, f.path AS path, s.impl_start_line AS a, s.impl_end_line AS b
  FROM refs r JOIN call_edges ce ON ce.ref_id = r.id JOIN symbols t ON t.id = ce.target_symbol_id
  JOIN symbols s ON s.id = r.enclosing_symbol_id JOIN files f ON f.id = r.file_id
 WHERE s.qualified_name = 'uJobList.ViewModel.TJobListViewModel.LoadAllAsync' AND t.name = 'ApplyRawPayload'
"@
$L = Get-StrippedSourceLines ([string]$la[0].path)
$tb = Get-TryBlocks $L ([int]$la[0].a) ([int]$la[0].b)
$site = [int]$la[0].l * 100000 + [int]$la[0].c
$blk = @($tb.Blocks | Where-Object { $_.Except -and $site -gt $_.Try -and $site -lt $_.Except })[0]
$res.ColumnBase = "$($la[0].c)/$($L[[int]$la[0].l - 1].IndexOf('ApplyRawPayload') + 1)/$(if ($blk) { $blk.Try % 100000 } else { 'none' })/$([bool]$blk)"
# ---- 7. focused checks: the per-EDGE walk (R13) on synthetic caller graphs --------
# Nodes are ints; an edge is caller <- callee with fake sites; $stopSet names the
# edges ("caller<-callee") whose caller catches. Each case pins the WHOLE result.
function SynWalk($Edges, $StopSet, [int] $Depth, $Unfetched = @(), $Capped = @{}, $Has = @{}) {
  $co = @{}; $fe = @{}
  foreach ($e in $Edges) {
    $c, $cal = $e -split '<-'
    if (-not $co.ContainsKey([int]$cal)) { $co[[int]$cal] = New-Object System.Collections.ArrayList }
    [void]$co[[int]$cal].Add([pscustomobject]@{ Caller = [int]$c; Sites = @(100001) })
    $fe[[int]$cal] = $true
  }
  foreach ($k in @($co.Keys)) { foreach ($x in $co[$k]) { $fe[[int]$x.Caller] = $true } }
  $fe[1] = $true
  foreach ($u in $Unfetched) { $fe.Remove([int]$u) }
  $ev = { param($c, $cal, $s, $ty) [pscustomobject]@{ Stopped = ($StopSet -contains "$c<-$cal"); Events = @(); NotGuarding = 0; No = 0 } }.GetNewClosure()
  $hc = { param([int[]] $ids) $h = @{}; foreach ($i in $ids) { if ($Has.ContainsKey($i)) { $h[$i] = $true } }; $h }.GetNewClosure()
  $w = Invoke-ExceptionWalk 1 $co $fe $Capped $Depth 'EX' $ev $hc
  "stops=$((@($w.Edges | Where-Object { $_.Result.Stopped } | ForEach-Object { "$($_.Caller)<-$($_.Callee)" }) | Sort-Object) -join ',')" +
  " pass=$($w.Passing -join ',') esc=$($w.Escapes -join ',') ends=$($w.Ends -join ',') cap=$($w.Capped -join ',') eval=$($w.Evaluated) nocaller=$($w.FocusNoCaller)"
}
$walks = [ordered]@{
  # 2 catches the call to 1 but ALSO calls 3, which lets EX through: 2 passes at
  # level 2 and its caller 5 is walked (the AutoTestSetupDefaults shape)
  'catch on one edge, escape on another' = @(
    (SynWalk @('2<-1', '3<-1', '2<-3', '5<-2') @('2<-1') 5),
    'stops=2<-1 pass=2,3,5 esc= ends=5 cap= eval=3 nocaller=False')
  # the round-2 behaviour would have stopped at 2 and never walked 5
  'catch everywhere stops the path' = @(
    (SynWalk @('2<-1', '5<-2') @('2<-1') 5),
    'stops=2<-1 pass= esc= ends= cap= eval=1 nocaller=False')
  # a cycle 2 -> 3 -> 2 above the focus must terminate, and nothing "ends"
  'cycle terminates' = @(
    (SynWalk @('2<-1', '3<-2', '2<-3') @() 50),
    'stops= pass=2,3 esc= ends= cap= eval=2 nocaller=False')
  # the depth bound: 3 is at the bound, unfetched, and HAS callers -> escapes
  'depth bound escapes' = @(
    (SynWalk @('2<-1', '3<-2') @() 2 @(3) @{} @{ 3 = $true }),
    'stops= pass=2,3 esc=3 ends= cap= eval=2 nocaller=False')
  # 2's only callers were capped: counted as capped, NEVER as "no caller"
  'capped is not no-caller' = @(
    (SynWalk @('2<-1') @() 5 @() @{ 2 = @(7, 8) }),
    'stops= pass=2 esc= ends= cap=7,8 eval=1 nocaller=False')
  'focus without callers' = @(
    (SynWalk @() @() 3),
    'stops= pass= esc= ends= cap= eval=0 nocaller=True')
}
$bad = New-Object System.Collections.ArrayList
foreach ($k in $walks.Keys) { if ($walks[$k][0] -ne $walks[$k][1]) { [void]$bad.Add("[$k] expected '$($walks[$k][1])' got '$($walks[$k][0])'") } }
$res.WalkFailures = $bad.ToArray()

[pscustomobject]$res
