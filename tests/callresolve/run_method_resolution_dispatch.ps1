<#
  run_method_resolution_dispatch.ps1 -- a METHOD-RESOLUTION CLAUSE routes the
  interface method to the NAMED class method in dispatch_edges, and is stored as
  a clause row, never as a phantom class member.

  WHAT WAS WRONG (extractor 1.28.0 / resolver at main 7d1f399c, measured on
  this fixture): `procedure IJob.Execute = RunJob;` was emitted as a METHOD
  NAMED `Execute` on TJob (the last dotted segment), and RunJob got no
  dispatch edge at all. DispatchResolver joined IJob.Execute by NAME, so it
  wrote two AMBIGUOUS `implements` edges -- to the phantom and to TJob's real,
  unrelated Execute -- and none to RunJob.

  WHAT THIS GUARD PINS (backlog METHRES-DISPATCH)
    ROW   the clause is ONE symbol: name 'IJob.Execute', signature '= RunJob',
          directives 'resolution'; TJob has exactly one member named Execute
    MR1   IJob.Execute -> TJob.RunJob   implements, certain (and no other TJob edge)
    MR2   IJob.Name    -> TJob.JobName  implements, certain
    MR3   no edge IJob.Execute -> TJob.Execute (the same-named method is NOT it)
    MR5   an INHERITED target: TSubJob's clause -> TBaseJob.BaseRun / BaseName
    PC    positive control, no clause: IJob.Execute -> TPlainJob.Execute, certain
    RB5   the call J.Execute (J: IJob) still binds IJob.Execute, certain

  Usage: pwsh -File tests\callresolve\run_method_resolution_dispatch.ps1 [-Exe <drag-lint.exe>]
