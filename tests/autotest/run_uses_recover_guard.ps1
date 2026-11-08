<#
  run_uses_recover_guard.ps1 -- lane 148-HP, spec docs\superpowers\specs\2026-11-08-uses-recover.md.

  `uses-recover` recovers the uses edges of units that have NO source in the index, from
  vendor .hpp headers and a dcc map. Owner ruling x2: no .dcu is read, by the verb or here.

  FIXTURE tests\fixtures\uses-recover (all text, captured once; nothing compiles at test time):
    src\Probe.dpr      uses FixLibA                  -- the project; indexed into a scratch DB
    src\Probe2.dpr     uses NoHdrLib                 -- no source, no header anywhere
    rtlsrc\FixRtl.pas                                -- indexed into a scratch LIBRARY DB
    libsrc\FixLibA/B/C.pas                           -- NOT indexed: they stand for the sourceless lib
    hpp\*.hpp, map\Probe.map                         -- what the compiler emitted for them
  FixLibA: interface uses FixLibB, FixRtl; implementation uses FixLibC (no header shows it).
  Regenerate the hpp + map (only if the fixture sources change), from rsvars:
    dcc32 -Q -B -JPHNE -N0<t>\dcu -NH<t>\hpp -NO<t>\obj -NB<t>\bpi -U libsrc;rtlsrc libsrc\FixLibA.pas
    dcc32 -Q -B -GD -N0<t>\dcu2 -E<t>\exe -U libsrc;rtlsrc src\Probe.dpr

  POSITIVE CONTROLS: without --library-db FixRtl must turn sourceless (the subtraction is live);
  without --map, in_map is null and map_only empty (the map facts come from the map); an unknown
  flag exits 3; a missing --hpp-dir exits 2. Run under pwsh 7.
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\drag-lint-uses-recover-$PID"
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
$ProjDb = Join-Path $WorkDir 'proj.sqlite'
$LibDb  = Join-Path $WorkDir 'lib.sqlite'
$Hpp    = Join-Path $Fix 'hpp'
$Map    = Join-Path $Fix 'map\Probe.map'

function Run([string[]]$a) {
  $out = & $Exe @a 2>$null | Out-String
  [pscustomobject]@{ Code = $LASTEXITCODE; Out = $out }
}

Write-Host '-- setup: index the project and the library fixture into scratch DBs' -ForegroundColor Cyan
$r = Run @('index', (Join-Path $Fix 'src'), '--db', $ProjDb)
Check 'setup: project fixture indexed' ($r.Code -eq 0) "exit $($r.Code)"
$r = Run @('index', (Join-Path $Fix 'rtlsrc'), '--db', $LibDb)
Check 'setup: library fixture indexed' ($r.Code -eq 0) "exit $($r.Code)"

