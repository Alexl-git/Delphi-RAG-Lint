#Requires -Version 7.3
<#
  run_v156_GCPC.ps1 -- `repo copy-grid` (1.56 lane GCP-C): the CLI verb over the grid copy model
  (DRagLint.CLI.RepoGridCopy on DRagLint.FieldRepo.GridCopy; fixture tests\fixtures\fieldrepo\gridcopy).

  Drives the engine exe on COPIES of the fixture form (a temp folder per case): dry run vs write, --json shape,
  --select, backups, exit codes. The fixture has tvMain (table view, 3 columns, many events), bvMain (banded, 1
  column) and cvMain (card view, empty).

  A missing engine exe is a FAIL here, never a skip. Exit 0 only when every check passes.

  Parameters:
    -Repo       repo root (default: two levels above this script)
    -Exe        engine to drive (default: <Repo>\src\cli\Win64\Debug\drag-lint.exe, built by
                build\build_draglint_win64.bat -NoStage or msbuild on src\cli\drag-lint.dproj, Win64 Debug)
#>
[CmdletBinding()]
param([string]$Repo = '',
      [string]$Exe = '')
if (-not $Repo) { $Repo = (Resolve-Path "$PSScriptRoot\..\..").Path }
if (-not $Exe) { $Exe = Join-Path $Repo 'src\cli\Win64\Debug\drag-lint.exe' }
$ErrorActionPreference = 'Stop'
Write-Host '== v156 GCP-C: repo copy-grid ==' -ForegroundColor Cyan
if (-not (Test-Path -LiteralPath $Exe)) { Write-Host "V156 GCPC: FAIL -- engine not found: $Exe" -ForegroundColor Red; exit 1 }
$fix = Join-Path $Repo 'tests\fixtures\fieldrepo\gridcopy'
$work = Join-Path $env:TEMP "drag-lint-v156-gcpc-$PID"
New-Item -ItemType Directory -Path $work -Force | Out-Null
$script:bad = 0
$script:n = 0
function Check($name, $ok, $detail = '') {
  $script:n++
  Write-Host ('[{0}] {1} {2}' -f $(if ($ok) { 'PASS' } else { 'FAIL' }), $name, $(if ($ok) { '' } else { $detail })) -ForegroundColor $(if ($ok) { 'Green' } else { 'Red' })
  if (-not $ok) { $script:bad++ }
}
$script:case = 0
function NewForm {
  $script:case++
  $d = Join-Path $work ("c$($script:case)")
  [IO.Directory]::CreateDirectory($d) | Out-Null
  foreach ($f in 'uCopy.dfm', 'uCopy.pas') { [IO.File]::Copy((Join-Path $fix $f), (Join-Path $d $f), $true) }
  $d
}
# runs the verb; returns @{ Code; Out; Err }
function Run($dir, [string[]]$more, [switch]$NoDfm) {
  $a = @('repo', 'copy-grid', '--repo', (Join-Path $work 'none.sqlite'))
  if (-not $NoDfm) { $a += @('--dfm', (Join-Path $dir 'uCopy.dfm')) }
  $a += $more
  $o = Join-Path $work 'o.txt'; $e = Join-Path $work 'e.txt'
  $p = Start-Process -FilePath $Exe -ArgumentList $a -Wait -PassThru -NoNewWindow -RedirectStandardOutput $o -RedirectStandardError $e
  @{ Code = $p.ExitCode; Out = (Get-Content -LiteralPath $o -Raw); Err = (Get-Content -LiteralPath $e -Raw) }
}
function Sum($dir) { (Get-FileHash -LiteralPath (Join-Path $dir 'uCopy.dfm') -Algorithm SHA256).Hash + (Get-FileHash -LiteralPath (Join-Path $dir 'uCopy.pas') -Algorithm SHA256).Hash }
function Backups($dir) { @(Get-ChildItem -LiteralPath $dir -Filter '*.before-write-dfm-*').Count }
function Detail($r) { "exit=$($r.Code) out=[$($r.Out)] err=[$($r.Err)]" }
try {
  # ---- list ----
  $d = NewForm
  $r = Run $d @('--list')
  Check 'L1 --list names the three views and writes nothing' (($r.Code -eq 0) -and ($r.Out -match '(?m)^view tvMain \(TcxGridDBTableView\)') -and ($r.Out -match '(?m)^view bvMain ') -and ($r.Out -match '(?m)^view cvMain ')) (Detail $r)
  $r = Run $d @('--list', '--from', 'tvMain', '--json')
  $j = try { $r.Out | ConvertFrom-Json } catch { $null }
  Check 'L2 --list --from V --json: views[] and events[] with component, event, handler' (($r.Code -eq 0) -and $j -and (@($j.views).Count -eq 3) -and (@($j.events | Where-Object { $_.event -eq 'OnCustomDrawCell' -and $_.handler -eq 'tvMainCustomDrawCell' -and -not $_.column }).Count -eq 1)) (Detail $r)

  # ---- dry run ----
  $d = NewForm; $before = Sum $d
  $r = Run $d @('--from', 'tvMain', '--to', 'bvMain')
  Check 'D1 default is a DRY RUN: plan text, the dry-run line, exit 0, no file touched' (($r.Code -eq 0) -and ($r.Out -match '(?m)^# plan [0-9A-F]{16}\r?$') -and ($r.Out -match 'copy tvMain \(TcxGridDBTableView\) -> bvMain \(TcxGridDBBandedTableView\)') -and ($r.Out -match 'dry run: nothing written') -and ((Sum $d) -eq $before) -and ((Backups $d) -eq 0)) (Detail $r)
  $r = Run $d @('--from', 'tvMain', '--to', 'bvMain', '--json')
  $j = try { $r.Out | ConvertFrom-Json } catch { $null }
  Check 'D2 --json shape: plan, source, target, count, changes[], mode dry-run, applied 0, written [], backups []' (($r.Code -eq 0) -and $j -and ($j.plan -match '^[0-9A-Fa-f]{16}$') -and ($j.source -eq 'tvMain') -and ($j.target -eq 'bvMain') -and ($j.count -gt 0) -and (@($j.changes).Count -eq $j.count) -and ($j.mode -eq 'dry-run') -and ($j.applied -eq 0) -and (@($j.written).Count -eq 0) -and (@($j.backups).Count -eq 0) -and ((Sum $d) -eq $before)) (Detail $r)
  $r = Run $d @('--from', 'tvMain', '--to', 'bvMain', '--apply', '--dry-run')
  Check 'D3 --dry-run wins over --apply: nothing written' (($r.Code -eq 0) -and ($r.Out -match 'dry run: nothing written') -and ((Sum $d) -eq $before)) (Detail $r)

  # ---- apply: copy everything ----
  $r = Run $d @('--from', 'tvMain', '--to', 'bvMain', '--apply')
  $dfm = Get-Content -LiteralPath (Join-Path $d 'uCopy.dfm') -Raw
  Check 'A1 --apply writes the DFM and the unit with a backup of each; the new columns are in the DFM' (($r.Code -eq 0) -and ($r.Out -match '(?m)^WRITTEN 2\r?$') -and ((Backups $d) -eq 2) -and ($dfm -match 'bvMainCODE: TcxGridDBBandedColumn') -and ($dfm -match 'bvMainQTY: TcxGridDBBandedColumn')) (Detail $r)
  $afterOne = Sum $d
  $r = Run $d @('--from', 'tvMain', '--to', 'bvMain', '--apply')
  Check 'A2 a second copy writes nothing: only the 2 UNCHECKED changes are left, WRITTEN 0, no new backup' (($r.Code -eq 0) -and ($r.Out -match '2 changes, 0 blocked, 2 unchecked') -and ($r.Out -match '(?m)^WRITTEN 0\r?$') -and ((Sum $d) -eq $afterOne) -and ((Backups $d) -eq 2)) (Detail $r)
  $d2 = NewForm
  $r = Run $d2 @('--from', 'tvMain', '--to', 'bvMain', '--apply', '--json')
  $j = try { $r.Out | ConvertFrom-Json } catch { $null }
  Check 'A3 --apply --json: mode apply, applied > 0, written = 2 files, backups = 2 files that exist' (($r.Code -eq 0) -and $j -and ($j.mode -eq 'apply') -and ($j.applied -gt 0) -and (@($j.written).Count -eq 2) -and (@($j.backups).Count -eq 2) -and (@($j.backups | Where-Object { Test-Path -LiteralPath $_ }).Count -eq 2)) (Detail $r)

  # ---- one event ----
  $d = NewForm; $before = Sum $d
  $r = Run $d @('--from', 'tvMain', '--to', 'bvMain', '--event', 'OnCustomDrawCell', '--json')
  $j = try { $r.Out | ConvertFrom-Json } catch { $null }
  Check 'E1 --event: a plan of ONE change, the view event' (($r.Code -eq 0) -and $j -and ($j.count -eq 1) -and ($j.changes[0].prop -eq 'OnCustomDrawCell') -and ($j.changes[0].new -eq 'tvMainCustomDrawCell') -and ((Sum $d) -eq $before)) (Detail $r)
  $r = Run $d @('--from', 'tvMain', '--to', 'bvMain', '--event', 'OnCustomDrawCell', '--apply')
  $dfm = Get-Content -LiteralPath (Join-Path $d 'uCopy.dfm') -Raw
  Check 'E2 --event --apply: the target view has the handler, no column was added' (($r.Code -eq 0) -and ($r.Out -match '(?m)^WRITTEN 1\r?$') -and ($dfm -match '(?s)object bvMain: TcxGridDBBandedTableView.*?OnCustomDrawCell = tvMainCustomDrawCell') -and ($dfm -notmatch 'bvMainCODE')) (Detail $r)
  $d = NewForm
  $r = Run $d @('--from', 'tvMain', '--to', 'bvMain', '--event', 'OnGetDisplayText', '--from-column', 'tvMainNAME', '--json')
  $j = try { $r.Out | ConvertFrom-Json } catch { $null }
  $sel = Join-Path $work 'sel3.txt'
  [IO.File]::WriteAllText($sel, "# plan $($j.plan)`r`nall`r`n")
  $r = Run $d @('--from', 'tvMain', '--to', 'bvMain', '--event', 'OnGetDisplayText', '--from-column', 'tvMainNAME', '--select', $sel)
  $dfm = Get-Content -LiteralPath (Join-Path $d 'uCopy.dfm') -Raw
  Check 'E3 --event with --from-column: an UNCHECKED update is not applied by default but is by `all`, on the column that shows the same field' ($j -and ($j.count -eq 1) -and ($j.unchecked -eq 1) -and ($j.changes[0].target -match 'bvMainNAME') -and ($r.Code -eq 0) -and ($dfm -match '(?s)object bvMainNAME: TcxGridDBBandedColumn.*?OnGetDisplayText = tvMainNAMEGetDisplayText')) (Detail $r)

  # ---- --select ----
  $d = NewForm; $before = Sum $d
  $r = Run $d @('--from', 'tvMain', '--to', 'bvMain')
  $plan = [regex]::Match($r.Out, '(?mi)^# plan ([0-9A-F]{16})').Groups[1].Value
  $sel = Join-Path $work 'sel.txt'
  [IO.File]::WriteAllText($sel, "1`r`n")
  $r = Run $d @('--from', 'tvMain', '--to', 'bvMain', '--select', $sel)
  Check 'S1 a --select file without the `# plan` line: exit 2, nothing written' (($r.Code -eq 2) -and ($r.Err -match 'plan') -and ((Sum $d) -eq $before)) (Detail $r)
  [IO.File]::WriteAllText($sel, "# plan 0000000000000000`r`n1`r`n")
  $r = Run $d @('--from', 'tvMain', '--to', 'bvMain', '--select', $sel)
  Check 'S2 a --select file of ANOTHER plan: exit 1, nothing written' (($r.Code -eq 1) -and ((Sum $d) -eq $before)) (Detail $r)
  [IO.File]::WriteAllText($sel, "# plan $plan`r`n1`r`n")
  $r = Run $d @('--from', 'tvMain', '--to', 'bvMain', '--select', $sel, '--json')
  $j = try { $r.Out | ConvertFrom-Json } catch { $null }
  Check 'S3 --select with the plan line writes exactly the named id' (($r.Code -eq 0) -and $j -and ($j.mode -eq 'apply') -and ($j.applied -eq 1) -and ((Sum $d) -ne $before)) (Detail $r)
  $d = NewForm; $before = Sum $d
  [IO.File]::WriteAllText($sel, "# plan $plan`r`n9999`r`n")
  $r = Run $d @('--from', 'tvMain', '--to', 'bvMain', '--select', $sel)
  Check 'S4 an unknown id in --select: exit 2, nothing written' (($r.Code -eq 2) -and ((Sum $d) -eq $before)) (Detail $r)
  $r = Run $d @('--from', 'tvMain', '--to', 'bvMain', '--select', (Join-Path $work 'nosuch.txt'))
  Check 'S5 a --select file that does not exist: exit 2' (($r.Code -eq 2) -and ((Sum $d) -eq $before)) (Detail $r)

  # ---- usage and failures ----
  $d = NewForm; $before = Sum $d
  $r = Run $d @('--from', 'tvMain', '--to', 'bvMain') -NoDfm
  Check 'X1 no --dfm: exit 2 with the flag named' (($r.Code -eq 2) -and ($r.Err -match '--dfm')) (Detail $r)
  $r = Run $d @('--from', 'tvMain')
  Check 'X2 no --to: exit 2' (($r.Code -eq 2) -and ($r.Err -match '--to')) (Detail $r)
  $r = Run $d @('--from', 'tvMain', '--to', 'bvMain', '--from-column', 'tvMainNAME')
  Check 'X3 --from-column without --event: exit 2' (($r.Code -eq 2) -and ($r.Err -match '--event')) (Detail $r)
  $r = Run $d @('--from', 'tvMain', '--to', 'noSuchView')
  Check 'X4 a view the form does not have: exit 1, message names it, nothing written' (($r.Code -eq 1) -and ($r.Err -match 'noSuchView') -and ((Sum $d) -eq $before)) (Detail $r)
  $r = Run $d @('--from', 'tvMain', '--to', 'tvMain')
  Check 'X5 source = target: exit 1' (($r.Code -eq 1) -and ((Sum $d) -eq $before)) (Detail $r)
  $r = Run $d @('--from', 'tvMain', '--to', 'bvMain', '--event', 'OnNoSuchEvent')
  Check 'X6 an event the source does not have: exit 1' (($r.Code -eq 1) -and ((Sum $d) -eq $before)) (Detail $r)
  $r = Run $d @('--from', 'tvMain', '--to', 'bvMain', '--json')
  $r2 = Run $d @('--dfm', (Join-Path $work 'missing.dfm'), '--from', 'tvMain', '--to', 'bvMain') -NoDfm
  Check 'X7 a DFM that does not exist: exit 1 (a dry run of a good form is exit 0)' (($r2.Code -eq 1) -and ($r.Code -eq 0)) (Detail $r2)
  $r = Run $d @('--from', 'tvMain', '--to', 'bvMain', '--unit', (Join-Path $work 'nosuch.pas'))
  Check 'X8 --unit that does not exist: exit 1' ($r.Code -eq 1) (Detail $r)
} finally {
  if (Test-Path -LiteralPath $work) { Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue }
}
Write-Host ("SUMMARY checks=$($script:n) fail=$($script:bad)")
if ($script:bad -gt 0) { Write-Host "V156 GCPC: FAIL -- $($script:bad) of $($script:n)" -ForegroundColor Red; exit 1 }
Write-Host 'V156 GCPC: PASS' -ForegroundColor Green
exit 0
