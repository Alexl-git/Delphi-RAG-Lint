<#
  Emit-Hierarchy.ps1 -- the `hierarchy` question: what this TYPE inherits from,
  and what inherits from it.

  The first emitter whose selection is a TYPE, and the first that is not
  left-to-right: ancestors sit ABOVE the focus and descendants BELOW, because a
  hierarchy read sideways stops looking like a hierarchy. The rounded-cluster
  and clickable-row grammar is otherwise identical to the other six.

  Arrows mean INHERITS FROM, so they all point upward -- focus -> ancestor and
  descendant -> focus. That is the UML generalization direction and it keeps one
  meaning for one arrow across the whole picture.

  IT IS A DAG, NOT A TREE. A class has ONE parent but any number of interfaces,
  so a node can be reached by several paths. Nodes are de-duplicated by identity
  and edges are allowed to multiply; the same type is never drawn twice.

  WHAT THE TWO VERBS ACTUALLY RETURN -- measured 2026-09-23, CLIENT index
  ---------------------------------------------------------------------
  * `ancestors --name T` gives DIRECT heritage only, each row carrying
    `resolved`. TBlueprintCADImport_ViewModel -> TInterfacedObject (unresolved)
    + IBlueprintCADImport_ViewModel (resolved), NOT the grandparents.
  * `descendants --of T` gives BARE NAMES and nothing else -- no file, no line,
    no kind -- so every row needs a lookup before it can be clicked.
    TInterfacedObject has 145 of them here, which is why the cap matters.

  A BARE NAME CAN COLLIDE, AND ON THIS CORPUS IT SOMETIMES DOES: 21 of 843 type
  names on CLIENT match more than one type, 23 of 706 on SERVER, worst
  `IDataService` at FOUR. A colliding row is rendered UN-ANCHORED with the
  ambiguity stated, because a confidently wrong jump is worse than no jump.

  THE SELF-LOOP THAT COLLISION CAUSES. `ancestors --name IDataService` returns
  IDataService AS ITS OWN ANCESTOR -- the verb matched a bare name, and one of
  the four IDataService declarations names another in its heritage. An ambiguous
  FOCUS is therefore refused outright, and any row that names the focus is
  dropped and counted rather than drawn as an edge from a node to itself.

  SINGLE-DB ON PURPOSE. An unresolved ancestor (TInterfacedObject lives in the
  RTL) is drawn grey, un-anchored, labelled "(outside this project's closure)".
  The library index is NOT opened: the house rule is that the authoritative set
  is the project DB plus the platform library, and mixing them here would make
  row provenance ambiguous exactly where this chart claims to be precise.
