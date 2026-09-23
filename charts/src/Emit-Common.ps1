<#
  Emit-Common.ps1 -- shared helpers, DOT-SOURCED by the emitters. Functions only,
  no top-level side effects: dot-sourcing this must never write a file, call the
  engine, or print.

  Dot-sourcing puts these functions in the CALLER's scope, so they resolve
  $Engine, $Dot and $DbPath dynamically from the emitter's own param block.
  That is deliberate -- it keeps the call sites short -- but it means an emitter
  MUST declare all three parameters with those exact names.

  Two traps are baked in here rather than left to each emitter:

  1. `--format json` splices a human staleness note INTO the JSON stream, and
     with 2>&1 it lands inside the document and breaks ConvertFrom-Json. Every
     engine call is routed through Get-EngineText, which drops ErrorRecords and
     `drag-lint:` lines before anything tries to parse.

  2. The engine emits BOTH shapes: reverse-calltree returns an OBJECT `{...}`
     and `query find-callers --json` returns a bare ARRAY `[...]`. Trimming to
     the first `{` (as an earlier draft did) silently corrupts the array into an
     object followed by garbage. Get-EngineText brackets on whichever of `{` or
     `[` comes FIRST and pairs it with the matching closer.
#>

# NOTE: deliberately NO Set-StrictMode here. Dot-sourcing runs in the CALLER's
# scope, so setting it would silently change the strictness of every emitter --
# exactly the top-level side effect this file is supposed to be free of.

# ---- text -------------------------------------------------------------------

function ConvertTo-XmlText([string] $s) {
  if ($null -eq $s) { return '' }
  $s.Replace('&', '&amp;').Replace('<', '&lt;').Replace('>', '&gt;').Replace('"', '&quot;')
}

function Get-UnitName([string] $file) {
  if ([string]::IsNullOrWhiteSpace($file)) { return '(unknown)' }
  [IO.Path]::GetFileNameWithoutExtension($file)
}

function Get-ShortName([string] $qname, [string] $unit) {
  if ([string]::IsNullOrWhiteSpace($qname)) { return '' }
  if ($unit -and $qname.StartsWith("$unit.", [StringComparison]::OrdinalIgnoreCase)) {
    return $qname.Substring($unit.Length + 1)
  }
  $qname
}

function New-RowHref([string] $File, [int] $Line) {
  'draglint://open?file=' + [uri]::EscapeDataString($File) + '&amp;line=' + $Line
}

# ---- engine -----------------------------------------------------------------

# Runs the engine and returns ONLY the JSON document, or '' when there is none.
# Records the exit code in $script:LastEngineExit for the caller's message.
function Get-EngineText([string[]] $ArgList) {
  $raw = & $Engine @ArgList 2>&1 |
         Where-Object { $_ -isnot [System.Management.Automation.ErrorRecord] } |
         Where-Object {
           $s = [string]$_
           $s -notmatch '^\(?loaded defaults' -and
           $s -notmatch '^drag-lint:'         -and
           $s -notmatch '^\s+may be stale'    -and
           $s -notmatch '^\s+drag-lint index ' -and
           # The resolver-mismatch note, emitted when the index was resolved by a
           # NEWER build than this engine. It goes to stderr, so the ErrorRecord
           # filter above already catches it -- this line is belt and braces for
           # a host that merges the streams, because when it does reach the
           # document the failure is an opaque ConvertFrom-Json error a long way
           # from its cause.
           $s -notmatch '^\s*resolver:'
         }
  $script:LastEngineExit = $LASTEXITCODE
  $txt = ($raw -join "`n")
  if ([string]::IsNullOrWhiteSpace($txt)) { return '' }

  # bracket on whichever opener comes first -- see header note 2
  $bo = $txt.IndexOf('{')
  $ba = $txt.IndexOf('[')
  if ($bo -lt 0 -and $ba -lt 0) { return '' }
  if ($bo -lt 0) { $open = $ba } elseif ($ba -lt 0) { $open = $bo } else { $open = [Math]::Min($bo, $ba) }
  $close = if ($txt[$open] -eq '[') { $txt.LastIndexOf(']') } else { $txt.LastIndexOf('}') }
  if ($close -le $open) { return '' }
  $txt.Substring($open, $close - $open + 1)
}

