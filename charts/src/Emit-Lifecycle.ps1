<#
  Emit-Lifecycle.ps1 -- the `lifecycle` question: which of a form's lifecycle
  stages are wired, which are written but never wired, and which do not exist.

  WHY THIS IS NOT event-wiring WITH A FILTER
  ------------------------------------------
  event-wiring answers "what fires what" and its rows are FACTS: every row comes
  from a `dfm_event`. This chart's most useful rows are the ones with NO fact --
  a stage nothing wires. So it cannot be a filtered view of the same query; it
  has to start from the SEQUENCE and ask what fills each slot.

  THREE STATES, NOT TWO (the design point)
  ----------------------------------------
  Measured on the CLIENT clone, 2026-09-23: FOUR form classes implement a
  `Form<Stage>` method that the DFM never wires --

      uMain.TfrmMAIN                              FormDestroy  pas:138,422
      SPCTplEdit.TfrmSPCTplEdit                   FormDestroy  pas:126,175
      DefineSerialNumbers.TfrmDefineSerialNumbers FormDestroy  pas:91,132
      DefineSerialNumbers.TfrmDefineSerialNumbers FormShow     pas:90,119

  Rendering those as "(not implemented)" would be a false statement about code
  that plainly exists, and it is the single easiest mistake this chart can make.
  So a stage is `wired`, `implemented but not wired`, or `absent`, and the three
  are drawn differently.

  The middle state is a NAME-CONVENTION INFERENCE and is labelled as one. There
  is no fact linking an unwired method to a stage -- that is what "unwired"
  means -- so `Form<Stage>` is the only available signal. Every other edge in
  this project comes from an index fact; this one does not, and the chart says
  so rather than letting it pass as measured.

  ORDER IS THE POINT, AND OnDeactivate IS NOT IN IT
  -------------------------------------------------
  Rows render in Delphi's real sequence, never alphabetically and never in DFM
  order. OnDeactivate is deliberately OUTSIDE the create->destroy spine: it is a
  focus-loss event that can fire many times, and fires after OnClose on hide. An
  earlier draft of the plan put it between OnActivate and OnCloseQuery, which
  would assert a sequence Delphi does not have. It is drawn as a dashed aside.

  SELECTION IS CHECKED BY HERITAGE, NOT BY ROW COUNT (N14)
  --------------------------------------------------------
  "Has zero dfm_event rows" is NOT the test for "is not a form": measured, 2 of
  the 60 form-rooted classes on CLIENT wire nothing at all, and "this is not a
  form" and "this form wires nothing" are different answers. The check walks
  type_ancestors instead. Note that every form root in this corpus is
  UNRESOLVED (TForm 50, TdxRibbonForm 8, TDataModule 2, all with
  ancestor_symbol_id NULL) because they are RTL/DevExpress and not in a project
  index -- so the match is by NAME, and the walk exists for project base forms,
  of which this corpus happens to have none (measured: 0 depth-2 form classes).
