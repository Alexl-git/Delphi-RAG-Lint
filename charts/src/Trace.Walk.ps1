<#
  Trace.Walk.ps1 -- the index-facing half of the round-trip question. Dot-sourced
  by Emit-RoundTrip.ps1 AFTER Emit-Common.ps1 and Trace.FormA.ps1; every function
  reads $DbPath / $Engine dynamically from the caller's scope, like Emit-Common.

  Part 1 (this task): the ANCHOR. From a -Target (spec section 3: a form control,
  its interface field, a TField variable, or TABLE.COLUMN) to the data anchor
  (dataset field, column, table, TABLE.COLUMN), as graded trace steps. A selection
  that is not data-bound or a chain that cannot reach a table ends in Stop + a
  StopAnchor and NO step for the stop itself -- the emitter writes ONE numbered
  STOPS from them, never an empty report (AC-13; ruling P3). A stale file on the
  way sets StaleFile and the emitter REFUSES (AC-14).
  Parts 2-4 (the shim, the walk, the server) are appended by their tasks.
#>

function Get-TraceAnchorText([string] $Path, [int] $Line) { "$([IO.Path]::GetFileName($Path)):$Line" }

# literal-derived text made safe for a step line or a note (the writer refuses ' @',
# ' [' and ' -- '; a note refuses '; ', its separator). SPACE-ANCHORED on purpose: it
# is applied to source-derived labels (a re-point RHS), and an indexer `Fields[0]` must
# be quoted as written (ruling T3-M1) -- only what the writer refuses is touched.
function ConvertTo-TraceWord([string] $s, [int] $Max = 72) {
  $t = (([string]$s) -replace '\s+', ' ').Trim() -replace ' -- ', ' - ' -replace ' @', ' at ' -replace ' \[', ' (' -replace '"', "'" -replace '; ', ', '
  $(if ($t.Length -gt $Max) { $t.Substring(0, $Max - 3) + '...' } else { $t })
}

# a hop's reason as a step note: the note separator '; ' cannot appear inside one
function ConvertTo-TraceNoteText([string] $s) { ([string]$s) -replace '; ', ', ' }

# SQL: the symbol $A's declared type is a dataset class. A SUFFIX match: `LIKE 'T%Table%'`
# also took `TcxGridDBTableView` (Blueprint4.pas:2331 names 'OPERAT' beside the grid view).
function Get-DataSetTypeSql([string] $A = 's') {
  "(TRIM($A.signature) LIKE 'T%MemTable' OR TRIM($A.signature) LIKE 'T%Query' OR TRIM($A.signature) LIKE 'T%Table' OR TRIM($A.signature) LIKE 'T%DataSet')"
}

function New-AnchorResult {
  [pscustomobject]@{ Items = (New-Object System.Collections.ArrayList); DataSet = $null; Table = ''; Column = ''; TableColumn = ''
                     Stop = ''; StopAnchor = ''; StaleFile = ''; Grades = @() }
}

# The table beside the dataset (a literal of the SQL table set on a line that reads
# the dataset field), then the column in the SQL index. Shared by every anchor form.
function Complete-AnchorFromDataSet($R, $Ds, [string] $Col, $SqlSet, [hashtable] $SourceOverride) {
  $R.DataSet = $Ds
  [void]$R.Items.Add((New-TraceStep 'step' "BINDS $($Ds.Name) : $($Ds.Type)" (Get-TraceAnchorText $Ds.File $Ds.Line) '' '' 'the anchor dataset'))
  $lit = Invoke-IndexQuery @"
SELECT sl.text AS t, MIN(sl.start_line) AS line, COUNT(*) AS n FROM string_literals sl
 WHERE sl.file_id = $($Ds.Fid) AND sl.kind = 'literal' AND sl.text IN ($(ConvertTo-SqlInList $SqlSet.Names))
   AND EXISTS (SELECT 1 FROM refs r WHERE r.file_id = sl.file_id AND r.start_line = sl.start_line AND r.name_text = '$(ConvertTo-SqlText $Ds.Name)')
 GROUP BY sl.text ORDER BY MIN(sl.start_line), sl.text
"@ 'round-trip (table literals)'
  if ($lit.Count -ne 1) {
    $R.Stop = $(if ($lit.Count -eq 0) { "no upper-case table-name literal shares a line with $($Ds.Name) in $(Get-UnitName $Ds.File) -- the table cannot be inferred" }
                else { "$($lit.Count) tables share a line with $($Ds.Name) in $(Get-UnitName $Ds.File) ($((@($lit | ForEach-Object { [string]$_.t })) -join ', ')) -- cannot tell which" })
    $R.StopAnchor = Get-TraceAnchorText $Ds.File $Ds.Line
    return $R
  }
  $R.Table = [string]$lit[0].t
  $encl = Invoke-IndexQuery "SELECT e.qualified_name AS q FROM refs r JOIN symbols e ON e.id = r.enclosing_symbol_id WHERE r.file_id = $($Ds.Fid) AND r.start_line = $([int]$lit[0].line) AND r.name_text = '$(ConvertTo-SqlText $Ds.Name)' LIMIT 1"
  $rn = $(if ($encl.Count) { (([string]$encl[0].q) -split '\.')[-1] } else { '' })
  [void]$R.Items.Add((New-TraceStep 'step' "READS $($R.Table)" (Get-TraceAnchorText $Ds.File ([int]$lit[0].line)) 'inferred' $rn "the table literal beside $($Ds.Name) on $($lit[0].n) line(s)" 'E4'))
  if (-not $Col) { $R.Stop = "$($Ds.Name) reaches $($R.Table) but the selection binds no column"; $R.StopAnchor = Get-TraceAnchorText $Ds.File $Ds.Line; return $R }
  $R.Column = $Col.ToUpperInvariant()
  $R.TableColumn = "$($R.Table).$($R.Column)"
  $cs = Get-SqlColumnState $SqlSet $R.Table $Col $SourceOverride
  if ($cs.IsColumn) {
    # the label is GENERATED text whose grade tags are bracketed (`[certain] a column of ...`); as
    # a note they read `(certain)` -- rewritten here, at their source, never in the shared sanitiser
    $lbl = ([string]$cs.Label) -replace '\[([^\]]*)\]', '($1)'
    [void]$R.Items.Add((New-TraceStep 'step' "READS $($R.TableColumn)" (Get-TraceAnchorText $cs.File ([int]$cs.Line)) 'inferred' '' (ConvertTo-TraceWord "column $($R.Column) of $($R.Table): $lbl") 'E4'))
  } else {
    $R.Stop = "$($R.TableColumn): $($cs.Label)"
    $R.StopAnchor = $R.Items[$R.Items.Count - 1].Anchor
    $R.TableColumn = ''
  }
  $R
}

function Resolve-AnchorFromControl([string] $Form, [string] $Ctl, $R, $SqlSet, [hashtable] $SourceOverride) {
  $forms = Invoke-IndexQuery "SELECT s.file_id AS fid, f.path AS path FROM symbols s JOIN files f ON f.id = s.file_id WHERE s.kind = 'form' AND UPPER(s.name) = UPPER('$(ConvertTo-SqlText $Form)')"
  if ($forms.Count -eq 0) { throw "round-trip: no form or data module named $Form in this index" }
  $cands = Invoke-IndexQuery @"
SELECT c.id AS id, c.name AS name, c.qualified_name AS q, c.signature AS sig, c.parent_id AS pid, c.start_line AS line, c.file_id AS fid, f.path AS path
  FROM symbols c JOIN files f ON f.id = c.file_id
 WHERE c.kind = 'component' AND c.file_id IN ($((@($forms | ForEach-Object { [int]$_.fid })) -join ',')) AND UPPER(c.name) = UPPER('$(ConvertTo-SqlText $Ctl)')
"@
  if ($cands.Count -eq 0) { throw "round-trip: no component named $Ctl on $Form" }
  if ($cands.Count -gt 1) { throw "round-trip: $Form.$Ctl names $($cands.Count) components ($((@($cands | ForEach-Object { [string]$_.q })) -join ', '))" }
  $C = $cands[0]; $cid = [int]$C.id; $dfm = [string]$C.path; $fid = [int]$C.fid
  $cpid = $(if ($C.pid) { [int]$C.pid } else { 0 })
  $short = "$Form.$([string]$C.name)"
  $fb = Invoke-IndexQuery "SELECT owner_name AS prop, text AS col, start_line AS line FROM string_literals WHERE kind = 'dfm-prop' AND symbol_id = $cid AND owner_name IN ('DataBinding.FieldName','DataBinding.DataField','DataField') ORDER BY start_line"
  $dsRow = Invoke-IndexQuery "SELECT $(Get-ControlDataSourceSql 'sl' 'c') AS ds FROM symbols c JOIN (SELECT $fid AS file_id) sl WHERE c.id = $cid"
  $dsText = $(if ($dsRow.Count) { [string]$dsRow[0].ds } else { '' })
  if (-not $fb.Count -or -not $dsText) {
    $R.Stop = "$short ($([string]$C.sig)) is not data-bound: $(if (-not $fb.Count -and -not $dsText) { 'no field binding and no DataSource' } elseif (-not $fb.Count) { 'no field binding' } else { 'no DataSource' }) on it or its two enclosing components in the DFM"
    $R.StopAnchor = Get-TraceAnchorText $dfm ([int]$C.line)
    return $R
  }
  $col = [string]$fb[0].col
  $own = Invoke-IndexQuery @"
SELECT d.symbol_id AS sid, d.owner_name AS prop, d.start_line AS line, s.name AS owner
  FROM string_literals d JOIN symbols s ON s.id = d.symbol_id
 WHERE d.kind = 'dfm-prop' AND d.file_id = $fid AND d.owner_name IN ('DataSource','DataBinding.DataSource','DataController.DataSource')
   AND d.text = '$(ConvertTo-SqlText $dsText)'
   AND d.symbol_id IN ($cid, $cpid, (SELECT g.parent_id FROM symbols g WHERE g.id = $cpid))
 ORDER BY d.start_line
"@
  # nearest first, as Get-ControlDataSourceSql picked it: the control, its parent, its grandparent
  $dsProp = @($own | Sort-Object { if ([int]$_.sid -eq $cid) { 0 } elseif ($cpid -and [int]$_.sid -eq $cpid) { 1 } else { 2 } })[0]
  $s1 = New-TraceStep 'step' "BINDS $([string]$C.name) : $([string]$C.sig) ONTO $col" (Get-TraceAnchorText $dfm ([int]$fb[0].line)) '' '' ([string]$fb[0].prop)
  $ch = Get-DataSourceChain $dfm $dsText $SqlSet $SourceOverride
  $owner = [string]$dsProp.owner
  $via = $(if ([int]$dsProp.sid -ne $cid) { "$owner.$([string]$dsProp.prop)" } else { [string]$dsProp.prop })
  $viaNote = $(if ($ch.Dangling) { "dangling: module $($ch.Module) is declared nowhere in this index" } else { '' })
  [void]$s1.Children.Add((New-TraceFacet 'VIA' "$via = $dsText" (Get-TraceAnchorText $dfm ([int]$dsProp.line)) $viaNote))
  [void]$R.Items.Add($s1)
  # a `:= nil` re-point UN-binds the control (Blueprint4.pas:3213, in FormClose) -- it feeds
  # nothing, as Get-DataSourceChain skips a nil DataSet assignment; a stale row has no RHS to test
  $rp = @($ch.RePointedAt | Where-Object { $_.Control -eq $owner -and ($_.Stale -or $_.Rhs -ne 'nil') })
  if ($ch.Grade -eq 'dangling') {
    # a stale form unit hides the re-point (its receiver may be lost, P29): refuse, naming THAT file
    $stRp = @($rp | Where-Object { $_.Stale })
    if ($stRp.Count -or ($ch.PasFile -and -not $rp.Count -and -not (Test-SourceFresh $ch.PasFile $SourceOverride))) {
      $sf = $(if ($stRp.Count) { [string]$stRp[0].File } else { [string]$ch.PasFile })
      $R.StaleFile = $sf
      $R.Stop = "$([IO.Path]::GetFileName($sf)) differs from the indexed copy -- the code re-point of $owner is not read"
      $R.StopAnchor = $s1.Anchor
      return $R
    }
    # T1-C2: the chain starts from the ONE assignment that re-points the control; several
    # with different right-hand sides is a choice the index cannot make -- a named stop
    $rhsSet = @($rp | ForEach-Object { ([string]$_.Rhs -replace '\s', '').ToUpperInvariant() } | Sort-Object -Unique)
    if ($rhsSet.Count -gt 1) {
      $R.Stop = "$owner is re-pointed at $($rp.Count) sites with $($rhsSet.Count) different right-hand sides ($((@($rp | ForEach-Object { "$([IO.Path]::GetFileName([string]$_.File)):$($_.Line)" })) -join ', ')) -- cannot tell which feeds the grid"
      $R.StopAnchor = $s1.Anchor
      return $R
    }
  }
  if ($ch.Grade -eq 'dangling' -and $rp.Count) {
    $rc = Get-RePointChain $rp[0] $SourceOverride
    foreach ($h in $rc.Hops) {
      $verb = $(switch ($h.Hop) { 're-point' { 'SETS' } 'member' { 'READS' } 'accessor' { 'CALLS' } 'field' { 'READS' } 'dataset' { 'SETS' } })
      $grade = $(if ($h.Grade -in 'by name', 'inferred') { $h.Grade } else { '' })
      [void]$R.Items.Add((New-TraceStep 'step' "$verb $(ConvertTo-TraceWord $h.Label 90)" (Get-TraceAnchorText $h.File $h.Line) $grade $h.Routine (ConvertTo-TraceNoteText $h.Reason) $h.Ask))
    }
    $last = $R.Items[$R.Items.Count - 1].Anchor
    if ($rc.StaleFile) { $R.StaleFile = $rc.StaleFile; $R.Stop = $rc.StopReason; $R.StopAnchor = $last; return $R }
    if ($rc.StopReason) { $R.Stop = $rc.StopReason; $R.StopAnchor = $last; return $R }
    return (Complete-AnchorFromDataSet $R $rc.DataSet $col $SqlSet $SourceOverride)
  }
  if ($ch.Grade -eq 'stale source') {
    # the file that differs is the one holding the DataSet sites -- the datasource's unit
    $sf = @($ch.DataSetSites | Where-Object { $_.Kind -eq 'stale' } | ForEach-Object { [string]$_.File })
    $R.StaleFile = $(if ($sf.Count) { $sf[0] } else { [string]$ch.PasFile }); $R.Stop = $ch.StopReason; $R.StopAnchor = $s1.Anchor; return $R
  }
  $assign = @($ch.DataSetSites | Where-Object { $_.Kind -eq 'assign' -and $_.Rhs -ne 'nil' })
  if (-not $assign.Count -or -not $ch.RhsType -or -not $ch.RhsType.TypeFile) {
    $R.Stop = $(if ($ch.StopReason) { $ch.StopReason } else { "the datasource $dsText names no dataset field this index can follow (chain grade $($ch.Grade))" })
    $R.StopAnchor = $s1.Anchor
    return $R
  }
  foreach ($h in $ch.Hops) {
    if ($h.Hop -eq 'table') { continue }     # the table is re-derived beside the DATASET, not from the unit's literals
    $verb = $(switch ($h.Hop) { 'datasource' { 'READS' } 'dataset' { 'SETS' } 'rhs-type' { 'READS' } })
    $grade = $(if ($h.Grade -in 'by name', 'inferred') { $h.Grade } else { '' })
    [void]$R.Items.Add((New-TraceStep 'step' "$verb $(ConvertTo-TraceWord $h.Label 90)" (Get-TraceAnchorText $h.File $h.Line) $grade '' (ConvertTo-TraceNoteText $h.Reason) $(if ($grade) { 'E4' } else { '' })))
  }
  $a0 = $assign[0]
  $dsName = (($a0.Rhs -replace '^Self\.', '') -split '\.')[-1]
  $tf = Invoke-IndexQuery "SELECT s.id AS id FROM symbols s JOIN files f ON f.id = s.file_id WHERE f.path = '$(ConvertTo-SqlText $ch.RhsType.TypeFile)' AND s.kind IN ('class','interface') AND UPPER(s.name) = UPPER('$(ConvertTo-SqlText $ch.RhsType.TypeName)')"
  $dsRow = $(if ($tf.Count -eq 1) { Invoke-IndexQuery "SELECT s.id AS id, s.name AS name, s.signature AS sig, s.start_line AS line, f.path AS path, s.file_id AS fid, s.parent_id AS pid FROM symbols s JOIN files f ON f.id = s.file_id WHERE s.parent_id = $([int]$tf[0].id) AND s.name = '$(ConvertTo-SqlText $dsName)' AND s.kind IN ('field','property')" } else { , @() })
  if ($dsRow.Count -ne 1) { $R.Stop = "the dataset $($a0.Rhs) (assigned at :$($a0.Line)) is not a field or property of $($ch.RhsType.TypeName) in this index"; $R.StopAnchor = Get-TraceAnchorText $a0.File $a0.Line; return $R }
  $d = $dsRow[0]
  Complete-AnchorFromDataSet $R ([pscustomobject]@{ Name = [string]$d.name; Id = [int]$d.id; ClassId = [int]$d.pid; File = [string]$d.path; Fid = [int]$d.fid; Line = [int]$d.line; Type = ([string]$d.sig).Trim() }) $col $SqlSet $SourceOverride
}