function Invoke-EngineJson([string[]] $ArgList) {
  $txt = Get-EngineText $ArgList
  if ([string]::IsNullOrWhiteSpace($txt)) {
    throw "engine returned nothing for $($ArgList -join ' ') (exit $script:LastEngineExit)"
  }
  $txt | ConvertFrom-Json
}

# schema sql/1 returns `columns` (name/type) and `rows` as POSITIONAL ARRAYS --
# zip them so callers can use property names. Hard row cap 200; the caller is
# expected to assert .Truncated where the plan says to.
function Invoke-IndexQuery([string] $sql, [string] $FailOnTruncate) {
  $txt = Get-EngineText @('sql', '--db', $DbPath, '--query', $sql, '--format', 'json')
  if ([string]::IsNullOrWhiteSpace($txt)) { return , @() }
  try { $o = $txt | ConvertFrom-Json } catch { throw "index query returned non-JSON: $txt" }
  if ($o.truncated) {
    # The 200-row cap is SILENT in the row list -- a truncated answer looks like
    # a small one. Callers that would render a short chart as if it were whole
    # pass -FailOnTruncate and get a hard stop instead.
    if ($FailOnTruncate) {
      throw "$FailOnTruncate hit the sql row cap ($($o.row_cap)); the answer would be silently short -- narrow the query"
    }
    Write-Host "  NOTE: result truncated at row_cap $($o.row_cap)"
  }
  $names = @($o.columns | ForEach-Object { $_.name })
  $out = New-Object System.Collections.ArrayList
  foreach ($row in @($o.rows)) {
    $vals = @($row)
    $h = [ordered]@{}
    for ($i = 0; $i -lt $names.Count; $i++) {
      $h[$names[$i]] = $(if ($i -lt $vals.Count) { $vals[$i] } else { $null })
    }
    [void]$out.Add([pscustomobject]$h)
  }
  # CONTRACT: the unary comma keeps a 0- or 1-row result an ARRAY through the
  # pipeline. It also means callers must assign the result DIRECTLY --
  #     $rows = Invoke-IndexQuery $sql          correct
  #     $rows = @(Invoke-IndexQuery $sql)       WRONG: nests it one level deep
  # The wrong form is quiet rather than fatal: Count reads 1, and member access
  # on the single wrapper element enumerates to the right value whenever there
  # is exactly one row, so it only misbehaves once a query returns two.
  , $out.ToArray()
}

function ConvertTo-SqlText([string] $s) { $s.Replace("'", "''") }

# "'a','b','c'" for an IN-list. Callers use this to BOUND a query that would
# otherwise run past the 200-row cap -- Blueprint4.dfm alone has 516 dfm-type
# rows, so an unbounded component query there returns a silently short answer.
function ConvertTo-SqlInList([string[]] $Values) {
  ($Values | ForEach-Object { "'" + (ConvertTo-SqlText $_) + "'" }) -join ','
}

