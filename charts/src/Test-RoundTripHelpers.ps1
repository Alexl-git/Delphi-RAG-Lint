<#
  Test-RoundTripHelpers.ps1 -- measures what the round-trip question stands on
  and RETURNS the values; Test-Emitters.ps1 pins them (the Test-FeedsFromHelpers
  pattern: dot-sourcing Emit-Common into the gate would put every helper and
  its $DbPath contract into the gate's scope). Nothing here writes a database.

  Section 1 is the RE-MEASURE the plan's first task asked for: the facts the
  walk assumes (an unbound GetTable, the post-commit broadcast, the Exit lines
  the 12 golden guards hang on, the dangling-datasource re-point) as strings a
  drift will break loudly. Later sections (Form A round trip, the chain, the
  shim, the golden matcher) are appended by their tasks.
#>
[CmdletBinding()]
param(
  [string] $DbCli  = (Join-Path $PSScriptRoot '..\scratch\db\CLIENT-Micronite2027.sqlite'),
  [string] $DbSrv  = (Join-Path $PSScriptRoot '..\scratch\db\SERVER-MicroniteMW1Service.sqlite'),
  [string] $DbSql  = (Join-Path $PSScriptRoot '..\scratch\db\SQL-drag-lint-sql.sqlite'),
  [Parameter(Mandatory)][string] $OutDir,
  [string] $Engine = 'C:\Projects\Delphi-RAG-lint\third_party\dll-win64\drag-lint.exe',
  [string] $Dot    = 'C:\Projects\GraphWiz\Graphviz-16.1.0-win64\bin\dot.exe'
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Emit-Common.ps1')

$work = Join-Path $OutDir 'roundtrip'
New-Item -ItemType Directory -Force $work | Out-Null
$res = [ordered]@{}
$VM  = 'Blueprint4.ViewModel.TBlueprint_ViewModel'

# Runs one query against one clone. Invoke-IndexQuery reads $DbPath from the
# caller's scope, so this function's local IS the rebinding. The unary comma
# keeps a 0/1-row result an array on the way out (the Invoke-IndexQuery contract).
function Rows([string] $Db, [string] $Sql) { $DbPath = Get-CloneDb $Db; $r = Invoke-IndexQuery $Sql; , $r }
function Join-Rows($R, [scriptblock] $F) { (@($R | ForEach-Object $F)) -join ',' }

# ---- 1. the re-measure --------------------------------------------------------------
# M1 GetTable: every call ref is UNBOUND (symbol_id NULL) and exactly one routine implements it
$m1 = Rows $DbSrv "SELECT f.path AS path, r.start_line AS line, COALESCE(r.symbol_id, -1) AS sid FROM refs r JOIN files f ON f.id = r.file_id WHERE r.kind = 'call' AND r.name_text = 'GetTable' ORDER BY f.path, r.start_line"
$res.GetTableCalls = Join-Rows $m1 { "$([IO.Path]::GetFileName([string]$_.path)):$($_.line):$($_.sid)" }
$m1i = Rows $DbSrv "SELECT s.qualified_name AS q, s.impl_start_line AS l FROM symbols s WHERE s.name = 'GetTable' AND s.kind = 'method' AND s.impl_start_line > 0 ORDER BY s.qualified_name"
$res.GetTableImpls = Join-Rows $m1i { "$($_.q):$($_.l)" }
$m1v = Rows $DbSrv "SELECT s.kind AS k, s.signature AS sig, s.start_line AS l FROM symbols s WHERE s.name IN ('GDatasetsDef', 'GBroadcastServer') ORDER BY s.name"
$res.GlobalVars = Join-Rows $m1v { "$($_.k):$($_.sig):$($_.l)" }

# M2 the post-commit broadcast
$m2 = Rows $DbSrv "SELECT f.path AS path, r.start_line AS line, COALESCE(r.symbol_id, -1) AS sid, e.name AS encl FROM refs r JOIN files f ON f.id = r.file_id LEFT JOIN symbols e ON e.id = r.enclosing_symbol_id WHERE r.kind = 'call' AND r.name_text = 'PushTableChanged' ORDER BY f.path, r.start_line"
$res.PushCalls = Join-Rows $m2 { "$([IO.Path]::GetFileName([string]$_.path)):$($_.line):$($_.sid):$($_.encl)" }
$m2i = Rows $DbSrv "SELECT s.qualified_name AS q, s.impl_start_line AS l, s.start_line AS d FROM symbols s WHERE s.name = 'PushTableChanged' AND s.impl_start_line > 0"
$res.PushImpl = Join-Rows $m2i { "$($_.q):$($_.l):decl$($_.d)" }

# M3 the Exit lines of the six routines the 12 golden guards live in
$routines = @(
  @{ Db = $DbCli; Q = "$VM.DoAfterPostOperation" }, @{ Db = $DbCli; Q = "$VM.SendDeltaOperation" }, @{ Db = $DbCli; Q = "$VM.LoadOneTable" },
  @{ Db = $DbSrv; Q = 'uGenericTableRoute.TGenericTableRoute.HandleDelta' }, @{ Db = $DbSrv; Q = 'uGenericTableRoute.TGenericApplyContext.HandleUpdateRecord' },
  @{ Db = $DbSrv; Q = 'uPipeSessionBuilder.TPipeSessionBuilder.HandleTableLoad' })
$parts = @()
foreach ($rt in $routines) {
  $x = Rows $rt.Db "SELECT r.start_line AS line FROM refs r JOIN symbols e ON e.id = r.enclosing_symbol_id WHERE e.qualified_name = '$(ConvertTo-SqlText $rt.Q)' AND r.kind = 'call' AND r.name_text = 'Exit' ORDER BY r.start_line"
  $parts += "$(($rt.Q -split '\.')[-1])=$((@($x | ForEach-Object { $_.line })) -join '/')"
}
$res.ExitLines = $parts -join ';'

# M4 the dangling-datasource re-point and the chain behind it (spec section 3)
$m4 = Rows $DbCli "SELECT sl.owner_name AS p, sl.text AS t, sl.start_line AS l FROM string_literals sl JOIN symbols c ON c.id = sl.symbol_id WHERE sl.kind = 'dfm-prop' AND c.qualified_name LIKE 'frmBlueprint4.%dxDBGrid1OperationV' AND sl.owner_name = 'DataController.DataSource'"
$res.DfmDataSource = Join-Rows $m4 { "$($_.t)@$($_.l)" }
$m4m = Rows $DbCli "SELECT COUNT(*) AS n FROM symbols WHERE UPPER(name) = 'BLUEPRINT4_MODEL'"
$res.DfmModuleSymbols = [int]$m4m[0].n
# The RE-POINT only: the member ref standing right of a `.DataSource` member ref on its
# line (`<grid>.DataController.DataSource:= X.pdsrOperation`). Without that test the
# query returns all 11 `FBlueprint_ViewModel.pdsrOperation` sites of Blueprint4.pas --
# the other 10 READ `.DataSet` through it (measured 2026-09-28, pre-1.9 and 1.9 clones alike).
$m4r = Rows $DbCli "SELECT r.start_line AS line, r.receiver_text AS rt, t.kind AS tk, t.qualified_name AS tq, t.start_line AS tl, t.prop_access AS acc FROM refs r JOIN files f ON f.id = r.file_id LEFT JOIN symbols t ON t.id = r.symbol_id WHERE f.path LIKE '%\Blueprint4.pas' AND r.kind = 'member-access' AND r.name_text = 'pdsrOperation' AND EXISTS (SELECT 1 FROM refs d WHERE d.file_id = r.file_id AND d.start_line = r.start_line AND d.kind = 'member-access' AND d.name_text = 'DataSource' AND d.start_col < r.start_col) ORDER BY r.start_line"
$res.RePointMember = Join-Rows $m4r { "$($_.line):$($_.rt):$($_.tk):$($_.tq):$($_.tl):$($_.acc)" }
$m4g = Rows $DbCli "SELECT s.qualified_name AS q, s.impl_start_line AS l FROM symbols s WHERE s.name = 'GetpdsrOperation' AND s.kind = 'method' AND s.impl_start_line > 0"
$res.AccessorImpls = Join-Rows $m4g { "$($_.q):$($_.l)" }
$m4b = Rows $DbCli "SELECT r.name_text AS n, COALESCE(r.symbol_id, -1) AS sid FROM refs r JOIN files f ON f.id = r.file_id WHERE f.path LIKE '%\Blueprint4.ViewModel.pas' AND r.start_line = 1263 AND r.kind = 'read' AND r.name_text <> 'Result'"
$res.AccessorReads = Join-Rows $m4b { "$($_.n):$($_.sid)" }
$m4d = Rows $DbCli "SELECT r.start_line AS line, e.name AS encl FROM refs r JOIN files f ON f.id = r.file_id LEFT JOIN symbols e ON e.id = r.enclosing_symbol_id WHERE f.path LIKE '%\Blueprint4.ViewModel.pas' AND r.kind = 'member-access' AND r.name_text = 'DataSet' AND r.receiver_text = 'FDsrOperation'"
$res.DataSetSites = Join-Rows $m4d { "$($_.line):$($_.encl)" }
$m4f = Rows $DbCli "SELECT s.name AS n, s.start_line AS l, s.signature AS sig FROM symbols s WHERE s.qualified_name IN ('$VM.FMTOperation', '$VM.FDsrOperation') ORDER BY s.name"
$res.AnchorFields = Join-Rows $m4f { "$($_.n):$($_.sig):$($_.l)" }
$m4t = Rows $DbCli "SELECT sl.start_line AS l, e.name AS encl FROM string_literals sl JOIN files f ON f.id = sl.file_id JOIN refs r ON r.file_id = sl.file_id AND r.start_line = sl.start_line AND r.name_text = 'FMTOperation' LEFT JOIN symbols e ON e.id = r.enclosing_symbol_id WHERE f.path LIKE '%\Blueprint4.ViewModel.pas' AND sl.kind = 'literal' AND sl.text = 'OPERAT' GROUP BY sl.start_line ORDER BY sl.start_line"
$res.TableLiterals = Join-Rows $m4t { "$($_.l):$($_.encl)" }
$m4s = Rows $DbSql "SELECT s.qualified_name AS q, s.start_line AS l, f.path AS p FROM symbols s JOIN files f ON f.id = s.file_id WHERE s.kind = 'sql_column' AND s.qualified_name = 'OPERAT.NAME' ORDER BY f.mtime_unix DESC"
$res.SqlColumn = Join-Rows $m4s { "$([IO.Path]::GetFileName([string]$_.p)):$($_.l)" }

# M5 the ALSO basis: callers of the traced sender, and every fill line carrying the table literal
$m5 = Rows $DbCli "SELECT e.name AS n, r.start_line AS line FROM call_edges ce JOIN refs r ON r.id = ce.ref_id JOIN symbols e ON e.id = r.enclosing_symbol_id WHERE ce.target_symbol_id = (SELECT id FROM symbols WHERE qualified_name = '$VM.SendDeltaOperation' AND kind = 'method') ORDER BY r.start_line"
$res.SenderCallers = Join-Rows $m5 { "$($_.n):$($_.line)" }
$m5f = Rows $DbCli "SELECT sl.start_line AS l, e.name AS encl, t.name AS tgt FROM string_literals sl JOIN files f ON f.id = sl.file_id JOIN refs r ON r.file_id = sl.file_id AND r.start_line = sl.start_line AND r.kind = 'call' JOIN call_edges ce ON ce.ref_id = r.id JOIN symbols t ON t.id = ce.target_symbol_id LEFT JOIN symbols e ON e.id = r.enclosing_symbol_id WHERE f.path LIKE '%\Blueprint4.ViewModel.pas' AND sl.kind = 'literal' AND sl.text = 'OPERAT' AND EXISTS (SELECT 1 FROM refs d WHERE d.file_id = sl.file_id AND d.start_line = sl.start_line AND d.name_text = 'FMTOperation') GROUP BY sl.start_line, t.name ORDER BY sl.start_line"
$res.FillLines = Join-Rows $m5f { "$($_.l):$($_.encl)->$($_.tgt)" }

# M6 the server dispatch arms: the constant's read, then the first call after it whose
# call_edges target is declared OUTSIDE Pipes.Commands (the spec's "first call after it"
# picks the unit-local ParseTableFromPayload for cmdTableLoad -- measured, hence the filter)
$arms = @()
foreach ($cmd in 'cmdDelta', 'cmdTableLoad') {
  $a = Rows $DbSrv "SELECT r.start_line AS line, r.enclosing_symbol_id AS eid, r.file_id AS fid FROM refs r JOIN symbols t ON t.id = r.symbol_id JOIN files f ON f.id = r.file_id WHERE t.kind = 'enum_value' AND t.name = '$cmd' AND f.path LIKE '%\Pipes.Commands.pas'"
  $c = Rows $DbSrv "SELECT r.start_line AS line, t.qualified_name AS tq, t.impl_start_line AS ti FROM refs r JOIN call_edges ce ON ce.ref_id = r.id JOIN symbols t ON t.id = ce.target_symbol_id WHERE r.enclosing_symbol_id = $([int]$a[0].eid) AND r.start_line > $([int]$a[0].line) AND t.file_id <> $([int]$a[0].fid) ORDER BY r.start_line, r.start_col LIMIT 1"
  $arms += "$cmd@$($a[0].line)->$($c[0].tq)@$($c[0].line):impl$($c[0].ti)"
}
$res.DispatchArms = $arms -join ';'
$res.PipesCommandsOnClient = [int](Rows $DbCli "SELECT COUNT(*) AS n FROM files WHERE path LIKE '%\Pipes.Commands.pas'")[0].n
$m6h = Rows $DbSrv "SELECT s.qualified_name AS q, s.impl_start_line AS l, c.heritage AS h FROM symbols s JOIN symbols c ON c.id = s.parent_id WHERE s.name IN ('HandleDelta', 'HandleTableLoad') AND s.kind = 'method' AND s.impl_start_line > 0 ORDER BY s.qualified_name"
$res.HandlerImpls = Join-Rows $m6h { "$($_.q):$($_.l):[$($_.h)]" }

# M7 the Firebird snapshot tables the STOPS steps name
$res.FbRows = "$((Rows $DbCli 'SELECT (SELECT COUNT(*) FROM fb_datasets) AS d, (SELECT COUNT(*) FROM fb_field_info) AS f')[0].d)/$((Rows $DbCli 'SELECT (SELECT COUNT(*) FROM fb_field_info) AS f')[0].f)/" +
             "$((Rows $DbSrv 'SELECT (SELECT COUNT(*) FROM fb_datasets) AS d')[0].d)/$((Rows $DbSrv 'SELECT (SELECT COUNT(*) FROM fb_field_info) AS f')[0].f)"

# M8 freshness of the golden path's files TODAY (informational, like DiskStaleCli -- never pinned)
$golden = @(
  @{ Db = $DbCli; P = 'C:\Projects\DB\ORM3\CLIENT\Blueprint4.ViewModel.pas' }, @{ Db = $DbCli; P = 'C:\Projects\DB\ORM3\CLIENT\Blueprint4.pas' },
  @{ Db = $DbCli; P = 'C:\Projects\DB\ORM3\CLIENT\Blueprint4.dfm' }, @{ Db = $DbCli; P = 'C:\Projects\DB\ORM3\CLIENT\Blueprint4.Interfaces.pas' },
  @{ Db = $DbSrv; P = 'C:\Projects\DB\ORM3\SERVER\uGenericTableRoute.pas' }, @{ Db = $DbSrv; P = 'C:\Projects\DB\ORM3\SERVER\uPipeSessionBuilder.pas' },
  @{ Db = $DbSrv; P = 'C:\Projects\DB\ORM3\SERVER\uDatasetsDef.pas' }, @{ Db = $DbSrv; P = 'C:\Projects\DB\ORM3\SERVER\uBroadcastServer.pas' },
  @{ Db = $DbSrv; P = 'C:\Projects\DB\ORM3\COMMON\Pipes.Protocol.pas' })
$stale = @()
foreach ($g in $golden) { $DbPath = Get-CloneDb $g.Db; if (-not (Test-SourceFresh $g.P)) { $stale += [IO.Path]::GetFileName($g.P) } }
$res.GoldenStaleToday = ($stale -join ',')

# M9 holdout candidates (informational, NOT pinned: the owner picks -- spec AC-16)
$m9 = Rows $DbCli @"
SELECT c.name AS n, (SELECT x.text FROM string_literals x WHERE x.kind = 'dfm-prop' AND x.symbol_id = c.id AND x.owner_name = 'DataBinding.FieldName') AS fld
  FROM symbols c
 WHERE c.kind = 'component' AND c.parent_id = (SELECT id FROM symbols WHERE kind = 'component' AND qualified_name LIKE 'frmBlueprint4.%dxDBGrid1FtrsV')
   AND NOT EXISTS (SELECT 1 FROM string_literals v WHERE v.kind = 'dfm-prop' AND v.symbol_id = c.id AND v.owner_name = 'Visible' AND v.text = 'False')
   AND NOT EXISTS (SELECT 1 FROM string_literals v WHERE v.kind = 'dfm-prop' AND v.symbol_id = c.id AND v.owner_name = 'Options.Editing' AND v.text = 'False')
 ORDER BY c.start_line
"@
$res.HoldoutCandidates = Join-Rows $m9 { "$($_.n)=$($_.fld)" }

[pscustomobject]$res
