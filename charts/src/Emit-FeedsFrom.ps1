<#
  Emit-FeedsFrom.ps1 -- the `feeds-from` question: which database TABLE.COLUMN
  does this data-aware CONTROL show, and how sure is each step of the answer?

  ONE CHAIN, DRAWN HOP BY HOP
  ----------------------------
  control --DataSource--> TDataSource --DataSet--> memtable --owner--> view model
          --literal--> TABLE --exists--> TABLE.COLUMN

  Every hop comes from Get-DataSourceChain (Emit-Common), the ONE function that
  consumers' column form and lands-where also use, so the three verbs cannot
  disagree on what a control feeds from. The control's datasource is found by
  Get-ControlDataSourceSql: its own DataSource property, else its parent's, else
  its grandparent's (a grid column is fed through its view).

  Top = the control, bottom = TABLE.COLUMN. Each hop carries its grade:
    [certain]      a fact of the index or of fresh source (the DFM line, the
                   same-file TDataSource, the assignment line, the column in the
                   newest script declaration)
    [by name]      found by NAME only (the RHS root's type; a module-prefixed
                   datasource in another file) -- dashed
    [inferred]     the table, taken from string literals in the view model's
                   unit -- never a fact -- dashed
    [dangling]     the DFM names a data module this index does not hold
  A chain that cannot be followed ends in a grey "chain stops here: <reason>"
  node. It NEVER guesses a table: an ambiguous view model prints its candidates
  (anchored on their literals) and no TABLE.COLUMN.

  RE-POINTED IN CODE (P29, R8): `edtF1.DataBinding.DataSource := DS` at runtime
  overrides the designer. Both are drawn -- the DFM row marked [dangling] when
  its module is not in the index, and a side cluster of [re-pointed at
  routine:line] rows anchored to the line even when receiver_text lost the
  control. A DataField / FieldName re-bound in code is drawn the same way.

  COVERAGE, MEASURED AT BUILD TIME (R9): the focus box prints the per-DATASOURCE
  split AND the per-CONTROL one (Get-FieldBindingChains). The 41% of the plan
  is per datasource and is not quoted.

  FRESHNESS (R11): every source line is read through Get-SourceContext /
  Test-SourceFresh; a stale file stops the chain with [stale source].
  -SourceOverride maps an indexed path to a copy to read instead (ruling R4).
