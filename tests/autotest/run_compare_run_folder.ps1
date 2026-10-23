<#
  run_compare_run_folder.ps1 -- `compare`'s new run writes its chart bundle to a PER-RUN
  folder, %TEMP%\drag-lint-reports\compare-run-<stamp>-<pid>\, not straight into the
  folder every ask / compare run shares (INBOX-compare-help-db-and-command-quoting item 3,
  e3d W5 item 6).

  TEMP / TMP are pointed at a private folder for the engine process, so the shared folder
  of the machine is never read or written.

  Positive controls: the old side made with `ask --out-root` lands where --out-root says
  (the option set the fix touches is compare's only); the compare itself still exits 0
  (same) -- so an empty report folder cannot pass for a run that never happened.
#>
[CmdletBinding()]
param(
  [string]$Exe  = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
  [string]$Repo = "$PSScriptRoot\..\.."
)
$ErrorActionPreference = 'Continue'
$script:fail = $false
function Check($n,$ok,$d=''){
  Write-Host ("[{0}] {1} {2}" -f (@('FAIL','PASS')[[int]$ok]),$n,$d) -ForegroundColor (@('Red','Green')[[int]$ok])
  if(-not $ok){ $script:fail=$true }
}
$Exe  = (Resolve-Path $Exe).Path
$Repo = (Resolve-Path $Repo).Path
$Proj0 = Join-Path $Repo 'tests\fixtures\compare-verb'
$Work = Join-Path ([IO.Path]::GetTempPath()) ('dl-compare-runfolder-' + [guid]::NewGuid().ToString('N'))
$PDir = Join-Path $Work 'proj'
$Tmp  = Join-Path $Work 'tmp'
New-Item -ItemType Directory -Force -Path $PDir, $Tmp | Out-Null
Copy-Item (Join-Path $Proj0 '*') $PDir
$Proj = Join-Path $PDir 'Cmp.dproj'
$Db   = Join-Path $Work 'cmp.sqlite'

function Invoke-Engine([string[]]$ArgList) {
  $psi = [Diagnostics.ProcessStartInfo]::new($Exe)
  foreach ($a in $ArgList) { $psi.ArgumentList.Add($a) }
  $psi.RedirectStandardOutput = $true; $psi.RedirectStandardError = $true; $psi.UseShellExecute = $false
  $psi.WorkingDirectory = $Work
  $psi.Environment['DRAGLINT_ASK_REPORT'] = (Join-Path $Work 'no-such-Ask-Report.ps1')
  $psi.Environment['TEMP'] = $Tmp
  $psi.Environment['TMP']  = $Tmp
  $p = [Diagnostics.Process]::Start($psi)
  $o = $p.StandardOutput.ReadToEndAsync(); $e = $p.StandardError.ReadToEndAsync()
  $p.WaitForExit()
  return [pscustomobject]@{ Code = $p.ExitCode; Out = $o.Result; Err = $e.Result }
}

try {
  $r = Invoke-Engine @('index','--project',$Proj,'--db',$Db)
  Check 'setup: index the fixture' ($r.Code -eq 0) "exit=$($r.Code)"
  $Bundles = Join-Path $Work 'bundles'
  $r = Invoke-Engine @('ask','who-writes','--target','Unit1.TFoo.FName','--project',$Proj,'--db',$Db,'--plain','--out-root',$Bundles)
  Check 'control: ask --out-root writes its bundle there' ($r.Code -eq 0 -and @(Get-ChildItem $Bundles -Directory -ErrorAction SilentlyContinue).Count -ge 1) "exit=$($r.Code)"
  $Old = Join-Path $Work 'old.txt'
  [IO.File]::WriteAllText($Old, $r.Out)

  $r = Invoke-Engine @('compare','--old',$Old,'--db',$Db)
  Check 'control: compare of an unchanged project exits 0' ($r.Code -eq 0) "exit=$($r.Code) err=$($r.Err)"
  $Shared = Join-Path $Tmp 'drag-lint-reports'
  $top = @(Get-ChildItem $Shared -Directory -ErrorAction SilentlyContinue)
  $runs = @($top | Where-Object { $_.Name -match '^compare-run-\d{8}-\d{6}-\d+$' })
  $loose = @($top | Where-Object { $_.Name -notmatch '^compare-run-' })
  Check 'the new run made exactly one per-run folder' ($runs.Count -eq 1) ("top: " + (($top | ForEach-Object Name) -join ', '))
  Check 'no bundle written straight into the shared folder' ($loose.Count -eq 0) (($loose | ForEach-Object Name) -join ', ')
  if ($runs.Count -eq 1) {
    Check 'the per-run folder holds the bundle' (@(Get-ChildItem $runs[0].FullName -Recurse -File).Count -ge 1) ''
  }
} finally {
  if (Test-Path -LiteralPath $Work) { [IO.Directory]::Delete($Work, $true) }
}
if ($script:fail) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
