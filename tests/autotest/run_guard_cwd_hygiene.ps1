<#
  run_guard_cwd_hygiene.ps1 -- 150 H1 item 2. A guard must not leave files in its caller's cwd
  (149/150 incidents: lint-report-<date>.txt and a file named '1' appeared in the worktree root,
  written by ANOTHER parallel guard, and made shared_via_property S1 fail).

  Runs each named guard with its cwd = a fresh EMPTY temp dir and FAILS when the dir is not empty
  afterwards (the files are listed). Guards that cannot run here (non-zero exit for a missing
  exe etc.) are judged only on what they left behind.

    default        : the guards that were found to write into cwd (-Guards list below) -- the battery set
    -All           : every run_*.ps1 in tests\autotest (hours; the one-off sweep, -Jobs N)
    -Guards a,b    : explicit guard file names
  The 150 H1 sweep (see C:\TEMP\claude\lanes\150\H1\REPORT.md) found the list below; add a name
  here when a new stray is found.

  Control (positive): a throwaway script that writes stray.txt to its cwd is reported as a stray,
  so the check cannot pass vacuously.
  pwsh 7.
#>
[CmdletBinding()]
param(
  [string[]]$Guards = @(
  'run_allow_supersedes_marker.ps1',
  'run_clone_anchor_stability.ps1',
  'run_doc_fix_seealso_agreement.ps1',
  'run_flow_out_arg_gate_profile.ps1',
  'run_lint_dfm_property_not_declared.ps1',
  'run_lintall_no_library_warning.ps1',
  'run_lintfix_compilegate.ps1',
  'run_marker_malformed_advises_every_form.ps1',
  'run_marker_span.ps1',
  'run_marker_unused_optin_gated_rules.ps1',
  'run_marker_unused_unjudgeable_rules.ps1',
  'run_missing_doc_impl_section.ps1',
  'run_pp_directives.ps1',
  'run_readonly_verbs.ps1',
  'run_shared_unit_scope.ps1',
  'run_shared_unit_staleness.ps1',
  'run_unused_public_shared_siblings.ps1',
  'run_unused_unit_inline_methods.ps1',
  'run_vm_polish_guard.ps1',
  'run_schema_read_compat.ps1',
  '..\ergonomics\run_pipeline_tests.ps1'),
  [switch]$All,
  [int]$Jobs = 4,
  [int]$TimeoutSec = 600,
  [string]$Exe = ''
)
$ErrorActionPreference = 'Stop'
$here = $PSScriptRoot
$script:Failed = $false
function Check([string]$Name, [bool]$Ok, [string]$Detail = '') {
  if ($Ok) { Write-Host "PASS  $Name" } else { Write-Host "FAIL  $Name  $Detail" -ForegroundColor Red; $script:Failed = $true }
}
$tmpRoot = Join-Path ([IO.Path]::GetTempPath()) ("drag-lint-cwdhyg-$PID")
[IO.Directory]::CreateDirectory($tmpRoot) | Out-Null

$runOne = {
  param($Script, $Root, $TimeoutSec, $Exe)
  $cwd = Join-Path $Root ([IO.Path]::GetFileNameWithoutExtension($Script))
  [IO.Directory]::CreateDirectory($cwd) | Out-Null
  $a = @('-NoProfile', '-NonInteractive', '-File', $Script)
  if ($Exe -ne '') { $a += @('-Exe', $Exe) }
  $p = Start-Process pwsh -ArgumentList $a -WorkingDirectory $cwd -PassThru -WindowStyle Hidden `
         -RedirectStandardOutput (Join-Path $Root ([IO.Path]::GetFileName($Script) + '.out')) `
         -RedirectStandardError  (Join-Path $Root ([IO.Path]::GetFileName($Script) + '.err'))
  if (-not $p.WaitForExit($TimeoutSec * 1000)) { try { $p.Kill($true) } catch { } }
  $left = @(Get-ChildItem -LiteralPath $cwd -Recurse -Force -File -ErrorAction SilentlyContinue | ForEach-Object { $_.FullName.Substring($cwd.Length + 1) })
  [pscustomobject]@{ Guard = [IO.Path]::GetFileName($Script); Left = $left }
}

# positive control
$ctl = Join-Path $tmpRoot 'ctl_stray.ps1'
[IO.File]::WriteAllText($ctl, "Set-Content -Path stray.txt -Value x", (New-Object Text.ASCIIEncoding))
$c = & $runOne $ctl (Join-Path $tmpRoot 'ctlout') 60 ''
Check 'control: a script writing stray.txt to cwd is detected' (($c.Left -contains 'stray.txt')) ($c.Left -join ',')

$list = if ($All) { Get-ChildItem $here -Filter 'run_*.ps1' | Where-Object { $_.Name -ne 'run_guard_cwd_hygiene.ps1' } | ForEach-Object { $_.FullName } }
        else { $Guards | ForEach-Object { Join-Path $here $_ } }
$rootOut = Join-Path $tmpRoot 'g'
[IO.Directory]::CreateDirectory($rootOut) | Out-Null
$runOneText = $runOne.ToString()
# A guard that does `Set-Location $repo` writes its stray into the REPO ROOT, not the empty cwd
# above (run_pipeline_tests, run_schema_read_compat -- 2026-11-10; lint-report-*.txt is gitignored,
# so nobody saw it). Watch the root's stray shapes too. Under a parallel battery another guard may
# be the writer -- the finding is still a real stray; run the named guards alone to attribute it.
$repoRoot = (Resolve-Path (Join-Path $here '..\..')).Path
$rootStart = Get-Date
$rootStrays = { Get-ChildItem -LiteralPath $repoRoot -File -Force -ErrorAction SilentlyContinue |
  Where-Object { ($_.Name -like 'lint-report-*.txt' -or $_.Name -eq '1') -and $_.LastWriteTime -ge $rootStart } |
  ForEach-Object Name }
$rs = $list | ForEach-Object -ThrottleLimit $Jobs -Parallel {
  & ([scriptblock]::Create($using:runOneText)) $_ $using:rootOut $using:TimeoutSec $using:Exe
}
foreach ($r in $rs) {
  Check "$($r.Guard) leaves nothing in its cwd" ($r.Left.Count -eq 0) ($r.Left -join ', ')
  if ($All -and $r.Left.Count -gt 0) { Write-Host "STRAY`t$($r.Guard)`t$($r.Left -join ';')" }
}
$rootLeft = @(& $rootStrays)
Check 'no lint-report-*.txt / "1" written into the repo root during the run' ($rootLeft.Count -eq 0) ($rootLeft -join ', ')
try { [IO.Directory]::Delete($tmpRoot, $true) } catch { }
if ($script:Failed) { Write-Host 'run_guard_cwd_hygiene: FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'run_guard_cwd_hygiene: PASS'; exit 0