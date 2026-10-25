<#
  run_cli_error_reason.ps1 -- every ambiguous CLI exit also says WHY (owner ruling 2026-10-25, A14).

  Exit codes stay (unknown verb 2, unknown flag 3, stale index 3); the reason tells a consumer
  (featuregen reading menu-tree) "flag too new for this engine" from "stale index".
    --json   : a JSON object on stderr {"error":"<reason>",...}; stdout stays empty
    no --json: a stderr line starting error[<reason>]:
  Reasons: unknown-verb, unknown-flag, stale-index.
  W6-misc: `ask` and `compare` exit 3 on a stale index too; each adds an error[stale-index]: line
  (compare --format json: the JSON object) after its own prose, which stays (ask-report: prefix).
  Positive control: a valid call (--version, menu-tree on a fresh index) exits 0 with no error object
  and no error[ token, so the matchers can fail.
#>
[CmdletBinding()]
param(
  [string]$Exe = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe",
  [string]$FixtureDir = "$PSScriptRoot\..\fixtures\menutree",
  [string]$WorkDir = "$env:TEMP\drag-lint-cli-error-reason-$PID"
)
$ErrorActionPreference = 'Stop'
$script:Failed = $false
function Check($n, $ok, $d = '') {
  $s = if ($ok) { 'PASS' } else { 'FAIL' }
  $c = if ($ok) { 'Green' } else { 'Red' }
  Write-Host ("  [{0}] {1} {2}" -f $s, $n, $d) -ForegroundColor $c
  if (-not $ok) { $script:Failed = $true }
}
# runs the exe, returns @{ Exit; Out; Err } with the streams kept apart
function Run($exeArgs) {
  $o = [IO.Path]::GetTempFileName(); $e = [IO.Path]::GetTempFileName()
  $p = Start-Process -FilePath $Exe -ArgumentList $exeArgs -NoNewWindow -Wait -PassThru -RedirectStandardOutput $o -RedirectStandardError $e
  $r = @{ Exit = $p.ExitCode; Out = [IO.File]::ReadAllText($o); Err = [IO.File]::ReadAllText($e) }
  [IO.File]::Delete($o); [IO.File]::Delete($e)
  return $r
}
function ErrObj($text) {
  # the first stderr line that parses as a JSON object with an "error" member
  foreach ($l in ($text -split "`r?`n")) {
    if ($l.StartsWith('{')) { try { $j = $l | ConvertFrom-Json; if ($j.error) { return $j } } catch { } }
  }
  return $null
}
if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
$Exe = (Resolve-Path $Exe).Path

# --- positive control: a valid call carries no reason ---
$r = Run @('--version')
Check 'control: --version exits 0, no error[ token, no error object' (($r.Exit -eq 0) -and ($r.Err -notmatch 'error\[') -and ($null -eq (ErrObj $r.Err))) "exit=$($r.Exit)"

# --- unknown verb: exit 2 ---
$r = Run @('nosuchverb-a14')
Check 'unknown verb, text: exit 2, error[unknown-verb]: first token' (($r.Exit -eq 2) -and ($r.Err -match '(?m)^error\[unknown-verb\]: .*nosuchverb-a14')) "exit=$($r.Exit)"
$r = Run @('nosuchverb-a14', '--json')
$j = ErrObj $r.Err
Check 'unknown verb, --json: exit 2, JSON error=unknown-verb verb=..., stdout empty' (($r.Exit -eq 2) -and ($null -ne $j) -and ($j.error -eq 'unknown-verb') -and ($j.verb -eq 'nosuchverb-a14') -and ($r.Out.Trim() -eq '')) "exit=$($r.Exit)"

# --- unknown flag: exit 3 ---
$r = Run @('cycles', '--no-such-flag-a14')
Check 'unknown flag, text: exit 3, error[unknown-flag]: first token' (($r.Exit -eq 3) -and ($r.Err -match '(?m)^error\[unknown-flag\]: .*--no-such-flag-a14')) "exit=$($r.Exit)"
$r = Run @('cycles', '--no-such-flag-a14', '--json')
$j = ErrObj $r.Err
Check 'unknown flag, --json: exit 3, JSON error=unknown-flag flag=..., stdout empty' (($r.Exit -eq 3) -and ($null -ne $j) -and ($j.error -eq 'unknown-flag') -and ($j.flag -eq '--no-such-flag-a14') -and ($r.Out.Trim() -eq '')) "exit=$($r.Exit)"

# --- stale index: exit 3 (menu-tree on a fixture touched after indexing) ---
if (Test-Path $WorkDir) { [IO.Directory]::Delete($WorkDir, $true) }
$null = New-Item -ItemType Directory $WorkDir
$fx = "$WorkDir\fx"
Copy-Item -LiteralPath (Resolve-Path $FixtureDir).Path -Destination $fx -Recurse
$proj = "$fx\MenuTreeFixture.dproj"; $db = "$WorkDir\fixture.sqlite"
$null = Run @('index', '--project', $proj, '--db', $db)
$r = Run @('menu-tree', '--project', $proj, '--db', $db, '--format', 'paths')
Check 'control: menu-tree on a fresh index exits 0, no reason' (($r.Exit -eq 0) -and ($r.Err -notmatch 'error\[') -and ($null -eq (ErrObj $r.Err))) "exit=$($r.Exit)"
[IO.File]::AppendAllText("$fx\MT.Builder.pas", "`r`n{ touched by run_cli_error_reason }", [Text.Encoding]::ASCII)
$r = Run @('menu-tree', '--project', $proj, '--db', $db, '--format', 'paths')
Check 'stale index, text: exit 3, error[stale-index]: first token' (($r.Exit -eq 3) -and ($r.Err -match '(?m)^error\[stale-index\]: ')) "exit=$($r.Exit)"
$r = Run @('menu-tree', '--project', $proj, '--db', $db, '--format', 'json', '--json')
$j = ErrObj $r.Err
Check 'stale index, --json: exit 3, JSON error=stale-index, stdout empty' (($r.Exit -eq 3) -and ($null -ne $j) -and ($j.error -eq 'stale-index') -and ($r.Out.Trim() -eq '')) "exit=$($r.Exit)"

# --- ask + compare on a stale index (W6-misc): exit 3 also carries error[stale-index] ---
# Fixture tests\fixtures\compare-verb (as run_compare_verb.ps1). DRAGLINT_ASK_REPORT names a missing
# script, so no PowerShell fallback can answer instead of the engine.
function RunEnv($exeArgs) {
  $psi = [Diagnostics.ProcessStartInfo]::new($Exe)
  foreach ($a in $exeArgs) { $psi.ArgumentList.Add($a) }
  $psi.RedirectStandardOutput = $true; $psi.RedirectStandardError = $true; $psi.UseShellExecute = $false
  $psi.Environment['DRAGLINT_ASK_REPORT'] = "$WorkDir\no-such-Ask-Report.ps1"
  $p = [Diagnostics.Process]::Start($psi)
  $o = $p.StandardOutput.ReadToEndAsync(); $e = $p.StandardError.ReadToEndAsync()
  $p.WaitForExit()
  return @{ Exit = $p.ExitCode; Out = $o.Result; Err = $e.Result }
}
$cv = "$WorkDir\cv"
$null = New-Item -ItemType Directory $cv
Copy-Item "$PSScriptRoot\..\fixtures\compare-verb\*" $cv
$cvProj = "$cv\Cmp.dproj"; $cvDb = "$WorkDir\cmp.sqlite"; $cvOld = "$WorkDir\old.txt"
$askArgs = @('ask', 'who-writes', '--target', 'Unit1.TFoo.FName', '--project', $cvProj, '--db', $cvDb, '--plain', '--out-root', "$WorkDir\bundles")
$null = RunEnv @('index', '--project', $cvProj, '--db', $cvDb)
$r = RunEnv $askArgs
Check 'control: ask on a fresh index exits 0, no error[ token' (($r.Exit -eq 0) -and ($r.Err -notmatch 'error\[') -and ($r.Out -match '(?m)^COMMAND who-writes ')) "exit=$($r.Exit) err=$($r.Err)"
[IO.File]::WriteAllText($cvOld, $r.Out, [Text.UTF8Encoding]::new($false))
$r = RunEnv @('compare', '--old', $cvOld, '--db', $cvDb)
Check 'control: compare on a fresh index exits 0, no error[ token' (($r.Exit -eq 0) -and ($r.Err -notmatch 'error\[')) "exit=$($r.Exit) err=$($r.Err)"
[IO.File]::AppendAllText("$cv\Unit1.pas", "`r`n{ touched by run_cli_error_reason }", [Text.Encoding]::ASCII)

$r = RunEnv $askArgs
Check 'ask stale, text: exit 3, an error[stale-index]: line' (($r.Exit -eq 3) -and ($r.Err -match '(?m)^error\[stale-index\]: ask: ')) "exit=$($r.Exit) err=$($r.Err)"
Check 'ask stale: the ask-report: prose still comes first (IDE prefix contract)' ($r.Err.StartsWith('ask-report: stale index')) $r.Err
Check 'ask stale: stdout stays empty' ($r.Out.Trim() -eq '') $r.Out

$r = RunEnv @('compare', '--old', $cvOld, '--db', $cvDb)
Check 'compare stale, text: exit 3, an error[stale-index]: line' (($r.Exit -eq 3) -and ($r.Err -match '(?m)^error\[stale-index\]: compare: ')) "exit=$($r.Exit) err=$($r.Err)"
$r = RunEnv @('compare', '--old', $cvOld, '--db', $cvDb, '--format', 'json')
$j = ErrObj $r.Err
$env1 = $null; try { $env1 = $r.Out | ConvertFrom-Json } catch { }
Check 'compare stale, --format json: exit 3, stderr JSON error=stale-index' (($r.Exit -eq 3) -and ($null -ne $j) -and ($j.error -eq 'stale-index')) "exit=$($r.Exit) err=$($r.Err)"
Check 'compare stale, --format json: the compare/1 envelope still parses on stdout' (($null -ne $env1) -and ($env1.exit_code -eq 3)) $r.Out

# negative control: a compare refusal that is NOT stale (exit 2) carries no stale reason
$r = RunEnv @('compare')
Check 'control: compare usage refusal (exit 2) has no error[stale-index]' (($r.Exit -eq 2) -and ($r.Err -notmatch 'stale-index')) "exit=$($r.Exit)"

if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
