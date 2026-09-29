<#
  Test-Task0Helpers.ps1 -- measures the shared helpers that the last four
  diagram verbs (exception-paths, consumers, feeds-from, lands-where) build on,
  and RETURNS the numbers. It asserts nothing itself: Test-Emitters.ps1 calls it
  and pins every number, so a drift fails the gate with the gate's own codes.

  A separate script rather than inline gate code because the helpers are
  dot-sourced, and dot-sourcing Emit-Common into the gate would put every helper
  (and its $DbPath/$Engine contract) into the gate's scope.

  Nothing here writes to a database. The stale-source checks MANUFACTURE a stale
  file -- a copy of an indexed source with one line changed, handed to the
  helpers through -SourceOverride -- so they never depend on the disk happening
  to differ from the index (controller ruling R4).
#>
[CmdletBinding()]
param(
  [string] $DbCli  = (Join-Path $PSScriptRoot '..\scratch\db\CLIENT-Micronite2027.sqlite'),
  [string] $DbSql  = (Join-Path $PSScriptRoot '..\scratch\db\SQL-drag-lint-sql.sqlite'),
  [Parameter(Mandatory)][string] $OutDir,
  [string] $Engine = 'C:\Projects\Delphi-RAG-lint\third_party\dll-win64\drag-lint.exe'
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Emit-Common.ps1')

$work = Join-Path $OutDir 'task0'
New-Item -ItemType Directory -Force $work | Out-Null
$res = [ordered]@{}

# ---- 1. the collapsed SQL table set ---------------------------------------------
$S = Get-SqlTableSet $DbSql
$res.SqlTables       = $S.TableCount
$res.SqlDeclarations = $S.DeclarationCount
$res.SqlCollapsed    = $S.CollapsedNames
$res.SqlProcedures   = "$($S.ProcedureCount)/$($S.ProcedureDeclCount)"
$res.FoldersColumns  = $S.Tables['FOLDERS'].ColumnNames.Count
$res.FoldersFrom     = [IO.Path]::GetFileName($S.Tables['FOLDERS'].File)
$res.CausfailColumns = (@($S.Tables['CAUSFAIL'].ColumnNames) | Sort-Object) -join ','

# ---- 2. trigger bodies -------------------------------------------------------------
$T = Get-SqlTriggerSet $DbSql
$res.Triggers        = $T.Count
$res.TriggerBodies   = $T.BodiesFound
$res.TriggerStale    = $T.Stale
$res.TriggerForKnown = $T.ForKnownTable
$res.TriggerNewOld   = $T.WithNewOld
$res.TriggerOther    = (@($T.Triggers | Where-Object { $_.OtherTables.Count } |
                          ForEach-Object { "$($_.Name)>$($_.OtherTables -join '+')" }) | Sort-Object) -join ','
$res.CausfailTriggers = (@($T.Triggers | Where-Object { $_.Table -eq 'CAUSFAIL' } |
                           ForEach-Object { "$($_.Name)=$($_.Columns -join '+')" }) | Sort-Object) -join ','

# ---- 3. the verb scan, on the cases P23 names -------------------------------------
$cases = [ordered]@{
  'SELECT * FROM CAUSFAIL WHERE ID = 1'          = 'FROM CAUSFAIL'
  'Cannot Load from CAUSFAIL'                     = ''            # lower-case verb: prose
  'SELECT NEXT VALUE FOR G FROM RDB$DATABASE'     = ''            # not a script table
  'SELECT DISTINCT P FROM ('                      = ''
  'DELETE FROM FOLDERS WHERE FLDRID = :F'         = 'DELETE FROM FOLDERS'
  'FROM FIB$FIELDS_INFO'                          = 'FROM FIB$FIELDS_INFO'   # the `$` is part of the name (P21)
  'UPDATE DRA1 SET X = 1'                         = 'UPDATE DRA1'
  'FROM CAUSFAILX'                                = ''            # word-bounded
  'SELECT A FROM CAUSFAIL C JOIN FOLDERS F ON 1=1' = 'FROM CAUSFAIL|JOIN FOLDERS'
}
$bad = New-Object System.Collections.ArrayList
$ran = 0
foreach ($k in $cases.Keys) {
  $ran++
  # assigned DIRECTLY: @(Get-SqlVerbTables ...) nests the `, $array` return and
  # turns an empty answer into one blank row -- which is how this check first failed.
  $v = Get-SqlVerbTables $k $S
  $got = ($v | ForEach-Object { "$($_.Verb) $($_.Name)" }) -join '|'
  if ($got -ne $cases[$k]) { [void]$bad.Add("[$k] expected '$($cases[$k])' got '$got'") }
}
# VerbCases is RETURNED so the gate can pin how many cases ran: a failure list
# that is empty because nothing ran must not read as nine passes.
$res.VerbCases        = $ran        # counted in the loop: cases EXECUTED, not table size
$res.VerbCaseFailures = $bad.ToArray()

# ---- 4. Get-SourceContext on the exception candidates (P2) ------------------------
# The kind is the pre-filter, the stripped source token is the classifier (R1).
$DbPath = Get-CloneDb $DbCli
$cand = Get-AllIndexRows @"
SELECT r.id AS id, r.kind AS kind, r.name_text AS name, r.start_line AS line,
       r.start_col AS col, r.end_col AS ecol, f.path AS path
  FROM refs r JOIN files f ON f.id = r.file_id
 WHERE r.name_text GLOB 'E[A-Z]*[a-z]*' OR r.name_text = 'Exception'
"@ 'r.id'
$raise = 0; $handle = 0; $stale = 0; $mis = 0
foreach ($r in $cand) {
  $c = Get-SourceContext ([string]$r.path) ([int]$r.line) ([int]$r.col) ([int]$r.ecol - [int]$r.col)
  if ($c.Stale) { $stale++; continue }
  if ($c.Token -ne [string]$r.name) { $mis++ }
  if ($r.kind -eq 'read'     -and $c.Before -match '\braise\s*$') { $raise++ }
  if ($r.kind -eq 'type_use' -and $c.Before -match '\bon(\s+[A-Za-z_][A-Za-z0-9_]*\s*:)?\s*$') { $handle++ }
}
$res.ExcCandidates = $cand.Count
$res.ExcRaise      = $raise
$res.ExcHandle     = $handle
$res.ExcStale      = $stale
$res.ExcTokenMiss  = $mis

# Informational only, NOT pinned: how many CLIENT files differ from disk today.
# It depends on the live source tree, which the owner edits; the pinned
# stale-source checks below manufacture their mismatch instead.
$diskStale = New-Object System.Collections.ArrayList
foreach ($p in @((Get-IndexedFileShas).Keys)) {
  if (-not (Test-SourceFresh $p)) { [void]$diskStale.Add([IO.Path]::GetFileName($p)) }
}
$res.DiskStaleCli = ($diskStale | Sort-Object) -join ','

# ---- 5. the datasource chain, every TDataSource on CLIENT ------------------------
$ds = Get-AllIndexRows @"
SELECT c.id AS id, c.name AS name, f.path AS path
  FROM symbols c JOIN files f ON f.id = c.file_id
 WHERE c.kind = 'component' AND c.signature = 'TDataSource'
"@ 'c.id'
$chains = @(foreach ($d in $ds) { Get-DataSourceChain ([string]$d.path) ([string]$d.name) $S })
$res.DsTotal     = $chains.Count
$res.DsDfmWired  = @($chains | Where-Object { @($_.DataSetSites | Where-Object { $_.Kind -eq 'dfm' }).Count }).Count
$res.DsCodeSite  = @($chains | Where-Object { @($_.DataSetSites | Where-Object { $_.Kind -ne 'dfm' }).Count }).Count
$res.DsAssigned  = @($chains | Where-Object { @($_.DataSetSites | Where-Object { $_.Kind -eq 'assign' }).Count }).Count
$res.DsOne       = @($chains | Where-Object { $_.Grade -eq 'one-table' }).Count
$res.DsMany      = @($chains | Where-Object { $_.Grade -in 'many', 'by-columns' }).Count
$res.DsNone      = @($chains | Where-Object { $_.Grade -eq 'none' }).Count
$res.DsByColumns = @($chains | Where-Object { $_.Grade -eq 'by-columns' }).Count
$res.DsGrades    = (@($chains | Group-Object Grade | Sort-Object Name | ForEach-Object { "$($_.Name)=$($_.Count)" })) -join ','
# every non-resolving chain must say why, and every chain must end in a hop
$res.DsNoReason  = @($chains | Where-Object { -not $_.ResolvedTable -and -not $_.StopReason }).Count
$res.DsNoHops    = @($chains | Where-Object { @($_.Hops).Count -eq 0 }).Count
$cf = @($chains | Where-Object { $_.DsName -eq 'dsrCausFail' })[0]
$res.CausFailChain = "$($cf.Grade):$($cf.ResolvedTable):$(@($cf.Hops | ForEach-Object { $_.Grade }) -join '>')"

# ---- 6. dangling designer references and their re-pointing in code ---------------
$pairs = Get-AllIndexRows @"
SELECT DISTINCT f.path AS path, sl.text AS ds
  FROM string_literals sl JOIN files f ON f.id = sl.file_id
 WHERE sl.kind = 'dfm-prop' AND sl.text LIKE '%.%'
   AND sl.owner_name IN ('DataSource','DataBinding.DataSource','DataController.DataSource')
"@ 'f.path, sl.text'
$rows = 0; $dang = 0; $viaRecv = 0; $viaAny = 0
foreach ($p in $pairs) {
  $c = Get-DataSourceChain ([string]$p.path) ([string]$p.ds) $S
  foreach ($ctl in @($c.Controls | Where-Object { -not $_.IsLookup })) {
    $rows++
    if ($c.Dangling) { $dang++ }
    $hits = @($c.RePointedAt | Where-Object { $_.Control -eq $ctl.Control })
    if (@($hits | Where-Object { $_.ControlFrom -eq 'receiver' }).Count) { $viaRecv++ }
    if ($hits.Count) { $viaAny++ }
  }
}
$res.DanglingRows     = $rows
$res.DanglingMissing  = $dang
$res.RePointedRecv    = $viaRecv
$res.RePointedAny     = $viaAny

# ---- 7. manufactured stale sources (N21 at helper level) ----------------------------
$pas = [string](@((Get-IndexedFileShas).Keys | Where-Object { $_ -like '*\uCausFailForm.pas' })[0])
$lines = [IO.File]::ReadAllLines($pas)
$same = Join-Path $work 'fresh_uCausFailForm.pas'
$chg  = Join-Path $work 'stale_uCausFailForm.pas'
[IO.File]::WriteAllBytes($same, [IO.File]::ReadAllBytes($pas))
$lines[125] = $lines[125] + ' '        # line 126: one trailing blank, nothing else
[IO.File]::WriteAllText($chg, (($lines -join "`r`n") + "`r`n"), (New-Object Text.ASCIIEncoding))

$res.OverrideSameFresh  = Test-SourceFresh $pas @{ $pas = $same }
$res.OverrideStaleFresh = Test-SourceFresh $pas @{ $pas = $chg }
$sc = Get-DataSourceChain $pas.Replace('.pas', '.dfm') 'dsrCausFail' $S @{ $pas = $chg }
$res.StaleChain      = "$($sc.Grade):$([string]$sc.ResolvedTable):$(@($sc.DataSetSites | ForEach-Object { $_.Kind }) -join ',')"
$res.StaleClassified = @($sc.DataSetSites | Where-Object { $_.Kind -in 'assign', 'read' }).Count
$ctx = Get-SourceContext $pas 125 15 7 @{ $pas = $chg }
$res.StaleContext    = "$($ctx.Stale):$($null -eq $ctx.Before):$($null -eq $ctx.After)"
$fc = Get-DataSourceChain $pas.Replace('.pas', '.dfm') 'dsrCausFail' $S @{ $pas = $same }
$res.FreshCopyChain  = "$($fc.Grade):$($fc.ResolvedTable)"

# the SQL side: one changed line in MS5.SQL stales exactly MS5's triggers
$ms5 = [string](@($T.Triggers | Where-Object { $_.File -like '*\MS5.SQL' })[0].File)
$sl = [IO.File]::ReadAllLines($ms5)
$sl[0] = $sl[0] + ' '
$ms5c = Join-Path $work 'stale_MS5.SQL'
[IO.File]::WriteAllText($ms5c, (($sl -join "`r`n") + "`r`n"), (New-Object Text.ASCIIEncoding))
$T2 = Get-SqlTriggerSet $DbSql @{ $ms5 = $ms5c }
$res.SqlStaleTriggers = $T2.Stale
$res.SqlStaleScanned  = @($T2.Triggers | Where-Object { $_.Stale -and $_.Found }).Count
$res.Ms5Triggers      = @($T.Triggers | Where-Object { $_.File -eq $ms5 }).Count

[pscustomobject]$res