# The grade of a TField-variable assignment line (fix round 1, Important 1). ONLY the
# FieldByName shape proves the column: `FfX := FMT.FieldByName('COL')` names the dataset
# as its receiver and the literal as the field -- certain when the dataset read is BOUND,
# [by name] when it is not (INBOX-in-class-field-reads-unbound). Any other shape --
# `FfX := FF(FMT, 'COL')`, but equally `SomeLookup(FMT, 'Caption')` -- proves only
# WHICH dataset and literal appear on the line; that the call returns FMT's field COL is
# an inference about the called routine: [inferred], whether or not the read is bound,
# and the reason names the call. $Calls: the call names on the line.
# Returns Grade ('' | 'by name' | 'inferred'), Reason, Ask.
function Get-FieldVarLineGrade([bool] $FieldByName, [bool] $Bound, [string[]] $Calls, [string] $DsName) {
  if ($FieldByName) {
    if ($Bound) { return [pscustomobject]@{ Grade = ''; Reason = 'the TField variable, by FieldByName on its dataset'; Ask = '' } }
    return [pscustomobject]@{ Grade = 'by name'; Reason = "the TField variable, by FieldByName on $DsName, matched by name among the class's dataset fields"; Ask = 'in-class-field-reads' }
  }
  $cl = @($Calls | Where-Object { $_ } | Sort-Object -Unique)
  $via = $(if ($cl.Count -eq 1) { "via $($cl[0])(dataset, literal)" } elseif ($cl.Count) { "via one of $($cl -join ', ')" } else { 'with no call on the line' })
  $r = "the TField variable $via, assumed to return the dataset's field named by the literal"
  if (-not $Bound) { $r += ", and $DsName matched by name among the class's dataset fields" }
  [pscustomobject]@{ Grade = 'inferred'; Reason = $r; Ask = $(if ($Bound) { '' } else { 'in-class-field-reads' }) }
}

# <Unit>.<TClass>.<FfX>: a TField variable. Its dataset and column come from the
# lines that WRITE it (a bound write): on such a line, the dataset is a field of
# the same class with a dataset type that the line names (a read, or the receiver
# of `.FieldByName`), and the column is the line's ONE string literal. That covers
# `FfX := FMT.FieldByName('COL')` and a helper call `FfX := FF(FMT, 'COL')`
# (Blueprint4.ViewModel.pas:939); Get-FieldVarLineGrade says how far each proves it.
# $Name is the variable's name (the LAST segment of the target -- the unit may be dotted, P13).
function Resolve-AnchorFromFieldVar($Mem, [string] $Target, [string] $Name, $R, $SqlSet, [hashtable] $SourceOverride) {
  $cls = Invoke-IndexQuery "SELECT s.parent_id AS pid FROM symbols s WHERE s.id = $([int]$Mem.id)"
  $cpid = [int]$cls[0].pid
  $w = Invoke-IndexQuery @"
SELECT r.start_line AS line, f.path AS path,
       (SELECT GROUP_CONCAT(DISTINCT s.name) FROM refs m JOIN symbols s ON s.parent_id = $cpid AND s.kind = 'field' AND $(Get-DataSetTypeSql 's')
                AND (s.name = m.name_text OR s.name = m.receiver_text OR 'Self.' || s.name = m.receiver_text)
         WHERE m.file_id = r.file_id AND m.start_line = r.start_line AND (m.kind = 'read' OR (m.kind = 'member-access' AND m.name_text = 'FieldByName'))) AS ds,
       (SELECT MAX(m.symbol_id IS NOT NULL) FROM refs m JOIN symbols s ON s.id = m.symbol_id AND s.parent_id = $cpid AND s.kind = 'field' AND $(Get-DataSetTypeSql 's')
         WHERE m.file_id = r.file_id AND m.start_line = r.start_line AND m.kind = 'read') AS bound,
       (SELECT COUNT(*) FROM refs m JOIN symbols s ON s.parent_id = $cpid AND s.kind = 'field' AND $(Get-DataSetTypeSql 's')
                AND (s.name = m.receiver_text OR 'Self.' || s.name = m.receiver_text)
         WHERE m.file_id = r.file_id AND m.start_line = r.start_line AND m.kind = 'member-access' AND m.name_text = 'FieldByName') AS fbn,
       (SELECT GROUP_CONCAT(DISTINCT m.name_text) FROM refs m WHERE m.file_id = r.file_id AND m.start_line = r.start_line AND m.kind = 'call') AS calls,
       (SELECT GROUP_CONCAT(sl.text, '|') FROM string_literals sl WHERE sl.file_id = r.file_id AND sl.start_line = r.start_line AND sl.kind = 'literal') AS col
  FROM refs r JOIN files f ON f.id = r.file_id
 WHERE r.symbol_id = $([int]$Mem.id) AND r.kind = 'write' ORDER BY r.start_line
"@
  # a pair only where the line names exactly ONE dataset field and ONE literal
  $ok = @($w | Where-Object { $_.ds -and $_.col -and ([string]$_.ds) -notmatch ',' -and ([string]$_.col) -notmatch '\|' })
  $pairs = @($ok | ForEach-Object { "$([string]$_.ds)|$([string]$_.col)" } | Sort-Object -Unique)
  if ($pairs.Count -ne 1) {
    $R.Stop = "$Target is written on $($w.Count) line(s) naming $($pairs.Count) (dataset field, column literal) pair(s)$(if ($pairs.Count) { " ($(($pairs | ForEach-Object { $_ -replace '\|', '.' }) -join ', '))" }) -- cannot tell which"
    $R.StopAnchor = Get-TraceAnchorText ([string]$Mem.path) ([int]$Mem.line)
    return $R
  }
  $dsName, $col = $pairs[0] -split '\|'
  $dsRow = Invoke-IndexQuery "SELECT s.id AS id, s.name AS name, s.signature AS sig, s.start_line AS line, f.path AS path, s.file_id AS fid, s.parent_id AS pid FROM symbols s JOIN files f ON f.id = s.file_id WHERE s.parent_id = $cpid AND s.name = '$(ConvertTo-SqlText $dsName)' AND s.kind = 'field'"
  if ($dsRow.Count -ne 1) { $R.Stop = "$dsName is not a field of the class declaring $Name"; $R.StopAnchor = Get-TraceAnchorText ([string]$Mem.path) ([int]$Mem.line); return $R }
  $site = $ok[0]
  $g = Get-FieldVarLineGrade ([int]$(if ($site.fbn) { $site.fbn } else { 0 }) -gt 0) ([int]$(if ($site.bound) { $site.bound } else { 0 }) -gt 0) `
                             @(([string]$site.calls) -split ',' | Where-Object { $_ -and $_ -ne 'FieldByName' }) $dsName
  [void]$R.Items.Add((New-TraceStep 'step' "SETS $Name := $dsName field '$col'" (Get-TraceAnchorText ([string]$site.path) ([int]$site.line)) $g.Grade '' $g.Reason $g.Ask))
  $d = $dsRow[0]
  Complete-AnchorFromDataSet $R ([pscustomobject]@{ Name = [string]$d.name; Id = [int]$d.id; ClassId = [int]$d.pid; File = [string]$d.path; Fid = [int]$d.fid; Line = [int]$d.line; Type = ([string]$d.sig).Trim() }) $col $SqlSet $SourceOverride
}

# TABLE.COLUMN: the dataset fields whose unit names the table beside them. Exactly
# one proceeds; several is a named stop (Review Focus 2), never a guess.
function Resolve-AnchorFromColumn([string] $Table, [string] $Col, $R, $SqlSet, [hashtable] $SourceOverride) {
  $cands = Invoke-IndexQuery @"
SELECT DISTINCT s.id AS id, s.name AS name, s.qualified_name AS q, s.signature AS sig, s.start_line AS line, f.path AS path, s.file_id AS fid, s.parent_id AS pid
  FROM string_literals sl JOIN refs r ON r.file_id = sl.file_id AND r.start_line = sl.start_line AND r.kind = 'read'
  JOIN symbols s ON s.name = r.name_text AND s.file_id = sl.file_id AND s.kind = 'field'
  JOIN files f ON f.id = s.file_id
 WHERE sl.kind = 'literal' AND sl.text = '$(ConvertTo-SqlText $Table)' AND $(Get-DataSetTypeSql 's')
 ORDER BY s.qualified_name
"@ 'round-trip (datasets of a table)'
  if ($cands.Count -ne 1) {
    $R.Stop = "$Table.$Col`: $($cands.Count) datasets load $Table in this index ($((@($cands | ForEach-Object { [string]$_.q })) -join ', ')) -- pass the control or the dataset field"
    $R.StopAnchor = $(if ($cands.Count) { Get-TraceAnchorText ([string]$cands[0].path) ([int]$cands[0].line) } else { Get-TraceAnchorText ([string]$SqlSet.Tables[$Table].File) ([int]$SqlSet.Tables[$Table].Line) })
    $R.TableColumn = "$Table.$Col"
    return $R
  }
  $d = $cands[0]
  Complete-AnchorFromDataSet $R ([pscustomobject]@{ Name = [string]$d.name; Id = [int]$d.id; ClassId = [int]$d.pid; File = [string]$d.path; Fid = [int]$d.fid; Line = [int]$d.line; Type = ([string]$d.sig).Trim() }) $Col $SqlSet $SourceOverride
}

