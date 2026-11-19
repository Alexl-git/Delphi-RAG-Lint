<#
  run_include_host_refs.ps1 -- a ref written INSIDE a code include binds in the scope of the unit
  that includes it (v151 lane INC, owner ruling OQ18 B: bind per host).

  Fixture tests\callresolve\fixtures\include_host_refs:
    IncHostU.pas        interface UProc, Clash, const cUsed.
    IncHostH.pas        uses IncHostU; class THost (Run, Helper), cHost, gHost, HostProc, HostFn;
                        implementation record THidden; {$I IncHostH_impl.inc}.
    IncHostH_impl.inc   ONE host: the body of THost.Run (Helper, HostProc, gHost, cHost, HostFn,
                        cUsed, a local R: THidden, UProc) and a free IncLocal (THost var, THost.Create).
    IncHostMA.pas / IncHostMB.pas  both use IncHostU, both declare Emit; MA also declares Clash;
                        both {$I IncHostShared.inc}.
    IncHostShared.inc   TWO hosts: SharedRun calls Emit, UProc, Clash.
    IncHostStray.inc    included by nobody: calls HostProc, UProc.

  Bound (RED on the v151 EXT base: every one NULL): the single-host include's refs to the host's
  class, method (Self call), routines, const, var, implementation-section record, its local, and to
  the used unit's routine / const; the method body THost.Run is a symbol of the include.
  Per host (OQ18): UProc in the shared include binds (both hosts agree on IncHostU.UProc).
  Controls (must stay unbound): Emit (each host has its own), Clash (MA's own vs IncHostU's) --
  the refs table holds one target per ref, so a disagreement is never stored as either answer;
  the stray include (no host) binds nothing.

  Usage: pwsh -File tests\callresolve\run_include_host_refs.ps1 [-Exe <drag-lint.exe>]
