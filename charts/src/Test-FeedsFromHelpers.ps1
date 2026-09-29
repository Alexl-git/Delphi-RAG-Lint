<#
  Test-FeedsFromHelpers.ps1 -- focused checks for the three datasource-chain
  defects routed to Task 3 by the Task 0 review, and for the two helpers
  extracted to fix them. RETURNS the measured values; Test-Emitters.ps1 pins
  them (the Test-Task0Helpers.ps1 pattern: dot-sourcing Emit-Common into the
  gate would put every helper and its $DbPath contract into the gate's scope).

  (a) a module-prefixed datasource resolved by NAME to a form in another file
      was graded `certain`. A name match is `[by name]` (plan R5).
  (b) the dataset-site query matched `receiver_text LIKE '%.<name>'`; `_` in a
      datasource name is a LIKE wildcard. The predicate is now an exact suffix
      comparison.
  (c) `Self.edtX.DataBinding` yielded the control `Self`; an RHS
      `(VM as IFoo).MemTable` yielded an empty root and a malformed `no-type`
      reason.

  Nothing here writes to a database. (a) runs on real data: CLIENT has no
  module-prefixed datasource whose module exists (all 65 rows are dangling), so
  the check asks the chain for `frmStopReas.dsrStopReas` FROM uCausFailForm.dfm
  -- a real component in another form's file, reached only through the module
  name.
#>
[CmdletBinding()]
param(
  [string] $DbCli  = (Join-Path $PSScriptRoot '..\scratch\db\CLIENT-Micronite2027.sqlite'),
  [string] $DbSql  = (Join-Path $PSScriptRoot '..\scratch\db\SQL-drag-lint-sql.sqlite'),
  [string] $Engine = 'C:\Projects\Delphi-RAG-lint\third_party\dll-win64\drag-lint.exe'
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Emit-Common.ps1')

$res = [ordered]@{}
$S = Get-SqlTableSet $DbSql
$DbPath = Get-CloneDb $DbCli

# ---- (a) a cross-file module reference is [by name], never certain ---------------
$cf = [string](@((Get-IndexedFileShas).Keys | Where-Object { $_ -like '*\uCausFailForm.dfm' })[0])
$xa = Get-DataSourceChain $cf 'frmStopReas.dsrStopReas' $S
$res.FixA = "$($xa.Hops[0].Hop):$($xa.Hops[0].Grade)"
$res.FixAReason = [string]$xa.Hops[0].Reason
# the same module prefix naming the form's OWN file stays certain
$xs = Get-DataSourceChain $cf 'frmCausFail.dsrCausFail' $S
$res.FixASelf = "$($xs.Hops[0].Grade):$($xs.ResolvedTable)"

# ---- (b) `_` is not a wildcard -----------------------------------------------------
# Evaluated BY THE INDEX'S OWN SQL ENGINE, on literals, so the check is on the
# predicate the chain actually sends.
$bcases = [ordered]@{
  "'Self.dsrXA'|dsr_A" = 0          # `_` must not match X
  "'Self.dsr_A'|dsr_A" = 1
  "'DSR_A'|dsr_A"      = 1          # case-insensitive, bare receiver
  "'Other.dsr_A'|dsr_A" = 1         # any qualifier ending in .dsr_A
  "'xdsr_A'|dsr_A"     = 0          # suffix must start at a dot
}
$bbad = New-Object System.Collections.ArrayList
foreach ($k in $bcases.Keys) {
  $lit, $nm = $k -split '\|'
  $r = Invoke-IndexQuery "SELECT ($(Get-ReceiverMatchSql $lit $nm)) AS m"
  if ([int]$r[0].m -ne $bcases[$k]) { [void]$bbad.Add("$k expected $($bcases[$k]) got $($r[0].m)") }
}
$res.FixBFailures = $bbad.ToArray()

# ---- (c1) the control behind a DataSource re-pointing ------------------------------
$c1 = [ordered]@{
  'Self.edtX.DataBinding|'                            = 'edtX|receiver'
  'edtF1.DataBinding|'                                = 'edtF1|receiver'
  '.DataBinding|  edtF2        .DataBinding   .'      = 'edtF2|source'
  '.DataBinding|  Self.edtY        .DataBinding   .'  = 'edtY|source'
  '.DataController|  x := 1; Self . grdV . DataController .' = 'grdV|source'
  '.DataBinding|  Foo(edtZ).DataBinding.'             = '|'
}
$cbad = New-Object System.Collections.ArrayList
foreach ($k in $c1.Keys) {
  $rt, $bef = $k -split '\|', 2
  $g = Get-RePointControl $rt $bef
  $got = "$($g.Control)|$($g.From)"
  if ($got -ne $c1[$k]) { [void]$cbad.Add("[$k] expected '$($c1[$k])' got '$got'") }
}
$res.FixC1Failures = $cbad.ToArray()

# ---- (c2) the RHS root, and a well-formed reason when there is none ---------------
$c2 = [ordered]@{
  'FViewModel.MemTable'              = 'FViewModel|'
  'Self.FViewModel.MemTable'         = 'FViewModel|'
  'FViewModel.Model.memDataChannels' = 'FViewModel|'
  'FList[0].MT'                      = 'FList|'
  '(VM as IFoo).MemTable'            = '|cast'
  'TFDMemTable(X)'                   = '|call'
  'GetTable(1).MT'                   = '|call'
  ''                                 = '|none'
}
$rbad = New-Object System.Collections.ArrayList
foreach ($k in $c2.Keys) {
  $g = Get-RhsRoot $k
  $kind = $(if ($g.Root) { '' } elseif ($g.Reason -like '*cast expression*') { 'cast' }
            elseif ($g.Reason -like '*call or hard cast*') { 'call' } elseif ($g.Reason) { 'none' } else { 'NO-REASON' })
  $got = "$($g.Root)|$kind"
  if ($got -ne $c2[$k]) { [void]$rbad.Add("[$k] expected '$($c2[$k])' got '$got' ($($g.Reason))") }
  if (-not $g.Root -and $g.Reason -notmatch '^RHS ') { [void]$rbad.Add("[$k] reason is not a sentence about the RHS: '$($g.Reason)'") }
}
$res.FixC2Failures = $rbad.ToArray()

# ---- candidate order: FIRST LITERAL in the view-model unit, not alphabetical --------
$sn = [string](@((Get-IndexedFileShas).Keys | Where-Object { $_ -like '*\DefineSerialNumbers.dfm' })[0])
$pl = Get-DataSourceChain $sn 'dsrPList' $S
$res.PListOrder = (@($pl.CandidateTables) -join ',')
$res.PListLines = (@($pl.CandidateTables | ForEach-Object { $pl.CandidateLines[$_] }) -join ',')

# ---- the shared control -> datasource rule (consumers and feeds-from) --------------
$cq = Invoke-IndexQuery @"
SELECT $(Get-ControlDataSourceSql 'sl' 'c') AS ds
  FROM string_literals sl JOIN symbols c ON c.id = sl.symbol_id
 WHERE sl.kind = 'dfm-prop' AND sl.owner_name = 'DataBinding.FieldName' AND c.qualified_name = 'frmCausFail.cxGrid1.cxGrid1DBTableView1.colREASON'
"@
$res.ColReasonDs = [string]$cq[0].ds

[pscustomobject]$res
