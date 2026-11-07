<#
  run_mcp_neighbors_graph_export.ps1 -- E-PARITY-CODEGRAPH / E-PARITY-GRAPHIFY (wave 146, lane k4).

  1. MCP `initialize` carries an `instructions` string that says "drag-lint first".
  2. MCP tool `get_neighbors` answers the call-graph neighbourhood of a symbol:
     hop 1 holds the direct caller and callee, hop 2 reaches the next unit; an
     unknown qname gives an empty list (and `omitted` 0).
  3. `graph --format json` and `--format html` export the unit graph; any other
     format still exits 2.

  RED-CHECK: against a pre-change build 1, 2 and 3 FAIL (no instructions, no tool,
  `graph` refuses json/html). CONTROL: dot output still starts with `digraph`.
#>
[CmdletBinding()]
param([string]$Exe = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe")
$ErrorActionPreference = 'Continue'
$script:Failed = $false
function Check($n, $ok, $d = '') {
  $s = if ($ok) { 'PASS' } else { 'FAIL' }
  Write-Host ("  [{0}] {1} {2}" -f $s, $n, $d)
  if (-not $ok) { $script:Failed = $true }
}
if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe"; exit 2 }
$Exe = (Resolve-Path $Exe).Path
$Work = Join-Path ([IO.Path]::GetTempPath()) ("dl-nbr-" + [guid]::NewGuid().ToString('N'))
$Src = Join-Path $Work 'src'
New-Item -ItemType Directory -Force $Src | Out-Null
try {
  $u = @{
    'uNbA.pas' = "unit uNbA;`r`ninterface`r`nprocedure RunA;`r`nimplementation`r`nuses uNbB;`r`nprocedure RunA;`r`nbegin`r`n  RunB;`r`nend;`r`nend.`r`n"
    'uNbB.pas' = "unit uNbB;`r`ninterface`r`nprocedure RunB;`r`nimplementation`r`nuses uNbC;`r`nprocedure RunB;`r`nbegin`r`n  RunC;`r`nend;`r`nend.`r`n"
    'uNbC.pas' = "unit uNbC;`r`ninterface`r`nprocedure RunC;`r`nimplementation`r`nprocedure RunC;`r`nbegin`r`nend;`r`nend.`r`n"
  }
  foreach ($k in $u.Keys) { [IO.File]::WriteAllText((Join-Path $Src $k), $u[$k], [Text.Encoding]::ASCII) }
  $Db = Join-Path $Work 'nb.sqlite'
  & $Exe index $Src --db $Db 2>&1 | Out-Null
  if (-not (Test-Path $Db)) { Write-Host 'FATAL: index produced no DB'; exit 2 }

  $req = Join-Path $Work 'req.txt'
  $lines = @(
    '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"g","version":"1"}}}',
    '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"get_neighbors","arguments":{"qname":"uNbB.RunB"}}}',
    '{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"get_neighbors","arguments":{"qname":"uNbB.RunB","hops":2}}}',
    '{"jsonrpc":"2.0","id":4,"method":"tools/call","params":{"name":"get_neighbors","arguments":{"qname":"No.Such"}}}')
  [IO.File]::WriteAllText($req, (($lines -join "`n") + "`n"), [Text.Encoding]::ASCII)
  $so = Join-Path $Work 'so.txt'
  Start-Process $Exe -ArgumentList 'serve','--db',$Db -RedirectStandardInput $req -RedirectStandardOutput $so `
    -RedirectStandardError (Join-Path $Work 'se.txt') -NoNewWindow -Wait | Out-Null
  $r = @{}
  foreach ($l in (Get-Content $so)) { try { $o = $l | ConvertFrom-Json; if ($o.id) { $r[[string]$o.id] = $o } } catch {} }
  $ins = [string]$r['1'].result.instructions
  Check '1 initialize carries instructions saying drag-lint first' ($ins -match 'drag-lint first') "got='$ins'"
  function Nb($id) { $c = $r[$id].result.content; if ($c) { $t = $c[0].text; $t | ConvertFrom-Json } else { $null } }
  $n1 = Nb '2'; $n2 = Nb '3'; $n0 = Nb '4'
  $q1 = @($n1.neighbors | ForEach-Object { $_.qname })
  $q2 = @($n2.neighbors | ForEach-Object { $_.qname })
  Check '2a hop 1 holds the caller RunA and callee RunC' (($q1 -contains 'uNbA.RunA') -and ($q1 -contains 'uNbC.RunC')) "q1=$($q1 -join ',')"
  Check '2b the seed is at hop 0' (@($n1.neighbors | Where-Object { $_.qname -eq 'uNbB.RunB' -and $_.hop -eq 0 }).Count -eq 1)
  Check '2c omitted is stated (0)' ($n1.omitted -eq 0) "omitted=$($n1.omitted)"
  Check '2d unknown qname: empty neighbors' (($null -ne $n0) -and (@($n0.neighbors).Count -eq 0))
  Check '2e hops 2 is a superset of hops 1' ($q2.Count -ge $q1.Count)

  $j = (& $Exe graph --db $Db --format json 2>$null | Out-String)
  $jo = $null; try { $jo = $j | ConvertFrom-Json } catch {}
  Check '3a graph --format json parses with edges' (($null -ne $jo) -and (@($jo.edges).Count -ge 2)) "raw=$($j.Substring(0, [Math]::Min(120,$j.Length)))"
  Check '3b json edge has from/to/weight' ($null -ne $jo -and $jo.edges[0].from -and $jo.edges[0].to -and $jo.edges[0].weight -gt 0)
  $h = (& $Exe graph --db $Db --format html 2>$null | Out-String)
  Check '3c graph --format html is a self-contained page' (($h -match '<!DOCTYPE html>') -and ($h -match 'application/json') -and ($h -match 'uNbA'))
  & $Exe graph --db $Db --format svg 2>&1 | Out-Null
  Check '3d unknown format still exits 2' ($LASTEXITCODE -eq 2) "exit=$LASTEXITCODE"
  $d = (& $Exe graph --db $Db 2>$null | Out-String)
  # 3e MUST-FIX (x3 finding): the json edge writer used a local escaper whose backslash replace was a no-op. A unit name
  # cannot hold a backslash on Windows, so no fixture can reach it: this reads the source. RED on the old code.
  $cli = [IO.File]::ReadAllText((Join-Path $PSScriptRoot '..\..\src\cli\DRagLint.CLI.pas'))
  $edgeLine = [regex]::Match($cli, '(?m)^.*"from":"%s","to":"%s","weight":%d.*$').Value
  Check '3e json edges go through JsonEscape' (($edgeLine -match 'JsonEscape\(FromUnit\), JsonEscape\(ToUnit\)') -and ($cli -notmatch 'function JsonEsc\(')) "line=$edgeLine"
  Check 'CONTROL dot default starts with the generated comment and digraph' ($d -match 'digraph DragLintDeps')
} finally {
  [IO.Directory]::Delete($Work, $true)
}
if ($script:Failed) { Write-Host 'FAILED'; exit 1 }
Write-Host 'ALL PASS'; exit 0
