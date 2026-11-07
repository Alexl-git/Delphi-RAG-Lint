# CH-ASK-UNTESTED (wave 146 rk): `ask` when Graphviz dot.exe cannot be found. The walk's last
# candidate is the shared default (machine specific), so "absent" is driven through the first
# step: $env:DRAGLINT_DOT naming a missing file, which the resolver reports instead of skipping.
# Contract pinned: exit 2 (setup), stderr names the step and the file, NO answer on stdout, NO
# bundle folder written. POSITIVE CONTROL: DRAGLINT_DOT naming a real dot.exe answers, exit 0.
# --open is NOT covered here: it shells out to the default browser (live proof owed, section C).
param([string] $Exe = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
      [string] $Dot = 'C:\Projects\GraphWiz\Graphviz-16.1.0-win64\bin\dot.exe')
$ErrorActionPreference = 'Stop'
$script:Failed = $false
function Check([string]$Name, [bool]$Ok, [string]$Detail='') {
  Write-Host ("  [{0}] {1} {2}" -f $(if ($Ok) {'PASS'} else {'FAIL'}), $Name, $Detail) -ForegroundColor $(if ($Ok) {'Green'} else {'Red'})
  if (-not $Ok) { $script:Failed = $true }
}
if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
$Exe = (Resolve-Path $Exe).Path
$work = Join-Path $env:TEMP ('draglint_ask_nodot_' + [guid]::NewGuid().ToString('N'))
try {
  New-Item -ItemType Directory $work | Out-Null
  Copy-Item "$PSScriptRoot\..\fixtures\compare-verb\*" $work -Recurse
  $proj = "$work\Cmp.dproj"; $db = "$work\cmp.sqlite"
  function RunAsk([string]$DotEnv, [string]$Out) {
    $psi = [Diagnostics.ProcessStartInfo]::new($Exe)
    foreach ($a in @('ask','who-writes','--target','Unit1.TFoo.FName','--project',$proj,'--db',$db,'--plain','--out-root',$Out)) { $psi.ArgumentList.Add($a) }
    $psi.RedirectStandardOutput = $true; $psi.RedirectStandardError = $true; $psi.UseShellExecute = $false
    $psi.Environment['DRAGLINT_ASK_REPORT'] = "$work\no-such-Ask-Report.ps1"   # no PowerShell fallback may answer
    $psi.Environment['DRAGLINT_DOT'] = $DotEnv
    $p = [Diagnostics.Process]::Start($psi)
    $o = $p.StandardOutput.ReadToEndAsync(); $e = $p.StandardError.ReadToEndAsync(); $p.WaitForExit()
    return @{ Exit = $p.ExitCode; Out = $o.Result; Err = $e.Result }
  }
  $psi = [Diagnostics.ProcessStartInfo]::new($Exe)
  foreach ($a in @('index','--project',$proj,'--db',$db)) { $psi.ArgumentList.Add($a) }
  $psi.RedirectStandardOutput = $true; $psi.RedirectStandardError = $true; $psi.UseShellExecute = $false
  $ip = [Diagnostics.Process]::Start($psi); $null = $ip.StandardOutput.ReadToEndAsync(); $null = $ip.StandardError.ReadToEndAsync(); $ip.WaitForExit()
  Check 'fixture indexed' (Test-Path $db)

  if (-not (Test-Path $Dot)) { Write-Host "  [SKIP] no dot.exe at $Dot : positive control cannot run" -ForegroundColor Yellow; $script:Failed = $true }
  $r = RunAsk $Dot "$work\ok"
  Check 'POSITIVE CONTROL: a real dot.exe answers, exit 0' (($r.Exit -eq 0) -and ($r.Out -match '(?m)^COMMAND who-writes ')) "exit=$($r.Exit) err=$($r.Err)"

  $r = RunAsk "$work\nope\dot.exe" "$work\bad"
  Check 'missing dot: exit 2 (setup)' ($r.Exit -eq 2) "exit=$($r.Exit)"
  Check 'missing dot: stderr names DRAGLINT_DOT and the file' (($r.Err -match 'Graphviz dot not found') -and ($r.Err -match 'DRAGLINT_DOT') -and ($r.Err -match 'nope')) $r.Err
  Check 'missing dot: no answer on stdout' ($r.Out -notmatch 'COMMAND who-writes')
  Check 'missing dot: no bundle written (an empty --out-root folder is tolerated)' (@(Get-ChildItem "$work\bad" -Recurse -File -ErrorAction SilentlyContinue).Count -eq 0) ((Get-ChildItem "$work\bad" -Recurse -ErrorAction SilentlyContinue | % FullName) -join ';')
} finally { if (Test-Path $work) { [IO.Directory]::Delete($work, $true) } }
if ($script:Failed) { Write-Host 'FAIL run_ask_no_graphviz' -ForegroundColor Red; exit 1 }
Write-Host 'PASS run_ask_no_graphviz' -ForegroundColor Green
