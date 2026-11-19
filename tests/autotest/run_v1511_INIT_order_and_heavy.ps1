<#
  run_v1511_INIT_order_and_heavy.ps1 -- 1.51.1 lane INIT (B08 + B05).

  B08: finalization-after-dependency / init-order-hazard follow a call through a
  unit-level procedural variable. Fixture fixtures\v1511-INIT\b08 = the FINPROOF
  FinP3 program after `cycles --fix` (FP3A's finalization -> FP3AStop ->
  FP3BReportPtr(..); FP3B's initialization assigns FP3BReportPtr := FP3BReport;
  FP3BReport reads FP3B.GName, which FP3B's finalization clears).

    c1  FinP3.dpr lists FP3B first: FP3B is finalized before FP3A -> one
        finalization-after-dependency finding on FP3A.pas naming GName
    c2  negative control: the .dpr lists FP3A first (FP3A finalized first) -> none

  B05: heavy-initialization counts a paren-less METHOD reference as a call only
  when it can be one. Fixture fixtures\v1511-INIT\b05.

    c3  uB05Value passes the file routines as VALUES (`AddHook(TB05Checks.CheckFile)`,
        `AddFn(TB05Checks.ReadIt)`, `GHook:= @WorkFile`): no finding
    c4  positive control: uB05Call `TB05Checks.CheckFile;` (a paren-less call statement) fires
    c5  positive control: uB05Bare `WorkFile;` fires

  Every index run passes --db into the work folder: no real DB is touched.
  Run from a NEUTRAL CWD, pwsh 7.
#>
[CmdletBinding()]
param(
  [string]$Exe     = '',
  [string]$WorkDir = "$env:TEMP\draglint_v1511_init_$PID",
  [switch]$Quiet
)
# Defaults that need the script path are resolved HERE, not in param(): Windows PowerShell 5 run with
# -File leaves $PSScriptRoot/$MyInvocation empty inside an advanced script's param block (Repo became C:\).
if (-not $Exe) { $Exe = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe" }
$ErrorActionPreference = 'Stop'
$script:fail = $false
function Check([bool]$ok, [string]$what) {
  if ($ok) { if (-not $Quiet) { Write-Host "PASS  $what" } }
  else     { Write-Host "FAIL  $what" -ForegroundColor Red; $script:fail = $true }
}

# lint-all --json is a bare array; keep the rows of one rule.
function Get-Findings([string]$ExePath, [string]$Db, [string]$Rule) {
  $raw = (& $ExePath lint-all --db $Db --rule $Rule --json 2>$null) -join "`n"
  $j = $raw | ConvertFrom-Json
  return ,@($j | Where-Object { $_.rule_id -eq $Rule -or $_.rule -eq $Rule })
}
function FileOf($F) { return [IO.Path]::GetFileName([string]$(if ($F.file) { $F.file } else { $F.file_path })) }

$exePath = (Resolve-Path $Exe).Path
$src     = Join-Path $PSScriptRoot 'fixtures\v1511-INIT'
New-Item -ItemType Directory -Force $WorkDir | Out-Null
Push-Location $env:TEMP
try {
  Copy-Item (Join-Path $src '*') $WorkDir -Recurse -Force

  # ---- B08
  $b08 = Join-Path $WorkDir 'b08'
  $db1 = Join-Path $WorkDir 'b08.sqlite'
  & $exePath index $b08 --db $db1 *> $null
  $fin = Get-Findings $exePath $db1 'finalization-after-dependency'
  $hit = @($fin | Where-Object { (FileOf $_) -eq 'FP3A.pas' -and $_.message -match 'GName' })
  Check (($hit.Count -eq 1) -and ($fin.Count -eq 1)) "c1 FP3B first: one finalization-after-dependency on FP3A.pas naming GName (got $($fin.Count): $(@($fin | ForEach-Object { (FileOf $_) + ':' + $_.start_line }) -join ', '))"

  $b08n = Join-Path $WorkDir 'b08n'
  Copy-Item $b08 $b08n -Recurse -Force
  $dpr = Join-Path $b08n 'FinP3.dpr'
  $t = [IO.File]::ReadAllText($dpr)
  $t = $t.Replace("  FP3B in 'FP3B.pas',`r`n  FP3A in 'FP3A.pas',", "  FP3A in 'FP3A.pas',`r`n  FP3B in 'FP3B.pas',")
  [IO.File]::WriteAllText($dpr, $t, [Text.Encoding]::ASCII)
  $db2 = Join-Path $WorkDir 'b08n.sqlite'
  & $exePath index $b08n --db $db2 *> $null
  $fin2 = Get-Findings $exePath $db2 'finalization-after-dependency'
  Check ($fin2.Count -eq 0) "c2 FP3A first: no finalization-after-dependency (got $($fin2.Count))"

  # ---- B05
  $b05 = Join-Path $WorkDir 'b05'
  $db3 = Join-Path $WorkDir 'b05.sqlite'
  & $exePath index $b05 --db $db3 *> $null
  $heavy = Get-Findings $exePath $db3 'heavy-initialization'
  $files = @($heavy | ForEach-Object { FileOf $_ })
  Check (-not ($files -contains 'uB05Value.pas')) "c3 routines passed as values: no heavy-initialization on uB05Value.pas (got: $($files -join ', '))"
  Check ($files -contains 'uB05Call.pas') "c4 positive control: TB05Checks.CheckFile; fires on uB05Call.pas"
  Check ($files -contains 'uB05Bare.pas') "c5 positive control: WorkFile; fires on uB05Bare.pas"
} finally {
  Pop-Location
  if (Test-Path $WorkDir) { [IO.Directory]::Delete($WorkDir, $true) }
}

if ($script:fail) { Write-Host 'run_v1511_INIT_order_and_heavy: FAIL'; exit 1 }
Write-Host 'run_v1511_INIT_order_and_heavy: PASS'
exit 0