# The four -Target forms of spec section 3. A dotted target of three or more
# segments is split from the RIGHT (P13): the last segment is the member, the one
# before it the class, and everything before THAT the unit -- so a dotted unit
# (`Blueprint4.ViewModel.TBlueprint_ViewModel.FfOperation_FileName`) resolves.
function Resolve-TraceAnchor([string] $Target, $SqlSet, [hashtable] $SourceOverride) {
  $R = New-AnchorResult
  $t = $Target.Trim()
  if ($t -notmatch '^[A-Za-z_][A-Za-z0-9_$]*(\.[A-Za-z_][A-Za-z0-9_$]*)+$') {
    throw "round-trip: -Target takes <Form>.<Control>, <Unit>.<TForm>.<Control>, <Unit>.<TClass>.<TField variable> or TABLE.COLUMN, got '$Target'"
  }
  $segs = $t -split '\.'
  if ($segs.Count -eq 2 -and $SqlSet.Tables.ContainsKey($segs[0].ToUpperInvariant())) {
    return (Resolve-AnchorFromColumn $segs[0].ToUpperInvariant() $segs[1].ToUpperInvariant() $R $SqlSet $SourceOverride)
  }
  if ($segs.Count -ge 3) {
    $memName = $segs[-1]; $clsName = $segs[-2]; $unit = ($segs[0..($segs.Count - 3)]) -join '.'
    $cls = Invoke-IndexQuery "SELECT s.id AS id FROM symbols s WHERE s.qualified_name = '$(ConvertTo-SqlText "$unit.$clsName")' AND s.kind = 'class'"
    if ($cls.Count -ne 1) { throw "round-trip: $t`: $unit.$clsName is not a class of this index ($($cls.Count) matches)" }
    $mem = Invoke-IndexQuery "SELECT s.id AS id, s.kind AS kind, s.signature AS sig, s.start_line AS line, f.path AS path FROM symbols s JOIN files f ON f.id = s.file_id WHERE s.parent_id = $([int]$cls[0].id) AND s.name = '$(ConvertTo-SqlText $memName)'"
    if ($mem.Count -eq 1 -and ([string]$mem[0].sig).Trim() -match '^T\w*Field$') { return (Resolve-AnchorFromFieldVar $mem[0] $t $memName $R $SqlSet $SourceOverride) }
    $formName = $clsName -replace '^T', ''
    $fm = Invoke-IndexQuery "SELECT COUNT(*) AS n FROM symbols WHERE kind = 'form' AND UPPER(name) = UPPER('$(ConvertTo-SqlText $formName)')"
    if ([int]$fm[0].n -ne 1) {
      $R.Stop = "$t`: $memName is not a TField variable of $clsName and no DFM object is named $formName (the T-less name is a convention)"
      $R.StopAnchor = $(if ($mem.Count) { Get-TraceAnchorText ([string]$mem[0].path) ([int]$mem[0].line) } else { 'unknown:0' })
      return $R
    }
    $R.Grades += 'by name'            # the class -> DFM object hop is a naming convention
    $segs = @($formName, $memName)
  }
  if ($segs.Count -ne 2) { throw "round-trip: $t is not <Form>.<Control>" }
  Resolve-AnchorFromControl $segs[0] $segs[1] $R $SqlSet $SourceOverride
}

# ---- Part 2: the condition shim (spec section 4; engine ask E1 retires it) ---------------
# The index holds tokens, not conditions. For an Exit the index ALREADY anchored
# (a `call` ref named Exit inside the routine) the branch around it is read from
# the source and its condition quoted VERBATIM from the RAW text -- never negated
# or rewritten. Pure over two line arrays (raw and comment/string-stripped, same
# columns) so synthetic cases test it; Get-GuardCondition is the fresh-checked
# wrapper and REFUSES a stale file by name (AC-14).
#
# The branch is found on KEYWORD TOKENS of the stripped text, read backwards from
# the Exit (a line count cannot see `end else begin`, whose begin is the opener,
# nor an `if .. then .. else` NESTED inside the exit block, SendDeltaOperation:3993).
# The token just before a statement says where it stands: `then` -> the if's then
# branch; `else` -> the else of the if (or case) it pairs with; `on .. do` -> an
# except handler; `;` / `begin` / `try` -> a statement of the enclosing block,
# whose opener is then read the same way. Forms:
#   inline  the `if` and the Exit share a line    -> UNLESS "C" (then branch), WHEN "C" (else branch)
#   block   the `if` is on an earlier line         -> the same keywords
#   except  `try S .. except .. Exit`              -> UNLESS "S raises"; a body of several statements is
#                                                     quoted "S1 ... Sn raises" -- which one raises is not in the source
#                                                     (' ... ', never ' .. ', Pascal's range operator -- ruling T4-R3)
#   case    `case X of .. else .. Exit`            -> UNLESS "case X of else"
#   unknown anything else: a loop, a case arm, no branch, a condition holding a double-quote, two
#           Exits on the anchored line, a comment wrapping across the quoted lines, a conditional-
#           compilation directive ({$IF.. {$ELSE {$ENDIF) between the guard and the Exit --
#           Reason is plain GENERATED text the walker writes as a STOPS naming E1; never a guess, never a throw
#
# KNOWN LIMIT (ruling T4-R4): the INNERMOST guard only. `if A then begin if B then
# Exit end` quotes B; that A also guards the Exit is not reported by the shim.
# The walk sees A only if A has its own Exit. Engine ask E1 (branch and condition
# facts from the syntax tree) retires this.
#
# Quoting (P16): a condition is the raw text between `if` and `then`. A wrapped one
# is JOINED: each line's piece runs from its first to its last code or string
# character (a comment at either END of a piece is dropped, as it would swallow
# the join; one inside is kept as written) and the pieces are joined with ONE
# space. Nothing inside a piece changes -- no whitespace collapse, no truncation,
# no quote rewriting. A condition holding `"` cannot be written (New-TraceCond
# refuses it) and comes back as a named `unknown`.
#
# Result: Form, Keyword ('' for unknown), Condition, IfLine (the if / except / case
# line: the condition's anchor), BlockStart..BlockEnd (the lines of the branch
# holding the Exit, for its `-- else ...` note), ExitArg (`Exit(<arg>)`), Reason.

$script:ShimTokenRx = [regex]'(?i)\b(begin|end|try|case|record|except|finally|if|then|else|do|on|with|while|for|of|repeat|until|procedure|function)\b|;|:(?!=)'
$script:ShimOpeners = @('begin', 'try', 'case', 'record', 'repeat')
$script:ShimClosers = @('end', 'until')

# The line on which the block opened by the begin/try/case at ($OpenerLine, $OpenerCol)
# is closed by its `end` (col 0: counting from the start of the line).
function Find-BlockEnd([string[]] $Stripped, [int] $OpenerLine, [int] $OpenerCol = 0) {
  $d = 0
  for ($i = $OpenerLine - 1; $i -lt $Stripped.Count; $i++) {
    $t = $(if ($i -eq $OpenerLine - 1) { $Stripped[$i].Substring([Math]::Min($OpenerCol, $Stripped[$i].Length)) } else { $Stripped[$i] })
    foreach ($m in $script:ShimTokenRx.Matches($t)) {
      $k = $m.Value.ToLowerInvariant()
      if ($k -in $script:ShimOpeners) { $d++ } elseif ($k -in $script:ShimClosers) { $d--; if ($d -le 0) { return $i + 1 } }
    }
  }
  $Stripped.Count
}

# The raw text from ($L1, $C1) to ($L2, $C2) (1-based lines, 0-based columns, end
# exclusive), one piece per line, joined with one space -- see "Quoting" above.
# The span always starts right after a CODE token (if / case / try / `;`), so the
# raw text is read with a string/comment state from there; a `{` or `(*` comment
# not closed on its own line would carry into the next piece, whose quote would
# then be garbled -- $null instead (fix round 1), which the callers turn into a
# named unknown. A raw character the stripped copy blanked that opens neither a
# string nor a comment is the same situation read from the other side: $null.
function Get-ShimSpanText([string[]] $Raw, [string[]] $Stripped, [int] $L1, [int] $C1, [int] $L2, [int] $C2) {
  $pieces = @()
  for ($l = $L1; $l -le $L2; $l++) {
    $r = $Raw[$l - 1]; $s = $Stripped[$l - 1]
    $a = $(if ($l -eq $L1) { $C1 } else { 0 })
    $b = $(if ($l -eq $L2) { [Math]::Min($C2, $r.Length) } else { $r.Length })
    $first = -1; $last = -1; $i = $a
    while ($i -lt $b) {
      $ch = $r[$i]
      if ($i -lt $s.Length -and -not [char]::IsWhiteSpace($s[$i])) { if ($first -lt 0) { $first = $i }; $last = $i; $i++ }
      elseif ([char]::IsWhiteSpace($ch)) { $i++ }
      elseif ($ch -eq "'") {
        # a string the stripped copy blanked: it runs to its closing quote
        $j = $r.IndexOf("'", $i + 1); if ($j -lt 0 -or $j -ge $b) { $j = $b - 1 }
        if ($first -lt 0) { $first = $i }; $last = $j; $i = $j + 1
      }
      elseif ($ch -eq '/' -and $i + 1 -lt $b -and $r[$i + 1] -eq '/') { break }
      elseif ($ch -eq '{') { $j = $r.IndexOf('}', $i + 1); if ($j -lt 0) { return $null }; $i = $j + 1 }
      elseif ($ch -eq '(' -and $i + 1 -lt $b -and $r[$i + 1] -eq '*') { $j = $r.IndexOf('*)', $i + 2); if ($j -lt 0) { return $null }; $i = $j + 2 }
      else { return $null }
    }
    if ($first -ge 0) { $pieces += $r.Substring($first, $last - $first + 1) }
  }
  $pieces -join ' '
}

function New-ShimResult($X, [string] $Form, [string] $Keyword, [string] $Condition, [int] $IfLine, [int] $BlockStart, [int] $BlockEnd, [string] $Reason = '') {
  if ($Form -ne 'unknown' -and $Condition.Contains('"')) {
    return (New-ShimResult $X 'unknown' '' '' 0 0 0 "the condition over the $($X.What) at :$($X.ExitLine) holds a double-quote, which a Form A condition cannot carry verbatim")
  }
  [pscustomobject]@{ Form = $Form; Keyword = $Keyword; Condition = $Condition; IfLine = $IfLine; BlockStart = $BlockStart; BlockEnd = $BlockEnd; ExitArg = $X.ExitArg; Reason = $Reason }
}

function New-ShimUnknown($X, [string] $Why) { New-ShimResult $X 'unknown' '' '' 0 0 0 "the $($X.What) at :$($X.ExitLine) $Why, a shape the source shim does not read" }

# the `if` token owning the `then` at token $ThenIdx (-1: none before a statement boundary)
function Find-ShimIf($X, [int] $ThenIdx) {
  for ($q = $ThenIdx - 1; $q -ge 0; $q--) {
    $k = $X.Tok[$q].T
    if ($k -eq 'if') { return $q }
    if ($k -in ';', 'begin', 'end', 'then', 'else', 'do', 'try', 'except', 'finally', 'of', 'repeat', 'until', 'case', 'procedure', 'function') { return -1 }
  }
  -1
}

# What the `else` at token $ElseIdx pairs with: back over balanced blocks, an inner
# if's own `else` absorbs the next `then`; the first free `then` before any `;` is
# the if's; a `case` opener is the case's. $null: neither.
function Find-ShimElseOwner($X, [int] $ElseIdx) {
  $d = 0; $semi = $false; $pend = 0
  for ($q = $ElseIdx - 1; $q -ge 0; $q--) {
    $k = $X.Tok[$q].T
    if ($k -in $script:ShimClosers) { $d++; continue }
    if ($k -in $script:ShimOpeners) {
      if ($d -gt 0) { $d--; continue }
      return $(if ($k -eq 'case') { [pscustomobject]@{ Kind = 'case'; Idx = $q } } else { $null })
    }
    if ($d -gt 0) { continue }
    if ($k -eq ';') { $semi = $true }
    elseif ($k -eq 'else') { $pend++ }
    elseif ($k -eq 'then' -and -not $semi) {
      if ($pend -gt 0) { $pend--; continue }
      $i = Find-ShimIf $X $q
      return $(if ($i -ge 0) { [pscustomobject]@{ Kind = 'if'; Idx = $i; Then = $q } } else { $null })
    }
    elseif ($k -in 'procedure', 'function') { return $null }
  }
  $null
}

# the depth-0 tokens in $Want strictly between token indexes $From and $To
function Get-ShimLevelTokens($X, [int] $From, [int] $To, [string[]] $Want) {
  $d = 0; $hits = @()
  for ($q = $From + 1; $q -lt $To; $q++) {
    $k = $X.Tok[$q].T
    if ($k -in $script:ShimOpeners) { $d++ } elseif ($k -in $script:ShimClosers) { $d-- } elseif ($d -eq 0 -and $k -in $Want) { $hits += $q }
  }
  , $hits
}

# Ruling T4-R1: a conditional-compilation directive between the guard's token and
# the Exit (`{$IFDEF X} if A then {$ELSE} if B then {$ENDIF} Exit;`) means the
# stripped copy shows ONE branch of a choice the compiler makes -- $true, and the
# caller returns a named unknown rather than quote a condition that may not apply.
function Test-ShimDirective($X, $Tok) {
  $t = ''
  for ($l = $Tok.L; $l -le $X.ExitLine; $l++) {
    $r = $X.Raw[$l - 1]
    $a = $(if ($l -eq $Tok.L) { $Tok.C } else { 0 }); $b = $(if ($l -eq $X.ExitLine) { [Math]::Min($X.ExitCol, $r.Length) } else { $r.Length })
    if ($b -gt $a) { $t += $r.Substring($a, $b - $a) + "`n" }
  }
  $t -match '(?i)(\{|\(\*)\$(IF|ELSE|ENDIF)'
}