#>
[CmdletBinding()]
param(
  [Parameter(Mandatory)][Alias('Target','Qname')][string] $Control,
  [Parameter(Mandatory)][string] $DbPath,
  [Parameter(Mandatory)][string] $SqlDbPath,
  [string]    $OutDir,
  [int]       $Cap = 12,                  # candidate / re-pointed rows shown; the rest disclosed
  [hashtable] $SourceOverride,
  [string] $Engine     = 'C:\Projects\Delphi-RAG-lint-wt\archify-ir\third_party\dll-win64\drag-lint.exe',
  [string] $Dot        = 'C:\Projects\GraphWiz\Graphviz-16.1.0-win64\bin\dot.exe',
  [string] $FontMono   = 'Consolas',
  [string] $FontSans   = 'Segoe UI'
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Emit-Common.ps1')

$DbPath    = Get-CloneDb $DbPath
$SqlDbPath = Get-CloneDb $SqlDbPath

$PAL = @{
  ctlBorder   = '#7C3AED'; ctlFill   = '#F3EEFF'; ctlHdr   = '#7C3AED'
  dsBorder    = '#0F766E'; dsFill    = '#E2F1EF'; dsHdr    = '#0F766E'
  setBorder   = '#3B5BDB'; setFill   = '#EDF2FF'; setHdr   = '#3B5BDB'
  typeBorder  = '#475569'; typeFill  = '#F1F5F9'; typeHdr  = '#475569'
  dbBorder    = '#BE185D'; dbFill    = '#FDF2F8'; dbHdr    = '#BE185D'
  codeBorder  = '#C2410C'; codeFill  = '#FFF4E6'; codeHdr  = '#C2410C'
  warnBorder  = '#B45309'; warnFill  = '#FEF3C7'; warnHdr  = '#B45309'
  stopBorder  = '#6B7280'; stopFill  = '#F3F4F6'; stopHdr  = '#6B7280'
  focusBorder = '#0F766E'; focusFill = '#E2F1EF'; focusHdr = '#0F766E'
  rowInk      = '#1F2933'; lineInk   = '#8A94A6'
}
$DS_PROPS = @('DataSource', 'DataBinding.DataSource', 'DataController.DataSource')

Write-Host "feeds-from: $Control"

# ---- 0. the SQL index role (a swapped pair must not render) --------------------------
$sqlSet = Get-SqlTableSet $SqlDbPath
if ($sqlSet.TableCount -eq 0) {
  throw "feeds-from: $SqlDbPath is not a SQL index (0 sql_table symbols) -- -SqlDbPath takes the SQL-script clone, -DbPath the Delphi project clone"
}

# ---- 1. the selection: <Form>.<Control> or the component's full qualified name -------
$sel = $Control.Trim()
if ($sel -notmatch '^[A-Za-z_][A-Za-z0-9_]*(\.[A-Za-z_][A-Za-z0-9_]*)+$') {
  throw "feeds-from: -Control takes <Form>.<Control> (e.g. frmCausFail.colREASON), got '$Control'"
}
$segs = $sel -split '\.'
$formName = $segs[0]; $ctlName = $segs[-1]
$forms = Invoke-IndexQuery @"
SELECT s.file_id AS fid, f.path AS path FROM symbols s JOIN files f ON f.id = s.file_id
 WHERE s.kind = 'form' AND UPPER(s.name) = UPPER('$(ConvertTo-SqlText $formName)')
"@
if ($forms.Count -eq 0) { throw "feeds-from: no form or data module named $formName in this index" }
$cands = Invoke-IndexQuery @"
SELECT c.id AS id, c.name AS name, c.qualified_name AS q, c.signature AS sig, c.parent_id AS pid,
       c.start_line AS line, c.file_id AS fid, f.path AS path, p.name AS pname, p.signature AS psig
  FROM symbols c JOIN files f ON f.id = c.file_id LEFT JOIN symbols p ON p.id = c.parent_id
 WHERE c.kind = 'component' AND c.file_id IN ($((@($forms | ForEach-Object { [int]$_.fid })) -join ','))
   AND UPPER(c.name) = UPPER('$(ConvertTo-SqlText $ctlName)')
"@
if ($segs.Count -gt 2) { $cands = @($cands | Where-Object { [string]::Equals([string]$_.q, $sel, [StringComparison]::OrdinalIgnoreCase) }) }
if ($cands.Count -eq 0) {
  throw "feeds-from: no component named $ctlName on $formName ($(($forms | ForEach-Object { [IO.Path]::GetFileName([string]$_.path) }) -join ', '))"
}
if ($cands.Count -gt 1) {
  throw "feeds-from: $sel names $($cands.Count) components ($(($cands | ForEach-Object { [string]$_.q }) -join ', ')) -- pass the full qualified name"
}
$C = $cands[0]
$cid = [int]$C.id; $ctype = [string]$C.sig; $dfm = [string]$C.path; $fid = [int]$C.fid
$qualified = [string]$C.q

if ($ctype -eq 'TDataSource') {
  throw ("feeds-from selects a data-aware CONTROL, not a datasource -- ask consumers/shown-where. " +
         "$qualified is a TDataSource; pick a control bound to it (a grid column, an edit) to see its chain.")
}

# the control's own field binding, and its datasource by the SHARED rule
$fb = Invoke-IndexQuery @"
SELECT owner_name AS prop, text AS col, start_line AS line FROM string_literals
 WHERE kind = 'dfm-prop' AND symbol_id = $cid
   AND owner_name IN ('DataBinding.FieldName','DataBinding.DataField','DataField','FieldName')
 ORDER BY start_line
"@
if (@($fb | Where-Object { $_.prop -eq 'FieldName' }).Count -and -not @($fb | Where-Object { $_.prop -ne 'FieldName' }).Count) {
  throw ("feeds-from: $qualified is a persistent FIELD ($ctype) of the dataset $([string]$C.pname), not a control -- " +
         'its FieldName names the dataset column it maps. Ask shown-where for the controls that display that column.')
}
$field = @($fb | Where-Object { $_.prop -ne 'FieldName' } | Select-Object -First 1)
$dsTextRow = Invoke-IndexQuery @"
SELECT $(Get-ControlDataSourceSql 'sl' 'c') AS ds
  FROM symbols c JOIN (SELECT $fid AS file_id) sl
 WHERE c.id = $cid
"@
$dsText = $(if ($dsTextRow.Count) { [string]$dsTextRow[0].ds } else { '' })
$dsProp = $null
if ($dsText) {
  $own = Invoke-IndexQuery @"
SELECT d.symbol_id AS sid, d.owner_name AS prop, d.start_line AS line, s.name AS owner, s.signature AS osig
  FROM string_literals d JOIN symbols s ON s.id = d.symbol_id
 WHERE d.kind = 'dfm-prop' AND d.file_id = $fid AND d.owner_name IN ($(ConvertTo-SqlInList $DS_PROPS))
   AND d.text = '$(ConvertTo-SqlText $dsText)'
   AND d.symbol_id IN ($cid, $(if ($C.pid) { [int]$C.pid } else { 0 }), (SELECT g.parent_id FROM symbols g WHERE g.id = $(if ($C.pid) { [int]$C.pid } else { 0 })))
 ORDER BY d.start_line
"@
  # nearest first, the same order Get-ControlDataSourceSql applies
  $dsProp = @($own | Sort-Object @{ E = { if ([int]$_.sid -eq $cid) { 0 } elseif ($C.pid -and [int]$_.sid -eq [int]$C.pid) { 1 } else { 2 } } },
                                 @{ E = { [int]$_.line } })[0]
}
$lookup = Invoke-IndexQuery @"
SELECT owner_name AS prop, text AS ds, start_line AS line FROM string_literals
 WHERE kind = 'dfm-prop' AND symbol_id = $cid AND owner_name IN ('ListSource','Properties.ListSource')
"@
if (-not $field.Count -and -not $dsText) {
  throw ("feeds-from: $qualified ($ctype) is not data-aware: no DataSource and no field binding on it or its two " +
         'enclosing components in the DFM. feeds-from selects a data-aware CONTROL.')
}

$shas = Get-IndexedFileShas
$pasGuess = [IO.Path]::ChangeExtension($dfm, '.pas')
$pas = @($shas.Keys | Where-Object { [string]::Equals($_, $pasGuess, [StringComparison]::OrdinalIgnoreCase) })
$pas = $(if ($pas.Count) { [string]$pas[0] } else { $null })
$unitName = Get-UnitName $pas

# ---- 2. the chain -----------------------------------------------------------------------
$ch = $null
if ($dsText) { $ch = Get-DataSourceChain $dfm $dsText $sqlSet $SourceOverride }
$owner = $(if ($dsProp) { [string]$dsProp.owner } else { $ctlName })
$repoint = @()
if ($ch) { $repoint = @($ch.RePointedAt | Where-Object { $_.Control -eq $owner }) }
elseif ($pas) { $repoint = Get-RePointSites $pas @($ctlName) @('DataSource') $SourceOverride }   # assigned DIRECTLY: @(...) nests the `, $array` return
$rebound = @()
if ($pas -and $field.Count) { $rebound = Get-RePointSites $pas @($ctlName) @('DataField', 'FieldName') $SourceOverride }
Write-Host ("  {0} ({1}); field {2}; datasource {3}{4}; chain {5}" -f $qualified, $ctype,
            $(if ($field.Count) { [string]$field[0].col } else { '(none)' }), $(if ($dsText) { $dsText } else { '(none in DFM)' }),
            $(if ($dsProp -and $dsProp.sid -ne $cid) { " via $owner" } else { '' }), $(if ($ch) { $ch.Grade } else { 'no-ds' }))

# ---- 3. index-wide coverage, per datasource AND per control (R9) --------------------------
$ix = Get-FieldBindingChains $sqlSet $SourceOverride
$dsAll = @($ix.DataSources)
$stat = [ordered]@{
  Ds       = $dsAll.Count
  DsDfm    = @($dsAll | Where-Object { @($_.DataSetSites | Where-Object { $_.Kind -eq 'dfm' }).Count }).Count
  DsCode   = @($dsAll | Where-Object { @($_.DataSetSites | Where-Object { $_.Kind -ne 'dfm' }).Count }).Count
  DsOne    = @($dsAll | Where-Object { $_.Grade -eq 'one-table' }).Count
  DsByCol  = @($dsAll | Where-Object { $_.Grade -eq 'by-columns' }).Count
  DsMany   = @($dsAll | Where-Object { $_.Grade -eq 'many' }).Count
  DsNone   = @($dsAll | Where-Object { $_.Grade -eq 'none' }).Count
}
$stat.DsOther = $stat.Ds - $stat.DsOne - $stat.DsByCol - $stat.DsMany - $stat.DsNone
$bAll = @($ix.Bindings)
$oc = @{}; foreach ($b in $bAll) { $oc[$b.Outcome] = 1 + [int]$oc[$b.Outcome] }
$ctlTotal = $bAll.Count
$ctlTable = [int]$oc['column'] + [int]$oc['not-column']
$pct = $(if ($ctlTotal) { [Math]::Round(100.0 * $ctlTable / $ctlTotal, 1) } else { 0 })
$pctCol = $(if ($ctlTotal) { [Math]::Round(100.0 * [int]$oc['column'] / $ctlTotal, 1) } else { 0 })
Write-Host ("  index: {0} datasources ({1} DFM / {2} code); one {3}, by-columns {4}, many {5}, none {6}, other {7}; controls {8}: column {9}, not-column {10}, ambiguous {11}, stops {12}, dangling {13}, no-ds {14}, stale {15}" -f `
  $stat.Ds, $stat.DsDfm, $stat.DsCode, $stat.DsOne, $stat.DsByCol, $stat.DsMany, $stat.DsNone, $stat.DsOther, $ctlTotal,
  [int]$oc['column'], [int]$oc['not-column'], [int]$oc['ambiguous'], [int]$oc['stops'], [int]$oc['dangling'], [int]$oc['no-ds'], [int]$oc['stale'])

# ---- 4. dot ----------------------------------------------------------------------------------
$sb = New-Object System.Text.StringBuilder
[void]$sb.AppendLine('digraph feedsfrom {')
[void]$sb.AppendLine('  rankdir=TB; bgcolor="transparent"; compound=true;')
[void]$sb.AppendLine('  nodesep=0.5; ranksep=0.55; splines=spline;')
[void]$sb.AppendLine("  graph [fontname=`"$FontSans`"];")
[void]$sb.AppendLine("  node  [shape=plaintext, fontname=`"$FontMono`", fontsize=14];")
[void]$sb.AppendLine("  edge  [fontname=`"$FontMono`", fontsize=11, color=`"$($PAL.lineInk)`", penwidth=1.4, arrowsize=0.7];")
[void]$sb.AppendLine('')

$nodeId = 0; $anchored = 0; $rtNote = ''
$chainNodes = New-Object System.Collections.ArrayList     # Nid, Grade (for the edge into it)
function New-Row([string] $Label, [string] $File, [int] $Line, [string] $Tip, [string] $Note) {
  $script:anchored++
  [pscustomobject]@{ Label = $Label; Line = $Line; Href = New-RowHref $File $Line; Tip = $Tip; Note = $Note }
}
function Get-GradeTag([string] $g) { "[$g]" }
function Add-Hop([string] $Title, [string] $Grade, $Rows, [string] $Border, [string] $Fill, [string] $Hdr, [switch] $Side) {
  $script:nodeId++
  $nid = "n$($script:nodeId)"
  $dashed = ($Grade -in 'inferred', 'by name')
  [void](Add-RowCluster -Sb $sb -Cid "cluster_hop_$($script:nodeId)" -Nid $nid -Title $Title -Subtitle (Get-GradeTag $Grade) `
           -Rows $Rows -Border $Border -Fill $Fill -Hdr $Hdr -RowInk $PAL.rowInk -LineInk $PAL.lineInk -FontSans $FontSans `
           -Style $(if ($dashed) { 'rounded,filled,dashed' } else { 'rounded,filled' }))
  if (-not $Side) { [void]$chainNodes.Add([pscustomobject]@{ Nid = $nid; Grade = $Grade; Title = $Title }) }
  $nid
}
# the column's own line in the winning declaration; $DbPath is SHADOWED in the
# function scope, so the caller's Delphi index is untouched (consumers' pattern)
function Get-SqlColumnLine([int] $TableId, [string] $Col, [int] $Fallback) {
  $DbPath = $SqlDbPath
  $cl = Invoke-IndexQuery "SELECT start_line AS line FROM symbols WHERE kind = 'sql_column' AND parent_id = $TableId AND UPPER(name) = UPPER('$(ConvertTo-SqlText $Col)')"
  $(if ($cl.Count) { [int]$cl[0].line } else { $Fallback })
}
function Get-RoutineShort([string] $Routine, [string] $File) {
  $s = Get-ShortName $Routine (Get-UnitName $File)
  $(if ($s) { $s } else { '(unit level)' })
}

# -- hop: the control ------------------------------------------------------------------------
$ctlRows = New-Object System.Collections.ArrayList
if ($field.Count) {
  [void]$ctlRows.Add((New-Row "$ctlName : $ctype" $dfm ([int]$field[0].line) "$qualified.$($field[0].prop) = '$($field[0].col)' -- $([IO.Path]::GetFileName($dfm)):$($field[0].line)" "$($field[0].prop) = $($field[0].col)"))
} else {
  [void]$ctlRows.Add((New-Row "$ctlName : $ctype" $dfm ([int]$C.line) "$qualified -- $([IO.Path]::GetFileName($dfm)):$($C.line)" 'binds no column itself'))
}
if ($dsProp) {
  $via = $(if ([int]$dsProp.sid -ne $cid) { "$($dsProp.owner).$($dsProp.prop)" } else { [string]$dsProp.prop })
  [void]$ctlRows.Add((New-Row "$via = $dsText" $dfm ([int]$dsProp.line) "$via = $dsText -- $([IO.Path]::GetFileName($dfm)):$($dsProp.line)" $(if ([int]$dsProp.sid -ne $cid) { "via its $($dsProp.osig)" } else { 'DFM' })))
} else {
  [void]$ctlRows.Add((New-NoteRow 'no DataSource on it or its two enclosing components in the DFM'))
}
foreach ($l in $lookup) {
  [void]$ctlRows.Add((New-Row "$($l.prop) = $($l.ds)" $dfm ([int]$l.line) "$($l.prop) = $($l.ds) -- a lookup list, a different binding" 'lookup list; not followed'))
}
$nCtl = Add-Hop 'control' 'certain' $ctlRows.ToArray() $PAL.ctlBorder $PAL.ctlFill $PAL.ctlHdr

# -- side: re-pointed / re-bound in code ------------------------------------------------------
$codeRows = New-Object System.Collections.ArrayList
foreach ($r in @($repoint + $rebound)) {
  $what = $(if ($r.Prop -in 'DataSource', 'ListSource' -or -not $r.Prop) { 're-pointed' } else { 're-bound' })
  $rtn = Get-RoutineShort $r.Routine $r.File
  # the receiver as written (`edtF1.DataBinding`), or the recovered control plus the
  # receiver_text the index kept (`.DataBinding`) when the control was lost (P29)
  $recv = $(if (-not $r.Receiver) { $r.Control } elseif ($r.Receiver.StartsWith('.')) { $r.Control + $r.Receiver } else { $r.Receiver -replace '^Self\.', '' })
  $lbl = "[$what at ${rtn}:$($r.Line)] $recv.$($r.Prop) := $(if ($r.Stale) { '?' } else { $r.Rhs })"
  $note = @()
  if ($r.ControlFrom -eq 'source') { $note += "control read from source (receiver_text '$($r.Receiver)')" }
  if ($r.Stale) { $note += '[stale source]' }
  [void]$codeRows.Add((New-Row $lbl $r.File $r.Line "$($r.Control).$($r.Prop) assigned in $($r.Routine) -- $([IO.Path]::GetFileName($r.File)):$($r.Line)" ($note -join '; ')))
}
$nCode = $null
if ($codeRows.Count) {
  $shown = @($codeRows | Select-Object -First $Cap)
  if ($codeRows.Count -gt $Cap) { $shown += New-NoteRow (Get-DisclosureText ($codeRows.Count - $Cap) 0 'sites') }
  $nCode = Add-Hop "in code ($unitName)" 'certain' $shown $PAL.codeBorder $PAL.codeFill $PAL.codeHdr -Side
  [void]$sb.AppendLine("  $nCtl -> $nCode [color=`"$($PAL.codeBorder)`", label=`" runtime `", fontcolor=`"$($PAL.codeBorder)`"];")
  if (@($rebound).Count -and $field.Count) {
    $script:rtNote = "$($field[0].prop) is re-assigned in code -- the DFM column $($field[0].col) may not be the one shown at runtime"
  }
}

# -- hops from the chain -----------------------------------------------------------------------
$stop = ''; $stopRows = New-Object System.Collections.ArrayList
$columnState = 'n/a'; $tableCol = ''
if (-not $ch) {
  $stop = "no datasource in the DFM for $ctlName$(if ($repoint.Count) { '; it is re-pointed in code (see the code rows) -- that right-hand side is not followed' } else { '' })"
} else {
  foreach ($h in $ch.Hops) {
    $last = ($h -eq $ch.Hops[-1])
    switch ($h.Hop) {
      'datasource' {
        if ($h.Grade -eq 'dangling') {
          $rows = @((New-Row $ch.DsName $dfm ([int]$h.Line) "$($ch.DsName) -- $([IO.Path]::GetFileName($dfm)):$($h.Line)" "the DFM names $($ch.Module), which is not in this project"))
          [void](Add-Hop 'datasource' 'dangling' $rows $PAL.warnBorder $PAL.warnFill $PAL.warnHdr)
          $stop = "the designer datasource $($ch.DsName) is dangling (module $($ch.Module) is declared nowhere in this index)$(if ($repoint.Count) { "; the control is re-pointed in code at runtime ($($repoint.Count) site(s)) -- that right-hand side is not followed" } else { '' })"
        } elseif ($h.Grade -in 'certain', 'by name') {
          $rows = @((New-Row $h.Label $h.File ([int]$h.Line) "$($h.Label) -- $([IO.Path]::GetFileName($h.File)):$($h.Line)" $(if ($h.Reason) { $h.Reason } else { "declared in $([IO.Path]::GetFileName($h.File))" })))
          [void](Add-Hop 'datasource' $h.Grade $rows $PAL.dsBorder $PAL.dsFill $PAL.dsHdr)
        } else { $stop = $h.Reason }
      }
      'dataset' {
        if ($h.Grade -in 'certain', 'inferred' -and -not ($last -and $ch.Grade -eq 'dfm-dataset')) {
          $site = @($ch.DataSetSites | Where-Object { $_.Line -eq $h.Line -and $_.Kind -eq 'assign' } | Select-Object -First 1)
          $rtn = $(if ($site.Count) { Get-RoutineShort $site[0].Routine $h.File } else { '' })
          $n = @($ch.DataSetSites | Where-Object { $_.Kind -ne 'dfm' }).Count
          $note = "in $rtn; $n DataSet site(s) in the unit scanned$(if ($h.Reason) { "; $($h.Reason)" })"
          [void](Add-Hop 'dataset' $h.Grade @((New-Row $h.Label $h.File ([int]$h.Line) "$($h.Label) -- $([IO.Path]::GetFileName($h.File)):$($h.Line)" $note)) $PAL.setBorder $PAL.setFill $PAL.setHdr)
        } elseif ($ch.Grade -eq 'dfm-dataset') {
          [void](Add-Hop 'dataset' 'certain' @((New-Row $h.Label $h.File ([int]$h.Line) "$($h.Label) -- $([IO.Path]::GetFileName($h.File)):$($h.Line)" 'set in the DFM')) $PAL.setBorder $PAL.setFill $PAL.setHdr)
          $stop = $h.Reason
        } else { $stop = $h.Reason }
      }
      'rhs-type' {
        if ($h.Grade -eq 'by name') {
          $kind = [string]$ch.RhsType.TypeKind
          [void](Add-Hop 'view model' 'by name' @((New-Row $h.Label $h.File ([int]$h.Line) "$($h.Label) ($kind) -- $([IO.Path]::GetFileName($h.File)):$($h.Line)" "$kind found by its name; $($ch.RhsType.Root) is a $($ch.RhsType.RootKind)")) $PAL.typeBorder $PAL.typeFill $PAL.typeHdr)
        } else { $stop = $h.Reason }
      }
      'table' {
        if ($ch.ResolvedTable) {
          $T = $sqlSet.Tables[$ch.ResolvedTable]
          $rows = New-Object System.Collections.ArrayList
          [void]$rows.Add((New-Row "table $($ch.ResolvedTable)" $h.File ([int]$h.Line) "'$($ch.ResolvedTable)' literal -- $([IO.Path]::GetFileName($h.File)):$($h.Line)" "[inferred] $($h.Reason)"))
          if ($ch.Grade -eq 'by-columns') {
            [void]$rows.Add((New-NoteRow "candidates: $($ch.CandidateTables -join ', ') -- tie broken by $($ch.BoundColumns.Count) bound column(s)"))
          }
          if ($field.Count) {
            $col = [string]$field[0].col
            $tableCol = "$($ch.ResolvedTable).$($col.ToUpperInvariant())"
            if ($T.Columns.Contains($col)) {
              $columnState = 'yes'
              $cline = Get-SqlColumnLine $T.Id $col $T.Line
              [void]$rows.Add((New-Row "column $($col.ToUpperInvariant())" $T.File $cline "$tableCol -- $([IO.Path]::GetFileName($T.File)):$cline" "[certain] a column of the newest of $($T.DeclCount) declaration(s), $([IO.Path]::GetFileName($T.File))"))
            } elseif ($T.OlderOnlyColumns.Contains($col.ToUpperInvariant())) {
              $columnState = 'older'
              $oc2 = $T.OlderOnlyColumns[$col.ToUpperInvariant()]
              [void]$rows.Add((New-Row "column $($col.ToUpperInvariant())" $oc2.File $oc2.Line "$tableCol -- $([IO.Path]::GetFileName($oc2.File)):$($oc2.Line)" "column ONLY in an older declaration ($([IO.Path]::GetFileName($oc2.File)))"))
            } else {
              $columnState = 'no'
              [void]$rows.Add((New-NoteRow "$($col.ToUpperInvariant()) is NOT a column of $($ch.ResolvedTable) in the scripts ($($T.ColumnNames.Count) columns in the newest declaration) -- computed, UI-only, or the scripts lag the schema"))
            }
            if ($script:rtNote) { [void]$rows.Add((New-NoteRow $script:rtNote)) }
            $title = $(if ($columnState -eq 'no') { "$($ch.ResolvedTable) (column absent)" } else { $tableCol })
          } else {
            [void]$rows.Add((New-NoteRow 'the control binds no column itself'))
            $title = $ch.ResolvedTable
          }
          [void](Add-Hop $title 'inferred' $rows.ToArray() $PAL.dbBorder $PAL.dbFill $PAL.dbHdr)
        } else {
          $stop = $h.Reason
          $list = @($(if ($ch.Grade -eq 'many' -and $ch.BoundColumns.Count -and $ch.ColumnMatch.Count -gt 1) { $ch.ColumnMatch } else { $ch.CandidateTables }))
          if ($ch.Grade -eq 'many') {
            $stop = $(if ($ch.BoundColumns.Count -and $ch.ColumnMatch.Count -gt 1) {
                        "ambiguous: $($ch.ColumnMatch -join ', ') share every bound column ($($ch.BoundColumns -join ', '))" }
                      elseif ($ch.BoundColumns.Count) {
                        "ambiguous: $($ch.CandidateTables.Count) candidate tables and none holds all $($ch.BoundColumns.Count) bound column(s)" }
                      else { "ambiguous: $($ch.CandidateTables.Count) candidate tables and no column is bound through $($ch.DsName) to tell them apart" })
          } elseif ($ch.RhsType -and $ch.RhsType.TypeKind -eq 'interface') {
            $stop = "[unresolved -- interface-typed view-model] $($h.Reason)"
          }
          foreach ($t in @($list | Select-Object -First $Cap)) {
            [void]$stopRows.Add((New-Row "candidate $t" $ch.RhsType.TypeFile $ch.CandidateLines[$t] "'$t' literal -- $([IO.Path]::GetFileName($ch.RhsType.TypeFile)):$($ch.CandidateLines[$t])" ''))
          }
          if ($list.Count -gt $Cap) { [void]$stopRows.Add((New-NoteRow (Get-DisclosureText ($list.Count - $Cap) 0 'candidates'))) }
        }
      }
    }
  }
}
if ($ch -and $ch.Grade -eq 'stale source') { $stop = "[stale source] $($ch.StopReason)" }
if ($stop) {
  $rows = @((New-NoteRow $stop)) + @($stopRows)
  $script:nodeId++
  $sid = "n$($script:nodeId)"
  [void](Add-RowCluster -Sb $sb -Cid "cluster_stop_$($script:nodeId)" -Nid $sid -Title 'chain stops here' -Subtitle '' `
           -Rows $rows -Border $PAL.stopBorder -Fill $PAL.stopFill -Hdr $PAL.stopHdr -RowInk $PAL.rowInk -LineInk $PAL.lineInk -FontSans $FontSans)
  [void]$chainNodes.Add([pscustomobject]@{ Nid = $sid; Grade = 'stop'; Title = 'chain stops here' })
}

# chain edges: dashed into anything that is not certain
for ($i = 1; $i -lt $chainNodes.Count; $i++) {
  $g = $chainNodes[$i].Grade
  $st = $(if ($g -eq 'stop') { 'dotted' } elseif ($g -in 'inferred', 'by name') { 'dashed' } else { 'solid' })
  $lb = $(if ($g -in 'inferred', 'by name', 'dangling') { " label=`" [$g] `"," } else { '' })
  [void]$sb.AppendLine("  $($chainNodes[$i-1].Nid) -> $($chainNodes[$i].Nid) [style=$st,$lb color=`"$($PAL.lineInk)`"];")
}

# -- the focus box: what was asked, and how much of the index this chain can see ---------------
$script:nodeId++
$fnid = "n$($script:nodeId)"
$ftbl = New-Object System.Text.StringBuilder
[void]$ftbl.Append('<TABLE BORDER="0" CELLBORDER="0" CELLSPACING="3" CELLPADDING="5">')
[void]$ftbl.Append("<TR><TD ALIGN=`"LEFT`" BGCOLOR=`"$($PAL.focusHdr)`"><FONT COLOR=`"#FFFFFF`" FACE=`"$FontSans`" POINT-SIZE=`"14`"><B> feeds-from &#183; $(ConvertTo-XmlText $sel) </B></FONT></TD></TR>")
Add-DisclosureRow $ftbl ("datasources in this index: $($stat.Ds) ($($stat.DsDfm) wired in DFM, $($stat.DsCode) in code); " +
  "one table: $($stat.DsOne); many: $($stat.DsMany + $stat.DsByCol) ($($stat.DsByCol) broken by bound columns); none: $($stat.DsNone); " +
  "chain stops before the table: $($stat.DsOther) -- measured per datasource") $PAL.lineInk
Add-DisclosureRow $ftbl ("per control: $ctlTotal field-bound controls; $ctlTable resolve to one table ($pct%), $([int]$oc['column']) of them to a column " +
  "that table has ($pctCol%); ambiguous $([int]$oc['ambiguous']), chain stops $([int]$oc['stops']), dangling $([int]$oc['dangling']), " +
  "no datasource in the DFM $([int]$oc['no-ds'])$(if ([int]$oc['stale']) { ", stale source $([int]$oc['stale'])" })$(if ([int]$oc['not-column']) { "; $([int]$oc['not-column']) resolve to a table without that column" })") $PAL.lineInk
Add-DisclosureRow $ftbl 'the table comes from string literals in the view model''s unit -- [inferred], dashed; never a fact' $PAL.lineInk
Add-DisclosureRow $ftbl "the column is checked against the SQL scripts ($($sqlSet.TableCount) tables) -- a script-derived schema, not the live one" $PAL.lineInk
if ($ch -and $ch.Dangling) { Add-DisclosureRow $ftbl "the DFM names $($ch.Module), which is not in this project" $PAL.lineInk }
[void]$ftbl.Append('</TABLE>')
[void]$sb.AppendLine("  subgraph cluster_focus_$($script:nodeId) {")
[void]$sb.AppendLine("    style=`"rounded,filled`"; color=`"$($PAL.focusBorder)`"; fillcolor=`"$($PAL.focusFill)`"; penwidth=2;")
[void]$sb.AppendLine('    label=""; margin=10;')
[void]$sb.AppendLine("    $fnid [label=<$($ftbl.ToString())>];")
[void]$sb.AppendLine('  }')
[void]$sb.AppendLine("  $fnid -> $nCtl [style=invis];")
[void]$sb.AppendLine('}')

if ([string]::IsNullOrWhiteSpace($OutDir)) { $OutDir = Join-Path $PSScriptRoot '..\scratch' }
$lay = Invoke-DotLayout $sb.ToString() $OutDir ('feedsfrom_' + ($sel -replace '[^A-Za-z0-9]', '_'))

[pscustomobject]@{
  Dot            = $lay.Dot
  Svg            = $lay.Svg
  Plain          = $lay.Plain
  Png            = $lay.Png
  Pdf            = $lay.Pdf
  Control        = $qualified
  ControlType    = $ctype
  Field          = $(if ($field.Count) { [string]$field[0].col } else { '' })
  DataSource     = $dsText
  DsOwner        = $owner
  Grade          = $(if ($ch) { $ch.Grade } else { 'no-ds' })
  HopGrades      = (@($chainNodes | ForEach-Object { $_.Grade }) -join '>')
  ChainRows      = $chainNodes.Count
  ResolvedTable  = $(if ($ch) { $ch.ResolvedTable } else { $null })
  TableColumn    = $tableCol
  ColumnExists   = $columnState
  Candidates     = $(if ($ch) { @($ch.CandidateTables) -join ',' } else { '' })
  AfterTieBreak  = $(if ($ch) { @($ch.ColumnMatch).Count } else { 0 })
  BoundColumns   = $(if ($ch) { @($ch.BoundColumns).Count } else { 0 })
  StopReason     = $stop
  Dangling       = [bool]($ch -and $ch.Dangling)
  RePointed      = @($repoint).Count
  RePointedAt    = (@($repoint | ForEach-Object { "$([IO.Path]::GetFileName($_.File)):$($_.Line)" }) -join ',')
  Rebound        = @($rebound).Count
  IndexDs        = $stat.Ds
  IndexDsDfm     = $stat.DsDfm
  IndexDsCode    = $stat.DsCode
  IndexDsOne     = $stat.DsOne
  IndexDsMany    = $stat.DsMany + $stat.DsByCol
  IndexDsByCol   = $stat.DsByCol
  IndexDsNone    = $stat.DsNone
  IndexDsOther   = $stat.DsOther
  Controls       = $ctlTotal
  CtlTable       = $ctlTable
  CtlColumn      = [int]$oc['column']
  CtlNotColumn   = [int]$oc['not-column']
  CtlAmbiguous   = [int]$oc['ambiguous']
  CtlStops       = [int]$oc['stops']
  CtlDangling    = [int]$oc['dangling']
  CtlNoDs        = [int]$oc['no-ds']
  CtlStale       = [int]$oc['stale']
  CoveragePct    = $pct
  ClickTargets   = $lay.Anchors
  Expected       = $anchored
  AllClickable   = ($lay.Anchors -ge $anchored)
}