#>
param([string]$Exe = '')
# Defaults that need the script path are resolved HERE, not in param(): Windows PowerShell 5 run with
# -File leaves $PSScriptRoot/$MyInvocation empty inside an advanced script's param block (Repo became C:\).
if (-not $Exe) { $Exe = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe" }
$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
$exePath = (Resolve-Path $Exe).Path
. "$repo\tests\autotest\lib\HermeticEngine.ps1"; $exePath = Get-HermeticEngine $exePath
$scratch = Join-Path ([IO.Path]::GetTempPath()) "draglint_inchost_$PID"
$script:fail = $false
function Check([string]$Name, [bool]$Ok, [string]$Detail = '') {
  Write-Host ("[{0}] {1}{2}" -f $(if ($Ok) { 'PASS' } else { 'FAIL' }), $Name, $(if ($Detail) { "  ($Detail)" } else { '' }))
  if (-not $Ok) { $script:fail = $true }
}
function Invoke-Rows([string]$Db, [string]$Query) {
  $raw = (& $exePath sql --db $Db --json --query $Query 2>$null) -join "`n"
  $j = $raw | ConvertFrom-Json
  $cols = @($j.columns | ForEach-Object { $_.name })
  $out = @()
  foreach ($r in @($j.rows)) {
    $o = [ordered]@{}
    for ($i = 0; $i -lt $cols.Count; $i++) { $o[$cols[$i]] = $r[$i] }
    $out += [pscustomobject]$o
  }
  return ,@($out)
}
try {
  [void](New-Item -ItemType Directory -Force -Path $scratch)
  $fx = Join-Path $scratch 'fx'
  [void](New-Item -ItemType Directory -Force -Path $fx)
  Copy-Item (Join-Path $PSScriptRoot 'fixtures\include_host_refs\*') $fx
  $db = Join-Path $scratch 'inchost.sqlite'
  & $exePath index $fx --db $db 2>&1 | Out-Null
  $q = "SELECT f.path AS src, r.name_text AS name, r.kind AS kind, r.start_line AS line, " +
       "COALESCE(tf.path, '') AS target, COALESCE(s.start_line, 0) AS tline, " +
       "(SELECT COUNT(*) FROM call_edges c WHERE c.ref_id = r.id AND c.target_symbol_id = r.symbol_id) AS edges " +
       "FROM refs r JOIN files f ON f.id = r.file_id LEFT JOIN symbols s ON s.id = r.symbol_id LEFT JOIN files tf ON tf.id = s.file_id " +
       "WHERE f.path LIKE '%.inc'"
  $rows = Invoke-Rows $db $q
  Check 'the includes produced refs' ($rows.Count -ge 25) "$($rows.Count)"
  function Hit([string]$Src, [int]$Line, [string]$Name, [string]$Kind) {
    return @($rows | Where-Object { (Split-Path $_.src -Leaf) -eq $Src -and $_.line -eq $Line -and $_.name -eq $Name -and $_.kind -eq $Kind })
  }
  function Target([string]$Src, [int]$Line, [string]$Name, [string]$Kind) {
    $h = Hit $Src $Line $Name $Kind
    if ($h.Count -ne 1) { return "<$($h.Count) refs>" }
    if ($h[0].target -eq '') { return '' }
    return ('{0}:{1}' -f (Split-Path $h[0].target -Leaf), $h[0].tline)
  }
  function Expect([string]$Label, [string]$Src, [int]$Line, [string]$Name, [string]$Kind, [string]$Want) {
    $got = Target $Src $Line $Name $Kind
    Check "$Label -> $(if ($Want) { $Want } else { 'unbound' })" ($got -eq $Want) $got
  }
  $h = 'IncHostH_impl.inc'
  Expect 'single host: THost (method header qualifier)' $h 1 'THost' 'type_use' 'IncHostH.pas:9'
  Expect 'single host: THidden (local var type, implementation record of the host)' $h 3 'THidden' 'type_use' 'IncHostH.pas:27'
  Expect 'single host: Helper (Self method call)' $h 5 'Helper' 'call' 'IncHostH.pas:12'
  Expect 'single host: HostProc (host routine)' $h 6 'HostProc' 'call' 'IncHostH.pas:21'
  Expect 'single host: gHost (write)' $h 7 'gHost' 'write' 'IncHostH.pas:19'
  Expect 'single host: cHost (read)' $h 7 'cHost' 'read' 'IncHostH.pas:16'
  Expect 'single host: HostFn (parenless call)' $h 7 'HostFn' 'read' 'IncHostH.pas:22'
  Expect 'single host: cUsed (const of a unit the host uses)' $h 7 'cUsed' 'read' 'IncHostU.pas:9'
  Expect 'single host: R (local of the include method body)' $h 8 'R' 'read' 'IncHostH_impl.inc:3'
  Expect 'single host: UProc (routine of a unit the host uses)' $h 9 'UProc' 'call' 'IncHostU.pas:5'
  Expect 'single host: THost (var type in a free routine)' $h 14 'THost' 'type_use' 'IncHostH.pas:9'
  Expect 'single host: THost (THost.Create receiver)' $h 16 'THost' 'read' 'IncHostH.pas:9'
  $hp = Hit $h 6 'HostProc' 'call'
  Check 'single host: HostProc has its call edge' (($hp.Count -eq 1) -and ($hp[0].edges -eq 1)) "$($hp.edges)"
  $run = Invoke-Rows $db ("SELECT s.kind AS kind, s.impl_start_line AS a, s.impl_end_line AS b FROM symbols s JOIN files f ON f.id = s.file_id " +
                          "WHERE f.path LIKE '%IncHostH_impl.inc' AND s.qualified_name = 'THost.Run'")
  Check 'the include method body THost.Run is a symbol (lines 1-10)' (($run.Count -eq 1) -and ($run[0].kind -eq 'method') -and ($run[0].a -eq 1) -and ($run[0].b -eq 10)) "$($run.Count) $($run.kind) $($run.a)-$($run.b)"
  $s = 'IncHostShared.inc'
  Expect 'two hosts agree: UProc' $s 4 'UProc' 'call' 'IncHostU.pas:5'
  Expect 'control, two hosts disagree: Emit (each host has its own)' $s 3 'Emit' 'call' ''
  Expect 'control, two hosts disagree: Clash (MA own, MB from IncHostU)' $s 5 'Clash' 'call' ''
  $st = 'IncHostStray.inc'
  Expect 'control, no host: HostProc' $st 3 'HostProc' 'call' ''
  Expect 'control, no host: UProc' $st 4 'UProc' 'call' ''
} finally {
  if (Test-Path $scratch) { [IO.Directory]::Delete($scratch, $true) }
}
Write-Host ''
if ($script:fail) { Write-Host 'RESULT: FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'RESULT: PASS' -ForegroundColor Green; exit 0
