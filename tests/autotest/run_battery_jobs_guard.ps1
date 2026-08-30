<#
  run_battery_jobs_guard.ps1 -- the battery's -Jobs option and its serial
  quarantine.

  WHY THIS EXISTS
  ---------------
  `tests\run_battery.ps1 -Jobs N` runs most runners concurrently and a named
  quarantine serially. A runner joins the quarantine by carrying
  `# dl:serial: <reason>` in its first 60 lines. Two things can rot silently:

    * the marker regex and the driver's reader drift apart, so a runner that
      LOOKS quarantined is silently run in parallel;
    * a new runner joins the LSP proxy family without a marker.

  Neither fails anything today -- a battery that runs a proxy guard in parallel
  usually still passes, and only flakes later, which is the worst way to find
  out. So both are asserted here.

  WHAT THE QUARANTINE IS, AND WHAT IT IS NOT
  ------------------------------------------
  It is NOT "the runners that write the shared staged exe". The note that asked
  for -Jobs (INBOX-battery-is-single-threaded-on-a-9-thread-box) said eight
  runners write it and named them. MEASURED 2026-08-30: **zero do.** Every hit
  was a mention of `build_draglint_win64.bat` inside a block comment or a
  Write-Host advice string, or a Copy-Item pulling the tree-sitter DLLs OUT of
  dll-win64 into the runner's own scratch dir. run_engine_hold does take an
  exclusive FileShare.None lock, but on its own $tmp\target.exe.

  That refutation is asserted below (check 3), because it is the load-bearing
  premise: if a runner ever does start writing the staged engine, parallelism
  becomes unsafe and this guard must go red.

  The quarantine IS the LSP proxy family, which is documented to have interfered
  with itself while strictly SERIALISED.
#>
[CmdletBinding()]
param(
  [string]$RepoRoot = "$PSScriptRoot\..\.."
)
$ErrorActionPreference = 'Stop'
$script:Failed = $false
function Check($n, $ok, $d = '') {
  $s = if ($ok) { 'PASS' } else { 'FAIL' }
  $c = if ($ok) { 'Green' } else { 'Red' }
  Write-Host ("  [{0}] {1} {2}" -f $s, $n, $d) -ForegroundColor $c
  if (-not $ok) { $script:Failed = $true }
}

$RepoRoot  = (Resolve-Path $RepoRoot).Path
$driver    = Join-Path $RepoRoot 'tests\run_battery.ps1'
$testsRoot = Join-Path $RepoRoot 'tests'
if (-not (Test-Path $driver)) { Write-Host "FATAL: no driver at $driver" -ForegroundColor Red; exit 2 }

$driverText = Get-Content -LiteralPath $driver -Raw

Write-Host ''
Write-Host 'The driver exposes -Jobs and defaults it to serial' -ForegroundColor Cyan
Check 'run_battery.ps1 declares [int]$Jobs' `
  ($driverText -match '\[int\]\$Jobs\s*=\s*1') `
  'must default to 1 -- the serial path is the reference every green claim is measured against'
