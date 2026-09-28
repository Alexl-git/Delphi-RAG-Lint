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
# ' [' and ' -- '; a note refuses '; ', its separator)
function ConvertTo-TraceWord([string] $s, [int] $Max = 72) {
  $t = (([string]$s) -replace '\s+', ' ').Trim() -replace ' -- ', ' - ' -replace ' @', ' at ' -replace '\[', '(' -replace '\]', ')' -replace '"', "'" -replace '; ', ', '
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
    [void]$R.Items.Add((New-TraceStep 'step' "READS $($R.TableColumn)" (Get-TraceAnchorText $cs.File ([int]$cs.Line)) 'inferred' '' (ConvertTo-TraceWord "column $($R.Column) of $($R.Table): $($cs.Label)") 'E4'))
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

# <Unit>.<TClass>.<FfX>: a TField variable. Its dataset and column come from the
# lines that WRITE it (a bound write): on such a line, the dataset is a field of
# the same class with a dataset type that the line names (a read, or the receiver
# of `.FieldByName`), and the column is the line's ONE string literal. That covers
# `FfX := FMT.FieldByName('COL')` and a helper call `FfX := FF(FMT, 'COL')`
# (Blueprint4.ViewModel.pas:939). An in-class read is unbound in this index, so a
# dataset matched by NAME is graded [by name] (INBOX-in-class-field-reads-unbound).
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
  $byName = -not ([int]$(if ($site.bound) { $site.bound } else { 0 }))
  [void]$R.Items.Add((New-TraceStep 'step' "SETS $Name := $dsName field '$col'" (Get-TraceAnchorText ([string]$site.path) ([int]$site.line)) $(if ($byName) { 'by name' } else { '' }) '' `
                       $(if ($byName) { "the TField variable, its dataset $dsName matched by name among the class's dataset fields" } else { 'the TField variable' }) $(if ($byName) { 'in-class-field-reads' } else { '' })))
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
