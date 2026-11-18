<#
  run_v1511_V151F_t03_t04.ps1 -- run v1511 lane V151F items T03 + T04 (no index: plain `lint`).
  T03 form-object-without-field: TdxBar* / TdxLayout* objects without a name-reachable use stay
      silent; a plain TLabel and a bar button whose name the unit uses by string still fire.
  T04 dataset-edit-without-post: an Edit whose dataset is posted in ANOTHER routine of the unit
      stays silent; a lone Edit still fires.
  Both rules are enabled with --enable (their default). Positive control: no --enable = no findings.
  Run from a NEUTRAL CWD, pwsh 7.
#>
[CmdletBinding()]
param([string]$Exe = '')
# Defaults that need the script path are resolved HERE, not in param(): Windows PowerShell 5 run with
# -File leaves $PSScriptRoot/$MyInvocation empty inside an advanced script's param block (Repo became C:\).
if (-not $Exe) { $Exe = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe" }
$ErrorActionPreference = 'Stop'
$script:fail = $false
function Check($n, $ok, $d) {
  Write-Host ("[{0}] {1}" -f (@('FAIL', 'PASS')[[int][bool]$ok]), $n)
  if (-not $ok) { if ($d) { Write-Host "      $d" }; $script:fail = $true }
}
$exePath = (Resolve-Path $Exe).Path
$fx = Join-Path $PSScriptRoot 'fixtures\v1511-V151F'
function Lines($file, $rule, [string[]]$extra) {
  $ra = if ($extra.Count -gt 0) { @("--rule", $rule) + $extra } else { @() }
  $raw = & $exePath lint $file --json @ra 2>$null
  $t = ($raw -join "`n").Trim()
  if ($t -eq '') { return @() }
  try { $j = @($t | ConvertFrom-Json) } catch { return @() }
  return @($j | Where-Object { $_.rule -eq $rule } | ForEach-Object { "$([IO.Path]::GetFileName($_.file_path)):$($_.start_line)" })
}
function LineOf($file, $pat) {
  $l = [IO.File]::ReadAllLines($file)
  for ($i = 0; $i -lt $l.Count; $i++) { if ($l[$i] -match $pat) { return $i + 1 } }
  return -1
}

# T03
$pas = Join-Path $fx 't03\UBars.pas'; $dfm = Join-Path $fx 't03\UBars.dfm'
$r = 'form-object-without-field'
$got = Lines $pas $r @('--enable', $r)
Write-Host ("T03 got: " + ($got -join ' '))
foreach ($n in 'Label1', 'dxBarButton2') { $l = LineOf $dfm "object $n\b"; Check "T03 fires for $n" ($got -contains "UBars.dfm:$l") }
foreach ($n in 'dxBarManager1', 'dxBarButton1', 'dxLayoutItem1') { $l = LineOf $dfm "object $n\b"; Check "T03 silent for $n" (-not ($got -contains "UBars.dfm:$l")) }
Check 'T03 positive control: rule not enabled -> no finding' ((Lines $pas $r @()).Count -eq 0)

# T04
$pas = Join-Path $fx 't04\UEd.pas'
$r = 'dataset-edit-without-post'
$got = Lines $pas $r @('--enable', $r)
Write-Host ("T04 got: " + ($got -join ' '))
$hit = LineOf $pas '\{HIT\}'; $ok = LineOf $pas '\{OK\}'
Check 'T04 fires on the lone Edit' ($got -contains "UEd.pas:$hit")
Check 'T04 silent when posted in another routine' (-not ($got -contains "UEd.pas:$ok"))
Check 'T04 positive control: rule not enabled -> no finding' ((Lines $pas $r @()).Count -eq 0)

if ($script:fail) { Write-Host 'RESULT: FAIL'; exit 1 } else { Write-Host 'RESULT: PASS' }
