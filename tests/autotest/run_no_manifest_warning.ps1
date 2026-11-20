<#
  run_no_manifest_warning.ps1 -- pins the 1.52.2 no-config warning (backlog 2026-11-19: "warn
  when no drag-lint.json / library DB beside the exe (rules silently 0)").

  An engine with no drag-lint.json beside it, none in %APPDATA%\drag-lint, no DRAGLINT_MANIFEST
  and no .drag-lint.json above the working directory runs on defaults: no library index, so the
  rules that need library types report nothing and nothing said so. Now one stderr warning names
  every place it looked.

    A  bare engine copy, cwd outside any config tree -> ONE warning naming the exe-side path
       and the working directory the upward walk started from
    B  --quiet -> no warning
    C  control: drag-lint.json beside the engine -> no warning
#>
param([string]$Exe = '', [string]$Scratch = '', [switch]$KeepWorkDir)

$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\lib\WorkDirCleanup.ps1"
$repo = (Resolve-Path "$PSScriptRoot\..\..").Path
if ($Exe -eq '') { $Exe = Join-Path $repo 'third_party\dll-win64\drag-lint.exe' }
if ($Scratch -eq '') { $Scratch = Join-Path ([IO.Path]::GetTempPath()) "no_manifest_guard_$PID" }
$engDir = Join-Path $Scratch 'engine'
$cwd = Join-Path $Scratch 'work'
$appData = Join-Path $Scratch 'appdata'
foreach ($d in $engDir, $cwd, $appData) { [void][IO.Directory]::CreateDirectory($d) }
foreach ($f in Get-ChildItem (Split-Path $Exe -Parent) -File | Where-Object { $_.Extension -in '.exe', '.dll' }) {
  [IO.File]::Copy($f.FullName, (Join-Path $engDir $f.Name), $true)
}
$eng = Join-Path $engDir 'drag-lint.exe'

$fails = 0; $passes = 0
function Check([string]$Name, [bool]$Ok, [string]$Detail = '') {
  if ($Ok) { $script:passes++; "PASS $Name" }
  else { $script:fails++; "FAIL $Name $Detail" }
}

function Invoke-Engine([string[]]$EngArgs) {
  $psi = New-Object Diagnostics.ProcessStartInfo $eng
  foreach ($a in $EngArgs) { $psi.ArgumentList.Add($a) }
  $psi.WorkingDirectory = $cwd
  $psi.UseShellExecute = $false; $psi.RedirectStandardError = $true; $psi.RedirectStandardOutput = $true
  $psi.Environment['APPDATA'] = $appData
  [void]$psi.Environment.Remove('DRAGLINT_MANIFEST')
  $p = [Diagnostics.Process]::Start($psi)
  $outTask = $p.StandardOutput.ReadToEndAsync(); $err = $p.StandardError.ReadToEnd()
  $p.WaitForExit(); [void]$outTask.Result
  return $err
}

$warnRe = 'no drag-lint\.json found'
if ($cwd -like 'C:\Projects*') { "SKIP: scratch is under C:\Projects (a .drag-lint.json may be above it)"; exit 0 }

$err = Invoke-Engine @('resolve-dbs', '--platform', 'win32')
Check 'A1 warns once without any config' (([regex]::Matches($err, $warnRe)).Count -eq 1) $err
Check 'A2 names the exe-side manifest path' ($err.Contains((Join-Path $engDir 'drag-lint.json'))) $err
Check 'A3 names where the .drag-lint.json walk started' ($err.Contains($cwd)) $err

$err = Invoke-Engine @('resolve-dbs', '--platform', 'win32', '--quiet')
Check 'B1 --quiet: no warning' ($err -notmatch $warnRe) $err

[IO.File]::WriteAllText((Join-Path $engDir 'drag-lint.json'), '{ "indexes": { "sections": [] } }')
$err = Invoke-Engine @('resolve-dbs', '--platform', 'win32')
Check 'C1 control: a manifest beside the engine silences it' ($err -notmatch $warnRe) $err

Remove-WorkDir $Scratch -Keep:$KeepWorkDir
"run_no_manifest_warning: $passes passed, $fails failed"
if ($fails -gt 0) { exit 1 }
exit 0
