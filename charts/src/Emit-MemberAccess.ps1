<#
  Emit-MemberAccess.ps1 -- TWO catalogue questions, one emitter:

    -Mode write   `who-writes`   which routines ASSIGN this member
    -Mode read    `who-reads`    which routines READ it
    -Mode both    both wings at once (default)

  This is the first emitter whose SELECTION is a FIELD or a PROPERTY rather than
  a method, a unit or a form class.

  THE THING THAT LOOKS LIKE A DEFECT AND IS NOT
  ----------------------------------------------
  `member_accesses.accessor_symbol_id` does NOT mean "who touched the member".
  It names the ACCESSOR that implements the access -- `Connected` -> the field
  `FConnected`, `VERDICT` -> the methods `GetVERDICT`/`SetVERDICT` -- and it is
  NULL for every plain field access (3,355 of 3,355 measured on CLIENT). That
  looks exactly like an extraction hole and IS NOT ONE: it is a shipped owner
  ruling (docs\INBOX-property-refs-never-resolve.md, RETIRED, resolver
  1.3.0-alpha). Do not file it, and do not build the caller list on it.

  Ask the VERB instead. `query find-callers --name <member> --resolved --json`
  returns `caller_qname` (the enclosing routine), `mode` (read/write) and
  `confidence`, and is NOT subject to the sql verb's 200-row cap -- measured 602
  rows for `Connected` where the sql verb truncates at 200, silently.

  TWO QUERIES, NEVER N
  --------------------
  Step 1 asks the verb for the routines and the totals, uncapped.
  Step 2 asks SQL for the SITE anchors of the routines that survived the cap.
  A query per shown routine would be N process spawns for information the chart
  does not display.

  A ROW IS A ROUTINE; A SITE IS A LINE *AND A COLUMN*. BASICSF.pas:4072 holds
  THREE accesses to RChartSampleData.R -- reads at col 34 and col 51, a write at
  col 63 -- so sites are keyed by line+col. Keying by line alone would silently
  merge three facts into one.

  A ROUTINE THAT BOTH READS AND WRITES APPEARS ON BOTH SIDES. That is the honest
  answer and the same ruling touches-tables makes for a table in both wings;
  collapsing it would have to pick a direction, and there are two.
