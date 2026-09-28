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

# ---- 4. the condition shim: the 12 golden guards, verbatim, on fresh files (AC-7); stale refuses (AC-14) ----
$inv = Import-PowerShellDataFile (Join-Path $PSScriptRoot '..\fixtures\golden-operat-name-inventory.psd1')
$srcOf = @{ 'Blueprint4.ViewModel.pas' = @{ Db = $DbCli; P = 'C:\Projects\DB\ORM3\CLIENT\Blueprint4.ViewModel.pas' }
            'uGenericTableRoute.pas'   = @{ Db = $DbSrv; P = 'C:\Projects\DB\ORM3\SERVER\uGenericTableRoute.pas' }
            'uPipeSessionBuilder.pas'  = @{ Db = $DbSrv; P = 'C:\Projects\DB\ORM3\SERVER\uPipeSessionBuilder.pas' } }
# the Exit line that sits under each golden guard's if/except line (measured, Task 1 A-RT0-EXITS)
$exitOf = @{ 3950 = 3950; 3973 = 3973; 3974 = 3974; 411 = 415; 421 = 425; 431 = 435; 446 = 451; 196 = 200; 1133 = 1133; 525 = 530; 549 = 554; 1137 = 1140 }
$startOf = @{ 'Blueprint4.ViewModel.pas' = @{ 3950 = 3948; 3973 = 3960; 3974 = 3960; 1133 = 1123; 1137 = 1123 }
              'uGenericTableRoute.pas' = @{ 411 = 389; 421 = 389; 431 = 389; 446 = 389; 196 = 183 }
              'uPipeSessionBuilder.pas' = @{ 525 = 502; 549 = 502 } }
$gl = @()
foreach ($g in $inv.Guards) {
  $DbPath = Get-CloneDb $srcOf[$g.File].Db
  $c = Get-GuardCondition $srcOf[$g.File].P $exitOf[[int]$g.Line] $startOf[$g.File][[int]$g.Line] $null
  # ruling T4-R2: the EXACT quoted condition, not a Contains($g.Word) -- a regression adding `not (..)` or
  # trailing text must break the pin; the golden's word is still checked (`ok`/`MISS`) for the AC-7 matcher
  $gl += "$($g.G):$($c.Form):$($c.Keyword):$($c.IfLine):$(if ($c.Condition.Contains($g.Word)) { 'ok' } else { 'MISS' }):$($c.Condition)"
}
$res.Guards = $gl -join ' | '
$DbPath = Get-CloneDb $DbCli
$c90 = Get-GuardCondition $vmPas 4004 3960 $null
$res.Guard3990 = "$($c90.Form):$($c90.Keyword):$($c90.IfLine):$($c90.BlockStart)-$($c90.BlockEnd):$($c90.Condition)"
$c73 = Get-GuardCondition $vmPas 3973 3960 $null
$res.Guard3973 = "$($c73.Condition)|$($c73.ExitArg)"
$DbPath = Get-CloneDb $DbSrv
$c46 = Get-GuardCondition $srcOf['uGenericTableRoute.pas'].P 451 389 $null
$res.Guard446 = "$($c46.Form):$($c46.Condition):$($c46.BlockStart)-$($c46.BlockEnd)"
$c93 = Get-GuardCondition $srcOf['uGenericTableRoute.pas'].P 193 183 $null
$res.Guard193 = "$($c93.Form):$($c93.Keyword)"
# T1-C1: HandleTableLoad's THIRD Exit (:612) sits in an `on E: Exception do begin` handler whose try (:591)
# guards ELEVEN statements -- which one raises is not in the source, so the first and last are quoted
$c612 = Get-GuardCondition $srcOf['uPipeSessionBuilder.pas'].P 612 502 $null
$res.Guard612 = "$($c612.Form):$($c612.Keyword):$($c612.IfLine):$($c612.BlockStart)-$($c612.BlockEnd):$($c612.Condition)"
# Review Focus 3: synthetic line arrays -- a wrapped `if`, an `else Exit`, an except handler
$syn = @('procedure P;', 'begin', '  if (A = 1) or', '     (B = 2) then', '  begin', '    Exit;', '  end;', '  if C then X else Exit;', '  try', '    Load(S);', '  except', '    on E: Exception do begin', '      Exit;', '    end;', '  end;', 'end;')
$g1 = Get-GuardConditionFromLines $syn $syn 6 1
$g2 = Get-GuardConditionFromLines $syn $syn 8 1
$g3 = Get-GuardConditionFromLines $syn $syn 13 1
$res.ShimSynthetic = "$($g1.Form):$($g1.Keyword):$($g1.Condition):$($g1.IfLine)|$($g2.Form):$($g2.Keyword):$($g2.Condition)|$($g3.Form):$($g3.Keyword):$($g3.Condition):$($g3.IfLine)"
# The shapes the line-count walk of the plan's draft misread, on a real file so comments and strings are
# stripped as in the corpus: a wrapped `if` whose first line ends in a comment and whose condition holds a
# string with two spaces (joined, never collapsed); an Exit in an `end else begin` block (WHEN); an `if`
# whose Exit is on the NEXT line (no begin); a `"` in the condition (named, not thrown, not rewritten);
# and the shapes the shim does not read -- a loop, a case arm, an Exit in no branch -- as named results
$shp = @(
  'procedure P1;', 'begin', "  if (S = 'a  b') or  // why", "     (T = 1) then", '  begin', '    Exit;', '  end;', 'end;',                   # 1-8
  'procedure P2;', 'begin', '  if C then', '  begin', '    X;', '  end else begin', '    Exit;', '  end;', 'end;',                      # 9-17
  'procedure P3;', 'begin', '  if D { note } then', '    Exit;', 'end;',                                                               # 18-22
  'procedure P4;', 'begin', "  if S = '""' then Exit;", 'end;',                                                                       # 23-26
  'procedure P5;', 'begin', '  while X do begin', '    Exit;', '  end;', 'end;',                                                      # 27-32
  'procedure P6;', 'begin', '  case K of', '    1: Exit;', '  end;', 'end;',                                                          # 33-38
  'procedure P7;', 'begin', '  if A then Y;', '  Exit;', 'end;')                                                                      # 39-43
$shpPas = Join-Path $work 'shim-shapes.pas'
[IO.File]::WriteAllText($shpPas, (($shp -join "`r`n") + "`r`n"), (New-Object Text.ASCIIEncoding))
$shR = [IO.File]::ReadAllLines($shpPas); $shS = Get-StrippedSourceLines $shpPas
$sh = foreach ($q in @(@(6, 1), @(15, 9), @(21, 18), @(25, 23), @(30, 27), @(36, 33), @(42, 39))) {
  $o = Get-GuardConditionFromLines $shR $shS $q[0] $q[1]
  "$($o.Form):$($o.Keyword):$($o.Condition):$($o.IfLine):$($o.BlockStart)-$($o.BlockEnd):$($o.Reason)"
}
$res.ShimShapes = $sh -join '|'
# Fix round 1 (review of Task 4): two Exits on the anchored line; a comment wrapping across the lines of
# a condition (an apostrophe, and a `(*` form, in its tail); a conditional-compilation choice between the
# guard and the Exit (one line and wrapped). Each is a NAMED unknown. The control: a comment CLOSED on its
# own line inside a wrapped condition is still quoted as written.
$fx = @(
  'procedure F1;', 'begin', '  if A then begin X; Exit; end else begin Y; Exit; end;', 'end;',                                        # 1-4
  'procedure F2;', 'begin', '  if A and { first line', "  don't } B then", '    Exit;', 'end;',                                   # 5-10
  'procedure F3;', 'begin', '  if A and (* first', '  // *) B then', '    Exit;', 'end;',                                            # 11-16
  'procedure F4;', 'begin', '  {$IFDEF X} if A then {$ELSE} if B then {$ENDIF} Exit;', 'end;',                                      # 17-20
  'procedure F5;', 'begin', '{$IFDEF X}', '  if A then', '{$ELSE}', '  if B then', '{$ENDIF}', '    Exit;', 'end;',                  # 21-29
  'procedure F6;', 'begin', '  if A and { c } B or', '     C then', '    Exit;', 'end;')                                                 # 30-35
$fxPas = Join-Path $work 'shim-fix1.pas'
[IO.File]::WriteAllText($fxPas, (($fx -join "`r`n") + "`r`n"), (New-Object Text.ASCIIEncoding))
$fxR = [IO.File]::ReadAllLines($fxPas); $fxS = Get-StrippedSourceLines $fxPas
$fr = foreach ($q in @(@(3, 1), @(9, 5), @(15, 11), @(19, 17), @(28, 21), @(34, 30))) {
  $o = Get-GuardConditionFromLines $fxR $fxS $q[0] $q[1]
  "$($o.Form):$($o.Keyword):$($o.Condition):$($o.Reason)"
}
$res.ShimFix1 = $fr -join '|'
# AC-14: a manufactured stale view model (one trailing blank on the guard line) -> the wrapper REFUSES and names the file
$stVm = Join-Path $work 'stale-vm'; New-Item -ItemType Directory -Force $stVm | Out-Null
$l = [IO.File]::ReadAllLines($vmPas); $l[3949] = $l[3949] + ' '
[IO.File]::WriteAllText((Join-Path $stVm 'Blueprint4.ViewModel.pas'), (($l -join "`r`n") + "`r`n"), (New-Object Text.ASCIIEncoding))
$DbPath = Get-CloneDb $DbCli
$res.ShimStale = $(try { Get-GuardCondition $vmPas 3950 3948 @{ $vmPas = (Join-Path $stVm 'Blueprint4.ViewModel.pas') } | Out-Null; 'accepted' }
                   catch { $(if ($_.Exception.Message -like '*Blueprint4.ViewModel.pas differs from the indexed copy*') { 'refused-named' } else { "wrong: $($_.Exception.Message)" }) })

# ---- 5. the WRITE direction end to end (AC-8, AC-9, AC-12) --------------------------------
# 6>$null: the emitter prints the whole trace (Write-Host); its else notes quote source text such as
# 'OPERAT %s FAILED', which must not read as a failure in the gate log
$rt = & (Join-Path $PSScriptRoot 'Emit-RoundTrip.ps1') -Target 'frmBlueprint4.dxDBGrid1OperationVName' -DbPath $DbCli -ServerDbPath $DbSrv -SqlDbPath $DbSql -OutDir $work 6>$null
$txt = [IO.File]::ReadAllText($rt.Trace)
$res.RtText = $txt
$res.RtSections = $rt.Sections
$res.RtCounts = "$($rt.Steps)/$($rt.Conditions)/$($rt.Crossings)/$($rt.Unresolved)"
$lines = $txt -split "\r\n"
function LinesLike([string] $rx) { , @($lines | Where-Object { $_ -match $rx }) }
# AC-8: the response guard carries the failure branch naming CancelUpdates
$res.RtCancel = (LinesLike 'UNLESS ".*<> rspOK\)" @Blueprint4\.ViewModel\.pas:3990 -- else .*FMTOperation\.CancelUpdates @Blueprint4\.ViewModel\.pas:3999').Count
# AC-9: client -> server -> database, on separately queried indexes. CROSSES STEP lines only (ruling P4):
# the request and the response are both anchored at the one ExecuteCommand call that carries both
$res.RtCrossOut = (LinesLike '^\[\d+\] CROSSES process boundary @Blueprint4\.ViewModel\.pas:3985').Count
$res.RtCrossFacets = (@((LinesLike '^       (FROM|TO|OVER|WITH|CONTRACT) ') | ForEach-Object { ($_.Trim() -split ' ')[0] }) -join ',')
$res.RtServer = (@((LinesLike '^\[\d+\] (CALLS|ROUTES) ') | Where-Object { $_ -match '@(Pipes\.Commands|uPipeSessionBuilder|uGenericTableRoute|uDatasetsDef|uBroadcastServer)\.pas' } | ForEach-Object { ($_ -replace '^\[\d+\] ', '') -replace ' @.*$', '' }) -join '|')
$res.RtFib = (LinesLike 'READS FROM FIB\$DATASETS_INFO \[inferred\] @uDatasetsDef\.pas:130').Count
# AC-12: the UPDATE text is a numbered STOPS counted as unresolved; the column comes from the SQL index.
# Ruling P5: only the WRITE / SERVER / DATABASE sections -- READ holds this task's placeholder STOPS (Task 6)
$secOf = ''; $stopsW = @()
foreach ($ln in $lines) {
  if ($ln -cmatch '^[A-Z]+$') { $secOf = $ln; continue }
  if ($secOf -in 'WRITE', 'SERVER', 'DATABASE' -and $ln -match '^\[\d+\] STOPS ') { $stopsW += (($ln -replace '^\[\d+\] STOPS ', '') -replace ' @.*$', '') }
}
$res.RtStops = $stopsW -join '|'
$res.RtColumn = (LinesLike 'WRITES OPERAT\.NAME \[inferred\] @MS1\.SQL:2808').Count
$res.RtRspOk = (LinesLike '^\[\d+\] RECEIVES rspOK @Blueprint4\.ViewModel\.pas:3990').Count + (LinesLike 'APPLIES FMTOperation\.CommitUpdates @Blueprint4\.ViewModel\.pas:4010').Count
# the rebinding really switched indexes: file counts differ (CLIENT 625, SERVER 471)
$res.RtOnDb = $rt.OnDbProof

