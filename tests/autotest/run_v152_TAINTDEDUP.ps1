# run_v152_TAINTDEDUP.ps1 -- lane TAINTDEDUP (1.52): the taint rules report ONE finding per sink
# site (file + line + col + rule), not one per source->sink path. Fixture
# tests\lint-project\taint-dedup\uDedup.pas: four callers pass ParamStr(1..4) to Spawn, whose one
# CreateProcess call takes the value in two arguments (line 27: 4 sources, 4 distinct paths), and
# one ParamStr(5) reaches SpawnTwo's CreateProcess in arg 0 directly and in arg 1 through Wrap
# (line 35: 1 source, 2 paths).
#
# Asserts: exactly one taint-command-injection finding per sink line; its message names the
# shortest path and ends "(4 sources, 4 paths)" / "(1 source, 2 paths)"; --json `path` is that
# shortest path and `paths` keeps ALL of them (source first, sink last each) -- no information lost; a dl:ok marker on the sink
# line (stamped by -StampExe, default -Exe: pass the pre-1.52 engine to prove an OLD marker still
# holds) suppresses the merged finding and is neither stale nor unused.
# POSITIVE CONTROL: the same lint without the marker finds the sink (the marker check can fail).
#
# Usage: pwsh -File tests\autotest\run_v152_TAINTDEDUP.ps1 [-Exe <drag-lint.exe>] [-StampExe <exe>]
param([string]$Exe = '', [string]$StampExe = '')
$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
if ($Exe -eq '') { $Exe = Join-Path $repo 'src\cli\Win64\Debug\drag-lint.exe' }
$exePath = (Resolve-Path $Exe).Path
$stampPath = if ($StampExe -eq '') { $exePath } else { (Resolve-Path $StampExe).Path }
$fx    = Join-Path $repo 'tests\lint-project\taint-dedup'
$tmp   = Join-Path $env:TEMP "taintdedup_$PID"
[void][IO.Directory]::CreateDirectory($tmp)
$empty = Join-Path $tmp 'empty.json'
[IO.File]::WriteAllText($empty, '{}')
$SINK_LINE = 27; $SINK_TWO = 35

$fail = 0
function Check([string]$Name, [bool]$Ok, [string]$Detail = '') {
  if ($Ok) { Write-Host "PASS  $Name" } else { Write-Host "FAIL  $Name  $Detail"; $script:fail++ }
}
function AllFindings([string[]]$CliArgs) {
  $raw = & { $ErrorActionPreference = 'Continue'; & $exePath @CliArgs 2>$null }
  $txt = ($raw -join "`n"); $b = $txt.IndexOf('[')
  $all = @(); if ($b -ge 0) { try { $all = @($txt.Substring($b) | ConvertFrom-Json) } catch { $all = @() } }
  return ,$all
}