#>
[CmdletBinding()]
param(
  [Parameter(Mandatory)][string] $Qname,
  [Parameter(Mandatory)][string] $DbPath,   # NOT -Db: CmdletBinding aliases that to -Debug
  [ValidateSet('write', 'read', 'both')][string] $Mode = 'both',
  [int]    $Cap        = 20,
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

# New role, this emitter only: STATE. Neither caller blue, callee amber, focus
# teal, ui violet nor db rose -- a member is a different tier from all of them.
# Both wings share the hue; DIRECTION carries read vs write, not colour.
$PAL = @{
  stateBorder = '#0E7490'; stateFill = '#ECFEFF'; stateHdr = '#0E7490'
  focusBorder = '#0F766E'; focusFill = '#E2F1EF'; focusHdr = '#0F766E'
  rowInk      = '#1F2933'; lineInk   = '#8A94A6'; focusInk = '#0B3F39'
}

$question = switch ($Mode) { 'write' { 'who-writes' } 'read' { 'who-reads' } default { 'member-access' } }
Write-Host "${question}: $Qname (mode $Mode)"

# ---- 1. the selection, REFUSING an ambiguous name ----------------------------
# Throws "<Q> is not in this index" / "<Q> is ambiguous -- ..." /
# "<Q> is a method, not a field or property -- ask who-calls instead".
$sel  = Resolve-MemberSelection $Qname @('field', 'property')
$unit = Get-UnitName $sel.Path
Write-Host "  selection: $($sel.Qname) ($($sel.Kind)) $([IO.Path]::GetFileName($sel.Path)):$($sel.FocusLine)"

# ---- 2. step 1: the routines and the TOTALS, from the verb, UNCAPPED ---------
$verbRows = @()
# no match exits 1 with `[]` (measured) -- accepted; any other failure throws (R19)
$txt = Get-EngineText @('query', 'find-callers', '--name', $sel.Name, '--db', $DbPath, '--resolved', '--json') -AllowNoMatch
if ($txt) { $verbRows = @($txt | ConvertFrom-Json) }

# A bare --name can match members of SEVERAL classes, so filter to the one that
# was actually selected. Measured: `R` matched only RChartSampleData.R here, but
# 40% of bare field/property names on this index match more than one symbol.
$hits = @($verbRows | Where-Object { [string]$_.target_qname -eq $sel.Qname })

# BOTH totals are computed whatever -Mode renders, so the zero case can say
# "no write sites (602 reads)" instead of a bare and misleading "0".
$writeHits = @($hits | Where-Object { [string]$_.mode -eq 'write' })
$readHits  = @($hits | Where-Object { [string]$_.mode -eq 'read' })
$totalWrites = $writeHits.Count
$totalReads  = $readHits.Count

$showWrite = $Mode -in 'write', 'both'
$showRead  = $Mode -in 'read', 'both'

# Rank by site count, then by name so the order is stable run to run.
function Group-Routines($Hits) {
  @($Hits | Group-Object { [string]$_.caller_qname } |
    ForEach-Object { [pscustomobject]@{ Routine = $_.Name; Sites = $_.Count } } |
    Sort-Object @{ E = 'Sites'; Descending = $true }, @{ E = 'Routine'; Descending = $false })
}
# Assigned as statements, NOT as `$x = if (...) { @() }`: that form assigns
# $null when the branch yields an empty array, because an empty array enumerates
# to nothing on the output stream.
$writeRoutines = @()
$readRoutines  = @()
if ($showWrite) { $writeRoutines = @(Group-Routines $writeHits) }
if ($showRead)  { $readRoutines  = @(Group-Routines $readHits) }

# Distinct routines / sites across the RENDERED modes only.
$renderedHits = @()
if ($showWrite) { $renderedHits += $writeHits }
if ($showRead)  { $renderedHits += $readHits }
$distinctRoutines = @($renderedHits | Group-Object { [string]$_.caller_qname }).Count
$totalSites       = $renderedHits.Count

Write-Host ("  writes={0}  reads={1}  routines={2}  sites={3}" -f `
            $totalWrites, $totalReads, $distinctRoutines, $totalSites)

# ---- 3. rank, cap, and DISCLOSE ----------------------------------------------
# A chart with 598 rows is not a chart. The cap is a READABILITY decision and
# applies whatever the engine is willing to return -- but nothing is ever
# dropped silently.
$wTop = Get-TopRanked $writeRoutines $Cap 'Sites'
$rTop = Get-TopRanked $readRoutines  $Cap 'Sites'
if ($wTop.HiddenRows -or $rTop.HiddenRows) {
  Write-Host ("  capped at {0}: writers hide {1} routine(s)/{2} site(s), readers hide {3}/{4}" -f `
              $Cap, $wTop.HiddenRows, $wTop.HiddenSites, $rTop.HiddenRows, $rTop.HiddenSites)
}

# ---- 4. step 2: SITE anchors, SQL, for the SHOWN routines only ---------------
# Bounded by an IN-list, so it cannot approach the 200-row cap the way an
# unbounded access query would.
$shownNames = @(@($wTop.Shown | ForEach-Object { $_.Routine }) +
                @($rTop.Shown | ForEach-Object { $_.Routine })) | Sort-Object -Unique
