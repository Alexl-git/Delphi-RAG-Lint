# run_v156_FA2.ps1 -- v156 lane FA-2: taint through exceptions (DRagLint.V156.TAINTEXC) over
# tests\lint-project\taintexc\ (real extractor rows; built-in catalogue: ParamStr -> .SQL.Text).
# A tainted value raised in one routine and caught `on E: T` in a caller that writes it to a sink
# is ONE taint-sql-injection finding at the handler's sink. Asserts the positives by marker line
# (same class, two call hops, a descendant class, a tainted parameter, through a local), the
# negatives (another class, a raise the handler cannot reach, a sanitised or literal raise, no
# sink) and the POSITIVE CONTROL: the direct path ParamStr -> .SQL.Text still fires, so a run that
# reports nothing at all cannot pass.
# Usage: pwsh -File tests\autotest\run_v156_FA2.ps1 [-Exe <drag-lint.exe>]
param([string]$Exe = '')
$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
if ($Exe -eq '') {
  $Exe = Join-Path $repo 'src\cli\Win64\Debug\drag-lint.exe'
  if (-not (Test-Path $Exe)) { $Exe = Join-Path $repo 'third_party\dll-win64\drag-lint.exe' }
}
$exePath = (Resolve-Path $Exe).Path
$fx   = Join-Path $repo 'tests\lint-project\taintexc'
$src  = [IO.File]::ReadAllLines((Join-Path $fx 'uTaintExc.pas'))
$tmp  = Join-Path $env:TEMP "v156fa2_$PID"
[void][IO.Directory]::CreateDirectory($tmp)
$db   = Join-Path $tmp 'fx.sqlite'
$rule = 'taint-sql-injection'
$fail = 0
function Check([string]$Name, [bool]$Ok, [string]$Detail = '') {
  if ($Ok) { Write-Host "PASS  $Name" } else { Write-Host "FAIL  $Name  $Detail"; $script:fail++ }
}
function LineOf([string]$Marker) {
  for ($i = 0; $i -lt $src.Length; $i++) { if ($src[$i].Contains("{ $Marker }")) { return $i + 1 } }
  throw "marker $Marker not in the fixture"
}
function Findings([string[]]$CliArgs) {
  $raw = & { $ErrorActionPreference = 'Continue'; & $exePath @CliArgs 2>$null }
  $txt = ($raw -join "`n"); $b = $txt.IndexOf('[')
  $all = @(); if ($b -ge 0) { try { $all = @(($txt.Substring($b) | ConvertFrom-Json | ForEach-Object { $_ }) | ForEach-Object { $_ }) } catch { $all = @() } }
  return ,@($all | Where-Object { $_.rule -like 'taint-*' })
}
function At($L, [int]$Line) { return ,@($L | Where-Object { $_.rule -eq $rule -and $_.start_line -eq $Line }) }
Push-Location $env:TEMP
try {
  & { $ErrorActionPreference = 'Continue'; & $exePath index $fx --db $db 2>&1 | ForEach-Object { "$_" } } | Out-Null
  $all = Findings @('lint-all', '--db', $db, '--json', '--quiet')
  $all | ForEach-Object { Write-Host ("  {0} {1} [{2}] {3}" -f $_.rule, $_.start_line, $_.severity, $_.message) }
  # positive control first: the ordinary walk is alive on this DB
  $ctl = At $all (LineOf 'M-CONTROL')
  Check 'POSITIVE CONTROL: the direct path ParamStr -> .SQL.Text fires' ($ctl.Count -eq 1) "got $($ctl.Count)"
  if ($ctl.Count -eq 1) { Check 'the control is an ordinary finding, not an exception one' ($ctl[0].message -notmatch 'through exception') $ctl[0].message }
  $pos = @(
    @('M-POS-SAME',     'ETaint',      'RaiseTainted'),   # on E: ETaint, raised by the callee
    @('M-POS-HOPS',     'ETaint',      'RaiseTainted'),   # two call hops below the handler
    @('M-POS-ANCESTOR', 'ETaintChild', 'RaiseChild'),     # on E: ETaint catches ETaintChild
    @('M-POS-PARAM',    'EParam',      'RaiseParam'),     # the raised value is the callee's parameter
    @('M-POS-LOCAL',    'ETaint',      'RaiseTainted')    # E.Message through a local to the sink
  )
  foreach ($p in $pos) {
    $h = At $all (LineOf $p[0])
    Check "positive $($p[0])" ($h.Count -eq 1) "got $($h.Count)"
    if ($h.Count -eq 1) {
      Check "$($p[0]) names the exception path" ($h[0].message -match "^Tainted data reaches Text through exception $($p[1]): raised in $($p[2]) ") $h[0].message
      Check "$($p[0]) severity error" ($h[0].severity -eq 'error') "got $($h[0].severity)"
    }
  }
  foreach ($m in 'M-NEG-CLASS', 'M-NEG-UNREACHABLE', 'M-NEG-SANITISED', 'M-NEG-LITERAL', 'M-NEG-NOSINK') {
    $ln = LineOf $m
    Check "negative $m" (@($all | Where-Object { $_.start_line -eq $ln }).Count -eq 0) 'a finding fired'
  }
  $raiseLines = @((LineOf 'M-RAISE'), (LineOf 'M-RAISE-CHILD'), (LineOf 'M-RAISE-PARAM'))
  Check 'no taint finding at a raise site' (@($all | Where-Object { $_.start_line -in $raiseLines }).Count -eq 0) 'the inner walk leaked a finding'
  Check 'exactly the five positives and the control' ($all.Count -eq 6) "got $($all.Count)"
} finally { Pop-Location }
Write-Host ("v156 FA-2: {0} failure(s)" -f $fail)
exit $fail