# ---- 5b. the pre-review rulings T5-R1..R3 -------------------------------------------------
$secLines = @{}; $secOf = ''
foreach ($ln in $lines) { if ($ln -cmatch '^[A-Z]+$') { $secOf = $ln; $secLines[$secOf] = @(); continue }; if ($secOf) { $secLines[$secOf] += $ln } }
# T5-R1: no step of the anchor's path comes from a branch for ANOTHER table. HandleDelta's MSCLIST / OPTRLIST
# branches (:468-469, :476-477, :515-531, :540-551) and its routine-level `sql_reads MSCLIST` fact were steps
$res.RtOtherTable = @($secLines['SERVER'] | Where-Object { $_ -match '^\[\d+\] ' -and $_ -match 'CoerceMSCLISTPlanIds|CaptureOptrlistDelta|ApplyOptrlistSyncItems|SyncRolesOnConn|QChk\.Open|READS MSCLIST' }).Count
# ... and ONE disclosure per section says what was left out, quoting the branch conditions verbatim
$res.RtOmits = (@($lines | Where-Object { $_ -match '^\[\d+\] OMITS ' } | ForEach-Object { $_ -replace '^\[\d+\] ', '' }) -join ' || ')
# the enclosing condition of a LINE (pure, over line arrays): then-branch WHEN, else-branch UNLESS, through
# begin / try blocks to the nearest if; a statement in no branch is a named unknown
$encSrc = @('procedure P;', 'begin', "  if T = 'MSCLIST' then", '    A;', "  if (T = 'X') and (N > 0) then", '  begin', '    try', '      B;',
            '    except', '    end;', '  end', '  else', '    C;', '  D;', 'end;')
$encPas = Join-Path $work 'enclosing.pas'
[IO.File]::WriteAllText($encPas, (($encSrc -join "`r`n") + "`r`n"), (New-Object Text.ASCIIEncoding))
$res.RtEnclosing = $(try {
  $eR = [IO.File]::ReadAllLines($encPas); $eS = Get-StrippedSourceLines $encPas
  (@(@(4, 4), @(8, 6), @(13, 4), @(14, 2)) | ForEach-Object { $o = Get-EnclosingConditionFromLines $eR $eS $_[0] $_[1] 1; "$($o.Form):$($o.Keyword):$($o.Condition):$($o.IfLine)" }) -join ' | '
} catch { "threw: $($_.Exception.Message)" })
# the prune predicate: WHEN + `= '<a known table>'` that is not the anchor's, and no `or` / `not` / `<>`
$res.RtOtherTableRule = $(try {
  $tabs = @('OPERAT', 'MSCLIST')
  (@(@('WHEN', "TableName = 'MSCLIST'"), @('UNLESS', "TableName = 'MSCLIST'"), @('WHEN', "TableName <> 'MSCLIST'"), @('WHEN', "(T = 'MSCLIST') or (T = 'OPERAT')"),
     @('WHEN', "(TableName = 'MSCLIST') and (X > 0)"), @('WHEN', "X = 'NOTATABLE'"), @('WHEN', "(A = 'MSCLIST') or B"), @('WHEN', "TableName = 'OPERAT'")) |
    ForEach-Object { Test-OtherTableBranch $_[0] $_[1] 'OPERAT' $tabs }) -join ','
} catch { "threw: $($_.Exception.Message)" })
# T5-R2: a condition hung on a CALLS step of ANOTHER routine names its own routine (411 / 421 hang on CALLS SplitPayload)
$res.RtCondRoutine = (@($lines | Where-Object { $_ -match '^       UNLESS ".*" @uGenericTableRoute\.pas:(411|421) ' } | ForEach-Object { ($_ -replace '^.* -- ', '') }) -join ' | ')
# T5-R3: an else note quotes a literal VERBATIM with Pascal's doubled '' (the index stores it unescaped); one the
# writer cannot carry (a double quote, the note separator) is named by its line, never rewritten
$res.RtElse431 = (@($lines | Where-Object { $_ -match '^       UNLESS ".*" @uGenericTableRoute\.pas:431 ' } | ForEach-Object { ($_ -replace '^.* -- ', '') }) -join ' | ')
$res.RtElseLits = $(try {
  $eF = [pscustomobject]@{ Path = 'X.pas'; Refs = @([pscustomobject]@{ kind = 'write'; tkind = 'param'; line = 5; nm = 'AOut' }); Lits = @() }   # line 5 writes a parameter: the payload line (T5-R11)
  $eG = [pscustomobject]@{ BlockStart = 4; BlockEnd = 6; ExitArg = '' }
  (@("Can't find the row", 'no entry for table "%s"', 'first; second part') | ForEach-Object {
    $eF.Lits = @([pscustomobject]@{ kind = 'literal'; text = $_; line = 5 }); Get-ElseNote $eF $eG @{} }) -join ' | '
} catch { "threw: $($_.Exception.Message)" })
# T5-R3 / Task 4 review: the shim's string reader over Pascal's doubled '' quotes a condition as written
$dqPas = Join-Path $work 'doubled-quote.pas'
[IO.File]::WriteAllText($dqPas, ((@('procedure Q;', 'begin', "  if S = 'it''s' then Exit;", "  if (S = 'a'' then') or", "     (N = 0) then Exit;", 'end;') -join "`r`n") + "`r`n"), (New-Object Text.ASCIIEncoding))
$dqR = [IO.File]::ReadAllLines($dqPas); $dqS = Get-StrippedSourceLines $dqPas
$res.RtDoubledQuote = (@(@(3, 1), @(5, 1)) | ForEach-Object { $o = Get-GuardConditionFromLines $dqR $dqS $_[0] $_[1]; "$($o.Form):$($o.Keyword):$($o.Condition)" }) -join ' | '
# the written trace still reads back byte for byte (the condition model gained a routine field for T5-R2)
$res.RtRoundTrip = $(if ((Write-FormA (Read-FormA $txt)) -ceq $txt) { 'identical' } else { 'differs' })

# ---- 5c. fix round 1 (task review Important 1-2, rulings T5-R5, T5-R6) -------------------------
function StepHead([string] $l) { ($l -replace '^\[\d+\] ', '') -replace ' @.*$', '' }
function NoteOf([string] $l) { $(if ($l -match ' -- (.*)$') { $Matches[1] } else { '' }) }
# Important 1: the else of `if ApplyResult = 0` (:557-569) and the except handler (:570-579) are not steps
# of the path, and the :405 `ARspCmd:= rspError` is a default the :553 rspOK overwrites, not a SENDS
$res.RtBranchSteps = @($secLines['SERVER'] | Where-Object { $_ -match '^\[\d+\] .*@uGenericTableRoute\.pas:(405|562|566|573|576)( |$)' }).Count
$res.RtApplyWhen = (@($lines | Where-Object { $_ -match '^       WHEN "ApplyResult = 0" @uGenericTableRoute\.pas:495' } | ForEach-Object { NoteOf $_ }) -join ' | ')
$res.RtExceptCond = (@($lines | Where-Object { $_ -match '^       UNLESS ".*" @uGenericTableRoute\.pas:570' } | ForEach-Object { $_.Trim() }) -join ' | ')
$res.RtRspOkNote = (@($secLines['SERVER'] | Where-Object { $_ -match '^\[\d+\] SENDS rspOK ' } | ForEach-Object { NoteOf $_ }) -join ' | ')
# the chain of enclosing conditions of a line, innermost first (synthetic): else of an if, an except handler
$chSrc = @('procedure P;', 'begin', '  try', '    R:= Apply;', '    if R = 0 then', '    begin', '      Send(1);', '    end', '    else', '    begin',
           '      if W then Roll;', '    end;', '  except', '    on E: Exception do Roll2;', '  end;', 'end;')
$chPas = Join-Path $work 'chain.pas'
[IO.File]::WriteAllText($chPas, (($chSrc -join "`r`n") + "`r`n"), (New-Object Text.ASCIIEncoding))
$res.RtChain = $(try {
  $cR = [IO.File]::ReadAllLines($chPas); $cS = Get-StrippedSourceLines $chPas
  (@(@(11, 16), @(14, 23), @(7, 6)) | ForEach-Object {
    $ch = Get-EnclosingChainFromLines $cR $cS $_[0] $_[1] 1   # assigned directly: the unary-comma contract
    ($ch | ForEach-Object { "$($_.Form):$($_.Keyword):$($_.Condition):$($_.IfLine)" }) -join ' > ' }) -join ' | '
} catch { "threw: $($_.Exception.Message)" })
# an except whose try body ends in a statement of many lines quotes `S1 ... raises`, never the whole block
$exSrc = @('procedure Q;', 'begin', '  try', '    A:= 1;', '    if A = 1 then', '    begin', '      B;', '      C;', '    end;', '  except', '    Exit;', '  end;', 'end;')
$exPas = Join-Path $work 'except-long.pas'
[IO.File]::WriteAllText($exPas, (($exSrc -join "`r`n") + "`r`n"), (New-Object Text.ASCIIEncoding))
$xR = [IO.File]::ReadAllLines($exPas); $xS = Get-StrippedSourceLines $exPas
$xo = Get-GuardConditionFromLines $xR $xS 11 1
$res.RtExceptLong = "$($xo.Form):$($xo.Keyword):$($xo.Condition):$($xo.IfLine)"
# Important 2: the OnUpdateRecord handler runs inside Mem.ApplyUpdates -- after OPENS, not at the :479 attach
$res.RtApplyOrder = (@($secLines['SERVER'] | Where-Object { $_ -match '^\[\d+\] (OPENS |APPLIES Mem\.ApplyUpdates|CALLS TGenericApplyContext\.HandleUpdateRecord|RUNS Cmd\.Execute)' } | ForEach-Object { StepHead $_ }) -join ' > ')
$res.RtHandlerNote = (@($secLines['SERVER'] | Where-Object { $_ -match '^\[\d+\] CALLS TGenericApplyContext\.HandleUpdateRecord' } | ForEach-Object { NoteOf $_ }) -join ' | ')
$res.RtEntryNote = (@($secLines['WRITE'] | Where-Object { $_ -match '^\[\d+\] CALLS TBlueprint_ViewModel\.DoAfterPostOperation' } | ForEach-Object { NoteOf $_ }) -join ' | ')
# T5-R5: payload and call literals quoted as written; the stream format read from the SaveToStream arguments
$res.RtPayload = (@($lines | Where-Object { $_ -match '^       WITH cmdDelta ' } | ForEach-Object { $_.Trim() }) -join ' | ')
$res.RtSendArg = (@($secLines['WRITE'] | Where-Object { $_ -match '^\[\d+\] CALLS TBlueprint_ViewModel\.SendDeltaOperation' } | ForEach-Object { StepHead $_ }) -join ' | ')
$res.RtStreamFmt = $(try { (@('    FMTOperation.SaveToStream(MS, sfBinary);', '  X.SaveToStream(MS);', '  X.SaveToStream(MS, TFmt(1));') | ForEach-Object { "[$(Get-StreamFormat $_)]" }) -join ',' } catch { "threw: $($_.Exception.Message)" })