function New-ShimIfResult($X, [int] $ThenIdx, [string] $Keyword, [int[]] $Blk) {
  $i = Find-ShimIf $X $ThenIdx
  if ($i -lt 0) { return (New-ShimUnknown $X 'follows a then with no if before it') }
  $it = $X.Tok[$i]; $th = $X.Tok[$ThenIdx]
  if (Test-ShimDirective $X $it) { return (New-ShimUnknown $X 'sits under a conditional-compilation directive') }
  $cond = Get-ShimSpanText $X.Raw $X.Stripped $it.L $it.E $th.L $th.C
  if ($null -eq $cond) { return (New-ShimUnknown $X 'has a condition that wraps a comment across lines') }
  New-ShimResult $X $(if ($it.L -eq $X.ExitLine) { 'inline' } else { 'block' }) $Keyword $cond $it.L $Blk[0] $Blk[1]
}

function New-ShimCaseResult($X, [int] $CaseIdx, [int] $ElseIdx) {
  $ca = $X.Tok[$CaseIdx]
  $of = @(for ($q = $CaseIdx + 1; $q -lt $X.Tok.Count; $q++) { if ($X.Tok[$q].T -eq 'of') { $X.Tok[$q]; break } })
  if (-not $of.Count) { return (New-ShimUnknown $X 'sits in a case with no of') }
  if (Test-ShimDirective $X $ca) { return (New-ShimUnknown $X 'sits under a conditional-compilation directive') }
  $sel = Get-ShimSpanText $X.Raw $X.Stripped $ca.L $ca.C $of[0].L $of[0].E
  if ($null -eq $sel) { return (New-ShimUnknown $X 'has a condition that wraps a comment across lines') }
  New-ShimResult $X 'case' 'UNLESS' "$sel else" $ca.L $X.Tok[$ElseIdx].L (Find-BlockEnd $X.Stripped $ca.L $ca.C)
}

# The Exit sits in the handler of the try at token $TryIdx (its `except` at $ExIdx):
# the protected statements are the depth-0 `;`-separated spans of the try body.
function New-ShimExceptResult($X, [int] $TryIdx, [int] $ExIdx) {
  $tr = $X.Tok[$TryIdx]; $ex = $X.Tok[$ExIdx]
  if (Test-ShimDirective $X $tr) { return (New-ShimUnknown $X 'sits under a conditional-compilation directive') }
  $stm = @(); $sl = $tr.L; $sc = $tr.E
  $semis = Get-ShimLevelTokens $X $TryIdx $ExIdx @(';')
  foreach ($q in (@($semis) + $ExIdx)) {
    $e = $X.Tok[$q]
    $txt = Get-ShimSpanText $X.Raw $X.Stripped $sl $sc $e.L $e.C
    if ($null -eq $txt) { return (New-ShimUnknown $X 'has a try body that wraps a comment across lines') }
    if ($txt) { $stm += $txt }
    $sl = $e.L; $sc = $e.E
  }
  if (-not $stm.Count) { return (New-ShimUnknown $X 'sits in the handler of an empty try') }
  # ruling T4-R3: ' ... ', not ' .. ' (Pascal's range operator)
  $s = $(if ($stm.Count -eq 1) { $stm[0] } else { "$($stm[0]) ... $($stm[-1])" })
  New-ShimResult $X 'except' 'UNLESS' "$s raises" $ex.L $ex.L (Find-BlockEnd $X.Stripped $tr.L $tr.C)
}

# The statement holding the Exit starts at token $P (Tok.Count: the Exit itself);
# $Blk is that statement's first and last line.
function Resolve-ShimStatement($X, [int] $P, [int[]] $Blk) {
  if ($P -le 0) { return (New-ShimUnknown $X 'is not inside a branch') }
  $k = $X.Tok[$P - 1].T
  if ($k -eq 'then') { return (New-ShimIfResult $X ($P - 1) 'UNLESS' $Blk) }
  if ($k -eq 'else') {
    $o = Find-ShimElseOwner $X ($P - 1)
    if (-not $o) { return (New-ShimUnknown $X 'follows an else the shim cannot pair') }
    if ($o.Kind -eq 'case') { return (New-ShimCaseResult $X $o.Idx ($P - 1)) }
    return (New-ShimIfResult $X $o.Then 'WHEN' $Blk)
  }
  if ($k -eq 'do') {
    # the statement head: an `on` right after `except` or `;` is a handler; else with / while / for
    for ($q = $P - 2; $q -ge 0; $q--) {
      $h = $X.Tok[$q].T
      if ($h -eq 'on' -and $q -gt 0 -and $X.Tok[$q - 1].T -in 'except', ';') { return (Resolve-ShimEnclosing $X $q) }
      if ($h -in 'with', 'while', 'for') { return (New-ShimUnknown $X "sits under a $h statement") }
      if ($h -in ';', 'begin', 'end', 'then', 'else', 'do', 'try', 'except', 'finally', 'of', 'repeat', 'until', 'case') { break }
    }
    return (New-ShimUnknown $X 'sits under a do the shim cannot place')
  }
  if ($k -eq ':') { return (New-ShimUnknown $X 'sits in a case arm') }
  Resolve-ShimEnclosing $X $P
}

# The Exit (or the statement at token $P) is one statement of a block: find the
# block's opener and read IT as the statement that holds the Exit.
function Resolve-ShimEnclosing($X, [int] $P) {
  $d = 0
  for ($q = $P - 1; $q -ge 0; $q--) {
    $k = $X.Tok[$q].T
    if ($k -in $script:ShimClosers) { $d++; continue }
    if ($k -in $script:ShimOpeners) {
      if ($d -gt 0) { $d--; continue }
      $o = $X.Tok[$q]
      $blk = @($o.L, (Find-BlockEnd $X.Stripped $o.L $o.C))
      if ($k -eq 'begin') {
        # a begin after then / else / do / a case label is a branch; any other is the routine body (or a bare block)
        if ($q -gt 0 -and $X.Tok[$q - 1].T -in 'then', 'else', 'do', ':') { return (Resolve-ShimStatement $X $q $blk) }
        return (New-ShimUnknown $X 'is not inside a branch')
      }
      if ($k -eq 'try') {
        $mk = Get-ShimLevelTokens $X $q $P @('except', 'finally')
        if ($mk.Count -and $X.Tok[$mk[-1]].T -eq 'except') { return (New-ShimExceptResult $X $q $mk[-1]) }
        return (Resolve-ShimStatement $X $q $blk)     # in the try body or the finally: the try is the statement
      }
      if ($k -eq 'case') {
        $els = Get-ShimLevelTokens $X $q $P @('else')
        foreach ($e in $els) {
          $ow = Find-ShimElseOwner $X $e
          if ($ow -and $ow.Kind -eq 'case' -and $ow.Idx -eq $q) { return (New-ShimCaseResult $X $q $e) }
        }
        return (New-ShimUnknown $X 'sits in a case arm')
      }
      return (New-ShimUnknown $X "sits inside a $k")
    }
    if ($d -eq 0 -and $k -in 'procedure', 'function') { return (New-ShimUnknown $X 'is not inside a branch') }
  }
  New-ShimUnknown $X 'is not inside a branch'
}

function Get-GuardConditionFromLines([string[]] $Raw, [string[]] $Stripped, [int] $ExitLine, [int] $RoutineStart) {
  $X = [pscustomobject]@{ Raw = $Raw; Stripped = $Stripped; ExitLine = $ExitLine; ExitCol = 0; ExitArg = ''; Tok = $null; What = 'Exit' }
  if ($ExitLine -lt 1 -or $ExitLine -gt $Stripped.Count) { return (New-ShimUnknown $X 'is outside the file') }
  $s = $Stripped[$ExitLine - 1]
  $ems = [regex]::Matches($s, '(?i)\bExit\b')
  if (-not $ems.Count) { return (New-ShimUnknown $X 'is not an Exit in this copy of the file') }
  # fix round 1: the index anchors a LINE; with two Exits on it (`if A then begin ..Exit.. end else begin ..Exit.. end`)
  # the shim cannot tell which one it was asked about -- named, never the first one's branch by default
  if ($ems.Count -gt 1) { return (New-ShimUnknown $X 'shares its line with another Exit') }
  $em = $ems[0]; $X.ExitCol = $em.Index
  # Exit(<arg>): the raw text inside the balanced parentheses
  $p = $em.Index + $em.Length
  while ($p -lt $s.Length -and [char]::IsWhiteSpace($s[$p])) { $p++ }
  if ($p -lt $s.Length -and $s[$p] -eq '(') {
    $d = 0
    for ($j = $p; $j -lt $s.Length; $j++) {
      if ($s[$j] -eq '(') { $d++ } elseif ($s[$j] -eq ')') { $d--; if ($d -eq 0) { $X.ExitArg = $Raw[$ExitLine - 1].Substring($p + 1, $j - $p - 1).Trim(); break } }
    }
  }
  $tok = New-Object System.Collections.ArrayList
  for ($l = [Math]::Max($RoutineStart, 1); $l -le $ExitLine; $l++) {
    $t = $(if ($l -eq $ExitLine) { $s.Substring(0, $em.Index) } else { $Stripped[$l - 1] })
    foreach ($m in $script:ShimTokenRx.Matches($t)) { [void]$tok.Add([pscustomobject]@{ L = $l; C = $m.Index; E = $m.Index + $m.Length; T = $m.Value.ToLowerInvariant() }) }
  }
  $X.Tok = $tok
  Resolve-ShimStatement $X $tok.Count @($ExitLine, $ExitLine)
}

function Get-GuardCondition([string] $Path, [int] $ExitLine, [int] $RoutineStart, [hashtable] $SourceOverride) {
  if (-not (Test-SourceFresh $Path $SourceOverride)) {
    throw "round-trip: $([IO.Path]::GetFileName($Path)) differs from the indexed copy (sha256) -- refusing to quote a condition from it. Reindex the project, then re-run."
  }
  $read = Resolve-SourceReadPath $Path $SourceOverride
  $stripped = Get-StrippedSourceLines $read
  $raw = [IO.File]::ReadAllLines($read, [Text.Encoding]::GetEncoding(28591))
  Get-GuardConditionFromLines $raw $stripped $ExitLine $RoutineStart
}

# The ENCLOSING condition of the statement that starts at ($Line, $Col) -- ruling T5-R1. The same
# token reader, asked from a statement instead of an Exit: the nearest `if` whose branch holds the
# statement, through begin / try blocks. The keyword says when the STATEMENT runs: WHEN "C" in the
# then branch, UNLESS "C" in the else branch (the reverse of a guard's, which says when the path
# CONTINUES past its Exit). Anything the reader cannot place -- no branch, a loop, a case arm, a
# directive -- is a named `unknown`, and the caller keeps the statement. Innermost if only (T4-R4).
function Get-EnclosingConditionFromLines([string[]] $Raw, [string[]] $Stripped, [int] $Line, [int] $Col, [int] $RoutineStart) {
  $X = [pscustomobject]@{ Raw = $Raw; Stripped = $Stripped; ExitLine = $Line; ExitCol = 0; ExitArg = ''; Tok = $null; What = 'statement' }
  if ($Line -lt 1 -or $Line -gt $Stripped.Count) { return (New-ShimUnknown $X 'is outside the file') }
  $X.ExitCol = [Math]::Min([Math]::Max($Col, 0), $Stripped[$Line - 1].Length)
  $tok = New-Object System.Collections.ArrayList
  for ($l = [Math]::Max($RoutineStart, 1); $l -le $Line; $l++) {
    $t = $(if ($l -eq $Line) { $Stripped[$l - 1].Substring(0, $X.ExitCol) } else { $Stripped[$l - 1] })
    foreach ($m in $script:ShimTokenRx.Matches($t)) { [void]$tok.Add([pscustomobject]@{ L = $l; C = $m.Index; E = $m.Index + $m.Length; T = $m.Value.ToLowerInvariant() }) }
  }
  $X.Tok = $tok
  $g = Resolve-ShimStatement $X $tok.Count @($Line, $Line)
  if ($g.Form -ne 'unknown') { $g.Keyword = $(if ($g.Keyword -eq 'UNLESS') { 'WHEN' } else { 'UNLESS' }) }
  $g
}

# A FRESH file's raw and stripped line arrays, read once per index + path; a stale file REFUSES (AC-14).
$script:RtSrc = @{}
function Get-TraceSource([string] $Path, [hashtable] $SourceOverride) {
  $k = "$DbPath|$Path"
  if (-not $script:RtSrc.ContainsKey($k)) {
    if (-not (Test-SourceFresh $Path $SourceOverride)) {
      throw "round-trip: $([IO.Path]::GetFileName($Path)) differs from the indexed copy (sha256) -- refusing to read it. Reindex the project, then re-run."
    }
    $read = Resolve-SourceReadPath $Path $SourceOverride
    $script:RtSrc[$k] = [pscustomobject]@{ Stripped = (Get-StrippedSourceLines $read); Raw = [IO.File]::ReadAllLines($read, [Text.Encoding]::GetEncoding(28591)) }
  }
  $script:RtSrc[$k]
}