$sites = @{}      # "routine|mode" -> @( @{Path;Line;Col} )
if ($shownNames.Count) {
  $encl = Get-EnclosingRoutineSql 'r'
  # MATCH THE MEMBER *OR* THE ACCESSOR IT IS THE BACKING FOR.
  #
  # The verb and this table attribute a property access to DIFFERENT symbols,
  # and selecting a backing field is where that shows. Measured on CLIENT:
  #   member_accesses rows for `Connected`  : 602 read, accessor = FConnected
  #   member_accesses rows for `FConnected` : 0
  #   find-callers --name FConnected        : 602 read, target = FConnected
  # The verb follows the owner ruling -- a field-backed accessor is a read/write
  # USE of that field -- so the table must be read the same way here, via
  # accessor_symbol_id. Matching only on the member left all 602 rows
  # unanchored; the cross-check below is what caught it.
  $sql = @"
SELECT $($encl.Select) AS routine, ma.mode AS mode, f.path AS path,
       r.start_line AS ln, r.start_col AS col
  FROM member_accesses ma
  JOIN refs r    ON r.id = ma.ref_id
  JOIN symbols m ON m.id = ma.member_symbol_id
  JOIN files f   ON f.id = r.file_id
  LEFT JOIN symbols acc ON acc.id = ma.accessor_symbol_id
  $($encl.Join)
 WHERE (m.qualified_name = '$(ConvertTo-SqlText $sel.Qname)'
        OR acc.qualified_name = '$(ConvertTo-SqlText $sel.Qname)')
   AND $($encl.Select) IN ($(ConvertTo-SqlInList $shownNames))
 ORDER BY r.start_line, r.start_col
"@
  $siteRows = Invoke-IndexQuery $sql "$question (site anchors)"
  # Truncation is SILENT, and a result landing EXACTLY on the cap is
  # indistinguishable from one that was cut. Refuse rather than render a short
  # answer as a whole one.
  if ($siteRows.Count -eq 200) {
    throw "${question}: the site query returned exactly 200 rows, which is the sql cap -- the answer may be silently short. Lower -Cap and re-ask."
  }
  foreach ($s in $siteRows) {
    $k = "$([string]$s.routine)|$([string]$s.mode)"
    if (-not $sites.ContainsKey($k)) { $sites[$k] = New-Object System.Collections.ArrayList }
    [void]$sites[$k].Add([pscustomobject]@{ Path = [string]$s.path; Line = [int]$s.ln; Col = [int]$s.col })
  }
}

# ---- 5. cross-check step 1 against step 2 ------------------------------------
# The verb and the SQL are two independent routes to the same fact. If the verb
# says 7 writes and the SQL finds 7 write sites, both agree. A mismatch is a
# FINDING to report, not a number to average -- so it is surfaced, not smoothed.
$mismatches = New-Object System.Collections.ArrayList
foreach ($pair in @(@{ Rows = $wTop.Shown; M = 'write' }, @{ Rows = $rTop.Shown; M = 'read' })) {
  foreach ($row in @($pair.Rows)) {
    $found = 0
    $k = "$($row.Routine)|$($pair.M)"
    if ($sites.ContainsKey($k)) { $found = $sites[$k].Count }
    if ($found -ne $row.Sites) {
      [void]$mismatches.Add("$($row.Routine) $($pair.M): verb $($row.Sites), sql $found")
    }
  }
}
$crossCheck = if ($mismatches.Count -eq 0) { 'agree' } else { "mismatch: $($mismatches -join '; ')" }
if ($mismatches.Count) {
  Write-Host "  FINDING: verb and sql disagree on $($mismatches.Count) routine(s) -- $($mismatches -join '; ')"
}

# ---- 6. rows -----------------------------------------------------------------
$unanchored = 0
function New-RoutineRow($Row, [string] $M) {
  $k = "$($Row.Routine)|$M"
  $ss = @()
  if ($sites.ContainsKey($k)) { $ss = @($sites[$k]) }
  $ru = Get-UnitName $(if ($ss.Count) { $ss[0].Path } else { $sel.Path })
  if (-not $ss.Count) {
    # The verb named this routine but SQL found no site for it. Anchor to the
    # member rather than to a guessed line, and SAY the site is not located.
    $script:unanchored++
    return [pscustomobject]@{
      Label = Get-ShortName $Row.Routine $ru
      Line  = $sel.FocusLine
      Href  = New-RowHref $sel.Path $sel.FocusLine
      Tip   = "$($Row.Routine) -- $($Row.Sites) $M site(s); no site location in the index, anchored to the member"
      Note  = 'site not located'
    }
  }
  # The tooltip names the SITES -- line:col, because three can share a line.
  $shownSites = @($ss | Select-Object -First 6 | ForEach-Object { "$($_.Line):$($_.Col)" })
  $more = if ($ss.Count -gt 6) { " (+$($ss.Count - 6) more)" } else { '' }
  [pscustomobject]@{
    Label = Get-ShortName $Row.Routine $ru
    Line  = $ss[0].Line                        # the FIRST site, not the decl line
    Href  = New-RowHref $ss[0].Path $ss[0].Line
    Tip   = "$($ss.Count) $M site$(if ($ss.Count -ne 1) { 's' }): $($shownSites -join ', ')$more"
    Note  = $(if ($ss.Count -gt 1) { "$($ss.Count) sites" } else { $null })
  }
}

