# run_v156_FIXTAINT.ps1 -- v156 lane FIX-TAINT (Lint.TaintRules.pas + rules\taint-*.json):
#   V1 a VALUE row (val_class int ...) is not a taint carrier: Length(<tainted>) / IntToStr(N) reaching a
#      path / command sink gives no finding (RowsOf drops ValClass <> '').
#   V2 the sink row's own CWE prints: XPath rows CWE-643, LDAP rows CWE-90 (not the rule's CWE-78).
#   V3 an untyped sink that the project declares `external` is still the catalogued API (fires); a project
#      METHOD of the same name is project code (does not fire).
#   V4 the exception hook sees the run's merged config: --config {"taint":{"disable":["paramstr"]}} -> no
#      exception finding either.
#   V5 a site reached directly AND through an exception is ONE finding; an exception object at a handler
#      sink is not a source by itself (EvalRows has no except branch).
#   V6 TFDQuery.Open(concatenated SQL) gives the SQL rule only, no taint-path-traversal.
# POSITIVE CONTROL: DeleteFile(GetEnvironmentVariable('X')) still fires taint-path-traversal.
# Fixtures: tests\fixtures\v156-fixtaint, tests\lint-project\taint156b, tests\lint-project\taintexc.
# Usage: pwsh -File tests\autotest\run_v156_FIXTAINT.ps1 [-Exe <drag-lint.exe>]   (rules\ beside the exe)
param([string]$Exe = '')
$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
if ($Exe -eq '') {
  $Exe = Join-Path $repo 'src\cli\Win64\Debug\drag-lint.exe'
  if (-not (Test-Path $Exe)) { $Exe = Join-Path $repo 'third_party\dll-win64\drag-lint.exe' }
}
$exePath = (Resolve-Path $Exe).Path
$fx   = Join-Path $repo 'tests\fixtures\v156-fixtaint'
$src  = [IO.File]::ReadAllLines((Join-Path $fx 'uFixTaint.pas'))
$tmp  = Join-Path $env:TEMP "v156fixtaint_$PID"
[void][IO.Directory]::CreateDirectory($tmp)
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
function AtLine($L, [int]$Line) { return ,@($L | Where-Object { $_.start_line -eq $Line }) }
function Idx([string]$Dir, [string]$Name) {
  $db = Join-Path $tmp "$Name.sqlite"
  & { $ErrorActionPreference = 'Continue'; & $exePath index $Dir --db $db 2>&1 | ForEach-Object { "$_" } } | Out-Null
  return $db
}
Push-Location $env:TEMP
try {
  $db = Idx $fx 'fx'
  $all = Findings @('lint-all', '--db', $db, '--json', '--quiet')
  $all | ForEach-Object { Write-Host ("  {0} {1} {2}" -f $_.rule, $_.start_line, $_.message) }
  $ctl = AtLine $all (LineOf 'STRPATH')
  Check 'POSITIVE CONTROL: a string path (GetEnvironmentVariable -> DeleteFile) still fires taint-path-traversal' (($ctl.Count -eq 1) -and ($ctl[0].rule -eq 'taint-path-traversal')) "got $($ctl.Count)"
  foreach ($m in 'INTVAL', 'LENPATH', 'LENCMD') {
    Check "V1 value row gives no finding ($m)" ((AtLine $all (LineOf $m)).Count -eq 0) 'a finding fired'
  }
  $e = AtLine $all (LineOf 'EXTSINK')
  Check 'V3 project `external` WinExec import is the catalogued sink' (($e.Count -eq 1) -and ($e[0].rule -eq 'taint-command-injection')) "got $($e.Count)"
  Check 'V3 control: a project METHOD named WinExec is project code, no finding' ((AtLine $all (LineOf 'PRJSINK')).Count -eq 0) 'fired'
  $o = AtLine $all (LineOf 'OPENSQL')
  Check 'V6 TFDQuery.Open(concatenated SQL) = the SQL rule only' (($o.Count -eq 1) -and ($o[0].rule -eq 'taint-sql-injection')) "got $($o.Count): $($o.rule -join ',')"
  Check 'V6 constant SQL: no finding' ((AtLine $all (LineOf 'OPENCONST')).Count -eq 0) 'fired'
  Check 'V5 an exception object at a handler sink is no source of its own' ((AtLine $all (LineOf 'HANDLER')).Count -eq 0) 'fired'
  $d = AtLine $all (LineOf 'DUP')
  Check 'V5 a site reached directly AND through an exception = ONE finding' ($d.Count -eq 1) "got $($d.Count)"
  Check 'V5 the merged finding keeps both paths' (($d.Count -eq 1) -and (@($d[0].paths).Count -ge 2)) "paths=$(@($d[0].paths).Count)"

  # V2 the row's own CWE
  $dbB = Idx (Join-Path $repo 'tests\lint-project\taint156b') 'b'
  $b = Findings @('lint-all', '--db', $dbB, '--json', '--quiet')
  $x = @($b | Where-Object { $_.message -match 'selectNodes' })
  $l = @($b | Where-Object { $_.message -match 'ldap_search_s' })
  Check 'V2 XPath row prints CWE-643' (($x.Count -ge 1) -and ($x[0].message -match 'CWE-643')) ($x | ForEach-Object { $_.message })
  Check 'V2 LDAP row prints CWE-90' (($l.Count -ge 1) -and ($l[0].message -match 'CWE-90')) ($l | ForEach-Object { $_.message })

  # V4 config reaches the exception hook
  $dbE = Idx (Join-Path $repo 'tests\lint-project\taintexc') 'e'
  $plain = Findings @('lint-all', '--db', $dbE, '--json', '--quiet')
  Check 'V4 control: the exception fixture has taint findings without a config' ($plain.Count -ge 5) "got $($plain.Count)"
  $cfg = Join-Path $tmp 'off.json'
  [IO.File]::WriteAllText($cfg, '{"taint":{"disable":["paramstr"]}}')
  $off = Findings @('lint-all', '--db', $dbE, '--json', '--quiet', '--config', $cfg)
  Check 'V4 "disable": ["paramstr"] silences exception paths too' ($off.Count -eq 0) "got $($off.Count)"
}
finally {
  Pop-Location
  try { [IO.Directory]::Delete($tmp, $true) } catch { }
}
if ($fail -gt 0) { Write-Host "FAIL: $fail check(s)"; exit 1 }
Write-Host 'run_v156_FIXTAINT: all checks passed'