Check 'the driver reads the dl:serial marker' `
  ($driverText -match 'dl:serial') ''

# The driver's own reader, quoted here so the two cannot drift apart silently.
function SerialReason([string]$path) {
  foreach ($ln in (Get-Content -LiteralPath $path -TotalCount 60 -ErrorAction SilentlyContinue)) {
    $m = [regex]::Match($ln, '^\s*#\s*dl:serial:\s*(.+?)\s*$')
    if ($m.Success) { return $m.Groups[1].Value }
  }
  return ''
}

# THIS FILE IS EXCLUDED FROM ITS OWN SCANS, and that is not a convenience.
# It is a guard ABOUT markers, so it necessarily quotes the marker syntax and the
# staged-engine patterns in its prose and its regexes. Included, it marks itself
# quarantined and reports itself as a writer -- which is exactly the "a text scan
# cannot tell code from prose" error it exists to pin. The positive control below
# plants a REAL unmarked runner, so excluding self does not weaken anything.
$selfPath = $MyInvocation.MyCommand.Path
$runners = @(Get-ChildItem -Path $testsRoot -Recurse -File -Filter 'run_*.ps1' |
             Where-Object { $_.FullName -ne $driver -and $_.FullName -ne $selfPath })
$marked = @()
foreach ($r in $runners) {
  $why = SerialReason $r.FullName
  if ($why -ne '') { $marked += [pscustomobject]@{ Path = $r.FullName; Why = $why } }
}
Write-Host ("  {0} runner(s) enumerated, {1} quarantined" -f $runners.Count, $marked.Count) -ForegroundColor DarkGray
foreach ($m in $marked) {
  Write-Host ("      {0}" -f (Split-Path $m.Path -Leaf)) -ForegroundColor DarkGray
}

Write-Host ''
Write-Host 'Every quarantined runner states a reason' -ForegroundColor Cyan
Check 'the quarantine is not empty' ($marked.Count -gt 0) `
  'an empty quarantine means the marker regex stopped matching, not that the hazard went away'
$vague = @($marked | Where-Object { $_.Why.Length -lt 20 })
Check 'no quarantine entry has a stub reason' ($vague.Count -eq 0) `
  ("vague: " + (($vague | ForEach-Object { Split-Path $_.Path -Leaf }) -join ', '))

Write-Host ''
Write-Host 'The LSP proxy family is quarantined -- it interfered even SERIALLY' -ForegroundColor Cyan
# Match the family by FILENAME. Matching on file CONTENT would sweep in
# run_flow_typeref_not_a_read.ps1, whose fixture merely quotes the identifier
# TLspProxyOptions in a Pascal sample -- a text scan reading prose as code,
# which is the same mistake that produced the phantom "eight writers".
$proxyFamily = @($runners | Where-Object { $_.Name -match 'lsp_proxy' })
Check 'the proxy family was found at all' ($proxyFamily.Count -gt 0) `
  "found $($proxyFamily.Count)"