# Callers want the BODY, so prefer impl_start_line over the interface decl line.
function Get-SymbolLocation([string] $Qname) {
  $q = ConvertTo-SqlText $Qname
  $rows = Invoke-IndexQuery @"
SELECT s.id AS id, s.kind AS kind, s.start_line AS start_line,
       s.impl_start_line AS impl_start_line, s.impl_end_line AS impl_end_line,
       f.path AS path
  FROM symbols s JOIN files f ON f.id = s.file_id
 WHERE s.qualified_name = '$q'
"@
  if ($rows.Count -eq 0) { throw "$Qname is not in this index" }
  if ($rows.Count -gt 1) {
    Write-Host "  NOTE: $Qname resolves to $($rows.Count) symbols; using the first (id $($rows[0].id))"
  }
  $r = $rows[0]
  $focus = if ($r.impl_start_line) { [int]$r.impl_start_line } else { [int]$r.start_line }
  [pscustomobject]@{
    Id = [int]$r.id; Kind = [string]$r.kind; Path = [string]$r.path
    DeclLine = [int]$r.start_line
    ImplStart = $(if ($r.impl_start_line) { [int]$r.impl_start_line } else { 0 })
    ImplEnd   = $(if ($r.impl_end_line)   { [int]$r.impl_end_line }   else { 0 })
    FocusLine = $focus
  }
}

# ---- member selection -------------------------------------------------------

# Collapse FORWARD DECLARATIONS onto the real declaration they announce.
#
# A Delphi interface section routinely declares a type twice -- `IDataService =
# interface;` up front, then the body further down -- and the index stores both,
# with the SAME qualified_name. Counting them as separate types makes a chart
# report an ambiguity that does not exist.
#
# The key is (qualified_name, generic_params), NOT qualified_name alone, because
# a generic and a non-generic type can legitimately share a name and this corpus
# has exactly that case: IuMicObject.pas declares `IDataService` and
# `IDataService<I: IMicObject>`, each with its own forward declaration -- FOUR
# rows, TWO real types. Collapsing on the name alone would merge two different
# types; collapsing on the pair does not.
#
# MEASURED 2026-09-23, CLIENT: 857 (qualified_name, generic_params) groups and
# ZERO of them span more than one file. So every group really is one type's
# declarations in one unit, and the widest line span is its body.
function Select-DeclarationRows($Rows) {
  $out = New-Object System.Collections.ArrayList
  foreach ($g in @($Rows | Group-Object { "$([string]$_.qualified_name)|$([string]$_.generic_params)" })) {
    $best = @($g.Group | Sort-Object `
                @{ E = { [int]$_.end_line - [int]$_.start_line }; Descending = $true }, `
                @{ E = { [int]$_.start_line }; Descending = $false })[0]
    [void]$out.Add($best)
  }
  , $out.ToArray()
}