#>
[CmdletBinding()]
param(
  [Parameter(Mandatory)][string] $Form,     # form CLASS qname, e.g. uMain.TfrmMAIN
  [Parameter(Mandatory)][string] $DbPath,
  [string] $OutDir,
  [string] $Engine     = 'C:\Projects\Delphi-RAG-lint-wt\archify-ir\third_party\dll-win64\drag-lint.exe',
  [string] $Dot        = 'C:\Projects\GraphWiz\Graphviz-16.1.0-win64\bin\dot.exe',
  [string] $FontMono   = 'Consolas',
  [string] $FontSans   = 'Segoe UI'
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Emit-Common.ps1')

# Refuse a live corpus DB (see Get-CloneDb): charts run against the frozen clones.
$DbPath = Get-CloneDb $DbPath

# Three states need three readings at a glance. Teal = a fact, amber = code that
# exists but nothing points at, grey = absent. Violet is the UI tier, reused from
# event-wiring for the one row that is not part of the spine.
$PAL = @{
  wiredBorder  = '#0F766E'; wiredFill  = '#E2F1EF'; wiredHdr  = '#0F766E'
  unwiredBorder= '#B45309'; unwiredFill= '#FEF6EC'; unwiredHdr= '#B45309'
  absentBorder = '#9AA3AF'; absentFill = '#F3F4F6'; absentHdr = '#6B7280'
  asideBorder  = '#7C3AED'; asideFill  = '#F3EEFF'; asideHdr  = '#7C3AED'
  focusBorder  = '#3B5BDB'; focusFill  = '#EDF2FF'; focusHdr  = '#3B5BDB'
  rowInk       = '#1F2933'; lineInk    = '#8A94A6'
}

# The create->destroy spine, in Delphi's order. OnDeactivate is NOT here.
$SPINE = @('OnCreate', 'OnShow', 'OnActivate', 'OnCloseQuery', 'OnClose', 'OnDestroy')
# Rendered beside the spine, never inside it.
$ASIDE = @('OnDeactivate')
# The conventional method name for each stage. This is the inference, isolated
# in one place so it is obvious that it IS one.
$CONVENTION = @{
  OnCreate = 'FormCreate'; OnShow = 'FormShow'; OnActivate = 'FormActivate'
  OnDeactivate = 'FormDeactivate'; OnCloseQuery = 'FormCloseQuery'
  OnClose = 'FormClose'; OnDestroy = 'FormDestroy'
}
# Measured on CLIENT: these are the only roots any DFM-owning class has.
# TCustomForm/TFrame/TCustomFrame are carried for correctness, not because this
# corpus uses them.
$FORM_ROOTS = @('TForm', 'TCustomForm', 'TdxRibbonForm', 'TDataModule', 'TFrame', 'TCustomFrame')

Write-Host "lifecycle: $Form"

# ---- 1. resolve the selection -------------------------------------------------
$sel = Resolve-MemberSelection $Form @('class') -Hint 'lifecycle selects a FORM CLASS -- ask class-surface for a plain class'

# ---- 2. heritage check (N14) --------------------------------------------------
# Walk ordinal 0 upward. It terminates at the first UNRESOLVED ancestor, which in
# this corpus is always the first step, because every form root is RTL or
# DevExpress. The loop is bounded so a cyclic heritage cannot hang the emitter.
$chain = New-Object System.Collections.ArrayList
$cur = $sel.Id
for ($hop = 0; $hop -lt 12 -and $cur; $hop++) {
  $a = Invoke-IndexQuery "SELECT ancestor_name AS nm, ancestor_symbol_id AS sid FROM type_ancestors WHERE symbol_id = $cur AND ordinal = 0"
  if ($a.Count -eq 0) { break }
  [void]$chain.Add([string]$a[0].nm)
  $cur = $(if ($a[0].sid) { [int]$a[0].sid } else { $null })
}
$chainNames = @($chain.ToArray())
$isForm = @($chainNames | Where-Object { $FORM_ROOTS -contains $_ }).Count -gt 0
if (-not $isForm) {
  $seen = if ($chainNames.Count) { $chainNames -join ' -> ' } else { '(no ancestors recorded)' }
  throw ("$($sel.Qname) is not a form: its heritage is $seen, and none of " +
         "$($FORM_ROOTS -join '/') appears in it. Note this is a HERITAGE check -- " +
         'a real form that wires nothing is a different answer and still renders.')
}
Write-Host "  heritage: $($chainNames -join ' -> ')"

# ---- 3. what the DFM wires ----------------------------------------------------
# Filtered to the lifecycle event NAMES, not to an owner. The owner is kept so a
# row can say when a lifecycle-named event belongs to something other than the
# form itself (U4: dfm_event records ONE owner per handler).
$all = @($SPINE + $ASIDE)
$wiredRows = Invoke-IndexQuery @"
SELECT sf.dfm_event AS ev, s.id AS sid, s.name AS handler, s.qualified_name AS qname,
       s.start_line AS decl_line, s.impl_start_line AS impl_line, f.path AS pas
  FROM symbol_facts sf
  JOIN symbols s ON s.id = sf.symbol_id
  JOIN symbols c ON c.id = s.parent_id
  JOIN files f ON f.id = s.file_id
 WHERE c.qualified_name = '$(ConvertTo-SqlText $sel.Qname)'
   AND sf.dfm_event IS NOT NULL
   AND substr(sf.dfm_event, instr(sf.dfm_event, '.') + 1) IN ($(ConvertTo-SqlInList $all))
 ORDER BY sf.dfm_event
"@ 'lifecycle Q1 (wired stages)'

$wired = @{}
foreach ($w in $wiredRows) {
  $ev = [string]$w.ev
  # NOT $dot: that is the [string] $Dot parameter (PowerShell names are
  # case-insensitive), and assigning an int to it COERCES IT TO STRING, so
  # `$dot + 1` concatenates -- "7" + 1 = "71" -- and Substring throws a long way
  # from the cause. Same family as the $E/$e and $PAL/$pal traps.
  $dotAt = $ev.IndexOf('.')
  $stage = $(if ($dotAt -ge 0) { $ev.Substring($dotAt + 1) } else { $ev })
  $owner = $(if ($dotAt -ge 0) { $ev.Substring(0, $dotAt) } else { '' })
  # A form legitimately has only one handler per lifecycle stage; if the index
  # ever holds two, keep the first and say so rather than picking silently.
  if ($wired.ContainsKey($stage)) {
    Write-Host "  NOTE: $stage is wired twice ($($wired[$stage].Handler) and $($w.handler)); showing the first"
    continue
  }
  $wired[$stage] = [pscustomobject]@{
    Owner = $owner; Handler = [string]$w.handler; Qname = [string]$w.qname
    Sid = [int]$w.sid; Decl = [int]$w.decl_line
    Impl = $(if ($w.impl_line) { [int]$w.impl_line } else { [int]$w.decl_line })
    Pas = [string]$w.pas
  }
}

# ---- 4. what is implemented but wired by nothing -------------------------------
$convNames = @($CONVENTION.Values | Sort-Object -Unique)
$implRows = Invoke-IndexQuery @"
SELECT s.id AS sid, s.name AS m, s.qualified_name AS qname,
       s.start_line AS decl_line, s.impl_start_line AS impl_line, f.path AS pas
  FROM symbols s
  JOIN symbols c ON c.id = s.parent_id
  JOIN files f ON f.id = s.file_id
  LEFT JOIN symbol_facts sf ON sf.symbol_id = s.id AND sf.dfm_event IS NOT NULL
 WHERE c.qualified_name = '$(ConvertTo-SqlText $sel.Qname)'
   AND s.name IN ($(ConvertTo-SqlInList $convNames))
   AND sf.symbol_id IS NULL
 ORDER BY s.name
"@ 'lifecycle Q2 (implemented but unwired)'

$unwired = @{}
foreach ($m in $implRows) {
  $stage = @($CONVENTION.Keys | Where-Object { $CONVENTION[$_] -eq [string]$m.m })[0]
  if (-not $stage) { continue }
  $unwired[$stage] = [pscustomobject]@{
    Handler = [string]$m.m; Qname = [string]$m.qname
    Decl = [int]$m.decl_line
    Impl = $(if ($m.impl_line) { [int]$m.impl_line } else { [int]$m.decl_line })
    Pas = [string]$m.pas
  }
}

# ---- 5. resolve each stage to exactly one of three states ----------------------
# A stage that is wired AND has a conventionally-named orphan is a real oddity
# worth a note -- the wired handler is the answer, but there is a FormX sitting
# unused beside it.
$oddities = New-Object System.Collections.ArrayList
function Get-Stage([string] $stage) {
  if ($wired.ContainsKey($stage)) {
    if ($unwired.ContainsKey($stage)) {
      [void]$oddities.Add("$stage is wired to $($wired[$stage].Handler), but $($unwired[$stage].Handler) also exists and is wired to nothing")
    }
    $w = $wired[$stage]
    return [pscustomobject]@{
      Stage = $stage; State = 'wired'; Handler = $w.Handler; Qname = $w.Qname
      Line = $w.Impl; Pas = $w.Pas; Owner = $w.Owner
    }
  }
  if ($unwired.ContainsKey($stage)) {
    $u = $unwired[$stage]
    return [pscustomobject]@{
      Stage = $stage; State = 'unwired'; Handler = $u.Handler; Qname = $u.Qname
      Line = $u.Impl; Pas = $u.Pas; Owner = ''
    }
  }
  [pscustomobject]@{
    Stage = $stage; State = 'absent'; Handler = ''; Qname = ''
    Line = 0; Pas = ''; Owner = ''
  }
}

$spineStates = @($SPINE | ForEach-Object { Get-Stage $_ })
$asideStates = @($ASIDE | ForEach-Object { Get-Stage $_ })

$nWired   = @($spineStates + $asideStates | Where-Object { $_.State -eq 'wired' }).Count
$nUnwired = @($spineStates + $asideStates | Where-Object { $_.State -eq 'unwired' }).Count
$nAbsent  = @($spineStates + $asideStates | Where-Object { $_.State -eq 'absent' }).Count

$pas = $(if ($wiredRows.Count) { [string]$wiredRows[0].pas } elseif ($implRows.Count) { [string]$implRows[0].pas } else { $sel.Path })
$unit = Get-UnitName $pas

Write-Host ("  stages: wired={0}  implemented-not-wired={1}  absent={2}  (of {3})" -f `
            $nWired, $nUnwired, $nAbsent, ($SPINE.Count + $ASIDE.Count))
foreach ($o in $oddities) { Write-Host "  NOTE: $o" }

# ---- 6. dot --------------------------------------------------------------------
# Top-to-bottom, because the chart's claim IS the order.
$sb = New-Object System.Text.StringBuilder
[void]$sb.AppendLine('digraph lifecycle {')
[void]$sb.AppendLine('  rankdir=TB; bgcolor="transparent"; compound=true;')
[void]$sb.AppendLine('  nodesep=0.35; ranksep=0.45; splines=spline;')
[void]$sb.AppendLine("  graph [fontname=`"$FontSans`"];")
[void]$sb.AppendLine("  node  [shape=plaintext, fontname=`"$FontMono`", fontsize=14];")
[void]$sb.AppendLine("  edge  [fontname=`"$FontMono`", fontsize=11, color=`"$($PAL.lineInk)`", penwidth=1.4, arrowsize=0.7];")
[void]$sb.AppendLine('')

$nodeId = 0
$clusters = 0
$anchoredRows = 0

function Add-StageCluster($st) {
  $script:nodeId++; $script:clusters++
  $nid = "n$script:nodeId"
  switch ($st.State) {
    'wired' {
      $border = $PAL.wiredBorder; $fill = $PAL.wiredFill; $hdr = $PAL.wiredHdr
      $style = 'rounded,filled'
      $rows = @([pscustomobject]@{
        Label = $st.Handler; Line = $st.Line
        Href  = New-RowHref $st.Pas $st.Line
        Tip   = "$($st.Qname)  --  wired in the DFM as $($st.Owner).$($st.Stage); body at $([IO.Path]::GetFileName($st.Pas)):$($st.Line)"
        Note  = $(if ($st.Owner) { "wired by $($st.Owner)" } else { 'wired' })
      })
      $script:anchoredRows++
    }
    'unwired' {
      $border = $PAL.unwiredBorder; $fill = $PAL.unwiredFill; $hdr = $PAL.unwiredHdr
      $style = 'rounded,filled,dashed'
      $rows = @([pscustomobject]@{
        Label = $st.Handler; Line = $st.Line
        Href  = New-RowHref $st.Pas $st.Line
        Tip   = "$($st.Qname)  --  IMPLEMENTED at $([IO.Path]::GetFileName($st.Pas)):$($st.Line) but NOTHING in the DFM wires it. Matched by name convention, not by an index fact."
        Note  = 'implemented, NOT wired'
      })
      $script:anchoredRows++
      $rows += (New-NoteRow 'matched by name convention, not a fact')
    }
    default {
      $border = $PAL.absentBorder; $fill = $PAL.absentFill; $hdr = $PAL.absentHdr
      $style = 'rounded,filled,dashed'
      $rows = @(New-NoteRow '(not implemented)')
    }
  }
  $ports = Add-RowCluster -Sb $script:sb -Cid "cluster_stage_$script:nodeId" -Nid $nid `
             -Title $st.Stage -Subtitle $st.State -Rows $rows `
             -Border $border -Fill $fill -Hdr $hdr `
             -RowInk $PAL.rowInk -LineInk $PAL.lineInk -FontSans $FontSans -Style $style
  [pscustomobject]@{ Nid = $nid; Port = $ports[0] }
}

$spineNodes = @($spineStates | ForEach-Object { Add-StageCluster $_ })

# the spine arrows -- this is the assertion the chart makes
[void]$sb.AppendLine('')
for ($i = 0; $i -lt $spineNodes.Count - 1; $i++) {
  [void]$sb.AppendLine("  $($spineNodes[$i].Port) -> $($spineNodes[$i + 1].Port) [color=`"$($PAL.wiredBorder)`", penwidth=1.6];")
}

