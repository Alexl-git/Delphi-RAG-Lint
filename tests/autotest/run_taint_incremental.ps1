# run_taint_incremental.ps1 -- lane TAINT (1.52.2, 2026-11-20): an INCREMENTAL reindex gives the
# SAME taint facts and findings as a FRESH index of the same tree
# (docs\INBOX-incremental-taint-facts-stale.md).
#
# Steps: copy the taint fixture (tests\lint-project\taint\) to a temp tree, index it fresh, then
# insert a comment line under `unit X;` in every OTHER unit (comment-only edit, shifts every line
# below it, half the units untouched so cross-unit paths join edited and unedited files), reindex
# the SAME db incrementally, and index the edited tree into a second, FRESH db.
# Asserts: the incremental run really was incremental (some files skipped up-to-date); data_flows
# and call_edges row counts are equal; the taint findings (rule + file + line + col + message) are
# identical. Positive controls: the fixture yields taint findings at all, and the edited tree's
# findings differ from the pre-edit ones (the edit moved sink lines), so the equality check cannot
# pass on two runs that both ignored the edit.
#
# Usage: pwsh -File tests\autotest\run_taint_incremental.ps1 [-Exe <drag-lint.exe>]
param([string]$Exe = '')
$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
if ($Exe -eq '') { $Exe = Join-Path $repo 'third_party\dll-win64\drag-lint.exe' }
$exePath = (Resolve-Path $Exe).Path
$fx      = Join-Path $repo 'tests\lint-project\taint'
$libFx   = Join-Path $repo 'tests\lint-project\taint-lib\lib'
$tmp     = Join-Path $env:TEMP "taint_incr_$PID"
[void][IO.Directory]::CreateDirectory($tmp)
$src     = Join-Path $tmp 'src'
[void][IO.Directory]::CreateDirectory($src)
$inc     = Join-Path $tmp 'inc.sqlite'
$fresh   = Join-Path $tmp 'fresh.sqlite'
$lib     = Join-Path $tmp 'lib.sqlite'
$empty   = Join-Path $tmp 'empty.json'
[IO.File]::WriteAllText($empty, '{}')

$fail = 0
function Check([string]$Name, [bool]$Ok, [string]$Detail = '') {
  if ($Ok) { Write-Host "PASS  $Name" } else { Write-Host "FAIL  $Name  $Detail"; $script:fail++ }
}
function Index([string]$Db) {
  return @(& { $ErrorActionPreference = 'Continue'; & $exePath index $src --db $Db --rule-cache-warm off 2>&1 | ForEach-Object { "$_" } })
}
function TaintKeys([string]$Db) {
  $raw = & { $ErrorActionPreference = 'Continue'; & $exePath lint-all --db $Db --db $lib --json --quiet --config $empty 2>$null }
  $txt = ($raw -join "`n"); $b = $txt.IndexOf('[')
  $all = @(); if ($b -ge 0) { $all = @($txt.Substring($b) | ConvertFrom-Json | ForEach-Object { $_ }) }
  return ,@($all | Where-Object { $_.rule -like 'taint-*' } |
    ForEach-Object { '{0}|{1}|{2}|{3}|{4}' -f $_.rule, (Split-Path $_.file_path -Leaf), $_.start_line, $_.start_col, $_.message } | Sort-Object)
}
function Count([string]$Db, [string]$Table) {
  $raw = & { $ErrorActionPreference = 'Continue'; & $exePath sql --db $Db --json --query "SELECT COUNT(*) AS n FROM $Table" 2>$null }
  return (($raw -join "`n") | ConvertFrom-Json).rows[0][0]
}

Push-Location $env:TEMP
try {
  Get-ChildItem $fx -Filter *.pas | ForEach-Object { [IO.File]::Copy($_.FullName, (Join-Path $src $_.Name), $true) }
  & { $ErrorActionPreference = 'Continue'; & $exePath index $libFx --db $lib 2>&1 | ForEach-Object { "$_" } } | Out-Null
  [void](Index $inc)
  $before = TaintKeys $inc
  Check 'positive control: the fixture has taint findings' ($before.Count -gt 0) 'got 0'

  # comment-only edit in every other unit; the file must get a NEWER mtime than the index saw
  $units = @(Get-ChildItem $src -Filter *.pas | Sort-Object Name)
  $edited = 0
  for ($i = 0; $i -lt $units.Count; $i += 2) {
    $p = $units[$i].FullName
    $t = [IO.File]::ReadAllText($p)
    $m = [regex]::Match($t, '(?im)^unit\s+[\w.]+\s*;\r\n')
    if (-not $m.Success) { continue }
    $t = $t.Insert($m.Index + $m.Length, "// incremental-taint edit: comment only`r`n")
    [IO.File]::WriteAllText($p, $t)
    [IO.File]::SetLastWriteTimeUtc($p, [DateTime]::UtcNow.AddMinutes(1))
    $edited++
  }
  Check 'edit: comment line inserted in half the units' ($edited -gt 0 -and $edited -lt $units.Count) "edited $edited of $($units.Count)"

  $log = Index $inc
  $done = ($log | Where-Object { $_ -match 'skipped (\d+) up-to-date' } | Select-Object -Last 1)
  $skipped = if ($done -match 'skipped (\d+) up-to-date') { [int]$Matches[1] } else { 0 }
  Check 'second run was incremental (files skipped up-to-date)' ($skipped -gt 0) "Done line: $done"
  [void](Index $fresh)

  foreach ($tbl in 'data_flows', 'call_edges') {
    $a = Count $inc $tbl; $b = Count $fresh $tbl
    Check "$tbl rows: incremental = fresh" ($a -eq $b -and $a -gt 0) "incremental $a, fresh $b"
  }
  $after = TaintKeys $inc
  $ref   = TaintKeys $fresh
  $diff  = @(Compare-Object $after $ref | ForEach-Object { "$($_.SideIndicator) $($_.InputObject)" })
  Check 'taint findings: incremental = fresh' ($diff.Count -eq 0 -and $ref.Count -gt 0) ($diff -join '; ')
  Check 'positive control: the edit moved findings' (@(Compare-Object $before $ref).Count -gt 0) 'pre-edit and post-edit findings are identical'
} finally {
  Pop-Location
}
if ($fail -eq 0) { Write-Host 'ALL PASS'; exit 0 } else { Write-Host "$fail FAIL"; exit 1 }
