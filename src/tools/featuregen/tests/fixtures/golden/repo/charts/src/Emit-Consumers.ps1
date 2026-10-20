<#
  Emit-Consumers.ps1 -- the `consumers` question: who reads and who writes this
  database TABLE, or this COLUMN, and what does the database itself hang on it
  (triggers, procedures, indexes)?

  TWO INDEXES, NEITHER OF THEM THE DATABASE
  ------------------------------------------
  -DbPath is a Delphi project index (the SERVER index answers the SQL half, the
  CLIENT index the by-name and data-binding half); -SqlDbPath is the index of
  the Firebird .SQL SCRIPTS. Both go through Get-CloneDb. Neither is the live
  schema, and the chart says so on its focus box:

    * The SQL index is HISTORY (P15/R6). 252 table declarations are 135 names;
      117 names are declared twice. Get-SqlTableSet collapses them onto the
      declaration in the NEWEST script (ruling R8) and the chart prints how many
      declarations were collapsed. Whether a selected COLUMN exists is decided
      by Get-SqlColumnState (Emit-Common) -- the ONE column test lands-where and
      feeds-from use too: extracted from the newest declaration; a QUOTED
      identifier the index does not extract (none since extractor 1.19 fixed
      engine D19 -- FOLDERCOUNT."TABLE" and IPCHART."ACTION" are extracted now;
      the state stays as a guard); extracted only from an OLDER declaration; or
      named by this index's own SQL for T (server-sql). Only when none holds
      is it refused, worded "not extracted as a column by the SQL index" -- and
      a stale script refuses as "not known", never as an absence.
    * 5 live tables (PDF_SCAN, PDF_SCAN_CHUNK, PDF_SCAN_ITEM, PDF_BALLOON,
      PDF_SCAN_REGION) were never scripted, and OPERATION is scripted but
      dropped live (P16, measured 2026-09-23 against the live DB for
      VALIDATION ONLY -- this emitter never opens it). So a refusal says
      "the scripts may lag the live schema", and a render says the schema is
      script-derived.

  THE FACT IS [certain], THE LITERAL IS [inferred] -- AND BOTH COUNTS SHOW (R7)
  ----------------------------------------------------------------------------
  symbol_facts.sql_reads / sql_writes are the engine's table facts. On the 1.18
  clone they were 19 read and 148 write rows on SERVER, and the read side was 14
  tables wide where the literals name 133 (P22): `SQL.Add('SELECT ...');
  SQL.Add('FROM CAUSFAIL')` produced no fact at all (engine D18,
  INBOX-sql-reads-misses-multiline-sql-add.md). Extractor 1.19 fixed D18: 112
  read rows (+93, every one a DataService PrepareLoadQuery), 104 tables. The
  fact is still not the whole story -- 3 routines read FOLDERS by literal only
  -- and a reads chart built on the fact alone would be the "smaller confident
  answer" this project exists to prevent, so:

    [certain]   a routine whose fact names T, anchored on the first literal in
                its body that names T (touches-tables' provenance rule), or on
                the routine line with "fact only" when no literal does;
    [inferred]  a routine with an UPPER-CASE SQL verb literal naming T inside
                its impl span (Get-SqlVerbTables, P23), split read (FROM, JOIN)
                / write (INTO, UPDATE, DELETE FROM), MINUS the routines already
                certain ON THAT SIDE. Dashed.

  Both counts are printed on the focus box, so a reader sees the gap.

  [by name] IS NOT SQL
  ---------------------
  A literal EQUAL to the table name ('CAUSFAIL') is a pipe command on CLIENT
  (P25) and a log context or generator key on SERVER. Those units are drawn in
  their own dashed "mentions (not SQL)" cluster labelled [by name], in the
  focus's rank with a dotted line and NO arrow (R15: a mention is not a read),
  and a literal inside a routine already drawn as a SQL consumer is not drawn
  twice. The match is exact; case-only matches are counted and named.

  THE COLUMN FORM
  ----------------
  T.C draws: SERVER routines that name T in SQL context (fact or verb literal)
  AND word-match C in a literal in the same span (P24); triggers FOR T whose
  body mentions NEW.C / OLD.C (P39); procedures whose scanned body names T and
  C; indexes on T whose definition line names C; and CLIENT DFM data bindings
  of C whose control's datasource chain (Get-DataSourceChain) RESOLVES TO T.
  A binding whose chain resolves elsewhere or not at all is COUNTED, never
  drawn: `ID` is a column of 77 tables (P34), and a binding of REASON on the
  STOPREAS form is not a consumer of CAUSFAIL.REASON.

  WHAT IT CANNOT SEE, SAID ON THE CHART
  --------------------------------------
  Positional reads (`Fields[1].AsString`), SQL assembled from non-literal
  pieces, and anything only the live schema knows.

  FRESHNESS (R11): trigger and procedure bodies and index lines are read from
  the .SQL source only after Test-SourceFresh; a stale script's rows render
  `[stale source]` and are not classified. -SourceOverride maps an indexed path
  to a copy to read instead (ruling R4).
#>
[CmdletBinding()]
param(
  [string]    $Table,
  [string]    $Column,
  [Parameter(Mandatory)][string] $DbPath,
  [Parameter(Mandatory)][string] $SqlDbPath,
  [string]    $OutDir,
  [int]       $Cap = 12,                  # rows shown per cluster; the rest disclosed
  [hashtable] $SourceOverride,
  # TEST HOOK (R25, fix round 1): 'TABLE.COLUMN' names taken back OUT of the SQL
  # index's extracted columns, so the gate can drive the `quoted` state through
  # this emitter against the real, fresh script (see Hide-ExtractedColumns). A chart
  # drawn with it says TEST CHART on its focus box.
  [string[]]  $TestHideColumn,
  [string] $Engine     = '',
  [string] $Dot        = '',
  [string] $FontMono   = 'Consolas',
  [string] $FontSans   = 'Segoe UI'
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Emit-Common.ps1')
$Engine = Resolve-DragLintEngine $Engine   # R2: '' = DRAGLINT_ENGINE, settings.json, installed, shared (Emit-Common)
$DbPath    = Get-CloneDb $DbPath
$SqlDbPath = Get-CloneDb $SqlDbPath

# touches-tables' DB hue for the database side; readers and writers keep the
# caller/callee pair; [by name] and data bindings get their own roles.
$PAL = @{
  readBorder  = '#3B5BDB'; readFill  = '#EDF2FF'; readHdr  = '#3B5BDB'
  writeBorder = '#C2410C'; writeFill = '#FFF4E6'; writeHdr = '#C2410C'
  dbBorder    = '#BE185D'; dbFill    = '#FDF2F8'; dbHdr    = '#BE185D'
  nameBorder  = '#6B7280'; nameFill  = '#F3F4F6'; nameHdr  = '#6B7280'
  bindBorder  = '#7C3AED'; bindFill  = '#F3EEFF'; bindHdr  = '#7C3AED'
  focusBorder = '#0F766E'; focusFill = '#E2F1EF'; focusHdr = '#0F766E'
  rowInk      = '#1F2933'; lineInk   = '#8A94A6'; focusInk = '#0B3F39'
}
$ROUTINE_KINDS = @('method', 'procedure', 'function', 'constructor', 'destructor')
$BIND = @('DataBinding.FieldName', 'DataBinding.DataField', 'FieldName', 'DataField',
          'DataController.KeyFieldNames', 'Properties.KeyFieldNames',
          'DataController.DetailKeyFieldNames', 'DataController.MasterKeyFieldNames',
          'IndexFieldNames')
# Measured 2026-09-23 against the live Firebird DB, VALIDATION ONLY (P16).
$SCHEMA_NOTE = '5 live tables are not in the scripts (2026-09-23)'

# ---- 0. the selection --------------------------------------------------------------
if ($Table -and $Column) { throw 'consumers: pass -Table OR -Column (TABLE.COLUMN), not both' }
if (-not $Table -and -not $Column) { throw 'consumers: pass -Table <TABLE> or -Column <TABLE.COLUMN>' }
$selTable = $Table; $selCol = $null
if ($Column) {
  if ($Column -notmatch '^\s*([A-Za-z_][A-Za-z0-9_$]*)\.([A-Za-z_][A-Za-z0-9_$]*)\s*$') {
    throw "consumers: -Column takes TABLE.COLUMN, got '$Column'"
  }
  $selTable = $Matches[1]; $selCol = $Matches[2]
}
$selTable = $selTable.Trim()
Write-Host "consumers: $(if ($selCol) { "$selTable.$selCol" } else { $selTable })"

# The two DB roles must not be swapped. Each check is one COUNT, run with $DbPath
# shadowed in a function scope so the caller's value is untouched.
function Get-SqlTableSymbolCount([string] $Db) {
  $DbPath = $Db
  $r = Invoke-IndexQuery "SELECT COUNT(*) AS n FROM symbols WHERE kind = 'sql_table'"
  [int]$r[0].n
}
$nSqlSyms = Get-SqlTableSymbolCount $SqlDbPath
if ($nSqlSyms -eq 0) {
  throw ("consumers: $SqlDbPath is not a SQL index (0 sql_table symbols). -SqlDbPath takes the " +
         'index of the .SQL scripts (SQL-drag-lint-sql.sqlite); the Delphi project index goes in -DbPath.')
}
if ((Get-SqlTableSymbolCount $DbPath) -gt 0) {
  throw ("consumers: $DbPath is a SQL-script index, not a Delphi project index. -DbPath takes the " +
         'Delphi project clone (SERVER for the SQL half, CLIENT for bindings); the scripts go in -SqlDbPath.')
}

# Nearest candidate (shared prefix, then edit distance), so a refusal names what was probably meant.
function Get-NearestName([string] $Want, [string[]] $Names) {
  $w = $Want.ToUpperInvariant()
  $best = $null; $bestD = [int]::MaxValue
  foreach ($n in $Names) {
    $u = $n.ToUpperInvariant()
    $d = New-Object 'int[,]' ($w.Length + 1), ($u.Length + 1)
    for ($i = 0; $i -le $w.Length; $i++) { $d[$i, 0] = $i }
    for ($j = 0; $j -le $u.Length; $j++) { $d[0, $j] = $j }
    for ($i = 1; $i -le $w.Length; $i++) {
      for ($j = 1; $j -le $u.Length; $j++) {
        $c = $(if ($w[$i - 1] -eq $u[$j - 1]) { 0 } else { 1 })
        $d[$i, $j] = [Math]::Min([Math]::Min($d[($i - 1), $j] + 1, $d[$i, ($j - 1)] + 1), $d[($i - 1), ($j - 1)] + $c)
      }
    }
    # a shared prefix of 3+ characters outranks raw distance: PDF_SCAN is
    # nearer PDF1 than DATACHAN for a reader, though not by edit count
    $lcp = 0
    while ($lcp -lt [Math]::Min($w.Length, $u.Length) -and $w[$lcp] -eq $u[$lcp]) { $lcp++ }
    $dist = $d[$w.Length, $u.Length] - $(if ($lcp -ge 3) { 1000 * $lcp } else { 0 })
    if ($dist -lt $bestD -or ($dist -eq $bestD -and [string]::CompareOrdinal($u, $best) -lt 0)) { $best = $u; $bestD = $dist }
  }
  $best
}

# ---- 1. resolve against the COLLAPSED script schema -----------------------------------
$sqlSet = Get-SqlTableSet $SqlDbPath
if ($TestHideColumn) {
  $sqlSet = Hide-ExtractedColumns $sqlSet $TestHideColumn
  Write-Host "  TEST: extracted column(s) hidden: $($TestHideColumn -join ', ')"
}
if (-not $sqlSet.Tables.ContainsKey($selTable)) {
  $near = Get-NearestName $selTable $sqlSet.Names
  throw ("consumers: no table $selTable in the SQL index (script-derived; the scripts may lag the live " +
         "schema) -- nearest: $near. The index holds $($sqlSet.TableCount) table names from " +
         "$($sqlSet.DeclarationCount) declarations; $SCHEMA_NOTE.")
}
$tbl = $sqlSet.Tables[$selTable]
$tName = $tbl.Name
$declFile = [IO.Path]::GetFileName($tbl.File)
$declText = $(if ($tbl.DeclCount -gt 1) { "declared $($tbl.DeclCount) times in the scripts; showing the newest ($declFile`:$($tbl.Line), by file date)" }
              else { "declared 1 time in the scripts ($declFile`:$($tbl.Line))" })
Write-Host "  $tName -- $declText; $($tbl.ColumnNames.Count) column(s)"

# THE column state (final wave, item 1): the SHARED Get-SqlColumnState. A
# column the SQL index does not extract (not yes / quoted / older) is not refused
# YET: this index's own SQL for T may name it (server-sql), which needs the
# routine set of step 3 -- decided right after it.
$colName = $null; $colFile = $tbl.File; $colLine = $tbl.Line; $colOlder = $false; $cs = $null
function Set-ColumnFromState {
  $script:colOlder = ($cs.State -eq 'older'); $script:colFile = $cs.File; $script:colLine = $cs.Line
  $decl = @($tbl.ColumnNames | Where-Object { [string]::Equals($_, $selCol, [StringComparison]::OrdinalIgnoreCase) })
  $script:colName = $(if ($decl.Count) { [string]$decl[0] } else { $cs.Column })
  Write-Host "  column $tName.$($script:colName) ($(Get-ColumnStateName $cs.State))"
}
if ($selCol) {
  $cs = Get-SqlColumnState $sqlSet $tName $selCol $SourceOverride
  if ($cs.IsColumn) { Set-ColumnFromState }
}

# ---- 2. index-wide pre-check on the Delphi index -----------------------------------------
function Split-Tables($v) {
  if ([string]::IsNullOrWhiteSpace([string]$v)) { return , @() }
  , @(([string]$v -split ',\s*') | ForEach-Object { $_.Trim().ToUpperInvariant() } |
      Where-Object { $_ -ne '' } | Sort-Object -Unique)
}
$facts = Get-AllIndexRows @'
SELECT sf.symbol_id AS sid, sf.sql_reads AS r, sf.sql_writes AS w
  FROM symbol_facts sf
 WHERE sf.sql_reads IS NOT NULL OR sf.sql_writes IS NOT NULL
'@ 'sf.symbol_id'
$nReadFacts  = @($facts | Where-Object { $null -ne $_.r }).Count
$nWriteFacts = @($facts | Where-Object { $null -ne $_.w }).Count
$nFactSyms   = $facts.Count
$factReadTables = @($facts | ForEach-Object { Split-Tables $_.r } | ForEach-Object { $_ } | Sort-Object -Unique)

# The P23 population: literals holding an UPPER-CASE SQL verb as a word. GLOB is
# case-sensitive, so it is a correct pre-filter for the regex that follows.
$VERB_RX = '(?<![A-Za-z0-9_$])(SELECT|INSERT|UPDATE|DELETE|FROM|JOIN|INTO|EXECUTE)(?![A-Za-z0-9_$])'
$glob = (@('SELECT', 'INSERT', 'UPDATE', 'DELETE', 'FROM', 'JOIN', 'INTO', 'EXECUTE') | ForEach-Object { "sl.text GLOB '*$_*'" }) -join ' OR '
$pre = Get-AllIndexRows @"
SELECT sl.id AS id, sl.file_id AS fid, sl.start_line AS line, sl.text AS text, f.path AS path
  FROM string_literals sl JOIN files f ON f.id = sl.file_id
 WHERE sl.source = 'pas' AND sl.kind IN ('literal','format') AND ($glob)
"@ 'sl.id'
$verbLits = @($pre | Where-Object { [regex]::IsMatch([string]$_.text, $VERB_RX) })
$verbHits = New-Object System.Collections.ArrayList       # one row per (literal, verb, name)
foreach ($x in $verbLits) {
  foreach ($h in (Get-SqlVerbTables ([string]$x.text) $sqlSet)) {
    [void]$verbHits.Add([pscustomobject]@{ Fid = [int]$x.fid; Path = [string]$x.path; Line = [int]$x.line
                                           Text = [string]$x.text; Verb = $h.Verb; Name = $h.Name; Kind = $h.Kind })
  }
}
$fromJoinTables = @($verbHits | Where-Object { $_.Kind -eq 'table' -and $_.Verb -in 'FROM', 'JOIN' } |
                    ForEach-Object { $_.Name } | Sort-Object -Unique)
Write-Host ("  index-wide: {0} read / {1} write facts over {2} symbols ({3} tables read by fact); {4} upper-case SQL-verb literals naming {5} tables after FROM/JOIN" -f `
            $nReadFacts, $nWriteFacts, $nFactSyms, $factReadTables.Count, $verbLits.Count, $fromJoinTables.Count)
$noSql = ($nFactSyms -eq 0 -and $verbLits.Count -eq 0)

# ---- helpers: routine spans ------------------------------------------------------------------
$routineCache = @{}   # file id -> routine rows with an impl span
function Get-FileRoutines([int] $Fid) {
  if (-not $routineCache.ContainsKey($Fid)) {
    # PAGED (final wave): uJobList.pas holds more than 200 routines, and the
    # unpaged query stopped `consumers -Table FOLDERS` on CLIENT at the row cap
    $routineCache[$Fid] = Get-AllIndexRows @"
SELECT s.id AS id, s.qualified_name AS q, s.impl_start_line AS a, s.impl_end_line AS b
  FROM symbols s
 WHERE s.file_id = $Fid AND s.impl_start_line > 0 AND s.kind IN ($(ConvertTo-SqlInList $ROUTINE_KINDS))
"@ 's.id'
  }
  , $routineCache[$Fid]
}
# the INNERMOST routine whose impl span holds the line; $null at unit level
function Find-Routine([int] $Fid, [int] $Line) {
  $best = $null
  foreach ($r in (Get-FileRoutines $Fid)) {
    if ([int]$r.a -le $Line -and [int]$r.b -ge $Line) {
      if (-not $best -or ([int]$r.b - [int]$r.a) -lt ([int]$best.b - [int]$best.a)) { $best = $r }
    }
  }
  $best
}
function Get-RoutineRows([int[]] $Ids) {
  $out = @{}
  for ($i = 0; $i -lt $Ids.Count; $i += 60) {
    $chunk = @($Ids[$i..([Math]::Min($i + 59, $Ids.Count - 1))])
    $rows = Invoke-IndexQuery @"
SELECT s.id AS id, s.qualified_name AS q, s.kind AS kind, s.file_id AS fid, f.path AS path,
       s.start_line AS dline, s.impl_start_line AS a, s.impl_end_line AS b
  FROM symbols s JOIN files f ON f.id = s.file_id
 WHERE s.id IN ($($chunk -join ','))
"@
    foreach ($r in $rows) {
      $out[[int]$r.id] = [pscustomobject]@{
        Id = [int]$r.id; Q = [string]$r.q; Kind = [string]$r.kind; Fid = [int]$r.fid; Path = [string]$r.path
        A = $(if ($r.a) { [int]$r.a } else { 0 }); B = $(if ($r.b) { [int]$r.b } else { 0 })
        Line = $(if ($r.a) { [int]$r.a } else { [int]$r.dline })
      }
    }
  }
  $out
}
# literals inside one span, cached per routine
$spanLits = @{}
function Get-SpanLiterals($Rt) {
  if (-not $spanLits.ContainsKey($Rt.Id)) {
    # assigned in each branch, not through $(if ...): a subexpression would
    # unroll the returned array (the Invoke-IndexQuery contract)
    if ($Rt.A -gt 0 -and $Rt.B -ge $Rt.A) {
      $spanLits[$Rt.Id] = Get-AllIndexRows @"
SELECT sl.id AS id, sl.start_line AS line, sl.text AS text
  FROM string_literals sl
 WHERE sl.file_id = $($Rt.Fid) AND sl.kind IN ('literal','format','const')
   AND sl.start_line BETWEEN $($Rt.A) AND $($Rt.B)
"@ 'sl.start_line, sl.id'
    } else {
      $spanLits[$Rt.Id] = New-Object object[] 0
    }
  }
  , $spanLits[$Rt.Id]
}
# "A, B, C +N more" -- a trigger over FOLDERS touches 80 columns, and one row
# carrying all of them makes the chart ten thousand pixels wide
function Get-ShortList($Items, [int] $Max) {
  $all = @($Items)
  if ($all.Count -le $Max) { return ($all -join ', ') }
  (@($all[0..($Max - 1)]) -join ', ') + " +$($all.Count - $Max) more"
}
function Get-WordRx([string] $Name) { "(?<![A-Za-z0-9_$])$([regex]::Escape($Name))(?![A-Za-z0-9_$])" }

# ---- 3. the table's SQL consumers on the Delphi side ----------------------------------------
$certR = @{}; $certW = @{}             # routine id -> $true
foreach ($f in $facts) {
  if ((Split-Tables $f.r) -contains $tName.ToUpperInvariant()) { $certR[[int]$f.sid] = $true }
  if ((Split-Tables $f.w) -contains $tName.ToUpperInvariant()) { $certW[[int]$f.sid] = $true }
}
# verb literals naming T -> routine; unit-level ones are keyed by -file id
# plain hashtables, NOT [ordered]: an OrderedDictionary indexed with an [int]
# key reads it as a POSITION, and these keys are routine ids
$litR = @{}; $litW = @{}
foreach ($h in @($verbHits | Where-Object { $_.Kind -eq 'table' -and $_.Name -eq $tName })) {
  $rt = Find-Routine $h.Fid $h.Line
  $key = $(if ($rt) { [int]$rt.id } else { - $h.Fid })
  $bag = $(if ($h.Verb -in 'FROM', 'JOIN') { $litR } else { $litW })
  if (-not $bag.ContainsKey($key)) {
    $bag[$key] = [pscustomobject]@{ Key = $key; Fid = $h.Fid; Path = $h.Path; Line = $h.Line; Verbs = New-Object System.Collections.ArrayList; Text = $h.Text }
  }
  if (-not $bag[$key].Verbs.Contains($h.Verb)) { [void]$bag[$key].Verbs.Add($h.Verb) }
}
$infR = @($litR.Keys | Where-Object { -not $certR.ContainsKey($_) })
$infW = @($litW.Keys | Where-Object { -not $certW.ContainsKey($_) })
$rtIds = @(@($certR.Keys) + @($certW.Keys) + @($litR.Keys) + @($litW.Keys) | Where-Object { $_ -gt 0 } | Sort-Object -Unique)
$rtInfo = $(if ($rtIds.Count) { Get-RoutineRows $rtIds } else { @{} })
# ROUTINES and UNIT-LEVEL rows counted apart (final wave, item 6): a unit-level
# row is one per UNIT (key = -file id), not one per literal, and it is not a routine
$mR = Measure-ConsumerKeys @($certR.Keys) @($litR.Keys)
$mW = Measure-ConsumerKeys @($certW.Keys) @($litW.Keys)
$unitLevel = (Measure-ConsumerKeys @() (@($litR.Keys) + @($litW.Keys))).Units
Write-Host ("  {0}: certain readers {1} / writers {2}; inferred readers {3} / writers {4}; reading routines {5} / writing routines {6}; units with a unit-level literal {7}" -f `
            $tName, $certR.Count, $certW.Count, $infR.Count, $infW.Count, $mR.Routines, $mW.Routines, $unitLevel)

# ---- 3b. a column the SQL index does not extract: this index's own SQL (server-sql)
# A routine above (fact or verb literal names T) whose span holds a literal that
# word-matches the column: the same evidence the column form draws, and the rule
# lands-where applies to its DataService. The first by file and line anchors it.
if ($selCol -and -not $cs.IsColumn) {
  $scRx = Get-WordRx $selCol.ToUpperInvariant()
  $scHits = New-Object System.Collections.ArrayList
  foreach ($id in $rtIds) {
    $rt = $rtInfo[$id]
    if (-not $rt) { continue }
    $h1 = @((Get-SpanLiterals $rt) | Where-Object { [regex]::IsMatch([string]$_.text, $scRx) } | Select-Object -First 1)
    if ($h1.Count) { [void]$scHits.Add([pscustomobject]@{ File = $rt.Path; Line = [int]$h1[0].line; Routine = (Get-ShortName $rt.Q (Get-UnitName $rt.Path)) }) }
  }
  $scFirst = @($scHits | Sort-Object File, Line | Select-Object -First 1)
  $cs = Get-SqlColumnState $sqlSet $tName $selCol $SourceOverride -ServerSqlHit $(if ($scFirst.Count) { $scFirst[0] } else { $null }) `
          -SqlSearched ([IO.Path]::GetFileName($DbPath))
  if ($cs.State -eq 'stale') {
    throw "consumers: cannot tell whether $tName.$($selCol.ToUpperInvariant()) is a column -- $($cs.Label). Script-derived; the scripts may lag the live schema."
  }
  if (-not $cs.IsColumn) {
    $near = Get-NearestName $selCol (@($tbl.ColumnNames) + @($tbl.OlderOnlyColumns.Keys))
    throw ("consumers: no column $selCol in ${tName}: $($cs.Label) -- nearest: $near. " +
           'Script-derived; the scripts may lag the live schema.')
  }
  Set-ColumnFromState
}

# ---- 4. [by name]: literals EQUAL to the table name ------------------------------------------
$tq = ConvertTo-SqlText $tName
$named = Get-AllIndexRows @"
SELECT sl.id AS id, sl.file_id AS fid, sl.start_line AS line, sl.kind AS kind, f.path AS path
  FROM string_literals sl JOIN files f ON f.id = sl.file_id
 WHERE sl.source = 'pas' AND sl.kind IN ('literal','const','format') AND sl.text = '$tq'
"@ 'sl.id'
$drawnIds = @{}
foreach ($k in @(@($certR.Keys) + @($certW.Keys) + @($litR.Keys) + @($litW.Keys))) { if ($k -gt 0) { $drawnIds[$k] = $true } }
$byNameFiles = [ordered]@{}
$byNameSkipped = 0
foreach ($n in @($named | Sort-Object { [string]$_.path }, { [int]$_.line })) {
  $rt = Find-Routine ([int]$n.fid) ([int]$n.line)
  if ($rt -and $drawnIds.ContainsKey([int]$rt.id)) { $byNameSkipped++; continue }
  $p = [string]$n.path
  if (-not $byNameFiles.Contains($p)) { $byNameFiles[$p] = New-Object System.Collections.ArrayList }
  [void]$byNameFiles[$p].Add([pscustomobject]@{ Line = [int]$n.line; Kind = [string]$n.kind; Routine = $(if ($rt) { [string]$rt.q } else { '' }) })
}
$byNameLits = @($byNameFiles.Values | ForEach-Object { $_.Count } | Measure-Object -Sum).Sum
if (-not $byNameLits) { $byNameLits = 0 }
# The match above is EXACT (final wave, item 8). Literals equal to T only
# case-insensitively are COUNTED and named, not drawn: measured on CLIENT, the
# one for FOLDERS is 'Folders', a ribbon tab caption (uJobList.pas:552) -- the
# pipe-command and log-context literals this cluster exists for are upper case.
$caseOnly = Invoke-IndexQuery @"
SELECT sl.text AS text, sl.start_line AS line, f.path AS path
  FROM string_literals sl JOIN files f ON f.id = sl.file_id
 WHERE sl.source = 'pas' AND sl.kind IN ('literal','const','format') AND UPPER(sl.text) = UPPER('$tq') AND sl.text <> '$tq'
 ORDER BY f.path, sl.start_line
"@ 'consumers (case-only name literals)'
$caseOnlyText = (@($caseOnly | ForEach-Object { "'$($_.text)' $([IO.Path]::GetFileName([string]$_.path)):$($_.line)" }) -join ', ')

# ---- 5. the database side (SQL index) --------------------------------------------------------
$trigSet = Get-SqlTriggerSet $SqlDbPath $SourceOverride
$trigFor = @($trigSet.Triggers | Where-Object { $_.Table -eq $tName } | Sort-Object Name)
$trigOther = @($trigSet.Triggers | Where-Object { $_.Table -ne $tName -and ($_.OtherTables -contains $tName) } | Sort-Object Name)
$procSet = Get-SqlProcedureSet $SqlDbPath $SourceOverride
$procByName = @($procSet.Declarations | Group-Object { $_.Name.ToUpperInvariant() })
$procRows = New-Object System.Collections.ArrayList      # one per procedure NAME naming T
$procUnscanned = New-Object System.Collections.ArrayList # name-only [body not scanned] rows
$tokRx = "(^|_)$([regex]::Escape($tName.ToUpperInvariant()))(_|$)"
foreach ($g in $procByName) {
  $hitDecl = @($g.Group | Where-Object { $_.Found -and ($_.Tables -contains $tName) } | Sort-Object Line)
  if ($hitDecl.Count) { [void]$procRows.Add([pscustomobject]@{ Decl = $hitDecl[0]; Decls = $g.Count }); continue }
  $unscanned = @($g.Group | Where-Object { -not $_.Found })
  if ($unscanned.Count -and $g.Name -match $tokRx) {
    [void]$procUnscanned.Add([pscustomobject]@{ Decl = $unscanned[0]; Stale = [bool]$unscanned[0].Stale })
  }
}
$procNotScanned = @($procSet.Declarations | Where-Object { -not $_.Found }).Count

function Get-SqlIndexRows([string] $Name) {
  $DbPath = $SqlDbPath
  Invoke-IndexQuery @"
SELECT s.name AS name, s.start_line AS line, f.path AS path
  FROM symbols s JOIN files f ON f.id = s.file_id
 WHERE s.kind = 'sql_index'
   AND EXISTS (SELECT 1 FROM refs r WHERE r.file_id = s.file_id AND r.start_line = s.start_line
                  AND r.kind = 'sql_table_ref' AND UPPER(r.name_text) = UPPER('$(ConvertTo-SqlText $Name)'))
 ORDER BY f.path, s.start_line
"@ 'consumers (sql indexes)'
}
$idxRows = Get-SqlIndexRows $tName
Write-Host ("  database side: {0} trigger(s) FOR {1}, {2} other trigger bod(ies) naming it, {3} procedure(s), {4} index(es); procedure bodies scanned {5}/{6}" -f `
            $trigFor.Count, $tName, $trigOther.Count, $procRows.Count, $idxRows.Count, $procSet.BodiesFound, $procSet.Count)

# the stripped text of one SQL line, or $null when its script is stale
function Get-SqlLineText([string] $Path, [int] $Line) {
  $DbPath = $SqlDbPath
  if (-not (Test-SourceFresh $Path $SourceOverride)) { return $null }
  $lines = Get-StrippedSqlLines (Resolve-SourceReadPath $Path $SourceOverride)
  $(if ($Line -ge 1 -and $Line -le $lines.Count) { $lines[$Line - 1] } else { '' })
}

# ---- 6. the COLUMN form ------------------------------------------------------------------------
$colRx = $null
$srvCol = @{}          # routine id -> first literal naming C: Line, Text
$srvColSilent = 0      # routines that touch T but name no C in a literal
$trigCol = @(); $procCol = @(); $idxCol = @(); $trigColStale = @(); $trigColNoBody = @()
$bindAll = 0; $bindDrawn = New-Object System.Collections.ArrayList
$bindElsewhere = @{}; $bindUnresolved = @{}; $bindStale = 0
if ($colName) {
  # Case-SENSITIVE on the upper-case name: the SQL in this corpus is upper case
  # (P23), and a case-insensitive match reads prose ("the reason ...") as a column.
  $colRx = Get-WordRx $colName.ToUpperInvariant()
  foreach ($id in $rtIds) {
    $rt = $rtInfo[$id]
    if (-not $rt) { continue }
    $hit = @((Get-SpanLiterals $rt) | Where-Object { [regex]::IsMatch([string]$_.text, $colRx) } | Select-Object -First 1)
    if ($hit.Count) { $srvCol[$id] = [pscustomobject]@{ Line = [int]$hit[0].line; Text = [string]$hit[0].text } }
    else { $srvColSilent++ }
  }
  $trigCol = @($trigFor | Where-Object { $_.Columns -contains $colName.ToUpperInvariant() })
  # a trigger FOR T whose body was NOT read has no Columns -- it must not vanish
  # from the column form (final wave, item 4): counted, named and said
  $trigColStale  = @($trigFor | Where-Object { $_.Stale })
  $trigColNoBody = @($trigFor | Where-Object { -not $_.Stale -and -not $_.Found })
  $procCol = @($procRows | Where-Object { [regex]::IsMatch([string]$_.Decl.Text, $colRx) })
  $idxCol  = @($idxRows | Where-Object { $lt = Get-SqlLineText ([string]$_.path) ([int]$_.line); $lt -and [regex]::IsMatch($lt.ToUpperInvariant(), $colRx) })

  # CLIENT data bindings of C, drawn only when the chain resolves to T (P32-P34)
  $binds = Get-AllIndexRows @"
SELECT sl.id AS id, sl.start_line AS line, sl.owner_name AS prop, f.path AS dfm, c.name AS ctl,
       $(Get-ControlDataSourceSql 'sl' 'c') AS ds
  FROM string_literals sl
  JOIN files f ON f.id = sl.file_id
  LEFT JOIN symbols c ON c.id = sl.symbol_id
 WHERE sl.kind = 'dfm-prop' AND UPPER(sl.text) = UPPER('$(ConvertTo-SqlText $colName)')
   AND sl.owner_name IN ($(ConvertTo-SqlInList $BIND))
"@ 'sl.id'
  $bindAll = $binds.Count
  $chainCache = @{}
  foreach ($b in $binds) {
    $ds = [string]$b.ds
    if (-not $ds) { $bindUnresolved['no datasource on the control or its view in the DFM'] = 1 + [int]$bindUnresolved['no datasource on the control or its view in the DFM']; continue }
    $ck = "$([string]$b.dfm)|$ds"
    if (-not $chainCache.ContainsKey($ck)) { $chainCache[$ck] = Get-DataSourceChain ([string]$b.dfm) $ds $sqlSet $SourceOverride }
    $ch = $chainCache[$ck]
    if ($ch.Grade -eq 'stale source') { $bindStale++; continue }
    if ($ch.ResolvedTable -and [string]::Equals($ch.ResolvedTable, $tName, [StringComparison]::OrdinalIgnoreCase)) {
      [void]$bindDrawn.Add([pscustomobject]@{ Dfm = [string]$b.dfm; Line = [int]$b.line; Control = [string]$b.ctl
                                              Prop = [string]$b.prop; Ds = $ds; Grade = $ch.Grade })
    } elseif ($ch.ResolvedTable) {
      $bindElsewhere[$ch.ResolvedTable] = 1 + [int]$bindElsewhere[$ch.ResolvedTable]
    } else {
      $bindUnresolved[$ch.Grade] = 1 + [int]$bindUnresolved[$ch.Grade]
    }
  }
  Write-Host ("  column {0}: {1} server routine(s) name it ({2} touch {3} without naming it); {4} trigger(s), {5} procedure(s), {6} index(es); bindings {7} index-wide, {8} drawn" -f `
              $colName, $srvCol.Count, $srvColSilent, $tName, $trigCol.Count, $procCol.Count, $idxCol.Count, $bindAll, $bindDrawn.Count)
}

# ---- 7. rows ------------------------------------------------------------------------------------
$anchored = 0
function New-Row([string] $Label, [string] $File, [int] $Line, [string] $Tip, [string] $Note) {
  $script:anchored++
  [pscustomobject]@{ Label = $Label; Line = $Line; Href = New-RowHref $File $Line; Tip = $Tip; Note = $Note }
}
function Get-RoutineLabel($Rt) { Get-ShortName $Rt.Q (Get-UnitName $Rt.Path) }

# a Delphi routine row: literal provenance first (touches-tables' rule), the
# routine line as the fallback, and SAID so
function New-RoutineRow($Key, [string] $Side, $LitBag, [bool] $Certain) {
  if ($Key -lt 0) {
    $e = $LitBag[$Key]
    return New-Row "(unit level) $(Get-UnitName $e.Path)" $e.Path $e.Line `
      "$($e.Verbs -join ', ') $tName outside any routine -- $([IO.Path]::GetFileName($e.Path)):$($e.Line)" 'unit-level literal'
  }
  $rt = $rtInfo[[int]$Key]
  $unit = Get-UnitName $rt.Path
  if ($colName) {
    $c = $srvCol[[int]$Key]
    $how = $(if ($certR.ContainsKey([int]$Key) -or $certW.ContainsKey([int]$Key)) { 'table by fact' } else { 'table by literal' })
    return New-Row (Get-RoutineLabel $rt) $rt.Path $c.Line "$($rt.Q) -- $([IO.Path]::GetFileName($rt.Path)):$($c.Line) names $colName ($how)" "$unit; $how"
  }
  if ($Certain) {
    $hit = @((Get-SpanLiterals $rt) | Where-Object { [regex]::IsMatch([string]$_.text, (Get-WordRx $tName)) } | Select-Object -First 1)
    if ($hit.Count) {
      return New-Row (Get-RoutineLabel $rt) $rt.Path ([int]$hit[0].line) "$($rt.Q) ($Side, sql_${Side}s fact) -- $([IO.Path]::GetFileName($rt.Path)):$($hit[0].line)" $unit
    }
    return New-Row (Get-RoutineLabel $rt) $rt.Path $rt.Line "$($rt.Q) ($Side, sql_${Side}s fact) -- no literal inside the routine names $tName" "$unit; fact only"
  }
  $e = $LitBag[$Key]
  New-Row (Get-RoutineLabel $rt) $rt.Path $e.Line "$($rt.Q) -- $($e.Verbs -join ', ') $tName at $([IO.Path]::GetFileName($rt.Path)):$($e.Line)" "$unit; $($e.Verbs -join '/')"
}
function Sort-Keys($Keys) {
  , @($Keys | Sort-Object @{ E = { if ($_ -gt 0) { $rtInfo[[int]$_].Q } else { '' } } }, @{ E = { [int]$_ } })
}

$clusters = New-Object System.Collections.ArrayList   # Side, Cid, Title, Subtitle, Rows, Style, Border, Fill, Hdr
function Add-Cluster([string] $Side, [string] $Id, [string] $Title, $Rows, [string] $Kind, [bool] $Dashed, [string] $Extra) {
  $all = @($Rows | Where-Object { $null -ne $_ })
  if (-not $all.Count -and -not $Extra) { return }
  $top = Get-TopRanked $all $Cap
  $shown = New-Object System.Collections.ArrayList
  foreach ($r in $top.Shown) { [void]$shown.Add($r) }
  # rows cut by the cap were counted as anchored when built; take them back out
  $script:anchored -= $top.HiddenRows
  $d = Get-DisclosureText $top.HiddenRows 0 'rows'
  if ($d) { [void]$shown.Add((New-NoteRow $d)) }
  if ($Extra) { foreach ($x in @($Extra -split "`n")) { if ($x) { [void]$shown.Add((New-NoteRow $x)) } } }
  [void]$clusters.Add([pscustomobject]@{
    Side = $Side; Id = $Id; Title = $Title; Count = $all.Count
    Subtitle = "$($all.Count) row$(if ($all.Count -ne 1) { 's' })$(if ($Dashed) { ' [inferred]' } else { '' })"
    Rows = $shown.ToArray(); Style = $(if ($Dashed) { 'rounded,filled,dashed' } else { 'rounded,filled' })
    Border = $PAL["${Kind}Border"]; Fill = $PAL["${Kind}Fill"]; Hdr = $PAL["${Kind}Hdr"]
  })
}

if ($colName) {
  $srvReadKeys  = @($srvCol.Keys | Where-Object { $certR.ContainsKey($_) -or $litR.ContainsKey($_) })
  $srvWriteKeys = @($srvCol.Keys | Where-Object { $certW.ContainsKey($_) -or $litW.ContainsKey($_) })
  $lb = @{}; foreach ($k in $litR.Keys) { $lb[$k] = $litR[$k] }
  Add-Cluster 'left' 'colreads' "reads $tName and names $colName" @((Sort-Keys $srvReadKeys) | ForEach-Object { New-RoutineRow $_ 'read' $lb $false }) 'read' $true ''
  $lb = @{}; foreach ($k in $litW.Keys) { $lb[$k] = $litW[$k] }
  Add-Cluster 'right' 'colwrites' "writes $tName and names $colName" @((Sort-Keys $srvWriteKeys) | ForEach-Object { New-RoutineRow $_ 'write' $lb $false }) 'write' $true ''
  $bextra = New-Object System.Collections.ArrayList
  foreach ($k in @($bindElsewhere.Keys | Sort-Object)) { [void]$bextra.Add("$($bindElsewhere[$k]) bound on a datasource that resolves to $k") }
  foreach ($k in @($bindUnresolved.Keys | Sort-Object)) { [void]$bextra.Add("$($bindUnresolved[$k]) whose datasource chain stops ($k)") }
  if ($bindStale) { [void]$bextra.Add("$bindStale in a form whose source differs from the index [stale source]") }
  if ($bindAll -gt 0) {
    Add-Cluster 'left' 'bindings' "bound to $colName via a datasource on $tName" @($bindDrawn | ForEach-Object {
        New-Row $_.Control $_.Dfm $_.Line "$($_.Control).$($_.Prop) = '$colName' via $($_.Ds) -> $tName ($($_.Grade)) -- $([IO.Path]::GetFileName($_.Dfm)):$($_.Line)" "$(Get-UnitName $_.Dfm); $($_.Ds)" }) `
      'bind' $true (@("$bindAll binding(s) of $colName in this index; only chains resolving to $tName are drawn") + @($bextra) -join "`n")
  }
  $tx = New-Object System.Collections.ArrayList
  if ($trigColStale.Count) {
    [void]$tx.Add("$($trigColStale.Count) trigger(s) FOR $tName in a script that differs from the index [stale source] -- not scanned for ${colName}: " +
                  (@($trigColStale | ForEach-Object { "$($_.Name)@$([IO.Path]::GetFileName($_.File)):$($_.Line)" }) -join ', '))
  }
  if ($trigColNoBody.Count) {
    [void]$tx.Add("$($trigColNoBody.Count) trigger(s) FOR $tName whose body was not found -- not scanned for ${colName}: " +
                  (@($trigColNoBody | ForEach-Object { "$($_.Name)@$([IO.Path]::GetFileName($_.File)):$($_.Line)" }) -join ', '))
  }
  Add-Cluster 'db' 'coltriggers' "triggers FOR $tName using $colName" @($trigCol | ForEach-Object {
      New-Row $_.Name $_.File $_.Line "$($_.Name) FOR ${tName}: NEW./OLD.$colName in its body -- $([IO.Path]::GetFileName($_.File)):$($_.Line)" "NEW/OLD.$colName" }) 'db' $false ($tx -join "`n")
  # procedure bodies not scanned (stale / no terminator) cannot name the column
  # either -- the same disclosure the table form carries, plus the name-only rows
  $cpx = New-Object System.Collections.ArrayList
  if ($procNotScanned) { [void]$cpx.Add("$procNotScanned of $($procSet.Count) procedure bodies not scanned") }
  foreach ($u in $procUnscanned) { [void]$cpx.Add("$($u.Decl.Name): name contains $tName, body not scanned $(if ($u.Stale) { '[stale source]' } else { '[body not scanned]' })") }
  Add-Cluster 'db' 'colprocs' "procedures naming $tName and $colName" @($procCol | ForEach-Object {
      New-Row $_.Decl.Name $_.Decl.File $_.Decl.Line "$($_.Decl.Name): body names $tName and $colName -- $([IO.Path]::GetFileName($_.Decl.File)):$($_.Decl.Line)" 'body scan' }) 'db' $true ($cpx -join "`n")
  Add-Cluster 'db' 'colindexes' "indexes on $tName over $colName" @($idxCol | ForEach-Object {
      New-Row ([string]$_.name) ([string]$_.path) ([int]$_.line) "$($_.name) ON $tName (...$colName...) -- $([IO.Path]::GetFileName([string]$_.path)):$($_.line)" '' }) 'db' $false ''
} else {
  $lb = @{}; foreach ($k in $litR.Keys) { $lb[$k] = $litR[$k] }
  Add-Cluster 'left' 'certreads' 'reads [certain]' @((Sort-Keys @($certR.Keys)) | ForEach-Object { New-RoutineRow $_ 'read' $lb $true }) 'read' $false ''
  Add-Cluster 'left' 'infreads'  'reads, by SQL literal' @((Sort-Keys $infR) | ForEach-Object { New-RoutineRow $_ 'read' $lb $false }) 'read' $true ''
  $lb = @{}; foreach ($k in $litW.Keys) { $lb[$k] = $litW[$k] }
  Add-Cluster 'right' 'certwrites' 'writes [certain]' @((Sort-Keys @($certW.Keys)) | ForEach-Object { New-RoutineRow $_ 'write' $lb $true }) 'write' $false ''
  Add-Cluster 'right' 'infwrites'  'writes, by SQL literal' @((Sort-Keys $infW) | ForEach-Object { New-RoutineRow $_ 'write' $lb $false }) 'write' $true ''
  # R15 (final wave, item 7): NOT on the readers side and no arrow into the
  # focus -- a literal equal to the name proves a mention, not a read
  Add-Cluster 'mention' 'byname' "mentions (not SQL) [by name] -- a literal equal to $tName" @($byNameFiles.Keys | ForEach-Object {
      $ls = $byNameFiles[$_]
      New-Row (Get-UnitName $_) $_ $ls[0].Line "$([IO.Path]::GetFileName($_)): '$tName' at $(@($ls | ForEach-Object { "$($_.Kind) :$($_.Line)" }) -join ', ')" `
        "$($ls.Count) literal$(if ($ls.Count -ne 1) { 's' }): $(@($ls | ForEach-Object { ":$($_.Line)" }) -join ' ')" }) 'name' $true ''
  Add-Cluster 'db' 'triggers' "triggers FOR $tName" @($trigFor | ForEach-Object {
      $cl = $(if ($_.Stale) { '[stale source]' } elseif ($_.Found) { "NEW/OLD: $(Get-ShortList $_.Columns 6)" } else { 'body not found' })
      New-Row $_.Name $_.File $_.Line "$($_.Name) FOR $tName -- $([IO.Path]::GetFileName($_.File)):$($_.Line)" $cl }) 'db' $false ''
  Add-Cluster 'db' 'othertriggers' "other triggers naming $tName in their body" @($trigOther | ForEach-Object {
      New-Row $_.Name $_.File $_.Line "$($_.Name) FOR $($_.Table): body names $tName -- $([IO.Path]::GetFileName($_.File)):$($_.Line)" "FOR $($_.Table)" }) 'db' $true ''
  $pextra = $(if ($procNotScanned) { "$procNotScanned of $($procSet.Count) procedure bodies not scanned" } else { '' })
  Add-Cluster 'db' 'procs' "procedures naming $tName" (@($procRows | ForEach-Object {
      New-Row $_.Decl.Name $_.Decl.File $_.Decl.Line "$($_.Decl.Name): body names $tName -- $([IO.Path]::GetFileName($_.Decl.File)):$($_.Decl.Line)$(if ($_.Decls -gt 1) { " ($($_.Decls) declarations)" })" 'body scan' }) +
      @($procUnscanned | ForEach-Object {
      New-Row $_.Decl.Name $_.Decl.File $_.Decl.Line "$($_.Decl.Name): name contains $tName; body not scanned" $(if ($_.Stale) { '[stale source]' } else { '[body not scanned]' }) })) 'db' $true $pextra
  Add-Cluster 'db' 'indexes' "indexes ON $tName" @($idxRows | ForEach-Object {
      New-Row ([string]$_.name) ([string]$_.path) ([int]$_.line) "$($_.name) ON $tName -- $([IO.Path]::GetFileName([string]$_.path)):$($_.line)" '' }) 'db' $false ''
}

# ---- 8. dot ---------------------------------------------------------------------------------------
$sb = New-Object System.Text.StringBuilder
[void]$sb.AppendLine('digraph consumers {')
[void]$sb.AppendLine('  rankdir=LR; newrank=true; bgcolor="transparent"; compound=true;')
[void]$sb.AppendLine('  nodesep=0.35; ranksep=1.3; splines=spline;')
[void]$sb.AppendLine("  graph [fontname=`"$FontSans`"];")
[void]$sb.AppendLine("  node  [shape=plaintext, fontname=`"$FontMono`", fontsize=14];")
[void]$sb.AppendLine("  edge  [fontname=`"$FontMono`", fontsize=11, color=`"$($PAL.lineInk)`", penwidth=1.5, arrowsize=0.8];")
[void]$sb.AppendLine('')

# the focus: the table (or column) box, anchored on its script declaration
$ftbl = New-Object System.Text.StringBuilder
[void]$ftbl.Append('<TABLE BORDER="0" CELLBORDER="0" CELLSPACING="3" CELLPADDING="5">')
[void]$ftbl.Append("<TR><TD ALIGN=`"LEFT`" BGCOLOR=`"$($PAL.focusHdr)`"><FONT COLOR=`"#FFFFFF`" FACE=`"$FontSans`" POINT-SIZE=`"14`"><B> $(if ($colName) { 'column' } else { 'table' }) &#183; focus </B></FONT></TD></TR>")
$fLabel = $(if ($colName) { "$tName.$colName" } else { $tName })
$fFile = $(if ($colName) { $colFile } else { $tbl.File })
$fLine = $(if ($colName) { $colLine } else { $tbl.Line })
$anchored++
[void]$ftbl.Append("<TR><TD ALIGN=`"LEFT`" HREF=`"$(New-RowHref $fFile $fLine)`" TITLE=`"$(ConvertTo-XmlText "$fLabel -- $([IO.Path]::GetFileName($fFile)):$fLine")`"><FONT COLOR=`"$($PAL.focusInk)`" POINT-SIZE=`"18`"><B>$(ConvertTo-XmlText $fLabel)</B></FONT></TD></TR>")
Add-DisclosureRow $ftbl $declText $PAL.lineInk
if ($colName) {
  # the SHARED label (Get-SqlColumnState): the same words lands-where and feeds-from print
  Add-DisclosureRow $ftbl "column state $(Get-ColumnStateName $cs.State): $($cs.Label)" $PAL.lineInk
} else {
  # "; a quoted column name is not extracted" used to close this row (engine
  # D19). Extractor 1.19 extracts quoted names, so the clause was dropped at the
  # 1.19 re-baseline: a limit the engine has fixed is not claimed.
  Add-DisclosureRow $ftbl "$($tbl.ColumnNames.Count) columns extracted from the newest declaration$(if ($tbl.OlderOnlyColumns.Count) { "; $($tbl.OlderOnlyColumns.Count) more extracted only from an older one ($(@($tbl.OlderOnlyColumns.Keys) -join ', '))" })" $PAL.lineInk
}
if ($nFactSyms -eq 0) {
  Add-DisclosureRow $ftbl "this index has no SQL facts (0 sql_reads / 0 sql_writes)" $PAL.lineInk
}
if ($noSql) {
  Add-DisclosureRow $ftbl 'this index has no SQL at all (no facts, no upper-case SQL literal) -- ask the SERVER index' $PAL.lineInk
}
# R7: BOTH grades, so the gap between fact and literal is visible
Add-DisclosureRow $ftbl ("[certain] by fact: $($certR.Count) reader(s) / $($certW.Count) writer(s); " +
                         "[inferred] by SQL literal: $($infR.Count) reader(s) / $($infW.Count) writer(s)") $PAL.focusInk 12
# item 6: the header counts ROUTINES; a unit-level row is a unit, said apart
if ($unitLevel) {
  Add-DisclosureRow $ftbl ("routines: $($mR.Routines) reading / $($mW.Routines) writing; plus $unitLevel unit(s) with an SQL literal naming $tName " +
                           "outside any routine ($($mR.Units) read / $($mW.Units) write) -- drawn as (unit level) rows, not counted as routines") $PAL.lineInk
}
if ($colName -and $rtIds.Count) {
  Add-DisclosureRow $ftbl ("$($srvCol.Count) of those routines name $colName in a literal; $srvColSilent touch $tName without naming it " +
                           '(SELECT *, positional or built-up SQL) -- every column row is [inferred]') $PAL.lineInk
}
if ($byNameLits -gt 0 -and -not $colName) {
  Add-DisclosureRow $ftbl "[by name]: $byNameLits literal(s) equal to $tName in $($byNameFiles.Count) unit(s)$(if ($byNameSkipped) { " (+$byNameSkipped inside a routine already drawn)" }) -- mentions, not reads" $PAL.lineInk
}
if ($caseOnly.Count -and -not $colName) {
  Add-DisclosureRow $ftbl "$($caseOnly.Count) literal(s) equal $tName only case-insensitively, not drawn: $caseOnlyText" $PAL.lineInk
}
Add-DisclosureRow $ftbl ("index-wide: $nReadFacts read / $nWriteFacts write facts over $nFactSyms routines ($($factReadTables.Count) tables read by fact); " +
                         "$($verbLits.Count) upper-case SQL-verb literals name $($fromJoinTables.Count) tables after FROM/JOIN") $PAL.lineInk
if ($TestHideColumn) { Add-DisclosureRow $ftbl "TEST CHART: $($TestHideColumn -join ', ') taken OUT of the SQL index's extracted columns (-TestHideColumn)" $PAL.lineInk }
Add-DisclosureRow $ftbl "script-derived schema: $($sqlSet.TableCount) tables; $SCHEMA_NOTE" $PAL.lineInk
Add-DisclosureRow $ftbl 'positional Fields[i] reads and SQL built from non-literal pieces are not visible' $PAL.lineInk
[void]$ftbl.Append('</TABLE>')
# Emission ORDER places the database side. With newrank + rank=same, the node
# that appears FIRST in the file lands LOWEST in the rank (measured on a
# three-node graph and on this chart: emitted after the focus the DB clusters
# sat ABOVE it). So: the DB clusters first, in REVERSE so the first of them
# (triggers) ends up nearest the focus; then the focus; then readers/writers.
$sbDb = New-Object System.Text.StringBuilder
$sbRest = New-Object System.Text.StringBuilder
$sbEdges = New-Object System.Text.StringBuilder
$dbNodes = New-Object System.Collections.ArrayList
$mentionNodes = New-Object System.Collections.ArrayList
$ni = 0
$dbC = @($clusters | Where-Object { $_.Side -eq 'db' })
[array]::Reverse($dbC)
$ordered = @($dbC) + @($clusters | Where-Object { $_.Side -ne 'db' })
foreach ($c in $ordered) {
  $ni++
  $nid = "n$ni"
  $target = $(if ($c.Side -eq 'db') { $sbDb } else { $sbRest })
  $ports = Add-RowCluster -Sb $target -Cid "cluster_$($c.Id)_$ni" -Nid $nid -Title $c.Title -Subtitle $c.Subtitle `
             -Rows $c.Rows -Border $c.Border -Fill $c.Fill -Hdr $c.Hdr `
             -RowInk $PAL.rowInk -LineInk $PAL.lineInk -FontSans $FontSans -Style $c.Style
  $style = $(if ($c.Style -like '*dashed*') { ', style="dashed"' } else { '' })
  switch ($c.Side) {
    'left'  { for ($i = 0; $i -lt $ports.Count; $i++) { if ($c.Rows[$i].Href) { [void]$sbEdges.AppendLine("  $($ports[$i]) -> focus [color=`"$($c.Border)`"$style];") } } }
    'right' { for ($i = 0; $i -lt $ports.Count; $i++) { if ($c.Rows[$i].Href) { [void]$sbEdges.AppendLine("  focus -> $($ports[$i]) [color=`"$($c.Border)`", penwidth=2.2$style];") } } }
    'db'    { [void]$dbNodes.Add($nid); [void]$sbEdges.AppendLine("  focus -> $nid [color=`"$($c.Border)`", arrowhead=none$style];") }
    # a neutral dotted line, no arrowhead: the literal MENTIONS the table; it is
    # emitted after the focus in the same rank, so it sits ABOVE it (the DB side
    # is below), on neither the readers' nor the writers' side
    'mention' { [void]$mentionNodes.Add($nid); [void]$sbEdges.AppendLine("  focus -> $nid [color=`"$($c.Border)`", style=`"dotted`", arrowhead=none, label=`" mentions `"];") }
  }
}
[void]$sb.Append($sbDb.ToString())
[void]$sb.AppendLine('  subgraph cluster_focus {')
[void]$sb.AppendLine("    style=`"rounded,filled`"; color=`"$($PAL.focusBorder)`"; fillcolor=`"$($PAL.focusFill)`"; penwidth=3;")
[void]$sb.AppendLine('    label=""; margin=12;')
[void]$sb.AppendLine("    focus [label=<$($ftbl.ToString())>];")
[void]$sb.AppendLine('  }')
[void]$sb.Append($sbRest.ToString())
[void]$sb.AppendLine('')
[void]$sb.Append($sbEdges.ToString())
# BOTTOM = the database side: the same rank as the focus stacks it under it
$sameNodes = @($dbNodes) + @($mentionNodes)
if ($sameNodes.Count) { [void]$sb.AppendLine("  { rank=same; focus; $($sameNodes -join '; '); }") }
[void]$sb.AppendLine('}')

if ([string]::IsNullOrWhiteSpace($OutDir)) { $OutDir = Join-Path $PSScriptRoot '..\scratch' }
$lay = Invoke-DotLayout $sb.ToString() $OutDir ('consumers_' + ($fLabel -replace '[^A-Za-z0-9]', '_'))

function Get-ClusterCount([string] $Id) { $c = @($clusters | Where-Object { $_.Id -eq $Id }); $(if ($c.Count) { $c[0].Count } else { 0 }) }

[pscustomobject]@{
  TestChart        = [bool]$TestHideColumn     # stamped, not only drawn (fix round 2)
  Dot              = $lay.Dot
  Svg              = $lay.Svg
  Plain            = $lay.Plain
  Png              = $lay.Png
  Pdf              = $lay.Pdf
  Table            = $tName
  Column           = $colName
  ColumnOlderOnly  = $colOlder
  ColumnState      = $(if ($cs) { $cs.State } else { '' })
  ColumnLabel      = $(if ($cs) { $cs.Label } else { '' })
  ColumnLine       = $(if ($colName) { "$([IO.Path]::GetFileName($colFile)):$colLine" } else { '' })
  Declarations     = $tbl.DeclCount
  Columns          = $tbl.ColumnNames.Count
  # the bundle header's "reading / writing routines": ROUTINES only (item 6);
  # unit-level rows are counted per UNIT in ReaderUnits / WriterUnits
  Readers          = $mR.Routines
  Writers          = $mW.Routines
  ReaderUnits      = $mR.Units
  WriterUnits      = $mW.Units
  CertainReaders   = $certR.Count
  CertainWriters   = $certW.Count
  InferredReaders  = $infR.Count
  InferredWriters  = $infW.Count
  InferredReaderNames = (@($infR | Where-Object { $_ -gt 0 } | ForEach-Object { $rtInfo[[int]$_].Q } | Sort-Object) -join ',')
  CertainWriterNames  = (@($certW.Keys | ForEach-Object { $rtInfo[[int]$_].Q } | Sort-Object) -join ',')
  UnitLevelUnits   = $unitLevel
  ByNameUnits      = $byNameFiles.Count
  ByNameLiterals   = $byNameLits
  ByNameCaseOnly   = $caseOnlyText
  ByNameLines      = (@($byNameFiles.Keys | ForEach-Object { "$(Get-UnitName $_):$(@($byNameFiles[$_] | ForEach-Object { $_.Line }) -join '+')" }) -join ',')
  Triggers         = $trigFor.Count
  TriggerNames     = (@($trigFor | ForEach-Object { "$($_.Name)@$([IO.Path]::GetFileName($_.File)):$($_.Line)" }) -join ',')
  OtherTriggers    = $trigOther.Count
  Procedures       = $procRows.Count
  ProcedureNames   = (@($procRows | ForEach-Object { $_.Decl.Name } | Sort-Object) -join ',')
  ProcsUnscanned   = $procUnscanned.Count
  ProcBodies       = "$($procSet.BodiesFound)/$($procSet.Count)"
  Indexes          = $idxRows.Count
  ServerRoutines   = $srvCol.Count
  ServerRoutineNames = (@($srvCol.Keys | ForEach-Object { $rtInfo[[int]$_].Q } | Sort-Object) -join ',')
  SilentRoutines   = $srvColSilent
  ColumnTriggers   = $trigCol.Count
  ColumnTriggerNames = (@($trigCol | ForEach-Object { $_.Name }) -join ',')
  ColumnTriggersStale = $trigColStale.Count
  ColumnTriggersNoBody = $trigColNoBody.Count
  ColumnProcedures = $procCol.Count
  ColumnIndexes    = $idxCol.Count
  IndexBindings    = $bindAll
  DrawnBindings    = $bindDrawn.Count
  DrawnBindingRows = (@($bindDrawn | ForEach-Object { "$([IO.Path]::GetFileName($_.Dfm)):$($_.Line):$($_.Control)" }) -join ',')
  BindingsElsewhere = (@($bindElsewhere.Values) | Measure-Object -Sum).Sum
  BindingsUnresolved = (@($bindUnresolved.Values) | Measure-Object -Sum).Sum
  BindingsStale    = $bindStale
  IndexReadFacts   = $nReadFacts
  IndexWriteFacts  = $nWriteFacts
  IndexFactSymbols = $nFactSyms
  IndexFactReadTables = $factReadTables.Count
  IndexVerbLiterals = $verbLits.Count
  IndexFromJoinTables = $fromJoinTables.Count
  NoSqlFacts       = ($nFactSyms -eq 0)
  NoSql            = $noSql
  Clusters         = $clusters.Count + 1
  ClickTargets     = $lay.Anchors
  Expected         = $anchored
  AllClickable     = ($lay.Anchors -ge $anchored)
}