# Resolve a FIELD or PROPERTY selection, REFUSING an ambiguous name rather than
# taking the first match the way Get-SymbolLocation does.
#
# MEASURED 2026-09-23 on BOTH ORM3 indexes, and the two halves disagree sharply:
#
#   form        CLIENT                      SERVER
#   qualified   13,131 names / 0 ambiguous   9,095 names / 0 ambiguous
#   bare         6,849 names / 2,716 (40%)   3,592 names / 2,136 (59%)
#
# So a QUALIFIED field/property name is a safe key -- not one of the 22,226
# measured is ambiguous -- while a BARE one is a coin toss, worst case `ID` at
# 154 distinct symbols. A bare name is therefore accepted only when it happens
# to be unique, and an ambiguous one is refused WITH its candidates.
#
# Refusing is the whole point: this chart is about ONE member, so resolving to
# the wrong one does not mislabel a row, it mislabels every row in the picture.
# `FConnected` resolving uniquely here is luck, not a rule.
# -AllowMissing returns $null instead of throwing when NOTHING matches, while
# still refusing an ambiguous name. The two outcomes are different questions:
# "I cannot tell WHICH one you mean" is always fatal, but "this index does not
# declare it" is a legitimate answer for a type whose DESCENDANTS live here even
# though its declaration does not -- TInterfacedObject has 145 descendants on
# CLIENT and no declaration in it, because it is RTL.
#
# -Hint is the advice appended when the symbol exists but is the WRONG KIND.
# It differs per emitter -- who-calls is the right redirect for a method asked
# of who-writes, and the wrong one for a unit asked of class-surface.
function Resolve-MemberSelection([string] $Qname, [string[]] $Kinds, [switch] $AllowMissing,
                                 [string] $Hint = 'ask who-calls instead') {
  $q = ConvertTo-SqlText $Qname
  $rows = Invoke-IndexQuery @"
SELECT s.id AS id, s.kind AS kind, s.qualified_name AS qualified_name,
       s.name AS name, s.start_line AS start_line, s.end_line AS end_line,
       s.impl_start_line AS impl_start_line, s.impl_end_line AS impl_end_line,
       s.prop_access AS prop_access, s.generic_params AS generic_params,
       f.path AS path
  FROM symbols s JOIN files f ON f.id = s.file_id
 WHERE s.qualified_name = '$q' OR s.name = '$q'
 ORDER BY s.qualified_name
"@
  if ($rows.Count -eq 0) {
    if ($AllowMissing) { return $null }
    throw "$Qname is not in this index"
  }
  # Forward declarations are not alternatives to choose between.
  $rows = Select-DeclarationRows $rows

  # An exact QUALIFIED hit wins outright: `R` as a qualified name and `R` as a
  # bare name are different questions, and the caller asked the precise one.
  $exact = @($rows | Where-Object { [string]$_.qualified_name -eq $Qname })
  $cand  = if ($exact.Count) { $exact } else { $rows }

  # Narrow a BARE name to the kinds actually asked for before judging ambiguity.
  # `ID` matches 170 symbols on CLIENT but only 4 are fields -- refusing on the
  # 150 properties and 16 params/locals would reject a selection that is not
  # ambiguous among the things this chart can even draw. Only narrow when it
  # leaves something: otherwise fall through to the kind error below, which
  # says what the symbol IS rather than that it is ambiguous.
  if (-not $exact.Count -and $Kinds) {
    $ofKind = @($cand | Where-Object { $Kinds -contains [string]$_.kind })
    if ($ofKind.Count) { $cand = $ofKind }
  }

  if ($cand.Count -gt 1) {
    # Name what actually TELLS THEM APART. Advising "qualify it" is useless when
    # the candidates already share a qualified name, which happens for a generic
    # and a non-generic type of the same name (IuMicObject.IDataService and
    # IDataService<I: IMicObject>) -- there the generic parameters are the
    # difference, and for everything else it is the unit.
    $sameQ = @($cand | Group-Object { [string]$_.qualified_name }).Count -eq 1
    $head = ($cand | Select-Object -First 6 | ForEach-Object {
      $g = [string]$_.generic_params
      "$([string]$_.qualified_name)$(if ($g) { "<$g>" }) at $([IO.Path]::GetFileName([string]$_.path)):$($_.start_line)"
    }) -join '; '
    $tail = if ($cand.Count -gt 6) { "; +$($cand.Count - 6) more" } else { '' }
    $advice = if ($sameQ) {
      'They share a qualified name, so qualifying will not separate them -- they differ by generic parameters.'
    } else {
      'Pass a fully qualified name.'
    }
    throw "$Qname is ambiguous -- $($cand.Count) symbols share that name: $head$tail. $advice"
  }

  $r = $cand[0]
  if ($Kinds -and ($Kinds -notcontains [string]$r.kind)) {
    throw "$($r.qualified_name) is a $($r.kind), not a $($Kinds -join ' or ') -- $Hint"
  }
  $focus = if ($r.impl_start_line) { [int]$r.impl_start_line } else { [int]$r.start_line }
  [pscustomobject]@{
    Id = [int]$r.id; Kind = [string]$r.kind; Path = [string]$r.path
    Qname = [string]$r.qualified_name; Name = [string]$r.name
    PropAccess = [string]$r.prop_access
    DeclLine = [int]$r.start_line
    ImplStart = $(if ($r.impl_start_line) { [int]$r.impl_start_line } else { 0 })
    ImplEnd   = $(if ($r.impl_end_line)   { [int]$r.impl_end_line }   else { 0 })
    FocusLine = $focus
  }
}