# The fresh-checked wrapper of Get-EnclosingConditionFromLines.
function Get-EnclosingCondition([string] $Path, [int] $Line, [int] $Col, [int] $RoutineStart, [hashtable] $SourceOverride) {
  $s = Get-TraceSource $Path $SourceOverride
  Get-EnclosingConditionFromLines $s.Raw $s.Stripped $Line $Col $RoutineStart
}

# A string literal exactly as the source writes it, quotes and doubled '' included (ruling T5-R3).
# The index stores the value UNESCAPED and TRIMMED (`'... for '` is stored `... for`: a gap), so the
# token is read from the fresh line at the literal's columns (1-based, end exclusive); when that span
# is not one quoted token, the index value is re-escaped instead. $Raw: the file's raw lines, or $null.
function Get-LiteralSourceText($Lit, $Raw) {
  $ln = [int]$Lit.line; $c0 = [int]$Lit.col - 1; $c1 = [int]$Lit.ecol - 1
  if ($Raw -and $ln -ge 1 -and $ln -le $Raw.Count -and $c0 -ge 0 -and $c1 -gt $c0 + 1 -and $c1 -le $Raw[$ln - 1].Length) {
    $tok = $Raw[$ln - 1].Substring($c0, $c1 - $c0)
    if ($tok -match "^'(?:[^']|'')*'$") { return $tok }
  }
  "'" + ([string]$Lit.text).Replace("'", "''") + "'"
}

# A branch for ANOTHER table (T5-R1): the statement runs WHEN "<cond>" and <cond> compares a value
# with `=` to a string literal that is a known table ($Tables) other than the anchor's -- and says
# nothing that could let the anchor's table through: no `or` / `xor` / `not` / `<>`, no literal
# naming the anchor table. Anything else keeps the step.
function Test-OtherTableBranch([string] $Keyword, [string] $Condition, [string] $AnchorTable, [string[]] $Tables) {
  if ($Keyword -cne 'WHEN') { return $false }
  if ($Condition -match '(?i)\b(or|xor|not)\b|<>') { return $false }
  $all = @([regex]::Matches($Condition, "'((?:[^']|'')*)'") | ForEach-Object { $_.Groups[1].Value.Replace("''", "'").ToUpperInvariant() })
  if ($all -contains $AnchorTable.ToUpperInvariant()) { return $false }
  $eq = @([regex]::Matches($Condition, "(?<![<>:])=\s*'((?:[^']|'')*)'|'((?:[^']|'')*)'\s*=") | ForEach-Object { ($_.Groups[1].Value + $_.Groups[2].Value).Replace("''", "'").ToUpperInvariant() })
  $up = @($Tables | ForEach-Object { ([string]$_).ToUpperInvariant() })
  [bool](@($eq | Where-Object { $up -contains $_ }).Count)
}

# ---- Part 3: the walk (spec section 4) ---------------------------------------------------
# Rulings this part carries: a condition reaches New-TraceCond VERBATIM ($g.Condition --
# no sanitiser, no length cap: P16, T4-C1); a shim `unknown` becomes a numbered STOPS
# whose text is the shim's GENERATED Reason, naming E1 (T3-M2); nothing here names the
# anchor's table, dataset or command -- the anchor ($Ctx) parametrises every rule; what IS named
# is convention (cmd* / rsp* constants, FIB$ tables, UpdateSQL / SelectSQL, the RtOps verbs).
$script:RtFacts = @{}
$script:RtImpls = @{}
# calls that are DATASET OPs / transaction / SQL steps, and the verb they get
$script:RtOps = @{ SaveToStream = 'SERIALIZES'; LoadFromStream = 'DESERIALIZES'; CommitUpdates = 'APPLIES'; CancelUpdates = 'APPLIES'
                   ApplyUpdates = 'APPLIES'; EmptyDataSet = 'LOADS'; StartTransaction = 'OPENS'; Commit = 'RUNS'; Rollback = 'RUNS'
                   Execute = 'RUNS'; ExecSQL = 'RUNS'; Open = 'RUNS' }
$script:RtEvents = @('AfterPost', 'AfterDelete', 'BeforePost', 'AfterInsert', 'OnUpdateRecord', 'OnUpdateError', 'OnReconcileError')

# A GENERATED stop reason made safe for a STOPS step (ruling T3-M2): only what the writer
# refuses in a text (' -- ', ' @', ' [') and what splits a note ('; ') is touched, a bracket
# PAIR reads as parentheses, and nothing is truncated -- a stop that names every candidate
# keeps them all. Never applied to source-derived text (a condition, an RHS quote).
function ConvertTo-TraceStopText([string] $s) {
  $t = (([string]$s) -replace '\s+', ' ').Trim() -replace ' \[([^\]]*)\]', ' ($1)'
  $t -replace ' -- ', ' - ' -replace ' @', ' at ' -replace ' \[', ' (' -replace '; ', ', '
}

function Get-BoundaryLikes([string] $Pattern) {
  (@($Pattern -split '\|' | ForEach-Object { "u.qualified_name LIKE '$(ConvertTo-SqlText $_)'" })) -join ' OR '
}

# One routine's body facts: every ref in its impl range joined to the symbol it
# binds to (call_edges target first, then refs.symbol_id) with the target's unit
# tested against the transport convention (tpipe), and every literal. Paged;
# cached per index + id for the run (the key carries $DbPath: CLIENT and SERVER
# ids are different populations and are never mixed). A NESTED routine's body
# lies inside its outer routine's impl range: its refs (enclosed by the nested
# symbol) and its literals are left out -- it is walked as its own routine when
# called, never twice as part of the outer body.
function Get-RoutineFacts([int] $Id, [string] $Likes) {
  $key = "$DbPath|$Id"
  if ($script:RtFacts.ContainsKey($key)) { return $script:RtFacts[$key] }
  $s = Invoke-IndexQuery @"
SELECT s.id AS id, s.name AS name, s.qualified_name AS q, s.impl_start_line AS istart, s.impl_end_line AS iend, s.start_line AS decl,
       f.path AS path, s.file_id AS fid, s.parent_id AS pid, sf.sql_reads AS sqlr, sf.sql_writes AS sqlw
  FROM symbols s JOIN files f ON f.id = s.file_id LEFT JOIN symbol_facts sf ON sf.symbol_id = s.id
 WHERE s.id = $Id
"@
  if ($s.Count -eq 0) { throw "Get-RoutineFacts: symbol $Id is not in $DbPath" }
  $s = $s[0]
  $F = [pscustomobject]@{ Id = $Id; Name = [string]$s.name; Qname = [string]$s.q; Short = (Get-ShortName ([string]$s.q) (Get-UnitName ([string]$s.path)))
                          Path = [string]$s.path; Fid = [int]$s.fid; Pid = $(if ($s.pid) { [int]$s.pid } else { 0 })
                          ImplStart = [int]$s.istart; ImplEnd = [int]$s.iend; Decl = [int]$s.decl
                          SqlReads = [string]$s.sqlr; SqlWrites = [string]$s.sqlw; Refs = @(); Lits = @() }
  if ($F.ImplStart -gt 0) {
    $F.Refs = Get-AllIndexRows @"
SELECT r.id AS rid, r.kind AS kind, r.name_text AS nm, r.receiver_text AS recv, r.start_line AS line, r.start_col AS col, r.end_col AS ecol,
       t.id AS tid, t.kind AS tkind, t.name AS tname, t.qualified_name AS tq, t.impl_start_line AS tistart, t.start_line AS tdecl, tf.path AS tpath, t.file_id AS tfid,
       (SELECT 1 FROM symbols u WHERE u.file_id = t.file_id AND u.kind = 'unit' AND ($Likes)) AS tpipe
  FROM refs r
  LEFT JOIN symbols t ON t.id = COALESCE((SELECT ce.target_symbol_id FROM call_edges ce WHERE ce.ref_id = r.id), r.symbol_id)
  LEFT JOIN files tf ON tf.id = t.file_id
 WHERE r.file_id = $($F.Fid) AND r.start_line BETWEEN $($F.ImplStart) AND $($F.ImplEnd)
   AND (r.enclosing_symbol_id = $Id OR r.enclosing_symbol_id IS NULL)
"@ 'r.start_line, r.start_col, r.id'
    $F.Lits = Get-AllIndexRows @"
SELECT sl.kind AS kind, sl.text AS text, sl.start_line AS line, sl.start_col AS col, sl.end_col AS ecol
  FROM string_literals sl
 WHERE sl.file_id = $($F.Fid) AND sl.start_line BETWEEN $($F.ImplStart) AND $($F.ImplEnd) AND sl.kind IN ('literal', 'format')
   AND NOT EXISTS (SELECT 1 FROM symbols n WHERE n.parent_id = $Id AND n.impl_start_line > 0 AND sl.start_line BETWEEN n.impl_start_line AND n.impl_end_line)
"@ 'sl.start_line, sl.start_col, sl.id'
  }
  $script:RtFacts[$key] = $F
  $F
}

function Add-RtItem($List, $Item, [int] $Line, [int] $Owner) {
  $Item | Add-Member -NotePropertyName Line -NotePropertyValue $Line -Force
  $Item | Add-Member -NotePropertyName Owner -NotePropertyValue $Owner -Force
  [void]$List.Add($Item)
}

function Get-LineLits($Lits) {
  $l = @($Lits | Where-Object { $_.kind -eq 'literal' } | ForEach-Object { '"' + (ConvertTo-TraceWord ([string]$_.text) 40) + '"' })
  $(if ($l.Count) { ' ' + ($l -join ' ') } else { '' })
}

# The implementation of an UNBOUND `<Receiver>.<Name>(...)`: the receiver's declared
# type, then the one method of that name in that class. A plain receiver is looked
# up in the NEAREST scope that declares it -- the routine's locals and params, then
# its class's fields and properties, then unit-level vars -- and only there: an
# index-wide name match took `MS` (a TMemoryStream local of SendDeltaOperation) for
# another routine's TABZMemoryStream. A dotted receiver (`X.Y.Name`) has no scope
# the index can give, so its last segment is matched index-wide. A receiver the
# index does not declare, or declares with a library type, resolves to nothing and
# the call is left alone. Rows carry the receiver's declaration kinds (rkinds),
# which say which engine ask the [by name] hop waits on: a FIELD / PROPERTY receiver
# is INBOX-in-class-field-reads-unbound; any other ('receiver-typed-calls': a member
# call on a unit var such as GDatasetsDef, D22 did not bind it) is filed as
# C:\Projects\Delphi-RAG-lint\docs\INBOX-charts-receiver-typed-calls-unbound.md (T5-R4).
# Cached per index + routine + receiver + name: the same `FConn.X` repeats in a body.
function Resolve-ImplByName([string] $Recv, [string] $Name, $F) {
  $segs = @(($Recv -replace '^Self\.', '') -split '\.')
  $root = $segs[-1]
  $key = "$DbPath|$($F.Id)|$($Recv.ToUpperInvariant())|$Name"
  if ($script:RtImpls.ContainsKey($key)) { return , $script:RtImpls[$key] }
  $scopes = $(if ($segs.Count -eq 1) { @("s.parent_id = $($F.Id) AND s.kind IN ('local_var','param')", "s.parent_id = $($F.Pid) AND s.kind IN ('field','property')", "s.kind = 'var'") }
              else { @("s.kind IN ('var','field','property','param','local_var')") })
  $t = @()
  foreach ($sc in $scopes) {
    # the first scope that DECLARES the name wins, typed or not (an untyped inline var hides the outer names)
    $t = Invoke-IndexQuery "SELECT DISTINCT COALESCE(TRIM(s.signature), '') AS sig, s.kind AS k FROM symbols s WHERE UPPER(s.name) = UPPER('$(ConvertTo-SqlText $root)') AND $sc"
    if ($t.Count) { break }
  }
  $t = @($t | Where-Object { [string]$_.sig -ne '' })
  $r = @()
  if ($t.Count) {
    $types = @($t | ForEach-Object { (([string]$_.sig) -replace '<.*$', '').Trim() } | Where-Object { $_ } | Sort-Object -Unique)
    $kinds = (@($t | ForEach-Object { [string]$_.k } | Sort-Object -Unique)) -join ','
    $r = Invoke-IndexQuery @"
SELECT s.id AS id, s.qualified_name AS q, s.impl_start_line AS istart, f.path AS path, s.file_id AS fid, s.parent_id AS pid, '$kinds' AS rkinds
  FROM symbols s JOIN files f ON f.id = s.file_id
 WHERE s.name = '$(ConvertTo-SqlText $Name)' AND s.kind = 'method' AND s.impl_start_line > 0
   AND s.parent_id IN (SELECT c.id FROM symbols c WHERE c.kind = 'class' AND UPPER(c.name) IN ($(ConvertTo-SqlInList ($types | ForEach-Object { $_.ToUpperInvariant() }))))
"@
  }
  $script:RtImpls[$key] = $r
  , $r
}

