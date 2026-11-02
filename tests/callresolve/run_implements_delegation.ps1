<#
  run_implements_delegation.ps1 -- a DELEGATING property
  (`property Job: IJob read FJob implements IJob;`) makes its class an
  implementor of IJob in dispatch_edges, through the property.

  WHAT WAS WRONG (extractor 1.28.0 / resolver at main 7d1f399c, measured on
  this fixture): the property row kept no trace of `implements IJob`
  (directives NULL), DispatchResolver joined IJob.Execute to TJobHost's
  unrelated same-named Execute, and nothing tied TJobHost to the delegate.
  Interface report ruling D2 (owner 2026-11-01).

  WHAT THIS GUARD PINS
    DIR  the property row's directives read 'implements IJob'
    DL1  dispatch_edges delegates  IJob -> uDeleg.TJobHost.Job, certain
    DL2  no implements edge IJob.Execute -> TJobHost.Execute (the trap)
    DL3  `implements IA, IB` -> two delegates edges, IA and IB -> TBothHost.Both
    RPT  "implementors of IJob" (implements-edge parents UNION delegates-edge
         parents) = TJobHost, TJobImpl
    PC   positive control: IJob.Execute -> TJobImpl.Execute implements, certain

  Usage: pwsh -File tests\callresolve\run_implements_delegation.ps1 [-Exe <drag-lint.exe>]
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
$fixDir  = (Resolve-Path (Join-Path $PSScriptRoot 'fixtures\implsdeleg')).Path
$scratch = Join-Path C:\TEMP "draglint_implements_delegation_$PID"
if (Test-Path $scratch) { [System.IO.Directory]::Delete($scratch, $true) }
New-Item -ItemType Directory -Path $scratch | Out-Null
Copy-Item (Join-Path $fixDir '*.pas') $scratch
$db = Join-Path $scratch 'implsdeleg.sqlite'

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

function Edges([string]$Kind, [string]$Base) {
  $r = Sql ("SELECT i.qualified_name AS q, d.confidence AS c FROM dispatch_edges d " +
            "JOIN symbols b ON b.id = d.base_symbol_id JOIN symbols i ON i.id = d.impl_symbol_id " +
            "WHERE d.kind = '$Kind' AND b.qualified_name = '$Base' ORDER BY i.qualified_name")
  return ,@($r | ForEach-Object { "$($_.q)|$($_.c)" })
}

$dir = Sql "SELECT COALESCE(directives, '') AS d FROM symbols WHERE qualified_name = 'uDeleg.TJobHost.Job'"
Check 'DIR property directives = implements IJob' (($dir.Count -eq 1) -and ($dir[0].d -eq 'implements IJob')) $(if ($dir.Count) { "'$($dir[0].d)'" } else { 'no row' })

$e = Edges 'delegates' 'uDeleg.IJob'
Check 'DL1 delegates IJob -> TJobHost.Job certain' (($e -join ',') -eq 'uDeleg.TJobHost.Job|certain') ($e -join ',')
$e = Edges 'implements' 'uDeleg.IJob.Execute'
Check 'DL2 no implements edge to the TJobHost.Execute trap' (-not ($e | Where-Object { $_ -like 'uDeleg.TJobHost.*' })) ($e -join ',')
Check 'PC IJob.Execute -> TJobImpl.Execute implements certain' (($e -join ',') -eq 'uDeleg.TJobImpl.Execute|certain') ($e -join ',')
$a = Edges 'delegates' 'uDeleg.IA'
$b = Edges 'delegates' 'uDeleg.IB'
Check 'DL3 implements IA, IB -> two delegates edges to TBothHost.Both' `
  ((($a -join ',') -eq 'uDeleg.TBothHost.Both|certain') -and (($b -join ',') -eq 'uDeleg.TBothHost.Both|certain')) ("IA=$($a -join ',') IB=$($b -join ',')")

$rpt = Sql ("SELECT DISTINCT c.qualified_name AS q FROM dispatch_edges d JOIN symbols i ON i.id = d.impl_symbol_id " +
            "JOIN symbols c ON c.id = i.parent_id JOIN symbols b ON b.id = d.base_symbol_id " +
            "WHERE (d.kind = 'implements' AND b.parent_id = (SELECT id FROM symbols WHERE qualified_name = 'uDeleg.IJob')) " +
            "OR (d.kind = 'delegates' AND b.qualified_name = 'uDeleg.IJob') ORDER BY c.qualified_name")
$names = ($rpt | ForEach-Object { $_.q }) -join ','
Check 'RPT implementors of IJob = TJobHost, TJobImpl' ($names -eq 'uDeleg.TJobHost,uDeleg.TJobImpl') $names

if ($script:fail) { Write-Host 'FAIL'; exit 1 }
Write-Host 'PASS'
exit 0
} finally {
  if ($scratch -and (Test-Path $scratch)) { try { [System.IO.Directory]::Delete($scratch, $true) } catch { } }
}