# ---- 5d. fix round 2 (task re-review Important, rulings T5-R10..R12) -------------------------------
# T5-R10: the path side of an if -- an error response is not success; an inverted if keeps its ELSE
$mk = { param($kind, $nm, $tk, $tn) [pscustomobject]@{ kind = $kind; nm = $nm; tkind = $tk; tname = $tn } }
$wOk  = @((& $mk 'write' 'ARsp' 'param' ''), (& $mk 'read' 'rspOK' 'enum_value' 'rspOK'))
$wErr = @((& $mk 'write' 'ARsp' 'param' ''), (& $mk 'read' 'rspError' 'enum_value' 'rspError'))
$roll = @((& $mk 'call' 'Rollback' '' '')); $comm = @((& $mk 'call' 'Commit' '' ''))
$res.RtPathSide = $(try {
  $L = { param($rs) [pscustomobject]@{ Rs = $rs } }
  @((Get-BranchPathSide @((& $L $comm), (& $L $wOk)) @((& $L $roll), (& $L $wErr))),     # normal: then answers
    (Get-BranchPathSide @((& $L $roll), (& $L $wErr)) @((& $L $comm), (& $L $wOk))),     # inverted: else answers
    (Get-BranchPathSide @((& $L $wOk)) @((& $L $comm))),                                 # both answer
    (Get-BranchPathSide @((& $L $roll)) @((& $L $wErr))),                                # neither
    (Test-SuccessLine $wErr)) -join ','
} catch { "threw: $($_.Exception.Message)" })
# T5-R11: the else note quotes the literal that goes OUT (a parameter / rsp write / raise line), never a logger's
$res.RtElsePick = $(try {
  $pF = [pscustomobject]@{ Path = 'X.pas'; Refs = @((& $mk 'call' 'Warning' '' ''), (& $mk 'write' 'AOut' 'param' '')); Lits = @() }
  $pF.Refs[0] | Add-Member line 5; $pF.Refs[1] | Add-Member line 6
  $pF.Lits = @([pscustomobject]@{ kind = 'literal'; text = 'logged, not sent back'; line = 5 }, [pscustomobject]@{ kind = 'literal'; text = 'sent back to the caller'; line = 6 })
  $pG = [pscustomobject]@{ BlockStart = 5; BlockEnd = 6; ExitArg = '' }
  $a1 = Get-ElseNote $pF $pG @{}
  $pF.Refs = @($pF.Refs[0])
  $a2 = Get-ElseNote $pF $pG @{}
  "[$a1] [$a2]"
} catch { "threw: $($_.Exception.Message)" })
# T5-R12: every path step inside a readable if carries it -- the transaction's OPENS and its Commit both say
# WHEN "not WasTxn"; and what EnsureLoaded / PushTableChanged now carry
$condsOf = @(); $lastHead = ''
foreach ($ln in $secLines['SERVER']) {
  if ($ln -match '^\[\d+\] ') { $lastHead = ($ln -replace '^\[\d+\] ', '') -replace ' @(\S+).*$', '@$1'; continue }
  if ($ln -match '^       (WHEN|UNLESS) ') { $condsOf += [pscustomobject]@{ Head = $lastHead; Cond = (($ln.Trim()) -replace ' -- .*$', '') } }
}
$res.RtWasTxn = (@($condsOf | Where-Object { $_.Cond -like 'WHEN "not WasTxn"*' } | ForEach-Object { $_.Head }) -join ' | ')
$res.RtCondEnsure = (@($condsOf | Where-Object { $_.Head -like 'CALLS TDatasetsDef.EnsureLoaded*' -or $_.Head -like 'CALLS TBroadcastServer.PushTableChanged*' } | ForEach-Object { "$($_.Head -replace ' \[by name\]', '') :: $($_.Cond)" }) -join ' | ')

# ---- 6. READ and ALSO (AC-6, AC-9, AC-10; Review Focus 1) ----------------------------------
# AC-6: both directions; AC-9: four crossings -- cmdDelta out and back, cmdTableLoad out and back
$res.RtDirs = "$($rt.WriteSteps -gt 0)/$($rt.ReadSteps -gt 0)"
$res.RtXings = $rt.Crossings
# the READ section, every step head in text order (actor word kept): the fill call, its callee, the send,
# the SERVER walk, the DATABASE stop and column, the rows back, the CLIENT load
$res.RtRead = (@($secLines['READ'] | Where-Object { $_ -match '^\[\d+\] ' } | ForEach-Object { (StepHead $_) -replace '\bSTOPS .*$', 'STOPS' }) -join '|')
# AC-7 on the READ path, in walk order (ruling P9 + T1-C1): the client connection guard (:1133), the server's
# missing-definition (:525) and unsafe-WHERE (:549) guards, the except handler whose Exit is :612 (its condition
# anchors at the `except` line, :605), the response guard (:1137)
$res.RtReadGuards = (@($secLines['READ'] | Where-Object { $_ -match '^       UNLESS ".*" @(Blueprint4\.ViewModel\.pas:(1133|1137)|uPipeSessionBuilder\.pas:(525|549|605))( |$)' } | ForEach-Object { $(if ($_ -match '" @(\S+)') { $Matches[1] }) }) -join ',')
# every condition of the READ section, verbatim, with its anchor
$res.RtReadConds = (@($secLines['READ'] | Where-Object { $_ -match '^       (WHEN|UNLESS) ' } | ForEach-Object { ($_.Trim()) -replace ' -- .*$', '' }) -join ' | ')
# AC-12: the SELECT statement text is a numbered STOPS naming the empty fb_field_info
$res.RtReadStops = @($secLines['READ'] | Where-Object { $_ -match '^\[\d+\] (SERVER |DATABASE )?STOPS .*fb_field_info' }).Count
$res.RtReadStopText = (@($secLines['READ'] | Where-Object { $_ -match '^\[\d+\] (SERVER |DATABASE )?STOPS ' } | ForEach-Object { ($_ -replace '^\[\d+\] ', '') }) -join ' | ')
# the payload of the READ send, as the source assembles it
$res.RtReadPayload = (@($secLines['READ'] | Where-Object { $_ -match '^       WITH cmdTableLoad ' } | ForEach-Object { $_.Trim() }) -join ' | ')
# AC-10 (ruling P10): ALSO = every route to the anchor the index holds, minus the routes traced
$res.RtAlso = $rt.AlsoSteps
$res.RtAlsoRows = (@($secLines['ALSO'] | Where-Object { $_ -match '^\[\d+\] ' } | ForEach-Object { (StepHead $_) -replace ' \[by name\]', '' }) -join '|')
$res.RtAlsoAnchors = (@($secLines['ALSO'] | Where-Object { $_ -match '^\[\d+\] ' } | ForEach-Object { ($_ -replace '^.* @(\S+).*$', '$1') }) -join ',')
# the whole trace still passes the checker and reads back byte for byte with both directions in it
& (Join-Path $PSScriptRoot 'Test-FormA.ps1') -Fixture $rt.Trace -Quiet 6>$null | Out-Null
$res.RtFormA = "$LASTEXITCODE/$(if ((Write-FormA (Read-FormA $txt)) -ceq $txt) { 'identical' } else { 'differs' })"
# T5-R13: success is a POSITIVE list (rspOK, rspData) -- rspNotFound / rspDenied (Pipes.Protocol.pas:212-213) are
# error codes, so an if answering rspOK in one branch and rspNotFound in the other has ONE path side
$res.RtSuccessRsp = $(try {
  $sr = foreach ($n in 'rspOK', 'rspData', 'rspNotFound', 'rspDenied', 'rspError') { Test-SuccessLine @((& $mk 'write' 'ARsp' 'param' ''), (& $mk 'read' $n 'enum_value' $n)) }
  $wNf = @((& $mk 'write' 'ARsp' 'param' ''), (& $mk 'read' 'rspNotFound' 'enum_value' 'rspNotFound'))
  "$($sr -join ','),$(Get-BranchPathSide @([pscustomobject]@{ Rs = $wOk }) @([pscustomobject]@{ Rs = $wNf }))"
} catch { "threw: $($_.Exception.Message)" })
# ---- 6b. Task 6 fix round 1 (Important 1-2, T6-R1, T6-R2, T6-R4 M1-M5) ---------------------
# Important 1: the guard-line rule takes only a call INSIDE the condition (between `if` and `then`). On a one-line
# guard `if not X(A) then begin Foo(B); Exit; end;` Foo is failure-branch code; a wrapped condition keeps its 2nd line
$gsSrc = @('procedure P;', 'begin', '  if not X(A) then begin Foo(B); Exit; end;', '  if not Y(A) or', '     Z(B) then begin Log(C); Exit; end;', 'end;')
$gsPas = Join-Path $work 'guard-span.pas'
[IO.File]::WriteAllText($gsPas, (($gsSrc -join "`r`n") + "`r`n"), (New-Object Text.ASCIIEncoding))
$res.RtGuardSpan = $(try {
  $gR = [IO.File]::ReadAllLines($gsPas); $gS = Get-StrippedSourceLines $gsPas
  $g3 = Get-GuardConditionFromLines $gR $gS 3 1; $g5 = Get-GuardConditionFromLines $gR $gS 5 1
  # 1-based ref columns, as refs.start_col: X :3 col 10, Foo :3 col 26, Y :4 col 10, Z :5 col 6, Log :5 col 22
  (@(@($g3, 3, 10, 'X'), @($g3, 3, 26, 'Foo'), @($g5, 4, 10, 'Y'), @($g5, 5, 6, 'Z'), @($g5, 5, 22, 'Log')) | ForEach-Object { "$($_[3]):$(Test-InShimCondition $_[0] $_[1] $_[2])" }) -join ','
} catch { "threw: $($_.Exception.Message)" })
# Important 2 + M1: the callers already on the page are the owners of every CLIENT item before each direction's
# crossing (handler -> helper -> sender: the helper is not "another caller"); a SERVER-actor crossing is never a sender
$res.RtTracedIds = $(try {
  $pI = { param($k, $o, $l, $a) [pscustomobject]@{ Kind = $k; Owner = $o; Line = $l; Actor = $a } }
  $pw = @((& $pI 'step' 0 1 ''), (& $pI 'step' 10 2 ''), (& $pI 'step' 11 3 ''), (& $pI 'step' 12 4 ''), (& $pI 'crosses' 12 50 ''), (& $pI 'step' 12 51 ''))
  $pr = @((& $pI 'step' 0 1 ''), (& $pI 'crosses' 99 5 'SERVER'), (& $pI 'step' 20 6 ''), (& $pI 'crosses' 20 70 ''), (& $pI 'step' 77 80 'SERVER'))
  $tr = Get-TracedRouteIds (@(, $pw) + @(, $pr))
  "callers $((@($tr.Callers) | Sort-Object) -join ','); senders $((@($tr.Senders | ForEach-Object { "$($_.Owner)@$($_.Line)" })) -join ',')"
} catch { "threw: $($_.Exception.Message)" })
# T6-R1: EmptyDataSet empties the dataset
$res.RtEmptyVerb = [string]$RtOps['EmptyDataSet']
# T6-R2: an empty ALSO is no STOPS -- no rows, a generated section note, 0 unresolved, checker and round trip hold
$res.RtAlsoEmpty = $(try {
  $Te = New-Trace 'X' 'x' 'x' 'A' '2026-09-28' 'x' 'client'
  [void](Add-TraceSection $Te 'READ').Items.Add((New-TraceStep 'step' 'CALLS X' 'X.pas:1'))
  $sae = Add-TraceSection $Te 'ALSO'; $sae.Note = 'no other route to this anchor in the index'
  $tE = Write-FormA $Te
  [IO.File]::WriteAllText((Join-Path $work 'also-empty.dlgraph'), $tE, (New-Object Text.ASCIIEncoding))
  & (Join-Path $PSScriptRoot 'Test-FormA.ps1') -Fixture (Join-Path $work 'also-empty.dlgraph') -Quiet 6>$null | Out-Null
  $cE = Get-TraceCounts $Te
  "$LASTEXITCODE/$($cE.Steps)/$($cE.Unresolved)/$($tE.Contains("ALSO`r`n  -- no other route to this anchor in the index`r`n"))/$(if ((Write-FormA (Read-FormA $tE)) -ceq $tE) { 'identical' } else { 'differs' })"
} catch { "threw: $($_.Exception.Message)" })
# M2: a sender is table-specific only when its PAYLOAD literals (the ones Get-PayloadText selects before the send)
# name the table -- an error message naming it after the send does not make a table-parameter sender one
$res.RtTableSender = $(try {
  $sF = [pscustomobject]@{ Lits = @([pscustomobject]@{ kind = 'literal'; text = 'TABLE='; line = 5 }, [pscustomobject]@{ kind = 'literal'; text = 'OPERAT %s FAILED'; line = 9 }) }
  $a1 = Test-TableSpecificSender $sF 7 'OPERAT'
  $sF.Lits += [pscustomobject]@{ kind = 'literal'; text = 'TABLE=OPERAT|'; line = 4 }
  "$a1,$(Test-TableSpecificSender $sF 7 'OPERAT')"
} catch { "threw: $($_.Exception.Message)" })
# M3: every assignment to the SQL variable is named -- the expression of one that is not at the line start too
$res.RtAssignAt = $(try {
  (@(@("  SQL:= 'SELECT ' + C + ' FROM ' + T;", 3), @("  if W <> '' then SQL:= SQL + ' WHERE ' + W;", 19), @('  X:= Y(', 3)) | ForEach-Object {
    $aS = $_[0] -replace "'[^']*'", { ' ' * $_.Value.Length }; "[$(Get-AssignExprAt $_[0] $aS $_[1])]" }) -join ','
} catch { "threw: $($_.Exception.Message)" })
# Review Focus 1: a control whose datasource is NOT dangling completes with a trace (a named STOPS is fine, a throw is not)
$rtO = $(try { & (Join-Path $PSScriptRoot 'Emit-RoundTrip.ps1') -Target 'frmCausFail.colREASON' -DbPath $DbCli -ServerDbPath $DbSrv -SqlDbPath $DbSql -OutDir $work 6>$null } catch { [pscustomobject]@{ Threw = $_.Exception.Message } })
$res.RtOther = $(if ($rtO.PSObject.Properties['Threw']) { "threw: $($rtO.Threw)" } else { "$($rtO.TableColumn):$($rtO.Steps -gt 0):$(Test-Path $rtO.Trace)" })
$res.RtOtherStop = $(if ($rtO.PSObject.Properties['Threw']) { '' } else { "$($rtO.DataSet)|$($rtO.Steps)/$($rtO.Unresolved)|$($rtO.Stop -replace '\s+', ' ')" })
# fix wave (FW-R2): the BINDS FMemTable note's assignment-line locator -- the property's read accessor is bound on
# `dsrCausFail.DataSet:= FViewModel.MemTable` in the FORM unit (uCausFailForm.pas:125), a DIFFERENT file than the
# BINDS step's own anchor (FMemTable's declaring file, uCausFail.ViewModel.pas), so it must be qualified
$res.RtOtherBindNote = $(if ($rtO.PSObject.Properties['Threw']) { '' } else {
  (@(($rtO.Text -split "`r`n") | Where-Object { $_ -match '^\[\d+\] BINDS FMemTable ' }))[0] -replace '^\[\d+\] ', ''
})
# Task 7 fix round 1 (I3): that trace stops at its anchor's SIXTH step, so its title claims no reach and every later
# section carries the generated note naming [06] -- the number is the ANCHOR count, not a constant
$res.RtOtherShape = $(if ($rtO.PSObject.Properties['Threw']) { '' } else {
  $oT = $(if ($rtO.Text -match '(?m)^  TITLE "([^"]*)"\r$') { $Matches[1] } else { '' })
  $oN = @([regex]::Matches($rtO.Text, '(?m)^[A-Z]+\r\n  -- not walked: the trace stopped at (\[\d+\])\r$'))
  "$oT|$($oN.Count)|$((@($oN | ForEach-Object { $_.Groups[1].Value } | Select-Object -Unique)) -join ',')" })

