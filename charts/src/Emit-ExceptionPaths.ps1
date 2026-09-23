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

  A caller's handler counts only when a call SITE lies between the `try` and the
  `except` of the block that holds it (Get-TryBlocks, controller ruling R10 --
  fix round 1: the first version matched a handler anywhere in the body, and its
  one pinned solid edge was false). A handler that re-raises is "caught and
  re-raised" and the walk goes on; an undecidable nesting scan is a dashed
  [inferred] edge, never a solid one.

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
# End of the walk (fix round 1, ruling R11) -- only 'left-index' lets the chart
# say a handler CANNOT catch:
#   left-index        an unbound ancestor whose name is not a class here: the
#                     chain left the project, so no class declared here is above it
#   unbound-in-index  an unbound ancestor whose name IS a class here (a resolver
#                     gap -- the chain may continue through it)
#   no-row            a declared class with no ancestor row at all
#   cap               the walk hit 32 links
$ancCache = @{}
function Get-TypeChain([string] $T) {
  if ($ancCache.ContainsKey($T)) { return $ancCache[$T] }
  $q = ConvertTo-SqlText $T
  $decl = Invoke-IndexQuery "SELECT DISTINCT id AS id, qualified_name AS q FROM symbols WHERE kind = 'class' AND name = '$q'"
  $names = New-Object System.Collections.ArrayList
  [void]$names.Add($T)
  $state = 'external'; $end = ''
  if ($decl.Count -gt 1 -and @($decl | ForEach-Object { $_.q } | Sort-Object -Unique).Count -gt 1) {
    $state = 'ambiguous'
  } elseif ($decl.Count -ge 1) {
    $state = 'walked'; $end = 'cap'
    $cur = [int]$decl[0].id
    for ($i = 0; $i -lt 32; $i++) {
      $a = Invoke-IndexQuery "SELECT ancestor_name AS n, ancestor_symbol_id AS s FROM type_ancestors WHERE symbol_id = $cur AND ordinal = 0"
      if ($a.Count -eq 0) { $end = 'no-row'; break }
      $an = (([string]$a[0].n) -split '\.')[-1]
      [void]$names.Add($an)
      if ($a[0].s) { $cur = [int]$a[0].s; continue }
      $end = $(if (Test-ClassInIndex $an) { 'unbound-in-index' } else { 'left-index' })
      break
    }
  }
  $o = [pscustomobject]@{ Type = $T; State = $state; End = $end; Names = $names.ToArray() }
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

# 'exact' / 'catch-all' / 'ancestor' / 'bare' are SOLID TYPE matches (whether the
# handler guards the call is decided separately, below); 'may' is dashed; 'no'
# means H cannot catch T. $T of '(re-raise)' is the object of a `raise;` /
# `raise E` -- its type is not a fact, so only a catch-all or a bare except
# matches it for certain.
function Get-CatchVerdict([string] $T, [string] $H, [bool] $Bare) {
  if ($Bare) { return 'bare' }
  if ($H -ieq 'Exception') { return 'catch-all' }
  if ($T -eq '(re-raise)') { return 'may' }
  if ($H -ieq $T) { return 'exact' }
  $ch = Get-TypeChain $T
  if (@($ch.Names | Select-Object -Skip 1 | Where-Object { $_ -ieq $H }).Count) { return 'ancestor' }
  # 'no' ONLY when the chain provably LEFT the project (R11): its last link is
  # unbound and not a class here, no cap, no missing row. A class declared here
  # cannot sit above a class declared outside, so H (ours) is not an ancestor.
  # Any other ending leaves the question open.
  if ($ch.State -eq 'walked' -and $ch.End -eq 'left-index' -and (Test-ClassInIndex $H)) { return 'no' }
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
# Every call SITE is kept (line and column), not just the first: containment in a
# handler's try is a question about the site, and one caller can call the same
# routine both inside and outside a try.
$dist = @{ $sel.Id = 0 }
$parentOf = @{}
$sitesOf = @{}
$frontier = @($sel.Id)
$callerCapped = $false
$levels = 0
for ($d = 1; $d -le $Depth; $d++) {
  if ($frontier.Count -eq 0) { break }
  $next = New-Object System.Collections.ArrayList
  for ($i = 0; $i -lt $frontier.Count; $i += 60) {
    $chunk = @($frontier[$i..([Math]::Min($i + 59, $frontier.Count - 1))])
    $pairs = Get-AllIndexRows @"
SELECT r.enclosing_symbol_id AS caller, ce.target_symbol_id AS callee,
       group_concat(r.start_line || ':' || r.start_col, ',') AS sites
  FROM call_edges ce JOIN refs r ON r.id = ce.ref_id
 WHERE ce.target_symbol_id IN ($($chunk -join ',')) AND r.enclosing_symbol_id IS NOT NULL
 GROUP BY r.enclosing_symbol_id, ce.target_symbol_id
"@ 'caller, callee'
    foreach ($p in $pairs) {
      $cid = [int]$p.caller
      $pos = @(([string]$p.sites -split ',') | ForEach-Object { $a = $_ -split ':'; [int]$a[0] * 100000 + [int]$a[1] })
      if ($dist.ContainsKey($cid)) {
        # a second walked callee at the SAME level: its sites count too
        if ($dist[$cid] -eq $d) { $sitesOf[$cid] = @($sitesOf[$cid]) + $pos }
        continue
      }
      if (($dist.Count - 1) -ge $MaxCallers) { $callerCapped = $true; break }
      $dist[$cid] = $d; $parentOf[$cid] = [int]$p.callee; $sitesOf[$cid] = $pos
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
  # the try-block nesting of the caller span (R10); a stale file is not scanned
  $tb = $null; $lines = $null
  if ($cb.Fresh -and $ci.From -gt 0) {
    $lines = Get-StrippedSourceLines (Resolve-SourceReadPath $ci.Path $SourceOverride)
    $tb = Get-TryBlocks $lines $ci.From $ci.To
  }
  [pscustomobject]@{ Info = $ci; D = $dist[$_]; Parent = $parentOf[$_]; Sites = @($sitesOf[$_])
                     Body = $cb; Try = $tb; Lines = $lines }
} | Sort-Object D, @{ E = { $_.Info.Q } })
$staleCallers = @($callers | Where-Object { -not $_.Body.Fresh }).Count
Write-Host ("  callers walked: {0} over {1} level(s){2}{3}" -f $callers.Count, $levels,
            $(if ($callerCapped) { " [CAPPED at $MaxCallers]" } else { '' }),
            $(if ($staleCallers) { ", $staleCallers not read (stale)" } else { '' }))

# ---- 4. handled-where, per raised type ---------------------------------------------------
# One handler, one caller, one raised type -> one of (fix round 1, ruling R10):
#   caught       the type matches, EVERY call site is inside the handler's try,
#                and the handler does not re-raise -- a SOLID edge; the walk
#                stops after this depth
#   partial      matches and does not re-raise, but only k of n sites are inside
#                -- solid, labelled; the walk goes on (the other sites escape)
#   reraised     matches, a site is inside, and the handler body re-raises
#                (`raise;` / `raise <its variable>`) -- solid "caught and
#                re-raised"; the walk goes on
#   unverified   the nesting scan could not decide -- DASHED, "call site not
#                verified inside its try"; the walk goes on
#   may          a site is inside (or undecided) but the TYPE relation is
#                unknown -- dashed "may catch -- ancestry not in this index"
# A matching handler whose try does NOT contain any call site guards something
# else: it is counted (NotGuarding), never drawn -- BuildSchema's two callers.
# A 'no' type verdict is counted and disclosed, never drawn (R11).

# Find-HandlerBlock is in Emit-Common, beside Get-TryBlocks.
# Re-raise detection is Test-HandlerReraises (Emit-Common), over the caller's
# stripped lines, so a check can drive it with a synthetic body.

$typeResults = New-Object System.Collections.ArrayList
$events = New-Object System.Collections.ArrayList
$types = @(@($raiseTypes) + $(if ($infRaise.Count) { @('(re-raise)') } else { @() }))
foreach ($t in $types) {
  $stop = $null; $notGuarding = 0; $noCount = 0
  $mine = New-Object System.Collections.ArrayList
  for ($d = 1; $d -le $levels -and -not $stop; $d++) {
    foreach ($c in @($callers | Where-Object { $_.D -eq $d })) {
      if (-not $c.Body.Fresh) { continue }          # counted in $staleCallers, said on the chart
      $cands = @(@($c.Body.Handles | ForEach-Object { [pscustomobject]@{ H = $_.Type; Line = $_.Line; Pos = $_.Line * 100000 + $_.Col; Bare = $false } }) +
                 @($c.Body.Inferred | ForEach-Object { [pscustomobject]@{ H = 'except'; Line = $_.Line; Pos = $_.Line * 100000 + $_.Col; Bare = $true } }) |
                 Sort-Object Pos)
      foreach ($h in $cands) {
        $v = Get-CatchVerdict $t $h.H $h.Bare
        if ($v -eq 'no') { $noCount++; continue }
        $blk = $(if ($c.Try -and $c.Try.Decided) { Find-HandlerBlock $c.Try $h.Pos } else { $null })
        if (-not $blk) {
          $kind = $(if ($v -eq 'may') { 'may' } else { 'unverified' })
          [void]$mine.Add([pscustomobject]@{ Type = $t; Caller = $c; Handler = $h; Kind = $kind; How = $v; Inside = 0; Total = $c.Sites.Count })
          continue
        }
        $inside = @($c.Sites | Where-Object { $_ -gt $blk.Try -and $_ -lt $blk.Except }).Count
        if ($inside -eq 0) { $notGuarding++; continue }
        if ($v -eq 'may') { $kind = 'may' }
        elseif (Test-HandlerReraises $c.Lines $blk $h.Pos $h.Bare) { $kind = 'reraised' }
        elseif ($inside -lt $c.Sites.Count) { $kind = 'partial' }
        else { $kind = 'caught' }
        $ev = [pscustomobject]@{ Type = $t; Caller = $c; Handler = $h; Kind = $kind; How = $v; Inside = $inside; Total = $c.Sites.Count }
        [void]$mine.Add($ev)
        if ($kind -eq 'caught' -and -not $stop) { $stop = $ev }
      }
    }
  }
  foreach ($e2 in $mine) { [void]$events.Add($e2) }
  [void]$typeResults.Add([pscustomobject]@{ Type = $t; Stop = $stop; Events = $mine.ToArray(); NotGuarding = $notGuarding; No = $noCount })
}
$caughtCount = @($typeResults | Where-Object { $_.Stop }).Count
function Get-EventCount([string] $K) { @($events | Where-Object { $_.Kind -eq $K }).Count }
$mayCount        = Get-EventCount 'may'
$reraisedCount   = Get-EventCount 'reraised'
$unverifiedCount = Get-EventCount 'unverified'
$partialCount    = Get-EventCount 'partial'
$solidCount      = @($events | Where-Object { $_.Kind -in 'caught', 'partial', 'reraised' }).Count
$notGuardingCount = ($typeResults | ForEach-Object { $_.NotGuarding } | Measure-Object -Sum).Sum
$noVerdictCount   = ($typeResults | ForEach-Object { $_.No } | Measure-Object -Sum).Sum
if (-not $notGuardingCount) { $notGuardingCount = 0 }
if (-not $noVerdictCount) { $noVerdictCount = 0 }

# The sentence for a type the walk did not stop. It never says "unhandled" (R3),
# and it never covers callers it did not read (fix round 1, finding 3).
$staleNote = $(if ($staleCallers) { "; $staleCallers caller$(if ($staleCallers -ne 1) { 's' }) not read: source changed since indexing" } else { '' })
function Get-WalkSentence($Tr) {
  if ($callers.Count -eq 0) { return 'no resolved caller in this index' }
  $lv = "$Depth caller level$(if ($Depth -ne 1) { 's' })"
  $cw = "$($callers.Count) caller$(if ($callers.Count -ne 1) { 's' }) walked"
  $seen = @($Tr.Events | Group-Object Kind | Sort-Object Name | ForEach-Object { "$($_.Count) $($_.Name)" })
  if ($seen.Count) { return "no handler that stops it found within $lv ($cw; $($seen -join ', '))$staleNote" }
  "no handler found within $lv ($cw)$staleNote"
}
$walkLines = @($typeResults | Where-Object { -not $_.Stop } | ForEach-Object {
  $s = Get-WalkSentence $_
  $(if ($types.Count -gt 1) { "$($_.Type): $s" } else { $s }) })
$walkSentence = $(if ($walkLines.Count) { $walkLines -join '; ' } else { $null })

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
  foreach ($wl in $walkLines) { Add-DisclosureRow $ftbl "handled-where: $wl" $PAL.lineInk }
} elseif (-not $types.Count) {
  Add-DisclosureRow $ftbl "callers: $(if ($callers.Count) { "$($callers.Count) walked over $levels level(s)$staleNote" } else { 'no resolved caller in this index' })" $PAL.lineInk
} elseif ($staleCallers) {
  Add-DisclosureRow $ftbl "$staleCallers caller(s) not read: source changed since indexing" $PAL.lineInk
}
if ($callerCapped) { Add-DisclosureRow $ftbl "caller walk CAPPED at $MaxCallers -- more callers exist" $PAL.lineInk }
Add-DisclosureRow $ftbl ("approximately $($idx.Raise) raise sites / $($idx.Handle) handlers index-wide (name-filtered); " +
                         "candidate refs in fresh files: $($idx.FreshFiles) of $($idx.Files) files") $PAL.lineInk
Add-DisclosureRow $ftbl 'callers come from resolved call_edges only: interface dispatch and DFM event wiring are not in them' $PAL.lineInk
if ($callers.Count) {
  Add-DisclosureRow $ftbl "a caller's handler counts only when a call site lies between its try and its except (nesting scan of the stripped caller body)" $PAL.lineInk
}
if ($notGuardingCount) {
  Add-DisclosureRow $ftbl "$notGuardingCount matching handler(s) in callers guard other statements, not the call -- not drawn" $PAL.lineInk
}
if ($noVerdictCount) {
  Add-DisclosureRow $ftbl "$noVerdictCount typed handler(s) in callers cannot catch: declared here, and the raised type's ancestry left the project without reaching them -- not drawn" $PAL.lineInk
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
$catchPort = @{}   # "<callerId>|<handler pos>" -> port of that handler row
$prevNid = $fnid; $prevPort = "${fnid}:p1"
for ($d = 1; $d -le $levels; $d++) {
  # callers holding a handler that is drawn come first, so -Cap never hides the
  # row an edge points at. The caller id is bound to a name before the inner
  # filter, whose $_ is an event, not the caller.
  $atD = @($callers | Where-Object { $_.D -eq $d } | Sort-Object @{ E = {
            $cid = $_.Info.Id
            -not @($events | Where-Object { $_.Caller.Info.Id -eq $cid }).Count } },
          @{ E = { $_.Info.Q } })
  if (-not $atD.Count) { continue }
  $rows = New-Object System.Collections.ArrayList
  $keys = New-Object System.Collections.ArrayList
  foreach ($c in $atD) {
    $ci = $c.Info
    $calleeName = $(if ($c.Parent -eq $sel.Id) { $sel.Name } elseif ($cinfo.ContainsKey($c.Parent)) { $cinfo[$c.Parent].Name } else { '?' })
    $hn = $c.Body.Handles.Count + $c.Body.Inferred.Count
    $note = $(if (-not $c.Body.Fresh) { '[stale source] not read: source changed since indexing' } else { "$hn handler(s)" })
    $siteLines = (@($c.Sites | ForEach-Object { [Math]::Floor($_ / 100000) } | Sort-Object -Unique) -join ', ')
    [void]$rows.Add([pscustomobject]@{
      Label = Get-ShortName $ci.Q $ci.Unit; Line = $ci.Line; Href = New-RowHref $ci.Path $ci.Line
      Tip = "$($ci.Q) calls $calleeName at $([IO.Path]::GetFileName($ci.Path)):$siteLines"; Note = $note
    })
    [void]$keys.Add($null)
    # the handler rows an event points at
    $hRows = @{}
    foreach ($ev in @($events | Where-Object { $_.Caller.Info.Id -eq $ci.Id })) { $hRows[$ev.Handler.Pos] = $ev.Handler }
    foreach ($hp in ($hRows.Keys | Sort-Object)) {
      $h = $hRows[$hp]
      $lbl = $(if ($h.Bare) { '  except (no on clause) [inferred]' } else { "  on $($h.H)" })
      [void]$rows.Add([pscustomobject]@{
        Label = $lbl; Line = $h.Line; Href = New-RowHref $ci.Path $h.Line
        Tip = "$($lbl.Trim()) in $($ci.Q) -- $([IO.Path]::GetFileName($ci.Path)):$($h.Line)"; Note = 'handler'
      })
      [void]$keys.Add("$($ci.Id)|$hp")
    }
  }
  # no cap on handler rows (they carry edges); callers beyond -Cap are disclosed
  $nodeId++; $clusters++
  $nid = "n$nodeId"
  $cells = New-Object System.Collections.ArrayList
  $callerRowsShown = 0; $hiddenCallers = 0; $skipHandlers = $false
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

# -- handler edges: raise row -> the caller handler, styled by what was PROVEN
foreach ($ev in $events) {
  $from = $(if ($portOfType.ContainsKey($ev.Type)) { $portOfType[$ev.Type] } elseif ($raiseNid) { $raiseNid } else { $fnid })
  $k = "$($ev.Caller.Info.Id)|$($ev.Handler.Pos)"
  if (-not $catchPort.ContainsKey($k)) { continue }
  $at = "$($ev.Caller.Info.Name):$($ev.Handler.Line)"
  switch ($ev.Kind) {
    'caught'     { $lbl = "caught ($($ev.How)) at $at"; $st = 'penwidth=2' }
    'partial'    { $lbl = "caught ($($ev.How)) at $at for $($ev.Inside) of $($ev.Total) call sites"; $st = 'penwidth=2' }
    'reraised'   { $lbl = "caught and re-raised ($($ev.How)) at $at"; $st = 'penwidth=2' }
    'unverified' { $lbl = 'handler in caller body; call site not verified inside its try [inferred]'; $st = 'style=dashed' }
    default      { $lbl = 'may catch -- ancestry not in this index'; $st = 'style=dashed' }
  }
  [void]$sb.AppendLine("  $from -> $($catchPort[$k]) [color=`"$($PAL.handleBorder)`", $st, label=`" $(ConvertTo-XmlText $lbl) `"];")
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
  Caught         = $caughtCount       # raised types STOPPED by a verified, non-re-raising handler
  SolidEdges     = $solidCount
  ReRaised       = $reraisedCount
  Partial        = $partialCount
  Unverified     = $unverifiedCount
  MayCatch       = $mayCount
  NotGuarding    = $notGuardingCount
  NoVerdicts     = $noVerdictCount
  StaleCallers   = $staleCallers
  Events         = (@($events | ForEach-Object { "$($_.Kind):$($_.Caller.Info.Name):$($_.Handler.Line)" }) -join ',')
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