Write-Host '-- 1: full run (--library-db + --map)' -ForegroundColor Cyan
$r = Run @('uses-recover', '--db', $ProjDb, '--hpp-dir', $Hpp, '--library-db', $LibDb, '--map', $Map, '--json')
Check '1 exit 0' ($r.Code -eq 0) "exit $($r.Code)"
$j = $null
try { $j = $r.Out | ConvertFrom-Json } catch { }
Check '1 json parses' ($null -ne $j)
if ($j) {
  $units = @($j.units)
  $a = $units | Where-Object unit -eq 'FixLibA'
  $b = $units | Where-Object unit -eq 'FixLibB'
  Check '1 FixLibA is a direct sourceless unit' ($a -and $a.reach -eq 'direct') ($units | ConvertTo-Json -Depth 5 -Compress)
  Check '1 FixLibA used by Probe.dpr' ($a -and (@($a.used_by) -contains 'Probe.dpr')) "$($a.used_by)"
  Check '1 FixLibA header found' ($a -and ($a.header -like '*FixLibA.hpp')) "$($a.header)"
  Check '1 FixLibA confirmed by the map' ($a -and $a.in_map -eq $true) "$($a.in_map)"
  $aUses = @($a.uses)
  Check '1 FixLibA -> FixLibB sourceless' (($aUses | Where-Object { $_.unit -eq 'FixLibB' -and $_.status -eq 'sourceless' }) -ne $null) ($aUses | ConvertTo-Json -Compress)
  Check '1 FixLibA -> FixRtl library'     (($aUses | Where-Object { $_.unit -eq 'FixRtl'  -and $_.status -eq 'library'    }) -ne $null) ($aUses | ConvertTo-Json -Compress)
  Check '1 System/SysInit dropped' ((@($aUses | Where-Object { $_.unit -in 'System','SysInit' })).Count -eq 0) ($aUses | ConvertTo-Json -Compress)
  Check '1 FixLibA has no implementation edge to FixLibC' ((@($aUses | Where-Object unit -eq 'FixLibC')).Count -eq 0)
  Check '1 FixLibB reached through the header' ($b -and $b.reach -eq 'header') "$($b.reach)"
  Check '1 FixLibB -> FixRtl library' ($b -and (@($b.uses | Where-Object { $_.unit -eq 'FixRtl' -and $_.status -eq 'library' })).Count -eq 1)
  Check '1 FixRtl is not reported as sourceless' ((@($units | Where-Object unit -eq 'FixRtl')).Count -eq 0)
  Check '1 FixLibC (implementation-only) is map_only' (@($j.map_only) -contains 'FixLibC') "$($j.map_only)"
  Check '1 map_only holds nothing else' (@($j.map_only).Count -eq 1) "$($j.map_only)"
  Check '1 NoHdrLib listed under no_header' ((@($j.no_header | Where-Object unit -eq 'NoHdrLib')).Count -eq 1) ($j.no_header | ConvertTo-Json -Compress)
  Check '1 exactly 2 units recovered' ($units.Count -eq 2) "$($units.Count)"
}

Write-Host '-- 2: positive control, no --library-db' -ForegroundColor Cyan
$r = Run @('uses-recover', '--db', $ProjDb, '--hpp-dir', $Hpp, '--map', $Map, '--json')
$j2 = $null
try { $j2 = $r.Out | ConvertFrom-Json } catch { }
$rtl = if ($j2) { @($j2.units) | Where-Object unit -eq 'FixRtl' }
Check '2 FixRtl turns sourceless without the library DB' ($rtl -and $rtl.reach -eq 'header') ($r.Out.Trim())

Write-Host '-- 3: positive control, no --map' -ForegroundColor Cyan
$r = Run @('uses-recover', '--db', $ProjDb, '--hpp-dir', $Hpp, '--library-db', $LibDb, '--json')
$j3 = $null
try { $j3 = $r.Out | ConvertFrom-Json } catch { }
$a3 = if ($j3) { @($j3.units) | Where-Object unit -eq 'FixLibA' }
Check '3 in_map is null without --map' ($a3 -and $null -eq $a3.in_map) ($r.Out.Trim())
Check '3 map_only is empty without --map' ($j3 -and @($j3.map_only).Count -eq 0)

Write-Host '-- 4: text output and exits' -ForegroundColor Cyan
$r = Run @('uses-recover', '--db', $ProjDb, '--hpp-dir', $Hpp, '--library-db', $LibDb, '--map', $Map)
Check '4 text names FixLibA -> FixLibB' ($r.Code -eq 0 -and $r.Out -match 'FixLibA' -and $r.Out -match 'FixLibB') $r.Out.Trim()
$r = Run @('uses-recover', '--db', $ProjDb, '--bogus')
Check '4 unknown flag exits 3' ($r.Code -eq 3) "exit $($r.Code)"
$r = Run @('uses-recover', '--db', $ProjDb)
Check '4 no --hpp-dir exits 2' ($r.Code -eq 2) "exit $($r.Code)"
$r = Run @('uses-recover', '--db', $ProjDb, '--hpp-dir', (Join-Path $WorkDir 'nope'))
Check '4 missing --hpp-dir dir exits 2' ($r.Code -eq 2) "exit $($r.Code)"
$r = Run @('uses-recover', '--db', $ProjDb, '--hpp-dir', $Hpp, '--map', (Join-Path $WorkDir 'nope.map'))
Check '4 missing --map file exits 2' ($r.Code -eq 2) "exit $($r.Code)"

try { [IO.Directory]::Delete($WorkDir, $true) } catch { }
if ($script:Failed) { Write-Host 'uses-recover guard: FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'uses-recover guard: PASS' -ForegroundColor Green
exit 0
