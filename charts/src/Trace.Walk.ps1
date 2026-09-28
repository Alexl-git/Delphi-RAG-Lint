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
#                                                     quoted "S1 .. Sn raises" -- which one raises is not in the source
#   case    `case X of .. else .. Exit`            -> UNLESS "case X of else"
#   unknown anything else (a loop, a case arm, no branch, a condition holding a double-quote) --
#           Reason is plain GENERATED text the walker writes as a STOPS naming E1; never a guess, never a throw
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
      elseif ($ch -eq '{') { $j = $r.IndexOf('}', $i + 1); $i = $(if ($j -lt 0) { $b } else { $j + 1 }) }
      elseif ($ch -eq '(' -and $i + 1 -lt $b -and $r[$i + 1] -eq '*') { $j = $r.IndexOf('*)', $i + 2); $i = $(if ($j -lt 0) { $b } else { $j + 2 }) }
      else { $i++ }      # the tail of a comment opened on an earlier line
    }
    if ($first -ge 0) { $pieces += $r.Substring($first, $last - $first + 1) }
  }
  $pieces -join ' '
}

function New-ShimResult($X, [string] $Form, [string] $Keyword, [string] $Condition, [int] $IfLine, [int] $BlockStart, [int] $BlockEnd, [string] $Reason = '') {
  if ($Form -ne 'unknown' -and $Condition.Contains('"')) {
    return (New-ShimResult $X 'unknown' '' '' 0 0 0 "the condition over the Exit at :$($X.ExitLine) holds a double-quote, which a Form A condition cannot carry verbatim")
  }
  [pscustomobject]@{ Form = $Form; Keyword = $Keyword; Condition = $Condition; IfLine = $IfLine; BlockStart = $BlockStart; BlockEnd = $BlockEnd; ExitArg = $X.ExitArg; Reason = $Reason }
}

function New-ShimUnknown($X, [string] $Why) { New-ShimResult $X 'unknown' '' '' 0 0 0 "the Exit at :$($X.ExitLine) $Why, a shape the source shim does not read" }

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

function New-ShimIfResult($X, [int] $ThenIdx, [string] $Keyword, [int[]] $Blk) {
  $i = Find-ShimIf $X $ThenIdx
  if ($i -lt 0) { return (New-ShimUnknown $X 'follows a then with no if before it') }
  $it = $X.Tok[$i]; $th = $X.Tok[$ThenIdx]
  $cond = Get-ShimSpanText $X.Raw $X.Stripped $it.L $it.E $th.L $th.C
  New-ShimResult $X $(if ($it.L -eq $X.ExitLine) { 'inline' } else { 'block' }) $Keyword $cond $it.L $Blk[0] $Blk[1]
}

function New-ShimCaseResult($X, [int] $CaseIdx, [int] $ElseIdx) {
  $ca = $X.Tok[$CaseIdx]
  $of = @(for ($q = $CaseIdx + 1; $q -lt $X.Tok.Count; $q++) { if ($X.Tok[$q].T -eq 'of') { $X.Tok[$q]; break } })
  if (-not $of.Count) { return (New-ShimUnknown $X 'sits in a case with no of') }
  New-ShimResult $X 'case' 'UNLESS' ((Get-ShimSpanText $X.Raw $X.Stripped $ca.L $ca.C $of[0].L $of[0].E) + ' else') $ca.L $X.Tok[$ElseIdx].L (Find-BlockEnd $X.Stripped $ca.L $ca.C)
}

# The Exit sits in the handler of the try at token $TryIdx (its `except` at $ExIdx):
# the protected statements are the depth-0 `;`-separated spans of the try body.
function New-ShimExceptResult($X, [int] $TryIdx, [int] $ExIdx) {
  $tr = $X.Tok[$TryIdx]; $ex = $X.Tok[$ExIdx]
  $stm = @(); $sl = $tr.L; $sc = $tr.E
  $semis = Get-ShimLevelTokens $X $TryIdx $ExIdx @(';')
  foreach ($q in (@($semis) + $ExIdx)) {
    $e = $X.Tok[$q]
    $txt = Get-ShimSpanText $X.Raw $X.Stripped $sl $sc $e.L $e.C
    if ($txt) { $stm += $txt }
    $sl = $e.L; $sc = $e.E
  }
  if (-not $stm.Count) { return (New-ShimUnknown $X 'sits in the handler of an empty try') }
  $s = $(if ($stm.Count -eq 1) { $stm[0] } else { "$($stm[0]) .. $($stm[-1])" })
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
  $X = [pscustomobject]@{ Raw = $Raw; Stripped = $Stripped; ExitLine = $ExitLine; ExitArg = ''; Tok = $null }
  if ($ExitLine -lt 1 -or $ExitLine -gt $Stripped.Count) { return (New-ShimUnknown $X 'is outside the file') }
  $s = $Stripped[$ExitLine - 1]
  $em = [regex]::Match($s, '(?i)\bExit\b')
  if (-not $em.Success) { return (New-ShimUnknown $X 'is not an Exit in this copy of the file') }
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