# ---- ranking and disclosure -------------------------------------------------

# Maps a `refs` row to its enclosing routine, as the SQL fragments to splice in.
# One place, so the emitters that need a SITE anchor cannot drift apart on it.
#
# WHY A COLUMN AND NOT THE CONTAINMENT SUBQUERY THE PLAN SPECIFIED
# ----------------------------------------------------------------
# PLAN-next-five-questions.md finding 2 hand-rolls this as a correlated subquery
# over symbols.impl_start_line/impl_end_line with `ORDER BY impl_start_line DESC
# LIMIT 1` to make the INNERMOST routine win. That subquery is correct -- and
# unnecessary. `refs.enclosing_symbol_id` already holds the answer.
#
# MEASURED 2026-09-23, every member-access row on both indexes, both ways:
#
#   index    rows     stored NULL  subquery NULL  DISAGREE
#   CLIENT   9,311    0            0              0
#   SERVER  14,836    0            0              0
#
# Zero disagreements, so the stored column IS the innermost-enclosing answer,
# computed by the engine. Using it means the chart cannot drift from the
# engine's own notion of "enclosing" the way a reimplementation silently can --
# and it is a join instead of a per-row subquery.
#
# The plan's totals were right; only its method was doing work already done.
# Same lesson as its finding 1 in a new place: ask what the index already
# stores before writing SQL to recompute it.
#
# `find-callers --resolved` still cannot answer this -- its `line` is the
# caller's DECLARATION line -- which is why a site anchor needs SQL at all.
function Get-EnclosingRoutineSql([string] $RefAlias, [string] $JoinAlias = 'encl') {
  [pscustomobject]@{
    Join   = "LEFT JOIN symbols $JoinAlias ON $JoinAlias.id = $RefAlias.enclosing_symbol_id"
    Select = "$JoinAlias.qualified_name"
  }
}

# Take the top $Cap of an ALREADY-RANKED row list and report exactly what was
# left out, so every caller discloses in the same words. Ranking is the
# caller's job; this only cuts and counts.
#
# $SiteProperty names the per-row count that must ALSO be totalled, because a
# chart whose rows are routines hides two different quantities at once: the
# routines it dropped and the access sites inside them.
function Get-TopRanked($Rows, [int] $Cap, [string] $SiteProperty = 'Sites') {
  # Strip nulls rather than trusting the caller. `$x = if (...) { @() }` assigns
  # $null, not an empty array -- an empty array enumerates to NOTHING on the
  # output stream -- and `@($null)` is then a ONE-element array holding $null.
  # That produced a phantom cross-check finding against an empty wing
  # ("write: verb , sql 0") before this guard existed.
  $all = @($Rows | Where-Object { $null -ne $_ })
  $shown = $all
  $hiddenRows = 0
  $hiddenSites = 0
  if ($Cap -gt 0 -and $all.Count -gt $Cap) {
    $shown = @($all[0..($Cap - 1)])
    foreach ($h in @($all[$Cap..($all.Count - 1)])) {
      $hiddenRows++
      if ($h.PSObject.Properties.Name -contains $SiteProperty) { $hiddenSites += [int]$h.$SiteProperty }
    }
  }
  [pscustomobject]@{
    Shown = $shown; Total = $all.Count
    HiddenRows = $hiddenRows; HiddenSites = $hiddenSites
  }
}

# The ONE place the "not shown" wording is built, so two charts never disclose
# the same fact in two different sentences.
function Get-DisclosureText([int] $HiddenRows, [int] $HiddenSites, [string] $Noun = 'routines') {
  if ($HiddenRows -le 0) { return '' }
  $t = "+$HiddenRows more $Noun"
  if ($HiddenSites -gt 0) { $t += " (+$HiddenSites more sites)" }
  "$t not shown"
}

