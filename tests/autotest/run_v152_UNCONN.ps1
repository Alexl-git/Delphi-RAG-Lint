# v152 lane UNCONN -- unconnected-control and hanging-handler (ruling B2, plan D7 / D12).
#
# What it pins:
#   1. both ids are in `rules --json`, default ON, severity warning, category dead-code.
#   2. single-unit fixtures (tests\lint\unconnected-control.* / hanging-handler.*): every
#      HIT line fires and every silent twin stays silent (no index: own-unit evidence).
#   3. cross-unit fixture (tests\lint\unconnected-control.xunit, indexed into a scratch DB):
#      a control referenced only from another unit, a handler bound only in a descendant's
#      .dfm and a handler assigned only in another unit are SILENT with --db, while the
#      dead control and the dead handler still fire; an `inherited` node of a dead control
#      in the descendant form is not reported twice.
#   4. positive control for 3: the same lint WITHOUT the index reports the three
#      index-only cases -- so it is the index evidence that silences them, not a blind spot.
param(
  [string]$Exe = "src\cli\Win64\Debug\drag-lint.exe",
  [string]$Repo = ""
)
$ErrorActionPreference = "Stop"
$repo = if ($Repo -ne "") { (Resolve-Path $Repo).Path } else { (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path }
Set-Location $repo
[Environment]::CurrentDirectory = $repo
$exe = (Resolve-Path $Exe).Path
$pass = 0; $fail = 0
function Assert($name, $cond) {
  if ($cond) { $script:pass++; Write-Host "PASS  $name" } else { $script:fail++; Write-Host "FAIL  $name" }
}
function LineOf($path, $regex) {
  $m = Select-String -Path $path -Pattern $regex | Select-Object -First 1
  if ($null -eq $m) { throw "fixture line not found: $regex in $path" }
  return $m.LineNumber
}
function Findings($file, $rule, [string]$db = "") {
  $cmd = @('lint', $file, '--rule', $rule, '--json')
  if ($db -ne "") { $cmd += @('--db', $db) }
  $raw = & { $ErrorActionPreference = 'Continue'; & $exe @cmd 2>$null }
  $arr = @()
  try { $arr = @(($raw | ConvertFrom-Json | ForEach-Object { $_ }) | ForEach-Object { $_ }) } catch { $arr = @() }
  return @($arr | Where-Object { $_ -ne $null -and $_.rule -eq $rule })
}
function HasLine($f, $line) { return @($f | Where-Object { $_.start_line -eq $line }).Count -gt 0 }

# --- 1. catalog ---
$rules = & { $ErrorActionPreference = 'Continue'; & $exe rules --json 2>$null } | ConvertFrom-Json | ForEach-Object { $_ }
$all = if ($rules.rules) { $rules.rules } else { $rules }
foreach ($id in 'unconnected-control', 'hanging-handler') {
  $r = @($all | Where-Object { $_.id -eq $id })
  Assert "catalog has $id" ($r.Count -eq 1)
  if ($r.Count -eq 1) {
    Assert "$id default ON" ($r[0].default_enabled -eq $true)
    Assert "$id severity warning" ($r[0].default_severity -eq 'warning')
  }
}

# --- 2. single-unit fixtures (text evidence) ---
$uc = Join-Path $repo 'tests\lint\unconnected-control.pas'
$f = @(Findings $uc 'unconnected-control')
foreach ($n in 'btnUcDead', 'chkUcDead', 'edtUcDead', 'bbUcDead', 'mnuUcDead') {
  Assert "uc hit $n" (HasLine $f (LineOf $uc "^\s+$n\s*:"))
}
foreach ($n in 'btnUcBound', 'btnUcAction', 'btnUcModal', 'btnUcCode', 'chkUcRead', 'edtUcLinked', 'edtUcFind', 'lblUcText', 'bbUcClose', 'mnuUcFile', 'mnuUcSep', 'mnuUcOpen') {
  Assert "uc twin $n silent" (-not (HasLine $f (LineOf $uc "^\s+$n\s*:")))
}
Assert "uc exactly 5 findings" ($f.Count -eq 5)
$hh = Join-Path $repo 'tests\lint\hanging-handler.pas'
$f = @(Findings $hh 'hanging-handler')
foreach ($n in 'hhUnboundClick', 'hhOrphanKeyPress') {
  Assert "hh hit $n" (HasLine $f (LineOf $hh "^procedure THhForm\.$n\b"))
}
foreach ($n in 'btnHhBoundClick', 'hhAssignedClick', 'hhCalledClick', 'edtHhExitExit', 'FormCreate', 'DoHhWork') {
  Assert "hh twin $n silent" (-not (HasLine $f (LineOf $hh "^procedure THhForm\.$n\b")))
}
Assert "hh exactly 2 findings" ($f.Count -eq 2)

# --- 3. cross-unit fixture with an index ---
$work = Join-Path ([IO.Path]::GetTempPath()) ("dl-v152-unconn-" + [Guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Path $work | Out-Null
Copy-Item (Join-Path $repo 'tests\lint\unconnected-control.xunit\*') $work
$db = Join-Path $work 'xu.sqlite'
& { $ErrorActionPreference = 'Continue'; & $exe index $work --db $db 2>&1 | ForEach-Object { "$_" } } | Out-Null
Assert "cross-unit index built" (Test-Path $db)
$base = Join-Path $work 'XuBase.pas'
$child = Join-Path $work 'XuChild.pas'
$fu = @(Findings $base 'unconnected-control' $db)
$fh = @(Findings $base 'hanging-handler' $db)
Assert "xu hit btnXuDead (index)" (HasLine $fu (LineOf $base '^\s+btnXuDead\s*:'))
Assert "xu twin btnXuBound silent (index)" (-not (HasLine $fu (LineOf $base '^\s+btnXuBound\s*:')))
Assert "xu btnXuRemote silent: referenced from XuUser (index)" (-not (HasLine $fu (LineOf $base '^\s+btnXuRemote\s*:')))
Assert "xu hit xuDeadHandler (index)" (HasLine $fh (LineOf $base '^procedure TXuBase\.xuDeadHandler\b'))
Assert "xu xuChildBound silent: bound in XuChild.dfm (index)" (-not (HasLine $fh (LineOf $base '^procedure TXuBase\.xuChildBound\b')))
Assert "xu xuRemoteAssigned silent: assigned in XuUser (index)" (-not (HasLine $fh (LineOf $base '^procedure TXuBase\.xuRemoteAssigned\b')))
Assert "xu twin btnXuBoundClick silent (index)" (-not (HasLine $fh (LineOf $base '^procedure TXuBase\.btnXuBoundClick\b')))
$fc = @(Findings $child 'unconnected-control' $db)
Assert "xu child: inherited btnXuDead not reported again, btnXuChild bound" ($fc.Count -eq 0)

# --- 4. positive control: the same unit without the index ---
$nu = @(Findings $base 'unconnected-control')
$nh = @(Findings $base 'hanging-handler')
Assert "control: btnXuRemote fires without the index" (HasLine $nu (LineOf $base '^\s+btnXuRemote\s*:'))
Assert "control: xuChildBound fires without the index" (HasLine $nh (LineOf $base '^procedure TXuBase\.xuChildBound\b'))
Assert "control: xuRemoteAssigned fires without the index" (HasLine $nh (LineOf $base '^procedure TXuBase\.xuRemoteAssigned\b'))

Write-Host ""
Write-Host "run_v152_UNCONN: $pass pass / $fail fail"
if ($fail -gt 0) { exit 1 }
exit 0