Push-Location $env:TEMP
try {
  # ---- 1: one finding per sink site ----
  $work = Join-Path $tmp 'a'; [void][IO.Directory]::CreateDirectory($work)
  [IO.File]::Copy((Join-Path $fx 'uDedup.pas'), (Join-Path $work 'uDedup.pas'), $true)
  $db = Join-Path $tmp 'a.sqlite'
  & { $ErrorActionPreference = 'Continue'; & $exePath index $work --db $db 2>&1 | ForEach-Object { "$_" } } | Out-Null
  $all = AllFindings @('lint-all', '--db', $db, '--json', '--quiet', '--config', $empty)
  $f = @($all | Where-Object { $_.rule -like 'taint-*' })
  $f | ForEach-Object { Write-Host ("  {0} {1}:{2}:{3} {4}" -f $_.rule, (Split-Path $_.file_path -Leaf), $_.start_line, $_.start_col, $_.message) }
  $at = @($f | Where-Object { $_.rule -eq 'taint-command-injection' -and $_.start_line -eq $SINK_LINE })
  Check "exactly one taint-command-injection finding at uDedup.pas:$SINK_LINE" ($at.Count -eq 1) "got $($at.Count)"
  $two = @($f | Where-Object { $_.rule -eq 'taint-command-injection' -and $_.start_line -eq $SINK_TWO })
  Check "exactly one taint-command-injection finding at uDedup.pas:$SINK_TWO" ($two.Count -eq 1) "got $($two.Count)"
  Check 'two taint findings in the fixture, one per sink' ($f.Count -eq 2) "got $($f.Count) total"
  if ($two.Count -ge 1) {
    Check 'SpawnTwo: message summarises 1 source, 2 paths' ($two[0].message -match '\(1 source, 2 paths\)') $two[0].message
    $tp = @($two[0].paths)
    Check 'SpawnTwo: --json paths keeps both paths (arg 0 and arg 1 via Wrap)' ($tp.Count -eq 2) "got $($tp.Count)"
    $viaWrap = @($tp | Where-Object { (@($_) | ForEach-Object { $_.note }) -match 'through Wrap' })
    Check 'SpawnTwo: one listed path crosses Wrap' ($viaWrap.Count -ge 1) (($tp | ForEach-Object { (@($_) | ForEach-Object { "$($_.line):$($_.note)" }) -join ' > ' }) -join ' || ')
  }
  if ($at.Count -ge 1) {
    $m = $at[0]
    Check 'message summarises 4 sources, 4 paths' ($m.message -match '\(4 sources, 4 paths\)') $m.message
    Check 'message names the shortest path (source ParamStr, sink CreateProcess)' ($m.message -match 'CreateProcess from ParamStr') $m.message
    Check 'message drops the old "+N more paths" tail' ($m.message -notmatch 'more paths') $m.message
    $paths = @($m.paths)
    Check '--json paths keeps all 4 paths' ($paths.Count -eq 4) "got $($paths.Count)"
    $bad = @($paths | Where-Object { @($_)[0].note -notmatch '^source ' -or @($_)[-1].note -notmatch '^sink ' })
    Check 'every listed path runs source first, sink last' ($bad.Count -eq 0) "$($bad.Count) malformed"
    $srcLines = @($paths | ForEach-Object { @($_)[0].line } | Sort-Object -Unique)
    Check 'the paths name 4 distinct source sites' ($srcLines.Count -eq 4) "lines: $($srcLines -join ',')"
    $lens = @($paths | ForEach-Object { @($_).Count })
    Check 'path = paths[0], the shortest' ((@($m.path).Count -eq $lens[0]) -and ($lens[0] -eq ($lens | Measure-Object -Minimum).Minimum)) "path $(@($m.path).Count), lens $($lens -join ',')"
  }

  # ---- 2: lint <file> --db agrees ----
  $one = @(AllFindings @('lint', (Join-Path $work 'uDedup.pas'), '--db', $db, '--json', '--config', $empty) | Where-Object { $_.rule -like 'taint-*' })
  Check "lint <file> --db: one finding at :$SINK_LINE too" ((@($one | Where-Object { $_.start_line -eq $SINK_LINE })).Count -eq 1) "got $($one.Count)"

  # ---- 3: a dl:ok marker on the sink line still suppresses the merged finding ----
  $mk = Join-Path $tmp 'm'; [void][IO.Directory]::CreateDirectory($mk)
  $mkUnit = Join-Path $mk 'uDedup.pas'
  [IO.File]::Copy((Join-Path $fx 'uDedup.pas'), $mkUnit, $true)
  # stamp the LOWER line first: a marker line inserted above would shift the upper one
  foreach ($ln in @($SINK_TWO, $SINK_LINE)) {
    & { $ErrorActionPreference = 'Continue'; & $stampPath rules disable --rule taint-command-injection --scope line --in $mkUnit --line $ln --reason 'TAINTDEDUP marker check' 2>&1 | ForEach-Object { "$_" } } | Out-Null
  }
  $txt = [IO.File]::ReadAllText($mkUnit)
  Check 'marker stamped on the sink line' (([regex]::Matches($txt, 'dl:ok taint-command-injection')).Count -eq 2) 'no marker written'
  $mdb = Join-Path $tmp 'm.sqlite'
  & { $ErrorActionPreference = 'Continue'; & $exePath index $mk --db $mdb 2>&1 | ForEach-Object { "$_" } } | Out-Null
  $mall = AllFindings @('lint-all', '--db', $mdb, '--json', '--quiet', '--config', $empty, '--enable', 'review-marker-stale,review-marker-unused')
  $mt = @($mall | Where-Object { $_.rule -like 'taint-*' })
  Check 'markers suppress both merged findings' ($mt.Count -eq 0) "got $($mt.Count)"
  $mr = @($mall | Where-Object { $_.rule -like 'review-marker-*' })
  Check 'marker is neither stale nor unused' ($mr.Count -eq 0) (($mr | ForEach-Object { "$($_.rule):$($_.start_line) $($_.message)" }) -join ' | ')
  Check 'positive control: without the marker the sink is found' ($at.Count -ge 1)
}
finally {
  Pop-Location
  try { [IO.Directory]::Delete($tmp, $true) } catch { }
}
if ($fail -eq 0) { Write-Host 'run_v152_TAINTDEDUP: ALL PASS'; exit 0 }
Write-Host "run_v152_TAINTDEDUP: $fail FAILED"; exit 1