# The handler a wiring line names: bound (certain) or a method of the same class by name (E3).
function Resolve-HandlerByName($Ref, $F) {
  if ($Ref.tid -and [int]$Ref.tistart -gt 0) {
    return [pscustomobject]@{ Id = [int]$Ref.tid; Short = (Get-ShortName ([string]$Ref.tq) (Get-UnitName ([string]$Ref.tpath))); Path = [string]$Ref.tpath; Line = [int]$Ref.tistart; Grade = ''; Ask = '' }
  }
  $h = Invoke-IndexQuery "SELECT s.id AS id, s.qualified_name AS q, s.impl_start_line AS istart, f.path AS path FROM symbols s JOIN files f ON f.id = s.file_id WHERE s.parent_id = $($F.Pid) AND s.name = '$(ConvertTo-SqlText ([string]$Ref.nm))' AND s.kind = 'method' AND s.impl_start_line > 0"
  if ($h.Count -ne 1) { return $null }
  [pscustomobject]@{ Id = [int]$h[0].id; Short = (Get-ShortName ([string]$h[0].q) (Get-UnitName ([string]$h[0].path))); Path = [string]$h[0].path; Line = [int]$h[0].istart; Grade = 'by name'; Ask = 'E3' }
}

# A FIB$ literal that is SQL reading a FIB$ table (`FROM FIB$DATASETS_INFO`), not a message
# that names one (`'cmdDelta: no FIB$DATASETS_INFO entry for table "%s"'`, HandleDelta:433).
$script:RtFibSqlRx = '(?i)\b(FROM|JOIN|INTO|UPDATE)\s+FIB\$'

# FIB$ SQL literals of a unit, with the routine each sits in (a by-name callee's unit).
function Get-FibLiterals([int] $Fid) {
  $rows = Get-AllIndexRows @"
SELECT sl.text AS text, sl.start_line AS line, sl.id AS id,
       (SELECT s.name FROM symbols s WHERE s.file_id = sl.file_id AND s.impl_start_line <= sl.start_line AND s.impl_end_line >= sl.start_line AND s.kind IN ('method','procedure','function','constructor') ORDER BY s.impl_start_line DESC LIMIT 1) AS routine
  FROM string_literals sl
 WHERE sl.file_id = $Fid AND sl.kind = 'literal' AND sl.text LIKE '%FIB$%'
"@ 'sl.start_line, sl.id'
  , @($rows | Where-Object { [string]$_.text -match $script:RtFibSqlRx })
}

# What the other branch does: dataset ops, enum reads and literals inside the
# exit block, plus `Exit(<arg>)`. Written as the condition's `-- else ...` note.
# The literal is SOURCE text (ruling T5-R3): quoted as written, Pascal's doubled ''
# restored (the index stores the unescaped value) and never shortened; one the
# note cannot carry -- a double quote, the '; ' separator, a byte outside ASCII --
# is left out and its line named, never rewritten.
function Get-ElseNote($F, $G, $Ctx) {
  $parts = @()
  $in = @($F.Refs | Where-Object { [int]$_.line -ge $G.BlockStart -and [int]$_.line -le $G.BlockEnd })
  foreach ($o in @($in | Where-Object { $_.kind -eq 'call' -and $script:RtOps.ContainsKey([string]$_.nm) })) {
    $parts += "$(if ($o.recv) { [string]$o.recv + '.' })$([string]$o.nm) @$(Get-TraceAnchorText $F.Path ([int]$o.line))"
  }
  $en = @($in | Where-Object { [string]$_.tkind -eq 'enum_value' } | ForEach-Object { [string]$_.tname } | Sort-Object -Unique)
  if ($en.Count) { $parts += ($en -join '/') }
  $lits = @($F.Lits | Where-Object { [int]$_.line -ge $G.BlockStart -and [int]$_.line -le $G.BlockEnd -and $_.kind -in 'literal', 'format' -and ([string]$_.text).Trim().Length -gt 8 } | Select-Object -First 1)
  foreach ($l in $lits) {
    $raw = $(if ($F.PSObject.Properties['Fid'] -and $F.Fid) { (Get-TraceSource $F.Path $Ctx.SourceOverride).Raw } else { $null })
    $lt = Get-LiteralSourceText $l $raw
    $parts += $(if ($lt -match '"|; |[^\x20-\x7E]') { "a literal at :$([int]$l.line)" } else { $lt })
  }
  if ($G.ExitArg) { $parts += "Exit($($G.ExitArg))" }
  $(if ($parts.Count) { 'else ' + ($parts -join ', ') } else { '' })
}

# The payload a transport call carries: the routine's literals before the send that
# name the anchor table, else its key=value literals; plus the stream when a
# SaveToStream precedes. Inferred from literals, never a fact.
function Get-PayloadText($F, [int] $Line, $Ctx) {
  $before = @($F.Lits | Where-Object { [int]$_.line -lt $Line -and $_.kind -eq 'literal' })
  $pl = @($before | Where-Object { $Ctx.Table -and ([string]$_.text).ToUpperInvariant().Contains([string]$Ctx.Table) })
  if (-not $pl.Count) { $pl = @($before | Where-Object { [string]$_.text -match '[=|]' }) }
  $t = (@($pl | ForEach-Object { '"' + (ConvertTo-TraceWord ([string]$_.text) 40) + '"' }) -join ' + ')
  if (@($F.Refs | Where-Object { [int]$_.line -lt $Line -and [string]$_.nm -eq 'SaveToStream' }).Count) { $t += $(if ($t) { ' + ' } else { '' }) + 'sfBinary stream' }
  $(if ($t) { $t } else { 'payload built before the send (no literal found)' })
}

function Add-CallsStep($List, $Tgt, $Sub, $Caller, [int] $SiteLine, [string] $Lits = '', [switch] $Always) {
  if (-not $Always -and -not $Sub.Items.Count -and -not $Sub.Conds.Count) { return }
  $s = New-TraceStep 'step' "CALLS $($Tgt.Short)$Lits" (Get-TraceAnchorText $Tgt.Path $Tgt.Line) $Tgt.Grade $Caller.Short "from :$SiteLine" $Tgt.Ask
  $s | Add-Member -NotePropertyName CalleeId -NotePropertyValue ([int]$Tgt.Id)
  foreach ($c in $Sub.Conds) { [void]$s.Children.Add($c) }
  Add-RtItem $List $s $SiteLine $Caller.Id
  foreach ($i in $Sub.Items) { [void]$List.Add($i) }
}

# The refs / literals of one line that could make a step (T5-R1 counts them when the line is
# omitted): a dataset / SQL op, a bound call into project code, a call resolvable by name, a
# protocol constant, a FIB$ SQL literal. Each with the column the line's statement is read from.
function Get-LineCandidates($Rs, $Lits, $F) {
  $out = @()
  foreach ($r in $Rs) {
    if ($r.kind -eq 'call' -and $script:RtOps.ContainsKey([string]$r.nm)) { $out += $r; continue }
    if ($r.kind -eq 'call' -and $r.tid -and [int]$r.tistart -gt 0 -and [string]$r.tkind -ne 'constructor') { $out += $r; continue }
    if ($r.kind -eq 'call' -and -not $r.tid -and $r.recv -and (Resolve-ImplByName ([string]$r.recv) ([string]$r.nm) $F).Count -eq 1) { $out += $r; continue }
    if ([string]$r.tkind -eq 'enum_value' -and ([string]$r.tname -like 'cmd*' -or [string]$r.tname -like 'rsp*')) { $out += $r }
  }
  foreach ($l in @($Lits | Where-Object { [string]$_.text -match $script:RtFibSqlRx })) { $out += [pscustomobject]@{ col = 0 } }
  , $out
}

