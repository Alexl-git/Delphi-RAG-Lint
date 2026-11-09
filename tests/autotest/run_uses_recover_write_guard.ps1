<#
  run_uses_recover_write_guard.ps1 -- lane 149-HW, spec docs\superpowers\specs\2026-11-08-uses-recover.md
  "The write path" (+ "149 HW: as built").

  `uses-recover --apply` STORES what the read verb recovers: one synthetic files row per recovered
  header (language 'hpp'), its #include edges as unit_uses rows (section interface, origin_path =
  the header), and the resolve pass binds the project's rows to it (target_file_id). Also the read
  side's unit aliases: `--project <x.dproj>` reads DCC_UnitAlias (+ the Delphi targets' defaults).

  FIXTURE tests\fixtures\uses-recover (the read guard's; see run_uses_recover_guard.ps1) plus
  src-alias\Probe3.dpr (uses OldName) + Probe3.dproj (DCC_UnitAlias OldName=FixRtl).

  POSITIVE CONTROLS: a run without --apply writes 0 rows and leaves the DB bytes unchanged;
  without --library-db FixRtl becomes a recovered header row (and a later run with it removes
  that row again); without --project OldName stays under no_header. Run under pwsh 7.
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\drag-lint-uses-recover-write-$PID"
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
$Fix = (Resolve-Path "$PSScriptRoot\..\fixtures\uses-recover").Path
[void](New-Item -ItemType Directory -Force $WorkDir)
$Src = Join-Path $WorkDir 'src'
[void](New-Item -ItemType Directory -Force $Src)
Copy-Item (Join-Path $Fix 'src\*.dpr') $Src
$ProjDb  = Join-Path $WorkDir 'proj.sqlite'
$CtlDb   = Join-Path $WorkDir 'ctl.sqlite'
$LibDb   = Join-Path $WorkDir 'lib.sqlite'
$AliasDb = Join-Path $WorkDir 'alias.sqlite'
$Hpp     = Join-Path $Fix 'hpp'
$Dproj   = Join-Path $Fix 'src-alias\Probe3.dproj'

function Run([string[]]$a) {
  $out = & $Exe @a 2>$null | Out-String
  [pscustomobject]@{ Code = $LASTEXITCODE; Out = $out }
}
function Json($r) { try { $r.Out | ConvertFrom-Json } catch { $null } }
# sql --json rows are POSITIONAL arrays: map them onto columns[].name. Returns the rows UNROLLED:
# wrap a call in @() before .Count / indexing.
function Sql([string]$db, [string]$q) {
  $j = Json (Run @('sql', '--query', $q, '--db', $db, '--json'))
  if (-not $j) { return }
  $names = @($j.columns | ForEach-Object name)
  $rows = @(foreach ($row in @($j.rows)) {
    $o = [ordered]@{}
    for ($i = 0; $i -lt $names.Count; $i++) { $o[$names[$i]] = $row[$i] }
    [pscustomobject]$o
  })
  return $rows
}
function Leaf([string]$p) { if ($p) { Split-Path $p -Leaf } else { '' } }
$QHpp  = "SELECT id, path, language FROM files WHERE language = 'hpp' ORDER BY path"
$QUses = "SELECT f.path AS src, u.unit_name, u.section, u.origin_path, t.path AS dst FROM unit_uses u JOIN files f ON f.id = u.file_id LEFT JOIN files t ON t.id = u.target_file_id ORDER BY f.path, u.unit_name"
function Dump([string]$db) {
  (@(Sql $db $QHpp | ForEach-Object { "F $(Leaf $_.path) $($_.language)" }) +
   @(Sql $db $QUses | ForEach-Object { "U $(Leaf $_.src) $($_.unit_name) $($_.section) $(Leaf $_.origin_path) -> $(Leaf $_.dst)" })) -join "`n"
}
function UnitsKey($j) {
  if (-not $j) { return '' }
  ((@($j.units | ForEach-Object { "$($_.unit):$($_.reach):$((@($_.uses | ForEach-Object { $_.unit + '=' + $_.status })) -join ',')" }) +
    @($j.no_header | ForEach-Object { "nohdr:$($_.unit)" })) -join ';')
}

Write-Host '-- setup: index the project and the library fixture into scratch DBs' -ForegroundColor Cyan
$r = Run @('index', $Src, '--db', $ProjDb)
Check 'setup: project fixture indexed' ($r.Code -eq 0) "exit $($r.Code)"
$r = Run @('index', $Src, '--db', $CtlDb)
Check 'setup: control project fixture indexed' ($r.Code -eq 0) "exit $($r.Code)"
$r = Run @('index', (Join-Path $Fix 'rtlsrc'), '--db', $LibDb)
Check 'setup: library fixture indexed' ($r.Code -eq 0) "exit $($r.Code)"
$base = @('uses-recover', '--db', $ProjDb, '--hpp-dir', $Hpp, '--library-db', $LibDb, '--json')
$jBefore = Json (Run $base)
Check 'setup: read report recovers FixLibA + FixLibB' ((UnitsKey $jBefore) -match 'FixLibA:direct' -and (UnitsKey $jBefore) -match 'FixLibB:header') (UnitsKey $jBefore)

Write-Host '-- 1: positive control, no --apply writes nothing' -ForegroundColor Cyan
$sha0 = (Get-FileHash $CtlDb -Algorithm SHA256).Hash
$r = Run @('uses-recover', '--db', $CtlDb, '--hpp-dir', $Hpp, '--library-db', $LibDb, '--json')
Check '1 read run exits 0' ($r.Code -eq 0) "exit $($r.Code)"
Check '1 read run: DB bytes unchanged' ((Get-FileHash $CtlDb -Algorithm SHA256).Hash -eq $sha0)
Check '1 read run: 0 header rows' ((Sql $CtlDb $QHpp).Count -eq 0)
$j1 = Json $r
Check '1 read run: no "applied" member' ($j1 -and -not ($j1.PSObject.Properties.Name -contains 'applied')) ($r.Out.Trim())

Write-Host '-- 2: --apply stores the header rows and binds the project row' -ForegroundColor Cyan
$r = Run ($base + @('--apply'))
Check '2 apply exits 0' ($r.Code -eq 0) "exit $($r.Code) $($r.Out.Trim())"
$j2 = Json $r
Check '2 json reports applied files=2' ($j2 -and $j2.applied.files -eq 2) ($r.Out.Trim())
$hppRows = Sql $ProjDb $QHpp
Check '2 two header file rows (FixLibA.hpp, FixLibB.hpp)' ((@($hppRows | ForEach-Object { Leaf $_.path }) -join ',') -eq 'FixLibA.hpp,FixLibB.hpp') (@($hppRows | ForEach-Object { Leaf $_.path }) -join ',')
$uses = Sql $ProjDb $QUses
$aRows = @($uses | Where-Object { (Leaf $_.src) -eq 'FixLibA.hpp' })
Check '2 FixLibA.hpp -> FixLibB, FixRtl (no System/SysInit)' ((@($aRows | ForEach-Object unit_name) -join ',') -eq 'FixLibB,FixRtl') (@($aRows | ForEach-Object unit_name) -join ',')
Check '2 header rows are section interface' ((@($aRows | Where-Object section -ne 'interface')).Count -eq 0 -and $aRows.Count -gt 0)
Check '2 header rows carry origin_path = the header' ((@($aRows | Where-Object { (Leaf $_.origin_path) -ne 'FixLibA.hpp' })).Count -eq 0 -and $aRows.Count -gt 0)
$pa = @($uses | Where-Object { (Leaf $_.src) -eq 'Probe.dpr' -and $_.unit_name -eq 'FixLibA' })
Check '2 Probe.dpr uses FixLibA -> FixLibA.hpp (target_file_id bound)' ($pa.Count -eq 1 -and (Leaf $pa[0].dst) -eq 'FixLibA.hpp') (Dump $ProjDb)
$ab = @($aRows | Where-Object unit_name -eq 'FixLibB')
Check '2 FixLibA.hpp uses FixLibB -> FixLibB.hpp' ($ab.Count -eq 1 -and (Leaf $ab[0].dst) -eq 'FixLibB.hpp')
$ar = @($aRows | Where-Object unit_name -eq 'FixRtl')
Check '2 FixRtl (library) stays unbound in the project DB' ($ar.Count -eq 1 -and -not $ar[0].dst)
$nh = @($uses | Where-Object { $_.unit_name -eq 'NoHdrLib' })
Check '2 NoHdrLib (no header) stays unbound' ($nh.Count -eq 1 -and -not $nh[0].dst)

Write-Host '-- 3: idempotent; the read report does not change after --apply' -ForegroundColor Cyan
$dump1 = Dump $ProjDb
$r = Run ($base + @('--apply'))
Check '3 second apply exits 0' ($r.Code -eq 0) "exit $($r.Code)"
$dump2 = Dump $ProjDb
Check '3 rows identical after a second apply' ($dump1 -match 'F FixLibA.hpp hpp' -and $dump1 -eq $dump2) "`n--1--`n$dump1`n--2--`n$dump2"
$jAfter = Json (Run $base)
Check '3 read report after apply = before apply' ((UnitsKey $jAfter) -eq (UnitsKey $jBefore)) "before=$(UnitsKey $jBefore) after=$(UnitsKey $jAfter)"

Write-Host '-- 4: replacement: a header no longer recovered loses its row' -ForegroundColor Cyan
$r = Run @('uses-recover', '--db', $ProjDb, '--hpp-dir', $Hpp, '--apply', '--json')
$names4 = @(Sql $ProjDb $QHpp | ForEach-Object { Leaf $_.path }) -join ','
Check '4 without --library-db FixRtl.hpp is stored too' ($names4 -eq 'FixLibA.hpp,FixLibB.hpp,FixRtl.hpp') $names4
$r = Run ($base + @('--apply'))
$names4b = @(Sql $ProjDb $QHpp | ForEach-Object { Leaf $_.path }) -join ','
Check '4 with --library-db again FixRtl.hpp is removed' ($names4b -eq 'FixLibA.hpp,FixLibB.hpp') $names4b
Check '4 rows back to the step-2 state' ($dump1 -match 'F FixLibA.hpp hpp' -and (Dump $ProjDb) -eq $dump1) (Dump $ProjDb)

Write-Host '-- 5: the binding survives a re-index of the project' -ForegroundColor Cyan
$p = Join-Path $Src 'Probe.dpr'
[IO.File]::AppendAllText($p, "`r`n{ touched by the guard }`r`n")
(Get-Item $p).LastWriteTime = (Get-Date).AddMinutes(1)
$r = Run @('index', $Src, '--db', $ProjDb)
Check '5 re-index exits 0' ($r.Code -eq 0) "exit $($r.Code)"
$pa5 = @(Sql $ProjDb $QUses | Where-Object { (Leaf $_.src) -eq 'Probe.dpr' -and $_.unit_name -eq 'FixLibA' })
Check '5 Probe.dpr uses FixLibA still -> FixLibA.hpp' ($pa5.Count -eq 1 -and (Leaf $pa5[0].dst) -eq 'FixLibA.hpp') (Dump $ProjDb)
Check '5 header rows survive the re-index' ((Sql $ProjDb $QHpp).Count -eq 2)

Write-Host '-- 6: unit aliases from --project (DCC_UnitAlias)' -ForegroundColor Cyan
$r = Run @('index', (Join-Path $Fix 'src-alias'), '--db', $AliasDb)
Check '6 alias fixture indexed' ($r.Code -eq 0) "exit $($r.Code)"
$j6a = Json (Run @('uses-recover', '--db', $AliasDb, '--hpp-dir', $Hpp, '--library-db', $LibDb, '--json'))
Check '6 control: without --project OldName is under no_header' ($j6a -and (@($j6a.no_header | Where-Object unit -eq 'OldName')).Count -eq 1) (UnitsKey $j6a)
$r = Run @('uses-recover', '--db', $AliasDb, '--hpp-dir', $Hpp, '--library-db', $LibDb, '--project', $Dproj, '--json')
$j6 = Json $r
Check '6 --project exits 0' ($r.Code -eq 0) "exit $($r.Code)"
Check '6 with --project OldName is no longer under no_header' ($j6 -and (@($j6.no_header | Where-Object unit -eq 'OldName')).Count -eq 0) ($r.Out.Trim())
$al = if ($j6) { @($j6.aliases | Where-Object unit -eq 'OldName') } else { @() }
Check '6 aliases lists OldName -> FixRtl (library)' ($al.Count -eq 1 -and $al[0].to -eq 'FixRtl' -and $al[0].status -eq 'library') ($r.Out.Trim())
$wp = if ($j6) { @($j6.aliases | Where-Object unit -eq 'WinProcs') } else { @() }
Check '6 Delphi-targets default alias WinProcs -> Winapi.Windows' ($wp.Count -eq 1 -and $wp[0].to -eq 'Winapi.Windows') ($r.Out.Trim())
Check '6 control: without --project WinProcs is under no_header' ($j6a -and (@($j6a.no_header | Where-Object unit -eq 'WinProcs')).Count -eq 1)
$r = Run @('uses-recover', '--db', $AliasDb, '--hpp-dir', $Hpp, '--project', (Join-Path $WorkDir 'nope.dproj'))
Check '6 missing --project file exits 2' ($r.Code -eq 2) "exit $($r.Code)"

try { [IO.Directory]::Delete($WorkDir, $true) } catch { }
if ($script:Failed) { Write-Host 'uses-recover write guard: FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'uses-recover write guard: PASS' -ForegroundColor Green
exit 0