# Append a NON-ANCHORED row to a raw HTML-label table builder (the focus box).
# Deliberately carries no HREF: there is no line to go to, and a dead link is
# worse than no link. touches-tables' zero case built this inline; both use it
# now so the two cannot diverge.
function Add-DisclosureRow([System.Text.StringBuilder] $Table, [string] $Text,
                           [string] $Ink = '#8A94A6', [int] $PointSize = 12) {
  if ([string]::IsNullOrWhiteSpace($Text)) { return }
  [void]$Table.Append("<TR><TD ALIGN=`"LEFT`"><FONT COLOR=`"$Ink`" POINT-SIZE=`"$PointSize`">$(ConvertTo-XmlText $Text)</FONT></TD></TR>")
}

# A row object for Add-RowCluster that carries NO Href, so the cluster renders
# it as a plain note line. Use it for disclosure and for "see also" notes.
function New-NoteRow([string] $Text) {
  [pscustomobject]@{ Label = $Text; Line = $null; Href = $null; Tip = $null; Note = $null }
}

# ---- dot --------------------------------------------------------------------

# ONE layout run, four outputs -- so the geometry in .plain can never drift from
# the picture in .svg. Verified 2026-09-22.
function Invoke-DotLayout([string] $DotText, [string] $OutDir, [string] $Base) {
  New-Item -ItemType Directory -Force $OutDir | Out-Null
  $dotO = Join-Path $OutDir "$Base.dot"
  $svgO = Join-Path $OutDir "$Base.svg"
  $plnO = Join-Path $OutDir "$Base.plain"
  $pngO = Join-Path $OutDir "$Base.png"
  $pdfO = Join-Path $OutDir "$Base.pdf"
  foreach ($f in @($svgO, $plnO, $pngO, $pdfO)) { if (Test-Path $f) { Remove-Item $f -Force } }

  [IO.File]::WriteAllText($dotO, ($DotText -replace "`r`n", "`n" -replace "`n", "`r`n"),
                          (New-Object Text.UTF8Encoding($false)))

  & $Dot -Tsvg -o $svgO -Tplain -o $plnO -Tpng -Gdpi=110 -o $pngO -Tpdf -o $pdfO $dotO 2>&1 |
    Where-Object { $_ -notmatch 'Pango-WARNING' -and ([string]$_).Trim() -ne '' } |
    ForEach-Object { Write-Host "  dot: $_" }

  if (-not (Test-Path $svgO)) { throw 'dot produced no SVG' }
  $svg = [IO.File]::ReadAllText($svgO)

  [pscustomobject]@{
    Dot = $dotO; Svg = $svgO; Plain = $plnO; Png = $pngO; Pdf = $pdfO
    Anchors = ([regex]::Matches($svg, '<a[\s>]')).Count
  }
}

