<#
  run_v1511_INC2_per_host_bindings.ps1 -- 1.51.1 lane INC2 (B10 / O13 / owner ruling OQ18):
  a ref written INSIDE a code include that SEVERAL units include keeps ONE binding PER HOST
  in the side table ref_host_bindings(ref_id, host_file_id, symbol_id), schema 26.

  Fixture tests\autotest\fixtures\v1511-INC2:
    PhU.pas        interface UProc, Clash.
    PhA.pas        uses PhU; class TWork (FCount, Run, Helper); Emit, Clash; implementation
                   const cLimit, var gTotal; {$I PhShared.inc}.
    PhB.pas        the same without Clash; its own cLimit / gTotal; {$I PhShared.inc}.
    PhShared.inc   TWO hosts: SharedRun calls Emit, UProc, Clash; the body of TWork.Run calls
                   Helper and writes FCount; SharedTotal reads cLimit and writes gTotal.
    PhS.pas / PhSingle.inc   ONE host (control): SingleRun calls SOnly.

  Checks (RED on 1.51.0: no table, the differing refs are unbound and invisible to both verbs):
    B   per host: Emit -> PhA.Emit / PhB.Emit; Clash -> PhA.Clash / PhU.Clash; the method body's
        Helper call and FCount write -> each host's own TWork member; the header qualifier TWork;
        the cLimit read and the gTotal write -> each host's own unit const / var.
        refs.symbol_id stays NULL where the hosts differ (one target per ref, never a guess).
    A   hosts agree: UProc keeps refs.symbol_id AND has one row per host.
    C   controls: the single-host include writes no row; no row names a dead symbol or a
        file that is not a host of the ref's include.
    R   readers: find-callers --name Emit reports the site `exact` (was name-only);
        find-callers --resolved lists the include site for BOTH Emit declarations;
        usages --name PhA.Emit / PhB.Emit / PhA.Clash / PhU.Clash each list the site.
    I   incremental: PhB gains its own Clash, reindex -> the Clash row of host PhB moves to
        PhB.Clash, host PhA's row is unchanged, no dead ids.
    M   migration: a copy made the way a schema 25 engine left it (table dropped, stamp 25;
        python stdlib sqlite3, a script FILE run with -I) answers the read-only verbs without
        the table (no AV, no migrate); `index` into it ends with the table present, schema 26,
        refs / call_edges / symbols kept; the next resolve (--resolve-only) writes the same rows.
  Needs python for arm M; missing python = FATAL, never a skip. pwsh 7.

  Usage: pwsh -File tests\autotest\run_v1511_INC2_per_host_bindings.ps1 [-Exe <drag-lint.exe>]