# ---- 7. the golden matcher (AC-5, AC-7) and the whole-trace checks (AC-1, AC-2, AC-4, AC-11) ----
# One row per ANCHORED line of a trace model: each numbered step, and each condition and facet under it
# (a child row carries its step's number). A child's routine is its own `in X` part only -- a facet has none,
# and it does not inherit its step's: a CONTRACT facet in Pipes.Protocol.pas is not IN the sender.
function Get-GoldenRowSubject([string] $Kind, [string] $Text) {
  if ($Kind -in 'cond', 'stops') { return '' }
  $tk = @($Text -split '\s+' | Where-Object { $_ })
  # a step's first word is its verb; a facet's text starts at its subject. `READS FROM X` is about X.
  $k = $(if ($Kind -eq 'facet') { 0 } else { 1 })
  while ($k -lt $tk.Count -and $tk[$k] -cin 'FROM', 'TO', 'VIA', 'ONTO', 'AT') { $k++ }
  $(if ($k -lt $tk.Count) { $tk[$k] } else { '' })
}
# Fix round 1 (M): a numbered item whose anchor is missing or is not `<file>:<line>` (the P14 case) is a row with
# NO file -- it matches nothing, so its node reads MISSING -- and Anchored $false, which Measure-GoldenMatch counts
# as unclickable. It used to throw a null-method / Substring error instead of being reported.
function Get-GoldenRows($Trace) {
  $rows = New-Object System.Collections.ArrayList
  $add = { param($Step, $Kind, $Anchor, $Text, $Routine, $Ask)
    $an = [string]$Anchor; $ai = $an.LastIndexOf(':'); $ln = 0
    $ok = $ai -gt 0 -and [int]::TryParse($an.Substring($ai + 1), [ref]$ln) -and $ln -gt 0
    [void]$rows.Add([pscustomobject]@{ Seq = $rows.Count; Step = [int]$Step; Kind = $Kind; File = $(if ($ok) { $an.Substring(0, $ai) } else { '' }); Line = $(if ($ok) { $ln } else { 0 })
                                       Anchored = $ok; Text = $Text; Routine = [string]$Routine; Ask = [string]$Ask; Subject = (Get-GoldenRowSubject $Kind $Text) }) }
  foreach ($sec in $Trace.Sections) {
    foreach ($i in $sec.Items) {
      & $add $i.Number $i.Kind $i.Anchor $i.Text $i.Routine $i.Ask
      foreach ($ch in $i.Children) {
        if (-not $ch.Anchor) { continue }
        if ($ch.Kind -eq 'cond') { & $add $i.Number 'cond' $ch.Anchor $ch.Condition $ch.Routine $ch.Ask } else { & $add $i.Number 'facet' $ch.Anchor $ch.Text '' '' }
      }
    }
  }
  , $rows
}
function Test-GoldenWord([string] $Text, [string] $Word) { $Text -match ('(^|[^A-Za-z0-9_])' + [regex]::Escape($Word) + '($|[^A-Za-z0-9_])') }
# AC-5: a node is MATCHED by a row in the node's FILE that is anchored to the node -- at the golden's own line,
# or IN the node's routine (the row's `in X`), or ABOUT it (the row's subject is the symbol or `<qualifier>.<symbol>`;
# a CALLS step anchors at the callee's body, where the golden may cite its declaration). Naming the symbol
# somewhere in the text is NOT a match (`FIRES FMTOperation.AfterPost -> DoAfterPostOperation` is about AfterPost,
# anchored in Create). DISCLOSED: a STOPS naming the symbol AND its engine ask; a STOPS with no ask is missing.
# AC-7: a guard is MATCHED by a condition at its file:line whose verbatim text holds the guard's word;
# DISCLOSED by a STOPS naming the word or anchored at that file:line, again with its ask.
# MatchedBy / GuardsBy name the row that matched (`<node>=<step>[/<child kind>]@<line>`), so a pin shows WHAT matched.
#
# Fix round 1 (I1) -- a golden line that is a COMMENT. When the golden cites a line of the comment block directly
# above a declaration ($DocDecl: `<file>:<golden line>` -> that declaration's span and its implementation's,
# Get-GoldenDocDecl), the node IS that declaration: it is matched by a row at the golden line, on the declaration,
# or inside its implementation (Test-GoldenDocLine) -- by POSITION from the index, and by nothing else: no routine
# or subject rule, because a name match there can be a different fact (node 6: the golden's :389 is the payload
# contract above IPipeSessionBuilder.HandleDelta @:392; the TCommandID.cmdDelta constant @:55 is the command id and
# must not stand in for it. Node 13: the golden's :120 is the comment above TBroadcastServer.PushTableChanged @:124,
# whose implementation (:401-441) the CALLS step anchors in).
#
# Fix round 1 (I2) -- $Facts: golden facts the walk DELIBERATELY does not produce as steps (each File, Line, What).
# A fact with no row at its file:line is DISCLOSED (FactsDisclosed); one the trace now carries is listed in FactsOnPage,
# so a walk that starts producing it, or a changed list, moves the pin.
# Unanchored: the step numbers of numbered items with no clickable anchor (fix round 1, M).
function Measure-GoldenMatch($Trace, $Inv, [hashtable] $DocDecl = @{}, $Facts = @()) {
  $rows = Get-GoldenRows $Trace
  $mb = @(); $nd = @(); $nx = @(); $nxN = @()
  foreach ($n in $Inv.Nodes) {
    $sym = [string]$n.Symbol; $gl = [int]$n.Golden
    $dl = [string]$DocDecl["$($n.File):$gl"]
    $cand = $(if ($dl) { @($rows | Where-Object { $_.Kind -ne 'stops' -and $_.File -eq $n.File -and (Test-GoldenDocLine $dl $gl $_.Line) }) }
              else { @($rows | Where-Object { $_.Kind -ne 'stops' -and $_.File -eq $n.File -and
                ($_.Line -eq $gl -or (($_.Routine -split '\.')[-1] -ceq $sym) -or $_.Subject -ceq $sym -or $_.Subject.EndsWith(".$sym", [StringComparison]::Ordinal)) }) })
    if ($cand.Count) {
      $b = @($cand | Sort-Object @{ E = { $(if ($_.Line -eq $gl) { 0 } else { 1 }) } }, @{ E = { $(if ($_.Kind -in 'step', 'crosses') { 0 } else { 1 }) } }, Seq)[0]
      $mb += "$($n.N)=$('{0:00}' -f $b.Step)$(if ($b.Kind -in 'cond', 'facet') { "/$($b.Kind)" })@$($b.Line)"
      continue
    }
    $st = @($rows | Where-Object { $_.Kind -eq 'stops' -and (Test-GoldenWord $_.Text $sym) })
    $sa = @($st | Where-Object { $_.Ask })
    if ($sa.Count) { $nd += "$($n.N):$($sa[0].Ask)" }
    elseif ($st.Count) { $nx += "$($n.N):$($n.Name) (a STOPS names it, with no ask)"; $nxN += "$($n.N)*" }
    else { $nx += "$($n.N):$($n.Name)"; $nxN += "$($n.N)" }
  }
  $gb = @(); $gd = @(); $gx = @(); $gxN = @()
  foreach ($g in $Inv.Guards) {
    $hit = @($rows | Where-Object { $_.Kind -eq 'cond' -and $_.File -eq $g.File -and $_.Line -eq [int]$g.Line -and $_.Text.Contains([string]$g.Word) })
    if ($hit.Count) { $gb += "$($g.G)@$('{0:00}' -f $hit[0].Step)"; continue }
    $st = @($rows | Where-Object { $_.Kind -eq 'stops' -and ($_.Text.Contains([string]$g.Word) -or ($_.File -eq $g.File -and $_.Line -eq [int]$g.Line)) })
    $sa = @($st | Where-Object { $_.Ask })
    if ($sa.Count) { $gd += "$($g.G):$($sa[0].Ask)" }
    elseif ($st.Count) { $gx += "$($g.G):$($g.Name) (a STOPS names it, with no ask)"; $gxN += "$($g.G)*" }
    else { $gx += "$($g.G):$($g.Name)"; $gxN += "$($g.G)" }
  }
  $fd = @(); $fp = @()
  foreach ($f in $Facts) {
    $on = @($rows | Where-Object { $_.File -eq $f.File -and $_.Line -eq [int]$f.Line })
    if ($on.Count) { $fp += "$($f.File):$($f.Line)@$('{0:00}' -f $on[0].Step)" } else { $fd += "$($f.File):$($f.Line) $($f.What)" }
  }
  $un = @($rows | Where-Object { -not $_.Anchored } | ForEach-Object { '{0:00}' -f $_.Step })
  [pscustomobject]@{ Matched = $mb.Count; MatchedBy = ($mb -join ','); Disclosed = ($nd -join ','); Missing = ($nx -join '|'); MissingN = ($nxN -join ',')
                     GuardsMatched = $gb.Count; GuardsBy = ($gb -join ','); GuardsDisclosed = ($gd -join ','); GuardsMissing = ($gx -join '|'); GuardsMissingN = ($gxN -join ',')
                     FactsDisclosed = ($fd -join ','); FactsDisclosedN = $fd.Count; FactsOnPage = ($fp -join ','); Unanchored = ($un -join ',') }
}
# I1: which golden lines are a line of the comment block directly above a declaration, from INDEX facts only (no
# source text): a symbol_docs span holding the line gives its symbol's declaration; otherwise the next declaration
# below the line (the first symbol starting after it) owns the line when `comment` string_literals cover EVERY line
# from the golden line down to that declaration and no symbol, ref or other literal lies between. Each clone that
# indexes the file answers ON ITS OWN (CLIENT, SERVER, SQL are never unioned); the answers must agree, or the line
# gets no tolerance. Returns `<file leaf>:<golden line>` -> the declaration line, for the lines that qualify.
function Get-GoldenDocDecl($Inv, [string[]] $Dbs) {
  $votes = @{}
  $leaves = @($Inv.Nodes | ForEach-Object { [string]$_.File } | Select-Object -Unique)
  foreach ($db in $Dbs) {
    $fr = Rows $db ('SELECT id AS fid, path AS p FROM files WHERE ' + (($leaves | ForEach-Object { "path LIKE '%\$(ConvertTo-SqlText $_)'" }) -join ' OR '))
    $fidOf = @{}
    foreach ($leaf in $leaves) { $h = @($fr | Where-Object { [IO.Path]::GetFileName([string]$_.p) -eq $leaf }); if ($h.Count -eq 1) { $fidOf[$leaf] = [int]$h[0].fid } }
    $parts = @(foreach ($n in $Inv.Nodes) {
      if (-not $fidOf.ContainsKey([string]$n.File)) { continue }
      $gl = [int]$n.Golden; $fid = $fidOf[[string]$n.File]
      $ndq = "(SELECT MIN(s.start_line) FROM symbols s WHERE s.file_id = $fid AND s.start_line > $gl)"
      $in = { param($a) "($a.start_line BETWEEN $gl AND $ndq - 1 OR $a.end_line BETWEEN $gl AND $ndq - 1)" }
      $dsq = { param($c) "(SELECT s.$c FROM symbol_docs d JOIN symbols s ON s.id = d.symbol_id WHERE s.file_id = $fid AND d.start_line <= $gl AND d.end_line >= $gl ORDER BY s.start_line LIMIT 1)" }
      $nsq = { param($c) "(SELECT MAX(s.$c) FROM symbols s WHERE s.file_id = $fid AND s.start_line = $ndq AND s.kind <> 'param')" }
      "SELECT $([int]$n.N) AS n, $ndq AS nd, $(& $nsq 'end_line') AS ne, $(& $nsq 'impl_start_line') AS ni, $(& $nsq 'impl_end_line') AS nie, " +
      "$(& $dsq 'start_line') AS dd, $(& $dsq 'end_line') AS de, $(& $dsq 'impl_start_line') AS di, $(& $dsq 'impl_end_line') AS die, " +
      "(SELECT COUNT(*) FROM symbols s WHERE s.file_id = $fid AND $(& $in 's')) + (SELECT COUNT(*) FROM refs r WHERE r.file_id = $fid AND $(& $in 'r')) + " +
      "(SELECT COUNT(*) FROM string_literals l WHERE l.file_id = $fid AND l.kind <> 'comment' AND $(& $in 'l')) AS other, " +
      "(SELECT group_concat(l.start_line || '-' || l.end_line) FROM string_literals l WHERE l.file_id = $fid AND l.kind = 'comment' AND l.end_line >= $gl AND l.start_line <= $ndq - 1) AS cm"
    })
    if (-not $parts.Count) { continue }
    foreach ($q in (Rows $db ($parts -join ' UNION ALL '))) {
      $n = @($Inv.Nodes | Where-Object { [int]$_.N -eq [int]$q.n })[0]
      $gl = [int]$n.Golden; $decl = ''
      if ([string]$q.dd) { $decl = "$([int]$q.dd)-$([int]$q.de)/$([int]$q.di)-$([int]$q.die)" }
      elseif ([string]$q.nd -and [int]$q.other -eq 0) {
        $cov = @{}
        foreach ($sp in @(([string]$q.cm) -split ',' | Where-Object { $_ })) { $ab = $sp -split '-'; for ($k = [int]$ab[0]; $k -le [int]$ab[1]; $k++) { $cov[$k] = $true } }
        if (@($gl..([int]$q.nd - 1) | Where-Object { -not $cov.ContainsKey($_) }).Count -eq 0) { $decl = "$([int]$q.nd)-$([int]$q.ne)/$([int]$q.ni)-$([int]$q.nie)" }
      }
      $k = "$($n.File):$gl"
      if (-not $votes.ContainsKey($k)) { $votes[$k] = @() }
      $votes[$k] += $decl
    }
  }
  # value: `<decl start>-<decl end>/<impl start>-<impl end>` (impl 0-0: no body, an interface method)
  $out = @{}
  foreach ($k in $votes.Keys) { $u = @($votes[$k] | Select-Object -Unique); if ($u.Count -eq 1 -and $u[0]) { $out[$k] = [string]$u[0] } }
  $out
}
# the lines a doc-line node's declaration owns: the golden line, the declaration, and its implementation (if any)
function Test-GoldenDocLine([string] $Span, [int] $Golden, [int] $Line) {
  $d = [int[]]($Span -split '[-/]')
  $Line -eq $Golden -or ($Line -ge $d[0] -and $Line -le $d[1]) -or ($d[2] -gt 0 -and $Line -ge $d[2] -and $Line -le $d[3])
}
# I4: every quoted condition occurs VERBATIM in the fresh source, starting on its anchor line. Skipped: the
# ` ... raises` form (an except handler -- the quote names the guarded statements, it is not a boolean) and the
# `case X of` form. The quote, whitespace collapsed, must start on the anchor line of the collapsed text that runs
# from that line on (a wrapped condition continues below it), at identifier boundaries, and NOT right behind a
# `not` it dropped. Only the anchored line and the lines a condition wraps onto are looked at; each file must be
# sha256-fresh against the clone that indexes it (Test-SourceFresh) -- a stale or unindexed file is a failure.
# Returns Bad/Checked/Skipped and Which (`<file>:<line>` of each failure).
function Measure-CondVerbatim($Rows, [string[]] $Dbs) {
  $pathOf = @{}; $srcOf = @{}; $bad = @(); $chk = 0; $skp = 0
  foreach ($r in @($Rows | Where-Object { $_.Kind -eq 'cond' })) {
    if ($r.Text -match ' raises$' -or $r.Text -match '^case .+ of$') { $skp++; continue }
    $chk++
    if (-not $pathOf.ContainsKey($r.File)) {
      $pathOf[$r.File] = $null
      foreach ($db in $Dbs) {
        $DbPath = Get-CloneDb $db
        $ps = @((Get-IndexedFileShas).Keys | Where-Object { [IO.Path]::GetFileName([string]$_) -eq $r.File })
        if ($ps.Count -eq 1) { $pathOf[$r.File] = @{ Db = $DbPath; Path = [string]$ps[0] }; break }
      }
    }
    $po = $pathOf[$r.File]
    if (-not $po) { $bad += "$($r.File):$($r.Line) (no clone indexes it)"; continue }
    $DbPath = $po.Db
    if (-not (Test-SourceFresh $po.Path)) { $bad += "$($r.File):$($r.Line) (stale)"; continue }
    if (-not $srcOf.ContainsKey($po.Path)) { $srcOf[$po.Path] = [IO.File]::ReadAllLines($po.Path) }
    $sl = $srcOf[$po.Path]
    if ($r.Line -lt 1 -or $r.Line -gt $sl.Count) { $bad += "$($r.File):$($r.Line) (no such line)"; continue }
    $q = ($r.Text -replace '\s+', ' ').Trim()
    $first = ($sl[$r.Line - 1] -replace '\s+', ' ').Trim()
    $w = ((@($sl[($r.Line - 1)..([Math]::Min($sl.Count, $r.Line + 19) - 1)]) -join ' ') -replace '\s+', ' ').Trim()
    $ok = $false; $i = $w.IndexOf($q, [StringComparison]::Ordinal)
    while (-not $ok -and $i -ge 0 -and $i -lt $first.Length) {
      $pre = $w.Substring(0, $i); $post = $w.Substring($i + $q.Length)
      $bL = -not ($q -match '^[A-Za-z0-9_]' -and $pre -match '[A-Za-z0-9_]$')
      $bR = -not ($q -match '[A-Za-z0-9_]$' -and $post -match '^[A-Za-z0-9_]')
      $ok = $bL -and $bR -and ($pre.TrimEnd() -notmatch '(?i)(^|[^A-Za-z0-9_])not$')
      $i = $w.IndexOf($q, $i + 1, [StringComparison]::Ordinal)
    }
    if (-not $ok) { $bad += "$($r.File):$($r.Line)" }
  }
  [pscustomobject]@{ Bad = $bad.Count; Checked = $chk; Skipped = $skp; Which = ($bad -join '|') }
}
# I2 (controller ruling, Task 6 review): the golden's READ [28]-[29] -- the BLOBS / WHERE keys at
# uPipeSessionBuilder.pas:533/:534 and the column list at :538 -- come from transport-convention helpers, not steps.
# They are DISCLOSED facts of THIS golden (the list describes the golden, not the walk).
$goldenFacts = @(
  [pscustomobject]@{ File = 'uPipeSessionBuilder.pas'; Line = 533; What = 'READ [28] READS BLOBS key' }
  [pscustomobject]@{ File = 'uPipeSessionBuilder.pas'; Line = 534; What = 'READ [28] READS WHERE key' }
  [pscustomobject]@{ File = 'uPipeSessionBuilder.pas'; Line = 538; What = 'READ [29] BUILDS column list FROM Def.NonBlobCols' })
