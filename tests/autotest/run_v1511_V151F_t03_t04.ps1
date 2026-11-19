<#
  run_v1511_V151F_t03_t04.ps1 -- run v1511 lane V151F items T03 + T04 (no index: plain `lint`).
  T03 form-object-without-field: TdxBar* / TdxLayout* objects without a name-reachable use stay
      silent; a plain TLabel and a bar button whose name the unit uses by string still fire.
  T04 dataset-edit-without-post: an Edit whose dataset is posted in ANOTHER routine of the unit
      stays silent; a lone Edit still fires.
  Both rules are enabled with --enable (default ON since 1.52). Positive control: --disable = no findings.
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
  # 1.52: both rules are default ON (DEFAULTS D7), so the positive control passes --disable WITHOUT --rule.
  $ra = @(if ($extra -contains '--disable') { $extra } elseif ($extra.Count -gt 0) { @("--rule", $rule) + $extra } else { @() })
  $raw = & { $ErrorActionPreference = 'Continue'; & $exePath lint $file --json @ra 2>$null }
  $t = ($raw -join "`n").Trim()
  if ($t -eq '') { return @() }
  try { $j = @(($t | ConvertFrom-Json | ForEach-Object { $_ }) | ForEach-Object { $_ }) } catch { return @() }
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
# 1.52 D3: the shipped exempt list names TdxBar* / TdxLayout*; T03 pins the 1.51.1 name-reachable skip, so it
# runs with use_default_list false (the list itself is pinned by run_v152_DEFAULTS.ps1).
$noList = Join-Path $env:TEMP ("v151f_t03_nolist_$PID.json")
[IO.File]::WriteAllText($noList, '{"form_object_without_field": {"use_default_list": false}}')
$got = @(Lines $pas $r @('--enable', $r, '--config', $noList))
Write-Host ("T03 got: " + ($got -join ' '))
foreach ($n in 'Label1', 'dxBarButton2') { $l = LineOf $dfm "object $n\b"; Check "T03 fires for $n" ($got -contains "UBars.dfm:$l") }
foreach ($n in 'dxBarManager1', 'dxBarButton1', 'dxLayoutItem1') { $l = LineOf $dfm "object $n\b"; Check "T03 silent for $n" (-not ($got -contains "UBars.dfm:$l")) }
Check 'T03 positive control: rule disabled -> no finding' ((@(Lines $pas $r @('--disable', $r, '--config', $noList))).Count -eq 0)
[IO.File]::Delete($noList)

# T04
$pas = Join-Path $fx 't04\UEd.pas'
$r = 'dataset-edit-without-post'
$got = @(Lines $pas $r @('--enable', $r))
Write-Host ("T04 got: " + ($got -join ' '))
$hit = LineOf $pas '\{HIT\}'; $ok = LineOf $pas '\{OK\}'
Check 'T04 fires on the lone Edit' ($got -contains "UEd.pas:$hit")
Check 'T04 silent when posted in another routine' (-not ($got -contains "UEd.pas:$ok"))
Check 'T04 positive control: rule disabled -> no finding' ((@(Lines $pas $r @('--disable', $r))).Count -eq 0)

if ($script:fail) { Write-Host 'RESULT: FAIL'; exit 1 } else { Write-Host 'RESULT: PASS' }