$unmarkedProxy = @($proxyFamily | Where-Object { (SerialReason $_.FullName) -eq '' })
Check 'every lsp_proxy runner carries dl:serial' ($unmarkedProxy.Count -eq 0) `
  ("unmarked: " + (($unmarkedProxy | ForEach-Object { $_.Name }) -join ', '))

Write-Host ''
Write-Host 'PREMISE CHECK: no runner writes the shared staged engine' -ForegroundColor Cyan
# If this ever goes red, parallelism is no longer safe and the quarantine must
# grow. Deliberately checks for an INVOCATION or a write, not a mention: the
# phantom eight were all mentions.
$writers = @()
foreach ($r in $runners) {
  $raw = Get-Content -LiteralPath $r.FullName -Raw
  # strip <# block comments #>, trailing # line comments, and Write-Host lines
  $code = [regex]::Replace($raw, '(?s)<#.*?#>', ' ')
  $code = ($code -split "`n" | ForEach-Object {
             $ln = $_
             $h = $ln.IndexOf('#')
             if ($h -ge 0 -and (($ln.Substring(0, $h).ToCharArray() | Where-Object { $_ -eq "'" }).Count % 2 -eq 0)) {
               $ln = $ln.Substring(0, $h)
             }
             if ($ln -match 'Write-Host') { '' } else { $ln }
           }) -join "`n"
  # For the build-script check, ALSO strip quoted string literals. run_exe_freshness
  # builds the advice text 'run build\build_draglint_win64.bat' inside a $(if ...)
  # expression on an ordinary line -- a message, not an invocation. Naming the
  # build script in a string you print is precisely what the phantom eight did.
  $codeNoStr = [regex]::Replace($code, "'[^'`n]*'", ' ')
  $codeNoStr = [regex]::Replace($codeNoStr, '"[^"`n]*"', ' ')
  if ($codeNoStr -match 'build_draglint\w*\.bat') {
    $writers += ($r.Name + ' (invokes the build script)')
  }
  foreach ($ln in ($code -split "`n")) {
    if ($ln -match '(Copy-Item|Move-Item|robocopy|xcopy)' -and $ln -match 'dll-win64') {
      # dll-win64 as the FIRST path is a read (copying OUT of the staged tree)
      $paths = [regex]::Matches($ln, '"[^"]+"|\$\w[\w\\.$]*')
      if ($paths.Count -gt 0 -and $paths[0].Value -notmatch 'dll-win64') {
        $writers += ($r.Name + ' (writes into dll-win64)')
      }
    }
  }
}
Check 'zero runners stage or overwrite third_party\dll-win64' ($writers.Count -eq 0) `
  (($writers | Select-Object -Unique) -join '; ')

Write-Host ''
Write-Host 'Every writer of the SHARED engine rules dir is quarantined' -ForegroundColor Cyan
# THE CHECK ABOVE WAS NOT ENOUGH, and this one exists because the A/B said so.
# "No runner writes the staged exe" is true, and three runners nonetheless
# re-stage <exeDir>\rules -- the catalogue every other runner READS. That is a
# genuine write to shared state that the dll-win64 question simply did not ask
# about, and it cost a real red: run_store_tests failed its circular-uses case
# under -Jobs 8 while passing serially.
#
# So this asserts CONTAINMENT (they carry the marker), not absence. Deleting the
# staging would be wrong -- these runners need it when invoked standalone.
$ruleWriters = @()
foreach ($r in $runners) {
  $raw  = Get-Content -LiteralPath $r.FullName -Raw
  $code = [regex]::Replace($raw, '(?s)<#.*?#>', ' ')
  foreach ($ln in ($code -split "`n")) {
    if ($ln -match '^\s*#') { continue }
    if ($ln -match '(Copy-Item|New-Item|Remove-Item|Out-File|Set-Content)' -and
        $ln -match '\$rulesDst') {
      $ruleWriters += $r
      break
    }
  }
}
$unquarantined = @($ruleWriters | Where-Object { (SerialReason $_.FullName) -eq '' })
Check 'the rules-writer set was found at all' ($ruleWriters.Count -gt 0) `
  "found $($ruleWriters.Count)"
Check 'every rules-writer carries dl:serial' ($unquarantined.Count -eq 0) `
  ("unquarantined: " + (($unquarantined | ForEach-Object { $_.Name }) -join ', '))

Write-Host ''
Write-Host 'POSITIVE CONTROL -- a planted unmarked proxy runner makes this FAIL' -ForegroundColor Cyan
# Without this, every assertion above passes when the marker regex matches
# nothing at all.
$plant = Join-Path $testsRoot 'autotest\run_lsp_proxy_zz_guard_control.ps1'
$controlCaught = $false
try {
  Set-Content -LiteralPath $plant -Value "Write-Host 'control'`r`nexit 0" -Encoding Ascii
  $replanted = @(Get-ChildItem -Path $testsRoot -Recurse -File -Filter 'run_*.ps1' |
                 Where-Object { $_.Name -match 'lsp_proxy' })
  $stillUnmarked = @($replanted | Where-Object { (SerialReason $_.FullName) -eq '' })
  $controlCaught = ($stillUnmarked.Count -eq 1 -and $stillUnmarked[0].Name -eq 'run_lsp_proxy_zz_guard_control.ps1')
} finally {
  if (Test-Path $plant) { Remove-Item -LiteralPath $plant -Force }
}
Check 'an unmarked lsp_proxy runner is detected' $controlCaught `
  'if this passes vacuously the check above proves nothing'
Check 'the planted control was cleaned up' (-not (Test-Path $plant)) ''

Write-Host ''
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