$res.GoldenFactsReason = 'transport-convention helper, not a step'
$docDecl = Get-GoldenDocDecl $inv @($DbCli, $DbSrv, $DbSql)
$res.GoldenDocDecl = (@($docDecl.Keys | Sort-Object | ForEach-Object { "$_=$($docDecl[$_])" })) -join ','
$T7 = Read-FormA $txt
$gm7 = Measure-GoldenMatch $T7 $inv $docDecl $goldenFacts
$res.GoldenMatched = $gm7.Matched; $res.GoldenMatchedBy = $gm7.MatchedBy; $res.GoldenDisclosed = $gm7.Disclosed; $res.GoldenMissing = $gm7.Missing
$res.GuardsMatched = $gm7.GuardsMatched; $res.GuardsBy = $gm7.GuardsBy; $res.GuardsDisclosed = $gm7.GuardsDisclosed; $res.GuardsMissing = $gm7.GuardsMissing
$res.GoldenFactsDisclosed = $gm7.FactsDisclosed; $res.GoldenFactsDisclosedN = $gm7.FactsDisclosedN; $res.GoldenFactsOnPage = $gm7.FactsOnPage; $res.GoldenUnanchored = $gm7.Unanchored
# I1 negative: the SAME trace without the far-side CONTRACT @Pipes.Protocol.pas:392 -- node 6 must turn MISSING, not
# fall back to the TCommandID.cmdDelta constant @:55 (which it read as matched before the doc-line rule)
$res.GoldenDocNeg = $(try {
  $Tn = Read-FormA $txt
  foreach ($s in $Tn.Sections) { foreach ($i in $s.Items) { foreach ($ch in @($i.Children)) { if ($ch.Anchor -eq 'Pipes.Protocol.pas:392') { $i.Children.Remove($ch) } } } }
  $gN = Measure-GoldenMatch $Tn $inv $docDecl $goldenFacts
  "$($gN.MissingN)|$($gN.Matched)"
} catch { "threw: $($_.Exception.Message)" })
# M: an item with no anchor (the P14 case) is reported -- its node MISSING, its step counted unanchored -- never a
# throw (it threw a Substring / null-method error before). [05] READS FDsrOperation @VM:99 is node 2's only row:
# its anchor nulled, and [07]'s cut to a colon-less `Blueprint4.ViewModel.pas` (node 1 keeps [44] LOADS FMTOperation)
$res.GoldenUnanchoredNeg = $(try {
  $Tu = Read-FormA $txt
  $uAll = @($Tu.Sections | ForEach-Object { $_.Items })
  @($uAll | Where-Object { $_.Anchor -eq 'Blueprint4.ViewModel.pas:99' })[0].Anchor = $null
  @($uAll | Where-Object { $_.Anchor -eq 'Blueprint4.ViewModel.pas:78' })[0].Anchor = 'Blueprint4.ViewModel.pas'
  $gU = Measure-GoldenMatch $Tu $inv $docDecl $goldenFacts
  "$($gU.Unanchored)|$($gU.MissingN)|$($gU.Matched)"
} catch { "threw: $($_.Exception.Message)" })
# the matcher can say all three things (proven on a synthetic trace, not merely on the one that passes):
# LoadOneTable matched; a MENTION of LoadAllForFolder, and GetTable in the wrong file, not matched; a STOPS
# with its ask discloses HandleTableLoad; a STOPS naming PushTableChanged with NO ask does not disclose it.
# Guards: 3950 matched; ChangeCount one line off (3972) not matched, but disclosed by a STOPS at 3973 with E1.
$Tm = New-Trace 'X' 'x' 'x' 'A' '2026-09-28' 'x' 'client -> server'
$sm = Add-TraceSection $Tm 'WRITE'
$m1 = New-TraceStep 'step' 'CALLS TBlueprint_ViewModel.LoadOneTable' 'Blueprint4.ViewModel.pas:1123'
[void]$m1.Children.Add((New-TraceCond 'UNLESS' 'FSuppressEvents' 'Blueprint4.ViewModel.pas:3950'))
[void]$m1.Children.Add((New-TraceCond 'UNLESS' 'FMTOperation.ChangeCount = 0' 'Blueprint4.ViewModel.pas:3972'))
[void]$sm.Items.Add($m1)
[void]$sm.Items.Add((New-TraceStep 'step' 'SETS P := LoadAllForFolder' 'Blueprint4.ViewModel.pas:10' '' 'TBlueprint_ViewModel.Create'))
[void]$sm.Items.Add((New-TraceStep 'step' 'CALLS TDatasetsDef.GetTable' 'uOther.pas:5'))
[void]$sm.Items.Add((New-TraceStep 'stops' 'HandleTableLoad is not reached from the dispatch' 'uPipeSessionBuilder.pas:1' '' '' '' 'E2'))
[void]$sm.Items.Add((New-TraceStep 'stops' 'the PushTableChanged call is unbound' 'uGenericTableRoute.pas:507'))
[void]$sm.Items.Add((New-TraceStep 'stops' 'the ChangeCount guard is not quoted' 'Blueprint4.ViewModel.pas:3973' '' '' '' 'E1'))
# I2: a walk that starts producing a disclosed golden fact as a step moves it from disclosed to on-page
[void]$sm.Items.Add((New-TraceStep 'step' 'READS BLOBS key' 'uPipeSessionBuilder.pas:533'))
$gmS = Measure-GoldenMatch (Read-FormA (Write-FormA $Tm)) $inv $docDecl $goldenFacts
$res.GoldenClassify = "$($gmS.MatchedBy) | $($gmS.Disclosed) | $($gmS.MissingN) || $($gmS.GuardsBy) | $($gmS.GuardsDisclosed) | $($gmS.GuardsMissingN)"
$res.GoldenFactsProduced = "$($gmS.FactsDisclosedN) || $($gmS.FactsOnPage)"
# AC-1 on the REAL trace, and the verb set it yields: Test-FormA now reads the verb AFTER an actor word
# (`[47] SERVER ROUTES ...`), which a numbered line starting at column 1 used to skip as a section header
$res.TraceVerbs = & (Join-Path $PSScriptRoot 'Test-FormA.ps1') -Fixture $rt.Trace -Quiet -PassThru
$res.TraceFormA = $LASTEXITCODE
$res.GoldenVerbs = & (Join-Path $PSScriptRoot 'Test-FormA.ps1') -Quiet -PassThru
# ... and so garbage behind an actor word is unclassified (it passed as a "section header" before)
[IO.File]::WriteAllText((Join-Path $work 'trace-actor-mut.dlgraph'), ($txt -replace '\] SERVER CALLS TPipeSessionBuilder\.HandleTableLoad', '] SERVER 42 TPipeSessionBuilder.HandleTableLoad'), (New-Object Text.ASCIIEncoding))
& (Join-Path $PSScriptRoot 'Test-FormA.ps1') -Fixture (Join-Path $work 'trace-actor-mut.dlgraph') -Quiet 6>$null | Out-Null
$res.TraceFormAActorMut = $LASTEXITCODE
# AC-2, AC-4
$res.TraceRoundTrip = $(if ((Write-FormA $T7) -ceq $txt) { 'identical' } else { 'differs' })
$tb = [IO.File]::ReadAllBytes($rt.Trace)
$res.TraceBytes = "$(@($tb | Where-Object { $_ -ne 0x0D -and $_ -ne 0x0A -and ($_ -lt 0x20 -or $_ -gt 0x7E) }).Count)/$(([regex]::Matches($txt, '(?<!\r)\n')).Count)/$(if ($tb[0] -eq 0xEF) { 'BOM' } else { 'noBOM' })"
# AC-11 / P14: every step line is a clickable source span, COMPUTED by the emitter (AllClickable) and here from
# the text -- and the check FAILS when one anchor is removed
$res.TraceAnchors = "$(@(Get-TraceUnclickable $txt).Count)/$($rt.ClickTargets)/$($rt.AllClickable)"
$cut = $txt -replace ' @Blueprint4\.ViewModel\.pas:78 -- the anchor dataset', ' -- the anchor dataset'
$res.TraceAnchorsCut = "$(@(Get-TraceUnclickable $cut).Count)/$($cut -ne $txt)"
# T4-C3: a case guard quotes its source line verbatim through `of`; the else arm is the generated note
$res.TraceCaseCond = (@($txt -split "\r\n" | Where-Object { $_ -match '^       (WHEN|UNLESS) "case ' } | ForEach-Object { $_.Trim() }) -join ' | ')
# I4 (replaces the `not (` heuristic): every condition quoted verbatim from the fresh source at its anchor line
$cv = Measure-CondVerbatim (Get-GoldenRows $T7) @($DbCli, $DbSrv)
$res.TraceNegated = "$($cv.Bad)/$($cv.Checked)/$($cv.Skipped)$(if ($cv.Which) { " $($cv.Which)" })"
# ... and it goes RED on a mutated condition: a `not ` prefixed to one quote, and a `not ` dropped from another
$res.TraceNegatedMut = $(try {
  (@(@('FSuppressEvents', 'not FSuppressEvents'), @('not GDatasetsDef.GetTable(TableName, Def)', 'GDatasetsDef.GetTable(TableName, Def)')) | ForEach-Object {
    $mu = $_
    $Tx = Read-FormA $txt
    foreach ($s in $Tx.Sections) { foreach ($i in $s.Items) { foreach ($ch in $i.Children) { if ($ch.Kind -eq 'cond' -and $ch.Condition -ceq $mu[0]) { $ch.Condition = $mu[1] } } } }
    $cx = Measure-CondVerbatim (Get-GoldenRows $Tx) @($DbCli, $DbSrv)
    "$($cx.Bad):$($cx.Which)" }) -join ','
} catch { "threw: $($_.Exception.Message)" })

