<#
  Trace.Chart.ps1 -- the round-trip CHART (R5): the trace drawn as a picture.
  Spec: docs\superpowers\specs\2026-10-05-R5-round-trip-chart-design.md (local); its
  section 10 (owner answers, 2026-10-05) is binding where it differs from 1-9.

  ONE function the emitter calls, ConvertTo-TraceChart, plus its private helpers.
  Functions only, dot-sourced AFTER Emit-Common.ps1 and Trace.FormA.ps1 (the
  Trace.FormA contract): NO index access, no source reads, no file writes. The
  input is the trace MODEL -- Emit-RoundTrip passes Read-FormA of the bytes it
  just wrote, so the chart is a pure function of trace.dlgraph -- and the
  leaf -> one-full-path map the emitter already builds for the bundle page's
  links (DOC-R1). Output: the .dot text and a Manifest saying where every step,
  condition and facet went. Invoke-DotLayout (Emit-Common) does the layout.

  The picture, in one paragraph. Four lanes, left to right, from the TIERS
  header (client -> pipe -> server -> database). A step's lane comes from its
  SECTION and actor word, never from an index. Steps become ROWS of a card --
  one card per (lane, routine): a `CALLS X` step is a row of X's card, a step
  `in X` a row of X's card -- so the request and its response read in one
  place. The ANCHOR's client rows are one chain card; a `.sql`-anchored step in
  the DATABASE lane is a column node (cylinder) that every direction meets at;
  each send anchor is ONE crossing node holding the request and the response;
  a STOPS is its own red node; a FIRES step is a small event node; ALSO is a
  dashed sub-cluster. A WHEN / UNLESS is a guard ROW under the step it gates,
  verbatim (wrapped, never shortened, never quoted); a guard whose else note
  names a line also gets a red failure edge to that line. Identical rows in one
  card (the EnsureLoaded / LoadFromInternal sub-walk both directions run) are
  drawn ONCE carrying both numbers, `[21]/[51]` (owner answer 5).

  Nothing is silently smaller. Every number is either on a drawn row or named
  in a disclosure row (`+N more ... not shown -- [aa]-[bb] ...`) that the
  Legend repeats; the Legend also carries the END TRACE line byte for byte,
  every section's generated note, and how many labels were shortened. The size
  rules (4.1, owner answer 4): ALSO shows every row up to $Caps.Also (default
  15 -- only an unusually long list folds); a routine card, the anchor chain and the DERIVED card
  (owner 2026-10-06: capped like its components) fold plain rows past $Caps.Rows (default 14) but
  never a protected row (a guard, a crossing, a STOPS, a failure edge, a column); above $Caps.Nodes
  (default 45) nodes the ladder folds ALSO, then every card with no protected row -- and if the
  chart is still above the cap it is drawn anyway and the Legend says so. Owner 2026-10-06: a
  fold of k rows draws one disclosure row on the card and one in the Legend, so a fold of fewer
  than 3 rows saves nothing and is not made; above $Caps.Folds (default 5) folds, the Legend
  carries ONE summary row (the folded steps' ranges when the row stays within
  $script:ChartSummaryWidth characters, else only their count) instead of one row per fold.

  Unknown section names, actor words outside the TIERS and an unnumbered item
  THROW (R19): a grammar that grows must grow this renderer, never fall into a
  default lane.
#>

$script:ChartSections    = @('ANCHOR', 'DERIVED', 'WRITE', 'SERVER', 'DATABASE', 'RESPONSE', 'READ', 'ALSO')
$script:ChartWidth       = 72
$script:ChartMaxLines    = 5
$script:ChartCapDefaults = @{ Also = 15; Rows = 14; Nodes = 45; Folds = 5 }
# the longest Legend summary row that still names the folded ranges (one unwrapped Legend row); past it, only the count
$script:ChartSummaryWidth = 120
# lane -> border, fill, header ink
$script:ChartLaneInk = @{
  CLIENT   = @('#2563EB', '#F2F6FF', '#1D4ED8')
  PIPE     = @('#B45309', '#FFF8EC', '#92400E')
  SERVER   = @('#047857', '#EEFBF4', '#065F46')
  DATABASE = @('#7C3AED', '#F6F1FF', '#5B21B6')
}
$script:ChartInk = @{ Text = '#1F2933'; Dim = '#6B7684'; Guard = '#B45309'; Fail = '#B91C1C'; Facet = '#0F766E'; Also = '#8A94A6' }

# A space that may become a line break: one space between two non-spaces, so rejoining the pieces with
# ONE space gives back the text exactly (a condition holding two spaces keeps them, A-R5-VERBATIM).
function Test-ChartBreakable([string] $T, [int] $K) {
  $T[$K] -eq ' ' -and $K -gt 0 -and $T[$K - 1] -ne ' ' -and ($K + 1) -lt $T.Length -and $T[$K + 1] -ne ' '
}

# The break positions of $Text at $Width: greedy, the last breakable space that keeps the line within the
# width, else the first one after it (a token longer than the width stays whole -- never cut).
function Get-ChartBreaks([string] $Text, [int] $Width) {
  $set = New-Object 'System.Collections.Generic.HashSet[int]'
  $start = 0
  while ($Text.Length - $start -gt $Width) {
    $cut = -1
    for ($k = $start + $Width; $k -gt $start; $k--) { if (Test-ChartBreakable $Text $k) { $cut = $k; break } }
    if ($cut -lt 0) { for ($k = $start + $Width + 1; $k -lt $Text.Length; $k++) { if (Test-ChartBreakable $Text $k) { $cut = $k; break } } }
    if ($cut -lt 0) { break }
    [void]$set.Add($cut); $start = $cut + 1
  }
  , $set
}

