<#
  Emit-LandsWhere.ps1 -- the `lands-where` question: this FIELD, where does it
  land in the database -- which server code writes and reads it, which
  TABLE.COLUMN it is, which triggers and procedures touch that column, and which
  forms show it?

  TWO SELECTION KINDS, DISPATCHED ON WHAT RESOLVES (protocol-trace precedent)
  --------------------------------------------------------------------------
    * an ORM object property or its backing field, on -DbPath:
        uCAUSFAIL.TmcCAUSFAIL.REASON   iCAUSFAIL.ImcCAUSFAIL.REASON
        uCAUSFAIL.TmcCAUSFAIL.fREASON  (-> the property REASON, [by name])
    * a DFM-bound field: <Form>.<Control> (frmCausFail.colREASON). Its datasource
      chain is the ONE feeds-from uses (Get-FieldBindingChains ->
      Get-DataSourceChain), so the two verbs cannot disagree about which table a
      control feeds (controller ruling R17: the 13 uJobList controls bound to
      computed FOLDERS fields read "not a column of FOLDERS -- computed or
      UI-only" in both). A chain that resolves continues as the ORM case for the
      resolved TABLE.COLUMN.
  Anything else refuses: "not an ORM object property (class is not Tmc<T>) and
  not a DFM-bound field".

  THREE INDEXES, NONE OF THEM THE DATABASE
  ----------------------------------------
    -DbPath        CLIENT clone: the ORM classes (COMMON units) and the DFM bindings
    -ServerDbPath  SERVER clone: TDataService_<T>_SERVER, the write/read path
    -SqlDbPath     SQL-script clone: TABLE.COLUMN, triggers, procedures
  Every one goes through Get-CloneDb; the roles are checked so a swapped pair
  refuses instead of rendering an empty chart.

  THE TABLE IS A NAMING CONVENTION, AND IS DRAWN AS ONE (plan R10)
  -----------------------------------------------------------------
  Tmc<T>.PROP = T.PROP holds for 1,992 of the 1,997 properties that sit on a
  table-named class by what the SQL index extracts (extractor 1.19, 2026-09-24;
  1,991 + the quoted FOLDERCOUNT.TABLE on 1.18). That is a convention, not a fact: the
  table hop is dashed and graded [inferred -- naming convention, N of M ...] with
  the numbers MEASURED on this run and printed, never quoted from the plan. The
  exceptions are the interesting rows: a property that is not a column of T
  renders "not a column of T -- computed or UI-only" and the DB side stays empty.
  But absence from the SCRIPTS is checked twice before it is called that (see the
  two FINDINGS below and the server-SQL rule at the server step): STATIONS.GRIDS /
  .MENUS are missing from every script yet written and read by the server's own SQL.

  FINDING (2026-09-23): two of those "exceptions" are REAL columns the SQL index
  does not extract. MS1.SQL declares `"TABLE"` on FOLDERCOUNT (:3848) and
  `"ACTION"` on IPCHART (:2243) as QUOTED identifiers, and the script index emits
  no sql_column for a quoted name. IPCHART.ACTION survives through the older
  MScript2.SQL copy (unquoted there -- the R8 known gap); FOLDERCOUNT.TABLE has no
  other copy. So before saying "not a column", the table's declaration is read
  from fresh source for a quoted identifier of that name, and a hit renders as
  such, [inferred -- source scan], anchored on its line. That test, and every
  label it prints, is Get-SqlColumnState in Emit-Common -- the ONE column test
  consumers and feeds-from use too. A script that differs from the indexed copy
  is not scanned, and the chart then says [stale source], never "not a column".
  ENGINE D19 FIXED (extractor 1.19): both quoted names are now extracted, so
  both are ordinary columns and no real property reaches the quoted state; it
  stays as a guard (R25) and the gate drives it on a hand-made table set.

  THE SERVER SIDE: facts first, literals graded
  ----------------------------------------------
  Per routine of TDataService_<T>_SERVER (the class found BY NAME, P36):
    [certain]  member accesses resolved to Imc<T>.PROP (member_accesses -- the
               `Obj.REASON` rows; 5,013 over 133 classes, every one bound)
    [inferred] an upper-case SQL literal in a routine whose literals name T
               after a verb (Get-SqlVerbTables), word-matching the COLUMN --
               PrepareSaveQuery's `(ID, REASON, ...)`, PrepareLoadQuery's
               `REASON AS REASON`
    [inferred] a ParamByName('<COL>') literal
  One row per routine, anchored on its first evidence line. Routines named
  *Save* are the write path, *Load* the read path. Load assigns the property
  from `QRYLoad.Fields[i]` -- positional, so the COLUMN is not named there; the
  row is the member access, and the chart says positional reads are not shown.

  FINDING (2026-09-23, R6): the plan lists a "Save ParamByName" row. There is
  none: all 189 ParamByName literals inside a DataService routine are in Load
  (188, the key parameters) and FindOperatorName (1). Save binds `Params[i]`
  positionally. The Save row is its member access (`Obj.REASON` :229).

  THE DATABASE SIDE (SQL index): triggers FOR T whose scanned body mentions
  NEW.<COL> / OLD.<COL> (P39), and procedures whose scanned body names T after a
  verb and word-matches COL (Task 2's scanner, 168/168 bodies). THE CLIENT SIDE:
  every field-bound control whose chain resolves to T with that column -- drawn;
  every other binding of the same name counted by where its chain went.

  PATH B (orm_links): detected, not used. Get-OrmLinksState reads the row count
  on BOTH Delphi clones; 0 today, printed on the focus box as the route taken.

  FRESHNESS (R11): SQL bodies and the quoted-identifier scan read source only
  after Test-SourceFresh; the chain reads Delphi source the same way.
  -SourceOverride maps an indexed path to a copy (ruling R4).
#>
[CmdletBinding()]
param(
  [Parameter(Mandatory)][Alias('Target','Qname')][string] $Field,
  [Parameter(Mandatory)][string] $DbPath,
  [Parameter(Mandatory)][string] $ServerDbPath,
  [Parameter(Mandatory)][string] $SqlDbPath,
  [string]    $OutDir,
  [int]       $Cap = 12,                  # rows shown per cluster; the rest disclosed
  [hashtable] $SourceOverride,
  [string] $Engine     = 'C:\Projects\Delphi-RAG-lint-wt\archify-ir\third_party\dll-win64\drag-lint.exe',
  [string] $Dot        = 'C:\Projects\GraphWiz\Graphviz-16.1.0-win64\bin\dot.exe',
  [string] $FontMono   = 'Consolas',
  [string] $FontSans   = 'Segoe UI'
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Emit-Common.ps1')

$DbPath       = Get-CloneDb $DbPath
$ServerDbPath = Get-CloneDb $ServerDbPath
$SqlDbPath    = Get-CloneDb $SqlDbPath

$PAL = @{
  propBorder  = '#0F766E'; propFill  = '#E2F1EF'; propHdr  = '#0F766E'
  ctlBorder   = '#7C3AED'; ctlFill   = '#F3EEFF'; ctlHdr   = '#7C3AED'
  writeBorder = '#C2410C'; writeFill = '#FFF4E6'; writeHdr = '#C2410C'
  readBorder  = '#3B5BDB'; readFill  = '#EDF2FF'; readHdr  = '#3B5BDB'
  dbBorder    = '#BE185D'; dbFill    = '#FDF2F8'; dbHdr    = '#BE185D'
  stopBorder  = '#6B7280'; stopFill  = '#F3F4F6'; stopHdr  = '#6B7280'
  focusBorder = '#0F766E'; focusFill = '#E2F1EF'; focusHdr = '#0F766E'
  rowInk      = '#1F2933'; lineInk   = '#8A94A6'
}
$ROUTINE_KINDS = @('method', 'procedure', 'function', 'constructor', 'destructor')
# Measured 2026-09-23 against the live Firebird DB, VALIDATION ONLY (P16).
$SCHEMA_NOTE = '5 live tables are not in the scripts (2026-09-23)'
$INV = [Globalization.CultureInfo]::InvariantCulture
function Format-N([int] $n) { $n.ToString('N0', $INV) }

Write-Host "lands-where: $Field"

# ---- 0. roles: each clone must be what its parameter says ---------------------------
$sqlSet = Get-SqlTableSet $SqlDbPath
if ($sqlSet.TableCount -eq 0) {
  throw "lands-where: $SqlDbPath is not a SQL index (0 sql_table symbols) -- -SqlDbPath takes the SQL-script clone"
}
function Get-DataServiceClassCount([string] $Db) {
  $DbPath = $Db
  $r = Invoke-IndexQuery "SELECT COUNT(*) AS n FROM symbols WHERE kind = 'class' AND name GLOB 'TDataService_*_SERVER'"
  [int]$r[0].n
}
function Get-SqlTableSymbolCount([string] $Db) {
  $DbPath = $Db
  $r = Invoke-IndexQuery "SELECT COUNT(*) AS n FROM symbols WHERE kind = 'sql_table'"
  [int]$r[0].n
}
if ((Get-SqlTableSymbolCount $DbPath) -gt 0 -or (Get-SqlTableSymbolCount $ServerDbPath) -gt 0) {
  throw 'lands-where: a SQL-script index was passed as a Delphi clone -- -DbPath takes CLIENT, -ServerDbPath SERVER, -SqlDbPath the scripts'
}
$nDsClasses = Get-DataServiceClassCount $ServerDbPath
if ($nDsClasses -eq 0) {
  throw ("lands-where: $ServerDbPath holds no TDataService_<T>_SERVER class -- -ServerDbPath takes the SERVER clone " +
         '(SERVER-MicroniteMW1Service.sqlite), where the write and read path live')
}
if ((Get-DataServiceClassCount $DbPath) -gt 0) {
  throw ("lands-where: $DbPath holds TDataService_<T>_SERVER classes, so it is a SERVER index -- -DbPath takes the CLIENT " +
         'clone (the ORM classes and the DFM bindings); the SERVER clone goes in -ServerDbPath')
}

# path B detector: orm_links on BOTH Delphi clones (0 today)
$olCli = Get-OrmLinksState $DbPath
$olSrv = Get-OrmLinksState $ServerDbPath

# ---- 1. the selection: ORM property / field, or <Form>.<Control> ----------------------
$sel = $Field.Trim()
if ($sel -notmatch '^[A-Za-z_][A-Za-z0-9_]*(\.[A-Za-z_][A-Za-z0-9_]*)+$') {
  throw "lands-where: -Field takes <Unit>.<Tmc class>.<property> or <Form>.<Control>, got '$Field'"
}
$NOT_ORM = 'not an ORM object property (class is not Tmc<T>) and not a DFM-bound field'
$symRows = Invoke-IndexQuery @"
SELECT s.id AS id, s.name AS name, s.kind AS kind, s.qualified_name AS q, s.start_line AS line, f.path AS path,
       p.id AS pid, p.name AS pname, p.kind AS pkind, p.heritage AS pher
  FROM symbols s JOIN files f ON f.id = s.file_id LEFT JOIN symbols p ON p.id = s.parent_id
 WHERE UPPER(s.qualified_name) = UPPER('$(ConvertTo-SqlText $sel)')
"@
$segs = $sel -split '\.'
$kind = ''; $selSym = $null
$ctl = $null; $bindRow = $null; $chain = $null
if ($symRows.Count) {
  $selSym = $symRows[0]
  if ([string]$selSym.kind -notin 'property', 'field') {
    throw "lands-where: $sel is a $($selSym.kind) -- $NOT_ORM. lands-where selects a property or field of a Tmc<T> / Imc<T> object."
  }
  if ([string]$selSym.pname -notmatch '^(Tmc|Imc)(.+)$' -or [string]$selSym.pkind -notin 'class', 'interface') {
    throw "lands-where: $sel is on $($selSym.pname) -- $NOT_ORM."
  }
  $kind = 'orm'
  # refuse BEFORE the index-wide work: the class name must name a table
  $tn0 = ([regex]::Match([string]$selSym.pname, '^(Tmc|Imc)(.+)$')).Groups[2].Value
  if (-not $sqlSet.Tables.ContainsKey($tn0)) {
    # the FIB$ tables: `$` is not legal in a Delphi identifier, so the class says `_`
    $alt = @($sqlSet.Names | Where-Object { $_.Replace('$', '_') -eq $tn0.ToUpperInvariant() })
    $declared = $(if ($alt.Count) { " (the scripts declare $($alt[0]))" } else { ' (script-derived; the scripts may lag the live schema)' })
    throw ("lands-where: no table named $tn0 in the SQL index$declared -- the name was derived from " +
           "$($selSym.pname) by the Tmc<T> / Imc<T> naming convention. $SCHEMA_NOTE.")
  }
} else {
  $forms = Invoke-IndexQuery @"
SELECT s.file_id AS fid, f.path AS path FROM symbols s JOIN files f ON f.id = s.file_id
 WHERE s.kind = 'form' AND UPPER(s.name) = UPPER('$(ConvertTo-SqlText $segs[0])')
"@
  if ($forms.Count -eq 0) {
    throw "lands-where: $sel resolves to no property or field in this index and $($segs[0]) is no form -- $NOT_ORM."
  }
  $cands = Invoke-IndexQuery @"
SELECT c.id AS id, c.name AS name, c.qualified_name AS q, c.signature AS sig, c.parent_id AS pid,
       c.start_line AS line, f.path AS path, p.name AS pname
  FROM symbols c JOIN files f ON f.id = c.file_id LEFT JOIN symbols p ON p.id = c.parent_id
 WHERE c.kind = 'component' AND c.file_id IN ($((@($forms | ForEach-Object { [int]$_.fid })) -join ','))
   AND UPPER(c.name) = UPPER('$(ConvertTo-SqlText $segs[-1])')
"@
  if ($segs.Count -gt 2) { $cands = @($cands | Where-Object { [string]::Equals([string]$_.q, $sel, [StringComparison]::OrdinalIgnoreCase) }) }
  if ($cands.Count -eq 0) { throw "lands-where: no component named $($segs[-1]) on $($segs[0]) -- $NOT_ORM." }
  if ($cands.Count -gt 1) {
    throw "lands-where: $sel names $($cands.Count) components ($(($cands | ForEach-Object { [string]$_.q }) -join ', ')) -- pass the full qualified name"
  }
  $ctl = $cands[0]
  $fbRows = Invoke-IndexQuery @"
SELECT owner_name AS prop, text AS col, start_line AS line FROM string_literals
 WHERE kind = 'dfm-prop' AND symbol_id = $([int]$ctl.id)
   AND owner_name IN ('DataBinding.FieldName','DataBinding.DataField','DataField','FieldName')
 ORDER BY start_line
"@
  if (@($fbRows | Where-Object { $_.prop -eq 'FieldName' }).Count -and -not @($fbRows | Where-Object { $_.prop -ne 'FieldName' }).Count) {
    throw ("lands-where: $([string]$ctl.q) is a persistent FIELD ($([string]$ctl.sig)) of the dataset $([string]$ctl.pname), not a " +
           'data-aware control -- its dataset is not a datasource chain. Ask lands-where of the ORM property, or of a control bound to that column.')
  }
  if (-not @($fbRows | Where-Object { $_.prop -ne 'FieldName' }).Count) {
    throw "lands-where: $([string]$ctl.q) ($([string]$ctl.sig)) binds no field in the DFM -- $NOT_ORM."
  }
  $kind = 'dfm'
}

# ---- 2. index-wide numbers, measured on this run (R10: never quoted) --------------------
$ix = Get-FieldBindingChains $sqlSet $SourceOverride
# Test-IsColumn / Get-SqlColumnState live in Emit-Common: ONE column test for
# consumers, feeds-from and lands-where (final wave, item 1).

# P35: Tmc properties / on a table-named class / extracted as a column of that table
$tmcProps = Get-AllIndexRows @"
SELECT p.id AS id, p.name AS pn, c.name AS cn
  FROM symbols p JOIN symbols c ON c.id = p.parent_id
 WHERE p.kind = 'property' AND c.kind = 'class' AND c.name GLOB 'Tmc*'
"@ 'p.id'
$convTable = @($tmcProps | Where-Object { $sqlSet.Tables.ContainsKey(([string]$_.cn).Substring(3)) })
$convCol = @($convTable | Where-Object { Test-IsColumn $sqlSet.Tables[([string]$_.cn).Substring(3)] ([string]$_.pn) })
$convNon = @($convTable | Where-Object { -not (Test-IsColumn $sqlSet.Tables[([string]$_.cn).Substring(3)] ([string]$_.pn)) })
# each non-extracted one through the SHARED state: quoted, or not scanned
# because its script is stale -- a stale scan is COUNTED and named, never
# dropped into "not a column" (final wave, item 5)
$convStates = @($convNon | ForEach-Object {
  $tn = ([string]$_.cn).Substring(3)
  [pscustomobject]@{ Name = "$tn.$($_.pn)"; State = (Get-SqlColumnState $sqlSet $tn ([string]$_.pn) $SourceOverride).State } })
$conv = [pscustomobject]@{
  Props = $tmcProps.Count; OnTable = $convTable.Count; Column = $convCol.Count
  NonColumn = (@($convNon | ForEach-Object { "$(([string]$_.cn).Substring(3)).$($_.pn)" } | Sort-Object) -join ',')
  Quoted = (@($convStates | Where-Object { $_.State -eq 'quoted' } | ForEach-Object { $_.Name } | Sort-Object) -join ',')
  Stale  = (@($convStates | Where-Object { $_.State -eq 'stale' }  | ForEach-Object { $_.Name } | Sort-Object) -join ',')
}
$nConvQuoted = @($convStates | Where-Object { $_.State -eq 'quoted' }).Count
$CONV_GRADE = "inferred -- naming convention, $(Format-N $conv.Column) of $(Format-N $conv.OnTable) properties on table-named classes are extracted as a column of that table" +
              $(if ($nConvQuoted) { " (+$nConvQuoted a QUOTED column the index does not extract)" } else { '' })
Write-Host ("  convention: {0} Tmc properties, {1} on a table-named class, {2} extracted as a column of it; not: {3}; quoted in the script: {4}; not scanned (stale): {5}" -f `
            $conv.Props, $conv.OnTable, $conv.Column, $conv.NonColumn, $(if ($conv.Quoted) { $conv.Quoted } else { 'none' }), $(if ($conv.Stale) { $conv.Stale } else { 'none' }))

# P36/P37 on the SERVER: DataService classes, and ParamByName literals inside them
function Get-ParamByNameStats {
  $DbPath = $ServerDbPath
  $rows = Get-AllIndexRows @"
SELECT sl.id AS id, sl.text AS txt, cls.name AS cls
  FROM string_literals sl
  JOIN refs r ON r.file_id = sl.file_id AND r.start_line = sl.start_line AND r.name_text = 'ParamByName'
             AND r.kind = 'call' AND sl.start_col = r.end_col + 1
  LEFT JOIN symbols e ON e.id = r.enclosing_symbol_id
  LEFT JOIN symbols cls ON cls.id = e.parent_id
"@ 'sl.id'
  $inDs = @($rows | Where-Object { [string]$_.cls -match '^TDataService_(.+)_SERVER$' })
  $col = @($inDs | Where-Object {
    $tn = ([regex]::Match([string]$_.cls, '^TDataService_(.+)_SERVER$')).Groups[1].Value
    $sqlSet.Tables.ContainsKey($tn) -and (Test-IsColumn $sqlSet.Tables[$tn] ([string]$_.txt)) })
  [pscustomobject]@{ All = $rows.Count; InDataService = $inDs.Count; Column = $col.Count }
}
$pbn = Get-ParamByNameStats
Write-Host ("  server: {0} TDataService_<T>_SERVER classes; ParamByName literals {1}, {2} inside a DataService routine, {3} a column of its table" -f `
            $nDsClasses, $pbn.All, $pbn.InDataService, $pbn.Column)

# ---- 3. resolve the selection to T and PROP ------------------------------------------
$selRows = New-Object System.Collections.ArrayList     # the top cluster's rows
$anchored = 0
function New-Row([string] $Label, [string] $File, [int] $Line, [string] $Tip, [string] $Note) {
  $script:anchored++
  [pscustomobject]@{ Label = $Label; Line = $Line; Href = New-RowHref $File $Line; Tip = $Tip; Note = $Note }
}

$TName = $null; $Prop = $null; $stop = ''; $chainOutcome = ''
$ormSym = $null                                         # the Tmc/Imc property drawn (either kind)
function Find-OrmProperty([string] $ClassName, [string] $Name) {
  $r = Invoke-IndexQuery @"
SELECT s.id AS id, s.name AS name, s.kind AS kind, s.qualified_name AS q, s.start_line AS line, f.path AS path,
       p.id AS pid, p.name AS pname, p.kind AS pkind, p.heritage AS pher
  FROM symbols s JOIN files f ON f.id = s.file_id JOIN symbols p ON p.id = s.parent_id
 WHERE s.kind = 'property' AND UPPER(p.name) = UPPER('$(ConvertTo-SqlText $ClassName)') AND p.kind IN ('class','interface')
   AND UPPER(s.name) = UPPER('$(ConvertTo-SqlText $Name)')
"@
  $(if ($r.Count) { $r[0] } else { $null })
}

if ($kind -eq 'orm') {
  $TName = ([regex]::Match([string]$selSym.pname, '^(Tmc|Imc)(.+)$')).Groups[2].Value
  if ([string]$selSym.kind -eq 'field') {
    # a backing field `fREASON` -> its property REASON, by the f<PROP> naming
    $pn = ([string]$selSym.name) -replace '^[fF]', ''
    $ormSym = Find-OrmProperty ([string]$selSym.pname) $pn
    if (-not $ormSym) { throw "lands-where: $sel is a field of $($selSym.pname) with no property named $pn -- select the property itself" }
    [void]$selRows.Add((New-Row "$($selSym.name) : field" ([string]$selSym.path) ([int]$selSym.line) "$($selSym.q) -- $([IO.Path]::GetFileName([string]$selSym.path)):$($selSym.line)" "[by name] backing field of $pn (f<PROP>)"))
  } else {
    $ormSym = $selSym
  }
  $Prop = [string]$ormSym.name
} else {
  $b = @($ix.Bindings | Where-Object { $_.ControlId -eq [int]$ctl.id } | Sort-Object Line | Select-Object -First 1)
  if (-not $b.Count) { throw "lands-where: $([string]$ctl.q) is not in the field-binding population (no DataBinding.FieldName / DataField) -- $NOT_ORM." }
  $bindRow = $b[0]
  $chainOutcome = $bindRow.Outcome
  if ($bindRow.Ds) { $chain = $ix.Chains[(Get-ChainKey $bindRow.Dfm $bindRow.Ds)] }
  [void]$selRows.Add((New-Row "$($ctl.name) : $($ctl.sig)" $bindRow.Dfm $bindRow.Line "$($ctl.q).$($bindRow.Prop) = '$($bindRow.Column)' -- $([IO.Path]::GetFileName($bindRow.Dfm)):$($bindRow.Line)" "$($bindRow.Prop) = $($bindRow.Column)"))
  if ($chain) {
    foreach ($h in $chain.Hops) {
      $lbl = "[$($h.Grade)] $($h.Hop): $($h.Label)"
      if ($h.Line -gt 0 -and $h.File) {
        [void]$selRows.Add((New-Row $lbl $h.File ([int]$h.Line) "$($h.Label) -- $([IO.Path]::GetFileName($h.File)):$($h.Line)" $h.Reason))
      } else { [void]$selRows.Add((New-NoteRow "$lbl -- $($h.Reason)")) }
    }
  }
  switch ($chainOutcome) {
    'column'     { $TName = $bindRow.Table; $Prop = $bindRow.Column }
    'not-column' { $TName = $bindRow.Table; $Prop = $bindRow.Column }
    'no-ds'      { $stop = "no DataSource on $($ctl.name) or its two enclosing components in the DFM -- the chain cannot start" }
    'dangling'   { $stop = "the designer datasource $($bindRow.Ds) is dangling ($($chain.StopReason)) -- no table" }
    # stale with a table: the chain resolved, but the table's script is stale, so
    # the column's state is unknown -- step 4 says so ([stale source])
    'stale'      { if ($bindRow.Table) { $TName = $bindRow.Table; $Prop = $bindRow.Column } else { $stop = "[stale source] $($chain.StopReason)" } }
    default      { $stop = "the chain stops before a table ($($chain.Grade)): $($chain.StopReason)" }
  }
  if ($TName) { $ormSym = Find-OrmProperty "Tmc$TName" $Prop }
}

# ---- 4. the table and the column --------------------------------------------------------
$tbl = $null; $colState = 'n/a'; $colRow = $null; $cs = $null
if ($TName) {
  # (an ORM selection was checked in step 1; a DFM chain only resolves to a table of the set)
  $tbl = $sqlSet.Tables[$TName]
  $TName = $tbl.Name
  # the SHARED state (Emit-Common); `no` / `stale` are looked at again after the
  # server step, whose own SQL for T may name the column (server-sql)
  $cs = Get-SqlColumnState $sqlSet $TName $Prop $SourceOverride
  $colState = $cs.State
}
Write-Host ("  selection: {0} ({1}); table {2}; column {3}" -f $sel, $kind, $(if ($TName) { $TName } else { '(none)' }), $colState)
$hasColumn = [bool]($cs -and $cs.IsColumn)
$COL = $(if ($Prop) { $Prop.ToUpperInvariant() } else { '' })

# ---- 5. the server write / read path -------------------------------------------------------
$srvRows = @{ write = New-Object System.Collections.ArrayList; read = New-Object System.Collections.ArrayList; other = New-Object System.Collections.ArrayList }
$srvClass = $null; $srvImp = $null; $srvElsewhere = 0; $srvFile = $null; $srvSqlHit = $null
function Get-WordRx([string] $Name) { "(?<![A-Za-z0-9_$])$([regex]::Escape($Name))(?![A-Za-z0-9_$])" }
if ($TName) {
  $srv = & {
    $DbPath = $ServerDbPath
    $cls = Invoke-IndexQuery @"
SELECT c.id AS id, c.name AS name, f.path AS path, c.file_id AS fid FROM symbols c JOIN files f ON f.id = c.file_id
 WHERE c.kind = 'class' AND UPPER(c.name) = UPPER('TDataService_$(ConvertTo-SqlText $TName)_SERVER')
"@
    $imp = Invoke-IndexQuery @"
SELECT s.id AS id, s.qualified_name AS q FROM symbols s JOIN symbols p ON p.id = s.parent_id
 WHERE s.kind = 'property' AND p.kind = 'interface' AND UPPER(p.name) = UPPER('Imc$(ConvertTo-SqlText $TName)')
   AND UPPER(s.name) = UPPER('$(ConvertTo-SqlText $Prop)')
"@
    $rts = @(); $acc = @(); $pbnRows = @(); $lits = @(); $other = 0
    if ($cls.Count) {
      $rts = Invoke-IndexQuery @"
SELECT s.id AS id, s.name AS name, s.qualified_name AS q, s.impl_start_line AS a, s.impl_end_line AS b
  FROM symbols s WHERE s.parent_id = $([int]$cls[0].id) AND s.impl_start_line > 0 AND s.kind IN ($(ConvertTo-SqlInList $ROUTINE_KINDS))
"@
      $ids = @($rts | ForEach-Object { [int]$_.id })
      if ($ids.Count) {
        if ($imp.Count) {
          $acc = Invoke-IndexQuery @"
SELECT r.start_line AS line, r.enclosing_symbol_id AS eid, ma.mode AS mode, r.receiver_text AS rt
  FROM refs r JOIN member_accesses ma ON ma.ref_id = r.id
 WHERE ma.member_symbol_id = $([int]$imp[0].id) AND r.enclosing_symbol_id IN ($($ids -join ','))
 ORDER BY r.start_line
"@ 'lands-where (member accesses)'
          $o = Invoke-IndexQuery @"
SELECT COUNT(*) AS n FROM refs r JOIN member_accesses ma ON ma.ref_id = r.id
 WHERE ma.member_symbol_id = $([int]$imp[0].id) AND (r.enclosing_symbol_id IS NULL OR r.enclosing_symbol_id NOT IN ($($ids -join ',')))
"@
          $other = [int]$o[0].n
        }
        if ($Prop) {
          $pbnRows = Invoke-IndexQuery @"
SELECT sl.start_line AS line, r.enclosing_symbol_id AS eid, sl.text AS txt
  FROM string_literals sl JOIN refs r ON r.file_id = sl.file_id AND r.start_line = sl.start_line AND r.name_text = 'ParamByName'
                                     AND r.kind = 'call' AND sl.start_col = r.end_col + 1
 WHERE r.enclosing_symbol_id IN ($($ids -join ',')) AND UPPER(sl.text) = UPPER('$(ConvertTo-SqlText $Prop)')
 ORDER BY sl.start_line
"@
          $lits = Get-AllIndexRows @"
SELECT sl.id AS id, sl.start_line AS line, sl.text AS txt FROM string_literals sl
 WHERE sl.file_id = $([int]$cls[0].fid) AND sl.kind IN ('literal','format','const')
"@ 'sl.start_line, sl.id'
        }
      }
    }
    [pscustomobject]@{ Cls = $cls; Imp = $imp; Routines = $rts; Acc = $acc; Pbn = $pbnRows; Lits = $lits; Other = $other }
  }
  if ($srv.Cls.Count) { $srvClass = [string]$srv.Cls[0].name; $srvFile = [string]$srv.Cls[0].path }
  if ($srv.Imp.Count) { $srvImp = [string]$srv.Imp[0].q }
  $srvElsewhere = $srv.Other
  $wordRx = $(if ($COL) { Get-WordRx $COL } else { $null })
  foreach ($rt in @($srv.Routines | Sort-Object { [int]$_.a })) {
    $ev = New-Object System.Collections.ArrayList
    foreach ($a in @($srv.Acc | Where-Object { [int]$_.eid -eq [int]$rt.id })) {
      [void]$ev.Add([pscustomobject]@{ Line = [int]$a.line; Grade = 'certain'; Text = "$(if ($a.rt) { "$($a.rt)." })$Prop $($a.mode)" })
    }
    foreach ($p in @($srv.Pbn | Where-Object { [int]$_.eid -eq [int]$rt.id })) {
      [void]$ev.Add([pscustomobject]@{ Line = [int]$p.line; Grade = 'inferred'; Text = "ParamByName('$($p.txt)')" })
    }
    if ($rt.a -and $rt.b) {
      $span = @($srv.Lits | Where-Object { [int]$_.line -ge [int]$rt.a -and [int]$_.line -le [int]$rt.b })
      $namesT = @($span | Where-Object { @((Get-SqlVerbTables ([string]$_.txt) $sqlSet) | Where-Object { $_.Kind -eq 'table' -and $_.Name -eq $TName }).Count })
      if ($namesT.Count) {
        $hit = @($span | Where-Object { [regex]::IsMatch([string]$_.txt, $wordRx) } | Select-Object -First 1)
        if ($hit.Count) {
          [void]$ev.Add([pscustomobject]@{ Line = [int]$hit[0].line; Grade = 'inferred'; Text = "SQL literal names $COL" })
          if (-not $srvSqlHit) { $srvSqlHit = [pscustomobject]@{ Line = [int]$hit[0].line; Routine = [string]$rt.q } }
        }
      }
    }
    if (-not $ev.Count) { continue }
    $first = @($ev | Sort-Object Line)[0]
    $grade = $(if (@($ev | Where-Object { $_.Grade -eq 'certain' }).Count) { 'certain' } else { 'inferred' })
    $evText = (@($ev | Sort-Object Line | ForEach-Object { "$($_.Text) :$($_.Line)" }) -join '; ')
    $side = $(if ([string]$rt.name -match '(?i)save') { 'write' } elseif ([string]$rt.name -match '(?i)load') { 'read' } else { 'other' })
    [void]$srvRows[$side].Add((New-Row ([string]$rt.name) $srvFile $first.Line "$($rt.q) -- $evText" "[$grade] $evText"))
  }
}
$srvCount = $srvRows.write.Count + $srvRows.read.Count + $srvRows.other.Count
# NOT IN THE SCRIPTS IS NOT "NOT A COLUMN" (FINDING 2026-09-23): STATIONS.GRIDS and
# .MENUS are absent from every script declaration, yet uSTATIONS_SERVER.PAS:129
# writes them (`UPDATE OR INSERT INTO STATIONS (... GRIDS ... MENUS ...)`) and
# :110-111 read them -- the scripts lag the live schema. So "computed or UI-only"
# is said ONLY when the server's own SQL for T does not name the column either;
# otherwise the column row anchors on that SQL literal, [inferred]. The decision
# and its label are the SHARED Get-SqlColumnState's (consumers makes the same one).
if ($colState -in 'no', 'stale') {
  # the routine named as consumers names it (unit-less short name), so the
  # shared label reads the same in both verbs
  $hit = $(if ($srvSqlHit) { [pscustomobject]@{ File = $srvFile; Line = $srvSqlHit.Line; Routine = (Get-ShortName $srvSqlHit.Routine (Get-UnitName $srvFile)) } } else { $null })
  $cs = Get-SqlColumnState $sqlSet $TName $Prop $SourceOverride -ServerSqlHit $hit `
          -SqlSearched $(if ($srvClass) { "the server's $srvClass" } else { '' })
  $colState = $cs.State
  $hasColumn = $cs.IsColumn
}
if ($cs -and $cs.IsColumn) {
  $cLabel = $(if ($colState -eq 'quoted') { "$TName.`"$COL`"" } else { "$TName.$COL" })
  $cTip = $(switch ($colState) {
      'quoted'     { $cs.Text }
      'server-sql' { "$($srvSqlHit.Routine) names $COL in its SQL for $TName" }
      default      { "$TName.$COL" } })
  $colRow = New-Row $cLabel $cs.File $cs.Line "$cTip -- $([IO.Path]::GetFileName($cs.File)):$($cs.Line)" $cs.Label
}

Write-Host ("  server: {0}; {1} write / {2} read / {3} other routine row(s); {4} access(es) to {5} outside it" -f `
            $(if ($srvClass) { $srvClass } else { '(no DataService class)' }), $srvRows.write.Count, $srvRows.read.Count, $srvRows.other.Count, $srvElsewhere,
            $(if ($srvImp) { $srvImp } else { "Imc$TName.$Prop" }))

# ---- 6. the database side: triggers and procedures -------------------------------------------
$trigRows = New-Object System.Collections.ArrayList; $procRows = New-Object System.Collections.ArrayList
$trigNames = @(); $procNames = @(); $trigStale = 0; $procUnscanned = 0
# a column whose state is unknown ([stale source]) is still looked up by name on
# the database side: a trigger naming NEW.<COL> is evidence either way
if ($TName -and ($hasColumn -or $colState -eq 'stale')) {
  $trigSet = Get-SqlTriggerSet $SqlDbPath $SourceOverride
  $forT = @($trigSet.Triggers | Where-Object { $_.Table -eq $TName } | Sort-Object Name)
  $trigStale = @($forT | Where-Object { $_.Stale }).Count
  $hitT = @($forT | Where-Object { $_.Columns -contains $COL })
  $trigNames = @($hitT | ForEach-Object { "$($_.Name)@$([IO.Path]::GetFileName($_.File)):$($_.Line)" })
  foreach ($x in $hitT) {
    [void]$trigRows.Add((New-Row $x.Name $x.File $x.Line "$($x.Name) FOR ${TName}: NEW./OLD.$COL in its body -- $([IO.Path]::GetFileName($x.File)):$($x.Line)" "NEW/OLD.$COL"))
  }
  $procSet = Get-SqlProcedureSet $SqlDbPath $SourceOverride
  $procUnscanned = @($procSet.Declarations | Where-Object { -not $_.Found }).Count
  $wordRx2 = Get-WordRx $COL
  foreach ($g in @($procSet.Declarations | Group-Object { $_.Name.ToUpperInvariant() } | Sort-Object Name)) {
    $d = @($g.Group | Where-Object { $_.Found -and ($_.Tables -contains $TName) -and [regex]::IsMatch([string]$_.Text, $wordRx2) } | Sort-Object Line | Select-Object -First 1)
    if ($d.Count) {
      $procNames += $d[0].Name
      [void]$procRows.Add((New-Row $d[0].Name $d[0].File $d[0].Line "$($d[0].Name): body names $TName and $COL -- $([IO.Path]::GetFileName($d[0].File)):$($d[0].Line)" '[inferred] body scan'))
    }
  }
}
Write-Host ("  database: {0} trigger(s) FOR {1} touching {2} ({3} stale); {4} procedure(s)" -f $trigRows.Count, $TName, $COL, $trigStale, $procRows.Count)

# ---- 7. the client side: field-bound controls, the REVERSE of feeds-from -------------------
$bindSame = @(); $bindOther = @()
if ($COL) {
  $bindAll = @($ix.Bindings | Where-Object { [string]::Equals([string]$_.Column, $COL, [StringComparison]::OrdinalIgnoreCase) })
  $bindSame = @($bindAll | Where-Object { $_.Table -and [string]::Equals([string]$_.Table, [string]$TName, [StringComparison]::OrdinalIgnoreCase) })
  $bindOther = @($bindAll | Where-Object { -not ($_.Table -and [string]::Equals([string]$_.Table, [string]$TName, [StringComparison]::OrdinalIgnoreCase)) })
}
$bindRowsOut = @($bindSame | Sort-Object Dfm, Line | ForEach-Object {
  New-Row "$(Get-UnitName $_.Dfm).$($_.Control)" $_.Dfm $_.Line "$($_.Control).$($_.Prop) = '$($_.Column)' via $($_.Ds) -> $TName -- $([IO.Path]::GetFileName($_.Dfm)):$($_.Line)" "$($_.Ds)$(if ($_.Outcome -eq 'not-column') { '; not extracted as a column' } elseif ($_.Outcome -eq 'stale') { '; [stale source]' })" })
Write-Host ("  client: {0} field-bound control(s) resolve to {1} with {2}; {3} other binding(s) of {2} counted" -f $bindSame.Count, $TName, $COL, $bindOther.Count)

# ---- 8. dot ------------------------------------------------------------------------------------
$sb = New-Object System.Text.StringBuilder
[void]$sb.AppendLine('digraph landswhere {')
[void]$sb.AppendLine('  rankdir=TB; bgcolor="transparent"; compound=true;')
[void]$sb.AppendLine('  nodesep=0.5; ranksep=0.6; splines=spline;')
[void]$sb.AppendLine("  graph [fontname=`"$FontSans`"];")
[void]$sb.AppendLine("  node  [shape=plaintext, fontname=`"$FontMono`", fontsize=14];")
[void]$sb.AppendLine("  edge  [fontname=`"$FontMono`", fontsize=11, color=`"$($PAL.lineInk)`", penwidth=1.4, arrowsize=0.7];")
[void]$sb.AppendLine('')
$ni = 0
function Add-Box([string] $Title, [string] $Sub, $Rows, [string] $Kind, [bool] $Dashed) {
  $all = @($Rows | Where-Object { $null -ne $_ })
  $top = Get-TopRanked $all $Cap
  $shown = New-Object System.Collections.ArrayList
  foreach ($r in $top.Shown) { [void]$shown.Add($r) }
  $script:anchored -= @($all | Select-Object -Skip $Cap | Where-Object { $_.Href }).Count
  $d = Get-DisclosureText $top.HiddenRows 0 'rows'
  if ($d) { [void]$shown.Add((New-NoteRow $d)) }
  $script:ni++
  $nid = "n$($script:ni)"
  [void](Add-RowCluster -Sb $sb -Cid "cluster_${Kind}_$($script:ni)" -Nid $nid -Title $Title -Subtitle $Sub -Rows $shown.ToArray() `
           -Border $PAL["${Kind}Border"] -Fill $PAL["${Kind}Fill"] -Hdr $PAL["${Kind}Hdr"] -RowInk $PAL.rowInk -LineInk $PAL.lineInk `
           -FontSans $FontSans -Style $(if ($Dashed) { 'rounded,filled,dashed' } else { 'rounded,filled' }))
  $nid
}
function Add-Edge([string] $From, [string] $To, [string] $Label, [bool] $Dashed, [switch] $Back, [string] $Color) {
  $st = $(if ($Dashed) { 'dashed' } else { 'solid' })
  $c = $(if ($Color) { $Color } else { $PAL.lineInk })
  [void]$sb.AppendLine("  $From -> $To [style=$st, color=`"$c`", label=`" $(ConvertTo-XmlText $Label) `"$(if ($Back) { ', dir=back' })];")
}

# -- top: the selection ---------------------------------------------------------------------------
$nTop = $null; $nProp = $null
if ($kind -eq 'dfm') {
  $nTop = Add-Box "control $($ctl.name)" "$($selRows.Count - 1) chain hop(s)" $selRows.ToArray() 'ctl' $false
}
if ($ormSym) {
  $pRows = New-Object System.Collections.ArrayList
  if ($kind -eq 'orm') { foreach ($r in $selRows) { [void]$pRows.Add($r) } }
  $imps = $(if ([string]$ormSym.pkind -eq 'interface') { 'the interface the server reads' }
            elseif ([string]$ormSym.pher -match "(^|[\s,<])Imc$([regex]::Escape($TName))(\s*,|\s*$|>)") { "implements Imc$TName (heritage)" }
            else { "Imc$TName not in its heritage" })
  [void]$pRows.Add((New-Row "$($ormSym.name) : property of $($ormSym.pname)" ([string]$ormSym.path) ([int]$ormSym.line) "$($ormSym.q) -- $([IO.Path]::GetFileName([string]$ormSym.path)):$($ormSym.line)" $imps))
  $pSub = $(if ($kind -eq 'dfm') { 'inferred -- naming convention Tmc<T>.<COL>' } else { 'certain' })
  $nProp = Add-Box 'ORM property' $pSub $pRows.ToArray() 'prop' ($kind -eq 'dfm')
  if ($nTop) { Add-Edge $nTop $nProp '[inferred] Tmc<T>.<COL>' $true }
}

# -- the table / column ----------------------------------------------------------------------------
$nCol = $null
if ($TName) {
  $cRows = New-Object System.Collections.ArrayList
  [void]$cRows.Add((New-Row "table $TName" $tbl.File $tbl.Line "$TName -- $([IO.Path]::GetFileName($tbl.File)):$($tbl.Line)" "$(if ($kind -eq 'orm') { "from $($ormSym.pname) by the naming convention" } else { 'where the chain resolved' }); newest of $($tbl.DeclCount) declaration(s)"))
  if ($colRow) { [void]$cRows.Add($colRow) }
  # R11: a stale scan is NOT an absence -- never "computed or UI-only" (final wave, item 5)
  elseif ($colState -eq 'stale') { [void]$cRows.Add((New-NoteRow "${Prop}: $($cs.Label)")) }
  else { [void]$cRows.Add((New-NoteRow "$Prop is not a column of $TName -- computed or UI-only: $($cs.Label); the database side is empty")) }
  $cTitle = $(if ($hasColumn) { "$TName.$COL" } elseif ($colState -eq 'stale') { "$TName.$COL [stale source]" } else { "$TName (no column $Prop)" })
  $nCol = Add-Box $cTitle $CONV_GRADE $cRows.ToArray() 'db' $true
} elseif ($stop) {
  $nCol = Add-Box 'chain stops here' '' @((New-NoteRow $stop)) 'stop' $false
}

# -- server clusters ----------------------------------------------------------------------------
$nW = $null; $nR = $null; $nO = $null
$srvSub = $(if ($srvClass) { "$srvClass [by name]" } else { '' })
if ($srvRows.write.Count) { $nW = Add-Box 'server write path' $srvSub $srvRows.write.ToArray() 'write' $false }
if ($srvRows.read.Count)  { $nR = Add-Box 'server read path'  $srvSub $srvRows.read.ToArray()  'read'  $false }
if ($srvRows.other.Count) { $nO = Add-Box 'other DataService routines' $srvSub $srvRows.other.ToArray() 'stop' $false }
$srcNode = $(if ($nProp) { $nProp } else { $nTop })
foreach ($pair in @(@($nW, $PAL.writeBorder, 'write'), @($nR, $PAL.readBorder, 'read'), @($nO, $PAL.stopBorder, 'other'))) {
  if (-not $pair[0]) { continue }
  $isRead = ($pair[2] -eq 'read')
  if ($srcNode) { Add-Edge $srcNode $pair[0] "Obj.$Prop" $false -Back:$isRead -Color $pair[1] }
  if ($nCol) { Add-Edge $pair[0] $nCol $(if ($hasColumn) { '[inferred] SQL names it' } else { '' }) $true -Back:$isRead -Color $pair[1] }
}
if ($srcNode -and $nCol -and -not ($nW -or $nR -or $nO)) { Add-Edge $srcNode $nCol $(if ($kind -eq 'dfm' -and -not $nProp) { '[inferred] chain' } else { '[inferred] naming convention' }) $true }
if ($nTop -and $nProp -and $nCol) { [void]$sb.AppendLine("  $nTop -> $nCol [style=invis];") }

# -- database side ------------------------------------------------------------------------------
if ($trigRows.Count) {
  $nT = Add-Box "triggers FOR $TName using $COL" "$($trigRows.Count) row(s)" $trigRows.ToArray() 'db' $false
  Add-Edge $nCol $nT 'NEW./OLD.' $false -Color $PAL.dbBorder
}
if ($procRows.Count) {
  $nP = Add-Box "procedures naming $TName and $COL" "$($procRows.Count) row(s) [inferred]" $procRows.ToArray() 'db' $true
  Add-Edge $nCol $nP 'body scan' $true -Color $PAL.dbBorder
}

# -- client side cluster ---------------------------------------------------------------------------
if ($COL -and $TName) {
  $cx = New-Object System.Collections.ArrayList
  foreach ($r in $bindRowsOut) { [void]$cx.Add($r) }
  $byT = @{}; $byO = @{}
  foreach ($b in $bindOther) { if ($b.Table) { $byT[$b.Table] = 1 + [int]$byT[$b.Table] } else { $byO[$b.Outcome] = 1 + [int]$byO[$b.Outcome] } }
  $extra = New-Object System.Collections.ArrayList
  if ($byT.Count) { [void]$extra.Add("$(@($byT.Values | Measure-Object -Sum).Sum) more bound to $COL on a chain resolving to another table ($(@($byT.Keys | Sort-Object | ForEach-Object { "$_ $($byT[$_])" }) -join ', '))") }
  if ($byO.Count) { [void]$extra.Add("$(@($byO.Values | Measure-Object -Sum).Sum) more whose chain does not reach a table ($(@($byO.Keys | Sort-Object | ForEach-Object { "$_ $($byO[$_])" }) -join ', '))") }
  if ($cx.Count -or $extra.Count) {
    if (-not $cx.Count) { [void]$cx.Add((New-NoteRow "no field-bound control in this index resolves to $TName.$COL")) }
    $nB = Add-Box 'client: controls bound to it' "$($bindSame.Count) resolve to $TName [inferred]" $cx.ToArray() 'ctl' $true
    if ($extra.Count) {
      $script:ni++
      $xn = "n$($script:ni)"
      [void](Add-RowCluster -Sb $sb -Cid "cluster_ctlx_$($script:ni)" -Nid $xn -Title 'other bindings of this name' -Subtitle 'counted, not drawn' `
               -Rows @($extra | ForEach-Object { New-NoteRow $_ }) -Border $PAL.stopBorder -Fill $PAL.stopFill -Hdr $PAL.stopHdr `
               -RowInk $PAL.rowInk -LineInk $PAL.lineInk -FontSans $FontSans)
      [void]$sb.AppendLine("  $nB -> $xn [style=invis];")
    }
    if ($nCol) { Add-Edge $nB $nCol '[inferred] chain resolves here' $true -Color $PAL.ctlBorder }
  }
}

# -- the focus box: what was asked, and what the chart can and cannot see ---------------------------
$script:ni++
$fnid = "n$($script:ni)"
$ftbl = New-Object System.Text.StringBuilder
[void]$ftbl.Append('<TABLE BORDER="0" CELLBORDER="0" CELLSPACING="3" CELLPADDING="5">')
[void]$ftbl.Append("<TR><TD ALIGN=`"LEFT`" BGCOLOR=`"$($PAL.focusHdr)`"><FONT COLOR=`"#FFFFFF`" FACE=`"$FontSans`" POINT-SIZE=`"14`"><B> lands-where &#183; $(ConvertTo-XmlText $sel) </B></FONT></TD></TR>")
Add-DisclosureRow $ftbl "table by naming convention (Tmc<T>): $(Format-N $conv.Column) of $(Format-N $conv.Props) Tmc properties in this index are a column of their class's table" $PAL.lineInk
Add-DisclosureRow $ftbl ("($(Format-N $conv.OnTable) sit on a table-named class; $($conv.OnTable - $conv.Column) are not extracted as a column by the SQL index" +
                         "$(if ($conv.Quoted) { "; of those, $($conv.Quoted) is a QUOTED column the index does not extract" })" +
                         "$(if ($conv.Stale) { "; not scanned for a quoted identifier [stale source]: $($conv.Stale)" }))") $PAL.lineInk
if ($kind -eq 'dfm') {
  $oc2 = @{}; foreach ($b in $ix.Bindings) { $oc2[$b.Outcome] = 1 + [int]$oc2[$b.Outcome] }
  Add-DisclosureRow $ftbl ("DFM-field selection: the feeds-from chain ($([int]$oc2['column']) of $($ix.Bindings.Count) field-bound controls reach a column of one table; " +
                           "outcome here: $chainOutcome)") $PAL.lineInk
}
Add-DisclosureRow $ftbl ("server: $(if ($srvClass) { "$srvClass (found by name; $nDsClasses DataService classes)" } else { "no TDataService_${TName}_SERVER in the SERVER index" }); " +
                         "member accesses resolved to Imc$TName.$Prop are [certain], SQL / ParamByName literals [inferred]" +
                         $(if ($srvElsewhere) { "; $srvElsewhere access(es) to it outside the DataService not drawn" } else { '' })) $PAL.lineInk
Add-DisclosureRow $ftbl 'positional Fields[i] / Params[i] reads are not shown -- they never name the column' $PAL.lineInk
Add-DisclosureRow $ftbl "script-derived schema: $($sqlSet.TableCount) tables; $SCHEMA_NOTE" $PAL.lineInk
if ($trigStale) { Add-DisclosureRow $ftbl "$trigStale trigger(s) FOR $TName in a script that differs from the index [stale source] -- not scanned" $PAL.lineInk }
if ($procUnscanned) { Add-DisclosureRow $ftbl "$procUnscanned procedure bodies not scanned" $PAL.lineInk }
$route = "route: derived (path A) -- orm_links rows: $($olCli.Rows) on $([IO.Path]::GetFileName($DbPath)), $($olSrv.Rows) on $([IO.Path]::GetFileName($ServerDbPath))"
if ($olCli.Rows -or $olSrv.Rows) { $route += ' -- the engine HAS links now; this chart does not read them yet (path B awaits the owner)' }
Add-DisclosureRow $ftbl $route $PAL.lineInk
[void]$ftbl.Append('</TABLE>')
[void]$sb.AppendLine("  subgraph cluster_focus_$($script:ni) {")
[void]$sb.AppendLine("    style=`"rounded,filled`"; color=`"$($PAL.focusBorder)`"; fillcolor=`"$($PAL.focusFill)`"; penwidth=2;")
[void]$sb.AppendLine('    label=""; margin=10;')
[void]$sb.AppendLine("    $fnid [label=<$($ftbl.ToString())>];")
[void]$sb.AppendLine('  }')
$first = $(if ($nTop) { $nTop } elseif ($nProp) { $nProp } else { $nCol })
if ($first) { [void]$sb.AppendLine("  $fnid -> $first [style=invis];") }
[void]$sb.AppendLine('}')

if ([string]::IsNullOrWhiteSpace($OutDir)) { $OutDir = Join-Path $PSScriptRoot '..\scratch' }
$lay = Invoke-DotLayout $sb.ToString() $OutDir ('landswhere_' + ($sel -replace '[^A-Za-z0-9]', '_'))

function Get-RowAnchors($List) { (@($List | Where-Object { $_.Href } | ForEach-Object { "$($_.Label):$($_.Line)" }) -join ',') }
[pscustomobject]@{
  Dot            = $lay.Dot
  Svg            = $lay.Svg
  Plain          = $lay.Plain
  Png            = $lay.Png
  Pdf            = $lay.Pdf
  Selection      = $sel
  Kind           = $kind
  Property       = $(if ($ormSym) { [string]$ormSym.q } else { '' })
  Table          = $TName
  TableColumn    = $(if ($hasColumn) { "$TName.$COL" } else { '' })
  ColumnState    = $colState
  ChainOutcome   = $chainOutcome
  StopReason     = $stop
  ServerClass    = $srvClass
  ServerRows     = $srvCount
  ServerWrite    = (Get-RowAnchors $srvRows.write)
  ServerRead     = (Get-RowAnchors $srvRows.read)
  ServerOther    = (Get-RowAnchors $srvRows.other)
  ServerElsewhere = $srvElsewhere
  Triggers       = $trigRows.Count
  TriggerNames   = ($trigNames -join ',')
  TriggersStale  = $trigStale
  Procedures     = $procRows.Count
  ProcedureNames = ($procNames -join ',')
  ClientBindings = $bindSame.Count
  ClientRows     = (@($bindSame | ForEach-Object { "$([IO.Path]::GetFileName($_.Dfm)):$($_.Line):$($_.Control)" }) -join ',')
  ClientOther    = $bindOther.Count
  ConvProps      = $conv.Props
  ConvOnTable    = $conv.OnTable
  ConvColumn     = $conv.Column
  ConvNonColumn  = $conv.NonColumn
  ConvQuoted     = $conv.Quoted
  ConvStale      = $conv.Stale
  ColumnLabel    = $(if ($cs) { $cs.Label } else { '' })
  DsClasses      = $nDsClasses
  ParamByNameAll = $pbn.All
  ParamByNameDs  = $pbn.InDataService
  ParamByNameCol = $pbn.Column
  OrmLinksCli    = $olCli.Rows
  OrmLinksSrv    = $olSrv.Rows
  ClickTargets   = $lay.Anchors
  Expected       = $anchored
  AllClickable   = ($lay.Anchors -ge $anchored)
}
