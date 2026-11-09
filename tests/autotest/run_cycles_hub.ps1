<#
  run_cycles_hub.ps1 -- `cycles --hub` (spec docs\superpowers\specs\2026-11-08-hub-scc-phased.md, P1):
  per group the hub units (a unit whose removal leaves the rest acyclic), the edges and
  reference weights on each side, whether cutting one side alone breaks the group, the
  spoke->hub surface (globals with member names, routines), the hub->spoke shapes and the
  dead uses inside the group. Text and --format json.

  Fixture (written here):
    star  -- H declares `GH: TH` (fields F1, F2, method M) and constructs GS1..GS3 (`uses S1, S2, S3`
             in the implementation); S1..S3 `uses H` in the implementation and read `GH.F1`, `GH.M`;
             S3 also `uses S1` without referencing it (one dead edge). Exactly one hub: h.
    knot  -- A <-> B and C <-> D joined by B -> C and D -> A: one group of 4, no single unit whose
             removal leaves the rest acyclic -> "hubs: none".
  Positive controls: plain `cycles` reports both groups (so a missing hub is the analysis, not a
  missing index); without --hub no hub line is printed. The whole guard is RED on an engine
  without the flag (exit 2 unknown flag).
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\drag-lint-cycles-hub-$PID"
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
  Write-Unit 'H' ("unit H;`ninterface`ntype`n  TH = class`n  public`n    F1: Integer;`n    F2: Integer;`n    procedure M;`n  end;`n" +
    "var`n  GH: TH;`nprocedure Boot;`nimplementation`nuses S1, S2, S3;`nprocedure TH.M;`nbegin`n  F2 := F1;`nend;`n" +
    "procedure Boot;`nbegin`n  GH := TH.Create;`n  GS1 := TS1.Create;`n  GS1.Load;`n  GS2 := TS2.Create;`n  GS2.Load;`n  GS3 := TS3.Create;`n  GS3.Load;`nend;`nend.`n")
  foreach ($n in 1, 2, 3) {
    $extra = if ($n -eq 3) { ', S1' } else { '' }
    Write-Unit "S$n" ("unit S$n;`ninterface`ntype`n  TS$n = class`n  public`n    procedure Load;`n  end;`nvar`n  GS${n}: TS$n;`n" +
      "implementation`nuses H$extra;`nprocedure TS$n.Load;`nbegin`n  GH.F1 := $n;`n  GH.M;`nend;`nend.`n")
  }
  Write-Unit 'A' "unit A;`ninterface`nprocedure PA;`nimplementation`nuses B;`nprocedure PA;`nbegin`n  PB;`nend;`nend.`n"
  Write-Unit 'B' "unit B;`ninterface`nprocedure PB;`nimplementation`nuses A, C;`nprocedure PB;`nbegin`n  PA;`n  PC;`nend;`nend.`n"
  Write-Unit 'C' "unit C;`ninterface`nprocedure PC;`nimplementation`nuses D;`nprocedure PC;`nbegin`n  PD;`nend;`nend.`n"
  Write-Unit 'D' "unit D;`ninterface`nprocedure PD;`nimplementation`nuses C, A;`nprocedure PD;`nbegin`n  PC;`n  PA;`nend;`nend.`n"

  $db = Join-Path $WorkDir 'hub.sqlite'
  $ix = Invoke-Engine @('index', ('"' + $script:Root + '"'), '--db', ('"' + $db + '"'), '--library-db', 'none') 'index'
  Check 'fixture indexed' ($ix.Exit -eq 0) "exit=$($ix.Exit)"
  $qdb = '"' + $db + '"'

  Write-Host '== positive controls' -ForegroundColor Cyan
  $all = Invoke-Engine @('cycles', '--db', $qdb, '--library-db', 'none', '--format', 'json') 'all'
  $allG = @(); try { $allG = @($all.Out | ConvertFrom-Json) } catch { }
  Check 'plain cycles reports both groups (star and knot)' ($allG.Count -eq 2) "groups=$($allG.Count)"
  $plain = Invoke-Engine @('cycles', '--db', $qdb, '--library-db', 'none') 'plain'
  Check 'without --hub no hub line is printed' ($plain.Exit -eq 0 -and $plain.Out -notmatch '(?m)^\s+hub |hubs: none|zero-ref edges') ''

  Write-Host '== --hub text' -ForegroundColor Cyan
  $t = Invoke-Engine @('cycles', '--db', $qdb, '--library-db', 'none', '--hub') 'hubt'
  Check '--hub exits 0' ($t.Exit -eq 0) "exit=$($t.Exit) err=$($t.Err)"
  Check 'star: hub h with 3 in / 3 out implementation edges' ($t.Out -match 'hub h: in 3 edges \(3 impl, 0 intf\) \d+ refs, the in-side alone breaks the group: yes; out 3 edges \(3 impl, 0 intf\) \d+ refs, the out-side alone: yes') $t.Out
  Check 'star: spoke->hub surface is the one global with its member names' ($t.Out -match 'spoke->hub surface: 1 symbols -- var GH \d+ refs in 3 units \(2 member names: (F1 \d+, M \d+|M \d+, F1 \d+)\)') ''
  Check 'star: hub->spoke surface counts the constructions and var writes' ($t.Out -match 'hub->spoke surface: 3 constructions, 3 var writes, \d+ var reads, \d+ method calls in 3 units') ''
  Check 'star: lighter side is spoke->hub' ($t.Out -match 'lighter side: spoke->hub \(1 hub symbols vs 3 spoke surfaces\)') ''
  Check 'star: the dead S3 -> S1 edge is the one zero-ref edge of 7' ($t.Out -match 'zero-ref edges inside the group: 1 of 7') ''
  Check 'knot: hubs: none' ($t.Out -match 'hubs: none \(no single unit whose removal leaves the group acyclic\)') ''

  Write-Host '== --hub json' -ForegroundColor Cyan
  $j = Invoke-Engine @('cycles', '--db', $qdb, '--library-db', 'none', '--hub', '--format', 'json') 'hubj'
  Check '--hub json exits 0' ($j.Exit -eq 0) "exit=$($j.Exit) err=$($j.Err)"
  $g = @(); try { $g = @($j.Out | ConvertFrom-Json | Where-Object { $_ }) } catch { Check '--hub json parses' $false $j.Out }
  $star = @($g | Where-Object { @($_.units) -contains 'h' })
  $knot = @($g | Where-Object { @($_.units) -contains 'a' })
  Check 'json: both groups present' ($star.Count -eq 1 -and $knot.Count -eq 1) "star=$($star.Count) knot=$($knot.Count)"
  if ($star.Count -eq 1) {
    $hubs = @($star[0].hubs)
    Check 'json star: exactly one hub, h' ($hubs.Count -eq 1 -and $hubs[0].unit -eq 'h') ($j.Out)
    if ($hubs.Count -eq 1) {
      $h = $hubs[0]
      Check 'json star: in/out edges 3/3, both sides break alone' ($h.in.edges -eq 3 -and $h.out.edges -eq 3 -and $h.in.breaks_alone -eq $true -and $h.out.breaks_alone -eq $true -and $h.in.intf_edges -eq 0) ''
      $s2h = @($h.spoke_to_hub)
      $mem = @(); if ($s2h.Count -ge 1) { $mem = @($s2h[0].members | ForEach-Object { $_.name }) }
      Check 'json star: spoke_to_hub = var GH with members F1 and M' ($s2h.Count -eq 1 -and $s2h[0].kind -eq 'var' -and $s2h[0].name -eq 'GH' -and $s2h[0].units -eq 3 -and ($mem -contains 'F1') -and ($mem -contains 'M') -and $mem.Count -eq 2) "members=$($mem -join ',')"
      Check 'json star: hub_to_spoke construction 3, var_write 3, units 3' ($h.hub_to_spoke.construction -eq 3 -and $h.hub_to_spoke.var_write -eq 3 -and $h.hub_to_spoke.units -eq 3) ''
      Check 'json star: lighter_side spoke->hub' ($h.lighter_side -eq 'spoke->hub') ''
    }
    Check 'json star: zero_ref_edges 1' ($star[0].zero_ref_edges -eq 1) "zero=$($star[0].zero_ref_edges)"
  }
  if ($knot.Count -eq 1) {
    Check 'json knot: no hubs' (@($knot[0].hubs).Count -eq 0) ''
    Check 'json knot: zero_ref_edges 0 (every edge carries a call)' ($knot[0].zero_ref_edges -eq 0) "zero=$($knot[0].zero_ref_edges)"
  }
} finally {
  if (Test-Path -LiteralPath $WorkDir) { [IO.Directory]::Delete($WorkDir, $true) }
}

if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