#>
param([string]$Exe = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe")
$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
$exePath = (Resolve-Path $Exe).Path
. "$repo\tests\autotest\lib\HermeticEngine.ps1"; $exePath = Get-HermeticEngine $exePath
$py = (Get-Command python -ErrorAction SilentlyContinue).Source
if (-not $py) { Write-Host 'FATAL: python not found (needed to make the schema 25 copy)' -ForegroundColor Red; exit 2 }
$scratch = Join-Path ([IO.Path]::GetTempPath()) "draglint_v1511_inc2_$PID"
$script:fail = 0
$script:pass = 0
function Check([string]$Name, [bool]$Ok, [string]$Detail = '') {
  Write-Host ("[{0}] {1}{2}" -f $(if ($Ok) { 'PASS' } else { 'FAIL' }), $Name, $(if ($Detail) { "  ($Detail)" } else { '' }))
  if ($Ok) { $script:pass++ } else { $script:fail++ }
}
function Invoke-Rows([string]$Db, [string]$Query) {
  $raw = (& $exePath sql --db $Db --json --query $Query 2>$null) -join "`n"
  $i = $raw.IndexOf('{')
  if ($i -lt 0) { return ,@() }
  try { $j = $raw.Substring($i) | ConvertFrom-Json } catch { return ,@() }
  if ($null -eq $j.columns) { return ,@() }
  $cols = @($j.columns | ForEach-Object { $_.name })
  $out = @()
  foreach ($r in @($j.rows)) {
    $o = [ordered]@{}
    for ($k = 0; $k -lt $cols.Count; $k++) { $o[$cols[$k]] = $r[$k] }
    $out += [pscustomobject]$o
  }
  return ,@($out)
}
function Invoke-Json([string[]]$CliArgs) {
  $raw = (& $exePath @CliArgs 2>$null) -join "`n"
  $a = $raw.IndexOf('['); $o = $raw.IndexOf('{')
  $i = if ($a -ge 0 -and ($o -lt 0 -or $a -lt $o)) { $a } else { $o }
  if ($i -lt 0) { return $null }
  try { return ($raw.Substring($i) | ConvertFrom-Json) } catch { return $null }
}
# One row per (ref, host) of the include refs: host leaf, target leaf + line ('' = unbound for that host).
$qHost = "SELECT r.name_text AS name, r.kind AS kind, r.start_line AS line, hf.path AS host, " +
         "COALESCE(tf.path, '') AS target, COALESCE(s.start_line, 0) AS tline, " +
         "(SELECT COUNT(*) FROM symbols d WHERE d.id = hb.symbol_id) AS live " +
         "FROM ref_host_bindings hb JOIN refs r ON r.id = hb.ref_id JOIN files f ON f.id = r.file_id " +
         "JOIN files hf ON hf.id = hb.host_file_id LEFT JOIN symbols s ON s.id = hb.symbol_id " +
         "LEFT JOIN files tf ON tf.id = s.file_id"
function HostTarget($Rows, [string]$Name, [string]$Kind, [int]$Line, [string]$HostLeaf) {
  $h = @($Rows | Where-Object { $_.name -eq $Name -and $_.kind -eq $Kind -and $_.line -eq $Line -and (Split-Path $_.host -Leaf) -eq $HostLeaf })
  if ($h.Count -ne 1) { return "<$($h.Count) rows>" }
  if ($h[0].target -eq '') { return '' }
  return ('{0}:{1}' -f (Split-Path $h[0].target -Leaf), $h[0].tline)
}
function RefSymbol([string]$Db, [string]$Name, [int]$Line) {
  $r = Invoke-Rows $Db ("SELECT COALESCE(tf.path, '') AS target, COALESCE(s.start_line, 0) AS tline FROM refs r JOIN files f ON f.id = r.file_id " +
                        "LEFT JOIN symbols s ON s.id = r.symbol_id LEFT JOIN files tf ON tf.id = s.file_id " +
                        "WHERE f.path LIKE '%PhShared.inc' AND r.name_text = '$Name' AND r.start_line = $Line")
  if ($r.Count -ne 1) { return "<$($r.Count) refs>" }
  if ($r[0].target -eq '') { return '' }
  return ('{0}:{1}' -f (Split-Path $r[0].target -Leaf), $r[0].tline)
}
function HasTable([string]$Db) {
  return (Invoke-Rows $Db "SELECT name FROM sqlite_master WHERE type = 'table' AND name = 'ref_host_bindings'").Count -eq 1
}
function SchemaVersion([string]$Db) {
  $r = Invoke-Rows $Db "SELECT value FROM schema_meta WHERE key = 'schema_version'"
  if ($r.Count -ne 1) { return 0 }
  return [int]$r[0].value
}
function SiteIn($Arr, [int]$Line) {
  return @($Arr | Where-Object { $_ -and ((Split-Path ([string]$_.file) -Leaf) -eq 'PhShared.inc') -and ($_.line -eq $Line) }).Count
}
function Check-PerHost([string]$Tag, [string]$Db, [string]$ClashB) {
  $rows = Invoke-Rows $Db $qHost
  Check "$Tag B Emit, host PhA -> PhA.Emit"   ((HostTarget $rows 'Emit' 'call' 3 'PhA.pas') -eq 'PhA.pas:17') (HostTarget $rows 'Emit' 'call' 3 'PhA.pas')
  Check "$Tag B Emit, host PhB -> PhB.Emit"   ((HostTarget $rows 'Emit' 'call' 3 'PhB.pas') -eq 'PhB.pas:17') (HostTarget $rows 'Emit' 'call' 3 'PhB.pas')
  Check "$Tag B Emit keeps refs.symbol_id NULL (hosts differ)" ((RefSymbol $Db 'Emit' 3) -eq '') (RefSymbol $Db 'Emit' 3)
  Check "$Tag B Clash, host PhA -> PhA.Clash" ((HostTarget $rows 'Clash' 'call' 5 'PhA.pas') -eq 'PhA.pas:18') (HostTarget $rows 'Clash' 'call' 5 'PhA.pas')
  Check "$Tag B Clash, host PhB -> $ClashB"   ((HostTarget $rows 'Clash' 'call' 5 'PhB.pas') -eq $ClashB) (HostTarget $rows 'Clash' 'call' 5 'PhB.pas')
  Check "$Tag B Helper (Self call in the include method body), host PhA -> PhA TWork.Helper" ((HostTarget $rows 'Helper' 'call' 10 'PhA.pas') -eq 'PhA.pas:14') (HostTarget $rows 'Helper' 'call' 10 'PhA.pas')
  Check "$Tag B Helper, host PhB -> PhB TWork.Helper" ((HostTarget $rows 'Helper' 'call' 10 'PhB.pas') -eq 'PhB.pas:14') (HostTarget $rows 'Helper' 'call' 10 'PhB.pas')
  Check "$Tag B FCount write, host PhA -> PhA TWork.FCount" ((HostTarget $rows 'FCount' 'write' 11 'PhA.pas') -eq 'PhA.pas:11') (HostTarget $rows 'FCount' 'write' 11 'PhA.pas')
  Check "$Tag B FCount write, host PhB -> PhB TWork.FCount" ((HostTarget $rows 'FCount' 'write' 11 'PhB.pas') -eq 'PhB.pas:11') (HostTarget $rows 'FCount' 'write' 11 'PhB.pas')
  Check "$Tag B header qualifier TWork, host PhA -> PhA.TWork" ((HostTarget $rows 'TWork' 'type_use' 8 'PhA.pas') -eq 'PhA.pas:9') (HostTarget $rows 'TWork' 'type_use' 8 'PhA.pas')
  Check "$Tag B header qualifier TWork, host PhB -> PhB.TWork" ((HostTarget $rows 'TWork' 'type_use' 8 'PhB.pas') -eq 'PhB.pas:9') (HostTarget $rows 'TWork' 'type_use' 8 'PhB.pas')
  foreach ($hostLeaf in @('PhA.pas', 'PhB.pas')) {
    Check "$Tag B cLimit read (unit const), host $hostLeaf -> its own const" ((HostTarget $rows 'cLimit' 'read' 16 $hostLeaf) -like "$hostLeaf`:*") (HostTarget $rows 'cLimit' 'read' 16 $hostLeaf)
    Check "$Tag B gTotal write (unit var), host $hostLeaf -> its own var"    ((HostTarget $rows 'gTotal' 'write' 16 $hostLeaf) -like "$hostLeaf`:*") (HostTarget $rows 'gTotal' 'write' 16 $hostLeaf)
  }
  Check "$Tag A UProc keeps refs.symbol_id (hosts agree)" ((RefSymbol $Db 'UProc' 4) -eq 'PhU.pas:5') (RefSymbol $Db 'UProc' 4)
  Check "$Tag A UProc has one row per host, same target" (((HostTarget $rows 'UProc' 'call' 4 'PhA.pas') -eq 'PhU.pas:5') -and ((HostTarget $rows 'UProc' 'call' 4 'PhB.pas') -eq 'PhU.pas:5'))
  Check "$Tag C the single-host include writes no row" (@($rows | Where-Object { $_.name -eq 'SOnly' }).Count -eq 0)
  Check "$Tag C SOnly (single host) is bound on the ref" ((Invoke-Rows $Db "SELECT r.id FROM refs r WHERE r.name_text = 'SOnly' AND r.kind = 'call' AND r.symbol_id IS NOT NULL").Count -eq 1)
  Check "$Tag C no row names a dead symbol" (@($rows | Where-Object { $_.target -ne '' -and $_.live -ne 1 }).Count -eq 0)
  Check "$Tag C every row's host is PhA or PhB" ($rows.Count -gt 0 -and @($rows | Where-Object { (Split-Path $_.host -Leaf) -notin @('PhA.pas', 'PhB.pas') }).Count -eq 0) "$($rows.Count) rows"
}
try {
  [void](New-Item -ItemType Directory -Force -Path $scratch)
  $fx = Join-Path $scratch 'fx'
  [void](New-Item -ItemType Directory -Force -Path $fx)
  Copy-Item (Join-Path $repo 'tests\autotest\fixtures\v1511-INC2\*') $fx
  $db = Join-Path $scratch 'ph.sqlite'
  & $exePath index $fx --db $db 2>&1 | Out-Null
  Check 'index exit 0' ($LASTEXITCODE -eq 0) "exit $LASTEXITCODE"
  Check 'S the index has ref_host_bindings' (HasTable $db)
  Check 'S schema_version is 26 or newer' ((SchemaVersion $db) -ge 26) "$(SchemaVersion $db)"
  Check-PerHost 'fresh' $db 'PhU.pas:6'

  # ---- R: the readers ----
  $fc = Invoke-Json @('query', 'find-callers', '--name', 'Emit', '--db', $db, '--json')
  $site = @($fc | Where-Object { $_ -and (Split-Path ([string]$_.file_path) -Leaf) -eq 'PhShared.inc' -and $_.start_line -eq 3 })
  Check 'R find-callers --name Emit lists the include site once' ($site.Count -eq 1) "$($site.Count)"
  Check 'R ... as exact (bound per host), not name-only' ($site.Count -eq 1 -and $site[0].resolution -eq 'exact') "$(if ($site.Count -eq 1) { $site[0].resolution })"
  $rawRes = (& $exePath query find-callers --name Emit --db $db --resolved 2>$null) -join "`n"
  $resSites = ([regex]::Matches($rawRes, 'PhShared\.inc:3\b')).Count
  Check 'R find-callers --resolved lists the include site for BOTH Emit declarations' ($resSites -eq 2) "$resSites site line(s)"
  foreach ($t in @(@('PhA.Emit', 3), @('PhB.Emit', 3), @('PhA.Clash', 5), @('PhU.Clash', 5))) {
    $u = Invoke-Json @('usages', '--name', $t[0], '--db', $db, '--json')
    $n = if ($null -eq $u) { -1 } else { SiteIn $u.calls $t[1] }
    Check "R usages --name $($t[0]) lists the include call site" ($n -eq 1) "$n"
  }
  $uS = Invoke-Json @('usages', '--name', 'PhS.SOnly', '--db', $db, '--json')
  Check 'R control: usages --name PhS.SOnly lists its single-host site once' ($null -ne $uS -and @($uS.calls | Where-Object { $_ -and (Split-Path ([string]$_.file) -Leaf) -eq 'PhSingle.inc' }).Count -eq 1)
  $uU = Invoke-Json @('usages', '--name', 'PhU.UProc', '--db', $db, '--json')
  Check 'R control: usages --name PhU.UProc lists the agreeing site ONCE (no double count)' ($null -ne $uU -and (SiteIn $uU.calls 4) -eq 1) "$(if ($null -ne $uU) { SiteIn $uU.calls 4 })"

  # ---- M: a schema 25 copy (read-only verbs first, then the writer upgrade) ----
  $v25 = Join-Path $scratch 'v25.sqlite'
  Copy-Item $db $v25
  $pyFile = Join-Path $scratch 'mk25.py'
  [IO.File]::WriteAllText($pyFile, "import sqlite3, sys`nc = sqlite3.connect(sys.argv[1])`nc.execute('DROP TABLE IF EXISTS ref_host_bindings')`n" +
    "c.execute(""UPDATE schema_meta SET value = '25' WHERE key = 'schema_version' AND CAST(value AS INTEGER) > 25"")`nc.commit()`nc.close()`n", [Text.Encoding]::ASCII)
  & $py -I $pyFile $v25
  Check 'M the copy was made (no table, stamp <= 25)' ((-not (HasTable $v25)) -and ((SchemaVersion $v25) -le 25)) "v$(SchemaVersion $v25)"
  $o = (& $exePath query find-callers --name Emit --db $v25 --json 2>&1 | Out-String); $c1 = $LASTEXITCODE
  Check 'M read-only find-callers on the v25 copy answers (no AV, no refusal)' ($c1 -eq 0 -and $o -notmatch 'Access violation|no such table|index schema v') "exit $c1"
  $o = (& $exePath query find-callers --name Emit --db $v25 --resolved 2>&1 | Out-String); $c1 = $LASTEXITCODE
  # exit 1 = "0 caller(s)": without the table the differing site has no resolved caller row
  Check 'M read-only find-callers --resolved on the v25 copy answers' ($c1 -in @(0, 1) -and $o -match 'caller\(s\)' -and $o -notmatch 'Access violation|no such table') "exit $c1"
  $o = (& $exePath usages --name PhA.Emit --db $v25 --json 2>&1 | Out-String); $c1 = $LASTEXITCODE
  Check 'M read-only usages on the v25 copy answers' ($c1 -eq 0 -and $o -notmatch 'Access violation|no such table') "exit $c1"
  Check 'M the read-only verbs did not migrate the copy' (-not (HasTable $v25))
  & $exePath index $fx --db $v25 2>&1 | Out-Null
  Check 'M index into the v25 copy: exit 0' ($LASTEXITCODE -eq 0) "exit $LASTEXITCODE"
  Check 'M ... the table is present, schema_version 26 or newer' ((HasTable $v25) -and ((SchemaVersion $v25) -ge 26)) "v$(SchemaVersion $v25)"
  $kept = Invoke-Rows $v25 "SELECT (SELECT COUNT(*) FROM refs) AS refs, (SELECT COUNT(*) FROM call_edges) AS edges, (SELECT COUNT(*) FROM symbols) AS syms"
  $orig = Invoke-Rows $db  "SELECT (SELECT COUNT(*) FROM refs) AS refs, (SELECT COUNT(*) FROM call_edges) AS edges, (SELECT COUNT(*) FROM symbols) AS syms"
  Check 'M ... the migration kept refs / call_edges / symbols' ($kept.Count -eq 1 -and $kept[0].refs -eq $orig[0].refs -and $kept[0].edges -eq $orig[0].edges -and $kept[0].syms -eq $orig[0].syms) "$($kept[0].refs)/$($kept[0].edges)/$($kept[0].syms)"
  # The rows are the calls pass's: an unchanged index is not re-resolved by the migration itself
  # (the release's resolver-version bump is what re-resolves every DB); --resolve-only does it here.
  & $exePath index $fx --db $v25 --resolve-only 2>&1 | Out-Null
  Check 'M re-resolve of the migrated copy: exit 0' ($LASTEXITCODE -eq 0) "exit $LASTEXITCODE"
  Check-PerHost 'migrated' $v25 'PhU.pas:6'

  # ---- I: incremental -- PhB gains its own Clash ----
  $bPath = Join-Path $fx 'PhB.pas'
  $b = [IO.File]::ReadAllText($bPath)
  $b = $b.Replace("procedure Emit;`r`n`r`nimplementation", "procedure Emit;`r`nprocedure Clash;`r`n`r`nimplementation")
  $b = $b.Replace("{`$I PhShared.inc}", "procedure Clash;`r`nbegin`r`nend;`r`n`r`n{`$I PhShared.inc}")
  [IO.File]::WriteAllText($bPath, $b, [Text.Encoding]::ASCII)
  (Get-Item $bPath).LastWriteTime = (Get-Date).AddSeconds(5)
  & $exePath index $fx --db $db 2>&1 | Out-Null
  Check 'I incremental index exit 0' ($LASTEXITCODE -eq 0) "exit $LASTEXITCODE"
  Check-PerHost 'incremental' $db 'PhB.pas:18'
} finally {
  if (Test-Path $scratch) { try { [IO.Directory]::Delete($scratch, $true) } catch { } }
}
Write-Host ("run_v1511_INC2_per_host_bindings: {0} pass, {1} fail" -f $script:pass, $script:fail)
if ($script:fail -gt 0) { exit 1 }
exit 0
