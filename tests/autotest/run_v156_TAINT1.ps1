# run_v156_TAINT1.ps1 -- v156 lane TAINT-1 (G-14): taint-deserialization, taint-html-output, taint-log
# over tests\lint-project\taint156\ (real extractor rows; sources/sinks/sanitizers from taint156.config.json
# so the test does not depend on the rules\taint-*.json rows owned by TAINT-2).
# Asserts positives by rule+line, negatives (literal, sanitised, wrong-category sanitiser), taint-log OFF by
# default and ON with --enable, and a positive control (no sources -> 0 findings).
# Usage: pwsh -File tests\autotest\run_v156_TAINT1.ps1 [-Exe <drag-lint.exe>]
param([string]$Exe = '')
$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
if ($Exe -eq '') { $Exe = Join-Path $repo 'third_party\dll-win64\drag-lint.exe' }
$exePath = (Resolve-Path $Exe).Path
$fx  = Join-Path $repo 'tests\lint-project\taint156'
$cfg = Join-Path $fx 'taint156.config.json'
$tmp = Join-Path $env:TEMP "taint156_$PID"
[void][IO.Directory]::CreateDirectory($tmp)
$db  = Join-Path $tmp 'fx.sqlite'
$noSrc = Join-Path $tmp 'nosrc.json'
[IO.File]::WriteAllText($noSrc, '{"taint":{"sources":[],"sinks":[{"id":"t156-deser","rule":"taint-deserialization","name":"ReadComponentText","kind":"call","args":[0]}]}}')
$fail = 0
function Check([string]$Name, [bool]$Ok, [string]$Detail = '') {
  if ($Ok) { Write-Host "PASS  $Name" } else { Write-Host "FAIL  $Name  $Detail"; $script:fail++ }
}
function Findings([string[]]$CliArgs) {
  $raw = & { $ErrorActionPreference = 'Continue'; & $exePath @CliArgs 2>$null }
  $txt = ($raw -join "`n"); $b = $txt.IndexOf('[')
  $all = @(); if ($b -ge 0) { try { $all = @(($txt.Substring($b) | ConvertFrom-Json | ForEach-Object { $_ }) | ForEach-Object { $_ }) } catch { $all = @() } }
  return ,@($all | Where-Object { $_.rule -like 'taint-*' })
}
function At($L, [string]$Rule, [int]$Line) { return ,@($L | Where-Object { $_.rule -eq $Rule -and $_.start_line -eq $Line }) }
Push-Location $env:TEMP
try {
  & { $ErrorActionPreference = 'Continue'; & $exePath index $fx --db $db 2>&1 | ForEach-Object { "$_" } } | Out-Null
  $common = @('lint-all', '--db', $db, '--json', '--quiet')
  $all = Findings ($common + @('--config', $cfg, '--enable', 'taint-log'))
  $all | ForEach-Object { Write-Host ("  {0} {1} [{2}] {3}" -f $_.rule, $_.start_line, $_.severity, $_.message) }
  $pos = @(
    @('taint-deserialization', 21, 'error'),   # Deser sink, reached from LoadBodyTwoHops (two hops)
    @('taint-deserialization', 26, 'error'),   # direct
    @('taint-html-output',     46, 'error'),   # request field into Response.Content
    @('taint-html-output',     56, 'error'),   # a LOG sanitiser does not stop the html rule
    @('taint-log',             66, 'warning')  # OFF by default, on under --enable
  )
  foreach ($p in $pos) {
    $h = At $all $p[0] $p[1]
    Check "positive $($p[0]) line $($p[1])" ($h.Count -eq 1) "got $($h.Count)"
    if ($h.Count -eq 1) { Check "severity $($p[0]) line $($p[1])" ($h[0].severity -eq $p[2]) "got $($h[0].severity)" }
  }
  foreach ($ln in 36, 41, 51, 61, 71, 76) {
    Check "negative line $ln (literal / sanitised)" (@($all | Where-Object { $_.start_line -eq $ln }).Count -eq 0) 'a finding fired'
  }
  Check 'exactly the five positives' ($all.Count -eq 5) "got $($all.Count)"
  $def = Findings ($common + @('--config', $cfg))
  Check 'taint-log is OFF by default' (@($def | Where-Object { $_.rule -eq 'taint-log' }).Count -eq 0) 'fired without --enable'
  Check 'default run keeps the two ON rules' ($def.Count -eq 4) "got $($def.Count)"
  $ctl = Findings ($common + @('--config', $noSrc))
  Check 'positive control: no sources -> 0 findings' ($ctl.Count -eq 0) "got $($ctl.Count)"
  $rl = (& { $ErrorActionPreference = 'Continue'; & $exePath rules --json 2>$null }) -join "`n"
  foreach ($id in 'taint-deserialization', 'taint-html-output', 'taint-log') { Check "rule listed: $id" ($rl -match $id) }
} finally { Pop-Location }
Write-Host ("v156 TAINT-1: {0} failure(s)" -f $fail)
exit $fail