#Requires -Version 7.3
<#
  run_v156_GCPP.ps1 -- Copy Grid Columns, the IDE command (1.56 lane GCP-P), below the UI.

  PART 1  builds and runs tests\plugin\gridcopy\GridCopyCmdTests.dpr (the pure part of DragLint.Plugin.Cmd.GridCopy).
  PART 2  chains what a real engine printed for the fixture form (tests\fixtures\fieldrepo\gridcopy) through that
          model, the way the command does: `--list --json` -> views, `--list --from V --json` -> events,
          `--dry-run --json` -> plan -> the --select file -> `--select` run; then the written form is COMPILED with
          DevExpress and LOADED (GridCopyLoad.dpr) and the copied handler is looked for in its output.

  A missing engine exe or compiler is a FAIL here, never a skip. Exit 0 only when every check passes.

  Parameters:
    -Repo   repo root (default: two levels above this script)
    -Exe    engine to drive (default: <Repo>\src\cli\Win64\Debug\drag-lint.exe, with `repo copy-grid`)
#>
[CmdletBinding()]
param([string]$Repo = '',
      [string]$Exe = '')
if (-not $Repo) { $Repo = (Resolve-Path "$PSScriptRoot\..\..").Path }
if (-not $Exe) { $Exe = Join-Path $Repo 'src\cli\Win64\Debug\drag-lint.exe' }
$ErrorActionPreference = 'Stop'
Write-Host '== v156 GCP-P: Copy Grid Columns (IDE command, model level) ==' -ForegroundColor Cyan
$work = Join-Path $env:TEMP "drag-lint-v156-gcpp-$PID"
New-Item -ItemType Directory -Path $work -Force | Out-Null
$script:bad = 0
$script:n = 0
function Check($name, $ok, $detail = '') {
  $script:n++
  Write-Host ('[{0}] {1} {2}' -f $(if ($ok) { 'PASS' } else { 'FAIL' }), $name, $(if ($ok) { '' } else { $detail })) -ForegroundColor $(if ($ok) { 'Green' } else { 'Red' })
  if (-not $ok) { $script:bad++ }
}
function Wrap([string]$bat, [string]$log) {
  Start-Process cmd.exe -ArgumentList '/c', "`"$bat`"" -Wait -WindowStyle Hidden -RedirectStandardOutput $log -RedirectStandardError "$log.err"
}
try {
  # ---- PART 1 ----
  $out1 = Join-Path $work 'model'
  [IO.Directory]::CreateDirectory($out1) | Out-Null
  $bat = Join-Path $work 'b1.bat'
  [IO.File]::WriteAllText($bat, "@echo off`r`ncall `"$Repo\build\_build_plugin_gridcopy_tests_local.bat`" $out1`r`n")
  Wrap $bat (Join-Path $work 'b1.log')
  $built = Select-String -LiteralPath (Join-Path $work 'b1.log') -Pattern 'BUILD_EXITCODE=0' -Quiet
  Check 'P0 the model runner builds' $built ((Select-String -LiteralPath (Join-Path $work 'b1.log') -Pattern 'Error' | Select-Object -First 3) -join ' | ')
  $runner = Join-Path $out1 'GridCopyCmdTests.exe'
  if ($built) {
    $lines = & { $ErrorActionPreference = 'Continue'; & $runner 2>&1 | ForEach-Object { "$_" } } | ForEach-Object { "$_" }
    $sum = $lines | Where-Object { $_ -match '^Summary: pass=(\d+) fail=(\d+)' }
    $m = [regex]::Match("$sum", 'pass=(\d+) fail=(\d+)')
    Check 'P1 the model cases all pass' (($m.Success) -and ([int]$m.Groups[2].Value -eq 0) -and ([int]$m.Groups[1].Value -ge 25)) (($lines | Where-Object { $_ -match 'FAIL|EXC' }) -join ' | ')
  }

  # ---- PART 2 ----
  if (-not (Test-Path -LiteralPath $Exe)) { Check 'E0 engine present' $false "not found: $Exe" }
  elseif ($built) {
    $fix = Join-Path $Repo 'tests\fixtures\fieldrepo\gridcopy'
    $d = Join-Path $work 'form'
    [IO.Directory]::CreateDirectory($d) | Out-Null
    foreach ($f in 'uCopy.dfm', 'uCopy.pas', 'GridCopyLoad.dpr') { [IO.File]::Copy((Join-Path $fix $f), (Join-Path $d $f), $true) }
    $dfm = Join-Path $d 'uCopy.dfm'
    function Eng([string]$more) {
      $o = Join-Path $work 'o.txt'; $e = Join-Path $work 'e.txt'
      $p = Start-Process -FilePath $Exe -ArgumentList "repo copy-grid --project `"$(Join-Path $work 'none.dproj')`" $more" -Wait -PassThru -NoNewWindow -RedirectStandardOutput $o -RedirectStandardError $e; $null = $p.Handle
      @{ Code = $p.ExitCode; Out = (Get-Content -LiteralPath $o -Raw) }
    }
    # the command line the model builds, copied from the runner's own cases: `--dfm "x" --list --json`
    $r = Eng "--dfm `"$dfm`" --list --json"
    $f1 = Join-Path $work 'list.json'; [IO.File]::WriteAllText($f1, $r.Out)
    $t = (& { $ErrorActionPreference = 'Continue'; & $runner --list $f1 2>&1 | ForEach-Object { "$_" } } | ForEach-Object { "$_" }) -join "`n"
    Check 'E1 --list --json of the engine: the model reads the three views' (($r.Code -eq 0) -and ($t -match 'views: 3 ') -and ($t -match 'view tvMain TcxGridDBTableView 3') -and ($t -match 'view cvMain ')) "exit=$($r.Code) $t"
    $r = Eng "--dfm `"$dfm`" --list --from tvMain --json"
    [IO.File]::WriteAllText($f1, $r.Out)
    $t = (& { $ErrorActionPreference = 'Continue'; & $runner --list $f1 2>&1 | ForEach-Object { "$_" } } | ForEach-Object { "$_" }) -join "`n"
    Check 'E2 --list --from V --json: the model reads the events, view and column ones' (($r.Code -eq 0) -and ($t -match 'event tvMain OnCustomDrawCell tvMainCustomDrawCell False') -and ($t -match 'event \w+ OnGetDisplayText \w+ True')) "exit=$($r.Code) $t"
    $r = Eng "--dfm `"$dfm`" --from tvMain --to bvMain --dry-run --json"
    $f2 = Join-Path $work 'plan.json'; [IO.File]::WriteAllText($f2, $r.Out)
    $sel = Join-Path $work 'select.txt'
    $t = (& { $ErrorActionPreference = 'Continue'; & $runner --plan $f2 $sel 2>&1 | ForEach-Object { "$_" } } | ForEach-Object { "$_" }) -join "`n"
    $selText = if (Test-Path -LiteralPath $sel) { Get-Content -LiteralPath $sel -Raw } else { '' }
    Check 'E3 the dry run --json of the engine: the model reads the plan and writes its --select file' (($r.Code -eq 0) -and ($t -match 'plan: [0-9A-F]{16} \d+ changes, [1-9]\d* checked') -and ($selText -match '(?m)^# plan [0-9A-F]{16}\r?$')) "exit=$($r.Code) $t sel=[$selText]"
    $before = (Get-FileHash -LiteralPath $dfm).Hash
    $r = Eng "--dfm `"$dfm`" --from tvMain --to bvMain --select `"$sel`""
    $text = Get-Content -LiteralPath $dfm -Raw
    Check 'E4 the --select run writes exactly the form the model planned: new columns in the DFM, a backup beside it' (($r.Code -eq 0) -and ((Get-FileHash -LiteralPath $dfm).Hash -ne $before) -and ($text -match 'bvMainCODE: TcxGridDBBandedColumn') -and (@(Get-ChildItem -LiteralPath $d -Filter '*.before-write-dfm-*').Count -ge 1)) "exit=$($r.Code) out=[$($r.Out)]"
    # compile + load the written form
    $bat2 = Join-Path $work 'b2.bat'
    [IO.File]::WriteAllText($bat2, "@echo off`r`ncall `"$Repo\build\_build_fieldrepo_gridcopy_form_local.bat`" $d`r`n")
    Wrap $bat2 (Join-Path $work 'b2.log')
    $built2 = Select-String -LiteralPath (Join-Path $work 'b2.log') -Pattern 'BUILD_EXITCODE=0' -Quiet
    Check 'E5 the written form COMPILES with DevExpress' $built2 ((Select-String -LiteralPath (Join-Path $work 'b2.log') -Pattern 'Error' | Select-Object -First 3) -join ' | ')
    if ($built2) {
      $load = (& { $ErrorActionPreference = 'Continue'; & (Join-Path $d 'GridCopyLoad.exe') 2>&1 | ForEach-Object { "$_" } }) -join "`n"
      Check 'E6 the written form LOADS: the copied column exists on the banded view' (($load -match 'bvMainCODE\|TcxGridDBBandedColumn') -and ($load -notmatch 'Exception|EReadError')) $load
    }
    # one event, column event: the --from-column of the model's pick
    $d2 = Join-Path $work 'form2'
    [IO.Directory]::CreateDirectory($d2) | Out-Null
    foreach ($f in 'uCopy.dfm', 'uCopy.pas') { [IO.File]::Copy((Join-Path $fix $f), (Join-Path $d2 $f), $true) }
    $r = Eng "--dfm `"$(Join-Path $d2 'uCopy.dfm')`" --list --from tvMain --json"
    [IO.File]::WriteAllText($f1, $r.Out)
    $col = ((& { $ErrorActionPreference = 'Continue'; & $runner --list $f1 2>&1 | ForEach-Object { "$_" } }) | Where-Object { "$_" -match '^event (\w+) OnGetDisplayText \w+ True' } | Select-Object -First 1)
    $colName = if ("$col" -match '^event (\w+) ') { $Matches[1] } else { '' }
    $null = Eng "--dfm `"$(Join-Path $d2 'uCopy.dfm')`" --from tvMain --to bvMain --apply"   # the target column must exist first: the engine refuses a column event otherwise (exit 1 + message, which the command shows)
    $r = Eng "--dfm `"$(Join-Path $d2 'uCopy.dfm')`" --from tvMain --to bvMain --event OnGetDisplayText --from-column $colName --dry-run --json"
    [IO.File]::WriteAllText($f2, $r.Out)
    $t = (& { $ErrorActionPreference = 'Continue'; & $runner --plan $f2 $sel 2>&1 | ForEach-Object { "$_" } } | ForEach-Object { "$_" }) -join "`n"
    Check 'E7 one column event (the model''s --from-column): a plan the model reads (the column already exists in the target)' (($r.Code -eq 0) -and ($colName -ne '') -and ($t -match 'plan: [0-9A-F]{16} \d+ changes')) "col=[$colName] exit=$($r.Code) $t out=[$($r.Out)]"
  }
}
finally {
  # scratch under $env:TEMP is left for the temp cleaner; nothing in the repo was written
}
Write-Host ('V156 GCPP: {0} checks, {1} failed' -f $script:n, $script:bad) -ForegroundColor $(if ($script:bad) { 'Red' } else { 'Green' })
exit ([int]($script:bad -gt 0))