# The OMITS disclosure (T5-R1): how many candidate calls were left out and the verbatim branch
# conditions that left them out (generated connectors, E1). $Recs: Count, Keyword, Condition,
# Anchor, Routine. A condition the note cannot carry ('; ') is named by its anchor only.
function New-OmitStep($Recs) {
  $n = [int](@($Recs) | Measure-Object -Property Count -Sum).Sum
  $rn = @($Recs | ForEach-Object { [string]$_.Routine } | Sort-Object -Unique)
  $seen = @{}; $cs = @()
  foreach ($r in $Recs) {
    $k = "$($r.Keyword)|$($r.Condition)|$($r.Anchor)"
    if ($seen.ContainsKey($k)) { continue }
    $seen[$k] = 1
    $cs += $(if ($r.Condition -match '; |[\r\n]') { "$($r.Keyword) at $($r.Anchor)" } else { "$($r.Keyword) `"$($r.Condition)`" @$($r.Anchor)" })
  }
  $s = New-TraceStep 'step' "OMITS $n call(s) in branches for other tables" $Recs[0].Anchor '' $(if ($rn.Count -eq 1) { $rn[0] } else { '' }) ('not walked, the branch conditions: ' + ($cs -join ' / ')) 'E1'
  $s | Add-Member -NotePropertyName Omits -NotePropertyValue @($Recs)
  $s
}

# ONE disclosure per section (T5-R1): the OMITS steps the walk left in a section become one, at the
# place of the first.
function Merge-TraceOmits($Section) {
  $om = @($Section.Items | Where-Object { $_.PSObject.Properties['Omits'] })
  if ($om.Count -lt 2) { return }
  $m = New-OmitStep @($om | ForEach-Object { $_.Omits })
  $m | Add-Member -NotePropertyName Line -NotePropertyValue $om[0].Line -Force
  $m | Add-Member -NotePropertyName Owner -NotePropertyValue $om[0].Owner -Force
  $Section.Items[$Section.Items.IndexOf($om[0])] = $m
  foreach ($o in @($om | Select-Object -Skip 1)) { $Section.Items.Remove($o) }
}

# One routine BODY, line by line, as trace items (spec section 4's classifier).
# Bound callees are walked and kept only when their subtree holds a step (drops
# logger noise); a CROSSES item carries .Command for the driver. Conditions hang
# on the step of their `if` line, else the nearest step of this body above it,
# else they come back in .Conds for the caller's CALLS step. A line inside a branch
# for ANOTHER table (T5-R1: its enclosing condition, read from fresh source, is
# `WHEN "<x> = '<TABLE>'"` for a known table that is not the anchor's) is not on
# the anchor's path: it is not walked, and one OMITS step counts it and quotes the
# condition. Only a routine whose literals name such a table is read for this.
function Walk-Routine([int] $Id, [int] $Depth, [hashtable] $Visited, $Ctx) {
  $items = New-Object System.Collections.ArrayList
  $pend  = New-Object System.Collections.ArrayList
  $res = [pscustomobject]@{ Items = $items; Conds = $pend }
  if ($Visited.ContainsKey($Id) -or $Depth -lt 0) { return $res }
  $Visited[$Id] = 1
  $F = Get-RoutineFacts $Id $Ctx.Likes
  if ($F.ImplStart -le 0) { return $res }
  # the body's refs and literals by line, built once (a per-line filter over the whole body is quadratic)
  $refsAt = @{}; $litsAt = @{}
  foreach ($r in $F.Refs) { $k = [int]$r.line; if (-not $refsAt.ContainsKey($k)) { $refsAt[$k] = New-Object System.Collections.ArrayList }; [void]$refsAt[$k].Add($r) }
  foreach ($l in $F.Lits) { $k = [int]$l.line; if (-not $litsAt.ContainsKey($k)) { $litsAt[$k] = New-Object System.Collections.ArrayList }; [void]$litsAt[$k].Add($l) }

  # the conditions: one per Exit the index anchored, quoted by the shim (E1). A condition two
  # Exits share is written once. The lines of the branch that ends in the Exit (its block,
  # less the `if` line itself) are the OTHER path: the condition's `-- else ...` note says
  # what they do, so the walk does not also list them as steps of the path that continues
  # (without this, SendDeltaOperation's `FMTOperation.CancelUpdates` at :3999 -- the failure
  # branch of the :3990 response guard -- read as a step between rspOK and CommitUpdates).
  $conds = @(); $condSeen = @{}; $skip = @{}
  foreach ($xl in @($F.Refs | Where-Object { $_.kind -eq 'call' -and [string]$_.nm -eq 'Exit' } | ForEach-Object { [int]$_.line } | Sort-Object -Unique)) {
    $g = Get-GuardCondition $F.Path $xl $F.ImplStart $Ctx.SourceOverride
    if ($g.Form -eq 'unknown') {
      Add-RtItem $items (New-TraceStep 'stops' (ConvertTo-TraceStopText $g.Reason) (Get-TraceAnchorText $F.Path $xl) '' $F.Short 'no condition is quoted for this Exit' 'E1') $xl $Id
      continue
    }
    for ($q = $g.BlockStart; $q -le $g.BlockEnd; $q++) { if ($q -ne $g.IfLine) { $skip[$q] = 1 } }
    $ck = "$($g.IfLine)|$($g.Keyword)|$($g.Condition)"
    if ($condSeen.ContainsKey($ck)) { continue }
    $condSeen[$ck] = 1
    # VERBATIM (P16 / T4-C1): the shim's text as it stands -- New-TraceCond refuses what it cannot carry
    $conds += [pscustomobject]@{ IfLine = $g.IfLine; Item = (New-TraceCond $g.Keyword $g.Condition (Get-TraceAnchorText $F.Path $g.IfLine) (Get-ElseNote $F $g $Ctx) 'E1') }
  }

  $others = @(@($Ctx.SqlSet.Names) | Where-Object { $Ctx.Table -and ([string]$_).ToUpperInvariant() -ne ([string]$Ctx.Table).ToUpperInvariant() } | ForEach-Object { ([string]$_).ToUpperInvariant() })
  $branchy = [bool](@($F.Lits | Where-Object { $_.kind -eq 'literal' -and $others -contains ([string]$_.text).ToUpperInvariant() }).Count)
  $omitItem = $null; $omitRecs = New-Object System.Collections.ArrayList
  # every line with a ref OR a literal: a SQL literal can stand on a line of its own (uDatasetsDef.pas:130)
  foreach ($ln in @(@($refsAt.Keys) + @($litsAt.Keys) | Sort-Object -Unique)) {
    if ($skip.ContainsKey($ln)) { continue }
    $rs   = @(if ($refsAt.ContainsKey($ln)) { $refsAt[$ln] })
    $lits = @(if ($litsAt.ContainsKey($ln)) { $litsAt[$ln] })
    if ($branchy) {
      $cand = Get-LineCandidates $rs $lits $F
      if ($cand.Count) {
        $col = [int](@($cand) | Measure-Object -Property col -Minimum).Minimum
        $e = Get-EnclosingCondition $F.Path $ln $col $F.ImplStart $Ctx.SourceOverride
        if ($e.Form -ne 'unknown' -and (Test-OtherTableBranch $e.Keyword $e.Condition $Ctx.Table $Ctx.SqlSet.Names)) {
          [void]$omitRecs.Add([pscustomobject]@{ Count = $cand.Count; Keyword = $e.Keyword; Condition = $e.Condition; Anchor = (Get-TraceAnchorText $F.Path $e.IfLine); Routine = $F.Short })
          if (-not $omitItem) { $omitItem = New-OmitStep $omitRecs; Add-RtItem $items $omitItem $ln $Id }
          continue
        }
      }
    }
    $enum = @($rs | Where-Object { [string]$_.tkind -eq 'enum_value' })
    $cmd  = @($enum | Where-Object { [string]$_.tname -like 'cmd*' })
    $rsp  = @($enum | Where-Object { [string]$_.tname -like 'rsp*' })
    $trans = @($rs | Where-Object { $_.kind -eq 'call' -and $_.tpipe -and [int]$_.tpipe -eq 1 })
    # CROSSES: a transport call carrying a protocol constant
    if ($trans.Count -and $cmd.Count) {
      $c = $cmd[0]
      $x = New-TraceStep 'crosses' 'process boundary' (Get-TraceAnchorText $F.Path $ln) '' $F.Short "$([string]$c.tname) via $([string]$trans[0].tname)"
      $x | Add-Member -NotePropertyName Command -NotePropertyValue ([string]$c.tname)
      [void]$x.Children.Add((New-TraceFacet 'FROM' $Ctx.NearIndex '' 'the index this side was read from'))
      [void]$x.Children.Add((New-TraceFacet 'TO' $Ctx.FarIndex '' 'the counterpart index, queried separately'))
      [void]$x.Children.Add((New-TraceFacet 'OVER' "$(Get-UnitName ([string]$trans[0].tpath)).$([string]$trans[0].tname)" (Get-TraceAnchorText ([string]$trans[0].tpath) ([int]$trans[0].tistart)) 'transport unit matched by naming convention'))
      [void]$x.Children.Add((New-TraceFacet 'WITH' "$([string]$c.tname) $(Get-PayloadText $F $ln $Ctx)" (Get-TraceAnchorText $F.Path $ln) 'payload inferred from the literals before the send'))
      [void]$x.Children.Add((New-TraceFacet 'CONTRACT' ([string]$c.tq) (Get-TraceAnchorText ([string]$c.tpath) ([int]$c.tdecl)) ''))
      Add-RtItem $items $x $ln $Id
      continue
    }
    # RESPONSE: a read of an rsp* constant
    if ($rsp.Count) {
      $verb = $(if (@($rs | Where-Object { $_.kind -eq 'write' }).Count) { 'SENDS' } else { 'RECEIVES' })
      Add-RtItem $items (New-TraceStep 'step' "$verb $((@($rsp | ForEach-Object { [string]$_.tname } | Sort-Object -Unique)) -join ' or ')" (Get-TraceAnchorText $F.Path $ln) '' $F.Short) $ln $Id
      continue
    }
    # DATASET OP / transaction / SQL execution
    $ops = @($rs | Where-Object { $_.kind -eq 'call' -and $script:RtOps.ContainsKey([string]$_.nm) })
    foreach ($o in $ops) {
      $recv = $(if ($o.recv) { [string]$o.recv + '.' } else { '' })
      Add-RtItem $items (New-TraceStep 'step' "$($script:RtOps[[string]$o.nm]) $recv$([string]$o.nm)$(Get-LineLits $lits)" (Get-TraceAnchorText $F.Path $ln) '' $F.Short) $ln $Id
    }
    if ($ops.Count) { continue }
    # a FIB$ literal in the body
    foreach ($l in @($lits | Where-Object { [string]$_.text -match $script:RtFibSqlRx })) {
      $k = "$($F.Path)|$ln"
      if ($Ctx.Seen.ContainsKey($k)) { continue }
      $Ctx.Seen[$k] = 1
      Add-RtItem $items (New-TraceStep 'step' "READS $(ConvertTo-TraceWord ([string]$l.text) 60)" (Get-TraceAnchorText $F.Path $ln) 'inferred' $F.Short 'a FIB$ literal in the body' 'E4') $ln $Id
    }
    # event wiring / attach: `<x>.<Event> := <Handler>`
    $ev = @($rs | Where-Object { $_.kind -eq 'member-access' -and [string]$_.nm -in $script:RtEvents })
    if ($ev.Count) {
      $h = @($rs | Where-Object { $_.kind -in 'read', 'member-access', 'call' -and [string]$_.nm -ne [string]$ev[0].nm -and [string]$_.nm -ne [string]$ev[0].recv } | Select-Object -Last 1)
      if ($h.Count) {
        $hs = Resolve-HandlerByName $h[0] $F
        if ($hs) {
          $verb = $(if ([string]$ev[0].nm -like 'On*') { 'ATTACHES' } else { 'FIRES' })
          Add-RtItem $items (New-TraceStep 'step' "$verb $([string]$ev[0].recv).$([string]$ev[0].nm) -> $($hs.Short)" (Get-TraceAnchorText $F.Path $ln) $hs.Grade $F.Short '' $hs.Ask) $ln $Id
          $sub = Walk-Routine $hs.Id ($Depth - 1) $Visited $Ctx
          Add-CallsStep $items $hs $sub $F $ln
          continue
        }
      }
    }
    # bound calls into project code (not transport, not constructors): descend
    foreach ($c in @($rs | Where-Object { $_.kind -eq 'call' -and $_.tid -and [int]$_.tistart -gt 0 -and -not ($_.tpipe -and [int]$_.tpipe -eq 1) -and [string]$_.tkind -ne 'constructor' })) {
      $sub = Walk-Routine ([int]$c.tid) ($Depth - 1) $Visited $Ctx
      $tgt = [pscustomobject]@{ Id = [int]$c.tid; Short = (Get-ShortName ([string]$c.tq) (Get-UnitName ([string]$c.tpath))); Path = [string]$c.tpath; Line = [int]$c.tistart; Grade = ''; Ask = '' }
      Add-CallsStep $items $tgt $sub $F $ln (Get-LineLits $lits)
    }
    # unbound calls with a receiver the index declares: the implementation BY NAME
    foreach ($c in @($rs | Where-Object { $_.kind -eq 'call' -and -not $_.tid -and $_.recv })) {
      $impl = Resolve-ImplByName ([string]$c.recv) ([string]$c.nm) $F
      $ask = $(if ($impl.Count -and (@(([string]$impl[0].rkinds) -split ',') | Where-Object { $_ -in 'field', 'property' })) { 'in-class-field-reads' } else { 'receiver-typed-calls' })
      if ($impl.Count -eq 1) {
        $i = $impl[0]
        $sub = Walk-Routine ([int]$i.id) ($Depth - 1) $Visited $Ctx
        $tgt = [pscustomobject]@{ Id = [int]$i.id; Short = (Get-ShortName ([string]$i.q) (Get-UnitName ([string]$i.path))); Path = [string]$i.path; Line = [int]$i.istart; Grade = 'by name'; Ask = $ask }
        Add-CallsStep $items $tgt $sub $F $ln (Get-LineLits $lits) -Always
        foreach ($fl in (Get-FibLiterals ([int]$i.fid))) {
          $k = "$([string]$i.path)|$([int]$fl.line)"
          if ($Ctx.Seen.ContainsKey($k)) { continue }
          $Ctx.Seen[$k] = 1
          Add-RtItem $items (New-TraceStep 'step' "READS $(ConvertTo-TraceWord ([string]$fl.text) 60)" (Get-TraceAnchorText ([string]$i.path) ([int]$fl.line)) 'inferred' ([string]$fl.routine) "a FIB`$ literal in $(Get-UnitName ([string]$i.path)), the unit of $($tgt.Short)" 'E4') $ln $Id
        }
      } elseif ($impl.Count -gt 1) {
        Add-RtItem $items (New-TraceStep 'stops' (ConvertTo-TraceStopText "$([string]$c.recv).$([string]$c.nm) is unbound and $($impl.Count) classes implement $([string]$c.nm)") (Get-TraceAnchorText $F.Path $ln) '' $F.Short '' $ask) $ln $Id
      }
    }
  }
  if ($omitItem) {
    $om = New-OmitStep $omitRecs
    $items[$items.IndexOf($omitItem)] = $om
    $om | Add-Member -NotePropertyName Line -NotePropertyValue $omitItem.Line -Force
    $om | Add-Member -NotePropertyName Owner -NotePropertyValue $Id -Force
  }
  # the routine's own SQL facts, at its last line so a condition never lands on them -- only the
  # anchor's table: a fact naming another table is not a step of this path (T5-R1)
  foreach ($fx in @(@('WRITES', $F.SqlWrites, 'sql_writes fact'), @('READS', $F.SqlReads, 'sql_reads fact'))) {
    $tabs = @(([string]$fx[1]) -split '[,;\s]+' | Where-Object { $_ -and $Ctx.Table -and $_.ToUpperInvariant() -eq ([string]$Ctx.Table).ToUpperInvariant() })
    if ($tabs.Count) { Add-RtItem $items (New-TraceStep 'step' "$($fx[0]) $($tabs[0].ToUpperInvariant())" (Get-TraceAnchorText $F.Path $F.ImplStart) '' $F.Short $fx[2]) $F.ImplEnd $Id }
  }
  foreach ($c in $conds) {
    $own = @($items | Where-Object { $_.Owner -eq $Id -and $_.Kind -ne 'stops' -and -not $_.PSObject.Properties['Omits'] })
    # $hostStep, never $host: $Host is PowerShell's read-only automatic variable (ruling P1)
    $hostStep = @($own | Where-Object { $_.Line -eq $c.IfLine } | Select-Object -First 1)
    if (-not $hostStep.Count) { $hostStep = @($own | Where-Object { $_.Kind -eq 'step' -and $_.Line -lt $c.IfLine } | Select-Object -Last 1) }
    if ($hostStep.Count) {
      # T5-R2: hung on the CALLS step of ANOTHER routine, the condition names its own routine
      if ($hostStep[0].PSObject.Properties['CalleeId'] -and [int]$hostStep[0].CalleeId -ne $Id) { $c.Item.Routine = $F.Short }
      [void]$hostStep[0].Children.Add($c.Item)
    } else { [void]$pend.Add($c.Item) }
  }
  $res
}

# ---- Part 4: the server side, run under the SERVER $DbPath ------------------------------
# DISPATCH (spec section 4; engine ask E2 retires it): a read of the command
# constant inside a transport-unit routine, then the first BOUND call after it
# whose target is declared OUTSIDE that unit (Task 1: the spec's plain "first
# call after it" picks the unit-local ParseTableFromPayload for cmdTableLoad),
# bounded by the next enum read (the next case arm or the error path).
function Find-DispatchArm([string] $CmdName, [string] $Likes) {
  $reads = Invoke-IndexQuery @"
SELECT r.start_line AS line, encl.id AS eid, encl.qualified_name AS routine, encl.impl_end_line AS iend, f.path AS path, f.id AS fid
  FROM refs r JOIN symbols tgt ON tgt.id = r.symbol_id JOIN symbols encl ON encl.id = r.enclosing_symbol_id
  JOIN files f ON f.id = encl.file_id JOIN symbols u ON u.file_id = f.id AND u.kind = 'unit'
 WHERE tgt.kind = 'enum_value' AND tgt.name = '$(ConvertTo-SqlText $CmdName)' AND ($Likes)
 ORDER BY f.path, r.start_line
"@ 'round-trip (dispatch reads)'
  foreach ($rd in $reads) {
    $next = Invoke-IndexQuery "SELECT MIN(r.start_line) AS l FROM refs r JOIN symbols t ON t.id = r.symbol_id WHERE r.enclosing_symbol_id = $([int]$rd.eid) AND t.kind = 'enum_value' AND r.start_line > $([int]$rd.line)"
    $hi = $(if ($next.Count -and $next[0].l) { [int]$next[0].l } else { [int]$rd.iend })
    $c = Invoke-IndexQuery @"
SELECT r.start_line AS line, t.id AS id, t.qualified_name AS q, t.kind AS kind, t.impl_start_line AS istart, t.start_line AS decl, t.name AS name, tf.path AS path
  FROM refs r JOIN call_edges ce ON ce.ref_id = r.id JOIN symbols t ON t.id = ce.target_symbol_id JOIN files tf ON tf.id = t.file_id
 WHERE r.enclosing_symbol_id = $([int]$rd.eid) AND r.start_line > $([int]$rd.line) AND r.start_line <= $hi AND t.file_id <> $([int]$rd.fid)
 ORDER BY r.start_line, r.start_col LIMIT 1
"@
    if ($c.Count) {
      return [pscustomobject]@{ Line = [int]$rd.line; Routine = (($([string]$rd.routine) -split '\.')[-1]); Path = [string]$rd.path; CallLine = [int]$c[0].line
                                Target = [pscustomobject]@{ id = [int]$c[0].id; q = [string]$c[0].q; kind = [string]$c[0].kind; istart = [int]$c[0].istart; decl = [int]$c[0].decl; path = [string]$c[0].path; name = [string]$c[0].name } }
    }
  }
  $null
}

