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

# ---- 2. the Form A model round trip (AC-2, AC-3, AC-4, AC-11, AC-12) ------------------
. (Join-Path $PSScriptRoot 'Trace.FormA.ps1')
$T = New-Trace 'OPERAT.NAME' 'How OPERAT.NAME reaches frmBlueprint4.dxDBGrid1OperationVName and goes back' 'frmBlueprint4.dxDBGrid1OperationVName' `
               'Micronite2027 + MicroniteMW1Service + SQL' '2026-09-24' 'New-DiagramArtifact.ps1 -Question round-trip -Target frmBlueprint4.dxDBGrid1OperationVName' 'client -> pipe -> server -> database'
$sA = Add-TraceSection $T 'ANCHOR'
$s1 = New-TraceStep 'step' 'BINDS dxDBGrid1OperationVName : TcxGridDBColumn ONTO Name' 'Blueprint4.dfm:4534' '' '' 'DataBinding.FieldName'
[void]$s1.Children.Add((New-TraceFacet 'VIA' 'dxDBGrid1OperationV.DataController.DataSource = Blueprint4_Model.dsrOperation' 'Blueprint4.dfm:4497' 'dangling: module Blueprint4_Model is declared nowhere in this index'))
[void]$sA.Items.Add($s1)
[void]$sA.Items.Add((New-TraceStep 'step' 'CALLS GetpdsrOperation' 'Blueprint4.ViewModel.pas:1263' 'by name' 'TBlueprint_ViewModel' '' 'in-class-field-reads'))
$sW = Add-TraceSection $T 'WRITE'
$s3 = New-TraceStep 'step' 'CALLS DoAfterPostOperation' 'Blueprint4.ViewModel.pas:3948' '' 'Create' 'from :639'
[void]$s3.Children.Add((New-TraceCond 'UNLESS' 'FSuppressEvents' 'Blueprint4.ViewModel.pas:3950' '' 'E1'))
[void]$sW.Items.Add($s3)
$s4 = New-TraceStep 'step' "RECEIVES rspOK" 'Blueprint4.ViewModel.pas:3990' '' 'SendDeltaOperation'
[void]$s4.Children.Add((New-TraceCond 'UNLESS' '(GLE <> ERROR_SUCCESS) or (TCommandID(RspHdr.CommandID) <> rspOK)' 'Blueprint4.ViewModel.pas:3990' 'else FMTOperation.CancelUpdates @Blueprint4.ViewModel.pas:3999' 'E1'))
[void]$sW.Items.Add($s4)
$x = New-TraceStep 'crosses' 'process boundary' 'Blueprint4.ViewModel.pas:3985' '' 'SendDeltaOperation'
[void]$x.Children.Add((New-TraceFacet 'FROM' 'Micronite2027' '' 'the index this side was read from'))
[void]$x.Children.Add((New-TraceFacet 'WITH' 'cmdDelta "TABLE=OPERAT|" + sfBinary stream' 'Blueprint4.ViewModel.pas:3985'))
[void]$x.Children.Add((New-TraceFacet 'CONTRACT' 'Pipes.Protocol.TCommandID.cmdDelta' 'Pipes.Protocol.pas:55'))
[void]$sW.Items.Add($x)
$sD = Add-TraceSection $T 'DATABASE'
[void]$sD.Items.Add((New-TraceStep 'stops' 'the UPDATE statement for OPERAT is FDef.UpdateSQL, loaded from FIB$DATASETS_INFO rows the clone does not hold (fb_datasets is empty)' 'uGenericTableRoute.pas:210' '' 'HandleUpdateRecord' '' 'E4'))
# the actor goes through -Actor: the model refuses a text that BEGINS with an actor word (it would read back as one)
[void]$sD.Items.Add((New-TraceStep 'step' 'WRITES OPERAT.NAME' 'MS1.SQL:2808' 'inferred' '' 'column NAME of OPERAT in the newest declaration' 'E4' 'SERVER'))
$text1 = Write-FormA $T
[IO.File]::WriteAllText((Join-Path $work 'model.dlgraph'), $text1, (New-Object Text.ASCIIEncoding))
$res.FormACounts = "$((Get-TraceCounts $T).Steps)/$((Get-TraceCounts $T).Conditions)/$((Get-TraceCounts $T).Crossings)/$((Get-TraceCounts $T).Unresolved)"
$res.FormAEnd = @($text1 -split "\r\n" | Where-Object { $_ -like 'END TRACE*' })[0]   # @(): one match is a string, and [0] of a string is its first char
$res.FormAAnchors = Get-TraceAnchors $T
# AC-2: parse it back, write it again, byte for byte
$T2 = Read-FormA $text1
$text2 = Write-FormA $T2
$rtA = $text1 -split "\r\n"; $rtB = $text2 -split "\r\n"; $rtK = 0
while ($rtK -lt $rtA.Count -and $rtK -lt $rtB.Count -and $rtA[$rtK] -ceq $rtB[$rtK]) { $rtK++ }
$res.FormARoundTrip = $(if ($text1 -ceq $text2) { 'identical' } else { "differs at line $($rtK + 1)" })
$res.FormARoundTripLines = "$($rtA.Count)/$($rtB.Count)"
# AC-4: bytes
$bytes = [IO.File]::ReadAllBytes((Join-Path $work 'model.dlgraph'))
$res.FormABytes = "$(@($bytes | Where-Object { $_ -ne 0x0D -and $_ -ne 0x0A -and ($_ -lt 0x20 -or $_ -gt 0x7E) }).Count)/$(([regex]::Matches($text1, '(?<!\r)\n')).Count)/$(if ($bytes[0] -eq 0xEF) { 'BOM' } else { 'noBOM' })"
# AC-1: the checker accepts what the writer wrote
& (Join-Path $PSScriptRoot 'Test-FormA.ps1') -Fixture (Join-Path $work 'model.dlgraph') -Quiet | Out-Null
$res.FormAChecker = $LASTEXITCODE
# the checker still fails on a mutation of the written text (proven to fail, not merely to pass);
# 6>$null: its FAIL lines are Write-Host, and an expected failure must not read as one in the gate log
$mut = $text1 -replace '(\d+) conditions', '9 conditions'
[IO.File]::WriteAllText((Join-Path $work 'model-mut.dlgraph'), $mut, (New-Object Text.ASCIIEncoding))
& (Join-Path $PSScriptRoot 'Test-FormA.ps1') -Fixture (Join-Path $work 'model-mut.dlgraph') -Quiet 6>$null | Out-Null
$res.FormACheckerMut = $LASTEXITCODE
# AC-11: a step without an anchor is refused by the model
$res.FormANoAnchor = $(try { New-TraceStep 'step' 'CALLS X' '' | Out-Null; 'accepted' } catch { $(if ($_.Exception.Message -like '*AC-11*') { 'refused' } else { "wrong: $($_.Exception.Message)" }) })
# Review Focus 4: a non-ASCII byte in a quoted condition is refused, never written as '?'
$Tn = New-Trace 'X' 'x' 'x' 'A' '2026-09-27' 'x' 'client'
$sn = Add-TraceSection $Tn 'WRITE'
$stn = New-TraceStep 'step' 'CALLS X' 'X.pas:1'
[void]$stn.Children.Add((New-TraceCond 'UNLESS' ('a ' + [char]0xE9 + ' b') 'X.pas:2'))
[void]$sn.Items.Add($stn)
$res.FormANonAscii = $(try { Write-FormA $Tn | Out-Null; 'accepted' } catch { $(if ($_.Exception.Message -like '*not 7-bit ASCII*') { 'refused' } else { "wrong: $($_.Exception.Message)" }) })
# a note with '; ' would break the parser's split -- refused up front
$res.FormABadNote = $(try { $Tb = New-Trace 'X' 'x' 'x' 'A' '2026-09-27' 'x' 'client'; $sb2 = Add-TraceSection $Tb 'WRITE'; [void]$sb2.Items.Add((New-TraceStep 'step' 'CALLS X' 'X.pas:1' '' '' 'a; b')); Write-FormA $Tb | Out-Null; 'accepted' } catch { 'refused' })
# P16: a condition is quoted VERBATIM, so one carrying a double-quote cannot be quoted -- the model refuses it
$res.FormAQuote = $(try { New-TraceCond 'WHEN' 'S = "x"' 'X.pas:1' | Out-Null; 'accepted' } catch { $(if ($_.Exception.Message -like '*double-quote*') { 'refused' } else { "wrong: $($_.Exception.Message)" }) })
# Fix round 1 / P16: a TITLE is quoted too, so a double-quote in it is refused (it was written raw and
# read back un-doubled -- bytes differed); both at New-Trace and at Write-FormA (the property is mutable)
$ttl1 = $(try { New-Trace 'X' 'a"b' 'x' 'A' '2026-09-28' 'x' 'client' | Out-Null; 'accepted' } catch { $(if ($_.Exception.Message -like '*double-quote*') { 'refused' } else { "wrong: $($_.Exception.Message)" }) })
$ttl2 = $(try { $Tq = New-Trace 'X' 'ab' 'x' 'A' '2026-09-28' 'x' 'client'; $Tq.Title = 'a""b'; [void](Add-TraceSection $Tq 'WRITE').Items.Add((New-TraceStep 'step' 'CALLS X' 'X.pas:1')); Write-FormA $Tq | Out-Null; 'accepted' } catch { $(if ($_.Exception.Message -like '*double-quote*') { 'refused' } else { "wrong: $($_.Exception.Message)" }) })
$res.FormATitleQuote = "$ttl1/$ttl2"
# Fix round 1: every text the writer would emit but its own parser or the checker would misread is refused
# up front. Step heads: a bare or leading actor/kind word, a counted head (WHEN UNLESS GUARD UNRESOLVED), a
# section word before STOPS/CROSSES, a lone annotation; any text: a leading '--' or a trailing ' --'.
$guardCases = @(
  @('step', 'SERVER'), @('step', 'STOPS'), @('step', 'CROSSES'), @('step', 'user'), @('step', 'CALLS x --'),
  @('step', 'WHEN x'), @('step', 'UNLESS'), @('step', 'GUARD x'), @('step', 'UNRESOLVED x'), @('step', 'READ STOPS x'),
  @('step', 'ALSO CROSSES x'), @('step', '-- x'), @('step', '[inferred]'), @('step', '@X.pas:1'),
  @('facet', 'x --'), @('facet', '-- x'))
$guardOk = @()
foreach ($gc in $guardCases) {
  $acc = $(try { if ($gc[0] -eq 'step') { New-TraceStep 'step' $gc[1] 'X.pas:1' | Out-Null } else { New-TraceFacet 'VIA' $gc[1] 'X.pas:1' | Out-Null }; $true } catch { $false })
  if ($acc) { $guardOk += "$($gc[0]):'$($gc[1])'" }
}
# and what the guard must NOT refuse: a facet naming a tier, a step text with a '--' inside a word
$guardFp = @()
foreach ($ok in @(@('facet', 'SERVER'), @('step', 'CALLS a--b'), @('step', 'READS WHEN_FLAG'))) {
  $acc = $(try { if ($ok[0] -eq 'step') { New-TraceStep 'step' $ok[1] 'X.pas:1' | Out-Null } else { New-TraceFacet 'TO' $ok[1] | Out-Null }; $true } catch { $false })
  if (-not $acc) { $guardFp += "$($ok[0]):'$($ok[1])'" }
}
$res.FormATextGuard = "refused $($guardCases.Count - $guardOk.Count)/$($guardCases.Count); accepted [$($guardOk -join ',')]; wrongly refused [$($guardFp -join ',')]"
# P7 / AC-12: a numbered STOPS is unresolved in EVERY section, with or without an actor word before it
# (`[NN] SERVER STOPS ...`); a Pascal condition with '' is written verbatim and reads back
$Ts = New-Trace 'X' 'x' 'x' 'A' '2026-09-28' 'x' 'client -> server'
$stAct = @('', 'CLIENT', 'SERVER', 'DATABASE', 'SERVER', 'USER', '')
$stSec = @('ANCHOR', 'READ', 'WRITE', 'SERVER', 'DATABASE', 'RESPONSE', 'ALSO')
for ($q = 0; $q -lt $stSec.Count; $q++) {
  $ssec = Add-TraceSection $Ts $stSec[$q]
  [void]$ssec.Items.Add((New-TraceStep 'stops' "no fact carries hop $($q + 1)" "X.pas:$($q + 1)" '' '' '' '' $stAct[$q]))
  if ($stSec[$q] -eq 'SERVER') {
    $sq = New-TraceStep 'step' 'CALLS HandleUpdateRecord' 'uGenericTableRoute.pas:208' '' 'HandleUpdateRecord'
    [void]$sq.Children.Add((New-TraceCond 'UNLESS' "SQL = ''" 'uGenericTableRoute.pas:196'))
    [void]$ssec.Items.Add($sq)
  }
}
$textS = Write-FormA $Ts
[IO.File]::WriteAllText((Join-Path $work 'model-stops.dlgraph'), $textS, (New-Object Text.ASCIIEncoding))
& (Join-Path $PSScriptRoot 'Test-FormA.ps1') -Fixture (Join-Path $work 'model-stops.dlgraph') -Quiet | Out-Null
$exS = $LASTEXITCODE
$cS = Get-TraceCounts $Ts
$rtS = $(if ((Write-FormA (Read-FormA $textS)) -ceq $textS) { 'identical' } else { 'differs' })
$srvS = @($textS -split "\r\n" | Where-Object { $_ -cmatch '^\[\d+\] SERVER STOPS ' }).Count
$vbS = $(if ($textS.Contains('UNLESS "SQL = ''''" @uGenericTableRoute.pas:196')) { 'verbatim' } else { 'rewritten' })
$res.FormAStopsAll = "$exS/$($cS.Steps)/$($cS.Conditions)/$($cS.Crossings)/$($cS.Unresolved)/$rtS/$srvS/$vbS"

# ---- 3. the anchor: the hop feeds-from misses (AC-15), and the non-data-bound / TABLE.COLUMN forms (AC-13) ----
. (Join-Path $PSScriptRoot 'Trace.Walk.ps1')
$S = Get-SqlTableSet $DbSql
$DbPath = Get-CloneDb $DbCli
# the extraction changed nothing: the colREASON chain still grades certain>certain>by name>inferred
$cf = [string](@((Get-IndexedFileShas).Keys | Where-Object { $_ -like '*\uCausFailForm.dfm' })[0])
$xc = Get-DataSourceChain $cf 'dsrCausFail' $S
$res.ChainUnchanged = "$($xc.Grade):$($xc.ResolvedTable):$((@($xc.Hops | ForEach-Object { $_.Grade })) -join '>'):$(@($xc.DataSetSites | Where-Object { $_.Kind -eq 'assign' }).Count)"
# Get-DataSetSites answers the same question of a FIELD: FDsrOperation.DataSet := FMTOperation at :657 in Create
$vmPas = 'C:\Projects\DB\ORM3\CLIENT\Blueprint4.ViewModel.pas'
$ds = Get-DataSetSites 0 '' $vmPas 'FDsrOperation' $null
$res.FieldDataSetSites = (@($ds | ForEach-Object { "$($_.Kind):$($_.Line):$($_.Rhs):$(($_.Routine -split '\.')[-1])" }) -join ',')
# the re-point chain from Blueprint4.pas:2282
$bp = [string](@((Get-IndexedFileShas).Keys | Where-Object { $_ -like '*\CLIENT\Blueprint4.dfm' })[0])
$ch = Get-DataSourceChain $bp 'Blueprint4_Model.dsrOperation' $S
$rp = @($ch.RePointedAt | Where-Object { $_.Control -eq 'dxDBGrid1OperationV' })
# EVERY re-point site of the view, with its RHS: the second is the `:= nil` teardown (FormClose), which the trace skips
$res.RePointSite = "$($ch.Grade):$($rp.Count):$((@($rp | ForEach-Object { "$($_.Line)=$($_.Rhs)" })) -join ','):$($rp[0].ControlFrom)"
$rc = Get-RePointChain $rp[0] $null
$res.RePointHops = (@($rc.Hops | ForEach-Object { "$($_.Hop)=$($_.Grade)@$([IO.Path]::GetFileName($_.File)):$($_.Line)" }) -join ',')
$res.RePointDataSet = "$($rc.DataSet.Name):$($rc.DataSet.Type):$($rc.DataSet.Line):$($rc.StopReason)"
# the whole anchor through the trace's own resolver, all four -Target forms
$a1 = Resolve-TraceAnchor 'frmBlueprint4.dxDBGrid1OperationVName' $S $null
$res.Anchor1 = "$($a1.TableColumn):$($a1.DataSet.Name):$($a1.Items.Count):$($a1.Stop)"
$res.Anchor1Grades = (@($a1.Items | ForEach-Object { $(if ($_.Grade) { $_.Grade } else { 'certain' }) }) -join '>')
$res.Anchor1Files = (@($a1.Items | ForEach-Object { ($_.Anchor -split ':')[0] } | Select-Object -Unique) -join ',')
$a2 = Resolve-TraceAnchor 'Blueprint4.TfrmBlueprint4.dxDBGrid1OperationVName' $S $null
$res.Anchor2 = "$($a2.TableColumn):$($a2.Grades -join '/'):$($a2.Stop)"
# P3: the resolver returns a stop REASON and ZERO chain items; the one-step trace is the emitter's (Task 7, RT-N1)
$a3 = Resolve-TraceAnchor 'OPERAT.NAME' $S $null
$res.Anchor3 = "$($a3.TableColumn):$($a3.Items.Count):$($a3.Stop -replace '\s+', ' ')"
$a4 = Resolve-TraceAnchor 'frmBlueprint4.cxGroupBox16' $S $null
$res.Anchor4 = "$($a4.Items.Count):$($a4.StopAnchor):$($a4.Stop -replace '\s+', ' ')"
# P13: the TField form with a DOTTED unit -- the spec's own example (4 segments, split from the right);
# it resolves its dataset and column, or ends in a named stop reason -- never a throw
$a6 = $(try { Resolve-TraceAnchor 'Blueprint4.ViewModel.TBlueprint_ViewModel.FfOperation_FileName' $S $null } catch { [pscustomobject]@{ Threw = $_.Exception.Message } })
$res.AnchorTField = $(if ($a6.PSObject.Properties['Threw']) { "threw: $($a6.Threw)" } else { "$($a6.TableColumn):$($a6.DataSet.Name):$($a6.Items.Count):$($a6.Stop -replace '\s+', ' ')" })
# fix round 1 (Important 1): the FF shape at :939 is an INFERENCE about FF -- never certain. The real step's
# grade, ask and reason, then the grading rule on every shape, including the LATENT one (a BOUND dataset
# read through a non-FieldByName call, which the index does not produce today): only FieldByName + bound is certain
$t6 = $(if ($a6.PSObject.Properties['Threw']) { $null } else { $a6.Items[0] })
$res.AnchorTFieldStep = $(if ($t6) { "$(if ($t6.Grade) { $t6.Grade } else { 'certain' })|$($t6.Ask)|$($t6.Note)" } else { 'no step' })
$gr = foreach ($gc in @(@($false, $true, 'FF'), @($false, $false, 'FF'), @($false, $true, 'SomeLookup'), @($true, $true, ''), @($true, $false, ''))) {
  $g = Get-FieldVarLineGrade $gc[0] $gc[1] @($gc[2]) 'FMT'
  "$(if ($gc[0]) { 'FieldByName' } else { $gc[2] })/$(if ($gc[1]) { 'bound' } else { 'unbound' })=$(if ($g.Grade) { $g.Grade } else { 'certain' })"
}
$res.FieldVarGrades = $gr -join ','
# ruling T3-M1: the shared sanitiser leaves an indexer as written; the generated column label reads '(certain)'
$res.TraceWordIndexer = ConvertTo-TraceWord 'X.Fields[0].DataSet [by name]'
$res.ColumnNote = $(if ($a1.Items.Count) { $a1.Items[$a1.Items.Count - 1].Note } else { '' })
# Review Focus 5: the re-point file (Blueprint4.pas, not the view model) stale -> the refusal names Blueprint4.pas
$bpPas = 'C:\Projects\DB\ORM3\CLIENT\Blueprint4.pas'
$stDir = Join-Path $work 'stale-form'; New-Item -ItemType Directory -Force $stDir | Out-Null
$l = [IO.File]::ReadAllLines($bpPas); $l[2281] = $l[2281] + ' '
[IO.File]::WriteAllText((Join-Path $stDir 'Blueprint4.pas'), (($l -join "`r`n") + "`r`n"), (New-Object Text.ASCIIEncoding))
$a5 = Resolve-TraceAnchor 'frmBlueprint4.dxDBGrid1OperationVName' $S @{ $bpPas = (Join-Path $stDir 'Blueprint4.pas') }
$res.Anchor5Stale = "$([IO.Path]::GetFileName([string]$a5.StaleFile)):$($a5.TableColumn)"

[pscustomobject]$res
