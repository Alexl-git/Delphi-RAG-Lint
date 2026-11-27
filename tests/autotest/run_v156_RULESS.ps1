#Requires -Version 7.3
<#
  run_v156_RULESS.ps1 -- 1.56 lane RULES-S: three small rule gaps (COMPETITOR-GAPS-2026-11-23).
    G70  implicit-package-import is ON in the catalogue (rules --json) | docs\wiki\compiler-messages.md must not
         call it refused (catalogue and wiki agree)
    G61  unit-used-by-no-unit is DI aware: a registrar unit (no class, no initialization, nothing uses it, it
         calls GlobalContainer.RegisterType<TFoo>) is silent | UDeadUnit still fires (positive control)
    G64  side-effect-in-short-circuit: UNCHANGED in 1.56 (owner question); `Ok:= Ok and Pop(N)` (free function)
         and `Ok:= Ok and R.Bump` (writes a field) still fire (positive controls)
  Fixture tests\fixtures\v156\RULESS\app (copied to a temp folder).
  Run: pwsh -File tests\autotest\run_v156_RULESS.ps1 [-Exe <drag-lint.exe>] [-Wiki <compiler-messages.md>]
#>
[CmdletBinding()]
param([string]$Exe = '', [string]$Wiki = '')
if (-not $Exe) { $Exe = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe" }
if (-not $Wiki) { $Wiki = "$PSScriptRoot\..\..\docs\wiki\compiler-messages.md" }
$ErrorActionPreference = 'Continue'
$script:Pass = 0
$script:Fail = 0
function Check($n, $ok, $d = '') {
  Write-Host ("[{0}] {1} {2}" -f (@('FAIL','PASS')[[int][bool]$ok]), $n, $(if ($ok) { '' } else { $d })) -ForegroundColor (@('Red','Green')[[int][bool]$ok])
  if ($ok) { $script:Pass++ } else { $script:Fail++ }
}
Write-Host '== v156 RULES-S ==' -ForegroundColor Cyan
if (-not (Test-Path -LiteralPath $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
$Exe = (Resolve-Path -LiteralPath $Exe).Path
$work = Join-Path ([IO.Path]::GetTempPath()) ('dl-v156-ruless-' + [guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($work) | Out-Null
try {
  # G70
  $cat = $null
  try { $cat = (& { $ErrorActionPreference = 'Continue'; & $Exe rules --json 2>$null } | ConvertFrom-Json | ForEach-Object { $_ }).rules | Where-Object { $_.id -eq 'implicit-package-import' } } catch { }
  $on = ($null -ne $cat) -and ($cat.default_enabled -eq $true)
  Check 'G70a catalogue: implicit-package-import exists, default ON' $on
  $row = (Get-Content -LiteralPath $Wiki | Where-Object { $_ -match '^\| `implicit-package-import`' }) -join ' '
  Check 'G70b wiki row exists' ($row -ne '')
  Check 'G70c wiki does not call a catalogue rule refused' ($row -ne '' -and $row -notmatch 'Refused as a rule') $row

  # fixture index
  Copy-Item -Path "$PSScriptRoot\..\fixtures\v156\RULESS\app" -Destination $work -Recurse
  $dproj = Join-Path $work 'app\App.dproj'
  $db = Join-Path $work 'app.sqlite'
  $idx = (& { $ErrorActionPreference = 'Continue'; & $Exe index --project $dproj --db $db 2>&1 | ForEach-Object { "$_" } }) -join "`n"
  if ($LASTEXITCODE -ne 0) { Write-Host $idx; Check 'index exit 0' $false; throw 'index failed' }
  function LintAll([string[]]$extra) {
    $raw = (& { $ErrorActionPreference = 'Continue'; & $Exe lint-all --db $db --project $dproj --json @extra 2>$null }) -join "`n"
    $arr = @()
    try { $arr = @(($raw | ConvertFrom-Json | ForEach-Object { $_ }) | ForEach-Object { $_ }) } catch { }
    return ,$arr
  }
  # G61
  $f = LintAll @('--rule', 'unit-used-by-no-unit')
  $u = @($f | Where-Object { $_.rule -eq 'unit-used-by-no-unit' } | ForEach-Object { [IO.Path]::GetFileNameWithoutExtension('' + $_.file_path) })
  Check 'G61a positive control: UDeadUnit fires' (@($u | Where-Object { $_ -eq 'UDeadUnit' }).Count -eq 1) ($u -join ',')
  Check 'G61b UConfig (DI registrar, nothing uses it) silent' (@($u | Where-Object { $_ -eq 'UConfig' }).Count -eq 0) ($u -join ',')
  Check 'G61c UUsed / UFoo / UChain silent' (@($u | Where-Object { $_ -in 'UUsed','UFoo','UChain' }).Count -eq 0) ($u -join ',')
  $off = LintAll @('--rule', 'unit-used-by-no-unit', '--disable', 'unit-used-by-no-unit')
  Check 'G61d positive control: --disable silences the rule' (@($off | Where-Object { $_.rule -eq 'unit-used-by-no-unit' }).Count -eq 0)

  # G64
  $rid = 'side-effect-in-short-circuit'
  $g = LintAll @('--rule', $rid, '--enable', $rid)
  $lines = Get-Content -LiteralPath (Join-Path $work 'app\UChain.pas')
  function LineOf([string]$marker) { for ($i = 0; $i -lt $lines.Count; $i++) { if ($lines[$i] -match [regex]::Escape($marker)) { return $i + 1 } } return -1 }
  $hit = @($g | Where-Object { $_.rule -eq $rid } | ForEach-Object { [int]$_.start_line })
  Check 'G64a RS-TRIGGER-1 (free function accumulator) fires' ($hit -contains (LineOf 'RS-TRIGGER-1')) ($hit -join ',')
  Check 'G64b RS-TRIGGER-2 (method writing a field) fires' ($hit -contains (LineOf 'RS-TRIGGER-2')) ($hit -join ',')
  $goff = LintAll @('--rule', $rid, '--enable', $rid, '--disable', $rid)
  Check 'G64e positive control: --disable silences the rule' (@($goff | Where-Object { $_.rule -eq $rid }).Count -eq 0)
} finally {
  try { [IO.Directory]::Delete($work, $true) } catch { }
}
Write-Host ("RESULT: pass={0} fail={1}" -f $script:Pass, $script:Fail)
if ($script:Fail -gt 0) { exit 1 }
exit 0