# Shared rounded-cluster builder. The cluster carries NO label -- Graphviz draws
# a cluster label inside the border and the rounded corner cuts through it; the
# title is a header ROW of the table instead.
#
# $Rows: objects with Label, Line, Href, Tip and optional Note (dimmed suffix).
# Returns the port id assigned to each row, IN ORDER, so callers can key the
# port map by ORDINAL. Keying by name is wrong: one method legitimately appears
# at two different call sites.
#
# -Title/-Subtitle/-Note take PLAIN TEXT and are escaped here. The middot
# separators are emitted OUTSIDE the escape on purpose: passing "a &#183; b" as
# a title would escape the ampersand and render the literal text "&#183;".
# -Style allows "rounded,filled,dashed" for a cluster whose rows are NOT facts
# of the same grade as the solid ones.
function Add-RowCluster {
  param(
    [System.Text.StringBuilder] $Sb, [string] $Cid, [string] $Nid,
    [string] $Title, [string] $Subtitle,
    $Rows, [string] $Border, [string] $Fill, [string] $Hdr,
    [string] $RowInk = '#1F2933', [string] $LineInk = '#8A94A6',
    [string] $FontSans = 'Segoe UI', [string] $Style = 'rounded,filled',
    [int] $PenWidth = 2
  )
  [void]$Sb.AppendLine("  subgraph $Cid {")
  [void]$Sb.AppendLine("    style=`"$Style`"; color=`"$Border`"; fillcolor=`"$Fill`"; penwidth=$PenWidth;")
  [void]$Sb.AppendLine('    label=""; margin=10;')

  $hdrText = ConvertTo-XmlText $Title
  if ($Subtitle) { $hdrText += ' &#183; ' + (ConvertTo-XmlText $Subtitle) }

  $tbl = New-Object System.Text.StringBuilder
  [void]$tbl.Append('<TABLE BORDER="0" CELLBORDER="0" CELLSPACING="3" CELLPADDING="5">')
  [void]$tbl.Append("<TR><TD ALIGN=`"LEFT`" BGCOLOR=`"$Hdr`"><FONT COLOR=`"#FFFFFF`" FACE=`"$FontSans`" POINT-SIZE=`"14`"><B> $hdrText </B></FONT></TD></TR>")

  $ports = New-Object System.Collections.ArrayList
  $p = 0
  foreach ($r in $Rows) {
    # An empty row is always a dot SYNTAX ERROR ("<FONT ...></FONT>" in a TD)
    # and kills the whole layout. THROW rather than skip: the port map is keyed
    # by ORDINAL, so quietly dropping a row would shift every port after it and
    # mis-attach the edges -- a wrong picture instead of no picture. The usual
    # cause is nesting a `, $array` return inside @().
    if ($null -eq $r -or ([string]::IsNullOrWhiteSpace([string]$r.Label) -and
                          [string]::IsNullOrWhiteSpace([string]$r.Href))) {
      throw "Add-RowCluster ($Cid): row $($p + 1) is empty -- did a `, `$array` return get wrapped in @()?"
    }
    $p++
    # A row with NO Href is a note/disclosure line. It must carry neither HREF
    # nor TITLE: HREF="" still makes dot emit an <a>, which both inflates the
    # anchor count the emitters assert on and offers the reader a dead link.
    # It KEEPS its port, so the caller's ordinal port map stays aligned.
    if ([string]::IsNullOrWhiteSpace([string]$r.Href)) {
      [void]$tbl.Append("<TR><TD PORT=`"p$p`" ALIGN=`"LEFT`"><FONT COLOR=`"$LineInk`" POINT-SIZE=`"12`">$(ConvertTo-XmlText $r.Label)</FONT></TD></TR>")
      [void]$ports.Add("${Nid}:p$p")
      continue
    }
    [void]$tbl.Append("<TR><TD PORT=`"p$p`" ALIGN=`"LEFT`" HREF=`"$($r.Href)`" TITLE=`"$(ConvertTo-XmlText $r.Tip)`">")
    [void]$tbl.Append("<FONT COLOR=`"$RowInk`">$(ConvertTo-XmlText $r.Label)</FONT>")
    [void]$tbl.Append("  <FONT COLOR=`"$LineInk`" POINT-SIZE=`"12`">:$($r.Line)</FONT>")
    $note = $null
    if ($r.PSObject.Properties.Name -contains 'Note') { $note = [string]$r.Note }
    if ($note) {
      [void]$tbl.Append("  <FONT COLOR=`"$LineInk`" POINT-SIZE=`"11`">&#183; $(ConvertTo-XmlText $note)</FONT>")
    }
    [void]$tbl.Append('</TD></TR>')
    [void]$ports.Add("${Nid}:p$p")
  }
  [void]$tbl.Append('</TABLE>')
  [void]$Sb.AppendLine("    $Nid [label=<$($tbl.ToString())>];")
  [void]$Sb.AppendLine('  }')
  , $ports.ToArray()
}