function Build-Wing($Top, [string] $M, [string] $Noun) {
  $rows = New-Object System.Collections.ArrayList
  foreach ($r in @($Top.Shown)) { [void]$rows.Add((New-RoutineRow $r $M)) }
  $d = Get-DisclosureText $Top.HiddenRows $Top.HiddenSites $Noun
  if ($d) { [void]$rows.Add((New-NoteRow $d)) }
  , $rows.ToArray()
}
$writeRows = @()
$readRows  = @()
# Assigned DIRECTLY. Build-Wing returns `, $array` -- the same contract
# Invoke-IndexQuery carries -- so wrapping it in @() NESTS it: an empty wing
# became a one-element array holding an empty array, which rendered as a blank
# row and made dot refuse the label outright ("syntax error ... in label of
# node nw"). Loud here, silent the moment a wing has exactly one row.
if ($showWrite) { $writeRows = Build-Wing $wTop 'write' 'routines' }
if ($showRead)  { $readRows  = Build-Wing $rTop 'read'  'routines' }

# ---- 7. dot ------------------------------------------------------------------
$sb = New-Object System.Text.StringBuilder
[void]$sb.AppendLine('digraph memberaccess {')
[void]$sb.AppendLine('  rankdir=LR; bgcolor="transparent"; compound=true;')
[void]$sb.AppendLine('  nodesep=0.35; ranksep=1.3; splines=spline;')
[void]$sb.AppendLine("  graph [fontname=`"$FontSans`"];")
[void]$sb.AppendLine("  node  [shape=plaintext, fontname=`"$FontMono`", fontsize=14];")
[void]$sb.AppendLine("  edge  [fontname=`"$FontMono`", fontsize=11, color=`"$($PAL.lineInk)`", penwidth=1.5, arrowsize=0.8];")
[void]$sb.AppendLine('')

