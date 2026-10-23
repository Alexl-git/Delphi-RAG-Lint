<#
  run_cycles_f2047.ps1 -- N-09 `cycles --f2047 [--unit <stem>]`: only the cycles made
  ENTIRELY of interface uses edges (the ones dcc rejects with F2047), with the symbols
  forcing each edge and the next commands (spec 2026-10-23-e18-followups.md).

  Fixture (written here): FA <-> FB both in the INTERFACE uses (F2047), and IC -> ID in the
  interface with ID -> IC in the implementation (legal, compiles).

  Positive controls: plain `cycles` reports BOTH groups (so --f2047 dropping IC/ID is the
  filter, not a missing index), and `--causes` text still names the forcing symbol (the
  --causes loop now shares IntfEdgeSymbols with --f2047).
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\drag-lint-cycles-f2047-$PID"
)
$ErrorActionPreference = 'Stop'
$script:Failed = $false
function Check($n, $ok, $d = '') {
  $s = if ($ok) { 'PASS' } else { 'FAIL' }
  $c = if ($ok) { 'Green' } else { 'Red' }
  Write-Host ("  [{0}] {1} {2}" -f $s, $n, $d) -ForegroundColor $c
  if (-not $ok) { $script:Failed = $true }
}
if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
$Exe = (Resolve-Path $Exe).Path

function Invoke-Engine([string[]]$Arguments, [string]$Tag) {
  $o = Join-Path $WorkDir "$Tag.out"; $e = Join-Path $WorkDir "$Tag.err"
  $p = Start-Process -FilePath $Exe -WorkingDirectory $WorkDir -NoNewWindow -Wait -PassThru `
    -ArgumentList $Arguments -RedirectStandardOutput $o -RedirectStandardError $e
  return @{ Exit = $p.ExitCode; Out = [IO.File]::ReadAllText($o); Err = [IO.File]::ReadAllText($e) }
}
function Write-Unit([string]$Name, [string]$Text) {
  [IO.File]::WriteAllText((Join-Path $script:Root "$Name.pas"), ($Text -replace "`r`n", "`n" -replace "`n", "`r`n"), [Text.Encoding]::ASCII)
}

New-Item -ItemType Directory -Force $WorkDir | Out-Null
try {
  $script:Root = Join-Path $WorkDir 'src'
  New-Item -ItemType Directory -Force $script:Root | Out-Null
  Write-Unit 'FA' "unit FA;`ninterface`nuses FB;`ntype`n  TA = class`n    FPeer: TB;`n  end;`nimplementation`nend.`n"
  Write-Unit 'FB' "unit FB;`ninterface`nuses FA;`ntype`n  TB = class`n    FPeer: TA;`n  end;`nimplementation`nend.`n"
  Write-Unit 'IC' "unit IC;`ninterface`nuses ID;`ntype`n  TC = class`n    FPeer: TD;`n  end;`nimplementation`nend.`n"
  Write-Unit 'ID' "unit ID;`ninterface`ntype`n  TD = class`n  end;`nimplementation`nuses IC;`nend.`n"

  $db = Join-Path $WorkDir 'f.sqlite'
  $ix = Invoke-Engine @('index', ('"' + $script:Root + '"'), '--db', ('"' + $db + '"'), '--library-db', 'none') 'index'
  Check 'fixture indexed' ($ix.Exit -eq 0) "exit=$($ix.Exit)"
  $qdb = '"' + $db + '"'

  Write-Host '== positive controls' -ForegroundColor Cyan
  $all = Invoke-Engine @('cycles', '--db', $qdb, '--library-db', 'none', '--format', 'json') 'all'
  $allG = @(); try { $allG = @($all.Out | ConvertFrom-Json) } catch { }
  Check 'plain cycles reports both groups (FA/FB and IC/ID)' ($allG.Count -eq 2) "groups=$($allG.Count)"
  $cau = Invoke-Engine @('cycles', '--db', $qdb, '--library-db', 'none', '--causes') 'causes'
  Check '--causes text still names the forcing symbol' ($cau.Out -match "fa's INTERFACE needs fb via:" -and $cau.Out -match 'line \d+: TB\s+\[') ''

  Write-Host '== --f2047' -ForegroundColor Cyan
  $j = Invoke-Engine @('cycles', '--db', $qdb, '--library-db', 'none', '--f2047', '--format', 'json') 'fj'
  Check '--f2047 json exits 0' ($j.Exit -eq 0) "exit=$($j.Exit) err=$($j.Err)"
  $g = @(); try { $g = @($j.Out | ConvertFrom-Json | Where-Object { $_ }) } catch { Check '--f2047 json parses' $false $j.Out }
  Check 'exactly the interface-only group' ($g.Count -eq 1 -and ((@($g[0].units) | Sort-Object) -join ',') -eq 'fa,fb') ($j.Out)
  if ($g.Count -eq 1) {
    $e = @($g[0].edges)
    Check 'both interface edges listed' ($e.Count -eq 2) "edges=$($e.Count)"
    $ab = @($e | Where-Object { $_.from -eq 'fa' -and $_.to -eq 'fb' })
    Check 'fa->fb carries symbol TB' ($ab.Count -eq 1 -and (@($ab[0].symbols | ForEach-Object { $_.name }) -contains 'TB')) ''
    Check 'plan and fix commands present' ("$($g[0].plan)" -match '--plan' -and "$($g[0].fix)" -match '--fix --project "<X\.dproj>" --unit fa') "fix=$($g[0].fix)"
  }

  $t = Invoke-Engine @('cycles', '--db', $qdb, '--library-db', 'none', '--f2047', '--unit', 'FB') 'ft'
  Check '--unit FB (dcc spelling) text lists the group and its fix' ($t.Exit -eq 0 -and $t.Out -match 'fa <-> fb|fb <-> fa' -and $t.Out -match '--unit fb') $t.Out
  Check 'text names the edge symbol' ($t.Out -match "INTERFACE uses fb via:" -and $t.Out -match 'TB') ''

  $n = Invoke-Engine @('cycles', '--db', $qdb, '--library-db', 'none', '--f2047', '--unit', 'IC') 'fn'
  Check '--unit of an implementation-broken cycle: exit 0 + note' ($n.Exit -eq 0 -and $n.Out -match 'IC is in no interface-only cycle') "exit=$($n.Exit) out=$($n.Out)"

  $p = Invoke-Engine @('cycles', '--db', $qdb, '--library-db', 'none', '--f2047', '--plan') 'fp'
  Check '--f2047 with --plan is refused (exit 2)' ($p.Exit -eq 2) "exit=$($p.Exit)"
} finally {
  if (Test-Path -LiteralPath $WorkDir) { [IO.Directory]::Delete($WorkDir, $true) }
}

if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
