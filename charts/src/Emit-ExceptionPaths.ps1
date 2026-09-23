<#
  Emit-ExceptionPaths.ps1 -- the `exception-paths` question: what does this
  routine raise, what does it handle itself, and where up the caller chain is
  each raise caught?

  THE INDEX HAS NO RAISE/HANDLE FACT -- BUT refs.kind ALREADY SPLITS THEM
  -----------------------------------------------------------------------
  `refs.kind` has no `raise` or `except` value (P1). What it does have, measured
  on the CLIENT clone 2026-09-23, is a different kind for each: `raise
  X.Create(...)` emits a `read` on X (the class is an expression) and `on E: X
  do` a `type_use` (a type annotation). 168 of 171 exception-class reads are
  raises and 185 of 242 type_uses are handlers -- but the same kinds also carry
  declarations, `is`/`as` tests and casts, so the KIND is only the pre-filter.
  The CLASSIFIER is the comment-stripped source token next to the ref
  (Get-ExceptionRefClass): `raise` before and `.Create...` after, or `on [E:]`
  before. Everything else is dropped from the picture and COUNTED.

  THE ROWS ARE REF-ANCHORED; ONLY THREE ARE NOT
  ----------------------------------------------
  Iterate refs, read source around each one (R2). A scan that looks for `raise`
  in source and then for a ref is right when the ref exists and silently wrong
  when it does not -- P6: of 19 source raises "missing" a ref, 7 sit in `{ }`
  comments and 11 in a never-defined `{$IFDEF}`. Only the statements that carry
  NO identifier are found by scanning source, inside the routine's INDEXED impl
  span, and are drawn `[inferred]`, dashed: bare `except`, `raise;` and `raise
  <var>`. Directive state is not evaluated for them, and every one says so.

  A FOCUS IS NOT FILTERED BY NAME
  --------------------------------
  The focus body classifies EVERY read and type_use it encloses, so `raise
  EdxException.Create` (a type outside the E-name filter) is found and a local
  called `ERollback` (P5) cannot be: a variable is never preceded by `raise` and
  followed by `.Create`. The cheap name filter is used only for the index-wide
  counts on the focus box and for the "declarations or tests" disclosure.

  HANDLED-WHERE, AND THE WORDS IT MAY NOT USE
  --------------------------------------------
  Callers are walked over call_edges to -Depth levels (who-calls' precedent). A
  raise of type T is CAUGHT at the first depth with a caller whose handler is T,
  `Exception`, a bare `except`, or a class the type_ancestors walk from T reaches
  -- a solid edge. A typed handler whose relation to T cannot be established in
  this index is a DASHED edge, "may catch -- ancestry not in this index" (R4): no
  RTL hierarchy is hard-coded, because it would be wrong for FireDAC and
  DevExpress and nobody would notice.

  The chart NEVER says "unhandled" (R3). 4 of the 5 measured focus candidates
  have ZERO resolved callers -- event handlers and interface dispatch are not in
  call_edges -- so the honest sentences are "no resolved caller in this index"
  and "no handler found within N caller levels (M callers walked)". A reader
  who takes "the walk ended" for "escapes to the user" is the riskiest failure
  this chart has, and the wording is the guard.

  A caller's handler is matched ANYWHERE in its body: whether the call sits
  inside that handler's `try` block is not checked, and the chart says so.

  FRESHNESS (R11)
  ---------------
  Every file read by column is checked against files.sha256 first. A stale
  focus is not classified at all: its exception-named refs render as
  `[stale source]` rows. -SourceOverride maps an indexed path to a copy to read
  instead, so a test can MANUFACTURE a stale file (N21) without writing to any
  database.
#>
[CmdletBinding()]
param(
  [Parameter(Mandatory)][Alias('Target')][string] $Qname,
  [Parameter(Mandatory)][string] $DbPath,
  [string]    $OutDir,
  [int]       $Depth      = 3,
  [int]       $Cap        = 12,       # rows shown per cluster; the rest disclosed
  [int]       $MaxCallers = 150,      # caller walk cap; reported when hit
  [hashtable] $SourceOverride,
  [string] $Engine     = 'C:\Projects\Delphi-RAG-lint-wt\archify-ir\third_party\dll-win64\drag-lint.exe',
  [string] $Dot        = 'C:\Projects\GraphWiz\Graphviz-16.1.0-win64\bin\dot.exe',
  [string] $FontMono   = 'Consolas',
  [string] $FontSans   = 'Segoe UI'
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Emit-Common.ps1')

$DbPath = Get-CloneDb $DbPath

$PAL = @{
  raiseBorder  = '#B02A37'; raiseFill  = '#FDECEE'; raiseHdr  = '#B02A37'
  handleBorder = '#2F9E44'; handleFill = '#EBFBEE'; handleHdr = '#2F9E44'
  callerBorder = '#3B5BDB'; callerFill = '#EDF2FF'; callerHdr = '#3B5BDB'
  focusBorder  = '#0F766E'; focusFill  = '#E2F1EF'; focusHdr  = '#0F766E'
  staleBorder  = '#6B7280'; staleFill  = '#F3F4F6'; staleHdr  = '#6B7280'
  rowInk       = '#1F2933'; lineInk    = '#8A94A6'
}
$INFERRED_NOTE = 'source scan; compiler directives not evaluated'

Write-Host "exception-paths: $Qname (depth $Depth)"

$sel = Resolve-MemberSelection $Qname @('method', 'procedure', 'function', 'constructor', 'destructor') `
         -Hint 'exception-paths selects a routine'

# ---- 1. index-wide pre-check (the touches-tables precedent) --------------------------
$idx = Get-ExceptionIndexStats $SourceOverride
Write-Host ("  index-wide (name-filtered): {0} candidate refs -> {1} raise / {2} handle / {3} other; {4} of {5} files fresh" -f `
            $idx.Candidates, $idx.Raise, $idx.Handle, $idx.Dropped, $idx.FreshFiles, $idx.Files)
if ($idx.Candidates -eq 0) {
  throw ('exception-paths: this index holds NO reference to an exception type at all ' +
         '(no ref named E<Name> or Exception), so there is nothing to classify -- ask the index ' +
         'that holds the code.')
}

# ---- helpers: symbol rows, nested spans, one body classified ----------------------------
function Get-RoutineInfo([int[]] $Ids) {
  $out = @{}
  for ($i = 0; $i -lt $Ids.Count; $i += 60) {
    $chunk = @($Ids[$i..([Math]::Min($i + 59, $Ids.Count - 1))])
    $rows = Invoke-IndexQuery @"
SELECT s.id AS id, s.qualified_name AS q, s.name AS name, s.file_id AS fid,
       s.impl_start_line AS a, s.impl_end_line AS b, s.start_line AS dline, f.path AS path
  FROM symbols s JOIN files f ON f.id = s.file_id
 WHERE s.id IN ($($chunk -join ','))
"@
    foreach ($r in $rows) {
      $out[[int]$r.id] = [pscustomobject]@{
        Id = [int]$r.id; Q = [string]$r.q; Name = [string]$r.name; FileId = [int]$r.fid
        Path = [string]$r.path; Unit = Get-UnitName ([string]$r.path)
        From = $(if ($r.a) { [int]$r.a } else { 0 }); To = $(if ($r.b) { [int]$r.b } else { 0 })
        Line = $(if ($r.a) { [int]$r.a } else { [int]$r.dline })
      }
    }
  }
  $out
}

# Nested routines' bodies belong to THEM: their refs carry their own
# enclosing_symbol_id, so the source scan must leave their lines out too.
function Get-NestedSkip($Rt) {
  if ($Rt.From -le 0) { return , @() }
  $rows = Invoke-IndexQuery @"
SELECT impl_start_line AS a, impl_end_line AS b FROM symbols
 WHERE file_id = $($Rt.FileId) AND id <> $($Rt.Id) AND impl_start_line > 0
   AND impl_start_line >= $($Rt.From) AND impl_end_line <= $($Rt.To)
"@
  , @($rows | ForEach-Object { , @([int]$_.a, [int]$_.b) })
}

# One routine body. -HandlersOnly (callers) reads type_use refs only: a caller's
# raises are not this chart's question.
function Get-BodyExceptions($Rt, [switch] $HandlersOnly) {
  $kinds = $(if ($HandlersOnly) { "'type_use'" } else { "'read','type_use'" })
  $refs = Get-AllIndexRows @"
SELECT r.id AS id, r.kind AS kind, r.name_text AS name, r.start_line AS line,
       r.start_col AS col, r.end_col AS ecol
  FROM refs r
 WHERE r.enclosing_symbol_id = $($Rt.Id) AND r.kind IN ($kinds)
"@ 'r.id'
  $fresh = Test-SourceFresh $Rt.Path $SourceOverride
  $raises = New-Object System.Collections.ArrayList
  $handles = New-Object System.Collections.ArrayList
  $stale = New-Object System.Collections.ArrayList
  $dropped = 0
  foreach ($r in $refs) {
    $isExc = Test-ExceptionTypeName ([string]$r.name)
    if (-not $fresh) {
      # never classified: the exception-named refs are listed as [stale source]
      if ($isExc) { [void]$stale.Add([pscustomobject]@{ Type = [string]$r.name; Line = [int]$r.line; Kind = [string]$r.kind }) }
      continue
    }
    $c = Get-SourceContext $Rt.Path ([int]$r.line) ([int]$r.col) ([int]$r.ecol - [int]$r.col) $SourceOverride
    $cls = Get-ExceptionRefClass $c ([string]$r.kind)
    $row = [pscustomobject]@{ Type = [string]$r.name; Line = [int]$r.line; Col = [int]$r.col }
    if ($cls -eq 'raise') { [void]$raises.Add($row) }
    elseif ($cls -eq 'handle') { [void]$handles.Add($row) }
    elseif ($isExc) { $dropped++ }
  }
  # casts and qualified `is`-tests arrive as call / member-access refs: counted, never drawn
  $otherKinds = 0
  if (-not $HandlersOnly) {
    $ok = Get-AllIndexRows @"
SELECT r.id AS id, r.name_text AS name FROM refs r
 WHERE r.enclosing_symbol_id = $($Rt.Id) AND r.kind NOT IN ('read','type_use')
   AND $(Get-ExceptionNameSql 'r.name_text')
"@ 'r.id'
    foreach ($o in $ok) {
      if (Test-ExceptionTypeName ([string]$o.name)) {
        if ($fresh) { $dropped++; $otherKinds++ }
      }
    }
  }
  $inferred = @()
  $scanStale = $false
  if ($Rt.From -gt 0) {
    $scan = Get-ExceptionSourceRows $Rt.Path $Rt.From $Rt.To $SourceOverride (Get-NestedSkip $Rt)
    $scanStale = $scan.Stale
    $want = $(if ($HandlersOnly) { @('bare-except') } else { @('bare-except', 'reraise', 'raise-var', 'raise-other') })
    $inferred = @($scan.Rows | Where-Object { $want -contains $_.Kind })
  }
  [pscustomobject]@{
    Fresh = $fresh; ScanStale = $scanStale; RefCount = $refs.Count
    Raises = $raises.ToArray(); Handles = $handles.ToArray()
    Inferred = $inferred; StaleRows = $stale.ToArray()
    Dropped = $dropped; OtherKinds = $otherKinds
  }
}

# ---- ancestry, walked inside the index only (R4) --------------------------------------
$ancCache = @{}
function Get-TypeChain([string] $T) {
  if ($ancCache.ContainsKey($T)) { return $ancCache[$T] }
  $q = ConvertTo-SqlText $T
  $decl = Invoke-IndexQuery "SELECT DISTINCT id AS id, qualified_name AS q FROM symbols WHERE kind = 'class' AND name = '$q'"
  $names = New-Object System.Collections.ArrayList
  [void]$names.Add($T)
  $state = 'external'
  if ($decl.Count -gt 1 -and @($decl | ForEach-Object { $_.q } | Sort-Object -Unique).Count -gt 1) {
    $state = 'ambiguous'
  } elseif ($decl.Count -ge 1) {
    $state = 'walked'
    $cur = [int]$decl[0].id
    for ($i = 0; $i -lt 32 -and $cur; $i++) {
      $a = Invoke-IndexQuery "SELECT ancestor_name AS n, ancestor_symbol_id AS s FROM type_ancestors WHERE symbol_id = $cur AND ordinal = 0"
      if ($a.Count -eq 0) { break }
      [void]$names.Add((([string]$a[0].n) -split '\.')[-1])
      $cur = $(if ($a[0].s) { [int]$a[0].s } else { 0 })
    }
  }
  $o = [pscustomobject]@{ Type = $T; State = $state; Names = $names.ToArray() }
  $ancCache[$T] = $o
  $o
}
$inIndexCache = @{}
function Test-ClassInIndex([string] $H) {
  if (-not $inIndexCache.ContainsKey($H)) {
    $q = ConvertTo-SqlText $H
    $n = Invoke-IndexQuery "SELECT COUNT(*) AS n FROM symbols WHERE kind = 'class' AND name = '$q'"
    $inIndexCache[$H] = ([int]$n[0].n -gt 0)
  }
  $inIndexCache[$H]
}

# 'exact' / 'catch-all' / 'ancestor' / 'bare' are SOLID; 'may' is dashed; 'no' is
# a project class that the in-index chain of T does not reach. $T of
# '(re-raise)' is the object of a `raise;` / `raise E` -- its type is not a fact,
# so only a catch-all or a bare except catches it for certain.
function Get-CatchVerdict([string] $T, [string] $H, [bool] $Bare) {
  if ($Bare) { return 'bare' }
  if ($H -ieq 'Exception') { return 'catch-all' }
  if ($T -eq '(re-raise)') { return 'may' }
  if ($H -ieq $T) { return 'exact' }
  $ch = Get-TypeChain $T
  if (@($ch.Names | Select-Object -Skip 1 | Where-Object { $_ -ieq $H }).Count) { return 'ancestor' }
  # A class DECLARED in this index cannot be an ancestor of one outside it, so
  # when T's chain was walked and misses H, and H is ours, H does not catch T.
  if ($ch.State -eq 'walked' -and (Test-ClassInIndex $H)) { return 'no' }
  'may'
}

# ---- 2. the focus body -----------------------------------------------------------------
$info = Get-RoutineInfo @($sel.Id)
$focus = $info[$sel.Id]
$body = Get-BodyExceptions $focus
$raiseTypes = @($body.Raises | ForEach-Object { $_.Type } | Sort-Object -Unique)
$infRaise = @($body.Inferred | Where-Object { $_.Kind -ne 'bare-except' })
$infBare  = @($body.Inferred | Where-Object { $_.Kind -eq 'bare-except' })
Write-Host ("  body: {0} raise ({1} types), {2} handle, {3} dropped, {4} inferred raise, {5} bare except, fresh={6}" -f `
            $body.Raises.Count, $raiseTypes.Count, $body.Handles.Count, $body.Dropped, $infRaise.Count, $infBare.Count, $body.Fresh)

# ---- 3. callers, walked UP over call_edges -----------------------------------------------
$dist = @{ $sel.Id = 0 }
$parentOf = @{}
$siteOf = @{}
$frontier = @($sel.Id)
$callerCapped = $false
$levels = 0
for ($d = 1; $d -le $Depth; $d++) {
  if ($frontier.Count -eq 0) { break }
  $next = New-Object System.Collections.ArrayList
  for ($i = 0; $i -lt $frontier.Count; $i += 60) {
    $chunk = @($frontier[$i..([Math]::Min($i + 59, $frontier.Count - 1))])
    $pairs = Get-AllIndexRows @"
SELECT r.enclosing_symbol_id AS caller, ce.target_symbol_id AS callee, MIN(r.start_line) AS site
  FROM call_edges ce JOIN refs r ON r.id = ce.ref_id
 WHERE ce.target_symbol_id IN ($($chunk -join ',')) AND r.enclosing_symbol_id IS NOT NULL
 GROUP BY r.enclosing_symbol_id, ce.target_symbol_id
"@ 'caller, callee'
    foreach ($p in $pairs) {
      $cid = [int]$p.caller
      if ($dist.ContainsKey($cid)) { continue }
      if (($dist.Count - 1) -ge $MaxCallers) { $callerCapped = $true; break }
      $dist[$cid] = $d; $parentOf[$cid] = [int]$p.callee; $siteOf[$cid] = [int]$p.site
      [void]$next.Add($cid)
    }
  }
  if ($next.Count) { $levels = $d }
  $frontier = @($next.ToArray())
  if ($callerCapped) { break }
}
$callerIds = @($dist.Keys | Where-Object { $dist[$_] -gt 0 } | ForEach-Object { [int]$_ })
$cinfo = $(if ($callerIds.Count) { Get-RoutineInfo $callerIds } else { @{} })
$callers = @($callerIds | ForEach-Object {
  $ci = $cinfo[$_]
  $cb = Get-BodyExceptions $ci -HandlersOnly
  [pscustomobject]@{ Info = $ci; D = $dist[$_]; Parent = $parentOf[$_]; Site = $siteOf[$_]; Body = $cb }
} | Sort-Object D, @{ E = { $_.Info.Q } })
Write-Host ("  callers walked: {0} over {1} level(s){2}" -f $callers.Count, $levels, $(if ($callerCapped) { " [CAPPED at $MaxCallers]" } else { '' }))

# ---- 4. handled-where, per raised type ---------------------------------------------------
$types = New-Object System.Collections.ArrayList
foreach ($t in $raiseTypes) { [void]$types.Add($t) }
if ($infRaise.Count) { [void]$types.Add('(re-raise)') }

$verdicts = New-Object System.Collections.ArrayList   # one per type
foreach ($t in $types) {
  $caught = $null; $alsoAtDepth = 0
  $may = New-Object System.Collections.ArrayList
  for ($d = 1; $d -le $levels -and -not $caught; $d++) {
    foreach ($c in @($callers | Where-Object { $_.D -eq $d })) {
      if (-not $c.Body.Fresh) { continue }
      $cands = @(@($c.Body.Handles | ForEach-Object { [pscustomobject]@{ H = $_.Type; Line = $_.Line; Bare = $false } }) +
                 @($c.Body.Inferred | ForEach-Object { [pscustomobject]@{ H = 'except'; Line = $_.Line; Bare = $true } }) |
                 Sort-Object Line)
      $hit = $null
      foreach ($h in $cands) {
        $v = Get-CatchVerdict $t $h.H $h.Bare
        if ($v -eq 'may') { [void]$may.Add([pscustomobject]@{ Caller = $c; Handler = $h }) }
        elseif ($v -ne 'no' -and -not $hit) { $hit = [pscustomobject]@{ Caller = $c; Handler = $h; How = $v } }
      }
      if ($hit) { if ($caught) { $alsoAtDepth++ } else { $caught = $hit } }
    }
  }
  [void]$verdicts.Add([pscustomobject]@{ Type = $t; Caught = $caught; Also = $alsoAtDepth; May = $may.ToArray() })
}
$caughtCount = @($verdicts | Where-Object { $_.Caught }).Count
$mayCount = ($verdicts | ForEach-Object { $_.May.Count } | Measure-Object -Sum).Sum
if (-not $mayCount) { $mayCount = 0 }

$walkSentence = $(if ($callers.Count -eq 0) { 'no resolved caller in this index' }
                  else { "no handler found within $Depth caller level$(if ($Depth -ne 1) { 's' }) ($($callers.Count) caller$(if ($callers.Count -ne 1) { 's' }) walked)" })

# files touched: the focus file and every caller file
$touched = @{}
$touched[$focus.Path] = $body.Fresh
foreach ($c in $callers) { $touched[$c.Info.Path] = $c.Body.Fresh }
$freshFiles = @($touched.Values | Where-Object { $_ }).Count
$staleFiles = $touched.Count - $freshFiles

# ---- 5. dot ------------------------------------------------------------------------------
$sb = New-Object System.Text.StringBuilder
[void]$sb.AppendLine('digraph exceptionpaths {')
[void]$sb.AppendLine('  rankdir=LR; bgcolor="transparent"; compound=true;')
[void]$sb.AppendLine('  nodesep=0.35; ranksep=1.3; splines=spline;')
[void]$sb.AppendLine("  graph [fontname=`"$FontSans`"];")
[void]$sb.AppendLine("  node  [shape=plaintext, fontname=`"$FontMono`", fontsize=14];")
[void]$sb.AppendLine("  edge  [fontname=`"$FontMono`", fontsize=11, color=`"$($PAL.lineInk)`", penwidth=1.4, arrowsize=0.7];")
[void]$sb.AppendLine('')

$nodeId = 0; $clusters = 0; $anchored = 0
$fileName = [IO.Path]::GetFileName($focus.Path)

# -- focus box
$nodeId++; $clusters++
$fnid = "n$nodeId"
$ftbl = New-Object System.Text.StringBuilder
[void]$ftbl.Append('<TABLE BORDER="0" CELLBORDER="0" CELLSPACING="3" CELLPADDING="5">')
[void]$ftbl.Append("<TR><TD ALIGN=`"LEFT`" BGCOLOR=`"$($PAL.focusHdr)`"><FONT COLOR=`"#FFFFFF`" FACE=`"$FontSans`" POINT-SIZE=`"14`"><B> $(ConvertTo-XmlText (Get-ShortName $sel.Qname $focus.Unit)) </B></FONT></TD></TR>")
$anchored++
[void]$ftbl.Append("<TR><TD PORT=`"p1`" ALIGN=`"LEFT`" HREF=`"$(New-RowHref $focus.Path $sel.FocusLine)`" TITLE=`"$(ConvertTo-XmlText $sel.Qname)`">")
[void]$ftbl.Append("<FONT COLOR=`"$($PAL.rowInk)`">$(ConvertTo-XmlText $focus.Unit)</FONT>")
[void]$ftbl.Append("  <FONT COLOR=`"$($PAL.lineInk)`" POINT-SIZE=`"12`">:$($sel.FocusLine)</FONT></TD></TR>")
Add-DisclosureRow $ftbl ("$($body.Raises.Count) raise site(s) ($($raiseTypes.Count) type(s)) -- $($body.Handles.Count) handler clause(s) in body -- " +
                         "$($infBare.Count) bare except block(s) [inferred] -- callers walked: $($callers.Count) over $levels level(s)") $PAL.lineInk
if ($infRaise.Count) { Add-DisclosureRow $ftbl "$($infRaise.Count) re-raise statement(s) [inferred] -- raise; / raise <var> carry no type reference" $PAL.lineInk }
if ($body.Dropped) { Add-DisclosureRow $ftbl "$($body.Dropped) other reference(s) to exception types in this body are declarations or tests (not drawn)" $PAL.lineInk }
Add-DisclosureRow $ftbl "type_use refs read from source at file:line:col; files checked fresh: $freshFiles of $($touched.Count)" $PAL.lineInk
if (-not $body.Fresh) {
  Add-DisclosureRow $ftbl "[stale source] $fileName differs from the indexed copy -- $($body.RefCount) reference(s) in this body were NOT classified" $PAL.lineInk
}
if ($types.Count -and $caughtCount -lt $types.Count) {
  Add-DisclosureRow $ftbl "handled-where: $walkSentence" $PAL.lineInk
} elseif (-not $types.Count) {
  Add-DisclosureRow $ftbl "callers: $(if ($callers.Count) { "$($callers.Count) walked over $levels level(s)" } else { 'no resolved caller in this index' })" $PAL.lineInk
}
if ($callerCapped) { Add-DisclosureRow $ftbl "caller walk CAPPED at $MaxCallers -- more callers exist" $PAL.lineInk }
Add-DisclosureRow $ftbl ("approximately $($idx.Raise) raise sites / $($idx.Handle) handlers index-wide (name-filtered); " +
                         "candidate refs in fresh files: $($idx.FreshFiles) of $($idx.Files) files") $PAL.lineInk
Add-DisclosureRow $ftbl 'callers come from resolved call_edges only: interface dispatch and DFM event wiring are not in them' $PAL.lineInk
if ($callers.Count) {
  Add-DisclosureRow $ftbl "a caller's handler is matched anywhere in its body; whether the call sits inside that try block is not checked" $PAL.lineInk
}
$edgelessNote = Get-EdgelessDisclosure (Get-EdgelessFiles)
if ($edgelessNote) { Add-DisclosureRow $ftbl $edgelessNote $PAL.lineInk }
[void]$ftbl.Append('</TABLE>')
[void]$sb.AppendLine("  subgraph cluster_focus_$nodeId {")
[void]$sb.AppendLine("    style=`"rounded,filled`"; color=`"$($PAL.focusBorder)`"; fillcolor=`"$($PAL.focusFill)`"; penwidth=2;")
[void]$sb.AppendLine('    label=""; margin=10;')
[void]$sb.AppendLine("    $fnid [label=<$($ftbl.ToString())>];")
[void]$sb.AppendLine('  }')

# A capped row cluster. Returns @{ Nid; Ports (ordinal, per SHOWN row); Shown }.
function Add-CappedCluster([string] $Key, [string] $Title, $Rows, [string] $Noun,
                           [string] $Border, [string] $Fill, [string] $Hdr, [string] $Style = 'rounded,filled',
                           [string] $Footer) {
  $script:nodeId++; $script:clusters++
  $nid = "n$($script:nodeId)"
  $top = Get-TopRanked $Rows $Cap 'none'
  $cells = New-Object System.Collections.ArrayList
  foreach ($r in $top.Shown) { [void]$cells.Add($r); if ($r.Href) { $script:anchored++ } }
  $more = Get-DisclosureText $top.HiddenRows 0 $Noun
  if ($more) { [void]$cells.Add((New-NoteRow $more)) }
  if ($Footer) { [void]$cells.Add((New-NoteRow $Footer)) }
  $ports = Add-RowCluster -Sb $sb -Cid "cluster_${Key}_$($script:nodeId)" -Nid $nid `
             -Title $Title -Subtitle "$($top.Total)" -Rows $cells.ToArray() `
             -Border $Border -Fill $Fill -Hdr $Hdr -RowInk $PAL.rowInk -LineInk $PAL.lineInk `
             -FontSans $FontSans -Style $Style
  [pscustomobject]@{ Nid = $nid; Ports = $ports; Shown = @($top.Shown) }
}

$portOfType = @{}      # raised type -> port of its first shown RAISE row
$raiseNid = $null

# -- LEFT: raises, ref-anchored
if ($body.Raises.Count) {
  $rows = @($body.Raises | Sort-Object Line | ForEach-Object {
    [pscustomobject]@{
      Label = "raise $($_.Type)"; Line = $_.Line; Href = New-RowHref $focus.Path $_.Line
      Tip = "raise $($_.Type) -- ${fileName}:$($_.Line):$($_.Col)"; Note = $null; Type = $_.Type
    } })
  $c = Add-CappedCluster 'raises' 'RAISES' $rows 'raise sites' $PAL.raiseBorder $PAL.raiseFill $PAL.raiseHdr
  $raiseNid = $c.Nid
  for ($i = 0; $i -lt $c.Shown.Count; $i++) {
    if (-not $portOfType.ContainsKey($c.Shown[$i].Type)) { $portOfType[$c.Shown[$i].Type] = $c.Ports[$i] }
  }
  [void]$sb.AppendLine("  $($c.Nid) -> ${fnid} [color=`"$($PAL.raiseBorder)`", dir=none];")
}
# -- LEFT, dashed: re-raises found only in source
if ($infRaise.Count) {
  $rows = @($infRaise | Sort-Object Line | ForEach-Object {
    [pscustomobject]@{
      Label = "$($_.Text) [inferred]"; Line = $_.Line; Href = New-RowHref $focus.Path $_.Line
      Tip = "$($_.Text) at ${fileName}:$($_.Line) -- $INFERRED_NOTE"; Note = $(if ($_.Kind -eq 'reraise') { 're-raise' } else { 'raises an object' })
    } })
  $c = Add-CappedCluster 'inferredraises' 'RE-RAISES [inferred]' $rows 're-raises' $PAL.raiseBorder $PAL.raiseFill $PAL.raiseHdr 'rounded,filled,dashed' $INFERRED_NOTE
  if ($c.Ports.Count) { $portOfType['(re-raise)'] = $c.Ports[0] }
  [void]$sb.AppendLine("  $($c.Nid) -> ${fnid} [color=`"$($PAL.raiseBorder)`", style=dashed, dir=none];")
}
# -- RIGHT: handlers in body
$handleNid = $null
if ($body.Handles.Count) {
  $rows = @($body.Handles | Sort-Object Line | ForEach-Object {
    [pscustomobject]@{
      Label = "on $($_.Type)"; Line = $_.Line; Href = New-RowHref $focus.Path $_.Line
      Tip = "on ...: $($_.Type) do -- ${fileName}:$($_.Line):$($_.Col)"; Note = $null
    } })
  $c = Add-CappedCluster 'handlers' 'HANDLERS IN BODY' $rows 'handler clauses' $PAL.handleBorder $PAL.handleFill $PAL.handleHdr
  $handleNid = $c.Nid
  [void]$sb.AppendLine("  ${fnid} -> $($c.Nid) [color=`"$($PAL.handleBorder)`", dir=none];")
}
# -- RIGHT, dashed: bare except blocks
if ($infBare.Count) {
  $rows = @($infBare | Sort-Object Line | ForEach-Object {
    [pscustomobject]@{
      Label = 'except (no on clause) [inferred]'; Line = $_.Line; Href = New-RowHref $focus.Path $_.Line
      Tip = "bare except at ${fileName}:$($_.Line) -- $INFERRED_NOTE"; Note = 'catches everything'
    } })
  $c = Add-CappedCluster 'inferredhandlers' 'BARE EXCEPT [inferred]' $rows 'bare except blocks' $PAL.handleBorder $PAL.handleFill $PAL.handleHdr 'rounded,filled,dashed' $INFERRED_NOTE
  [void]$sb.AppendLine("  ${fnid} -> $($c.Nid) [color=`"$($PAL.handleBorder)`", style=dashed, dir=none];")
}
# -- stale: listed, never classified
if ($body.StaleRows.Count) {
  $rows = @($body.StaleRows | Sort-Object Line | ForEach-Object {
    [pscustomobject]@{
      Label = "$($_.Type) [stale source]"; Line = $_.Line; Href = New-RowHref $focus.Path $_.Line
      Tip = "$($_.Kind) $($_.Type) at ${fileName}:$($_.Line) -- the file on disk differs from the indexed copy; not classified"
      Note = 'not classified'
    } })
  $c = Add-CappedCluster 'stale' '[stale source]' $rows 'references' $PAL.staleBorder $PAL.staleFill $PAL.staleHdr 'rounded,filled,dashed' 'file differs from the indexed copy -- nothing here is classified'
  [void]$sb.AppendLine("  ${fnid} -> $($c.Nid) [color=`"$($PAL.staleBorder)`", style=dashed, dir=none];")
}

# -- BELOW / RIGHT: the caller chain, one cluster per depth
$catchPort = @{}   # "<callerId>|<line>" -> port of that handler row
$prevNid = $fnid; $prevPort = "${fnid}:p1"
for ($d = 1; $d -le $levels; $d++) {
  # callers holding a catching (or may-catching) handler first, so -Cap never hides
  # the row a catch edge points at. The caller id is bound to a name before the
  # inner filters, whose $_ is a verdict, not the caller.
  $atD = @($callers | Where-Object { $_.D -eq $d } | Sort-Object @{ E = {
            $cid = $_.Info.Id
            -not @($verdicts | Where-Object { ($_.Caught -and $_.Caught.Caller.Info.Id -eq $cid) -or
                                              @($_.May | Where-Object { $_.Caller.Info.Id -eq $cid }).Count }).Count } },
          @{ E = { $_.Info.Q } })
  if (-not $atD.Count) { continue }
  $rows = New-Object System.Collections.ArrayList
  $keys = New-Object System.Collections.ArrayList
  foreach ($c in $atD) {
    $ci = $c.Info
    $calleeName = $(if ($c.Parent -eq $sel.Id) { $sel.Name } elseif ($cinfo.ContainsKey($c.Parent)) { $cinfo[$c.Parent].Name } else { '?' })
    $hn = $c.Body.Handles.Count + $c.Body.Inferred.Count
    $note = $(if (-not $c.Body.Fresh) { '[stale source] handlers not read' } else { "$hn handler(s)" })
    [void]$rows.Add([pscustomobject]@{
      Label = Get-ShortName $ci.Q $ci.Unit; Line = $ci.Line; Href = New-RowHref $ci.Path $ci.Line
      Tip = "$($ci.Q) calls $calleeName at $([IO.Path]::GetFileName($ci.Path)):$($c.Site)"; Note = $note
    })
    [void]$keys.Add($null)
    # the handler rows that catch or may catch something raised by the focus
    $hRows = @{}
    foreach ($v in $verdicts) {
      if ($v.Caught -and $v.Caught.Caller.Info.Id -eq $ci.Id) { $hRows[$v.Caught.Handler.Line] = $v.Caught.Handler }
      foreach ($m in $v.May) { if ($m.Caller.Info.Id -eq $ci.Id) { $hRows[$m.Handler.Line] = $m.Handler } }
    }
    foreach ($ln in ($hRows.Keys | Sort-Object)) {
      $h = $hRows[$ln]
      $lbl = $(if ($h.Bare) { '  except (no on clause) [inferred]' } else { "  on $($h.H)" })
      [void]$rows.Add([pscustomobject]@{
        Label = $lbl; Line = $ln; Href = New-RowHref $ci.Path $ln
        Tip = "$($lbl.Trim()) in $($ci.Q) -- $([IO.Path]::GetFileName($ci.Path)):$ln"; Note = 'handler'
      })
      [void]$keys.Add("$($ci.Id)|$ln")
    }
  }
  # no cap on handler rows (they carry edges); callers beyond -Cap are disclosed
  $nodeId++; $clusters++
  $nid = "n$nodeId"
  $cells = New-Object System.Collections.ArrayList
  $callerRowsShown = 0; $hiddenCallers = 0
  $keep = New-Object System.Collections.ArrayList
  for ($i = 0; $i -lt $rows.Count; $i++) {
    $isCallerRow = ($null -eq $keys[$i])
    if ($isCallerRow) {
      if ($callerRowsShown -ge $Cap) { $hiddenCallers++; $skipHandlers = $true; continue }
      $callerRowsShown++; $skipHandlers = $false
    } elseif ($skipHandlers) { continue }
    [void]$cells.Add($rows[$i]); [void]$keep.Add($keys[$i]); $anchored++
  }
  $more = Get-DisclosureText $hiddenCallers 0 'callers'
  if ($more) { [void]$cells.Add((New-NoteRow $more)); [void]$keep.Add($null) }
  $ports = Add-RowCluster -Sb $sb -Cid "cluster_d${d}_$nodeId" -Nid $nid `
             -Title 'CALLERS' -Subtitle "depth $d, $($atD.Count) caller$(if ($atD.Count -ne 1) { 's' })" -Rows $cells.ToArray() `
             -Border $PAL.callerBorder -Fill $PAL.callerFill -Hdr $PAL.callerHdr `
             -RowInk $PAL.rowInk -LineInk $PAL.lineInk -FontSans $FontSans
  for ($i = 0; $i -lt $keep.Count; $i++) { if ($keep[$i]) { $catchPort[$keep[$i]] = $ports[$i] } }
  # the exception travels UP: from the callee level to the level that called it
  [void]$sb.AppendLine("  $prevPort -> $nid [color=`"$($PAL.callerBorder)`", label=`" escapes to depth $d `"];")
  $prevNid = $nid; $prevPort = $nid
}

# -- catch edges: raise row -> the handler that catches it
foreach ($v in $verdicts) {
  $from = $(if ($portOfType.ContainsKey($v.Type)) { $portOfType[$v.Type] } elseif ($raiseNid) { $raiseNid } else { $fnid })
  if ($v.Caught) {
    $k = "$($v.Caught.Caller.Info.Id)|$($v.Caught.Handler.Line)"
    if ($catchPort.ContainsKey($k)) {
      $lbl = "caught ($($v.Caught.How))$(if ($v.Also) { " +$($v.Also) more at depth $($v.Caught.Caller.D)" })"
      [void]$sb.AppendLine("  $from -> $($catchPort[$k]) [color=`"$($PAL.handleBorder)`", penwidth=2, label=`" $(ConvertTo-XmlText $lbl) `"];")
    }
  }
  foreach ($m in $v.May) {
    $k = "$($m.Caller.Info.Id)|$($m.Handler.Line)"
    if ($catchPort.ContainsKey($k)) {
      [void]$sb.AppendLine("  $from -> $($catchPort[$k]) [color=`"$($PAL.handleBorder)`", style=dashed, label=`" may catch -- ancestry not in this index `"];")
    }
  }
}
[void]$sb.AppendLine('}')

if ([string]::IsNullOrWhiteSpace($OutDir)) { $OutDir = Join-Path $PSScriptRoot '..\scratch' }
$lay = Invoke-DotLayout $sb.ToString() $OutDir ('excpaths_' + ($sel.Qname -replace '[^A-Za-z0-9]', '_'))

[pscustomobject]@{
  Dot            = $lay.Dot
  Svg            = $lay.Svg
  Plain          = $lay.Plain
  Png            = $lay.Png
  Pdf            = $lay.Pdf
  Qname          = $sel.Qname
  Raises         = $body.Raises.Count
  RaiseTypes     = $raiseTypes.Count
  RaiseTypeNames = ($raiseTypes -join ',')
  RaiseLines     = (@($body.Raises | ForEach-Object { $_.Line } | Sort-Object) -join ',')
  Handles        = $body.Handles.Count
  HandleLines    = (@($body.Handles | ForEach-Object { $_.Line } | Sort-Object) -join ',')
  Dropped        = $body.Dropped
  Inferred       = $body.Inferred.Count
  InferredRaises = $infRaise.Count
  BareExcepts    = $infBare.Count
  InferredLines  = (@($body.Inferred | ForEach-Object { "$($_.Kind)@$($_.Line)" }) -join ',')
  StaleRows      = $body.StaleRows.Count
  FocusFresh     = $body.Fresh
  Callers        = $callers.Count
  CallerLevels   = $levels
  CallerNames    = (@($callers | ForEach-Object { "d$($_.D):$($_.Info.Name)" }) -join ',')
  CallersCapped  = $callerCapped
  Caught         = $caughtCount
  MayCatch       = $mayCount
  # $null when every raised type was caught: the sentence is about a walk that
  # ENDED without a handler, and is only drawn in that case
  WalkSentence   = $(if ($types.Count -and $caughtCount -eq $types.Count) { $null } else { $walkSentence })
  FilesTouched   = $touched.Count
  StaleFiles     = $staleFiles
  IndexCandidates = $idx.Candidates
  IndexRaise     = $idx.Raise
  IndexHandle    = $idx.Handle
  IndexDropped   = $idx.Dropped
  IndexRaiseRoutines  = $idx.RaiseRoutines
  IndexHandleRoutines = $idx.HandleRoutines
  Clusters       = $clusters
  ClickTargets   = $lay.Anchors
  Expected       = $anchored
  AllClickable   = ($lay.Anchors -ge $anchored)
}
