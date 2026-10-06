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

# FW-R2 (final review): a bare `:N` in a generated NOTE means "line N of the step's OWN anchor
# file" -- write `File.pas:N` instead whenever the referenced line lives in a DIFFERENT file than
# that anchor, so the locator is never ambiguous (a property's field is bound on an assignment
# line that sits in the FORM unit, not the field's own declaring unit -- Resolve-PropertyReadField).
function Get-TraceNoteLocator([string] $AnchorFile, [string] $RefFile, [int] $RefLine) {
  $(if (([IO.Path]::GetFileName($AnchorFile)) -eq ([IO.Path]::GetFileName($RefFile))) { ":$RefLine" } else { Get-TraceAnchorText $RefFile $RefLine })
}

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
                     Stop = ''; StopAnchor = ''; StaleFile = ''; Grades = @(); Calc = $null }
}

# The note of a column step (final-review I7): what the SQL index says about the column, as GENERATED
# text, never truncated (T3-M2). It states the SQL fact on its own terms -- the step's [inferred] grade is
# the dataset -> table hop, and the note must not read as grading the column. An extracted column reads
# `NAME is a column of the newest of 2 OPERAT declarations (SQL index, MS1.SQL:2809)`; any other state
# (quoted, older declaration, server SQL) keeps Get-SqlColumnState's label, made safe for a note.
function Get-ColumnFactNote($Cs, $SqlSet) {
  $n = [int]$SqlSet.Tables[[string]$Cs.Table].DeclCount
  $at = "$([IO.Path]::GetFileName([string]$Cs.File)):$([int]$Cs.Line)"
  if ($Cs.State -eq 'yes') {
    $of = $(if ($n -gt 1) { "the newest of $n $($Cs.Table) declarations" } else { "the $($Cs.Table) declaration" })
    return "$($Cs.Column) is a column of $of (SQL index, $at)"
  }
  ConvertTo-TraceStopText "$($Cs.Column) of $($Cs.Table) in the SQL scripts: $(([string]$Cs.Label) -replace '\[([^\]]*)\]', '($1)')"
}

# The table beside the dataset (a literal of the SQL table set on a line that reads
# the dataset field), then the column in the SQL index. Shared by every anchor form.
function Complete-AnchorFromDataSet($R, $Ds, [string] $Col, $SqlSet, [hashtable] $SourceOverride, [string] $BindGrade = '', [string] $BindNote = 'the anchor dataset') {
  $R.DataSet = $Ds
  [void]$R.Items.Add((New-TraceStep 'step' "BINDS $($Ds.Name) : $($Ds.Type)" (Get-TraceAnchorText $Ds.File $Ds.Line) $BindGrade '' $BindNote))
  $lit = Get-DataSetTableLiterals $Ds $SqlSet      # Emit-Common: shared with feeds-from / lands-where
  if ($lit.Count -ne 1) {
    $R.Stop = $(if ($lit.Count -eq 0) { "no upper-case table-name literal shares a line with $($Ds.Name) in $(Get-UnitName $Ds.File) -- the table cannot be inferred" }
                else { "$($lit.Count) tables share a line with $($Ds.Name) in $(Get-UnitName $Ds.File) ($((@($lit | ForEach-Object { [string]$_.t })) -join ', ')) -- cannot tell which" })
    $R.StopAnchor = Get-TraceAnchorText $Ds.File $Ds.Line
    return $R
  }
  $R.Table = [string]$lit[0].t
  $encl = Invoke-IndexQuery "SELECT e.qualified_name AS q FROM refs r JOIN symbols e ON e.id = r.enclosing_symbol_id WHERE r.file_id = $($Ds.Fid) AND r.start_line = $([int]$lit[0].line) AND r.name_text = '$(ConvertTo-SqlText $Ds.Name)' LIMIT 1"
  $rn = $(if ($encl.Count) { (([string]$encl[0].q) -split '\.')[-1] } else { '' })
  # final-review M2: no ask -- that the literal names the dataset's table is the walk's inference from a shared
  # line; E4 (fb_datasets rows) holds server-side definitions and would not retire it
  [void]$R.Items.Add((New-TraceStep 'step' "READS $($R.Table)" (Get-TraceAnchorText $Ds.File ([int]$lit[0].line)) 'inferred' $rn "the table literal beside $($Ds.Name) on $($lit[0].n) line(s)"))
  if (-not $Col) { $R.Stop = "$($Ds.Name) reaches $($R.Table) but the selection binds no column"; $R.StopAnchor = Get-TraceAnchorText $Ds.File $Ds.Line; return $R }
  $R.Column = $Col.ToUpperInvariant()
  $R.TableColumn = "$($R.Table).$($R.Column)"
  $cs = Get-SqlColumnState $SqlSet $R.Table $Col $SourceOverride
  if ($cs.IsColumn) {
    # final-review I7: the column fact as a GENERATED note, never truncated (T3-M2) -- Get-ColumnFactNote
    [void]$R.Items.Add((New-TraceStep 'step' "READS $($R.TableColumn)" (Get-TraceAnchorText $cs.File ([int]$cs.Line)) 'inferred' '' (Get-ColumnFactNote $cs $SqlSet) 'E4'))
  } else {
    $R.Stop = "$($R.TableColumn): $($cs.Label)"
    $R.StopAnchor = $R.Items[$R.Items.Count - 1].Anchor
    # calc-field brief (owner, 2026-09-28): before that stop, is the field CALCULATED (Part 6)? Only an
    # OnCalcFields handler that writes it makes it one; the stop then says so and the emitter offers its
    # source fields. A field set in another event, or created as a lookup, is a named stop with no offer.
    $cf = Get-CalcFieldInfo $Ds $Col $R.Table $SqlSet $SourceOverride
    if ($cf) { $R.Calc = $cf; $R.Stop = $cf.StopText; $R.StopAnchor = $cf.Anchor }
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
  # the re-point rule (nil sites skipped, a stale form unit REFUSES, several different right-hand
  # sides a named stop) is Get-RePointPick in Emit-Common -- ONE copy, shared with feeds-from and
  # lands-where since 2026-10-05
  $pk = $(if ($ch.Grade -eq 'dangling') { Get-RePointPick $ch $owner $SourceOverride } else { $null })
  if ($pk -and $pk.Status -eq 'stale') { $R.StaleFile = $pk.StaleFile; $R.Stop = $pk.Stop; $R.StopAnchor = $s1.Anchor; return $R }
  if ($pk -and $pk.Status -eq 'multi-rhs') { $R.Stop = $pk.Stop; $R.StopAnchor = $s1.Anchor; return $R }
  if ($pk -and $pk.Status -eq 'follow') {
    $rc = Get-RePointChain $pk.Rows[0] $SourceOverride
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
    # final-review M2: the ask that would retire THIS hop's grade, or none -- E4 (populated fb_datasets) retires none
    # of them. rhs-type [by name]: the declared type is matched to a class by NAME because no `type_use` ref is bound
    # (0 of 60,603 on the CLIENT clone) -- ask type-use-binding. A datasource resolved through a module name, or a
    # dataset picked among several right-hand sides, is the walk's own choice: no engine fact retires it
    $ask = $(if ($grade -and $h.Hop -eq 'rhs-type') { 'type-use-binding' } else { '' })
    [void]$R.Items.Add((New-TraceStep 'step' "$verb $(ConvertTo-TraceWord $h.Label 90)" (Get-TraceAnchorText $h.File $h.Line) $grade '' (ConvertTo-TraceNoteText $h.Reason) $ask))
  }
  $a0 = $assign[0]
  $dsName = (($a0.Rhs -replace '^Self\.', '') -split '\.')[-1]
  $tf = Invoke-IndexQuery "SELECT s.id AS id FROM symbols s JOIN files f ON f.id = s.file_id WHERE f.path = '$(ConvertTo-SqlText $ch.RhsType.TypeFile)' AND s.kind IN ('class','interface') AND UPPER(s.name) = UPPER('$(ConvertTo-SqlText $ch.RhsType.TypeName)')"
  $dsRow = $(if ($tf.Count -eq 1) { Invoke-IndexQuery "SELECT s.id AS id, s.name AS name, s.kind AS kind, s.signature AS sig, s.start_line AS line, f.path AS path, s.file_id AS fid, s.parent_id AS pid FROM symbols s JOIN files f ON f.id = s.file_id WHERE s.parent_id = $([int]$tf[0].id) AND s.name = '$(ConvertTo-SqlText $dsName)' AND s.kind IN ('field','property')" } else { , @() })
  if ($dsRow.Count -ne 1) { $R.Stop = "the dataset $($a0.Rhs) (assigned at :$($a0.Line)) is not a field or property of $($ch.RhsType.TypeName) in this index"; $R.StopAnchor = Get-TraceAnchorText $a0.File $a0.Line; return $R }
  $d = $dsRow[0]
  if ([string]$d.kind -eq 'property') {
    # final-review I8: a PROPERTY is not the dataset -- its read accessor is. The wirings and the table literal
    # sit on the FIELD behind it (uCausFail.ViewModel: property MemTable, `read FMemTable`), so the anchor follows
    # the accessor to that field, as Get-RePointChain does, and stops (if it must) on the field
    $pf = Resolve-PropertyReadField $d $a0 $SourceOverride
    [void]$R.Items.Add((New-TraceStep 'step' "READS $([string]$d.name) : $(([string]$d.sig).Trim())" (Get-TraceAnchorText ([string]$d.path) ([int]$d.line)) '' '' "a property of $($ch.RhsType.TypeName)$(if ($pf.Accessor) { ", read $($pf.Accessor)" })"))
    if ($pf.StaleFile) { $R.StaleFile = $pf.StaleFile; $R.Stop = $pf.Reason; $R.StopAnchor = $R.Items[$R.Items.Count - 1].Anchor; return $R }
    if (-not $pf.Field) { $R.Stop = $pf.Reason; $R.StopAnchor = $R.Items[$R.Items.Count - 1].Anchor; return $R }
    $d = $pf.Field
    return (Complete-AnchorFromDataSet $R ([pscustomobject]@{ Name = [string]$d.name; Id = [int]$d.id; ClassId = [int]$d.pid; File = [string]$d.path; Fid = [int]$d.fid; Line = [int]$d.line; Type = ([string]$d.sig).Trim() }) $col $SqlSet $SourceOverride $pf.Grade "the anchor dataset, $($pf.Reason)")
  }
  Complete-AnchorFromDataSet $R ([pscustomobject]@{ Name = [string]$d.name; Id = [int]$d.id; ClassId = [int]$d.pid; File = [string]$d.path; Fid = [int]$d.fid; Line = [int]$d.line; Type = ([string]$d.sig).Trim() }) $col $SqlSet $SourceOverride
}

# final-review I8: the FIELD a dataset property reads. The index fact first -- the member_accesses row of the
# property's ref on the assignment line ($Assign: File, Line), whose accessor is a field (certain); else the
# `read <X>` accessor quoted from the FRESH declaration line and the field of that name in the property's class
# ([by name], as Get-RePointChain grades it). Returns Field ($null | id, name, sig, line, path, fid, pid),
# Accessor, Grade, Reason (the stop reason when Field is $null), StaleFile.
function Resolve-PropertyReadField($Prop, $Assign, [hashtable] $SourceOverride) {
  $fq = 'SELECT s.id AS id, s.name AS name, s.signature AS sig, s.start_line AS line, f.path AS path, s.file_id AS fid, s.parent_id AS pid FROM symbols s JOIN files f ON f.id = s.file_id'
  $out = [pscustomobject]@{ Field = $null; Accessor = ''; Grade = ''; Reason = ''; StaleFile = '' }
  $ma = Invoke-IndexQuery @"
SELECT DISTINCT ma.accessor_symbol_id AS aid FROM member_accesses ma JOIN refs r ON r.id = ma.ref_id JOIN files f ON f.id = r.file_id
 WHERE f.path = '$(ConvertTo-SqlText ([string]$Assign.File))' AND r.start_line = $([int]$Assign.Line) AND ma.member_symbol_id = $([int]$Prop.id)
   AND ma.accessor_kind = 'field' AND ma.accessor_symbol_id IS NOT NULL
"@
  if ($ma.Count -eq 1) {
    $fr = Invoke-IndexQuery "$fq WHERE s.id = $([int]$ma[0].aid) AND s.kind = 'field'"
    if ($fr.Count -eq 1) {
      $out.Field = $fr[0]; $out.Accessor = [string]$fr[0].name
      # FW-R2 (final review): the BINDS step this note attaches to anchors on the FIELD's own
      # declaring file ($fr[0].path, as Complete-AnchorFromDataSet uses it) -- the assignment can
      # sit in a DIFFERENT file (the form that wires the datasource), so a bare `:N` would silently
      # misread as a line of the field's file. Get-TraceNoteLocator qualifies it when the files differ.
      $out.Reason = "the read accessor of $([string]$Prop.name), bound on the assignment line $(Get-TraceNoteLocator ([string]$fr[0].path) ([string]$Assign.File) ([int]$Assign.Line))"
      return $out
    }
  }
  if (-not (Test-SourceFresh ([string]$Prop.path) $SourceOverride)) {
    $out.StaleFile = [string]$Prop.path; $out.Reason = "$([IO.Path]::GetFileName([string]$Prop.path)) differs from the indexed copy -- the property's read accessor is not read"; return $out
  }
  $pl = (Get-StrippedSourceLines (Resolve-SourceReadPath ([string]$Prop.path) $SourceOverride))[[int]$Prop.line - 1]
  if ($pl -notmatch '\bread\s+([A-Za-z_][A-Za-z0-9_]*)') { $out.Reason = "property $([string]$Prop.name) at $([IO.Path]::GetFileName([string]$Prop.path)):$([int]$Prop.line) has no read accessor on its declaration line"; return $out }
  $out.Accessor = $Matches[1]
  $fr = Invoke-IndexQuery "$fq WHERE s.parent_id = $([int]$Prop.pid) AND s.name = '$(ConvertTo-SqlText $out.Accessor)' AND s.kind = 'field'"
  if ($fr.Count -ne 1) { $out.Reason = "the read accessor $($out.Accessor) of $([string]$Prop.name) is not a field of its class ($($fr.Count) matches) -- a getter method is not followed"; return $out }
  $out.Field = $fr[0]; $out.Grade = 'by name'; $out.Reason = "the read accessor of $([string]$Prop.name), by name in its class"
  $out
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
  $w = Get-FieldVarWriteRows $cpid "r.symbol_id = $([int]$Mem.id)"
  # a pair only where the line names exactly ONE dataset field and ONE literal
  $fp = Get-FieldVarPairs $w
  $ok = $fp.Ok; $pairs = $fp.Pairs
  if ($pairs.Count -ne 1) {
    $R.Stop = "$Target is written on $($w.Count) line(s) naming $($pairs.Count) (dataset field, column literal) pair(s)$(if ($pairs.Count) { " ($(($pairs | ForEach-Object { $_ -replace '\|', '.' }) -join ', '))" }) -- cannot tell which"
    $R.StopAnchor = Get-TraceAnchorText ([string]$Mem.path) ([int]$Mem.line)
    return $R
  }
  $dsName, $col = $pairs[0] -split '\|'
  $dsRow = Invoke-IndexQuery "SELECT s.id AS id, s.name AS name, s.signature AS sig, s.start_line AS line, f.path AS path, s.file_id AS fid, s.parent_id AS pid FROM symbols s JOIN files f ON f.id = s.file_id WHERE s.parent_id = $cpid AND s.name = '$(ConvertTo-SqlText $dsName)' AND s.kind = 'field'"
  if ($dsRow.Count -ne 1) { $R.Stop = "$dsName is not a field of the class declaring $Name"; $R.StopAnchor = Get-TraceAnchorText ([string]$Mem.path) ([int]$Mem.line); return $R }
  $site = $ok[0]
  $g = Get-FieldVarSiteGrade $site $dsName
  [void]$R.Items.Add((New-TraceStep 'step' "SETS $Name := $dsName field '$col'" (Get-TraceAnchorText ([string]$site.path) ([int]$site.line)) $g.Grade '' $g.Reason $g.Ask))
  $d = $dsRow[0]
  Complete-AnchorFromDataSet $R ([pscustomobject]@{ Name = [string]$d.name; Id = [int]$d.id; ClassId = [int]$d.pid; File = [string]$d.path; Fid = [int]$d.fid; Line = [int]$d.line; Type = ([string]$d.sig).Trim() }) $col $SqlSet $SourceOverride
}

# The WRITE lines of the TField variables of class $ClassId that $Where selects (a condition on `r`,
# the write ref), each with what Resolve-AnchorFromFieldVar reads off the line: the dataset fields of
# the class the line names (ds), whether one is a bound read (bound), the FieldByName count (fbn), the
# call names (calls) and the literals (col). var: the variable's name, vq its qualified name. Shared by
# the TField-variable anchor and the calc-field check (Part 6), so both read ONE rule.
function Get-FieldVarWriteRows([int] $ClassId, [string] $Where) {
  # calc-field fix round 2: ONE pass over the refs of the write lines (materialized), the class's dataset fields
  # passed as IN-lists. The per-line correlated `JOIN symbols s ON ... (s.name = m.name_text OR ...)` took ~9-10 s
  # over one class's 133 write lines under load -- the engine's 10 s cap. Same facts, compared row for row on every
  # class of the CLIENT clone: ds = the dataset fields a line names (a read, or a FieldByName's receiver, bare or
  # `Self.`); bound = a read ref BOUND to one; fbn = the FieldByName refs on one; calls; col (the literals).
  $dsf = Invoke-IndexQuery "SELECT s.id AS id, s.name AS name FROM symbols s WHERE s.parent_id = $ClassId AND s.kind = 'field' AND $(Get-DataSetTypeSql 's')"
  $names = $(if ($dsf.Count) { ConvertTo-SqlInList @($dsf | ForEach-Object { [string]$_.name }) } else { 'NULL' })
  $selfs = $(if ($dsf.Count) { ConvertTo-SqlInList @($dsf | ForEach-Object { "Self.$([string]$_.name)" }) } else { 'NULL' })
  $ids = $(if ($dsf.Count) { (@($dsf | ForEach-Object { [int]$_.id })) -join ',' } else { 'NULL' })
  $dk = "(lm.kind = 'read' OR (lm.kind = 'member-access' AND lm.nm = 'FieldByName'))"
  Get-AllIndexRows @"
WITH w AS MATERIALIZED (SELECT v.name AS var, v.qualified_name AS vq, r.start_line AS line, r.file_id AS fid, r.id AS rid FROM refs r JOIN symbols v ON v.id = r.symbol_id WHERE $Where AND r.kind = 'write'),
     lm AS MATERIALIZED (SELECT m.file_id AS fid, m.start_line AS line, m.kind AS kind, m.name_text AS nm, m.receiver_text AS rc, m.symbol_id AS sid FROM refs m
                          WHERE m.file_id IN (SELECT fid FROM w) AND m.start_line IN (SELECT line FROM w)),
     dsn AS MATERIALIZED (SELECT fid, line, nm AS x FROM lm WHERE $dk AND nm IN ($names)
              UNION ALL SELECT fid, line, rc FROM lm WHERE $dk AND rc IN ($names)
              UNION ALL SELECT fid, line, SUBSTR(rc, 6) FROM lm WHERE $dk AND rc IN ($selfs))
SELECT w.var AS var, w.vq AS vq, w.line AS line, f.path AS path,
       (SELECT GROUP_CONCAT(DISTINCT x) FROM dsn WHERE dsn.fid = w.fid AND dsn.line = w.line) AS ds,
       (SELECT MAX(lm.sid IS NOT NULL) FROM lm WHERE lm.fid = w.fid AND lm.line = w.line AND lm.kind = 'read' AND lm.sid IN ($ids)) AS bound,
       (SELECT COUNT(*) FROM lm WHERE lm.fid = w.fid AND lm.line = w.line AND lm.kind = 'member-access' AND lm.nm = 'FieldByName' AND (lm.rc IN ($names) OR lm.rc IN ($selfs))) AS fbn,
       (SELECT GROUP_CONCAT(DISTINCT lm.nm) FROM lm WHERE lm.fid = w.fid AND lm.line = w.line AND lm.kind = 'call') AS calls,
       (SELECT GROUP_CONCAT(sl.text, '|') FROM string_literals sl WHERE sl.file_id = w.fid AND sl.start_line = w.line AND sl.kind = 'literal') AS col
  FROM w JOIN files f ON f.id = w.fid
"@ 'w.line, w.rid'
}
# The (dataset field, column literal) pairs of a variable's write rows: a pair only where the line names
# exactly ONE dataset field and ONE literal. Ok: those rows; Pairs: the distinct 'DS|COL' strings. Pure.
function Get-FieldVarPairs($Rows) {
  $ok = @($Rows | Where-Object { $_.ds -and $_.col -and ([string]$_.ds) -notmatch ',' -and ([string]$_.col) -notmatch '\|' })
  [pscustomobject]@{ Ok = $ok; Pairs = @($ok | ForEach-Object { "$([string]$_.ds)|$([string]$_.col)" } | Sort-Object -Unique) }
}

# Get-FieldVarLineGrade over one write row of Get-FieldVarWriteRows.
function Get-FieldVarSiteGrade($Site, [string] $DsName) {
  Get-FieldVarLineGrade ([int]$(if ($Site.fbn) { $Site.fbn } else { 0 }) -gt 0) ([int]$(if ($Site.bound) { $Site.bound } else { 0 }) -gt 0) `
                        @(([string]$Site.calls) -split ',' | Where-Object { $_ -and $_ -ne 'FieldByName' }) $DsName
}

# TABLE.COLUMN: the dataset fields whose unit names the table beside them. Exactly
# one proceeds; several is a named stop (Review Focus 2), never a guess.
function Resolve-AnchorFromColumn([string] $Table, [string] $Col, $R, $SqlSet, [hashtable] $SourceOverride) {
  $cands = Get-TableDataSetRows $Table
  if ($cands.Count -ne 1) {
    $R.Stop = "$Table.$Col`: $($cands.Count) datasets load $Table in this index ($((@($cands | ForEach-Object { [string]$_.q })) -join ', ')) -- pass the control or the dataset field"
    $R.StopAnchor = $(if ($cands.Count) { Get-TraceAnchorText ([string]$cands[0].path) ([int]$cands[0].line) } else { Get-TraceAnchorText ([string]$SqlSet.Tables[$Table].File) ([int]$SqlSet.Tables[$Table].Line) })
    $R.TableColumn = "$Table.$Col"
    return $R
  }
  $d = $cands[0]
  Complete-AnchorFromDataSet $R ([pscustomobject]@{ Name = [string]$d.name; Id = [int]$d.id; ClassId = [int]$d.pid; File = [string]$d.path; Fid = [int]$d.fid; Line = [int]$d.line; Type = ([string]$d.sig).Trim() }) $Col $SqlSet $SourceOverride
}