# An interface method -> its ONE implementation, in a class whose heritage names the interface.
function Resolve-InterfaceImpl($Target) {
  $iface = (([string]$Target.q) -split '\.')[-2]
  $r = Invoke-IndexQuery @"
SELECT s.id AS id, s.qualified_name AS q, s.impl_start_line AS istart, f.path AS path
  FROM symbols s JOIN files f ON f.id = s.file_id
 WHERE s.name = '$(ConvertTo-SqlText $Target.name)' AND s.kind = 'method' AND s.impl_start_line > 0
   AND s.parent_id IN (SELECT c.id FROM symbols c WHERE c.kind = 'class' AND c.heritage LIKE '%$(ConvertTo-SqlText $iface)%')
"@
  , $r
}

function Get-ServerHandling([string] $CmdName, $Ctx, [int] $Depth) {
  $items = New-Object System.Collections.ArrayList
  $out = [pscustomobject]@{ Items = $items; Responses = @(); Contract = $null }
  $arm = Find-DispatchArm $CmdName $Ctx.Likes
  if (-not $arm) {
    $decl = Invoke-IndexQuery "SELECT s.start_line AS l, f.path AS p FROM symbols s JOIN files f ON f.id = s.file_id WHERE s.kind = 'enum_value' AND s.name = '$(ConvertTo-SqlText $CmdName)' LIMIT 1"
    $anchor = $(if ($decl.Count) { Get-TraceAnchorText ([string]$decl[0].p) ([int]$decl[0].l) } else { 'unknown:0' })
    Add-RtItem $items (New-TraceStep 'stops' (ConvertTo-TraceStopText "no transport routine of $($Ctx.FarIndex) reads $CmdName and then calls a handler declared in another unit") $anchor '' '' '' 'E2') 0 0
    return $out
  }
  $T = $arm.Target
  Add-RtItem $items (New-TraceStep 'step' "ROUTES $CmdName TO $(Get-ShortName $T.q (Get-UnitName $T.path))" (Get-TraceAnchorText $arm.Path $arm.Line) '' $arm.Routine "the first cross-unit call after the constant, at :$($arm.CallLine)" 'E2') $arm.Line 0
  $out.Contract = [pscustomobject]@{ Text = $T.q; Anchor = (Get-TraceAnchorText $T.path $T.decl) }
  $impl = $null; $grade = ''
  if ($T.istart -gt 0) {
    $impl = [pscustomobject]@{ Id = $T.id; Short = (Get-ShortName $T.q (Get-UnitName $T.path)); Path = $T.path; Line = $T.istart; Grade = '' }
  } else {
    $im = Resolve-InterfaceImpl $T
    if ($im.Count -ne 1) {
      Add-RtItem $items (New-TraceStep 'stops' (ConvertTo-TraceStopText "$($T.q) has $($im.Count) implementations in classes whose heritage names its interface") (Get-TraceAnchorText $T.path $T.decl) '' $arm.Routine '' 'E2') $arm.CallLine 0
      return $out
    }
    $impl = [pscustomobject]@{ Id = [int]$im[0].id; Short = (Get-ShortName ([string]$im[0].q) (Get-UnitName ([string]$im[0].path))); Path = [string]$im[0].path; Line = [int]$im[0].istart; Grade = 'by name' }
    $grade = 'by name'
  }
  $visited = @{}
  $sub = Walk-Routine $impl.Id $Depth $visited $Ctx
  $s = New-TraceStep 'step' "CALLS $($impl.Short)" (Get-TraceAnchorText $impl.Path $impl.Line) $grade $arm.Routine "from :$($arm.CallLine)$(if ($grade) { ', the interface method resolved to its one implementation' })" $(if ($grade) { 'E2' } else { '' })
  foreach ($c in $sub.Conds) { [void]$s.Children.Add($c) }
  Add-RtItem $items $s $arm.CallLine 0
  foreach ($i in $sub.Items) { [void]$items.Add($i) }
  $rsp = New-Object System.Collections.ArrayList
  foreach ($id in $visited.Keys) {
    $F = $script:RtFacts["$DbPath|$id"]
    if (-not $F) { continue }
    foreach ($e in @($F.Refs | Where-Object { [string]$_.tkind -eq 'enum_value' -and [string]$_.tname -like 'rsp*' })) { [void]$rsp.Add([string]$e.tname) }
  }
  $out.Responses = @($rsp | Sort-Object -Unique)
  $out
}

# DATABASE (ruling P15: the STOPS says only what was QUERIED). A SQL fact naming the
# anchor table is kept as is; otherwise the statement text is a STOPS naming
#   * the statement member -- `<recv>.UpdateSQL` for a write, `<recv>.SelectSQL` for a
#     read -- ONLY when a ref of a walked routine names it, anchored at that ref: the
#     APPLY's own ref first (a routine that also runs `<x>.Execute` / `ExecSQL`), else
#     the first in walk order; with no such ref, the routine and line of the apply
#     (the last RUNS / APPLIES step);
#   * "loaded at <file:line> from FIB$DATASETS_INFO" ONLY when one walked routine both
#     names that member and holds the walk's own FIB$DATASETS_INFO read;
#   * the fb_datasets row count of THIS index, counted now (fb_datasets is the engine's
#     snapshot of FIB$DATASETS_INFO; E4 asks for it to be populated).
# The column comes from the SQL index, [inferred]. Run under the SERVER $DbPath.
function Get-DatabaseSteps($ServerItems, $Ctx, [string] $Mode, $SqlSet, [hashtable] $SourceOverride) {
  $items = New-Object System.Collections.ArrayList
  $verb = $(if ($Mode -eq 'write') { 'WRITES' } else { 'READS' })
  $fact = @($ServerItems | Where-Object { $_.Kind -eq 'step' -and $_.Text -match "^$verb .*\b$([regex]::Escape($Ctx.Table))\b" })
  $tblFile = $SqlSet.Tables[$Ctx.Table].File; $tblLine = $SqlSet.Tables[$Ctx.Table].Line
  if (-not $fact.Count) {
    $stmtName = $(if ($Mode -eq 'write') { 'UpdateSQL' } else { 'SelectSQL' })
    $kind = $(if ($Mode -eq 'write') { 'UPDATE' } else { 'SELECT' })
    $naming = @()
    foreach ($own in @($ServerItems | Where-Object { $_.Owner -gt 0 } | ForEach-Object { [int]$_.Owner } | Select-Object -Unique)) {
      $F = $script:RtFacts["$DbPath|$own"]
      if (-not $F) { continue }
      foreach ($m in @($F.Refs | Where-Object { $_.kind -eq 'member-access' -and [string]$_.nm -eq $stmtName })) { $naming += [pscustomobject]@{ F = $F; Ref = $m } }
    }
    $applyOwners = @($ServerItems | Where-Object { $_.Kind -eq 'step' -and $_.Text -match '^RUNS (\S+\.)?(Execute|ExecSQL)\b' } | ForEach-Object { [int]$_.Owner })
    $pick = @($naming | Where-Object { $applyOwners -contains $_.F.Id } | Select-Object -First 1)
    if (-not $pick.Count) { $pick = @($naming | Select-Object -First 1) }
    $loader = $null
    foreach ($fs in @($ServerItems | Where-Object { $_.Kind -eq 'step' -and $_.Text -match '^READS .*FIB\$DATASETS_INFO' })) {
      $fsFile, $fsLine = $fs.Anchor -split ':'
      $hit = @($naming | Where-Object { [IO.Path]::GetFileName($_.F.Path) -eq $fsFile -and [int]$fsLine -ge $_.F.ImplStart -and [int]$fsLine -le $_.F.ImplEnd } | Select-Object -First 1)
      if ($hit.Count) { $loader = $hit[0]; break }
    }
    $fb = [int](Invoke-IndexQuery 'SELECT COUNT(*) AS n FROM fb_datasets')[0].n
    $held = $(if ($fb -eq 0) { "fb_datasets has 0 rows in $($Ctx.FarIndex)" } else { "fb_datasets has $fb rows in $($Ctx.FarIndex), which this walk does not look up" })
    if ($pick.Count) {
      $p0 = $pick[0]
      $sText = "$(if ($p0.Ref.recv) { [string]$p0.Ref.recv + '.' })$stmtName"
      $src = $(if ($loader) { ", loaded at $(Get-TraceAnchorText $loader.F.Path ([int]$loader.Ref.line)) from FIB`$DATASETS_INFO rows$(if ($fb -eq 0) { ' the index does not hold' })" } else { ', whose text the walk does not read' })
      $why = "the $kind statement for $($Ctx.Table) is $sText$src ($held)"
      $anchor = Get-TraceAnchorText $p0.F.Path ([int]$p0.Ref.line); $rn = $p0.F.Short
      $nt = "the statement member is named here$(if ($applyOwners -contains $p0.F.Id) { ', in the routine that executes it' })"
    } else {
      $last = @($ServerItems | Where-Object { $_.Kind -eq 'step' -and $_.Text -match '^(RUNS|APPLIES) ' } | Select-Object -Last 1)
      if (-not $last.Count) { $last = @($ServerItems | Where-Object { $_.Kind -ne 'crosses' } | Select-Object -Last 1) }
      $why = "no walked routine names the $kind statement for $($Ctx.Table)$(if ($last.Count) { ", applied in $($last[0].Routine) at $($last[0].Anchor)" }) ($held)"
      $anchor = $(if ($last.Count) { $last[0].Anchor } else { Get-TraceAnchorText $tblFile $tblLine }); $rn = $(if ($last.Count) { $last[0].Routine } else { '' }); $nt = ''
    }
    Add-RtItem $items (New-TraceStep 'stops' (ConvertTo-TraceStopText $why) $anchor '' $rn $nt 'E4') 0 0
  }
  $cs = Get-SqlColumnState $SqlSet $Ctx.Table $Ctx.Column $SourceOverride
  if ($cs.IsColumn) {
    # the label is GENERATED text with bracketed grade tags; as a note they read `(certain)` (as the anchor's column step)
    $lbl = ([string]$cs.Label) -replace '\[([^\]]*)\]', '($1)'
    Add-RtItem $items (New-TraceStep 'step' "$verb $($Ctx.TableColumn)" (Get-TraceAnchorText $cs.File ([int]$cs.Line)) 'inferred' '' (ConvertTo-TraceWord "column $($Ctx.Column) of $($Ctx.Table): $lbl") 'E4') 0 0
  } else {
    Add-RtItem $items (New-TraceStep 'stops' (ConvertTo-TraceStopText "$($Ctx.TableColumn): $($cs.Label)") (Get-TraceAnchorText $tblFile $tblLine) '' '' '' 'E4') 0 0
  }
  , $items.ToArray()
}

# The event wiring on the anchor dataset in its unit: `<ds>.<Event> := <Handler>`.
# The handler is the last plain READ on the wiring line and is matched BY NAME
# among the dataset's class methods (E3: the assignment is not bound).
function Get-EventWiring($Ds) {
  $rows = Get-AllIndexRows @"
SELECT r.start_line AS line, r.id AS rid, r.name_text AS ev, e.qualified_name AS routine,
       (SELECT h.name_text FROM refs h WHERE h.file_id = r.file_id AND h.start_line = r.start_line AND h.kind = 'read' AND h.name_text <> '$(ConvertTo-SqlText $Ds.Name)' AND h.name_text <> r.name_text ORDER BY h.start_col DESC LIMIT 1) AS handler
  FROM refs r LEFT JOIN symbols e ON e.id = r.enclosing_symbol_id
 WHERE r.file_id = $($Ds.Fid) AND r.kind = 'member-access' AND r.name_text IN ($(ConvertTo-SqlInList $script:RtEvents)) AND r.receiver_text = '$(ConvertTo-SqlText $Ds.Name)'
"@ 'r.start_line, r.id'
  $out = New-Object System.Collections.ArrayList
  foreach ($r in $rows) {
    if (-not $r.handler) { continue }
    $h = Invoke-IndexQuery "SELECT s.id AS id, s.qualified_name AS q, s.impl_start_line AS istart, f.path AS path FROM symbols s JOIN files f ON f.id = s.file_id WHERE s.parent_id = $($Ds.ClassId) AND s.name = '$(ConvertTo-SqlText ([string]$r.handler))' AND s.kind = 'method' AND s.impl_start_line > 0"
    if ($h.Count -ne 1) { continue }
    [void]$out.Add([pscustomobject]@{ Line = [int]$r.line; Event = [string]$r.ev; Handler = [string]$r.handler; HandlerId = [int]$h[0].id
                                       HandlerShort = (Get-ShortName ([string]$h[0].q) (Get-UnitName ([string]$h[0].path))); HandlerImpl = [int]$h[0].istart; HandlerPath = [string]$h[0].path
                                       Routine = (($([string]$r.routine) -split '\.')[-1]); Grade = 'by name' })
  }
  , $out.ToArray()
}