# the aside -- deliberately NOT joined to the spine
foreach ($st in $asideStates) {
  $n = Add-StageCluster $st
  [void]$sb.AppendLine("  $($spineNodes[0].Port) -> $($n.Port) [style=invis];")
}

# focus box: what was selected, and the caveats that apply to the whole picture
$nodeId++; $clusters++
$fnid = "n$nodeId"
$ftbl = New-Object System.Text.StringBuilder
[void]$ftbl.Append('<TABLE BORDER="0" CELLBORDER="0" CELLSPACING="3" CELLPADDING="5">')
[void]$ftbl.Append("<TR><TD ALIGN=`"LEFT`" BGCOLOR=`"$($PAL.focusHdr)`"><FONT COLOR=`"#FFFFFF`" FACE=`"$FontSans`" POINT-SIZE=`"14`"><B> $(ConvertTo-XmlText $sel.Qname) </B></FONT></TD></TR>")
Add-DisclosureRow $ftbl "$unit  &#183;  $($chainNames -join ' -> ')" $PAL.lineInk
Add-DisclosureRow $ftbl "wired $nWired  &#183;  implemented but not wired $nUnwired  &#183;  absent $nAbsent" $PAL.lineInk
Add-DisclosureRow $ftbl 'OnDeactivate is drawn apart: it is focus loss, not a pre-close stage' $PAL.lineInk
if ($nUnwired -gt 0) {
  Add-DisclosureRow $ftbl 'dashed amber = a Form<Stage> method exists that no DFM wires (name convention)' $PAL.lineInk
}
foreach ($o in $oddities) { Add-DisclosureRow $ftbl $o $PAL.lineInk }
[void]$ftbl.Append('</TABLE>')
[void]$sb.AppendLine("  subgraph cluster_focus_$nodeId {")
[void]$sb.AppendLine("    style=`"rounded,filled`"; color=`"$($PAL.focusBorder)`"; fillcolor=`"$($PAL.focusFill)`"; penwidth=2;")
[void]$sb.AppendLine('    label=""; margin=10;')
[void]$sb.AppendLine("    $fnid [label=<$($ftbl.ToString())>];")
[void]$sb.AppendLine('  }')
[void]$sb.AppendLine("  $fnid -> $($spineNodes[0].Port) [style=invis];")
[void]$sb.AppendLine('}')

# ---- 7. lay out -----------------------------------------------------------------
if ([string]::IsNullOrWhiteSpace($OutDir)) { $OutDir = Join-Path $PSScriptRoot '..\scratch' }
$base = 'lifecycle_' + ($sel.Qname -replace '[^A-Za-z0-9]', '_')
$lay = Invoke-DotLayout $sb.ToString() $OutDir $base

[pscustomobject]@{
  Dot          = $lay.Dot
  Svg          = $lay.Svg
  Plain        = $lay.Plain
  Png          = $lay.Png
  Pdf          = $lay.Pdf
  Form         = $sel.Qname
  Heritage     = ($chainNames -join ' -> ')
  Wired        = $nWired
  NotWired     = $nUnwired
  Absent       = $nAbsent
  Stages       = $SPINE.Count + $ASIDE.Count
  Oddities     = $oddities.Count
  Clusters     = $clusters
  ClickTargets = $lay.Anchors
  Expected     = $anchoredRows
  AllClickable = ($lay.Anchors -ge $anchoredRows)
}