# Segments -> the HTML of one cell. A segment is @(text, ink, point size, bold); the text is escaped here and
# each break space becomes <BR ALIGN="LEFT"/>. An empty segment is skipped (an empty FONT is a dot syntax error).
function ConvertTo-ChartCellHtml($Segs, [int] $Width = $script:ChartWidth) {
  $plain = -join @($Segs | ForEach-Object { [string]$_[0] })
  $breaks = Get-ChartBreaks $plain $Width
  $sb = New-Object System.Text.StringBuilder
  $pos = 0
  foreach ($s in $Segs) {
    $t = [string]$s[0]
    if (-not $t) { continue }
    $open = '<FONT' + $(if ($s[1]) { " COLOR=`"$($s[1])`"" } else { '' }) + $(if ($s[2]) { " POINT-SIZE=`"$($s[2])`"" } else { '' }) + '>'
    $close = '</FONT>'
    if ($s[3]) { $open += '<B>'; $close = '</B></FONT>' }
    [void]$sb.Append($open)
    $chunk = New-Object System.Text.StringBuilder
    for ($k = 0; $k -lt $t.Length; $k++) {
      if ($breaks.Contains($pos + $k)) { [void]$sb.Append((ConvertTo-XmlText $chunk.ToString())).Append('<BR ALIGN="LEFT"/>'); [void]$chunk.Clear() }
      else { [void]$chunk.Append($t[$k]) }
    }
    [void]$sb.Append((ConvertTo-XmlText $chunk.ToString())).Append($close)
    $pos += $t.Length
  }
  $sb.ToString()
}

# '<leaf>:<line>' with a .sql leaf (case-insensitive: the corpus writes MS1.SQL)
function Test-ChartSqlAnchor([string] $Anchor) { $Anchor -match '\.sql:\d+$' }

# Step numbers as the disclosure rows print them: two digits, runs folded -- [74]-[76], [80]
function Format-ChartNumbers($Nums) {
  $n = @($Nums | Sort-Object -Unique)
  $out = @(); $i = 0
  while ($i -lt $n.Count) {
    $j = $i
    while ($j + 1 -lt $n.Count -and [int]$n[$j + 1] -eq [int]$n[$j] + 1) { $j++ }
    $out += $(if ($j -gt $i) { '[{0:00}]-[{1:00}]' -f [int]$n[$i], [int]$n[$j] } else { '[{0:00}]' -f [int]$n[$i] })
    $i = $j + 1
  }
  $out -join ', '
}

# The lane of one step, from the TEXT (spec 3.1). $Lanes: the upper-case tier words of the TIERS header.
function Get-TraceChartLane([string] $Section, $Item, [string[]] $Lanes) {
  $x = $Item.Kind -eq 'crosses'
  $lane = switch -CaseSensitive ($Section) {
    'ANCHOR'   { $(if ($x) { 'PIPE' } elseif (Test-ChartSqlAnchor $Item.Anchor) { 'DATABASE' } else { 'CLIENT' }) }
    'DERIVED'  { 'CLIENT' }
    'WRITE'    { $(if ($x) { 'PIPE' } else { 'CLIENT' }) }
    'RESPONSE' { $(if ($x) { 'PIPE' } else { 'CLIENT' }) }
    'SERVER'   { $(if ($x) { 'PIPE' } else { 'SERVER' }) }
    'DATABASE' { $(if ($x) { 'PIPE' } else { 'DATABASE' }) }
    'READ'     { $(if ($x) { 'PIPE' } elseif ($Item.Actor) { [string]$Item.Actor } else { 'CLIENT' }) }
    'ALSO'     { 'CLIENT' }
    default    { throw "ConvertTo-TraceChart: section '$Section' has no lane rule -- a grammar that grows must grow the renderer (R19)" }
  }
  if ($Lanes -cnotcontains $lane) { throw "ConvertTo-TraceChart: step [$('{0:00}' -f $Item.Number)] belongs in lane $lane, which the TIERS header ($($Lanes -join ' -> ')) does not name (R19)" }
  $lane
}

# What a step text names as its callee / target: `CALLS X`, `... VIA X`, `FIRES d.E -> X` ('' when none)
function Get-TraceChartCallee([string] $Text) {
  if ($Text -cmatch '^CALLS (\S+)') { return $Matches[1] }
  ''
}
function Get-TraceChartTarget([string] $Text) {
  if ($Text -cmatch '^CALLS (\S+)') { return $Matches[1] }
  if ($Text -cmatch ' VIA (\S+)') { return $Matches[1] }
  if ($Text -cmatch '^FIRES \S+ -> (\S+)') { return $Matches[1] }
  ''
}

# The traced card an ALSO row converges on: the card whose routine IS the row's callee / target, by exact text
# (or `<Class>.<name>` for a bare name) -- one card, or none ($null: the row says so instead of an edge)
function Get-TraceChartAlsoTarget([string] $Text, $Nodes) {
  $tg = Get-TraceChartTarget $Text
  if (-not $tg) { return $null }
  $hit = @($Nodes.Values | Where-Object { $_.Kind -eq 'card' -and ($_.Title -ceq $tg -or $_.Title.EndsWith(".$tg", [StringComparison]::Ordinal)) })
  $(if ($hit.Count -eq 1) { $hit[0] } else { $null })
}

# The label words of a crossing edge, from its WITH facet: the whole alternative set when the facet is one
# (`rspError or rspOK` -- never just its first word, which would name the failure code on the success path), the
# command when a payload follows it (`cmdDelta 'TABLE=...`), else nothing (the step number stands alone)
function Get-TraceChartWithLabel([string] $With) {
  if ($With -cmatch '^[A-Za-z_]\w*(?: or [A-Za-z_]\w*)*$') { return $With }
  if ($With -cmatch '^([A-Za-z_]\w*) [''"(]') { return $Matches[1] }
  ''
}

# One Form A line of an item or child, for a tooltip (the text's own words, never re-phrased)
function Format-TraceChartTip($Item, [string] $Nums) {
  $note = Format-TraceNote $Item.Routine $Item.Note $Item.Ask
  $head = $(switch ($Item.Kind) { 'crosses' { "CROSSES $($Item.Text)" } 'stops' { "STOPS $($Item.Text)" } default { $Item.Text + $(if ($Item.Grade) { " [$($Item.Grade)]" } else { '' }) } })
  "$Nums " + $(if ($Item.Actor) { "$($Item.Actor) " } else { '' }) + $head + " @$($Item.Anchor)" + $(if ($note) { " -- $note" } else { '' })
}

# HREF / TITLE attributes of an anchored cell. A leaf the indexes name once links; any other stays unlinked
# (no dead link, no guessed path -- the Manifest counts it).
function Get-TraceChartLink([string] $Anchor, [hashtable] $AnchorPaths, [string] $Tip, $State) {
  if (-not $Anchor) { return '' }
  $leaf = $Anchor -replace ':\d+$', ''
  $line = [int]($Anchor -replace '^.*:', '')
  $full = $(if ($AnchorPaths -and $line -gt 0) { [string]$AnchorPaths[$leaf] } else { '' })
  # spec 5: no dead link and no guessed path -- the row says why it has none (the leaf is held at zero or several paths)
  if (-not $full) { $State.Unlinked++; return " TITLE=`"$(ConvertTo-XmlText "ambiguous file name -- the indexes hold $leaf at zero or several paths; see trace.dlgraph")`"" }
  " HREF=`"$(New-RowHref $full $line)`" TITLE=`"$(ConvertTo-XmlText $Tip)`""
}

<#
  ConvertTo-TraceChart -- the chart of a numbered trace.

  $Trace: a model whose items carry their numbers (Read-FormA's result, or the
  model Write-FormA has numbered). $AnchorPaths: leaf -> the one full path the
  indexes hold (rows on any other leaf stay unlinked). $Caps: Also / Rows /
  Nodes, each optional (defaults above).

  Returns Dot (the text for Invoke-DotLayout) and Manifest: Steps (number ->
  'drawn:<node>:<port>' | 'disclosed:<legend row>'), Conds and Facets (the same,
  keyed '<step>|<keyword or head>|<anchor or text>'; a REGENERATE facet goes
  'tooltip:<node>:<port>'), Collapses (the Legend rows that hid numbers), Nodes,
  Lanes ('client/pipe/server/database' card counts), Merged (the multi-number
  rows), Unlinked, Shortened, Ladder.
#>
function ConvertTo-TraceChart($Trace, [hashtable] $AnchorPaths = @{}, [hashtable] $Caps = @{}) {
  $cap = @{}; foreach ($k in $script:ChartCapDefaults.Keys) { $cap[$k] = $(if ($Caps -and $Caps.ContainsKey($k)) { [int]$Caps[$k] } else { $script:ChartCapDefaults[$k] }) }
  $lanes = @(([string]$Trace.Tiers -split '\s*->\s*') | Where-Object { $_ } | ForEach-Object { $_.Trim().ToUpperInvariant() })
  if (-not $lanes.Count) { throw 'ConvertTo-TraceChart: the trace has no TIERS header' }
  foreach ($l in $lanes) { if (-not $script:ChartLaneInk.ContainsKey($l)) { throw "ConvertTo-TraceChart: TIERS names '$l', which has no lane style (R19)" } }

  $nodes = [ordered]@{}
  $edges = [ordered]@{}
  $state = [pscustomobject]@{ Unlinked = 0; Shortened = 0 }
  $legend = New-Object System.Collections.ArrayList     # disclosure rows (plain text)
  $manifest = [pscustomobject]@{ Steps = @{}; Conds = @{}; Facets = @{}; Collapses = (New-Object System.Collections.ArrayList); Nodes = 0; Lanes = ''
                                 Merged = ''; Unlinked = 0; Shortened = 0; Ladder = '' }
  $newNode = {
    param($Key, $Kind, $Lane, $Title)
    $n = [pscustomobject]@{ Key = $Key; Id = "n$($nodes.Count + 1)"; Kind = $Kind; Lane = $Lane; Title = $Title; Rows = (New-Object System.Collections.ArrayList); Fold = $null; FoldLegend = $null }
    $nodes[$Key] = $n
    $n
  }
  $addEdge = {
    param($From, $To, [string] $Kind, [int] $Num, [string] $Extra)
    if (-not $From -or -not $To -or [object]::ReferenceEquals($From, $To)) { return }
    $k = "$($From.Id)>$($To.Id)>$Kind"
    if (-not $edges.Contains($k)) { $edges[$k] = [pscustomobject]@{ From = $From; To = $To; Kind = $Kind; Nums = (New-Object System.Collections.ArrayList); Extras = (New-Object System.Collections.ArrayList) } }
    [void]$edges[$k].Nums.Add($Num)
    if ($Extra -and -not $edges[$k].Extras.Contains($Extra)) { [void]$edges[$k].Extras.Add($Extra) }
  }

  # ---- 1. every step to its node and row, every edge -----------------------------------------------
  $prev = $null; $anchorNode = $null; $total = 0
  foreach ($sec in $Trace.Sections) {
    if ($script:ChartSections -cnotcontains $sec.Name) { throw "ConvertTo-TraceChart: unknown section '$($sec.Name)' -- a grammar that grows must grow the renderer (R19)" }
    # a direction starts at the anchor, not at the last step of the one before it
    if ($sec.Name -cin 'WRITE', 'READ' -and $anchorNode) { $prev = $anchorNode }
    foreach ($i in $sec.Items) {
      $total++
      if ([int]$i.Number -le 0) { throw "ConvertTo-TraceChart: an item has no step number -- render Read-FormA's model, or the model after Write-FormA" }
      $lane = Get-TraceChartLane $sec.Name $i $lanes
      $callee = Get-TraceChartCallee $i.Text
      $fires = $i.Text -cmatch '^FIRES '
      if ($sec.Name -ceq 'ALSO') { $key = 'also'; $kind = 'also'; $title = 'ALSO -- other routes to the anchor' }
      elseif ($sec.Name -ceq 'DERIVED') { $key = 'derived'; $kind = 'derived'; $title = 'DERIVED -- the fields the calculation reads' }
      elseif ($i.Kind -eq 'stops') { $key = "stops|$($i.Number)"; $kind = 'stops'; $title = 'STOPS' }
      elseif ($i.Kind -eq 'crosses') { $key = "x|$($i.Anchor)"; $kind = 'crossing'; $title = "process boundary @$($i.Anchor)" }
      elseif ($lane -eq 'DATABASE' -and (Test-ChartSqlAnchor $i.Anchor)) {
        $subj = $(if ($i.Text -cmatch '^\S+ (\S+)') { $Matches[1] } else { $i.Text })
        $key = "col|$($i.Anchor)|$subj"; $kind = 'column'; $title = $subj
      }
      elseif ($sec.Name -ceq 'ANCHOR') { $key = 'anchor'; $kind = 'anchor'; $title = "ANCHOR -- $($Trace.From)" }
      elseif ($fires) { $key = "ev|$($i.Number)"; $kind = 'event'; $title = 'event' }
      elseif ($callee) { $key = "card|$lane|$callee"; $kind = 'card'; $title = $callee }
      elseif ($i.Routine) { $key = "card|$lane|$($i.Routine)"; $kind = 'card'; $title = $i.Routine }
      elseif ($prev -and $prev.Kind -eq 'card' -and $prev.Lane -eq $lane) { $key = $prev.Key; $kind = 'card'; $title = $prev.Title }
      else { $key = "card|$lane|#$($i.Number)"; $kind = 'card'; $title = '(no routine named)' }
      $isNew = -not $nodes.Contains($key)
      $node = $(if ($isNew) { & $newNode $key $kind $lane $title } else { $nodes[$key] })
      if ($kind -eq 'anchor') { $anchorNode = $node }

      # the row: identical steps in one node are ONE row carrying every number (owner answer 5)
      $sig = "$($i.Kind)|$($i.Text)|$($i.Grade)|$($i.Anchor)|" + ((@($i.Children | ForEach-Object {
               if ($_.Kind -eq 'cond') { "c:$($_.Keyword)|$($_.Condition)|$($_.Anchor)|$($_.Note)" } else { "f:$($_.Head)|$($_.Text)|$($_.Anchor)|$($_.Note)" } })) -join '||')
      $row = @($node.Rows | Where-Object { $_.Sig -ceq $sig })
      if ($row.Count) { [void]$row[0].Nums.Add([int]$i.Number) }
      else {
        $fail = @($i.Children | Where-Object { $_.Kind -eq 'cond' -and $_.Note -match '^else .* @[A-Za-z0-9_$.\-]+:\d+' })
        $prot = $i.Kind -in 'crosses', 'stops' -or $kind -in 'column', 'crossing', 'stops' -or @($i.Children | Where-Object { $_.Kind -eq 'cond' }).Count -gt 0
        $r = [pscustomobject]@{ Sig = $sig; Item = $i; Nums = (New-Object System.Collections.ArrayList); Protected = [bool]$prot; Folded = $false; Fail = $fail; Port = ''; CondPorts = @{} }
        [void]$r.Nums.Add([int]$i.Number)
        [void]$node.Rows.Add($r)
      }

      # the edge into this node (3.3): a CALLS from the card its note names; else from the step before it --
      # when the node opens here, after a crossing or a STOPS, or onto a column / crossing hub
      if ($kind -ne 'also') {
        $src = $null; $ek = ''
        $own = $(if ($i.Routine) { @($nodes.Values | Where-Object { $_.Kind -eq 'card' -and $_.Title -ceq $i.Routine }) } else { @() })
        $ownLane = @($own | Where-Object { $_.Lane -eq $lane })
        $ownCard = $(if ($ownLane.Count) { $ownLane[0] } elseif ($own.Count) { $own[0] } else { $null })
        if ($fires) { $src = $(if ($anchorNode) { $anchorNode } else { $prev }); $ek = 'event' }
        elseif ($callee -and $ownCard -and -not [object]::ReferenceEquals($ownCard, $node)) { $src = $ownCard; $ek = 'call' }
        elseif ($isNew -and $ownCard -and $kind -in 'stops', 'event') { $src = $ownCard; $ek = 'flow' }
        elseif ($isNew -or $callee -or $kind -in 'column', 'crossing' -or ($prev -and $prev.Kind -in 'crossing', 'stops')) { $src = $prev; $ek = $(if ($callee) { 'call' } else { 'flow' }) }
        if ($src) {
          if ($src.Kind -eq 'crossing' -or $kind -eq 'crossing') { $ek = 'crossing' }
          elseif ($src.Kind -eq 'event') { $ek = 'event' }
          # the label's words: a crossing edge names what crosses (Get-TraceChartWithLabel); a call edge the line it
          # is called from (spec 3.3, the note's `from :<line>`)
          $with = @($i.Children | Where-Object { $_.Kind -eq 'facet' -and $_.Head -ceq 'WITH' } | ForEach-Object { Get-TraceChartWithLabel $_.Text })
          $extra = $(if ($kind -eq 'crossing' -and $with.Count) { $with[0] } elseif ($ek -eq 'call' -and $i.Note -cmatch '^from (:\d+)') { "from $($Matches[1])" } else { '' })
          & $addEdge $src $node $ek ([int]$i.Number) $extra
        }
      }
      if ($kind -ne 'also') { $prev = $node }
    }
  }
  if ($total -eq 0) { throw 'ConvertTo-TraceChart: the trace has no steps -- a one-step trace is a one-node chart, a zero-step one is not a trace' }

  # ---- 2. the size rules (4.1), in order; every fold writes a Legend row and a Manifest entry ----------
  # one disclosure per node: a later fold of the same node (the ladder) replaces the earlier one (the row cap)
  # owner 2026-10-06: a fold of k rows draws 1 disclosure row on the card and 1 in the Legend -- it saves k - 2 rows, so
  # a fold of fewer than 3 rows is not made (a 2-row card stays whole). Returns whether the fold was made.
  $fold = {
    param($Node, $Rows, [string] $Noun)
    if (@($Rows).Count -lt 3) { return $false }
    if ($Node.FoldLegend) { [void]$legend.Remove($Node.FoldLegend); [void]$manifest.Collapses.Remove($Node.FoldLegend) }
    $nums = @($Rows | ForEach-Object { $_.Nums } | ForEach-Object { [int]$_ })
    foreach ($r in $Rows) { $r.Folded = $true }
    $txt = "$(Get-DisclosureText $Rows.Count 0 $Noun) -- $(Format-ChartNumbers $nums), full text in trace.dlgraph"
    $lg = "$(Get-DisclosureText $Rows.Count 0 $Noun) in $(if ($Node.Kind -eq 'also') { 'ALSO' } else { $Node.Title }) -- $(Format-ChartNumbers $nums), full text in trace.dlgraph"
    $Node.Fold = $txt; $Node.FoldLegend = $lg
    [void]$legend.Add($lg); [void]$manifest.Collapses.Add($lg)
    foreach ($r in $Rows) {
      foreach ($n in $r.Nums) { $manifest.Steps[[int]$n] = "disclosed:$lg" }
      foreach ($ch in $r.Item.Children) {
        $ck = $(if ($ch.Kind -eq 'cond') { "$($r.Nums[0])|$($ch.Keyword)|$($ch.Anchor)" } else { "$($r.Nums[0])|$($ch.Head)|$(if ($ch.Anchor) { $ch.Anchor } else { $ch.Text })" })
        if ($ch.Kind -eq 'cond') { $manifest.Conds[$ck] = "disclosed:$lg" } else { $manifest.Facets[$ck] = "disclosed:$lg" }
      }
    }
    $true
  }
  # 2a. ALSO: every row up to the cap (owner answer 4: only an unusually long list folds)
  if ($nodes.Contains('also') -and $nodes['also'].Rows.Count -gt $cap.Also) {
    $ar = @($nodes['also'].Rows)
    [void](& $fold $nodes['also'] @($ar[$cap.Also..($ar.Count - 1)]) 'routes')
  }
  # 2b. a card's plain rows past the row cap; a protected row never folds. DERIVED is capped like the component cards
  # it is derived from (owner 2026-10-06; it was exempt until then -- A-R5-CALC, A-R5-DERIVEDCAP)
  foreach ($n in @($nodes.Values | Where-Object { $_.Kind -in 'card', 'anchor', 'derived' })) {
    if ($n.Rows.Count -le $cap.Rows) { continue }
    $room = [Math]::Max(0, $cap.Rows - @($n.Rows | Where-Object { $_.Protected }).Count)
    $plain = @($n.Rows | Where-Object { -not $_.Protected })
    if ($plain.Count -gt $room) { [void](& $fold $n @($plain[$room..($plain.Count - 1)]) 'steps') }
  }
  # 2c. the ladder: above the node cap, ALSO folds whole, then every card with no protected row
  $laneNodes = @($nodes.Values)
  $ladder = @()
  if ($laneNodes.Count -gt $cap.Nodes) {
    if ($nodes.Contains('also') -and @($nodes['also'].Rows | Where-Object { -not $_.Folded }).Count) {
      if (& $fold $nodes['also'] @($nodes['also'].Rows) 'routes') { $ladder += 'also' }
    }
    foreach ($n in @($nodes.Values | Where-Object { $_.Kind -in 'card', 'derived' })) {
      if (@($n.Rows | Where-Object { $_.Protected }).Count) { continue }
      if (& $fold $n @($n.Rows) 'steps') { $ladder += 'cards' }
    }
    # folding rows does not remove nodes, so the chart is still above the cap: drawn anyway, and said
    [void]$legend.Add("$($laneNodes.Count) nodes, above the $($cap.Nodes)-node readability cap: drawn anyway, nothing dropped")
  }
  # 2d. owner 2026-10-06: above $cap.Folds folds the Legend holds ONE summary row instead of one row per fold -- the
  # folded steps' ranges when the row stays within $script:ChartSummaryWidth, else their count; each card keeps its own
  # disclosure row, and the Manifest's disclosed entries name the summary row (A-R5-SUMMARY, A-R5-SUMCOUNT)
  $folded = @($nodes.Values | Where-Object { $_.FoldLegend })
  if ($folded.Count -gt $cap.Folds) {
    $fr = @($folded | ForEach-Object { @($_.Rows | Where-Object { $_.Folded }) })
    $fn = @($fr | ForEach-Object { $_.Nums } | ForEach-Object { [int]$_ } | Sort-Object -Unique)
    $head = "$($folded.Count) cards folded ($($fr.Count) rows not shown)"
    $tail = 'the full trace is in the text answer'
    $sum = "$head -- $(Format-ChartNumbers $fn) -- $tail"
    if ($sum.Length -gt $script:ChartSummaryWidth) { $sum = "$head -- $($fn.Count) steps -- $tail" }
    foreach ($n in $folded) { [void]$legend.Remove($n.FoldLegend); [void]$manifest.Collapses.Remove($n.FoldLegend) }
    foreach ($tbl in @($manifest.Steps, $manifest.Conds, $manifest.Facets)) {
      foreach ($k in @($tbl.Keys)) { if ([string]$tbl[$k] -like 'disclosed:*') { $tbl[$k] = "disclosed:$sum" } }
    }
    $legend.Insert(0, $sum); [void]$manifest.Collapses.Add($sum)
  }
  $manifest.Ladder = (@($ladder | Select-Object -Unique) -join ',')

  # ---- 3. the dot ------------------------------------------------------------------------------------
  $sb = New-Object System.Text.StringBuilder
  $L = { param($s) [void]$sb.Append($s).Append("`r`n") }
  & $L 'digraph roundtrip {'
  & $L '  graph [rankdir=LR, fontname="Segoe UI", bgcolor="#FFFFFF", nodesep=0.3, ranksep=0.55, newrank=true, pad=0.3];'
  & $L '  node [shape=plain, fontname="Segoe UI", fontsize=12];'
  & $L '  edge [fontname="Segoe UI", fontsize=10, color="#5B6674", fontcolor="#5B6674", arrowsize=0.7];'

  $failNodes = [ordered]@{}
  $cellRows = {
    # the TRs of one step row: the step, its guard rows, its facet rows; returns nothing, appends to $tb
    param($tb, $Node, $R)
    $i = $R.Item
    $numTxt = (@($R.Nums | Sort-Object | ForEach-Object { '[{0:00}]' -f [int]$_ }) -join '/')
    $body = $(switch ($i.Kind) { 'crosses' { "CROSSES $($i.Text)" } 'stops' { "STOPS $($i.Text)" } default { $i.Text } })
    $grade = $(if ($i.Grade) { " [$($i.Grade)]" } else { '' })
    $headTxt = "$numTxt $body$grade"
    # past 5 lines the BODY is shortened (at a break, ' ...' marking the cut) and the grade KEPT: cutting a trailing
    # [inferred] / [by name] off would read as a certain step
    if ((Get-ChartBreaks $headTxt $script:ChartWidth).Count + 1 -gt $script:ChartMaxLines) {
      $lead = "$numTxt $body"
      $cuts = @((Get-ChartBreaks $lead $script:ChartWidth) | Sort-Object -Descending)
      foreach ($cutAt in $cuts) {
        $headTxt = $lead.Substring(0, $cutAt) + ' ...' + $grade
        if ((Get-ChartBreaks $headTxt $script:ChartWidth).Count + 1 -le $script:ChartMaxLines) { break }
      }
      $state.Shortened++
    }
    $tips = @(foreach ($n in @($R.Nums | Sort-Object)) { Format-TraceChartTip $i ('[{0:00}]' -f [int]$n) })
    $regen = @($i.Children | Where-Object { $_.Kind -eq 'facet' -and $_.Head -ceq 'REGENERATE' } | ForEach-Object { "REGENERATE $($_.Text)" })
    $tip = (@($tips) + @($regen)) -join ' | '
    $segs = @(, @("$numTxt ", $script:ChartInk.Dim, 11, $false))
    $rest = $headTxt.Substring($numTxt.Length + 1)
    $segs += , @($rest, $script:ChartInk.Text, 0, ($i.Kind -eq 'stops'))
    $segs += , @(" @$($i.Anchor)", $script:ChartInk.Dim, 10, $false)
    $p = "p$($Node.Rows.IndexOf($R) + 1)"
    $R.Port = $p
    foreach ($n in $R.Nums) { $manifest.Steps[[int]$n] = "drawn:$($Node.Id):$p" }
    [void]$tb.Append("<TR><TD PORT=`"$p`" ALIGN=`"LEFT`" BALIGN=`"LEFT`"$(Get-TraceChartLink $i.Anchor $AnchorPaths $tip $state)>$(ConvertTo-ChartCellHtml $segs)</TD></TR>")
    if ($i.Kind -eq 'stops' -and $i.Ask) {
      [void]$tb.Append("<TR><TD ALIGN=`"LEFT`"><FONT COLOR=`"$($script:ChartInk.Fail)`" POINT-SIZE=`"11`">ask $(ConvertTo-XmlText $i.Ask)</FONT></TD></TR>")
    }
    $k = 0
    foreach ($ch in $i.Children) {
      $k++
      if ($ch.Kind -eq 'cond') {
        $cp = "$p" + "c$k"
        $segs = @(, @($ch.Keyword, $script:ChartInk.Guard, 11, $true))
        $segs += , @(" $($ch.Condition)", $script:ChartInk.Text, 11, $false)
        $segs += , @(" @$($ch.Anchor)", $script:ChartInk.Dim, 10, $false)
        if ($ch.Note -match '^else ') { $segs += , @(" -- $($ch.Note)", $script:ChartInk.Fail, 10, $false) }
        $cn = Format-TraceNote $ch.Routine $ch.Note $ch.Ask
        $ctip = "$($ch.Keyword) $($ch.Condition) @$($ch.Anchor)" + $(if ($cn) { " -- $cn" } else { '' })
        [void]$tb.Append("<TR><TD PORT=`"$cp`" ALIGN=`"LEFT`" BALIGN=`"LEFT`"$(Get-TraceChartLink $ch.Anchor $AnchorPaths $ctip $state)>$(ConvertTo-ChartCellHtml $segs)</TD></TR>")
        foreach ($n in $R.Nums) { $manifest.Conds["$n|$($ch.Keyword)|$($ch.Anchor)"] = "drawn:$($Node.Id):$cp" }
        if ($ch.Note -match '^else (.*?) @([A-Za-z0-9_$.\-]+:\d+)') {
          $ft = $Matches[1]; $fa = $Matches[2]
          $fk = "fail|$fa|$ft"
          if (-not $failNodes.Contains($fk)) { $failNodes[$fk] = [pscustomobject]@{ Id = "f$($failNodes.Count + 1)"; Text = "else $ft"; Anchor = $fa; Lane = $Node.Lane; Edges = (New-Object System.Collections.ArrayList) } }
          [void]$failNodes[$fk].Edges.Add("$($Node.Id):$cp")
        }
      } elseif ($ch.Head -ceq 'REGENERATE') {
        foreach ($n in $R.Nums) { $manifest.Facets["$n|REGENERATE|$($ch.Text)"] = "tooltip:$($Node.Id):$p" }
      } else {
        $segs = @(, @($ch.Head, $script:ChartInk.Facet, 11, $true))
        $segs += , @(" $($ch.Text)", $script:ChartInk.Text, 11, $false)
        if ($ch.Anchor) { $segs += , @(" @$($ch.Anchor)", $script:ChartInk.Dim, 10, $false) }
        $ftip = "$($ch.Head) $($ch.Text)" + $(if ($ch.Anchor) { " @$($ch.Anchor)" } else { '' }) + $(if ($ch.Note) { " -- $($ch.Note)" } else { '' })
        [void]$tb.Append("<TR><TD ALIGN=`"LEFT`" BALIGN=`"LEFT`"$(Get-TraceChartLink $ch.Anchor $AnchorPaths $ftip $state)>$(ConvertTo-ChartCellHtml $segs)</TD></TR>")
        foreach ($n in $R.Nums) { $manifest.Facets["$n|$($ch.Head)|$(if ($ch.Anchor) { $ch.Anchor } else { $ch.Text })"] = "drawn:$($Node.Id):$p" }
      }
    }
  }

  $nodeHtml = {
    param($Node)
    $ink = $script:ChartLaneInk[$Node.Lane]
    $tb = New-Object System.Text.StringBuilder
    $bg = $(switch ($Node.Kind) { 'stops' { '#FFF1F1' } 'also' { '#FAFAFB' } default { '#FFFFFF' } })
    $border = $(switch ($Node.Kind) { 'stops' { $script:ChartInk.Fail } 'also' { $script:ChartInk.Also } default { $ink[0] } })
    $hdr = $(switch ($Node.Kind) { 'stops' { $script:ChartInk.Fail } 'also' { $script:ChartInk.Also } 'event' { $ink[2] } default { $ink[2] } })
    [void]$tb.Append("<TABLE BORDER=`"1`" COLOR=`"$border`" CELLBORDER=`"0`" CELLSPACING=`"1`" CELLPADDING=`"3`" BGCOLOR=`"$bg`">")
    if ($Node.Kind -notin 'stops', 'event') {
      [void]$tb.Append("<TR><TD ALIGN=`"LEFT`" BALIGN=`"LEFT`" BGCOLOR=`"$hdr`">$(ConvertTo-ChartCellHtml @(, @($Node.Title, '#FFFFFF', 12, $true)))</TD></TR>")
    }
    foreach ($r in $Node.Rows) {
      if ($r.Folded) { continue }
      & $cellRows $tb $Node $r
      if ($Node.Kind -eq 'also' -and -not (Get-TraceChartAlsoTarget $r.Item.Text $nodes)) { Add-DisclosureRow $tb 'converges outside the drawn path' $script:ChartInk.Also 10 }
    }
    if ($Node.Fold) { Add-DisclosureRow $tb $Node.Fold $script:ChartInk.Dim 11 }
    [void]$tb.Append('</TABLE>')
    $tb.ToString()
  }


  # lanes, in TIERS order; each lane a rounded cluster; ALSO a dashed sub-cluster of the client lane
  $nodeLines = @{}
  foreach ($n in $nodes.Values) {
    $html = & $nodeHtml $n
    $attr = $(switch ($n.Kind) {
      'column'   { "shape=cylinder, style=filled, fillcolor=`"$($script:ChartLaneInk[$n.Lane][1])`", color=`"$($script:ChartLaneInk[$n.Lane][0])`", margin=0.12" }
      'stops'    { "shape=note, style=`"filled,dashed`", fillcolor=`"#FFF1F1`", color=`"$($script:ChartInk.Fail)`", penwidth=1.5, margin=0.05" }
      'event'    { "shape=box, style=`"rounded,dashed`", color=`"$($script:ChartLaneInk[$n.Lane][0])`", margin=0.05" }
      default    { 'shape=plain' }
    })
    $nodeLines[$n.Key] = "    $($n.Id) [$attr, label=<$html>];"
  }
  # one dotted also-edge per drawn ALSO row, from its own port to the card it converges on
  $alsoEdges = New-Object System.Collections.ArrayList
  if ($nodes.Contains('also')) {
    $an = $nodes['also']
    foreach ($r in @($an.Rows | Where-Object { -not $_.Folded })) {
      $hit = Get-TraceChartAlsoTarget $r.Item.Text $nodes
      if ($hit) { [void]$alsoEdges.Add("  $($an.Id):$($r.Port) -> $($hit.Id) [style=dotted, color=`"$($script:ChartInk.Also)`", constraint=false, arrowhead=open];") }
    }
  }

  # the header (TITLE, FROM, INDEX .. AS OF, TIERS; REGENERATE in its tooltip) and the Legend (the disclosure)
  $hb = New-Object System.Text.StringBuilder
  [void]$hb.Append('<TABLE BORDER="1" COLOR="#5B6674" CELLBORDER="0" CELLSPACING="1" CELLPADDING="4" BGCOLOR="#FFFFFF">')
  [void]$hb.Append("<TR><TD ALIGN=`"LEFT`" BALIGN=`"LEFT`" BGCOLOR=`"#1F2933`">$(ConvertTo-ChartCellHtml @(, @("TRACE $($Trace.Name)", '#FFFFFF', 13, $true)))</TD></TR>")
  foreach ($h in @($Trace.Title, "FROM $($Trace.From)", "INDEX $($Trace.Index) AS OF $($Trace.AsOf)", "TIERS $($Trace.Tiers)")) {
    [void]$hb.Append("<TR><TD ALIGN=`"LEFT`" BALIGN=`"LEFT`">$(ConvertTo-ChartCellHtml @(, @($h, $script:ChartInk.Text, 11, $false)))</TD></TR>")
  }
  [void]$hb.Append('</TABLE>')
  $c = Get-TraceCounts $Trace
  $lb = New-Object System.Text.StringBuilder
  [void]$lb.Append('<TABLE BORDER="1" COLOR="#8A94A6" CELLBORDER="0" CELLSPACING="1" CELLPADDING="3" BGCOLOR="#FFFFFF">')
  [void]$lb.Append("<TR><TD ALIGN=`"LEFT`" BGCOLOR=`"#5B6674`"><FONT COLOR=`"#FFFFFF`" POINT-SIZE=`"12`"><B>LEGEND -- what the picture holds and what it does not</B></FONT></TD></TR>")
  Add-DisclosureRow $lb (Format-TraceEndLine $c) $script:ChartInk.Text 11
  Add-DisclosureRow $lb 'full text, every note and ask in trace.dlgraph' $script:ChartInk.Dim 11
  foreach ($g in $legend) { Add-DisclosureRow $lb $g $script:ChartInk.Dim 11 }
  foreach ($sec in $Trace.Sections) { if ($sec.Note) { Add-DisclosureRow $lb "$($sec.Name) -- $($sec.Note)" $script:ChartInk.Dim 11 } }
  if ($state.Shortened) { Add-DisclosureRow $lb "$($state.Shortened) label(s) shortened; the full text is in the tooltip and in trace.dlgraph" $script:ChartInk.Dim 11 }
  Add-DisclosureRow $lb 'amber WHEN / UNLESS: the guard on the step above it, verbatim; red dashed: the failure branch it names' $script:ChartInk.Also 10
  Add-DisclosureRow $lb '[aa]/[bb]: one row both directions run; bold edges cross the process boundary' $script:ChartInk.Also 10
  [void]$lb.Append('</TABLE>')

  # nodes are emitted after their rows were built (the cell builder counts unlinked rows and records ports).
  # The header's tooltip is a dot escString: a backslash is doubled, or dot eats it (measured: the REGENERATE
  # paths lost every '\'). It is the one <a> in the SVG without an href (A-R5-LINKS counts it).
  & $L "  hdr [label=<$($hb.ToString())>, tooltip=`"$((ConvertTo-XmlText "REGENERATE $($Trace.Regenerate)").Replace('\', '\\'))`"];"
  foreach ($lane in $lanes) {
    $inLane = @($nodes.Values | Where-Object { $_.Lane -eq $lane })
    $fl = @($failNodes.Values | Where-Object { $_.Lane -eq $lane })
    if (-not $inLane.Count -and -not $fl.Count) { continue }
    $ink = $script:ChartLaneInk[$lane]
    & $L "  subgraph cluster_lane_$($lane.ToLowerInvariant()) {"
    & $L "    label=<<B>$lane</B>>; labeljust=l; fontcolor=`"$($ink[2])`"; style=`"rounded,filled`"; color=`"$($ink[0])`"; fillcolor=`"$($ink[1])`"; penwidth=1.5; margin=12;"
    foreach ($n in @($inLane | Where-Object { $_.Kind -ne 'also' })) { & $L $nodeLines[$n.Key] }
    foreach ($n in @($inLane | Where-Object { $_.Kind -eq 'also' })) {
      & $L '    subgraph cluster_also {'
      & $L "      label=<<B>ALSO</B>>; labeljust=l; fontcolor=`"$($script:ChartInk.Also)`"; style=`"rounded,dashed`"; color=`"$($script:ChartInk.Also)`"; fillcolor=`"#FFFFFF`";"
      & $L "  $($nodeLines[$n.Key])"
      & $L '    }'
    }
    foreach ($f in $fl) {
      $ftip = "$($f.Text) @$($f.Anchor)"
      $fh = "<TABLE BORDER=`"0`" CELLBORDER=`"0`" CELLPADDING=`"2`"><TR><TD ALIGN=`"LEFT`" BALIGN=`"LEFT`"$(Get-TraceChartLink $f.Anchor $AnchorPaths $ftip $state)>$(ConvertTo-ChartCellHtml @(@($f.Text, $script:ChartInk.Fail, 11, $false), @(" @$($f.Anchor)", $script:ChartInk.Dim, 10, $false)))</TD></TR></TABLE>"
      & $L "    $($f.Id) [shape=box, style=`"rounded,dashed`", color=`"$($script:ChartInk.Fail)`", margin=0.05, label=<$fh>];"
    }
    & $L '  }'
  }
  & $L "  legend [label=<$($lb.ToString())>];"

  # edges: a backward edge (to an earlier lane) does not rank -- the lanes stay left to right
  $laneIx = @{}; for ($q = 0; $q -lt $lanes.Count; $q++) { $laneIx[$lanes[$q]] = $q }
  foreach ($e in $edges.Values) {
    $lbl = (@($e.Nums | Sort-Object -Unique | ForEach-Object { '[{0:00}]' -f [int]$_ }) -join '/') + $(if ($e.Extras.Count) { " $($e.Extras -join ', ')" } else { '' })
    $st = $(switch ($e.Kind) {
      'crossing' { "penwidth=2.2, color=`"$($script:ChartLaneInk['PIPE'][0])`", fontcolor=`"$($script:ChartLaneInk['PIPE'][2])`"" }
      'event'    { 'style=dashed' }
      'call'     { '' }
      default    { '' }
    })
    $back = $laneIx[$e.To.Lane] -lt $laneIx[$e.From.Lane]
    $a = @("label=`"$(ConvertTo-XmlText $lbl)`"") + @($(if ($st) { $st })) + @($(if ($back) { 'constraint=false' }))
    & $L "  $($e.From.Id) -> $($e.To.Id) [$($a -join ', ')];"
  }
  foreach ($f in $failNodes.Values) {
    foreach ($src in $f.Edges) { & $L "  $src -> $($f.Id) [style=dashed, color=`"$($script:ChartInk.Fail)`"];" }
  }
  foreach ($a in $alsoEdges) { & $L $a }
  & $L '  hdr -> legend [style=invis];'
  & $L '}'

  $manifest.Nodes = $laneNodes.Count
  $manifest.Lanes = (@('CLIENT', 'PIPE', 'SERVER', 'DATABASE') | ForEach-Object { $ln = $_; @($nodes.Values | Where-Object { $_.Lane -eq $ln }).Count }) -join '/'
  $manifest.Merged = (@($nodes.Values | ForEach-Object { $_.Rows } | Where-Object { $_.Nums.Count -gt 1 -and -not $_.Folded } | ForEach-Object { (@($_.Nums | Sort-Object | ForEach-Object { '[{0:00}]' -f [int]$_ }) -join '/') }) -join ',')
  $manifest.Unlinked = $state.Unlinked
  $manifest.Shortened = $state.Shortened
  $dot = $sb.ToString()
  $bad = [regex]::Match($dot, '[^\x0D\x0A\x20-\x7E]')
  if ($bad.Success) { throw "ConvertTo-TraceChart: the dot is not 7-bit ASCII at offset $($bad.Index)" }
  [pscustomobject]@{ Dot = $dot; Manifest = $manifest }
}
