# run_v156_TAINT2.ps1 -- v156 lane TAINT-2 (Q9 + G-14 catalogue rows): the BUILT-IN rows of
# rules\taint-*.json (no --config) must fire for XPath / LDAP sinks (rule taint-command-injection, no new id)
# and for the three G-14 ids taint-deserialization / taint-html-output / taint-log.
# Fixture tests\lint-project\taint156b\ (sources: ParamStr(1), GetEnvironmentVariable; sinks: selectNodes,
# ldap_search_s, ADsOpenObject, TJson.JsonToObject, TWebResponse.Content :=, TLogLogger.Info).
# Positives by rule+line, negatives (literal, encoded), taint-log OFF by default, ON with --enable.
# Usage: pwsh -File tests\autotest\run_v156_TAINT2.ps1 [-Exe <drag-lint.exe>]   (rules\ must sit beside the exe)
param([string]$Exe = '')
$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
if ($Exe -eq '') { $Exe = Join-Path $repo 'third_party\dll-win64\drag-lint.exe' }
$exePath = (Resolve-Path $Exe).Path
$fx  = Join-Path $repo 'tests\lint-project\taint156b'
$src = Join-Path $fx 'uTaint156b.pas'
$tmp = Join-Path $env:TEMP "taint156b_$PID"
[void][IO.Directory]::CreateDirectory($tmp)
$db  = Join-Path $tmp 'fx.sqlite'
$fail = 0
function Check([string]$Name, [bool]$Ok, [string]$Detail = '') {
  if ($Ok) { Write-Host "PASS  $Name" } else { Write-Host "FAIL  $Name  $Detail"; $script:fail++ }
}
function LineOf([string]$Needle) {
  $i = 0
  foreach ($l in [IO.File]::ReadAllLines($src)) { $i++; if ($l.Contains($Needle)) { return $i } }
  throw "marker not found: $Needle"
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
  $all = Findings ($common + @('--enable', 'taint-log'))
  $all | ForEach-Object { Write-Host ("  {0} {1} [{2}] {3}" -f $_.rule, $_.start_line, $_.severity, $_.message) }
  $pos = @(
    @('taint-command-injection', (LineOf "N.selectNodes('//user[@name=' + ParamStr"), 'XPath selectNodes'),
    @('taint-command-injection', (LineOf "S.selectNode('//user"), 'XPath IDOMNodeSelect.selectNode'),
    @('taint-command-injection', (LineOf "ldap_search_s(nil, 'dc=x', 2, '(uid=' +"), 'LDAP ldap_search_s filter'),
    @('taint-command-injection', (LineOf "ADsOpenObject('LDAP://' +"), 'ADSI ADsOpenObject path'),
    @('taint-deserialization',   (LineOf "TJson.JsonToObject(GetEnvironmentVariable"), 'TJson.JsonToObject'),
    @('taint-html-output',       (LineOf "R.Content:= '<p>' + GetEnvironmentVariable"), 'TWebResponse.Content'),
    @('taint-log',               (LineOf "L.Info('user ' + GetEnvironmentVariable"), 'TLogLogger.Info')
  )
  foreach ($p in $pos) {
    $h = At $all $p[0] $p[1]
    Check "positive $($p[2]) ($($p[0]) line $($p[1]))" ($h.Count -eq 1) "got $($h.Count)"
  }
  foreach ($n in "selectNodes('//user[@name=''admin'']')", "'(uid=admin)'", "JsonToObject('{}')", "'<p>hello</p>'",
                 'HTMLEscape(GetEnvironmentVariable', 'HTTPEncode(GetEnvironmentVariable', "L.Info('user logged in')") {
    $ln = LineOf $n
    Check "negative line $ln ($n)" (@($all | Where-Object { $_.start_line -eq $ln }).Count -eq 0) 'a finding fired'
  }
  Check 'exactly the seven positives' ($all.Count -eq 7) "got $($all.Count)"
  $def = Findings $common
  Check 'taint-log is OFF by default' (@($def | Where-Object { $_.rule -eq 'taint-log' }).Count -eq 0) 'fired without --enable'
  Check 'default run keeps the six ON findings' ($def.Count -eq 6) "got $($def.Count)"
} finally { Pop-Location }
Write-Host ("v156 TAINT-2: {0} failure(s)" -f $fail)
exit $fail