#>
[CmdletBinding()]
param(
  [Parameter(Mandatory)][string] $Type,
  [Parameter(Mandatory)][string] $DbPath,   # NOT -Db: CmdletBinding aliases that to -Debug
  [int]    $Cap        = 20,
  [string] $OutDir,
  [string] $Engine     = 'C:\Projects\Delphi-RAG-lint\third_party\dll-win64\drag-lint.exe',
  [string] $Dot        = 'C:\Projects\GraphWiz\Graphviz-16.1.0-win64\bin\dot.exe',
  [string] $FontMono   = 'Consolas',
  [string] $FontSans   = 'Segoe UI'
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Emit-Common.ps1')

# Refuse a live corpus DB (see Get-CloneDb): charts run against the frozen clones.
$DbPath = Get-CloneDb $DbPath

# Ancestors share caller blue (what this type came FROM), descendants callee
# amber (what came FROM it) -- the same up/down reading the call charts use.
$PAL = @{
  ancBorder   = '#3B5BDB'; ancFill   = '#EDF2FF'; ancHdr   = '#3B5BDB'
  descBorder  = '#B45309'; descFill  = '#FEF6EC'; descHdr  = '#B45309'
  focusBorder = '#0F766E'; focusFill = '#E2F1EF'; focusHdr = '#0F766E'
  rowInk      = '#1F2933'; lineInk   = '#8A94A6'; focusInk = '#0B3F39'
  greyBorder  = '#98A2B3'; greyFill  = '#F4F5F7'; greyHdr  = '#98A2B3'
}

Write-Host "hierarchy: $Type"

# ---- 1. the focus, REFUSING an ambiguous type name ---------------------------
# Refusing matters more here than anywhere else: an ambiguous name makes the
# VERB answer about a different declaration than the one the chart is labelled
# with, and `IDataService` shows the failure mode -- it returns itself.
#
# A MISSING focus is NOT refused here, and that distinction is the whole reason
# -AllowMissing exists. `TInterfacedObject` is RTL: no CLIENT unit declares it,
# yet 145 types in CLIENT inherit from it. "Nothing here declares this type, and
# here are the 145 things that extend it" is a real and useful answer, so the
# focus is drawn un-anchored instead of the question being rejected. Only a name
# that is BOTH undeclared here AND has no heritage either way is refused, below.
$sel  = Resolve-MemberSelection $Type @('class', 'interface', 'record', 'type') -AllowMissing
$bare = if ($sel) { $sel.Name } else { ($Type -split '\.')[-1] }
$unit = if ($sel) { Get-UnitName $sel.Path } else { '(not in this index)' }
if ($sel) {
  Write-Host "  selection: $($sel.Qname) ($($sel.Kind)) $([IO.Path]::GetFileName($sel.Path)):$($sel.FocusLine)"
} else {
  Write-Host "  selection: $bare is not declared in this index -- asking for its heritage anyway"
}

# ---- 2. the two verbs --------------------------------------------------------
$anc = @()
$desc = @()
# Both verbs exit 1 on NO MATCH with an empty list (measured); -AllowNoMatch
# accepts exactly that and nothing else -- any other failure throws (R19).
$txt = Get-EngineText @('query', 'ancestors', '--name', $bare, '--db', $DbPath, '--json') -AllowNoMatch
if ($txt) { $anc = @(($txt | ConvertFrom-Json).ancestors) }
$txt = Get-EngineText @('query', 'descendants', '--of', $bare, '--db', $DbPath, '--json') -AllowNoMatch
if ($txt) { $desc = @(($txt | ConvertFrom-Json).descendants) }

# Drop any row that names the focus. See the header: a colliding bare name makes
# the verb report a type as its own ancestor, and an edge from a node to itself
# is not a fact about inheritance, it is an artifact of the lookup.
$selfRefs = 0
$anc  = @($anc  | Where-Object { if ([string]$_.name -eq $bare) { $script:selfRefs++; $false } else { $true } })
$desc = @($desc | Where-Object { if ([string]$_      -eq $bare) { $script:selfRefs++; $false } else { $true } })
if ($selfRefs) {
  Write-Host "  NOTE: dropped $selfRefs self-reference(s) -- a bare name matched another declaration of the same name"
}

# The only genuine refusal: not declared here AND no heritage either way, which
# is what a typo looks like. With either list non-empty there is a chart to draw.
if (-not $sel -and $anc.Count -eq 0 -and $desc.Count -eq 0) {
  throw "$Type is not in this index, and nothing in it inherits from or is inherited by that name"
}

$unresolvedAnc = @($anc | Where-Object { -not $_.resolved }).Count
Write-Host ("  ancestors={0} (of which {1} outside this project)  descendants={2}" -f `
            $anc.Count, $unresolvedAnc, $desc.Count)

# ---- 3. rank and cap ---------------------------------------------------------
# Ancestors keep the VERB's order -- that is the declaration order of the
# heritage clause, which is information. Descendants have no natural weight, so
# they sort alphabetically.
$ancRanked  = @($anc)
$descRanked = @($desc | Sort-Object)
$aTop = Get-TopRanked $ancRanked  $Cap
$dTop = Get-TopRanked $descRanked $Cap

# ---- 4. ONE batched lookup for every name that will be DRAWN -----------------
# Never one query per row: `descendants` returns names only, and TInterfacedObject
# has 145 of them. Bounded to the shown rows, this cannot approach the 200 cap.
$lookup = @{}     # bare name -> @( rows )
$wanted = @(@($aTop.Shown | Where-Object { $_.resolved } | ForEach-Object { [string]$_.name }) +
            @($dTop.Shown | ForEach-Object { [string]$_ })) | Sort-Object -Unique
if ($wanted.Count) {
  $rows = Invoke-IndexQuery @"
SELECT s.name AS nm, s.qualified_name AS qualified_name, s.kind AS kind,
       s.start_line AS start_line, s.end_line AS end_line,
       s.generic_params AS generic_params, f.path AS path
  FROM symbols s JOIN files f ON f.id = s.file_id
 WHERE s.name IN ($(ConvertTo-SqlInList $wanted))
   AND s.kind IN ('class','interface','record','type')
 ORDER BY s.name, s.qualified_name
"@ 'hierarchy (name lookup)'
  # A forward declaration plus its body is ONE type, not a collision. Without
  # this, `IDataService` reports four candidates where the unit declares two.
  $rows = Select-DeclarationRows $rows
  foreach ($r in $rows) {
    $k = [string]$r.nm
    if (-not $lookup.ContainsKey($k)) { $lookup[$k] = New-Object System.Collections.ArrayList }
    [void]$lookup[$k].Add($r)
  }
}

# ---- 5. rows -----------------------------------------------------------------
$collisions = 0
$unlocatable = 0

# Turn a BARE name into a row. Three outcomes and each is stated, never guessed:
#   exactly one match -> anchored
#   several matches   -> un-anchored, ambiguity named  (measured: 21/843 names)
#   no match          -> un-anchored, said plainly
function New-TypeRow([string] $Name, [string] $Note) {
  $hits = @()
  if ($lookup.ContainsKey($Name)) { $hits = @($lookup[$Name]) }
  if ($hits.Count -eq 1) {
    $h = $hits[0]
    return [pscustomobject]@{
      Label = $Name
      Line  = [int]$h.start_line
      Href  = New-RowHref ([string]$h.path) ([int]$h.start_line)
      Tip   = "$([string]$h.qualified_name) ($([string]$h.kind))  --  $([IO.Path]::GetFileName([string]$h.path)):$($h.start_line)"
      Note  = $Note
    }
  }
  if ($hits.Count -gt 1) {
    $script:collisions++
    return New-NoteRow "$Name  ($($hits.Count) types share this name -- ambiguous, not linked)"
  }
  $script:unlocatable++
  New-NoteRow "$Name  (not a type in this index)"
}

$ancRows = New-Object System.Collections.ArrayList
foreach ($a in @($aTop.Shown)) {
  if (-not $a.resolved) {
    # An RTL/VCL parent. It is a real ancestor and a real fact; it simply lives
    # in the platform library index, which this emitter deliberately does not open.
    [void]$ancRows.Add((New-NoteRow "$([string]$a.name)  (outside this project's closure)"))
  } else {
    [void]$ancRows.Add((New-TypeRow ([string]$a.name) ([string]$a.kind)))
  }
}
$d = Get-DisclosureText $aTop.HiddenRows 0 'ancestors'
if ($d) { [void]$ancRows.Add((New-NoteRow $d)) }

$descRows = New-Object System.Collections.ArrayList
foreach ($n in @($dTop.Shown)) { [void]$descRows.Add((New-TypeRow ([string]$n) $null)) }
$d = Get-DisclosureText $dTop.HiddenRows 0 'descendants'
if ($d) { [void]$descRows.Add((New-NoteRow $d)) }

if ($ancRows.Count -eq 0 -and $descRows.Count -eq 0) {
  Write-Host '  NOTE: no ancestors and no descendants -- rendering the focus alone'
}

# ---- 6. dot ------------------------------------------------------------------
$sb = New-Object System.Text.StringBuilder
[void]$sb.AppendLine('digraph hierarchy {')
# TB, not LR: this is the one chart whose axis carries meaning.
[void]$sb.AppendLine('  rankdir=TB; bgcolor="transparent"; compound=true;')
[void]$sb.AppendLine('  nodesep=0.35; ranksep=1.1; splines=spline;')
[void]$sb.AppendLine("  graph [fontname=`"$FontSans`"];")
[void]$sb.AppendLine("  node  [shape=plaintext, fontname=`"$FontMono`", fontsize=14];")
[void]$sb.AppendLine("  edge  [fontname=`"$FontMono`", fontsize=11, color=`"$($PAL.lineInk)`", penwidth=1.5, arrowsize=0.8];")
[void]$sb.AppendLine('')

$ancPorts = @()
if ($ancRows.Count) {
  $ancPorts = Add-RowCluster -Sb $sb -Cid 'cluster_ancestors' -Nid 'na' `
                -Title 'inherits from' -Subtitle "$($aTop.Total) direct" -Rows $ancRows `
                -Border $PAL.ancBorder -Fill $PAL.ancFill -Hdr $PAL.ancHdr `
                -RowInk $PAL.rowInk -LineInk $PAL.lineInk -FontSans $FontSans
}

[void]$sb.AppendLine('  subgraph cluster_focus {')
[void]$sb.AppendLine("    style=`"rounded,filled`"; color=`"$($PAL.focusBorder)`"; fillcolor=`"$($PAL.focusFill)`"; penwidth=3;")
[void]$sb.AppendLine('    label=""; margin=12;')
$fkind = if ($sel) { $sel.Kind } else { 'not declared here' }
$fhdr  = "<TR><TD ALIGN=`"LEFT`" BGCOLOR=`"$($PAL.focusHdr)`"><FONT COLOR=`"#FFFFFF`" FACE=`"$FontSans`" POINT-SIZE=`"14`"><B> $(ConvertTo-XmlText $unit) &#183; $(ConvertTo-XmlText $fkind) </B></FONT></TD></TR>"
$ftbl  = New-Object System.Text.StringBuilder
[void]$ftbl.Append("<TABLE BORDER=`"0`" CELLBORDER=`"0`" CELLSPACING=`"3`" CELLPADDING=`"7`">$fhdr")
if ($sel) {
  $fhref = New-RowHref $sel.Path $sel.FocusLine
  $ftip  = ConvertTo-XmlText "$($sel.Qname)  --  $([IO.Path]::GetFileName($sel.Path)):$($sel.FocusLine)"
  [void]$ftbl.Append("<TR><TD HREF=`"$fhref`" TITLE=`"$ftip`"><FONT COLOR=`"$($PAL.focusInk)`" POINT-SIZE=`"18`"><B>$(ConvertTo-XmlText $bare)</B></FONT></TD></TR>")
} else {
  # No declaration to click through to, so no link -- same rule as every other
  # un-anchored row in these charts.
  [void]$ftbl.Append("<TR><TD><FONT COLOR=`"$($PAL.focusInk)`" POINT-SIZE=`"18`"><B>$(ConvertTo-XmlText $bare)</B></FONT></TD></TR>")
  Add-DisclosureRow $ftbl "outside this project's closure -- declared in the platform library index" $PAL.lineInk
}
if ($anc.Count -eq 0)  { Add-DisclosureRow $ftbl 'no declared ancestors' $PAL.lineInk }
if ($desc.Count -eq 0) { Add-DisclosureRow $ftbl 'nothing in this index inherits from it' $PAL.lineInk }
if ($selfRefs) { Add-DisclosureRow $ftbl "$selfRefs self-reference(s) dropped (name collision)" $PAL.lineInk }
[void]$ftbl.Append('</TABLE>')
[void]$sb.AppendLine("    focus [label=<$($ftbl.ToString())>];")
[void]$sb.AppendLine('  }')

$descPorts = @()
if ($descRows.Count) {
  $descPorts = Add-RowCluster -Sb $sb -Cid 'cluster_descendants' -Nid 'nd' `
                 -Title 'inherited by' -Subtitle "$($dTop.Total) type$(if ($dTop.Total -ne 1) { 's' })" -Rows $descRows `
                 -Border $PAL.descBorder -Fill $PAL.descFill -Hdr $PAL.descHdr `
                 -RowInk $PAL.rowInk -LineInk $PAL.lineInk -FontSans $FontSans
}

[void]$sb.AppendLine('')
# Every arrow means INHERITS FROM and so points upward. A note row (unresolved,
# colliding, or a disclosure) gets no edge: it names no node this graph owns.
for ($i = 0; $i -lt $ancRows.Count; $i++) {
  if ([string]::IsNullOrWhiteSpace([string]$ancRows[$i].Href)) { continue }
  [void]$sb.AppendLine("  focus -> $($ancPorts[$i]) [color=`"$($PAL.ancBorder)`"];")
}
for ($i = 0; $i -lt $descRows.Count; $i++) {
  if ([string]::IsNullOrWhiteSpace([string]$descRows[$i].Href)) { continue }
  [void]$sb.AppendLine("  $($descPorts[$i]) -> focus [color=`"$($PAL.descBorder)`"];")
}
[void]$sb.AppendLine('}')

# ---- 7. lay out --------------------------------------------------------------
if ([string]::IsNullOrWhiteSpace($OutDir)) { $OutDir = Join-Path $PSScriptRoot '..\scratch' }
$base = ($(if ($sel) { $sel.Qname } else { $Type }) -replace '[^A-Za-z0-9]', '_') + '_hierarchy'
$lay  = Invoke-DotLayout $sb.ToString() $OutDir $base

# The focus counts as a click target only when it HAS a declaration to open.
$anchored = @($ancRows | Where-Object { $_.Href }).Count + @($descRows | Where-Object { $_.Href }).Count
$expected = $anchored + $(if ($sel) { 1 } else { 0 })

[pscustomobject]@{
  Dot             = $lay.Dot
  Svg             = $lay.Svg
  Plain           = $lay.Plain
  Png             = $lay.Png
  Pdf             = $lay.Pdf
  Resolved        = $(if ($sel) { $sel.Qname } else { $null })
  Kind            = $(if ($sel) { $sel.Kind } else { $null })
  FocusDeclared   = [bool]$sel
  Ancestors       = $anc.Count
  UnresolvedAnc   = $unresolvedAnc     # real ancestors, in the LIBRARY index
  Descendants     = $desc.Count
  ShownAncestors  = $aTop.Shown.Count
  ShownDescendants= $dTop.Shown.Count
  HiddenAncestors = $aTop.HiddenRows
  HiddenDescendants = $dTop.HiddenRows
  Collisions      = $collisions        # names matching >1 type: drawn un-anchored
  Unlocatable     = $unlocatable
  SelfRefs        = $selfRefs
  ClickTargets    = $lay.Anchors
  Expected        = $expected
  AllClickable    = ($lay.Anchors -ge $expected)
}