# ---- 9. the holdout (AC-16): dxDBGrid1FtrsVNum -> MSCLIST.NUM, accepted by the owner on 2026-09-28 ----
# A second edited field through a different dataset (FMTFtrs) and sender (SendDeltaFtrs) than OPERAT.NAME. The owner
# compared this trace with the OPERAT.NAME trace and the golden and checked the path's shape, not every line. FtrName
# (the brief's default) is a CALCULATED field of FMTFtrs (Blueprint4.ViewModel.pas:756), no DB column, so not a holdout.
# Ruling T9-R1: the three line patterns are what the trace WRITES (the re-point is `.DataSource`, not
# `.DataController.DataSource`; the sender call carries its 'AfterPost' argument), each anchored to its line.
$rh = & (Join-Path $PSScriptRoot 'Emit-RoundTrip.ps1') -Target 'frmBlueprint4.dxDBGrid1FtrsVNum' -DbPath $DbCli -ServerDbPath $DbSrv -SqlDbPath $DbSql -OutDir $work 6>$null
$res.HoldCounts = "$($rh.Steps)/$($rh.Conditions)/$($rh.Crossings)/$($rh.Unresolved)"
$res.HoldAnchor = "$($rh.TableColumn):$($rh.DataSet)"
$hl = $rh.Text -split "\r\n"
$res.HoldSender = (@($hl | Where-Object { $_ -match "^\[\d+\] CALLS TBlueprint_ViewModel\.SendDeltaFtrs 'AfterPost' @Blueprint4\.ViewModel\.pas:3565 -- " })).Count
$res.HoldCancel = (@($hl | Where-Object { $_ -match '^       UNLESS ".*<> rspOK\)" @Blueprint4\.ViewModel\.pas:3599 -- else .*FMTFtrs\.CancelUpdates @Blueprint4\.ViewModel\.pas:3611' })).Count
$res.HoldRePoint = (@($hl | Where-Object { $_ -match '^\[\d+\] SETS dxDBGrid1FtrsV\.DataSource := FBlueprint_ViewModel\.pdsrFtrs @Blueprint4\.pas:2283 -- in FormShow$' })).Count
# fix wave (FW-R1): the same per-statement load lines as OPERAT.NAME's A-RT5-STOPS, on a DIFFERENT anchor table
# (MSCLIST) -- proves the derivation is generic, not hard-coded to OPERAT's :148/:149/:150
$res.HoldStops = @(@($hl | Where-Object { $_ -match '^\[\d+\] STOPS the statement for the posted MSCLIST row ' }) | ForEach-Object { ($_ -replace '^\[\d+\] STOPS ', '') -replace ' @.*$', '' })[0]
& (Join-Path $PSScriptRoot 'Test-FormA.ps1') -Fixture $rh.Trace -Quiet 6>$null | Out-Null
$res.HoldFormA = $LASTEXITCODE
# final-review I6: CoerceMSCLISTPlanIds' conditions in evaluation order -- the caller's enclosing branch first
$hcAt = [array]::FindIndex($hl, [Predicate[string]]{ param($l) $l -match '^\[\d+\] CALLS CoerceMSCLISTPlanIds ' })
$hcC = @(); if ($hcAt -ge 0) { for ($q = $hcAt + 1; $q -lt $hl.Count -and $hl[$q] -match '^       (WHEN|UNLESS) '; $q++) { $hcC += (($hl[$q].Trim()) -replace ' -- .*$', '') } }
$res.HoldCoerceConds = $hcC -join ' | '