# WRITERS on the left, grouped by unit, drawn heavier than readers: a write is
# the stronger claim about shared state and the picture should say so.
$writePorts = @()
if ($writeRows.Count) {
  $writePorts = Add-RowCluster -Sb $sb -Cid 'cluster_writers' -Nid 'nw' `
                  -Title 'writers' -Subtitle "$($wTop.Total) routine$(if ($wTop.Total -ne 1) { 's' }), $totalWrites site$(if ($totalWrites -ne 1) { 's' })" `
                  -Rows $writeRows -Border $PAL.stateBorder -Fill $PAL.stateFill -Hdr $PAL.stateHdr `
                  -RowInk $PAL.rowInk -LineInk $PAL.lineInk -FontSans $FontSans -PenWidth 3
}

# focus: the MEMBER
[void]$sb.AppendLine('  subgraph cluster_focus {')
[void]$sb.AppendLine("    style=`"rounded,filled`"; color=`"$($PAL.focusBorder)`"; fillcolor=`"$($PAL.focusFill)`"; penwidth=3;")
[void]$sb.AppendLine('    label=""; margin=12;')
$fhref = New-RowHref $sel.Path $sel.FocusLine
$fhdr  = "<TR><TD ALIGN=`"LEFT`" BGCOLOR=`"$($PAL.focusHdr)`"><FONT COLOR=`"#FFFFFF`" FACE=`"$FontSans`" POINT-SIZE=`"14`"><B> $(ConvertTo-XmlText $unit) &#183; $($sel.Kind) </B></FONT></TD></TR>"
$ftip  = ConvertTo-XmlText "$($sel.Qname)  --  $([IO.Path]::GetFileName($sel.Path)):$($sel.FocusLine)"
$ftbl  = New-Object System.Text.StringBuilder
[void]$ftbl.Append("<TABLE BORDER=`"0`" CELLBORDER=`"0`" CELLSPACING=`"3`" CELLPADDING=`"7`">$fhdr")
[void]$ftbl.Append("<TR><TD HREF=`"$fhref`" TITLE=`"$ftip`"><FONT COLOR=`"$($PAL.focusInk)`" POINT-SIZE=`"18`"><B>$(ConvertTo-XmlText (Get-ShortName $sel.Qname $unit))</B></FONT></TD></TR>")

# ENGINE D13 (INBOX-defects-found-2026-09-23-rule-work.md): up to extractor 1.18
# `write` refs never got a symbol_id on CLIENT (32,909 of 32,909 on the 1.18
# clone). The verb above sees a write only when it is a MEMBER ACCESS
# (`Obj.FConnected :=`); a bare in-class assignment (`FConnected := True`) was an
# unbound `write` ref and invisible to it. Measured: who-writes FConnected said
# "no write sites" while uPipeClientConnection.pas holds four -- :164, :320,
# :455, :543.
#
# The disclosure is BY NAME, so it is never added to the writers wing or the
# totals: a same-name write in the DECLARING file is very probably this member,
# one elsewhere may be anything that shares the name. Both counts are printed.
#
# AFTER THE ENGINE FIX (extractor 1.19 / resolver 1.8, measured on the CLIENT
# clone 2026-09-24): 21,916 of 32,909 write refs are now BOUND -- and not one of
# them has a member_accesses row (0 of 21,916), which is what find-callers
# reports. So FConnected's four writes are now bound to FConnected itself, the
# by-name check below no longer sees them, and the verb still does not: the
# chart said "no write sites (602 reads)" -- a false absence. Those are counted
# as BOUND UNREPORTED: exact (the index binds them to THIS symbol), disclosed on
# the focus, never merged into the verb's totals or the writers wing. The
# by-name check stays for what 1.19 still leaves unbound (10,993 on CLIENT),
# e.g. a field written inside a `with` body (uPLANLIST.PAS:2544-2550).
$d13Same = 0; $d13Else = 0; $d13Lines = @(); $bound = 0; $boundLines = @()
if ($showWrite) {
  $nm = ConvertTo-SqlText $sel.Name
  $pth = ConvertTo-SqlText $sel.Path
  $boundWhere = "r.kind = 'write' AND r.symbol_id = $($sel.Id) AND NOT EXISTS (SELECT 1 FROM member_accesses ma WHERE ma.ref_id = r.id)"
  $bc = Invoke-IndexQuery "SELECT COUNT(*) AS c FROM refs r WHERE $boundWhere"
  $bound = [int]$bc[0].c
  if ($bound) {
    # Assigned FIRST, for the same reason as $lnRows below.
    $blRows = Invoke-IndexQuery @"
SELECT f.path AS path, r.start_line AS ln FROM refs r JOIN files f ON f.id = r.file_id
 WHERE $boundWhere
 ORDER BY (f.path <> '$pth'), f.path, r.start_line LIMIT 12
"@
    $boundLines = @($blRows | ForEach-Object {
      if ([string]::Equals([string]$_.path, $sel.Path, [StringComparison]::OrdinalIgnoreCase)) { ":$($_.ln)" }
      else { "$([IO.Path]::GetFileName([string]$_.path)):$($_.ln)" } })
  }
  $cnt = Invoke-IndexQuery @"
SELECT (f.path = '$pth') AS same, COUNT(*) AS c
  FROM refs r JOIN files f ON f.id = r.file_id
 WHERE r.kind = 'write' AND r.symbol_id IS NULL AND lower(r.name_text) = lower('$nm')
 GROUP BY (f.path = '$pth')
"@
  foreach ($c in $cnt) { if ([int]$c.same -eq 1) { $d13Same = [int]$c.c } else { $d13Else = [int]$c.c } }
  if ($d13Same) {
    # Assigned FIRST: piping Invoke-IndexQuery's `, $array` hands ForEach-Object
    # ONE item, the whole array, and `$_.ln` member-enumerates into one string.
    $lnRows = Invoke-IndexQuery @"
SELECT r.start_line AS ln FROM refs r JOIN files f ON f.id = r.file_id
 WHERE r.kind = 'write' AND r.symbol_id IS NULL AND lower(r.name_text) = lower('$nm')
   AND f.path = '$pth'
 ORDER BY r.start_line LIMIT 12
"@
    $d13Lines = @($lnRows | ForEach-Object { ":$($_.ln)" })
  }
}

# A zero in the RENDERED direction is a real answer, so say it with the other
# direction's number beside it -- a bare "0 writes" reads as "nothing uses this".
# Under D13 it is only a zero of RESOLVED writes, and says so; with bound writes
# the verb does not report, it is only a zero of what find-callers REPORTS.
if ($showWrite -and $totalWrites -eq 0) {
  $zeroWhat = $(if ($bound) { 'no write sites reported by find-callers' }
                elseif ($d13Same -or $d13Else) { 'no resolved write sites' } else { 'no write sites' })
  Add-DisclosureRow $ftbl "$zeroWhat ($totalReads read$(if ($totalReads -ne 1) { 's' }))" $PAL.lineInk
}
if ($bound) {
  $more = $(if ($bound -gt $boundLines.Count) { " (+$($bound - $boundLines.Count) more)" } else { '' })
  Add-DisclosureRow $ftbl ("$bound bare write(s) BOUND to $($sel.Name) in the index at $($boundLines -join ', ')$more -- " +
                           'find-callers does not report them (no member-access row), NOT counted above') $PAL.lineInk
}
if ($d13Same) {
  $more = $(if ($d13Same -gt $d13Lines.Count) { " (+$($d13Same - $d13Lines.Count) more)" } else { '' })
  Add-DisclosureRow $ftbl ("engine D13: $d13Same UNBOUND write(s) named $($sel.Name) in $([IO.Path]::GetFileName($sel.Path)) " +
                           "at $($d13Lines -join ', ')$more -- by name, NOT counted above") $PAL.lineInk
}
if ($d13Else) {
  Add-DisclosureRow $ftbl "engine D13: $d13Else more unbound write(s) of the name $($sel.Name) in other files -- may be other symbols" $PAL.lineInk
}
if ($showRead -and $totalReads -eq 0) {
  Add-DisclosureRow $ftbl "no read sites ($totalWrites write$(if ($totalWrites -ne 1) { 's' }))" $PAL.lineInk
}

# THE BACKING NOTE, and why it is a note rather than extra rows.
# A property and its backing are DIFFERENT SELECTIONS. who-writes on `Connected`
# reports writes THROUGH THE PROPERTY; it does not silently union the writes to
# `FConnected` inside the class, which would answer a question nobody asked and
# double-count the setter's own assignment. The note keeps the other answer
# reachable without inventing it.
#
# MEASURED CORRECTION to PLAN-next-five-questions.md: the plan says
# `symbols.prop_access` names the backing field. It does not -- it is an access
# MODE (`ro`, `rw`, NULL for fields). The backing is in
# `member_accesses.accessor_symbol_id` + `accessor_kind`, measured:
#   Connected -> FConnected        (accessor_kind = field)
#   VERDICT   -> Get/SetVERDICT    (accessor_kind = method)
$backing = @()
if ($sel.Kind -eq 'property') {
  $backing = Invoke-IndexQuery @"
SELECT DISTINCT acc.qualified_name AS acc, acc.name AS nm, ma.accessor_kind AS k
  FROM member_accesses ma
  JOIN symbols m   ON m.id = ma.member_symbol_id
  JOIN symbols acc ON acc.id = ma.accessor_symbol_id
 WHERE m.qualified_name = '$(ConvertTo-SqlText $sel.Qname)'
 ORDER BY acc.name
"@
  foreach ($b in $backing) {
    $hint = if ([string]$b.k -eq 'field') {
      "backed by $($b.nm) -- ask who-writes on it for writes that bypass this property"
    } else {
      "accessor $($b.nm) -- ask who-calls on it"
    }
    Add-DisclosureRow $ftbl $hint $PAL.lineInk
  }
}
[void]$ftbl.Append('</TABLE>')
[void]$sb.AppendLine("    focus [label=<$($ftbl.ToString())>];")
[void]$sb.AppendLine('  }')

$readPorts = @()
if ($readRows.Count) {
  $readPorts = Add-RowCluster -Sb $sb -Cid 'cluster_readers' -Nid 'nr' `
                 -Title 'readers' -Subtitle "$($rTop.Total) routine$(if ($rTop.Total -ne 1) { 's' }), $totalReads site$(if ($totalReads -ne 1) { 's' })" `
                 -Rows $readRows -Border $PAL.stateBorder -Fill $PAL.stateFill -Hdr $PAL.stateHdr `
                 -RowInk $PAL.rowInk -LineInk $PAL.lineInk -FontSans $FontSans
}

[void]$sb.AppendLine('')
# Writer -> member (the routine acts ON the member); member -> reader (the value
# flows OUT to the routine). A disclosure row gets NO edge: it is not a routine,
# and an edge would assert a relationship for a row that names none.
for ($i = 0; $i -lt $writeRows.Count; $i++) {
  if ([string]::IsNullOrWhiteSpace([string]$writeRows[$i].Href)) { continue }
  [void]$sb.AppendLine("  $($writePorts[$i]) -> focus [color=`"$($PAL.stateBorder)`", penwidth=2.2];")
}
for ($i = 0; $i -lt $readRows.Count; $i++) {
  if ([string]::IsNullOrWhiteSpace([string]$readRows[$i].Href)) { continue }
  [void]$sb.AppendLine("  focus -> $($readPorts[$i]) [color=`"$($PAL.stateBorder)`"];")
}
[void]$sb.AppendLine('}')

# ---- 8. lay out --------------------------------------------------------------
if ([string]::IsNullOrWhiteSpace($OutDir)) { $OutDir = Join-Path $PSScriptRoot '..\scratch' }
$base = ($sel.Qname -replace '[^A-Za-z0-9]', '_') + "_$Mode"
$lay  = Invoke-DotLayout $sb.ToString() $OutDir $base

# anchored rows + the focus. Disclosure rows carry no anchor by design.
$anchoredRows = @($writeRows | Where-Object { $_.Href }).Count + @($readRows | Where-Object { $_.Href }).Count
$expected = $anchoredRows + 1

[pscustomobject]@{
  Dot             = $lay.Dot
  Svg             = $lay.Svg
  Plain           = $lay.Plain
  Png             = $lay.Png
  Pdf             = $lay.Pdf
  Question        = $question
  Mode            = $Mode
  Kind            = $sel.Kind
  Resolved        = $sel.Qname
  Writes          = $totalWrites          # ALWAYS both totals, whatever -Mode drew
  Reads           = $totalReads
  Routines        = $distinctRoutines     # DISTINCT, across the rendered modes
  Sites           = $totalSites
  ShownWriters    = $wTop.Shown.Count
  ShownReaders    = $rTop.Shown.Count
  Shown           = $wTop.Shown.Count + $rTop.Shown.Count
  HiddenRoutines  = $wTop.HiddenRows + $rTop.HiddenRows
  HiddenSites     = $wTop.HiddenSites + $rTop.HiddenSites
  Unanchored      = $unanchored
  Backing         = @($backing | ForEach-Object { [string]$_.nm })
  CrossCheck      = $crossCheck
  D13SameFile     = $d13Same              # unbound same-name writes, declaring file
  D13Elsewhere    = $d13Else              # ... in every other file (weaker)
  BoundUnreported = $bound                # write refs BOUND to this symbol the verb does not report
  BoundLines      = ($boundLines -join ',')
  ClickTargets    = $lay.Anchors
  Expected        = $expected
  AllClickable    = ($lay.Anchors -ge $expected)
}