#>
[CmdletBinding()]
param([string]$Exe = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe")
try {

$ErrorActionPreference = 'Stop'
$script:fail = $false
function Check([string]$Name, [bool]$Ok, [string]$Detail = '') {
  $tag = if ($Ok) { 'PASS' } else { 'FAIL' }
  Write-Host ("[{0}] {1}{2}" -f $tag, $Name, $(if ($Detail) { "  ($Detail)" } else { '' }))
  if (-not $Ok) { $script:fail = $true }
}

$exePath = (Resolve-Path $Exe).Path
$fixDir  = (Resolve-Path (Join-Path $PSScriptRoot 'fixtures\methres')).Path
$scratch = Join-Path C:\TEMP "draglint_method_resolution_dispatch_$PID"
if (Test-Path $scratch) { [System.IO.Directory]::Delete($scratch, $true) }
New-Item -ItemType Directory -Path $scratch | Out-Null
Copy-Item (Join-Path $fixDir '*.pas') $scratch
$db = Join-Path $scratch 'methres.sqlite'

# sql --json rows are POSITIONAL arrays: map them onto columns[].name.
function Sql([string]$Query) {
  $raw = (& $exePath sql --db $db --json --limit 1000 --query $Query 2>$null) -join "`n"
  $b = $raw.IndexOf('{')
  if ($b -lt 0) { throw "sql returned no JSON for: $Query" }
  $o = $raw.Substring($b) | ConvertFrom-Json
  $names = @($o.columns | ForEach-Object { $_.name })
  $out = @()
  foreach ($r in @($o.rows)) {
    $h = @{}
    for ($i = 0; $i -lt $names.Count; $i++) { $h[$names[$i]] = $r[$i] }
    $out += $h
  }
  return ,@($out)
}

$null = & $exePath index $scratch --db $db 2>&1 | Out-String
Check 'index exits 0' ($LASTEXITCODE -eq 0)

# Every implements edge out of interface method BASE into class CLS, as "impl|conf" strings.
function EdgesInto([string]$Base, [string]$Cls) {
  $r = Sql ("SELECT i.qualified_name AS q, d.confidence AS c FROM dispatch_edges d " +
            "JOIN symbols b ON b.id = d.base_symbol_id JOIN symbols i ON i.id = d.impl_symbol_id " +
            "WHERE d.kind = 'implements' AND b.qualified_name = '$Base' AND i.qualified_name LIKE '$Cls.%' " +
            "ORDER BY i.qualified_name")
  return ,@($r | ForEach-Object { "$($_.q)|$($_.c)" })
}

$EXEC = 'uMethRes.IJob.Execute'
$NAME = 'uMethRes.IJob.Name'

$row = Sql ("SELECT name AS n, COALESCE(signature, '') AS s, COALESCE(directives, '') AS d FROM symbols " +
            "WHERE qualified_name = 'uMethRes.TJob.IJob.Execute'")
Check 'ROW clause stored as IJob.Execute / = RunJob / resolution' `
  (($row.Count -eq 1) -and ($row[0].n -eq 'IJob.Execute') -and ($row[0].s -eq '= RunJob') -and ($row[0].d -eq 'resolution')) `
  ("rows=$($row.Count) " + $(if ($row.Count) { "name=$($row[0].n) sig=$($row[0].s) dir=$($row[0].d)" }))
$ex = Sql "SELECT id FROM symbols WHERE qualified_name = 'uMethRes.TJob.Execute'"
Check 'ROW TJob has exactly one member named Execute (no phantom)' ($ex.Count -eq 1) "count=$($ex.Count)"

$e1 = EdgesInto $EXEC 'uMethRes.TJob'
Check 'MR1 IJob.Execute -> TJob.RunJob certain, only' ((($e1 -join ',') -eq 'uMethRes.TJob.RunJob|certain')) ($e1 -join ',')
$e2 = EdgesInto $NAME 'uMethRes.TJob'
Check 'MR2 IJob.Name -> TJob.JobName certain, only' ((($e2 -join ',') -eq 'uMethRes.TJob.JobName|certain')) ($e2 -join ',')
Check 'MR3 no edge IJob.Execute -> TJob.Execute' (-not ($e1 | Where-Object { $_ -like 'uMethRes.TJob.Execute|*' })) ($e1 -join ',')

$e5 = EdgesInto $EXEC 'uMethRes.TBaseJob'
Check 'MR5 inherited target IJob.Execute -> TBaseJob.BaseRun certain' ((($e5 -join ',') -eq 'uMethRes.TBaseJob.BaseRun|certain')) ($e5 -join ',')
$e6 = EdgesInto $NAME 'uMethRes.TBaseJob'
Check 'MR5 inherited target IJob.Name -> TBaseJob.BaseName certain' ((($e6 -join ',') -eq 'uMethRes.TBaseJob.BaseName|certain')) ($e6 -join ',')

$pc = EdgesInto $EXEC 'uMethRes.TPlainJob'
Check 'PC no clause: IJob.Execute -> TPlainJob.Execute certain' ((($pc -join ',') -eq 'uMethRes.TPlainJob.Execute|certain')) ($pc -join ',')

$call = Sql ("SELECT COALESCE(t.qualified_name, '') AS q, COALESCE(e.confidence, '') AS c FROM refs r " +
             "LEFT JOIN call_edges e ON e.ref_id = r.id LEFT JOIN symbols t ON t.id = e.target_symbol_id " +
             "WHERE r.kind = 'call' AND r.name_text = 'Execute' AND r.receiver_text = 'J'")
Check 'RB5 J.Execute (J: IJob) binds IJob.Execute certain' `
  (($call.Count -eq 1) -and ($call[0].q -eq $EXEC) -and ($call[0].c -eq 'certain')) `
  $(if ($call.Count) { "$($call[0].q) $($call[0].c)" } else { 'no call ref' })

if ($script:fail) { Write-Host 'FAIL'; exit 1 }
Write-Host 'PASS'
exit 0
} finally {
  if ($scratch -and (Test-Path $scratch)) { try { [System.IO.Directory]::Delete($scratch, $true) } catch { } }
}