# The dataset fields whose unit names $Table beside them -- the TABLE.COLUMN anchor's candidates, and (calc-field
# fix round 1, I2) whether a TABLE.COLUMN target resolves to one dataset. Assign directly (Invoke-IndexQuery contract).
function Get-TableDataSetRows([string] $Table) {
  Invoke-IndexQuery @"
SELECT DISTINCT s.id AS id, s.name AS name, s.qualified_name AS q, s.signature AS sig, s.start_line AS line, f.path AS path, s.file_id AS fid, s.parent_id AS pid
  FROM string_literals sl JOIN refs r ON r.file_id = sl.file_id AND r.start_line = sl.start_line AND r.kind = 'read'
  JOIN symbols s ON s.name = r.name_text AND s.file_id = sl.file_id AND s.kind = 'field'
  JOIN files f ON f.id = s.file_id
 WHERE sl.kind = 'literal' AND sl.text = '$(ConvertTo-SqlText $Table)' AND $(Get-DataSetTypeSql 's')
 ORDER BY s.qualified_name
"@ 'round-trip (datasets of a table)'
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
#   case    `case X of .. else .. Exit`            -> UNLESS "case X of", the note `else arm at :<line>` (T4-C3:
#                                                     the source line verbatim, the arm said in generated text)
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

# StmtLine / StmtCol: where the statement that owns the branch starts (its if / try / case token) --
# the point Get-EnclosingChainFromLines asks next, to walk outwards (fix round 1).
# How many lines of the span ($L1,$C1)..($L2,$C2) carry code (the stripped copy is non-blank there).
function Get-ShimCodeLineCount([string[]] $Stripped, [int] $L1, [int] $C1, [int] $L2, [int] $C2) {
  $n = 0
  for ($l = $L1; $l -le $L2; $l++) {
    $s = $Stripped[$l - 1]
    $a = $(if ($l -eq $L1) { [Math]::Min($C1, $s.Length) } else { 0 }); $b = $(if ($l -eq $L2) { [Math]::Min($C2, $s.Length) } else { $s.Length })
    if ($b -gt $a -and $s.Substring($a, $b - $a).Trim()) { $n++ }
  }
  $n
}

function New-ShimResult($X, [string] $Form, [string] $Keyword, [string] $Condition, [int] $IfLine, [int] $BlockStart, [int] $BlockEnd, [string] $Reason = '', [int] $StmtLine = 0, [int] $StmtCol = 0) {
  if ($Form -ne 'unknown' -and $Condition.Contains('"')) {
    return (New-ShimResult $X 'unknown' '' '' 0 0 0 "the condition over the $($X.What) at :$($X.ExitLine) holds a double-quote, which a Form A condition cannot carry verbatim")
  }
  [pscustomobject]@{ Form = $Form; Keyword = $Keyword; Condition = $Condition; IfLine = $IfLine; BlockStart = $BlockStart; BlockEnd = $BlockEnd; ExitArg = $X.ExitArg; Reason = $Reason
                     StmtLine = $StmtLine; StmtCol = $StmtCol }
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
  $r = New-ShimResult $X $(if ($it.L -eq $X.ExitLine) { 'inline' } else { 'block' }) $Keyword $cond $it.L $Blk[0] $Blk[1] '' $it.L $it.C
  # Task 6 fix round 1: where the condition's text lies -- after the `if` token, before the `then` (0-based
  # columns, the tokens' own), so a caller can tell a ref IN the condition from one in the branch
  if ($r.Form -ne 'unknown') { $r | Add-Member -NotePropertyMembers @{ CondL1 = $it.L; CondC1 = $it.E; CondL2 = $th.L; CondC2 = $th.C } }
  $r
}

# Is the ref at ($Line, 1-based $Col) inside the CONDITION of shim result $G (between its `if` and `then`)?
# Only an if-form result carries the span; any other form answers $false. Pure.
function Test-InShimCondition($G, [int] $Line, [int] $Col) {
  if (-not $G.PSObject.Properties['CondL1']) { return $false }
  $c = $Col - 1
  $after = ($Line -gt $G.CondL1) -or ($Line -eq $G.CondL1 -and $c -ge $G.CondC1)
  $before = ($Line -lt $G.CondL2) -or ($Line -eq $G.CondL2 -and $c -lt $G.CondC2)
  $after -and $before
}

# final-review I1: the FAILURE branch of an if-form Exit guard on its `then` line, as 0-based columns
# [From, To) of that line (CondL2): for UNLESS (the Exit in the then branch) from the `then` to the
# if statement's own `else` or `;` on that line, else to the line end; for WHEN (the Exit in the else
# branch) from that `else` to the `;` that ends it, else to the line end -- $null when the else is not
# on the line (its lines are the guard's block). Tokens are read from the stripped line: a begin / try /
# case .. end nests, and an `if` nested in the branch takes the next `else` for itself. Pure.
function Get-GuardFailSpan($G, [string] $Stripped) {
  if (-not $G.PSObject.Properties['CondL2']) { return $null }
  $c0 = [int]$G.CondC2
  if ($c0 -ge $Stripped.Length) { return $null }
  $d = 0; $pend = 0; $els = -1; $end = $Stripped.Length
  foreach ($m in $script:ShimTokenRx.Matches($Stripped.Substring($c0 + 4))) {
    $k = $m.Value.ToLowerInvariant(); $at = $c0 + 4 + $m.Index
    if ($k -in $script:ShimOpeners) { $d++; continue }
    if ($k -in $script:ShimClosers) { $d--; continue }
    if ($d -ne 0) { continue }
    if ($k -eq 'if') { $pend++; continue }
    if ($k -eq 'else') { if ($pend -gt 0) { $pend--; continue }; if ($els -lt 0) { $els = $at; continue } }
    if ($k -eq ';') { $end = $at + 1; break }
  }
  if ($G.Keyword -ceq 'UNLESS') { return [pscustomobject]@{ Line = [int]$G.CondL2; From = $c0; To = $(if ($els -ge 0) { $els } else { $end }) } }
  if ($els -lt 0) { return $null }
  [pscustomobject]@{ Line = [int]$G.CondL2; From = $els; To = $end }
}

function New-ShimCaseResult($X, [int] $CaseIdx, [int] $ElseIdx) {
  $ca = $X.Tok[$CaseIdx]
  $of = @(for ($q = $CaseIdx + 1; $q -lt $X.Tok.Count; $q++) { if ($X.Tok[$q].T -eq 'of') { $X.Tok[$q]; break } })
  if (-not $of.Count) { return (New-ShimUnknown $X 'sits in a case with no of') }
  if (Test-ShimDirective $X $ca) { return (New-ShimUnknown $X 'sits under a conditional-compilation directive') }
  $sel = Get-ShimSpanText $X.Raw $X.Stripped $ca.L $ca.C $of[0].L $of[0].E
  if ($null -eq $sel) { return (New-ShimUnknown $X 'has a condition that wraps a comment across lines') }
  # T4-C3: VERBATIM through `of`; that the Exit is in the else arm is the condition's generated note (Get-ElseNote)
  New-ShimResult $X 'case' 'UNLESS' $sel $ca.L $X.Tok[$ElseIdx].L (Find-BlockEnd $X.Stripped $ca.L $ca.C) '' $ca.L $ca.C
}

# The Exit sits in the handler of the try at token $TryIdx (its `except` at $ExIdx):
# the protected statements are the depth-0 `;`-separated spans of the try body.
function New-ShimExceptResult($X, [int] $TryIdx, [int] $ExIdx) {
  $tr = $X.Tok[$TryIdx]; $ex = $X.Tok[$ExIdx]
  if (Test-ShimDirective $X $tr) { return (New-ShimUnknown $X 'sits under a conditional-compilation directive') }
  $stm = @(); $lines = @(); $sl = $tr.L; $sc = $tr.E
  $semis = Get-ShimLevelTokens $X $TryIdx $ExIdx @(';')
  foreach ($q in (@($semis) + $ExIdx)) {
    $e = $X.Tok[$q]
    $txt = Get-ShimSpanText $X.Raw $X.Stripped $sl $sc $e.L $e.C
    if ($null -eq $txt) { return (New-ShimUnknown $X 'has a try body that wraps a comment across lines') }
    if ($txt) { $stm += $txt; $lines += (Get-ShimCodeLineCount $X.Stripped $sl $sc $e.L $e.C) }
    $sl = $e.L; $sc = $e.E
  }
  if (-not $stm.Count) { return (New-ShimUnknown $X 'sits in the handler of an empty try') }
  # ruling T4-R3: ' ... ', not ' .. ' (Pascal's range operator). Fix round 1 (Task 5): a statement of more
  # than three code lines is a compound block (an if / begin .. end), not a quotable statement: a LAST one is
  # left out -- `S1 ... raises`, the connector standing for the statements after S1 -- and a FIRST (or only)
  # one makes the form a named unknown; quoting it whole wrote a 75-line condition (HandleDelta :493-569)
  if ($lines[0] -gt 3) { return (New-ShimUnknown $X 'sits in the handler of a try whose body opens with a compound statement') }
  $s = $(if ($stm.Count -eq 1) { $stm[0] } elseif ($lines[-1] -gt 3) { "$($stm[0]) ..." } else { "$($stm[0]) ... $($stm[-1])" })
  New-ShimResult $X 'except' 'UNLESS' "$s raises" $ex.L $ex.L (Find-BlockEnd $X.Stripped $tr.L $tr.C) '' $tr.L $tr.C
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
# The keyword tokens of lines $From..$To, once per routine (fix round 1: every step line of a routine
# asks for its enclosing chain, and re-tokenizing the body per ask was quadratic).
function Get-ShimTokens([string[]] $Stripped, [int] $From, [int] $To) {
  $tok = New-Object System.Collections.ArrayList
  for ($l = [Math]::Max($From, 1); $l -le [Math]::Min($To, $Stripped.Count); $l++) {
    foreach ($m in $script:ShimTokenRx.Matches($Stripped[$l - 1])) { [void]$tok.Add([pscustomobject]@{ L = $l; C = $m.Index; E = $m.Index + $m.Length; T = $m.Value.ToLowerInvariant() }) }
  }
  , $tok
}

function Get-EnclosingConditionFromLines([string[]] $Raw, [string[]] $Stripped, [int] $Line, [int] $Col, [int] $RoutineStart, $AllTok = $null) {
  $X = [pscustomobject]@{ Raw = $Raw; Stripped = $Stripped; ExitLine = $Line; ExitCol = 0; ExitArg = ''; Tok = $null; What = 'statement' }
  if ($Line -lt 1 -or $Line -gt $Stripped.Count) { return (New-ShimUnknown $X 'is outside the file') }
  $X.ExitCol = [Math]::Min([Math]::Max($Col, 0), $Stripped[$Line - 1].Length)
  if ($null -eq $AllTok) { $AllTok = Get-ShimTokens $Stripped $RoutineStart $Line }
  # the tokens that END before ($Line, $ExitCol): a binary search over the (line, end) order
  $lo = 0; $hi = $AllTok.Count
  while ($lo -lt $hi) {
    $mid = [int][Math]::Floor(($lo + $hi) / 2); $m = $AllTok[$mid]
    if ($m.L -lt $Line -or ($m.L -eq $Line -and $m.E -le $X.ExitCol)) { $lo = $mid + 1 } else { $hi = $mid }
  }
  $tok = $(if ($lo -gt 0) { $AllTok.GetRange(0, $lo) } else { New-Object System.Collections.ArrayList })
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

# The CHAIN of enclosing conditions of the statement at ($Line, $Col), innermost first: each branch's
# owning statement (its if / try / case token) is asked in turn, until one sits in no branch. Pure.
function Get-EnclosingChainFromLines([string[]] $Raw, [string[]] $Stripped, [int] $Line, [int] $Col, [int] $RoutineStart, $AllTok = $null) {
  if ($null -eq $AllTok) { $AllTok = Get-ShimTokens $Stripped $RoutineStart $Line }
  $out = @(); $l = $Line; $c = $Col
  for ($i = 0; $i -lt 12; $i++) {
    $e = Get-EnclosingConditionFromLines $Raw $Stripped $l $c $RoutineStart $AllTok
    if ($e.Form -eq 'unknown') { break }
    $out += $e
    if (-not $e.StmtLine -or ($e.StmtLine -eq $l -and $e.StmtCol -ge $c)) { break }
    $l = $e.StmtLine; $c = $e.StmtCol
  }
  , $out
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
                   ApplyUpdates = 'APPLIES'; EmptyDataSet = 'EMPTIES'; StartTransaction = 'OPENS'; Commit = 'RUNS'; Rollback = 'RUNS'
                   Execute = 'RUNS'; ExecSQL = 'RUNS'; Open = 'RUNS' }
$script:RtEvents = @('AfterPost', 'AfterDelete', 'BeforePost', 'AfterInsert', 'OnUpdateRecord', 'OnUpdateError', 'OnReconcileError')
# RC-R6 (2026-09-28): the Windows I/O primitives that make a TRANSPORT-CONVENTION callee a step of the path.
# The convention keeps transport bodies out of the walk, so a BOUND call into a transport unit is skipped --
# right for a logger or a payload parser there (uPipeSessionBuilder.Log, ExtractKeyValue), wrong for a helper
# whose own act is OUTWARD: TBroadcastServer.PushTableChanged writes the change notice to every subscriber's
# pipe (WriteFile, uBroadcastServer.pas:434/:435). While that call was unbound (before resolver 1.11 RB-1) it
# was a [by name] step; bound, it fell to the skip. The index's effect facts cannot tell the two apart (both
# effect_summary '?'; `touches` has no pipe / IPC class), so the outward act is read from the callee's own
# body: an UNBOUND call to one of these names, receiver-less or on Winapi.Windows (Test-OutwardIoCallee).
$script:RtOutwardIoCalls = @('WriteFile', 'WriteFileEx', 'TransactNamedPipe', 'CallNamedPipe')
# final-review I4: which wiring the WRITE direction starts from -- the event that sends an EDITED row
# first, a delete last; a generic, stated order, then the line (Sort-RtWiring). Every $RtEvents name is in it.
$script:RtWritePreference = @('AfterPost', 'BeforePost', 'AfterInsert', 'OnUpdateRecord', 'OnUpdateError', 'OnReconcileError', 'AfterDelete')

# Wirings in write preference order ($RtWritePreference), each event's by line. An event outside the list sorts last. Pure.
function Sort-RtWiring($Wirings) {
  , @($Wirings | Sort-Object @{ E = { $i = [array]::IndexOf($script:RtWritePreference, [string]$_.Event); $(if ($i -lt 0) { 99 } else { $i }) } }, @{ E = { [int]$_.Line } })
}

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

# RC-R6: does routine $Id's own body make an outward Windows I/O call ($RtOutwardIoCalls, unbound,
# receiver-less or on Winapi.Windows)? Reads the callee's cached body facts; never walks it.
function Test-OutwardIoCallee([int] $Id, $Ctx) {
  $F = Get-RoutineFacts $Id $Ctx.Likes
  [bool]@($F.Refs | Where-Object { $_.kind -eq 'call' -and -not $_.tid -and [string]$_.nm -in $script:RtOutwardIoCalls -and
                                   ([string]::IsNullOrEmpty([string]$_.recv) -or [string]$_.recv -eq 'Winapi.Windows') }).Count
}

function Add-RtItem($List, $Item, [int] $Line, [int] $Owner) {
  $Item | Add-Member -NotePropertyName Line -NotePropertyValue $Line -Force
  $Item | Add-Member -NotePropertyName Owner -NotePropertyValue $Owner -Force
  [void]$List.Add($Item)
}

# A SOURCE literal for a step or facet TEXT (ruling T5-R5): the token as written (quotes, doubled '',
# full length), or -- when the text cannot carry it (a double quote the checker would pair, ' @' / ' ['
# / ' -- ', a byte outside ASCII) -- `(a literal at :N)`. Never shortened or rewritten.
function Format-TraceLiteral($Lit, $F, $Ctx) {
  $raw = $(if ($F.PSObject.Properties['Fid'] -and $F.Fid) { (Get-TraceSource $F.Path $Ctx.SourceOverride).Raw } else { $null })
  $lt = Get-LiteralSourceText $Lit $raw
  $(if ($lt -match '"| @| \[| -- |--$|[^\x20-\x7E]') { "(a literal at :$([int]$Lit.line))" } else { $lt })
}

function Get-LineLits($Lits, $F, $Ctx) {
  $l = @($Lits | Where-Object { $_.kind -eq 'literal' } | ForEach-Object { Format-TraceLiteral $_ $F $Ctx })
  $(if ($l.Count) { ' ' + ($l -join ' ') } else { '' })
}

# The stream format a `SaveToStream(<stream>, <format>)` call names: its last argument when that is one
# plain identifier, as written; '' otherwise (the caller then says just "stream"). Pure, over one raw line.
function Get-StreamFormat([string] $RawLine) {
  $m = [regex]::Match($RawLine, '(?i)\bSaveToStream\s*\(([^()]*)\)')
  if (-not $m.Success) { return '' }
  $a = @($m.Groups[1].Value -split ',' | ForEach-Object { $_.Trim() })
  $(if ($a.Count -ge 2 -and $a[-1] -match '^[A-Za-z_]\w*$') { $a[-1] } else { '' })
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
# Resolver 1.11 (RB-1) binds those unit-var calls, so on the 1.20 / 1.11 clones the
# GDatasetsDef / GBroadcastServer sites no longer reach this by-name path; it stays for
# any receiver the index still leaves unbound.
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
  # final-review I1: on the guard's `then` line only the failure span counts (Get-GuardFailSpan) -- the
  # condition before it, and a then branch that is the path (a WHEN guard), are not the else
  $spL = $(if ($G.PSObject.Properties['SpanLine']) { [int]$G.SpanLine } else { 0 })
  $inBr = { param($o) [int]$o.line -ge $G.BlockStart -and [int]$o.line -le $G.BlockEnd -and ([int]$o.line -ne $spL -or (([int]$o.col - 1) -ge $G.SpanFrom -and ([int]$o.col - 1) -lt $G.SpanTo)) }
  $in = @($F.Refs | Where-Object { & $inBr $_ })
  foreach ($o in @($in | Where-Object { $_.kind -eq 'call' -and $script:RtOps.ContainsKey([string]$_.nm) })) {
    $parts += "$(if ($o.recv) { [string]$o.recv + '.' })$([string]$o.nm) @$(Get-TraceAnchorText $F.Path ([int]$o.line))"
  }
  # the protocol constants only (fix round 1: `mtError`, a logger's level, is not what the branch answers)
  $en = @($in | Where-Object { [string]$_.tkind -eq 'enum_value' -and ([string]$_.tname -like 'rsp*' -or [string]$_.tname -like 'cmd*') } | ForEach-Object { [string]$_.tname } | Sort-Object -Unique)
  if ($en.Count) { $parts += ($en -join '/') }
  # T5-R11: the literal that goes OUT with the branch -- on a line that writes the response (an rsp
  # write), writes one of the routine's parameters (the response payload leaves through an out / var
  # param), or raises. A line that only CALLS something (a logger) is never quoted; with no such line,
  # no literal.
  $outLn = @{}
  foreach ($r in $in) {
    if ($r.kind -eq 'write' -and [string]$r.tkind -eq 'param') { $outLn[[int]$r.line] = 1 }
    if ([string]$r.tkind -eq 'enum_value' -and [string]$r.tname -like 'rsp*' -and @($in | Where-Object { [int]$_.line -eq [int]$r.line -and $_.kind -eq 'write' }).Count) { $outLn[[int]$r.line] = 1 }
  }
  if ($F.PSObject.Properties['Fid'] -and $F.Fid) {
    $st = (Get-TraceSource $F.Path $Ctx.SourceOverride).Stripped
    for ($q = [int]$G.BlockStart; $q -le [int]$G.BlockEnd -and $q -le $st.Count; $q++) {
      $sl = $(if ($q -eq $spL) { $st[$q - 1].Substring([Math]::Min([int]$G.SpanFrom, $st[$q - 1].Length), [Math]::Max(0, [Math]::Min([int]$G.SpanTo, $st[$q - 1].Length) - [Math]::Min([int]$G.SpanFrom, $st[$q - 1].Length))) } else { $st[$q - 1] })
      if ($sl -match '(?i)\braise\b') { $outLn[$q] = 1 }
    }
  }
  $lits = @($F.Lits | Where-Object { (& $inBr $_) -and $outLn.ContainsKey([int]$_.line) -and $_.kind -in 'literal', 'format' -and ([string]$_.text).Trim().Length -gt 8 } | Select-Object -First 1)
  foreach ($l in $lits) {
    $raw = $(if ($F.PSObject.Properties['Fid'] -and $F.Fid) { (Get-TraceSource $F.Path $Ctx.SourceOverride).Raw } else { $null })
    $lt = Get-LiteralSourceText $l $raw
    $parts += $(if ($lt -match '"|; |[^\x20-\x7E]') { "a literal at :$([int]$l.line)" } else { $lt })
  }
  if ($G.ExitArg) { $parts += "Exit($($G.ExitArg))" }
  # T4-C3: a case condition quotes only `case X of`; the note says which arm the Exit sits in
  if ($G.PSObject.Properties['Form'] -and $G.Form -eq 'case') { return "else arm at :$($G.BlockStart)$(if ($parts.Count) { ': ' + ($parts -join ', ') })" }
  $(if ($parts.Count) { 'else ' + ($parts -join ', ') } else { '' })
}

# The right-hand side of a ONE-line assignment `X:= <expr>;` whose expression concatenates (a `+`
# outside any literal or comment), as the source writes it; '' for any other line. Pure: $Raw is the
# line as written, $Stripped the same line with literals and comments blanked column for column.
function Get-ConcatAssignExpr([string] $Raw, [string] $Stripped) {
  $m = [regex]::Match($Stripped, '^\s*[A-Za-z_][\w.]*\s*:=')
  $e = $Stripped.LastIndexOf(';')
  if (-not $m.Success -or $e -le $m.Length -or $Stripped.Substring($e + 1).Trim() -or $Raw.Length -lt $e) { return '' }
  if ($Stripped.Substring($m.Length, $e - $m.Length) -notmatch '\+') { return '' }
  $Raw.Substring($m.Length, $e - $m.Length).Trim()
}

# The RHS of the assignment whose target starts at the 1-based column $Col (`X:= <expr>;`, anywhere on the
# line -- `if W <> '' then SQL:= SQL + ...;` too), as the source writes it, up to the `;` that ends it on
# this line; '' when the line holds no `:=` there or the statement runs on. Pure, like Get-ConcatAssignExpr.
function Get-AssignExprAt([string] $Raw, [string] $Stripped, [int] $Col) {
  $c0 = $Col - 1
  if ($c0 -lt 0 -or $c0 -ge $Stripped.Length) { return '' }
  $m = [regex]::Match($Stripped.Substring($c0), '^[A-Za-z_][\w.]*\s*:=')
  if (-not $m.Success) { return '' }
  $b = $c0 + $m.Length
  $e = $Stripped.IndexOf(';', $b)
  if ($e -lt 0 -or $Raw.Length -lt $e) { return '' }
  $Raw.Substring($b, $e - $b).Trim()
}

# The literals a transport call's payload is inferred from (pure, over $F.Lits): the routine's literals
# before the send that name the anchor table, else its key=value literals.
function Get-PayloadLits($F, [int] $Line, [string] $Table) {
  $before = @($F.Lits | Where-Object { [int]$_.line -lt $Line -and $_.kind -eq 'literal' })
  $pl = @($before | Where-Object { $Table -and ([string]$_.text).ToUpperInvariant().Contains($Table.ToUpperInvariant()) })
  if (-not $pl.Count) { $pl = @($before | Where-Object { [string]$_.text -match '[=|]' }) }
  , $pl
}

# A sender serves ONLY the anchor's table when its PAYLOAD literals name that table as a word (fix round 1,
# M2: an error message naming the table, :3992, is not the payload). Pure.
function Test-TableSpecificSender($F, [int] $Line, [string] $Table) {
  $rx = "(?i)\b$([regex]::Escape($Table))\b"
  [bool]@(Get-PayloadLits $F $Line $Table | Where-Object { [string]$_.text -match $rx }).Count
}

# The payload a transport call carries (Get-PayloadLits), plus the stream when a SaveToStream precedes.
# Inferred from literals, never a fact. Returns Text and the facet's Note -- which says so when the text is
# an assignment quoted as written (fix round 1, M5) rather than the literals joined.
function Get-PayloadText($F, [int] $Line, $Ctx) {
  $pl = Get-PayloadLits $F $Line ([string]$Ctx.Table)
  $t = (@($pl | ForEach-Object { Format-TraceLiteral $_ $F $Ctx }) -join ' + ')
  $nt = 'payload inferred from the literals before the send'
  # Task 6: literals that one assignment CONCATENATES with values (`P:= 'TABLE=' + ATableName + ...;`)
  # are quoted as that expression, as written -- the literals alone, joined, would read as the payload
  $pls = @($pl | ForEach-Object { [int]$_.line } | Sort-Object -Unique)
  if ($pls.Count -eq 1) {
    $src = Get-TraceSource $F.Path $Ctx.SourceOverride
    $ex = Get-ConcatAssignExpr $src.Raw[$pls[0] - 1] $src.Stripped[$pls[0] - 1]
    if ($ex -and $ex -notmatch '"| @| \[| -- |--$|[^\x20-\x7E]') { $t = $ex; $nt = "payload quoted from the assignment at :$($pls[0])" }
  }
  $sv = @($F.Refs | Where-Object { [int]$_.line -lt $Line -and [string]$_.nm -eq 'SaveToStream' -and $_.kind -eq 'call' } | Select-Object -Last 1)
  if ($sv.Count) {
    $fmt = Get-StreamFormat ((Get-TraceSource $F.Path $Ctx.SourceOverride).Raw[[int]$sv[0].line - 1])
    $t += $(if ($t) { ' + ' } else { '' }) + $(if ($fmt) { "$fmt stream" } else { 'stream' })
  }
  [pscustomobject]@{ Text = $(if ($t) { $t } else { 'payload built before the send (no literal found)' }); Note = $nt }
}

function Add-CallsStep($List, $Tgt, $Sub, $Caller, [int] $SiteLine, [string] $Lits = '', [switch] $Always, [string] $Note = '') {
  if (-not $Always -and -not $Sub.Items.Count -and -not $Sub.Conds.Count) { return }
  $s = New-TraceStep 'step' "CALLS $($Tgt.Short)$Lits" (Get-TraceAnchorText $Tgt.Path $Tgt.Line) $Tgt.Grade $Caller.Short $(if ($Note) { $Note } else { "from :$SiteLine" }) $Tgt.Ask
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

# A line that answers the path with SUCCESS: a success response written, or a commit (fix round 1).
# Success is a POSITIVE list (ruling T5-R13): the protocol's rspOK (a write acknowledged) and rspData
# (rows returned). Every other rsp* -- rspError, rspNotFound, rspDenied (Pipes.Protocol.pas:212-213) --
# is a failure answer, so in `if Failed then begin ..rspError.. end else begin ..rspOK.. end` the ELSE
# is the path (T5-R10), and an if answering rspOK / rspNotFound has one path side, not both.
$script:RtSuccessRsp = @('rspOK', 'rspData')
function Test-SuccessLine($Rs) {
  (@($Rs | Where-Object { [string]$_.tkind -eq 'enum_value' -and [string]$_.tname -in $script:RtSuccessRsp }).Count -and @($Rs | Where-Object { $_.kind -eq 'write' }).Count) -or
  [bool]@($Rs | Where-Object { $_.kind -eq 'call' -and [string]$_.nm -in 'CommitUpdates', 'Commit' }).Count
}

# Which side of an if the path follows: the ONE side holding a success line ('then' / 'else'), or
# 'both' / 'none' -- then neither side is the other's else note. $Then / $Else: the lines' facts (.Rs).
function Get-BranchPathSide($Then, $Else) {
  $t = [bool]@($Then | Where-Object { Test-SuccessLine $_.Rs }).Count
  $e = [bool]@($Else | Where-Object { Test-SuccessLine $_.Rs }).Count
  $(if ($t -and $e) { 'both' } elseif ($t) { 'then' } elseif ($e) { 'else' } else { 'none' })
}

# How many STEPS one line would have yielded, with the classifier's own precedence (T5-R6; fix round 2:
# a call counts its CALLS step AND every step of its subtree -- the number an OMITS states is steps):
# a crossing or a response is one, else its dataset ops, else its FIB$ SQL, an event wiring with its
# handler's subtree, else bound calls whose subtree holds a step and calls resolvable by name, each
# with its subtree, and a transport callee that makes an outward I/O call (RC-R6) as one step. Subtrees come from a DRY walk over copies of Visited and Seen, so the omission
# changes nothing the real walk sees.
function Get-LineYield($I, $F, [int] $Depth, [hashtable] $Visited, $Ctx) {
  $rs = @($I.Rs)
  $en = @($rs | Where-Object { [string]$_.tkind -eq 'enum_value' })
  if (@($en | Where-Object { [string]$_.tname -like 'cmd*' }).Count -and @($rs | Where-Object { $_.kind -eq 'call' -and $_.tpipe -and [int]$_.tpipe -eq 1 }).Count) { return 1 }
  if (@($en | Where-Object { [string]$_.tname -like 'rsp*' }).Count) { return 1 }
  $ops = @($rs | Where-Object { $_.kind -eq 'call' -and $script:RtOps.ContainsKey([string]$_.nm) })
  if ($ops.Count) { return $ops.Count }
  $n = @($I.Lits | Where-Object { [string]$_.text -match $script:RtFibSqlRx }).Count
  $dry = @{}; foreach ($k in $Ctx.Keys) { $dry[$k] = $Ctx[$k] }; $dry['Seen'] = $Ctx.Seen.Clone()
  $ev = @($rs | Where-Object { $_.kind -eq 'member-access' -and [string]$_.nm -in $script:RtEvents })
  if ($ev.Count) {
    $h = @($rs | Where-Object { $_.kind -in 'read', 'member-access', 'call' -and [string]$_.nm -ne [string]$ev[0].nm -and [string]$_.nm -ne [string]$ev[0].recv } | Select-Object -Last 1)
    $hs = $(if ($h.Count) { Resolve-HandlerByName $h[0] $F } else { $null })
    if ($hs) {
      $sub = Walk-Routine $hs.Id ($Depth - 1) ($Visited.Clone()) $dry
      return ($n + 1 + $(if ($sub.Items.Count -or $sub.Conds.Count) { 1 + $sub.Items.Count } else { 0 }))
    }
  }
  foreach ($c in @($rs | Where-Object { $_.kind -eq 'call' -and $_.tid -and [int]$_.tistart -gt 0 -and -not ($_.tpipe -and [int]$_.tpipe -eq 1) -and [string]$_.tkind -ne 'constructor' })) {
    $sub = Walk-Routine ([int]$c.tid) ($Depth - 1) ($Visited.Clone()) $dry
    if ($sub.Items.Count -or $sub.Conds.Count) { $n += 1 + $sub.Items.Count }
  }
  # RC-R6: a transport callee that makes an outward I/O call is one step (kept, not descended)
  foreach ($c in @($rs | Where-Object { $_.kind -eq 'call' -and $_.tid -and [int]$_.tistart -gt 0 -and $_.tpipe -and [int]$_.tpipe -eq 1 -and [string]$_.tkind -ne 'constructor' })) {
    if (Test-OutwardIoCallee ([int]$c.tid) $Ctx) { $n += 1 }
  }
  foreach ($c in @($rs | Where-Object { $_.kind -eq 'call' -and -not $_.tid -and $_.recv })) {
    $impl = Resolve-ImplByName ([string]$c.recv) ([string]$c.nm) $F
    if ($impl.Count -ne 1) { continue }
    $sub = Walk-Routine ([int]$impl[0].id) ($Depth - 1) ($Visited.Clone()) $dry
    $n += 1 + $sub.Items.Count + @(Get-FibLiterals ([int]$impl[0].fid) | Where-Object { -not $dry.Seen.ContainsKey("$([string]$impl[0].path)|$([int]$_.line)") }).Count
  }
  $n
}

# The OMITS disclosure (T5-R1): how many STEPS the omitted lines would have yielded (T5-R6) and the
# verbatim branch conditions that left them out (generated connectors, E1). $Recs: Count, Keyword,
# Condition, Anchor, Routine. A condition the note cannot carry ('; ') is named by its anchor only.
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
  $s = New-TraceStep 'step' "OMITS $n step(s) in branches for other tables, every enclosing if read up to a loop or case arm" $Recs[0].Anchor '' $(if ($rn.Count -eq 1) { $rn[0] } else { '' }) ('not walked, the branch conditions: ' + ($cs -join ' / ')) 'E1'
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
# Fix round 1: every step line's enclosing CHAIN is read; the else branch of an if whose
# then branch answers (a response or a commit) and an except handler are that
# condition's else note, not path steps; a response overwritten later on the path is a
# default; an attached On* handler runs at its receiver's ApplyUpdates, not at the attach.
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
  $src = Get-TraceSource $F.Path $Ctx.SourceOverride
  foreach ($xl in @($F.Refs | Where-Object { $_.kind -eq 'call' -and [string]$_.nm -eq 'Exit' } | ForEach-Object { [int]$_.line } | Sort-Object -Unique)) {
    $g = Get-GuardCondition $F.Path $xl $F.ImplStart $Ctx.SourceOverride
    if ($g.Form -eq 'unknown') {
      Add-RtItem $items (New-TraceStep 'stops' (ConvertTo-TraceStopText $g.Reason) (Get-TraceAnchorText $F.Path $xl) '' $F.Short 'no condition is quoted for this Exit' 'E1') $xl $Id
      continue
    }
    for ($q = $g.BlockStart; $q -le $g.BlockEnd; $q++) { if ($q -ne $g.IfLine) { $skip[$q] = 1 } }
    # final-review I1: the IfLine is kept for its CONDITION only. On the `then` line, the refs and literals of
    # the failure branch (`if X then begin FMT.CancelUpdates; Exit; end;`) are not path steps -- they are
    # the else note, and only that span of the line is (Get-ElseNote reads SpanLine / SpanFrom / SpanTo)
    $sp = $(if ($g.PSObject.Properties['CondL2']) { Get-GuardFailSpan $g $src.Stripped[[int]$g.CondL2 - 1] } else { $null })
    if ($sp) {
      $g | Add-Member -NotePropertyMembers @{ SpanLine = $sp.Line; SpanFrom = $sp.From; SpanTo = $sp.To }
      $inSp = { param($o) $c = [int]$o.col - 1; $c -ge $sp.From -and $c -lt $sp.To }
      if ($refsAt.ContainsKey($sp.Line)) { $refsAt[$sp.Line] = [Collections.ArrayList]@($refsAt[$sp.Line] | Where-Object { -not (& $inSp $_) }) }
      if ($litsAt.ContainsKey($sp.Line)) { $litsAt[$sp.Line] = [Collections.ArrayList]@($litsAt[$sp.Line] | Where-Object { -not (& $inSp $_) }) }
    }
    $ck = "$($g.IfLine)|$($g.Keyword)|$($g.Condition)"
    if ($condSeen.ContainsKey($ck)) { continue }
    $condSeen[$ck] = 1
    # VERBATIM (P16 / T4-C1): the shim's text as it stands -- New-TraceCond refuses what it cannot carry
    $co = [pscustomobject]@{ IfLine = $g.IfLine; Guard = $true; G = $g; Item = (New-TraceCond $g.Keyword $g.Condition (Get-TraceAnchorText $F.Path $g.IfLine) (Get-ElseNote $F $g $Ctx) 'E1') }
    # Task 6: `<try body> raises` is the condition of the WHOLE try body, so it hangs on the body's first
    # path step, as an except handler's condition does below -- not on the step nearest the `except`
    # (HandleTableLoad :605 had landed on the Commit, the body's last statement)
    if ($g.Form -eq 'except' -and $g.StmtLine) { $co | Add-Member HostFrom ([int]$g.StmtLine); $co | Add-Member HostTo ([int]$g.IfLine) }
    $conds += $co
  }
  # Task 6: a bound call IN THE CONDITION of an Exit guard -- between its `if` and `then` (fix round 1,
  # Important 1: not merely on its line, where a one-line guard also holds failure-branch code) -- is a
  # step even when its subtree holds none: the path turns on its answer (HandleTableLoad :549 `if not
  # TryBuildSafeWhere(..) then .. Exit`); without it the guard hung on the step before it
  $guardGs = @($conds | ForEach-Object { $_.G })

  # ---- the branch structure of the body's step lines (T5-R1; fix round 1, Important 1) -------------
  # Every line that could make a step gets the CHAIN of its enclosing conditions, read once over the
  # routine's tokens from fresh source (E1: the index holds no branches).
  $allTok = Get-ShimTokens $src.Stripped $F.ImplStart $F.ImplEnd
  $allLines = @(@($refsAt.Keys) + @($litsAt.Keys) | Sort-Object -Unique)
  $info = @{}
  foreach ($ln in $allLines) {
    if ($skip.ContainsKey($ln)) { continue }
    $rs = @(if ($refsAt.ContainsKey($ln)) { $refsAt[$ln] }); $lits = @(if ($litsAt.ContainsKey($ln)) { $litsAt[$ln] })
    $cand = Get-LineCandidates $rs $lits $F
    $evr = @($rs | Where-Object { $_.kind -eq 'member-access' -and [string]$_.nm -in $script:RtEvents })
    if (-not $cand.Count -and -not $evr.Count) { continue }
    $col = [int](@(@($cand) + @($evr)) | Measure-Object -Property col -Minimum).Minimum
    $info[$ln] = [pscustomobject]@{ Rs = $rs; Lits = $lits; Chain = (Get-EnclosingChainFromLines $src.Raw $src.Stripped $ln $col $F.ImplStart $allTok) }
  }
  $infoLines = @($info.Keys | Sort-Object)

  # T5-R1: a line inside a branch for another table is not walked. Final-review I5: EVERY if of its
  # enclosing chain is tested, innermost first, and the first that is such a branch is the one named (it was
  # the innermost if only, so a line one if deeper stayed on the path); a try / except inside that branch
  # (HandleDelta :516-531) is inside it too. The chain is read outwards until a loop or a case arm, which the
  # reader does not place (Get-EnclosingChainFromLines). Only what would have yielded a step is counted
  # (T5-R6: a logger call yields none)
  $others = @(@($Ctx.SqlSet.Names) | Where-Object { $Ctx.Table -and ([string]$_).ToUpperInvariant() -ne ([string]$Ctx.Table).ToUpperInvariant() } | ForEach-Object { ([string]$_).ToUpperInvariant() })
  $branchy = [bool](@($F.Lits | Where-Object { $_.kind -eq 'literal' -and $others -contains ([string]$_.text).ToUpperInvariant() }).Count)
  $omitLines = @{}; $omitRecs = New-Object System.Collections.ArrayList; $omitFirst = 0
  if ($branchy) {
    foreach ($ln in $infoLines) {
      $e0 = @($info[$ln].Chain | Where-Object { $_.Form -in 'inline', 'block' -and (Test-OtherTableBranch $_.Keyword $_.Condition $Ctx.Table $Ctx.SqlSet.Names) } | Select-Object -First 1)
      if (-not $e0.Count) { continue }
      $omitLines[$ln] = 1
      $y = Get-LineYield $info[$ln] $F $Depth $Visited $Ctx
      if ($y -gt 0) {
        [void]$omitRecs.Add([pscustomobject]@{ Count = $y; Keyword = $e0[0].Keyword; Condition = $e0[0].Condition; Anchor = (Get-TraceAnchorText $F.Path $e0[0].IfLine); Routine = $F.Short })
        if (-not $omitFirst) { $omitFirst = $ln }
      }
    }
  }

  # Important 1 / T5-R10 / T5-R12: every if around a path step is written ONCE, verbatim, on the first
  # path step of its branch -- WHEN in the then branch, UNLESS in the else. When exactly ONE side answers
  # (a success response or a commit, Get-BranchPathSide), the OTHER side is that condition's `-- else`
  # note, not steps; when both or neither answer, both sides stay steps, each with its condition. A
  # line in an except handler is the note of UNLESS "<try body> raises". Innermost first. An if an Exit
  # guard already quotes is not written twice.
  $br = @{}
  foreach ($ln in $infoLines) {
    if ($omitLines.ContainsKey($ln)) { continue }
    foreach ($e in $info[$ln].Chain) {
      if ($e.Form -notin 'inline', 'block') { continue }
      $k = "$($e.StmtLine):$($e.StmtCol)"
      if (-not $br.ContainsKey($k)) { $br[$k] = [pscustomobject]@{ E = $e; Then = (New-Object System.Collections.ArrayList); Else = (New-Object System.Collections.ArrayList); Removed = (New-Object System.Collections.ArrayList); Side = '' } }
      if ($e.Keyword -ceq 'WHEN') { [void]$br[$k].Then.Add($ln) } else { [void]$br[$k].Else.Add($ln) }
    }
  }
  foreach ($k in $br.Keys) { $br[$k].Side = Get-BranchPathSide @($br[$k].Then | ForEach-Object { $info[$_] }) @($br[$k].Else | ForEach-Object { $info[$_] }) }
  $xb = @{}
  foreach ($ln in $infoLines) {
    if ($omitLines.ContainsKey($ln)) { continue }
    foreach ($e in $info[$ln].Chain) {
      $k = "$($e.StmtLine):$($e.StmtCol)"
      if ($e.Form -eq 'except') {
        if (-not $xb.ContainsKey($k)) { $xb[$k] = [pscustomobject]@{ E = $e; Removed = (New-Object System.Collections.ArrayList) } }
        [void]$xb[$k].Removed.Add($ln); $skip[$ln] = 1; break
      }
      if ($e.Form -notin 'inline', 'block' -or -not $br.ContainsKey($k)) { continue }
      $side = $(if ($e.Keyword -ceq 'WHEN') { 'then' } else { 'else' })
      if ($br[$k].Side -in 'then', 'else' -and $br[$k].Side -ne $side) { [void]$br[$k].Removed.Add($ln); $skip[$ln] = 1; break }
    }
  }
  $guardIfs = @{}; foreach ($gc in @($conds | Where-Object { $_.PSObject.Properties['Guard'] })) { $guardIfs["$($gc.IfLine)|$($gc.Item.Condition)"] = 1 }
  foreach ($k in @($br.Keys | Sort-Object { $br[$_].E.IfLine })) {
    $b = $br[$k]
    if ($guardIfs.ContainsKey("$($b.E.IfLine)|$($b.E.Condition)")) { continue }
    foreach ($side in 'then', 'else') {
      if ($b.Side -in 'then', 'else' -and $b.Side -ne $side) { continue }
      $onPath = @($(if ($side -eq 'then') { $b.Then } else { $b.Else }) | Where-Object { -not $skip.ContainsKey($_) })
      if (-not $onPath.Count) { continue }
      $nt = $(if ($b.Side -eq $side -and $b.Removed.Count) { Get-ElseNote $F ([pscustomobject]@{ BlockStart = ($b.Removed | Measure-Object -Minimum).Minimum; BlockEnd = ($b.Removed | Measure-Object -Maximum).Maximum; ExitArg = '' }) $Ctx } else { '' })
      $conds += [pscustomobject]@{ IfLine = $b.E.IfLine; HostLines = $onPath; Strict = $true
                                   Item = (New-TraceCond $(if ($side -eq 'then') { 'WHEN' } else { 'UNLESS' }) $b.E.Condition (Get-TraceAnchorText $F.Path $b.E.IfLine) $nt 'E1') }
    }
  }
  foreach ($k in @($xb.Keys | Sort-Object { $xb[$_].E.IfLine })) {
    $b = $xb[$k]
    # a handler that does nothing the walk would show (a logger line) has no else to name
    if (-not (@($b.Removed | ForEach-Object { Get-LineYield $info[$_] $F $Depth $Visited $Ctx }) | Measure-Object -Sum).Sum) { continue }
    $nt = Get-ElseNote $F ([pscustomobject]@{ BlockStart = ($b.Removed | Measure-Object -Minimum).Minimum; BlockEnd = ($b.Removed | Measure-Object -Maximum).Maximum; ExitArg = '' }) $Ctx
    $conds += [pscustomobject]@{ IfLine = $b.E.IfLine; HostFrom = $b.E.StmtLine; HostTo = $b.E.IfLine; Item = (New-TraceCond 'UNLESS' $b.E.Condition (Get-TraceAnchorText $F.Path $b.E.IfLine) $nt 'E1') }
  }
  # Important 2: an On* handler ATTACHED to a dataset runs inside that dataset's ApplyUpdates, not at the
  # attach line -- its CALLS subtree waits for the first later `<receiver>.ApplyUpdates` step
  $deferred = New-Object System.Collections.ArrayList
  foreach ($ln in $allLines) {
    if ($skip.ContainsKey($ln)) { continue }
    if ($omitLines.ContainsKey($ln)) {
      if ($ln -eq $omitFirst) { Add-RtItem $items (New-OmitStep $omitRecs) $ln $Id }
      continue
    }
    $rs   = @(if ($refsAt.ContainsKey($ln)) { $refsAt[$ln] })
    $lits = @(if ($litsAt.ContainsKey($ln)) { $litsAt[$ln] })
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
      $pt = Get-PayloadText $F $ln $Ctx
      [void]$x.Children.Add((New-TraceFacet 'WITH' "$([string]$c.tname) $($pt.Text)" (Get-TraceAnchorText $F.Path $ln) $pt.Note))
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
      Add-RtItem $items (New-TraceStep 'step' "$($script:RtOps[[string]$o.nm]) $recv$([string]$o.nm)$(Get-LineLits $lits $F $Ctx)" (Get-TraceAnchorText $F.Path $ln) '' $F.Short) $ln $Id
      if ([string]$o.nm -eq 'ApplyUpdates') {
        $rv = ([string]$o.recv) -replace '^Self\.', ''
        foreach ($d in @($deferred | Where-Object { $_.Recv -eq $rv })) {
          $sub = Walk-Routine $d.Hs.Id ($Depth - 1) $Visited $Ctx
          Add-CallsStep $items $d.Hs $sub $F $ln -Note "fired by $rv.ApplyUpdates at :$ln, attached as $($d.Recv).$($d.Event) at :$($d.Line)"
          $deferred.Remove($d)
        }
      }
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
          if ($verb -eq 'ATTACHES' -and $ev[0].recv) {
            [void]$deferred.Add([pscustomobject]@{ Recv = (([string]$ev[0].recv) -replace '^Self\.', ''); Event = [string]$ev[0].nm; Hs = $hs; Line = $ln })
          } else {
            $sub = Walk-Routine $hs.Id ($Depth - 1) $Visited $Ctx
            Add-CallsStep $items $hs $sub $F $ln
          }
          continue
        }
      }
    }
    # bound calls into project code (not transport, not constructors): descend. In an Exit guard's CONDITION a
    # call into a transport-convention unit is a step too (this line carried no crossing) -- the server's
    # own helpers live in uPipe* units (HandleTableLoad :549 TryBuildSafeWhere, in uPipeSessionBuilder) --
    # but it is NOT descended: the convention keeps transport bodies out of the walk, the step only names
    # the call the guard turns on. RC-R6: a transport callee whose own body makes an outward I/O call
    # ($RtOutwardIoCalls -- the post-commit broadcast) is a step too, by the same shape: kept, not descended
    foreach ($c in @($rs | Where-Object { $_.kind -eq 'call' -and $_.tid -and [int]$_.tistart -gt 0 -and [string]$_.tkind -ne 'constructor' })) {
      $cc = $c
      $g1 = [bool]@($guardGs | Where-Object { Test-InShimCondition $_ $ln ([int]$cc.col) }).Count
      $io = $false
      if (-not $g1 -and $c.tpipe -and [int]$c.tpipe -eq 1) {
        $io = Test-OutwardIoCallee ([int]$c.tid) $Ctx
        if (-not $io) { continue }
      }
      $sub = $(if ($c.tpipe -and [int]$c.tpipe -eq 1) { [pscustomobject]@{ Items = @(); Conds = @() } } else { Walk-Routine ([int]$c.tid) ($Depth - 1) $Visited $Ctx })
      $tgt = [pscustomobject]@{ Id = [int]$c.tid; Short = (Get-ShortName ([string]$c.tq) (Get-UnitName ([string]$c.tpath))); Path = [string]$c.tpath; Line = [int]$c.tistart; Grade = ''; Ask = '' }
      Add-CallsStep $items $tgt $sub $F $ln (Get-LineLits $lits $F $Ctx) -Always:($g1 -or $io)
    }
    # unbound calls with a receiver the index declares: the implementation BY NAME
    foreach ($c in @($rs | Where-Object { $_.kind -eq 'call' -and -not $_.tid -and $_.recv })) {
      $impl = Resolve-ImplByName ([string]$c.recv) ([string]$c.nm) $F
      $ask = $(if ($impl.Count -and (@(([string]$impl[0].rkinds) -split ',') | Where-Object { $_ -in 'field', 'property' })) { 'in-class-field-reads' } else { 'receiver-typed-calls' })
      if ($impl.Count -eq 1) {
        $i = $impl[0]
        $sub = Walk-Routine ([int]$i.id) ($Depth - 1) $Visited $Ctx
        $tgt = [pscustomobject]@{ Id = [int]$i.id; Short = (Get-ShortName ([string]$i.q) (Get-UnitName ([string]$i.path))); Path = [string]$i.path; Line = [int]$i.istart; Grade = 'by name'; Ask = $ask }
        Add-CallsStep $items $tgt $sub $F $ln (Get-LineLits $lits $F $Ctx) -Always
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
  # an attached handler no ApplyUpdates of its receiver fires in this routine: at the end, saying so
  foreach ($d in @($deferred)) {
    $sub = Walk-Routine $d.Hs.Id ($Depth - 1) $Visited $Ctx
    Add-CallsStep $items $d.Hs $sub $F $d.Line -Note "attached as $($d.Recv).$($d.Event) at :$($d.Line), no $($d.Recv).ApplyUpdates follows in this routine"
  }
  # Important 1: a response written and then OVERWRITTEN on the path (`ARspCmd:= rspError` :405, then
  # `ARspCmd:= rspOK` :553) is a default, not a send. The later send names it, and every Exit guard
  # between the two says it responds with that default.
  $sends = @($items | Where-Object { $_.Owner -eq $Id -and $_.Kind -eq 'step' -and $_.Text -like 'SENDS rsp*' })
  foreach ($s0 in $sends) {
    $tg0 = @(@(if ($refsAt.ContainsKey([int]$s0.Line)) { $refsAt[[int]$s0.Line] }) | Where-Object { $_.kind -eq 'write' } | ForEach-Object { [string]$_.nm })
    if (-not $tg0.Count) { continue }
    $later = @($sends | Where-Object { $_.Line -gt $s0.Line -and $items.Contains($_) -and @(@(if ($refsAt.ContainsKey([int]$_.Line)) { $refsAt[[int]$_.Line] }) | Where-Object { $_.kind -eq 'write' -and [string]$_.nm -eq $tg0[0] }).Count } | Select-Object -First 1)
    if (-not $later.Count) { continue }
    $rn = $s0.Text -replace '^SENDS ', ''
    $items.Remove($s0)
    $later[0].Note = ((@($later[0].Note, "overwrites the $rn default set at :$($s0.Line)") | Where-Object { $_ }) -join ', ')
    foreach ($gc in @($conds | Where-Object { $_.PSObject.Properties['Guard'] -and $_.IfLine -gt $s0.Line -and $_.IfLine -lt $later[0].Line })) {
      $gc.Item.Note = $(if ($gc.Item.Note) { "$($gc.Item.Note), responds $rn, the default set at :$($s0.Line)" } else { "else responds $rn, the default set at :$($s0.Line)" })
    }
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
    $hostStep = @()
    if ($c.PSObject.Properties['HostLines']) { $hostStep = @($own | Where-Object { $c.HostLines -contains $_.Line } | Select-Object -First 1) }
    elseif ($c.PSObject.Properties['HostFrom']) { $hostStep = @($own | Where-Object { $_.Line -gt $c.HostFrom -and $_.Line -lt $c.HostTo } | Select-Object -First 1) }
    if (-not $hostStep.Count -and $c.PSObject.Properties['Strict']) { continue }
    if (-not $hostStep.Count) { $hostStep = @($own | Where-Object { $_.Line -eq $c.IfLine } | Select-Object -First 1) }
    if (-not $hostStep.Count) { $hostStep = @($own | Where-Object { $_.Kind -eq 'step' -and $_.Line -lt $c.IfLine } | Select-Object -Last 1) }
    if ($hostStep.Count) {
      $h0 = $hostStep[0]
      # T5-R2: hung on the CALLS step of ANOTHER routine, the condition names its own routine
      $onCall = $h0.PSObject.Properties['CalleeId'] -and [int]$h0.CalleeId -ne $Id
      if ($onCall) { $c.Item.Routine = $F.Short }
      if ($onCall -and $c.PSObject.Properties['HostLines']) {
        # final-review I6: an if ENCLOSING the call is evaluated before it runs, so it stands ahead of the
        # callee's own conditions (Add-CallsStep added those); these callers' ifs keep their own order. A
        # guard hung here (its Exit follows the call, or the call is inside its condition) is evaluated
        # after the callee's and stays behind them
        $k = $(if ($h0.PSObject.Properties['CallerConds']) { [int]$h0.CallerConds } else { 0 })
        $h0.Children.Insert($k, $c.Item)
        $h0 | Add-Member -NotePropertyName CallerConds -NotePropertyValue ($k + 1) -Force
      } else { [void]$h0.Children.Add($c.Item) }
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
  # final-review I2: Walked -- a handler was reached and walked; when not, Stop is the STOPS that ended the
  # server side, and the caller walks no DATABASE tier and claims no response
  $out = [pscustomobject]@{ Items = $items; Responses = @(); Contract = $null; Walked = $false; Stop = $null }
  $arm = Find-DispatchArm $CmdName $Ctx.Likes
  if (-not $arm) {
    $decl = Invoke-IndexQuery "SELECT s.start_line AS l, f.path AS p FROM symbols s JOIN files f ON f.id = s.file_id WHERE s.kind = 'enum_value' AND s.name = '$(ConvertTo-SqlText $CmdName)' LIMIT 1"
    $anchor = $(if ($decl.Count) { Get-TraceAnchorText ([string]$decl[0].p) ([int]$decl[0].l) } else { 'unknown:0' })
    $out.Stop = New-TraceStep 'stops' (ConvertTo-TraceStopText "no transport routine of $($Ctx.FarIndex) reads $CmdName and then calls a handler declared in another unit") $anchor '' '' '' 'E2'
    Add-RtItem $items $out.Stop 0 0
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
      $out.Stop = New-TraceStep 'stops' (ConvertTo-TraceStopText "$($T.q) has $($im.Count) implementations in classes whose heritage names its interface") (Get-TraceAnchorText $T.path $T.decl) '' $arm.Routine '' 'E2'
      Add-RtItem $items $out.Stop $arm.CallLine 0
      return $out
    }
    $impl = [pscustomobject]@{ Id = [int]$im[0].id; Short = (Get-ShortName ([string]$im[0].q) (Get-UnitName ([string]$im[0].path))); Path = [string]$im[0].path; Line = [int]$im[0].istart; Grade = 'by name' }
    $grade = 'by name'
  }
  $visited = @{}
  $sub = Walk-Routine $impl.Id $Depth $visited $Ctx
  $out.Walked = $true
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
# final-review M7: the write-statement members of a dataset definition (FireDAC / FIB convention, as
# UpdateSQL / SelectSQL are) -- which one runs depends on the posted row
$script:RtWriteStmts = @('InsertSQL', 'UpdateSQL', 'ModifySQL', 'DeleteSQL')

# The `case <X> of` condition the walk already quoted (a cond under a walked step) in routine $F above
# line $Line: its selector as written and its line, or $null. A selector the stop text cannot carry
# untouched (' @', ' [', ' -- ', '; ', a double quote) is not quoted (T3-M2). Pure over the items.
function Get-WalkedCaseSelector($Items, $F, [int] $Line) {
  $leaf = [IO.Path]::GetFileName([string]$F.Path)
  foreach ($i in @($Items)) {
    foreach ($ch in @($i.Children | Where-Object { $_.Kind -eq 'cond' -and [string]$_.Condition -cmatch '^case\s+(.+?)\s+of$' })) {
      $x = [regex]::Match([string]$ch.Condition, '^case\s+(.+?)\s+of$').Groups[1].Value
      $f, $l = ([string]$ch.Anchor) -split ':'
      if ($f -ne $leaf -or [int]$l -lt $F.ImplStart -or [int]$l -ge $Line) { continue }
      if ($x -match '"| @| \[| -- |; ') { return $null }
      return [pscustomobject]@{ Selector = $x; Line = [int]$l }
    }
  }
  $null
}

function Get-DatabaseSteps($ServerItems, $Ctx, [string] $Mode, $SqlSet, [hashtable] $SourceOverride) {
  $items = New-Object System.Collections.ArrayList
  $verb = $(if ($Mode -eq 'write') { 'WRITES' } else { 'READS' })
  $fact = @($ServerItems | Where-Object { $_.Kind -eq 'step' -and $_.Text -match "^$verb .*\b$([regex]::Escape($Ctx.Table))\b" })
  $tblFile = $SqlSet.Tables[$Ctx.Table].File; $tblLine = $SqlSet.Tables[$Ctx.Table].Line
  if (-not $fact.Count -and $Mode -ne 'write') {
    Add-RtItem $items (Get-SelectStop $ServerItems $Ctx) 0 0
  } elseif (-not $fact.Count) {
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
      if ($Mode -eq 'write') {
        # final-review M7: the handler that runs the statement may pick it per row (`case ARequest of` :188 --
        # Insert / Update / Delete), and AfterPost fires for an inserted row too. So the step names the
        # statement for the POSTED row: every write-statement member of the same receiver the routine names
        # (a convention list, like UpdateSQL itself), and the walked `case` condition above them, if any
        $wmSorted = @($p0.F.Refs | Where-Object { $_.kind -eq 'member-access' -and [string]$_.nm -in $script:RtWriteStmts -and [string]$_.recv -ceq [string]$p0.Ref.recv } |
                      Sort-Object { [int]$_.line }, { [int]$_.col })
        # dedup by bare name, keeping the FIRST (sorted) occurrence -- same as the old Select-Object
        # -Unique on the formatted string, but keeping the ref object (its own line) for FW-R1
        $wmSeen = @{}; $wmRefs = @()
        foreach ($r in $wmSorted) { $k = [string]$r.nm; if (-not $wmSeen.ContainsKey($k)) { $wmSeen[$k] = 1; $wmRefs += $r } }
        $sel = Get-WalkedCaseSelector $ServerItems $p0.F ([int]$p0.Ref.line)
        # FW-R1 (final review): only ONE loader was named for all three members, and it is true of
        # whichever member $stmtName happens to be (:149, UpdateSQL) -- InsertSQL/DeleteSQL load on
        # OTHER lines of the same routine (:148/:150). Each member gets its OWN load line, found the
        # same way $loader is above: naming refs for THAT bare name, whose routine also holds the
        # walk's own FIB$DATASETS_INFO read.
        $wmNaming = @()
        foreach ($own in @($ServerItems | Where-Object { $_.Owner -gt 0 } | ForEach-Object { [int]$_.Owner } | Select-Object -Unique)) {
          $fw = $script:RtFacts["$DbPath|$own"]
          if (-not $fw) { continue }
          foreach ($m in @($fw.Refs | Where-Object { $_.kind -eq 'member-access' -and [string]$_.nm -in $script:RtWriteStmts })) { $wmNaming += [pscustomobject]@{ F = $fw; Ref = $m } }
        }
        $wm = @()
        foreach ($r in $wmRefs) {
          $ownLoader = $null
          foreach ($fs in @($ServerItems | Where-Object { $_.Kind -eq 'step' -and $_.Text -match '^READS .*FIB\$DATASETS_INFO' })) {
            $fsFile, $fsLine = $fs.Anchor -split ':'
            $hit = @($wmNaming | Where-Object { [string]$_.Ref.nm -eq [string]$r.nm -and [IO.Path]::GetFileName($_.F.Path) -eq $fsFile -and [int]$fsLine -ge $_.F.ImplStart -and [int]$fsLine -le $_.F.ImplEnd } |
                     Sort-Object { [int]$_.Ref.line } | Select-Object -First 1)
            if ($hit.Count) { $ownLoader = $hit[0]; break }
          }
          $wm += [pscustomobject]@{ Text = "$(if ($r.recv) { [string]$r.recv + '.' })$([string]$r.nm)"; Loader = $ownLoader }
        }
        $allLoaded = $wm.Count -gt 0 -and -not (@($wm | Where-Object { -not $_.Loader })).Count
        $names = $(if ($wm.Count -gt 1 -and $allLoaded) {
          @($wm | ForEach-Object { "$($_.Text) (loaded at $(Get-TraceAnchorText $_.Loader.F.Path ([int]$_.Loader.Ref.line)))" })
        } else { @($wm | ForEach-Object { $_.Text }) })
        $alts = $(if ($names.Count -gt 1) { "$((@($names | Select-Object -SkipLast 1)) -join ', ') or $($names[-1])" } else { $sText })
        $how = $(if ($wm.Count -gt 1 -and $sel) { ", picked by the case over $($sel.Selector) at :$($sel.Line)" } else { '' })
        $fromWhat = "from FIB`$DATASETS_INFO rows$(if ($fb -eq 0) { ' the index does not hold' })"
        $loadClause = $(
          if ($names.Count -gt 1 -and $allLoaded) { ", $fromWhat" }
          elseif ($loader) { ", loaded at $(Get-TraceAnchorText $loader.F.Path ([int]$loader.Ref.line)) $fromWhat" }
          else {
            $anyLdr = @($wm | Where-Object { $_.Loader } | Select-Object -First 1)
            if ($anyLdr.Count) { ", loaded in $($anyLdr[0].Loader.F.Short) ($(Get-TraceAnchorText $anyLdr[0].Loader.F.Path ([int]$anyLdr[0].Loader.F.ImplStart))-$([int]$anyLdr[0].Loader.F.ImplEnd)), $fromWhat" }
            else { ", whose text the walk does not read" }
          }
        )
        $why = "the statement for the posted $($Ctx.Table) row is $alts$how$loadClause ($held)"
      }
      $anchor = Get-TraceAnchorText $p0.F.Path ([int]$p0.Ref.line); $rn = $p0.F.Short
      $nt = "the statement member is named here$(if ($applyOwners -contains $p0.F.Id) { ', in the routine that executes it' })"
    } else {
      $last = @($ServerItems | Where-Object { $_.Kind -eq 'step' -and $_.Text -match '^(RUNS|APPLIES) ' } | Select-Object -Last 1)
      if (-not $last.Count) { $last = @($ServerItems | Where-Object { $_.Kind -ne 'crosses' } | Select-Object -Last 1) }
      $what = $(if ($Mode -eq 'write') { "the statement for the posted $($Ctx.Table) row" } else { "the $kind statement for $($Ctx.Table)" })
      $why = "no walked routine names $what$(if ($last.Count) { ", applied in $($last[0].Routine) at $($last[0].Anchor)" }) ($held)"
      $anchor = $(if ($last.Count) { $last[0].Anchor } else { Get-TraceAnchorText $tblFile $tblLine }); $rn = $(if ($last.Count) { $last[0].Routine } else { '' }); $nt = ''
    }
    Add-RtItem $items (New-TraceStep 'stops' (ConvertTo-TraceStopText $why) $anchor '' $rn $nt 'E4') 0 0
  }
  $cs = Get-SqlColumnState $SqlSet $Ctx.Table $Ctx.Column $SourceOverride
  if ($cs.IsColumn) {
    # final-review I7: the same untruncated column fact as the anchor's column step
    Add-RtItem $items (New-TraceStep 'step' "$verb $($Ctx.TableColumn)" (Get-TraceAnchorText $cs.File ([int]$cs.Line)) 'inferred' '' (Get-ColumnFactNote $cs $SqlSet) 'E4') 0 0
  } else {
    Add-RtItem $items (New-TraceStep 'stops' (ConvertTo-TraceStopText "$($Ctx.TableColumn): $($cs.Label)") (Get-TraceAnchorText $tblFile $tblLine) '' '' '' 'E4') 0 0
  }
  , $items.ToArray()
}

# DATABASE for a READ (Task 6; P15's rule: the STOPS says only what was QUERIED). The routine that
# RUNS the query is an `<x>.Open` owner that reads no FIB$ table itself (a FIB$ reader loads the
# dataset DEFINITIONS, it does not fetch the anchor's rows). Its first literal opening with SELECT is
# where the statement is assembled; every assignment to the variable that literal is assigned to is
# named, each quoted as written (Get-AssignExprAt; fix round 1, M3) -- and the FIB$ tables the walk reads are named with the rows
# THIS index holds of their snapshot (fb_datasets / fb_field_info, counted now; E4 asks for them).
# With no such literal, the routine and line of the last query run. The stop carries `After`, the RUNS
# step that executes the query, so the emitter can place the DATABASE steps in source order (M4). Run
# under the SERVER $DbPath.
$script:RtFbSnapshot = @{ 'FIB$DATASETS_INFO' = 'fb_datasets'; 'FIB$FIELDS_INFO' = 'fb_field_info' }
function Get-SelectStop($ServerItems, $Ctx) {
  $fib = @($ServerItems | Where-Object { $_.Kind -eq 'step' -and $_.Text -match '^READS .*\bFIB\$\w+' })
  $loaders = @($fib | ForEach-Object { [int]$_.Owner } | Select-Object -Unique)
  $tabs = @($fib | ForEach-Object { if ($_.Text -match '\b(FIB\$\w+)') { $Matches[1].ToUpperInvariant() } } | Select-Object -Unique)
  $runs = @($ServerItems | Where-Object { $_.Kind -eq 'step' -and $_.Text -match '^RUNS (\S+\.)?Open\b' -and $loaders -notcontains [int]$_.Owner })
  $held = @(); $sum = 0
  foreach ($t in $tabs) {
    if (-not $script:RtFbSnapshot.ContainsKey($t)) { continue }
    $sn = $script:RtFbSnapshot[$t]
    $n = [int](Invoke-IndexQuery "SELECT COUNT(*) AS n FROM $sn")[0].n
    $held += "$sn has $n rows"; $sum += $n
  }
  $heldTxt = $(if (-not $held.Count) { '' }
               elseif ($sum -eq 0) { ", and the FIB`$ rows the walk reads ($($tabs -join ', ')) are not in the index ($($held -join ', ') in $($Ctx.FarIndex))" }
               else { ", and the FIB`$ rows the walk reads ($($tabs -join ', ')) are not looked up by this walk ($($held -join ', ') in $($Ctx.FarIndex))" })
  foreach ($own in @($runs | ForEach-Object { [int]$_.Owner } | Select-Object -Unique)) {
    $F = $script:RtFacts["$DbPath|$own"]
    if (-not $F) { continue }
    $sel = @($F.Lits | Where-Object { $_.kind -eq 'literal' -and [string]$_.text -match '(?i)^\s*SELECT\b' } | Select-Object -First 1)
    if (-not $sel.Count) { continue }
    $ln = [int]$sel[0].line
    $src = Get-TraceSource $F.Path $Ctx.SourceOverride
    # fix round 1 (M3): EVERY assignment to the variable the SELECT literal is assigned to (`SQL:= 'SELECT '
    # ...` :544, then `SQL:= SQL + ' WHERE ' + WhereSql` :556), each quoted as written when the stop text can
    # carry it untouched (ConvertTo-TraceStopText rewrites ' -- ', ' @', ' [', '; ' and runs of blanks)
    $w0 = @($F.Refs | Where-Object { [int]$_.line -eq $ln -and $_.kind -eq 'write' -and -not $_.recv -and [int]$_.col -lt [int]$sel[0].col } | Select-Object -Last 1)
    $parts = @()
    $ws = $(if ($w0.Count) { @($F.Refs | Where-Object { $_.kind -eq 'write' -and -not $_.recv -and [string]$_.nm -eq [string]$w0[0].nm }) } else { @() })
    foreach ($w in $ws) {
      $wl = [int]$w.line
      $ex = Get-AssignExprAt $src.Raw[$wl - 1] $src.Stripped[$wl - 1] ([int]$w.col)
      $at = $(if ($parts.Count) { ":$wl" } else { Get-TraceAnchorText $F.Path $wl })
      $parts += $(if ($ex -and $ex -notmatch '"| @| \[| -- |; |\s\s|[^\x20-\x7E]') { "$at ($([string]$w.nm):= $ex)" } else { $at })
    }
    $where = $(if (-not $parts.Count) { "at $(Get-TraceAnchorText $F.Path $ln)" }
               elseif ($parts.Count -eq 1) { "in $([string]$w0[0].nm) at $($parts[0])" }
               else { "in $([string]$w0[0].nm) at $((@($parts | Select-Object -SkipLast 1)) -join ', ') and $($parts[-1])" })
    $why = "the SELECT statement for $($Ctx.Table) is assembled $where, from values the index holds no text for$heldTxt"
    $st = New-TraceStep 'stops' (ConvertTo-TraceStopText $why) (Get-TraceAnchorText $F.Path $ln) '' $F.Short 'the statement is assembled here, in the routine that runs it' 'E4'
    # M4: the DATABASE steps stand right after the step that RUNS this routine's query (the emitter places them)
    $st | Add-Member -NotePropertyName After -NotePropertyValue (@($runs | Where-Object { [int]$_.Owner -eq $own } | Select-Object -First 1) | Select-Object -First 1)
    return $st
  }
  $last = @($runs | Select-Object -Last 1)
  if (-not $last.Count) { $last = @($ServerItems | Where-Object { $_.Kind -ne 'crosses' } | Select-Object -Last 1) }
  $why = "no walked routine assembles a SELECT for $($Ctx.Table) from a literal$(if ($last.Count) { ", run in $($last[0].Routine) at $($last[0].Anchor)" })$heldTxt"
  $anchor = $(if ($last.Count) { $last[0].Anchor } else { Get-TraceAnchorText $Ctx.SqlSet.Tables[$Ctx.Table].File $Ctx.SqlSet.Tables[$Ctx.Table].Line })
  $st = New-TraceStep 'stops' (ConvertTo-TraceStopText $why) $anchor '' $(if ($last.Count) { $last[0].Routine } else { '' }) '' 'E4'
  if ($last.Count) { $st | Add-Member -NotePropertyName After -NotePropertyValue $last[0] }
  $st
}

# The event wiring on the anchor dataset in its unit: `<ds>.<Event> := <Handler>`.
# The handler is the last plain READ on the wiring line and is matched BY NAME
# among the dataset's class methods (E3: the assignment is not bound). $Events: the event names
# to read ($RtEvents, the write events, unless the caller asks for others -- the calc-field
# check asks for OnCalcFields and for every other On*/After*/Before* event, Part 6).
# RETURNS ITS ARRAY WHOLE (Sort-RtWiring's unary comma): assign it before piping -- `Get-EventWiring .. | Sort-Object` sorts ONE item.
function Get-EventWiring($Ds, [string[]] $Events = $script:RtEvents) {
  $rows = Get-AllIndexRows @"
SELECT r.start_line AS line, r.id AS rid, r.name_text AS ev, e.qualified_name AS routine,
       (SELECT h.name_text FROM refs h WHERE h.file_id = r.file_id AND h.start_line = r.start_line AND h.kind = 'read' AND h.name_text <> '$(ConvertTo-SqlText $Ds.Name)' AND h.name_text <> r.name_text ORDER BY h.start_col DESC LIMIT 1) AS handler
  FROM refs r LEFT JOIN symbols e ON e.id = r.enclosing_symbol_id
 WHERE r.file_id = $($Ds.Fid) AND r.kind = 'member-access' AND r.name_text IN ($(ConvertTo-SqlInList $Events)) AND r.receiver_text = '$(ConvertTo-SqlText $Ds.Name)'
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
  # final-review I4: in write preference order (AfterPost first), not by line -- the WRITE direction starts at [0]
  Sort-RtWiring $out.ToArray()
}

# ---- Part 5: READ routes and ALSO (Task 6) ---------------------------------------------
# READ (spec section 4): the routines that FILL the anchor dataset -- a bound call on a line of the
# dataset's unit that carries the TABLE literal and names the dataset -- whose callee's subtree
# reaches a CROSSES. Ordered by line: the first is traced, the rest are ALSO. Each candidate is
# walked with its OWN Seen (a copy of $Ctx): the READ path runs the FIB$ reads the WRITE walk
# already showed, and a candidate that is dropped must leave nothing behind. Client index.
function Get-FillRoutes($Ds, $Ctx, [int] $Depth) {
  $rows = Get-AllIndexRows @"
SELECT sl.start_line AS line, e.qualified_name AS routine, t.id AS tid, t.qualified_name AS tq, t.impl_start_line AS tistart, tf.path AS tpath, r.id AS rid
  FROM string_literals sl
  JOIN refs r ON r.file_id = sl.file_id AND r.start_line = sl.start_line AND r.kind = 'call'
  JOIN call_edges ce ON ce.ref_id = r.id JOIN symbols t ON t.id = ce.target_symbol_id JOIN files tf ON tf.id = t.file_id
  LEFT JOIN symbols e ON e.id = r.enclosing_symbol_id
 WHERE sl.file_id = $($Ds.Fid) AND sl.kind = 'literal' AND UPPER(sl.text) = '$(ConvertTo-SqlText ([string]$Ctx.Table).ToUpperInvariant())' AND t.impl_start_line > 0
   AND EXISTS (SELECT 1 FROM refs d WHERE d.file_id = sl.file_id AND d.start_line = sl.start_line AND d.name_text = '$(ConvertTo-SqlText $Ds.Name)')
"@ 'sl.start_line, r.id'
  $out = New-Object System.Collections.ArrayList
  $seen = @{}
  foreach ($r in $rows) {
    $k = "$([int]$r.line)|$([int]$r.tid)"
    if ($seen.ContainsKey($k)) { continue }
    $seen[$k] = 1
    $rc = @{}; foreach ($ck in $Ctx.Keys) { $rc[$ck] = $Ctx[$ck] }; $rc['Seen'] = @{}
    $walk = Walk-Routine ([int]$r.tid) $Depth @{} $rc
    if (-not @($walk.Items | Where-Object { $_.Kind -eq 'crosses' }).Count) { continue }
    # the fill line's literals, quoted from source (T5-R5); the routine's short name keeps its class (P8)
    $ll = Invoke-IndexQuery "SELECT sl.kind AS kind, sl.text AS text, sl.start_line AS line, sl.start_col AS col, sl.end_col AS ecol FROM string_literals sl WHERE sl.file_id = $($Ds.Fid) AND sl.start_line = $([int]$r.line) AND sl.kind = 'literal' ORDER BY sl.start_col, sl.id"
    [void]$out.Add([pscustomobject]@{ Line = [int]$r.line; Routine = $(if ($r.routine) { Get-ShortName ([string]$r.routine) (Get-UnitName $Ds.File) } else { '' }); TargetId = [int]$r.tid
                                       TargetShort = (Get-ShortName ([string]$r.tq) (Get-UnitName ([string]$r.tpath))); TargetPath = [string]$r.tpath; TargetImpl = [int]$r.tistart
                                       Lits = (Get-LineLits $ll ([pscustomobject]@{ Path = $Ds.File; Fid = $Ds.Fid }) $Ctx); Walk = $walk; Ctx = $rc })
  }
  , $out.ToArray()
}

# What the traced paths already show (fix round 1). $Paths: one item list per direction, in text order.
# Walking each until its first CLIENT-side crossing (M1: a SERVER / DATABASE actor's crossing is never a
# sender -- its Owner is a SERVER symbol id, meaningless on the CLIENT index): that crossing is the
# direction's SENDER, and the Owner of every client item before it is a routine already on the page --
# the handler, any helper between it and the sender, the sender itself (Important 2: none of them is
# "another caller"). Pure.
function Get-TracedRouteIds($Paths) {
  $snd = New-Object System.Collections.ArrayList; $cal = New-Object System.Collections.ArrayList
  foreach ($p in $Paths) {
    foreach ($i in @($p)) {
      if ([string]$i.Actor -in 'SERVER', 'DATABASE') { continue }
      $o = $(if ($i.PSObject.Properties['Owner']) { [int]$i.Owner } else { 0 })
      if ($i.Kind -eq 'crosses') { if ($o) { [void]$snd.Add($i) }; break }
      if ($o -and -not $cal.Contains($o)) { [void]$cal.Add($o) }
    }
  }
  [pscustomobject]@{ Senders = $snd.ToArray(); Callers = $cal.ToArray() }
}

# ALSO (AC-10, ruling P10): the other routes into a traced SENDER. A sender whose PAYLOAD literals name
# the anchor table (`'TABLE=OPERAT|'`; Test-TableSpecificSender, M2) serves only that table, so EVERY
# bound caller of it is a route to the anchor; a sender that takes the table from its caller
# (LoadOneTable's ATableName) serves every table, and its routes to the anchor are the fill lines
# (Get-FillRoutes), not its callers. $Senders: the crossing items (Owner, Line) of Get-TracedRouteIds.
# $SkipIds: callers already on the page -- Get-TracedRouteIds' Callers and each listed wiring's handler.
# Rows are ordered by the call line and anchored at the call site. Client index.
function Get-AlsoRoutes($Senders, [int[]] $SkipIds, $Ctx) {
  $out = New-Object System.Collections.ArrayList
  $done = @{}
  foreach ($x in @($Senders)) {
    $sid = [int]$x.Owner
    if (-not $sid -or $done.ContainsKey($sid)) { continue }
    $done[$sid] = 1
    $S = Get-RoutineFacts $sid $Ctx.Likes
    if (-not (Test-TableSpecificSender $S ([int]$x.Line) ([string]$Ctx.Table))) { continue }
    $callers = Get-AllIndexRows @"
SELECT e.id AS eid, e.qualified_name AS q, r.start_line AS line, ef.path AS path, r.id AS rid
  FROM call_edges ce JOIN refs r ON r.id = ce.ref_id JOIN symbols e ON e.id = r.enclosing_symbol_id JOIN files ef ON ef.id = e.file_id
 WHERE ce.target_symbol_id = $sid
"@ 'r.start_line, r.id'
    foreach ($c in $callers) {
      if ($SkipIds -contains [int]$c.eid) { continue }
      [void]$out.Add((New-TraceStep 'step' "CALLS $($S.Short)" (Get-TraceAnchorText ([string]$c.path) ([int]$c.line)) '' (Get-ShortName ([string]$c.q) (Get-UnitName ([string]$c.path))) 'another caller of the traced sender'))
    }
  }
  , $out.ToArray()
}

# ---- Part 6: a CALCULATED anchor field (calc-field brief, owner 2026-09-28) -------------------------
# A selection bound to a field that is not a column of its table stops at the anchor. When the field is
# CALCULATED -- its dataset has an OnCalcFields wiring (Get-EventWiring: a same-line name match, E3) AND that
# handler WRITES the field, through a TField variable bound to the field's name (Get-FieldVarWriteRows, the
# Task 3 rule) or through `FieldByName('<name>')` -- the STOPS says so, carries the handler's own guards as
# conditions (VERBATIM, the shim), and the emitter offers the SOURCE fields the computation reads, each with
# a ready command to trace it instead. Nothing here names a form, a dataset, a table or a field: the anchor
# parametrises every rule. Deeper computation inside a called routine is NOT walked, and the trace says so.
#
# Three layers: Get-CalcFieldFacts reads the index and the FRESH source (a stale file refuses, AC-14);
# Resolve-CalcField decides and lists the sources, PURE over those facts (synthetic facts test it);
# New-CalcFieldItems turns the result into Form A items, pure. Out of scope and NAMED, never offered: a field
# written only in another event's handler (AfterScroll, OnNewRecord, ...) and a field whose creating routine
# sets FieldKind fkLookup.
$script:CalcStmtRx  = [regex]'(?i)\b(begin|end|try|case|record|repeat|until|else|except|finally|if)\b|:=|[()\[\];]'
$script:CalcFkKinds = @('fkCalculated', 'fkLookup', 'fkInternalCalc', 'fkAggregate', 'fkData')
# a bound read of one of these kinds is a CONSTANT of the computation (an enum value, a type, a routine), not a value source
# fix round 2 (R2-2): the built-in types whose name is a typecast head (`Integer(x)`) -- a type, not a value
$script:CalcBuiltinTypes = @('Integer', 'Cardinal', 'ShortInt', 'SmallInt', 'LongInt', 'Int64', 'UInt64', 'Byte', 'Word', 'LongWord', 'NativeInt', 'NativeUInt',
                              'Boolean', 'ByteBool', 'WordBool', 'LongBool', 'Char', 'AnsiChar', 'WideChar', 'string', 'AnsiString', 'WideString', 'UnicodeString',
                              'Single', 'Double', 'Extended', 'Real', 'Currency', 'Comp', 'Variant', 'Pointer', 'TDateTime')
$script:CalcConstKinds = @('const', 'constant', 'enum_value', 'enum', 'type', 'class', 'record', 'interface', 'function', 'procedure', 'method', 'unit', 'resourcestring')

# The statement that starts at ($Line, 0-based $Col): up to its first depth-0 `;`, or a depth-0 end / until /
# else / except / finally (a statement that is a branch, or the last of a block, has no `;` of its own), or the
# routine's last line. Depth counts ( ) [ ] and begin/try/case/record/repeat .. end/until; an `if` after the
# `:=` is a Delphi 13 conditional expression, whose `else` stays inside. AssignLine / AssignCol: the first
# depth-0 `:=` (AssignCol -1: none). Pure over the stripped lines. L2/C2: the end, C2 exclusive.
function Get-StatementSpan([string[]] $Stripped, [int] $Line, [int] $Col, [int] $LastLine) {
  $pd = 0; $bd = 0; $ifs = 0; $al = 0; $ac = -1
  $last = [Math]::Min($LastLine, $Stripped.Count)
  for ($l = $Line; $l -le $last; $l++) {
    $s = $Stripped[$l - 1]; $from = $(if ($l -eq $Line) { [Math]::Min($Col, $s.Length) } else { 0 })
    foreach ($m in $script:CalcStmtRx.Matches($s.Substring($from))) {
      $k = $m.Value.ToLowerInvariant(); $at = $from + $m.Index
      if ($k -in '(', '[') { $pd++; continue }
      if ($k -in ')', ']') { $pd--; continue }
      if ($pd -gt 0) { continue }
      if ($k -eq ':=') { if ($ac -lt 0 -and $bd -eq 0) { $al = $l; $ac = $at }; continue }
      if ($k -in 'begin', 'try', 'case', 'record', 'repeat') { $bd++; continue }
      if ($k -in 'end', 'until') { if ($bd -gt 0) { $bd--; continue }; return [pscustomobject]@{ L1 = $Line; C1 = $Col; L2 = $l; C2 = $at; AssignLine = $al; AssignCol = $ac } }
      if ($bd -gt 0) { continue }
      if ($k -eq 'if') { if ($ac -ge 0) { $ifs++ }; continue }
      if ($k -eq 'else' -and $ifs -gt 0) { $ifs--; continue }
      if ($k -in ';', 'else', 'except', 'finally') { return [pscustomobject]@{ L1 = $Line; C1 = $Col; L2 = $l; C2 = $at; AssignLine = $al; AssignCol = $ac } }
    }
  }
  [pscustomobject]@{ L1 = $Line; C1 = $Col; L2 = $last; C2 = $(if ($last -ge 1) { $Stripped[$last - 1].Length } else { 0 }); AssignLine = $al; AssignCol = $ac }
}

# Is (1-based $Line, 0-based $Col0) on the right-hand side of span $Sp -- after its `:=`, before its end? Pure.
function Test-InStatementRhs($Sp, [int] $Line, [int] $Col0) {
  if ($Sp.AssignCol -lt 0) { return $false }
  $after = ($Line -gt $Sp.AssignLine) -or ($Line -eq $Sp.AssignLine -and $Col0 -gt $Sp.AssignCol)
  $before = ($Line -lt $Sp.L2) -or ($Line -eq $Sp.L2 -and $Col0 -lt $Sp.C2)
  $after -and $before
}

# The 0-based column where the receiver of the member at 0-based $MemberCol starts: back over blanks, the
# dot, blanks, then the (possibly dotted) identifier. -1 when the member has no dotted receiver. Pure.
function Get-ReceiverStart([string] $S, [int] $MemberCol) {
  $p = $MemberCol - 1
  while ($p -ge 0 -and [char]::IsWhiteSpace($S[$p])) { $p-- }
  if ($p -lt 0 -or $S[$p] -ne '.') { return -1 }
  $p--
  while ($p -ge 0 -and [char]::IsWhiteSpace($S[$p])) { $p-- }
  $e = $p
  while ($p -ge 0 -and ($S[$p] -match '[A-Za-z0-9_.]')) { $p-- }
  $(if ($p -lt $e) { $p + 1 } else { -1 })
}

# The statements of handler $H that WRITE the field: `<Var>.<Member> :=` for a TField variable in $Vars, or
# `<X>.FieldByName('<Field>').<Member> :=`. $H: Refs (Get-RoutineFacts columns), Raw, Stripped, ImplStart,
# ImplEnd. Each write: Line, Col (0-based, the statement's first token), Span (Get-StatementSpan). Pure.
function Find-CalcWrites($H, [string[]] $Vars, [string] $Field) {
  $out = New-Object System.Collections.ArrayList
  $seen = @{}
  foreach ($r in @($H.Refs | Where-Object { [string]$_.kind -eq 'member-access' } | Sort-Object { [int]$_.line }, { [int]$_.col })) {
    $ln = [int]$r.line
    if ($ln -lt $H.ImplStart -or $ln -gt $H.ImplEnd -or $ln -gt $H.Stripped.Count) { continue }
    $s = $H.Stripped[$ln - 1]; $c0 = [int]$r.col - 1; $e = [int]$r.ecol - 1
    $hit = $false
    if ($Vars.Count -and $Vars -contains [string]$r.recv) {
      $hit = ($e -le $s.Length) -and ($s.Substring($e) -match '^\s*:=')
    } elseif ([string]$r.nm -eq 'FieldByName' -and $Field -and $c0 -ge 0 -and $c0 -lt $H.Raw[$ln - 1].Length) {
      $m = [regex]::Match($H.Raw[$ln - 1].Substring($c0), "^FieldByName\s*\(\s*'((?:[^']|'')*)'\s*\)\s*\.\s*[A-Za-z_]\w*\s*:=")
      # the := must be CODE in the stripped copy (not inside a comment)
      $hit = $m.Success -and ($m.Groups[1].Value.Replace("''", "'") -ieq $Field) -and ($c0 + $m.Length -le $s.Length) -and ($s.Substring($c0 + $m.Length - 2, 2) -eq ':=')
    }
    if (-not $hit) { continue }
    $st = Get-ReceiverStart $s $c0
    if ($st -lt 0) { continue }
    if ($seen.ContainsKey("$ln|$st")) { continue }
    $seen["$ln|$st"] = 1
    [void]$out.Add([pscustomobject]@{ Line = $ln; Col = $st; Span = (Get-StatementSpan $H.Stripped $ln $st $H.ImplEnd) })
  }
  , $out.ToArray()
}

# The guards of the computation, VERBATIM (P16): every Exit of the handler before its first write (the Exit
# guard's own UNLESS / WHEN, from Get-GuardConditionFromLines, the note `else Exit at :N`), then each write's
# chain of enclosing ifs (WHEN "C" in a then branch; if-forms only, as the walk), read past a case (Cases: the selectors).
# A shape the shim cannot read is not guessed: its generated reason is returned in Unknown for the STOPS note. Pure.
function Get-CalcConditions($H, $Writes) {
  $out = New-Object System.Collections.ArrayList; $unk = New-Object System.Collections.ArrayList; $seen = @{}
  $first = @($Writes | Sort-Object Line, Col)[0]
  $add = { param($kw, $cond, $line, $note) $k = "$kw|$cond|$line"; if (-not $seen.ContainsKey($k)) { $seen[$k] = 1; [void]$out.Add([pscustomobject]@{ Keyword = $kw; Condition = $cond; Line = $line; Note = $note }) } }
  $exits = @($H.Refs | Where-Object { [string]$_.kind -eq 'call' -and [string]$_.nm -eq 'Exit' -and [int]$_.line -ge $H.ImplStart -and [int]$_.line -lt $first.Line } | ForEach-Object { [int]$_.line } | Sort-Object -Unique)
  foreach ($xl in $exits) {
    $g = Get-GuardConditionFromLines $H.Raw $H.Stripped $xl $H.ImplStart
    if ($g.Form -eq 'unknown') { [void]$unk.Add($g.Reason); continue }
    & $add $g.Keyword $g.Condition $g.IfLine "else Exit at :$xl"
  }
  # fix round 1 (I1): each write's chain of enclosing statements, read OUTWARDS past a case. A case arm (or a case
  # else arm) is not a branch CONDITION -- the shim does not quote an arm label -- so the case is recorded as a
  # SELECTOR of the formula (its `case X of` span; its reads become DERIVED rows) and the chain continues from the
  # case token, so an if that encloses the whole case (Assigned(...)) is still written for the writes inside it.
  # Any other shape the shim cannot place ends the chain and its generated reason goes to Unknown (the STOPS note).
  # A condition names the writes it encloses only when it does not enclose them all.
  $tok = Get-ShimTokens $H.Stripped $H.ImplStart $H.ImplEnd
  $around = [ordered]@{}; $cases = [ordered]@{}
  $wlines = @($Writes | ForEach-Object { $_.Line } | Sort-Object -Unique)
  $addCase = { param($ct, $wl)
    $k = "$($ct.L):$($ct.C)"
    if (-not $cases.Contains($k)) {
      $of = @(foreach ($q in $tok) { if (($q.L -gt $ct.L -or ($q.L -eq $ct.L -and $q.C -gt $ct.C)) -and $q.T -eq 'of') { $q; break } })
      $cases[$k] = [pscustomobject]@{ L = $ct.L; C = $ct.C; E = $ct.E; OfL = $(if ($of.Count) { $of[0].L } else { 0 }); OfC = $(if ($of.Count) { $of[0].C } else { 0 }); Lines = (New-Object System.Collections.ArrayList) }
    }
    if (-not $cases[$k].Lines.Contains($wl)) { [void]$cases[$k].Lines.Add($wl) } }
  foreach ($w in $Writes) {
    $l = $w.Line; $c = $w.Col
    for ($i = 0; $i -lt 16; $i++) {
      $e = Get-EnclosingConditionFromLines $H.Raw $H.Stripped $l $c $H.ImplStart $tok
      if ($e.Form -eq 'unknown') {
        if ($e.Reason -match 'sits in a case arm') {
          $ct = Find-EnclosingCase $tok $l $c
          if ($ct) { & $addCase $ct $w.Line; $l = $ct.L; $c = $ct.C; continue }
        }
        if ($e.Reason -notmatch 'is not inside a branch') { [void]$unk.Add($e.Reason) }
        break
      }
      if ($e.Form -eq 'case') {
        $ct = @($tok | Where-Object { $_.L -eq $e.StmtLine -and $_.C -eq $e.StmtCol -and $_.T -eq 'case' })
        if ($ct.Count) { & $addCase $ct[0] $w.Line }
      } elseif ($e.Form -in 'inline', 'block') {
        $k = "$($e.Keyword)|$($e.Condition)|$($e.IfLine)"
        if (-not $around.Contains($k)) { $around[$k] = [pscustomobject]@{ E = $e; Lines = (New-Object System.Collections.ArrayList) } }
        if (-not $around[$k].Lines.Contains($w.Line)) { [void]$around[$k].Lines.Add($w.Line) }
      }
      if (-not $e.StmtLine -or ($e.StmtLine -eq $l -and $e.StmtCol -ge $c)) { break }
      $l = $e.StmtLine; $c = $e.StmtCol
    }
  }
  foreach ($a in $around.Values) {
    $all = $a.Lines.Count -ge $wlines.Count
    & $add $a.E.Keyword $a.E.Condition $a.E.IfLine $(if ($all) { '' } else { "around the write$(if ($a.Lines.Count -gt 1) { 's' }) at $((@($a.Lines | Sort-Object | ForEach-Object { ":$_" })) -join ', ')" })
  }
  # Ifs (fix round 2, R2-3): every enclosing if-form, its condition span (CondL1/CondC1 .. CondL2/CondC2) -- the reads in it
  # CHOOSE the value exactly as a case selector does
  $ifs = [ordered]@{}; foreach ($a in $around.Values) { $k = "$($a.E.IfLine):$($a.E.CondC1)"; if (-not $ifs.Contains($k)) { $ifs[$k] = $a.E } }
  [pscustomobject]@{ Conds = $out.ToArray(); Unknown = $unk.ToArray(); Cases = @($cases.Values | Sort-Object L, C); Ifs = @($ifs.Values | Sort-Object IfLine, CondC1) }
}

# The `case` token that opens the case whose arm holds the statement at ($Line, 0-based $Col): back over balanced
# blocks to the first unclosed opener; $null when that opener is not a case. $Tok: Get-ShimTokens. Pure.
function Find-EnclosingCase($Tok, [int] $Line, [int] $Col) {
  $d = 0
  for ($q = $Tok.Count - 1; $q -ge 0; $q--) {
    $k = $Tok[$q]
    if ($k.L -gt $Line -or ($k.L -eq $Line -and $k.E -gt $Col)) { continue }
    if ($k.T -in $script:ShimClosers) { $d++; continue }
    if ($k.T -in $script:ShimOpeners) {
      if ($d -gt 0) { $d--; continue }
      # fix round 2 (R2-1): the `begin` of a begin-wrapped ARM (`1: begin .. end`, or `else begin .. end` in a case) is
      # the arm's own block -- step past it to the case that owns the arm
      if ($k.T -eq 'begin' -and $q -gt 0 -and $Tok[$q - 1].T -in ':', 'else') { continue }
      return $(if ($k.T -eq 'case') { $k } else { $null })
    }
  }
  $null
}

# Unknown reasons that differ only in their line (`the statement at :N <rest>`) merged into one. Pure.
function Join-CalcReasons([string[]] $Reasons) {
  $g = [ordered]@{}; $other = @()
  foreach ($r in $Reasons) {
    if ($r -match '^the (\w+) at :(\d+) (.+)$') { $k = "$($Matches[1])|$($Matches[3])"; if (-not $g.Contains($k)) { $g[$k] = @() }; $g[$k] += $Matches[2] }
    elseif ($other -notcontains $r) { $other += $r }
  }
  @(foreach ($k in $g.Keys) { $w, $rest = $k -split '\|', 2; $ls = @($g[$k] | Select-Object -Unique)
    $(if ($ls.Count -gt 1) { "the $($w)s at $((@($ls | ForEach-Object { ":$_" })) -join ', ') $($rest -replace '^sits ', 'sit ')" } else { "the $w at :$($ls[0]) $rest" }) }) + $other
}
# What one read on a computation's right-hand side is: a TField variable of the class (Kind var), a LOCAL of
# the handler resolved ONE hop -- its one assignment before the read names exactly one TField variable (Kind
# local) -- a `<ds>.FieldByName('<lit>')` read on the handler's dataset parameter or the anchor dataset (Kind fbn,
# fix round 1 I2: the literal is read from the fresh line), a TField variable the walk cannot bind (Kind unmapped,
# IsField), or a value it cannot place (Kind unmapped, with Why). $null: a constant -- a bound enum value, type
# or routine, or (fix round 1 M3, NAME SHAPE, no library index is read: the charts read clones only) an unbound
# name that is a receiver or call head (`TTktVerd.FromInteger`, `Integer(...)`) or has the Delphi enum/type shape
# (`dsInsert`, `ffFixed`, `TSpecType`). Locals shadow class fields, as in Pascal. Pure.
function Resolve-CalcRead($F, $H, $R) {
  $nm = [string]$R.nm; $ln = [int]$R.line
  if ($nm -eq 'Self') { return $null }
  $fb = @($H.Refs | Where-Object { [string]$_.kind -eq 'member-access' -and [string]$_.nm -eq 'FieldByName' -and [string]$_.recv -eq $nm -and [int]$_.line -eq $ln -and [int]$_.col -gt [int]$R.col } | Sort-Object { [int]$_.col } | Select-Object -First 1)
  if ($fb.Count -and (($H.Locals.ContainsKey($nm) -and $H.Locals[$nm] -eq 'param') -or $nm -eq $F.DsName)) {
    $c0 = [int]$fb[0].col - 1; $raw = $H.Raw[$ln - 1]
    $m = $(if ($c0 -lt $raw.Length) { [regex]::Match($raw.Substring($c0), "^FieldByName\s*\(\s*'((?:[^']|'')*)'\s*\)") } else { $null })
    if (-not $m -or -not $m.Success) { return [pscustomobject]@{ Kind = 'unmapped'; IsField = $true; Name = "$nm.FieldByName"; Why = 'its argument is not a string literal' } }
    return [pscustomobject]@{ Kind = 'fbn'; Name = "$nm.FieldByName"; Recv = $nm; Literal = $m.Groups[1].Value.Replace("''", "'"); IsParam = ($nm -ne $F.DsName) }
  }
  if ($H.Locals.ContainsKey($nm)) {
    if ($H.Locals[$nm] -ne 'local_var') { return [pscustomobject]@{ Kind = 'unmapped'; IsField = $false; Name = $nm; Why = "a parameter of $($H.Name)" } }
    $pos = $ln * 100000 + [int]$R.col
    $ws = @($H.Refs | Where-Object { [string]$_.kind -eq 'write' -and [string]$_.nm -eq $nm -and ([int]$_.line * 100000 + [int]$_.col) -lt $pos })
    if ($ws.Count -ne 1) { return [pscustomobject]@{ Kind = 'unmapped'; IsField = $false; Name = $nm; Why = "a local of $($H.Name) set at $($ws.Count) places before this read" } }
    $w = $ws[0]
    $sp = Get-StatementSpan $H.Stripped ([int]$w.line) ([int]$w.col - 1) $H.ImplEnd
    $vs = @($H.Refs | Where-Object { [string]$_.kind -eq 'read' -and (Test-InStatementRhs $sp ([int]$_.line) ([int]$_.col - 1)) -and -not $H.Locals.ContainsKey([string]$_.nm) -and
                                     $F.ClassFields.ContainsKey([string]$_.nm) -and ([string]$F.ClassFields[[string]$_.nm]) -match '^T\w*Field$' } |
             ForEach-Object { [string]$_.nm } | Sort-Object -Unique)
    if ($vs.Count -ne 1) { return [pscustomobject]@{ Kind = 'unmapped'; IsField = $false; Name = $nm; Why = "a local of $($H.Name) set at :$([int]$w.line) from $($vs.Count) TField variables" } }
    return [pscustomobject]@{ Kind = 'local'; Name = $nm; Var = $vs[0]; SetLine = [int]$w.line }
  }
  if ($F.ClassFields.ContainsKey($nm)) {
    $sig = [string]$F.ClassFields[$nm]
    if ($sig -match '^T\w*Field$') { return [pscustomobject]@{ Kind = 'var'; Name = $nm; Var = $nm } }
    return [pscustomobject]@{ Kind = 'unmapped'; IsField = $false; Name = $nm; Why = "a field of $($F.ClassName) of type $sig, not a TField variable" }
  }
  if ($R.tid) {
    if ([string]$R.tkind -in $script:CalcConstKinds) { return $null }
    return [pscustomobject]@{ Kind = 'unmapped'; IsField = $false; Name = $nm; Why = "a $([string]$R.tkind) outside $($F.ClassName), not a TField variable" }
  }
  # fix round 2 (R2-2): only a TYPE is a constant by name -- the Delphi type shape (`TTktVerd.FromInteger`, `TKind`), or
  # a typecast head of a built-in type (`Integer(...)`). A receiver is NOT one: a TField variable is always a receiver
  # (`.AsFloat`), and an inherited or unbound one must stay a named row, counted. Everything else unbound is named.
  $s = $H.Stripped[$ln - 1]; $e = [int]$R.ecol - 1
  if ($nm -cmatch '^[TE][A-Z]\w*$') { return $null }
  if ($nm -in $script:CalcBuiltinTypes -and $e -le $s.Length -and $s.Substring($e) -match '^\s*\(') { return $null }
  [pscustomobject]@{ Kind = 'unmapped'; IsField = $false; Name = $nm; Why = "not a field, local or parameter the walk can place" }
}

# The decision, PURE over the facts of Get-CalcFieldFacts (or synthetic ones). $F: Field (as the selection
# names it), DsName, Table, ClassName, Vars (the TField variables bound to the field), Bindings (var ->
# Get-CalcBinding result), ClassFields (name -> declared type), Wirings (Event, Line, Handler, WirePath, H),
# Creating ($null | Line, Path, Call, Kind, KindLine, KindPath), IsColumn (scriptblock: ($F, literal) -> bool).
# Returns $null (not calculated: the caller keeps its stop) or Kind calculated | event | lookup with StopText,
# StopNote and Anchor; a calculated one also carries Handler, Writes, Conds, Sources and HeadCall.
function Resolve-CalcField($F) {
  foreach ($w in @($F.Wirings | Where-Object { $_.Event -eq 'OnCalcFields' })) {
    $ws = Find-CalcWrites $w.H $F.Vars $F.Field
    if ($ws.Count) { return (New-CalcInfo $F $w $ws) }
  }
  foreach ($w in @($F.Wirings | Where-Object { $_.Event -ne 'OnCalcFields' })) {
    $ws = Find-CalcWrites $w.H $F.Vars $F.Field
    if (-not $ws.Count) { continue }
    $at = Get-TraceAnchorText $w.H.Path $ws[0].Line
    return [pscustomobject]@{ Kind = 'event'; Anchor = $at; StopNote = ''
      StopText = "$($F.Field) is not a column of $($F.Table) in the SQL index: it is set in $($w.Handler), wired as $($F.DsName).$($w.Event) at $(Get-TraceNoteLocator $w.H.Path $w.WirePath $w.Line), not in an OnCalcFields handler, so no source fields are offered" }
  }
  if ($F.Creating -and $F.Creating.Kind -eq 'fkLookup') {
    $c = $F.Creating
    return [pscustomobject]@{ Kind = 'lookup'; Anchor = (Get-TraceAnchorText $c.Path $c.Line); StopNote = ''
      StopText = "$($F.Field) is a lookup field of $($F.DsName): $($c.Call) sets FieldKind fkLookup at $(Get-TraceNoteLocator $c.Path $c.KindPath $c.KindLine), not a column of $($F.Table) in the SQL index, so no source fields are offered" }
  }
  $null
}

function New-CalcInfo($F, $Wire, $Writes) {
  $H = $Wire.H
  $cd = Get-CalcConditions $H $Writes
  # the reads on every write's right-hand side, in source order, then (fix round 1 I1) the reads in the SELECTOR of
  # every case that picks among the writes; one row per source -- a TField variable and a FieldByName read of the
  # same column are one source (I2), keyed by the column
  $rhs = @($H.Refs | Where-Object { [string]$_.kind -eq 'read' } | Where-Object { $r = $_; @($Writes | Where-Object { Test-InStatementRhs $_.Span ([int]$r.line) ([int]$r.col - 1) }).Count } |
           Sort-Object { [int]$_.line }, { [int]$_.col })
  $src = New-Object System.Collections.ArrayList; $have = @{}
  $take = { param($r, $sel)
    if ($F.Vars -contains [string]$r.nm) { return }
    $x = Resolve-CalcRead $F $H $r
    if (-not $x) { return }
    $b = $(if ($x.Kind -in 'var', 'local') { $F.Bindings[$x.Var] } else { $null })
    $key = $(if ($x.Kind -eq 'unmapped') { "?$($x.Name)" } elseif ($x.Kind -eq 'fbn') { "#$($x.Literal.ToUpperInvariant())" }
             elseif ($b -and -not $b.Why -and $b.DataSet -eq $F.DsName) { "#$($b.Literal.ToUpperInvariant())" } else { $x.Var })
    if ($have.ContainsKey($key)) { return }
    $have[$key] = 1
    [void]$src.Add((New-CalcSourceRow $F $H $r $x $sel))
  }
  foreach ($r in $rhs) { & $take $r '' }
  # fix round 2 (R2-3): the reads in every CHOOSER of the value -- a case selector (`case X of`) or an enclosing if's
  # condition -- in line order; the Exit guards are not choosers (they skip the handler, not pick a value)
  $choosers = @(@($cd.Cases | Where-Object { $_.OfL } | ForEach-Object { [pscustomobject]@{ Line = $_.L; Word = 'case'; Sp = [pscustomobject]@{ AssignLine = $_.L; AssignCol = $_.E - 2; L2 = $_.OfL; C2 = $_.OfC } } }) +
                @($cd.Ifs | ForEach-Object { [pscustomobject]@{ Line = $_.IfLine; Word = 'if'; Sp = [pscustomobject]@{ AssignLine = $_.CondL1; AssignCol = $_.CondC1 - 1; L2 = $_.CondL2; C2 = $_.CondC2 } } }) |
                Sort-Object Line, Word)
  foreach ($ch in $choosers) {
    foreach ($r in @($H.Refs | Where-Object { [string]$_.kind -eq 'read' -and (Test-InStatementRhs $ch.Sp ([int]$_.line) ([int]$_.col - 1)) } | Sort-Object { [int]$_.line }, { [int]$_.col })) {
      & $take $r "$($ch.Word) at $(Get-TraceNoteLocator $H.Path $H.Path $ch.Line)"
    }
  }
  # the call that computes the value: the first token of a right-hand side, when it is a call; the others named
  $calls = @($H.Refs | Where-Object { [string]$_.kind -eq 'call' } | Where-Object { $r = $_; @($Writes | Where-Object { Test-InStatementRhs $_.Span ([int]$r.line) ([int]$r.col - 1) }).Count } |
             Sort-Object { [int]$_.line }, { [int]$_.col })
  $head = $null
  foreach ($w in $Writes) {
    $sp = $w.Span
    $hc = @($calls | Where-Object { Test-InStatementRhs $sp ([int]$_.line) ([int]$_.col - 1) } | Select-Object -First 1)
    if (-not $hc.Count) { continue }
    # nothing but blanks between the := and the call
    $gap = $(if ([int]$hc[0].line -eq $sp.AssignLine) { $H.Stripped[$sp.AssignLine - 1].Substring($sp.AssignCol + 2, [int]$hc[0].col - 1 - ($sp.AssignCol + 2)) }
             else { $H.Stripped[$sp.AssignLine - 1].Substring($sp.AssignCol + 2) + (@(for ($l = $sp.AssignLine + 1; $l -lt [int]$hc[0].line; $l++) { $H.Stripped[$l - 1] }) -join '') + $H.Stripped[[int]$hc[0].line - 1].Substring(0, [int]$hc[0].col - 1) })
    if ($gap.Trim()) { continue }
    $head = $hc[0]; break
  }
  $hcall = $null
  if ($head) {
    $others = @($calls | ForEach-Object { [string]$_.nm } | Where-Object { $_ -ne [string]$head.nm } | Select-Object -Unique)
    $at = $(if ($head.tid -and $head.tpath -and [int]$head.tdecl -gt 0) { Get-TraceAnchorText ([string]$head.tpath) ([int]$head.tdecl) } else { Get-TraceAnchorText $H.Path ([int]$head.line) })
    $hcall = [pscustomobject]@{ Name = [string]$head.nm; Anchor = $at
                                Note = "computed by this call at :$([int]$head.line), its body is not walked$(if ($others.Count) { ", nor are those of $($others -join ', ')" })" }
  }
  $first = @($Writes | Sort-Object Line, Col)[0]
  $anchor = Get-TraceAnchorText $H.Path $first.Line
  # fix round 1 (M1): "created" only when the creating call's body sets FieldKind exactly once; otherwise the line
  # only NAMES the field beside its dataset
  $cloc = $(if ($F.Creating) { Get-TraceNoteLocator $H.Path $F.Creating.Path $F.Creating.Line } else { '' })
  $created = $(if (-not $F.Creating) { '' } elseif ($F.Creating.Kind) { "created (FieldKind $($F.Creating.Kind)) at $cloc, " } else { "named at $cloc, " })
  $kindNote = $(if ($F.Creating -and $F.Creating.Kind) { ", $($F.Creating.Call) sets FieldKind $($F.Creating.Kind) at $(Get-TraceNoteLocator $H.Path $F.Creating.KindPath $F.Creating.KindLine)" } else { '' })
  $unkNote = $(if ($cd.Unknown.Count) { ", not read as a guard: $((@(Join-CalcReasons $cd.Unknown | ForEach-Object { ConvertTo-TraceNoteText $_ })) -join ', ')" } else { '' })
  # fix round 1 (I1): the cases that pick the formula are not guards -- say which writes each picks among
  $caseNote = $(if ($cd.Cases.Count) { ", the formula is chosen by $((@($cd.Cases | ForEach-Object { "the case at $(Get-TraceNoteLocator $H.Path $H.Path $_.L) (writes at $((@($_.Lines | Sort-Object | ForEach-Object { ":$_" })) -join ', '))" })) -join ' and '), $(if ($cd.Cases.Count -gt 1) { 'their selectors are' } else { 'its selector is' }) offered below" } else { '' })
  [pscustomobject]@{
    Kind = 'calculated'; Field = $F.Field; DsName = $F.DsName; Table = $F.Table; Handler = $Wire; Writes = $Writes; Anchor = $anchor
    Conds = $cd.Conds; CondUnknown = $cd.Unknown; Sources = $src.ToArray(); HeadCall = $hcall
    StopText = "$($F.Field) is a calculated field of $($F.DsName) (${created}computed in $($Wire.Handler) at $(Get-TraceNoteLocator $H.Path $H.Path $H.ImplStart)-$($H.ImplEnd)), not a column of $($F.Table) in the SQL index"
    StopNote = "wired as $($F.DsName).OnCalcFields at $(Get-TraceNoteLocator $H.Path $Wire.WirePath $Wire.Line), the handler matched by name$kindNote$caseNote$unkNote"
  }
}

# One offered source as row data: Text, Line (the read), Grade, Note (without the binding reason), Reason (the
# binding's Task 3 reason, which New-CalcFieldItems states ONCE when every row shares it -- fix round 1 M4), Ask,
# Target (the -Target that traces it instead, '' when there is none), IsField (a field, mapped or not -- not an
# other value) and Selector ('' or `case at :N`: the read picks the formula, fix round 1 I1). Pure.
function New-CalcSourceRow($F, $H, $R, $X, [string] $Sel = '') {
  $row = [pscustomobject]@{ Text = ''; Line = [int]$R.line; Grade = ''; Note = ''; Reason = ''; Ask = ''; Target = ''; IsField = $true; Selector = $Sel; Name = $X.Name }
  $selText = $(if ($Sel) { ", chooses the value ($Sel)" } else { '' })
  if ($X.Kind -eq 'unmapped') { $row.IsField = [bool]$X.IsField; $row.Text = ConvertTo-TraceStopText "FROM $($X.Name), not mapped: $($X.Why)$selText"; return $row }
  if ($X.Kind -eq 'fbn') { return (New-CalcFieldByNameRow $F $H $R $X $row $selText) }
  $b = $F.Bindings[$X.Var]
  if (-not $b -or $b.Why) {
    $why = $(if ($b) { $b.Why } else { 'no binding line of it is in the index' })
    $row.Text = ConvertTo-TraceStopText "FROM $($X.Name), not mapped: $($X.Var) $why$selText"; return $row
  }
  $row.Target = $b.Qname
  $label = Get-CalcColumnLabel $F $H @($X.Var) $b.Literal $b.DataSet
  $via = $(if ($X.Kind -eq 'local') { "$($X.Name), set from $($X.Var)" } else { $X.Var })
  $row.Text = ConvertTo-TraceStopText "FROM $label VIA $via$selText"
  $pre = $(if ($X.Kind -eq 'local') { "$($X.Name) set at :$($X.SetLine), " } else { '' })
  $calc = $(if ($label -like '* (calculated)') { "itself calculated in $($H.Name), not expanded, " } else { '' })
  $row.Note = ConvertTo-TraceNoteText "$calc$pre$($X.Var) bound at $(Get-TraceNoteLocator $H.Path $b.Path $b.Line) $($b.Via)"
  $row.Reason = ConvertTo-TraceNoteText $b.Reason
  # the read of an in-class field is unbound in this index: matched by name among the class's fields
  $unbound = -not $R.tid
  $row.Grade = $(if ($b.Grade) { $b.Grade } elseif ($unbound) { 'by name' } else { '' })
  $row.Ask = $(if ($b.Ask) { $b.Ask } elseif ($unbound) { 'in-class-field-reads' } else { '' })
  $row
}

# The label of a source column: `<TABLE>.<COL>` for a column of the anchor's table, `<lit> (calculated)` when the
# same handler writes it (marked, not expanded), `<lit> (not a column of <TABLE>)`, `<lit> of <DataSet>` for another
# dataset's field. $Vars: the TField variables bound to it. Pure (IsColumn is the facts' scriptblock).
function Get-CalcColumnLabel($F, $H, [string[]] $Vars, [string] $Lit, [string] $DataSet) {
  if ($DataSet -ne $F.DsName) { return "$Lit of $DataSet" }
  if ((Find-CalcWrites $H $Vars $Lit).Count) { return "$Lit (calculated)" }
  if (& $F.IsColumn $F $Lit) { return "$($F.Table).$($Lit.ToUpperInvariant())" }
  "$Lit (not a column of $($F.Table))"
}

# fix round 1 (I2): `<ds>.FieldByName('<lit>')` read on the right-hand side -- the canonical OnCalcFields idiom. The
# column is the literal on the anchor's dataset (the handler's dataset parameter is TAKEN as it: [inferred]). The
# -Target that resolves to THIS dataset: a TField variable bound to the same column; else TABLE.COLUMN when exactly one
# dataset loads the table (Resolve-AnchorFromColumn stops otherwise); else none, and the row says why.
function New-CalcFieldByNameRow($F, $H, $R, $X, $Row, [string] $SelText) {
  $lit = $X.Literal
  $bv = @($F.Bindings.Values | Where-Object { -not $_.Why -and $_.DataSet -eq $F.DsName -and $_.Literal -ieq $lit } | Sort-Object Var)
  $label = Get-CalcColumnLabel $F $H @($bv | ForEach-Object { $_.Var }) $lit $F.DsName
  $Row.Text = ConvertTo-TraceStopText "FROM $label VIA $($X.Recv).FieldByName$SelText"
  $who = $(if ($X.IsParam) { "$($X.Recv) is a parameter of $($H.Name), taken as $($F.DsName)" } else { "on $($F.DsName)" })
  if ($bv.Count) {
    $Row.Target = $bv[0].Qname
    $how = "traced through $($bv[0].Var), bound at $(Get-TraceNoteLocator $H.Path $bv[0].Path $bv[0].Line) $($bv[0].Via)"
  } elseif ($label -notmatch ' \(' -and [int]$F.TableDataSets -eq 1) {
    $Row.Target = "$($F.Table).$($lit.ToUpperInvariant())"
    $how = "traced as $($Row.Target), the one dataset that loads $($F.Table)"
  } else {
    $how = "no -Target resolves to $($F.DsName): $([int]$F.TableDataSets) datasets load $($F.Table) and no TField variable is bound to '$lit'"
  }
  $Row.Note = ConvertTo-TraceNoteText "$who, $how"
  $Row.Grade = $(if ($X.IsParam) { 'inferred' } elseif (-not $R.tid) { 'by name' } else { '' })
  $Row.Ask = $(if (-not $X.IsParam -and -not $R.tid) { 'in-class-field-reads' } else { '' })
  $Row
}

# A TField variable's binding from its write rows (Get-FieldVarWriteRows): exactly ONE (dataset field, column
# literal) pair binds it -- DataSet, Literal, Line, Path, Qname, Via (`via FF` / `by FieldByName`, the row's short
# form) and the Task 3 grade -- else Why says what the rows name instead. Pure.
function Get-CalcBinding([string] $Var, $Rows) {
  $fp = Get-FieldVarPairs $Rows
  if ($fp.Pairs.Count -ne 1) { return [pscustomobject]@{ Var = $Var; Why = "is written on $(@($Rows).Count) line(s) naming $($fp.Pairs.Count) (dataset field, column literal) pairs" } }
  $ds, $lit = $fp.Pairs[0] -split '\|'
  $site = $fp.Ok[0]
  $g = Get-FieldVarSiteGrade $site $ds
  $cl = @(([string]$site.calls) -split ',' | Where-Object { $_ -and $_ -ne 'FieldByName' } | Sort-Object -Unique)
  $via = $(if ([int]$(if ($site.fbn) { $site.fbn } else { 0 }) -gt 0) { 'by FieldByName' } elseif ($cl.Count -eq 1) { "via $($cl[0])" } elseif ($cl.Count) { "via one of $($cl -join ', ')" } else { 'with no call on the line' })
  [pscustomobject]@{ Var = $Var; Why = ''; DataSet = $ds; Literal = $lit; Line = [int]$site.line; Path = [string]$site.path; Qname = [string]$site.vq
                     Grade = $g.Grade; Reason = $g.Reason; Ask = $g.Ask; Via = $via }
}
# One handler's facts: its refs (nested routines' left out, as Get-RoutineFacts does), its locals and
# parameters, and its FRESH source (Get-TraceSource refuses a stale file).
function Get-CalcHandler($Wiring, [hashtable] $SourceOverride) {
  $s = Invoke-IndexQuery "SELECT s.name AS name, s.impl_start_line AS istart, s.impl_end_line AS iend, s.file_id AS fid, f.path AS path FROM symbols s JOIN files f ON f.id = s.file_id WHERE s.id = $([int]$Wiring.HandlerId)"
  $s = $s[0]; $id = [int]$Wiring.HandlerId
  $refs = Get-AllIndexRows @"
SELECT r.id AS rid, r.kind AS kind, r.name_text AS nm, r.receiver_text AS recv, r.start_line AS line, r.start_col AS col, r.end_col AS ecol,
       t.id AS tid, t.kind AS tkind, t.qualified_name AS tq, t.start_line AS tdecl, tf.path AS tpath
  FROM refs r
  LEFT JOIN symbols t ON t.id = COALESCE((SELECT ce.target_symbol_id FROM call_edges ce WHERE ce.ref_id = r.id), r.symbol_id)
  LEFT JOIN files tf ON tf.id = t.file_id
 WHERE r.file_id = $([int]$s.fid) AND r.start_line BETWEEN $([int]$s.istart) AND $([int]$s.iend)
   AND (r.enclosing_symbol_id = $id OR r.enclosing_symbol_id IS NULL)
"@ 'r.start_line, r.start_col, r.id'
  $loc = Invoke-IndexQuery "SELECT name AS name, kind AS kind FROM symbols WHERE parent_id = $id AND kind IN ('local_var', 'param')"
  $locals = @{}; foreach ($l in $loc) { $locals[[string]$l.name] = [string]$l.kind }
  $src = Get-TraceSource ([string]$s.path) $SourceOverride
  [pscustomobject]@{ Name = [string]$s.name; Path = [string]$s.path; ImplStart = [int]$s.istart; ImplEnd = [int]$s.iend; Refs = $refs; Locals = $locals
                     Raw = $src.Raw; Stripped = $src.Stripped }
}

# The facts Resolve-CalcField decides on, read from the index (the dataset's unit and class) and the fresh source.
function Get-CalcFieldFacts($Ds, [string] $Col, [string] $Table, $SqlSet, [hashtable] $SourceOverride) {
  $cls = Invoke-IndexQuery "SELECT name AS name FROM symbols WHERE id = $([int]$Ds.ClassId)"
  $cf = Get-AllIndexRows "SELECT s.id AS id, s.name AS name, s.signature AS sig FROM symbols s WHERE s.parent_id = $([int]$Ds.ClassId) AND s.kind = 'field'" 's.id'
  $fields = @{}; foreach ($f in $cf) { $fields[[string]$f.name] = ([string]$f.sig).Trim() }
  $rows = Get-FieldVarWriteRows ([int]$Ds.ClassId) "v.parent_id = $([int]$Ds.ClassId) AND v.kind = 'field' AND TRIM(v.signature) LIKE 'T%Field'"
  $bind = @{}
  foreach ($g in @($rows | Group-Object { [string]$_.var })) { $bind[$g.Name] = Get-CalcBinding $g.Name $g.Group }
  $vars = @($bind.Values | Where-Object { -not $_.Why -and $_.DataSet -eq $Ds.Name -and $_.Literal -ieq $Col } | ForEach-Object { $_.Var })
  # every event wired on the dataset: OnCalcFields decides; any other On*/After*/Before* names a field set there
  $ev = Invoke-IndexQuery "SELECT DISTINCT r.name_text AS ev FROM refs r WHERE r.file_id = $($Ds.Fid) AND r.kind = 'member-access' AND r.receiver_text = '$(ConvertTo-SqlText $Ds.Name)' AND (r.name_text LIKE 'On%' OR r.name_text LIKE 'After%' OR r.name_text LIKE 'Before%')"
  $events = @($ev | ForEach-Object { [string]$_.ev } | Where-Object { $_ -cmatch '^(On|After|Before)[A-Z]' })
  $wir = New-Object System.Collections.ArrayList
  if ($events.Count) {
    # assigned first: Get-EventWiring returns its array whole (Sort-RtWiring's unary comma), a pipe would sort ONE item
    $wl = Get-EventWiring $Ds $events
    foreach ($w in @($wl | Sort-Object @{ E = { if ($_.Event -eq 'OnCalcFields') { 0 } else { 1 } } }, @{ E = { [int]$_.Line } })) {
      [void]$wir.Add([pscustomobject]@{ Event = $w.Event; Line = $w.Line; Handler = $w.Handler; WirePath = $Ds.File; H = (Get-CalcHandler $w $SourceOverride) })
    }
  }
  # the line that CREATES the field: its name as a literal beside the dataset on a line that writes no variable (a
  # binding line writes one); its first call, and the FieldKind that call's body sets (`F.FieldKind:= fkCalculated`)
  $creating = $null
  $cl = Invoke-IndexQuery @"
SELECT sl.start_line AS line FROM string_literals sl
 WHERE sl.file_id = $($Ds.Fid) AND sl.kind = 'literal' AND UPPER(sl.text) = UPPER('$(ConvertTo-SqlText $Col)')
   AND EXISTS (SELECT 1 FROM refs d WHERE d.file_id = sl.file_id AND d.start_line = sl.start_line AND d.kind = 'read' AND d.name_text = '$(ConvertTo-SqlText $Ds.Name)')
   AND NOT EXISTS (SELECT 1 FROM refs w WHERE w.file_id = sl.file_id AND w.start_line = sl.start_line AND w.kind = 'write')
 ORDER BY sl.start_line LIMIT 1
"@
  if ($cl.Count) {
    $ln = [int]$cl[0].line
    $call = Invoke-IndexQuery "SELECT r.name_text AS nm, COALESCE((SELECT ce.target_symbol_id FROM call_edges ce WHERE ce.ref_id = r.id), r.symbol_id) AS tid FROM refs r WHERE r.file_id = $($Ds.Fid) AND r.start_line = $ln AND r.kind = 'call' ORDER BY r.start_col LIMIT 1"
    $creating = [pscustomobject]@{ Line = $ln; Path = $Ds.File; Call = $(if ($call.Count) { [string]$call[0].nm } else { '' }); Kind = ''; KindLine = 0; KindPath = '' }
    if ($call.Count -and $call[0].tid) {
      # fix round 1 (M1): the kind only when the body sets FieldKind on exactly ONE line (a helper that sets it on
      # several, by branch, proves no kind for this field)
      $fk = Invoke-IndexQuery @"
SELECT r.name_text AS k, r.start_line AS line, f.path AS path FROM refs r JOIN files f ON f.id = r.file_id
 WHERE r.enclosing_symbol_id = $([int]$call[0].tid) AND r.kind = 'read' AND r.name_text IN ($(ConvertTo-SqlInList $script:CalcFkKinds))
   AND EXISTS (SELECT 1 FROM refs m WHERE m.file_id = r.file_id AND m.start_line = r.start_line AND m.kind = 'member-access' AND m.name_text = 'FieldKind')
 ORDER BY r.start_line LIMIT 5
"@
      if ($fk.Count -eq 1) { $creating.Kind = [string]$fk[0].k; $creating.KindLine = [int]$fk[0].line; $creating.KindPath = [string]$fk[0].path }
    }
  }
  $tds = Get-TableDataSetRows $Table     # assigned directly: @(...) would nest it (Invoke-IndexQuery contract)
  [pscustomobject]@{ Field = $Col; DsName = $Ds.Name; Table = $Table; ClassName = $(if ($cls.Count) { [string]$cls[0].name } else { '' })
                     Vars = $vars; Bindings = $bind; ClassFields = $fields; Wirings = $wir.ToArray(); Creating = $creating; TableDataSets = $tds.Count
                     SqlSet = $SqlSet; SourceOverride = $SourceOverride; IsColumn = { param($F, $lit) (Get-SqlColumnState $F.SqlSet $F.Table $lit $F.SourceOverride).IsColumn } }
}

function Get-CalcFieldInfo($Ds, [string] $Col, [string] $Table, $SqlSet, [hashtable] $SourceOverride) {
  Resolve-CalcField (Get-CalcFieldFacts $Ds $Col $Table $SqlSet $SourceOverride)
}

# The Form A items of a CALCULATED anchor (Kind calculated): the STOPS -- its guards as conditions, the call
# that computes the value as a VIA facet -- and the DERIVED rows, one numbered step per source with a
# REGENERATE facet holding the command that traces it instead ($CmdFor: target -> command). Note: the DERIVED
# section's lead-in (form-a-grammar-spec.md 8.5). Pure.
function New-CalcFieldItems($Info, [scriptblock] $CmdFor) {
  $H = $Info.Handler.H
  $stop = New-TraceStep 'stops' (ConvertTo-TraceStopText $Info.StopText) $Info.Anchor '' $H.Name (ConvertTo-TraceNoteText $Info.StopNote) 'E3'
  foreach ($c in $Info.Conds) { [void]$stop.Children.Add((New-TraceCond $c.Keyword $c.Condition (Get-TraceAnchorText $H.Path $c.Line) $c.Note)) }
  if ($Info.HeadCall) { [void]$stop.Children.Add((New-TraceFacet 'VIA' $Info.HeadCall.Name $Info.HeadCall.Anchor $Info.HeadCall.Note)) }
  # fix round 1 (M4): a binding reason every row shares is stated ONCE, in the note; a row keeps `bound at :N via FF`
  $rs = @($Info.Sources | Where-Object { $_.Reason } | ForEach-Object { $_.Reason } | Select-Object -Unique)
  $shared = $(if ($rs.Count -eq 1) { $rs[0] } else { '' })
  $rows = New-Object System.Collections.ArrayList
  foreach ($s in $Info.Sources) {
    $nt = $(if ($s.Reason -and -not $shared) { "$($s.Note): $($s.Reason)" } else { $s.Note })
    $st = New-TraceStep 'step' $s.Text (Get-TraceAnchorText $H.Path $s.Line) $s.Grade $H.Name $nt $s.Ask
    if ($s.Target) { [void]$st.Children.Add((New-TraceFacet 'REGENERATE' (& $CmdFor $s.Target))) }
    [void]$rows.Add($st)
  }
  # the lead-in counts FIELDS the value is computed from, the fields that SELECT the formula (a case selector, I1), and
  # other values the walk cannot map (M3: a constant is none of these) -- each row says which it is
  $n = @($Info.Sources | Where-Object { $_.IsField -and -not $_.Selector }).Count
  $sN = @($Info.Sources | Where-Object { $_.Selector }).Count
  $u = @($Info.Sources | Where-Object { -not $_.IsField -and -not $_.Selector }).Count
  $cmd = @($Info.Sources | Where-Object { $_.Target }).Count
  # fix round 2 (R2-3): the choosers -- case selectors AND enclosing if conditions -- by word, in line order: `if at :1106, :1110, case at :1043`
  $chW = [ordered]@{}
  foreach ($s in @($Info.Sources | Where-Object { $_.Selector })) { $w, $at = $s.Selector -split ' at ', 2; if (-not $chW.Contains($w)) { $chW[$w] = New-Object System.Collections.ArrayList }; if (-not $chW[$w].Contains($at)) { [void]$chW[$w].Add($at) } }
  $loc = (@($chW.Keys | ForEach-Object { "$_ at $($chW[$_] -join ', ')" })) -join ', '
  $lead = "$($Info.Field) is calculated from $(if ($n) { "$n field$(if ($n -ne 1) { 's' })" } else { 'no field' })"
  if ($sN) { $lead += $(if ($n) { ", and the value is chosen by $sN more ($loc)" } else { ", but its value is chosen by $sN ($loc)" }) }
  if ($u) { $lead += ", and $u other value$(if ($u -ne 1) { 's' }) the walk cannot map" }
  $tail = $(if (-not $cmd) { ' -- nothing to trace instead' } elseif ($cmd -eq 1) { ' -- trace it instead' } else { ' -- trace one of them instead' })
  $nb = @($Info.Sources | Where-Object { $_.Reason }).Count
  $note = "$lead$tail$(if ($cmd -and $shared) { " ($(if ($nb -eq 1) { 'the binding' } else { 'every binding' }) below: $shared)" }):"
  if (-not $cmd) { $note = "$lead$tail" }
  [pscustomobject]@{ Stop = $stop; Rows = $rows.ToArray(); Note = $note }
}