# ---- 10. the final review (I1, I2, I4-I8, M2, M3, M7) ------------------------------------------
# Synthetic walks: Walk-Routine over a routine written to a scratch .pas, its facts injected into the walk's own
# caches (RtFacts; the sha map Test-SourceFresh reads, keyed by a synthetic $DbPath) -- NO index is read. A ref is
# a hashtable of Get-RoutineFacts columns; `at` names the token whose FIRST occurrence on its line is the ref's
# 1-based start_col. Returns the walk's Items and Conds.
function Invoke-SynthWalk([string] $Name, [string[]] $Src, $Refs, [string] $Table = 'OPERAT', [string[]] $Tables = @('OPERAT', 'MSCLIST'), $Lits = @()) {
  $DbPath = "synth:$Name"
  $p = Join-Path $work "$Name.pas"
  [IO.File]::WriteAllText($p, (($Src -join "`r`n") + "`r`n"), (New-Object Text.ASCIIEncoding))
  if (-not $script:DlFileShas) { $script:DlFileShas = @{} }
  $script:DlFileShas[$DbPath] = @{ $p = (Get-FileHash -Algorithm SHA256 -LiteralPath $p).Hash }
  $cols = 'rid', 'kind', 'nm', 'recv', 'line', 'col', 'ecol', 'tid', 'tkind', 'tname', 'tq', 'tistart', 'tdecl', 'tpath', 'tfid', 'tpipe'
  $rs = @(foreach ($r in $Refs) {
    $o = [ordered]@{}; foreach ($c in $cols) { $o[$c] = $(if ($r.ContainsKey($c)) { $r[$c] } else { $null }) }
    if ($r.ContainsKey('at')) { $o.col = $Src[[int]$r.line - 1].IndexOf([string]$r.at) + 1 }
    [pscustomobject]$o })
  $ls = @(foreach ($l in $Lits) { $c = $Src[[int]$l.line - 1].IndexOf("'$($l.text)'") + 1; [pscustomobject]@{ kind = 'literal'; text = $l.text; line = $l.line; col = $c; ecol = $c + ([string]$l.text).Length + 2 } })
  $script:RtFacts["$DbPath|1"] = [pscustomobject]@{ Id = 1; Name = 'P'; Qname = 'uSynth.TSynth.P'; Short = 'TSynth.P'; Path = $p; Fid = 1; Pid = 0
                                                     ImplStart = 1; ImplEnd = $Src.Count; Decl = 1; SqlReads = ''; SqlWrites = ''; Refs = $rs; Lits = $ls }
  $ctx = @{ Table = $Table; Column = 'X'; TableColumn = "$Table.X"; DataSet = $null; SqlSet = [pscustomobject]@{ Names = $Tables }; SourceOverride = $null
            Likes = '1 = 0'; NearIndex = 'A'; FarIndex = 'B'; Seen = @{} }
  Walk-Routine 1 4 @{} $ctx
}
# a walk as text: `<step head> [<cond>, <cond>]` per item, ' > ' between; then ` || pending: <conds>`
function Format-SynthWalk($W) {
  $fc = { param($c) "$($c.Keyword) $($c.Condition)$(if ($c.Note) { " ($($c.Note))" })" }
  $it = @($W.Items | ForEach-Object { "$($_.Text) [$((@($_.Children | Where-Object { $_.Kind -eq 'cond' } | ForEach-Object { & $fc $_ })) -join ', ')]" })
  "$($it -join ' > ') || pending: $((@($W.Conds | ForEach-Object { & $fc $_ })) -join ', ')"
}
# I1: an Exit guard's IfLine is walked for its CONDITION only. `if X then begin FMT.CancelUpdates; Exit; end;`
# wrote APPLIES FMT.CancelUpdates as a path step with UNLESS "X" hung on it (inverted) AND named it in the else
# note; an `ARspCmd:= rspError` after the `then` was a SENDS. P2: a WHEN guard (Exit in the else) keeps its then
# branch as the path, and its else note names only the else branch.
$res.FinI1Walk = $(try {
  $s1 = @('procedure TSynth.P;', 'begin', '  FMT.SaveToStream(MS);', '  if not Ready then begin FMT.CancelUpdates; Exit; end;',
          '  if Failed then begin ARspCmd:= rspError; Exit; end;', '  FMT.ApplyUpdates;', 'end;')
  $r1 = @(@{ kind = 'call'; nm = 'SaveToStream'; recv = 'FMT'; line = 3; at = 'SaveToStream' }, @{ kind = 'read'; nm = 'Ready'; line = 4; at = 'Ready' },
          @{ kind = 'call'; nm = 'CancelUpdates'; recv = 'FMT'; line = 4; at = 'CancelUpdates' }, @{ kind = 'call'; nm = 'Exit'; line = 4; at = 'Exit' },
          @{ kind = 'read'; nm = 'Failed'; line = 5; at = 'Failed' }, @{ kind = 'write'; nm = 'ARspCmd'; tkind = 'param'; line = 5; at = 'ARspCmd' },
          @{ kind = 'read'; nm = 'rspError'; tkind = 'enum_value'; tname = 'rspError'; line = 5; at = 'rspError' }, @{ kind = 'call'; nm = 'Exit'; line = 5; at = 'Exit' },
          @{ kind = 'call'; nm = 'ApplyUpdates'; recv = 'FMT'; line = 6; at = 'ApplyUpdates' })
  $s2 = @('procedure TSynth.P;', 'begin', '  if Ready then FMT.ApplyUpdates else begin FMT.CancelUpdates; Exit; end;', 'end;')
  $r2 = @(@{ kind = 'read'; nm = 'Ready'; line = 3; at = 'Ready' }, @{ kind = 'call'; nm = 'ApplyUpdates'; recv = 'FMT'; line = 3; at = 'ApplyUpdates' },
          @{ kind = 'call'; nm = 'CancelUpdates'; recv = 'FMT'; line = 3; at = 'CancelUpdates' }, @{ kind = 'call'; nm = 'Exit'; line = 3; at = 'Exit' })
  "$(Format-SynthWalk (Invoke-SynthWalk 'fin-i1a' $s1 $r1)) ## $(Format-SynthWalk (Invoke-SynthWalk 'fin-i1b' $s2 $r2))"
} catch { "threw: $($_.Exception.Message)" })
# I1: the failure span on a guard's `then` line (0-based [From,To) of the stripped line), pure: a then-branch Exit
# up to its `;`, a statement after it on the line is the path; an else-branch Exit from its else; a nested if takes
# its own else; an else on a later line leaves the then line alone
$res.FinI1Span = $(try {
  # (line, keyword, which `then` is the guard's: 0 = the first)
  (@(@('  if A then Exit; Foo;', 'UNLESS', 0), @('  if A then Foo else Exit;', 'WHEN', 0), @('  if A then begin if B then X else Y; Exit; end;', 'UNLESS', 0),
     @('  if A then if B then Exit else Y;', 'UNLESS', 1), @('  if A then Foo', 'WHEN', 0)) | ForEach-Object {
    $ln = $_[0]; $th = @([regex]::Matches($ln, '\bthen\b'))[$_[2]].Index
    $sp = Get-GuardFailSpan ([pscustomobject]@{ Keyword = $_[1]; CondL2 = 1; CondC2 = $th }) $ln
    $(if ($sp) { "[$($ln.Substring($sp.From, $sp.To - $sp.From).Trim())]" } else { '[]' }) }) -join ','
} catch { "threw: $($_.Exception.Message)" })
# I4: the WRITE direction starts at the preferred event -- AfterPost wired BELOW an AfterDelete (and a BeforePost)
$res.FinI4Wiring = $(try {
  # assigned directly: Sort-RtWiring keeps its array whole with a unary comma (@(...) would nest it)
  $sw = Sort-RtWiring @([pscustomobject]@{ Event = 'AfterDelete'; Line = 10 }, [pscustomobject]@{ Event = 'AfterPost'; Line = 20 },
                        [pscustomobject]@{ Event = 'BeforePost'; Line = 5 }, [pscustomobject]@{ Event = 'AfterPost'; Line = 15 })
  (@($sw | ForEach-Object { "$($_.Event)@$($_.Line)" })) -join ','
} catch { "threw: $($_.Exception.Message)" })
# I5: a line one if DEEPER inside another table's branch is omitted too -- the whole enclosing chain is tested
$res.FinI5Omits = $(try {
  $s5 = @('procedure TSynth.P;', 'begin', "  if T = 'MSCLIST' then", '  begin', '    if N > 0 then FMT.ApplyUpdates;', '  end;', '  FMT.CommitUpdates;', 'end;')
  $r5 = @(@{ kind = 'read'; nm = 'T'; line = 3; at = 'T =' }, @{ kind = 'read'; nm = 'N'; line = 5; at = 'N >' },
          @{ kind = 'call'; nm = 'ApplyUpdates'; recv = 'FMT'; line = 5; at = 'ApplyUpdates' }, @{ kind = 'call'; nm = 'CommitUpdates'; recv = 'FMT'; line = 7; at = 'CommitUpdates' })
  $w5 = Invoke-SynthWalk 'fin-i5' $s5 $r5 -Lits @(@{ text = 'MSCLIST'; line = 3 })
  (@($w5.Items | ForEach-Object { "$($_.Text)$(if ($_.Note) { " -- $($_.Note)" })" })) -join ' > '
} catch { "threw: $($_.Exception.Message)" })
# M2: the ask on every ANCHOR step (`<NN>=<ask>`, '-' for none) -- E4 on a designer-chain hop or on the table-literal hop
# was a wrong ask: the rhs-type [by name] hop names type-use-binding (no type_use ref is bound), the table literal none
$askOf = { param($t) (@(($t -split "\r\n") | Where-Object { $_ -cmatch '^\[\d+\] ' } | ForEach-Object { $n = $_.Substring(1, 2); $(if ($_ -match '; ask (\S+)$|-- ask (\S+)$') { "$n=$($Matches[1])$($Matches[2])" } else { "$n=-" }) } | Select-Object -First 9)) -join ',' }
$res.FinM2Asks = "$(& $askOf $txt) || $(if ($rtO.PSObject.Properties['Text']) { & $askOf $rtO.Text })"
# M3: the header's AS OF is each index's own schema_meta indexed_at_unix, UTC to the minute (was the CLIENT file's date)
$res.FinM3AsOf = @($txt -split "\r\n" | Where-Object { $_ -clike '  INDEX *' })[0]

# ---- 11. a CALCULATED anchor field offers its sources (calc-field brief, owner 2026-09-28) ----------------
# frmBlueprint4.dxDBGrid1FtrsVFtrName stopped at [09] "MSCLIST.FTRNAME: not extracted as a column ..." -- true, but
# not WHY. FtrName is one of the 12 calculated fields of FMTFtrs (Blueprint4.ViewModel.pas:756, C(FMTFtrs,
# 'FtrName', ...)), written by FtrsOnCalcFields (wired :790) at :986-993 from 17 TField variables and the local
# FtrType (:978). The corpus facts are the TEST, never the rule: Trace.Walk Part 6 names no form, dataset or field.
# A trace as its pinnable parts: title | the STOPS line | its conditions and facets | the DERIVED note | each row
# `<text> => <target>` | counts | Test-FormA exit | Read-FormA round trip | all clickable
function Get-CalcTraceParts($R) {
  $l = $R.Text -split "\r\n"
  $si = [array]::FindIndex($l, [Predicate[string]]{ param($x) $x -cmatch '^\[\d+\] STOPS ' })
  $ch = @(); if ($si -ge 0) { for ($q = $si + 1; $q -lt $l.Count -and $l[$q] -cmatch '^       '; $q++) { $ch += $l[$q].Trim() } }
  & (Join-Path $PSScriptRoot 'Test-FormA.ps1') -Fixture $R.Trace -Quiet 6>$null | Out-Null
  $fa = $LASTEXITCODE
  $rtp = $(try { if ((Write-FormA (Read-FormA $R.Text)) -ceq $R.Text) { 'identical' } else { 'differs' } } catch { "threw: $($_.Exception.Message)" })
  [pscustomobject]@{ Title = $R.Title; Stop = $(if ($si -ge 0) { $l[$si] -replace '^\[\d+\] ', '' } else { '' }); Children = $ch -join ' | '
                     Note = $R.DerivedNote; Rows = @($R.Derived) -join ' ## '; Counts = "$($R.Steps)/$($R.Conditions)/$($R.Crossings)/$($R.Unresolved)"
                     Check = "$fa|$rtp|$($R.AllClickable)|$($R.Sections)|$($R.Notes)" }
}
$rcF = & (Join-Path $PSScriptRoot 'Emit-RoundTrip.ps1') -Target 'frmBlueprint4.dxDBGrid1FtrsVFtrName' -DbPath $DbCli -ServerDbPath $DbSrv -SqlDbPath $DbSql -OutDir $work 6>$null
$pF = Get-CalcTraceParts $rcF
$res.CalcFtrTitle = $pF.Title; $res.CalcFtrStop = $pF.Stop; $res.CalcFtrChildren = $pF.Children; $res.CalcFtrNote = $pF.Note
$res.CalcFtrRows = $pF.Rows; $res.CalcFtrCounts = $pF.Counts; $res.CalcFtrCheck = $pF.Check
# the second corpus case: Tolerance (:760) -- five writes in a nested case, four source fields
$rcT = & (Join-Path $PSScriptRoot 'Emit-RoundTrip.ps1') -Target 'frmBlueprint4.dxDBGrid1FtrsVTolerance' -DbPath $DbCli -ServerDbPath $DbSrv -SqlDbPath $DbSql -OutDir $work 6>$null
$pT = Get-CalcTraceParts $rcT
$res.CalcTolTitle = $pT.Title; $res.CalcTolStop = $pT.Stop; $res.CalcTolChildren = $pT.Children; $res.CalcTolNote = $pT.Note
$res.CalcTolRows = $pT.Rows; $res.CalcTolCounts = $pT.Counts; $res.CalcTolCheck = $pT.Check
# ONE candidate's command, run END TO END exactly as the row writes it (New-DiagramArtifact.ps1 from this folder,
# the bundle under $work): the DimAbbr row -> MSCLIST.DIMABBR through FMTFtrs and SendDeltaFtrs
$res.CalcE2E = $(try {
  $cmd = @($rcF.DerivedCommands | Where-Object { $_ -match '-Target \S+\.FfFtrs_DimAbbr ' })[0]
  $art = Invoke-Expression ("& '$(Join-Path $PSScriptRoot 'New-DiagramArtifact.ps1')'" + $cmd.Substring('New-DiagramArtifact.ps1'.Length) + " -OutRoot '$(Join-Path $work 'calc-e2e')'") 6>$null
  $et = [IO.File]::ReadAllText((Join-Path $art.Bundle 'trace.dlgraph'))
  $end = @($et -split "\r\n" | Where-Object { $_ -clike 'END TRACE*' })[0]
  $ttl = $(if ($et -cmatch '(?m)^  TITLE "([^"]*)"\r$') { $Matches[1] } else { '' })
  "$ttl|$end"
} catch { "threw: $($_.Exception.Message)" })

# Synthetic facts (NO index): Resolve-CalcField and New-CalcFieldItems are pure over them. The handler is written to
# a scratch .pas so the shim reads its stripped copy; each ref is `kind:name[:receiver|!boundkind]`, placed left to
# right on its line (the column of the next whole-word match).
function New-SynthCalcRefs([string[]] $Src, [hashtable] $Spec) {
  foreach ($ln in @($Spec.Keys | Sort-Object)) {
    $pos = 0
    foreach ($it in $Spec[$ln]) {
      $kind, $nm, $x = $it -split ':', 3
      $m = [regex]::Match($Src[$ln - 1].Substring($pos), "\b$([regex]::Escape($nm))\b")
      if (-not $m.Success) { throw "New-SynthCalcRefs: $nm not on line $ln after column $pos" }
      $c = $pos + $m.Index + 1; $pos = $c - 1 + $nm.Length
      [pscustomobject]@{ kind = $kind; nm = $nm; recv = $(if ($x -and $x -notlike '!*') { $x } else { $null }); line = $ln; col = $c; ecol = $c + $nm.Length
                         tid = $(if ($x -like '!*') { 1 } else { $null }); tkind = $(if ($x -like '!*') { $x.Substring(1) } else { $null }); tdecl = 0; tpath = $null }
    }
  }
}
function New-SynthCalcFacts([string] $Name, [string[]] $Src, [hashtable] $Spec, [string] $Field = 'A', [string[]] $Vars = @('FfA'), [string] $Event = 'OnCalcFields', $Creating = $null) {
  $p = Join-Path $work "$Name.pas"
  [IO.File]::WriteAllText($p, (($Src -join "`r`n") + "`r`n"), (New-Object Text.ASCIIEncoding))
  $H = [pscustomobject]@{ Name = 'CalcH'; Path = $p; ImplStart = 1; ImplEnd = $Src.Count; Refs = @(New-SynthCalcRefs $Src $Spec)
                          Locals = @{ L = 'local_var'; DataSet = 'param' }; Raw = $Src; Stripped = (Get-StrippedSourceLines $p) }
  $bind = @{}
  foreach ($v in 'FfA', 'FfB', 'FfC', 'FfK') {
    $bind[$v] = [pscustomobject]@{ Var = $v; Why = ''; DataSet = 'FMT'; Literal = $v.Substring(2); Line = 30; Path = $p; Qname = "uSynth.TSynth.$v"; Grade = 'inferred'; Reason = 'via FF'; Ask = '' }
  }
  $bind['FfZ'] = [pscustomobject]@{ Var = 'FfZ'; Why = 'is written on 2 line(s) naming 2 (dataset field, column literal) pairs' }
  [pscustomobject]@{ Field = $Field; DsName = 'FMT'; Table = 'T'; ClassName = 'TSynth'; Vars = $Vars; Bindings = $bind
                     ClassFields = @{ FfA = 'TField'; FfB = 'TField'; FfC = 'TField'; FfK = 'TField'; FfZ = 'TField'; FNum = 'Integer'; FMT = 'TFDMemTable' }
                     Wirings = @($(if ($Event) { [pscustomobject]@{ Event = $Event; Line = 20; Handler = 'CalcH'; WirePath = $p; H = $H } }))
                     Creating = $Creating; IsColumn = { param($F, $l) $l -in 'B', 'K' } }
}
# a calculated result as one string: kind | stop text | conditions and facets | the DERIVED note | rows `<text> => <target>`
function Format-SynthCalc($Info) {
  if (-not $Info) { return 'not calculated' }
  if ($Info.Kind -ne 'calculated') { return "$($Info.Kind) | $($Info.StopText) @$($Info.Anchor)" }
  $it = New-CalcFieldItems $Info { param($t) "CMD $t" }
  $ch = @($it.Stop.Children | ForEach-Object { if ($_.Kind -eq 'cond') { "$($_.Keyword) $($_.Condition)$(if ($_.Note) { " -- $($_.Note)" })" } else { "$($_.Head) $($_.Text) -- $($_.Note)" } })
  $rw = @($it.Rows | ForEach-Object { "$($_.Text)$(if ($_.Grade) { " [$($_.Grade)]" }) => $(@($_.Children | ForEach-Object { $_.Text }) -join '')" })
  "calculated | $($it.Stop.Text) @$($it.Stop.Anchor) | $($ch -join ' / ') | $($it.Note) | $($rw -join ' ## ')"
}
$synSrc = @('procedure TSynth.CalcH(DataSet: TDataSet);', 'var', '  L: Integer;', 'begin', '  if DataSet.State = dsInsert then Exit;', '  L:= TagOf(FfK);',
            '  if Assigned(FfA) then', '    FfA.AsString:= Fmt(FfB.AsString, L, FfC.AsFloat, Zz, FNum, FfZ.AsString);', '  FfC.AsFloat:= FfB.AsFloat * 2;', 'end;')
$synSpec = @{ 5 = @('read:DataSet', 'member-access:State:DataSet', 'read:dsInsert:!enum_value', 'call:Exit'); 6 = @('write:L', 'call:TagOf', 'read:FfK')
              7 = @('call:Assigned', 'read:FfA'); 8 = @('read:FfA', 'member-access:AsString:FfA', 'call:Fmt', 'read:FfB', 'member-access:AsString:FfB', 'read:L', 'read:FfC',
              'member-access:AsFloat:FfC', 'read:Zz', 'read:FNum', 'read:FfZ', 'member-access:AsString:FfZ'); 9 = @('read:FfC', 'member-access:AsFloat:FfC', 'read:FfB', 'member-access:AsFloat:FfB') }
# the positive: the Exit guard and the enclosing if, verbatim; B a column, L one hop to K, C itself calculated (marked,
# not expanded), Zz / FNum / FfZ named and NOT guessed; the head call Fmt named once
$res.CalcSynOffer = $(try { Format-SynthCalc (Resolve-CalcField (New-SynthCalcFacts 'calc-syn' $synSrc $synSpec)) } catch { "threw: $($_.Exception.Message)" })
# negative 1: a field CREATED calculated (its creating call sets fkCalculated) whose dataset has NO OnCalcFields wiring ->
# not calculated by this rule (the caller keeps today's stop): the FieldKind alone offers nothing
$res.CalcSynNoWire = $(try {
  $ck = [pscustomobject]@{ Line = 12; Path = (Join-Path $work 'calc-nowire.pas'); Call = 'C'; Kind = 'fkCalculated'; KindLine = 40; KindPath = (Join-Path $work 'calc-nowire.pas') }
  Format-SynthCalc (Resolve-CalcField (New-SynthCalcFacts 'calc-nowire' $synSrc $synSpec -Event '' -Creating $ck)) } catch { "threw: $($_.Exception.Message)" })
# negative 1b: wired, but the handler never writes the field -> not calculated
$res.CalcSynNoWrite = $(try { Format-SynthCalc (Resolve-CalcField (New-SynthCalcFacts 'calc-nowrite' $synSrc $synSpec -Field 'Q' -Vars @('FfQ'))) } catch { "threw: $($_.Exception.Message)" })
# FieldByName('<name>') written directly (no TField variable) is a write too; a field set in ANOTHER event is named, not offered;
# a lookup (the creating call sets fkLookup) is named, not offered
$fbnSrc = @('procedure TSynth.CalcH(DataSet: TDataSet);', 'begin', "  DataSet.FieldByName('A').AsString:= FfB.AsString;", 'end;')
$fbnSpec = @{ 3 = @('read:DataSet', 'member-access:FieldByName:DataSet', 'member-access:AsString', 'read:FfB', 'member-access:AsString:FfB') }
$res.CalcSynFieldByName = $(try { Format-SynthCalc (Resolve-CalcField (New-SynthCalcFacts 'calc-fbn' $fbnSrc $fbnSpec -Vars @())) } catch { "threw: $($_.Exception.Message)" })
$res.CalcSynEvent = $(try { Format-SynthCalc (Resolve-CalcField (New-SynthCalcFacts 'calc-event' $synSrc $synSpec -Event 'AfterScroll')) } catch { "threw: $($_.Exception.Message)" })
$res.CalcSynLookup = $(try {
  $lk = [pscustomobject]@{ Line = 12; Path = (Join-Path $work 'calc-lookup.pas'); Call = 'MakeLookup'; Kind = 'fkLookup'; KindLine = 40; KindPath = (Join-Path $work 'calc-lookup.pas') }
  Format-SynthCalc (Resolve-CalcField (New-SynthCalcFacts 'calc-lookup' $synSrc $synSpec -Event '' -Creating $lk)) } catch { "threw: $($_.Exception.Message)" })

[pscustomobject]$res
