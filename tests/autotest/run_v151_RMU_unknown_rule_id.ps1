<#
  run_v151_RMU_unknown_rule_id.ps1 -- review-marker-malformed names the rule a
  mistyped id was most likely meant to be (v151 RMU, unknown-rule-id widening).

  An unknown id in a dl:ok marker or a drag-lint:ignore directive suppresses
  nothing. The hint now adds `Did you mean "<id>"?` when exactly one catalogue id
  is within edit distance 2 of it, and stays silent about a guess otherwise.

  CASES
  -----
    A  dl:ok empty-excpet                      -> malformed, suggests "empty-except"
    B  drag-lint:ignore empty-excpet           -> malformed, suggests "empty-except" (RED on 1.50.0-alpha: no hint at all)
    C  dl:ok no-such-rule                      -> malformed, NO suggestion (nothing close)
    D  drag-lint:ignore empty-except -- why    -> nothing (known id, then prose)
    P  positive control: --disable review-marker-malformed -> A and B gone

  Run from any CWD, pwsh 7:
    pwsh -File tests\autotest\run_v151_RMU_unknown_rule_id.ps1 -Exe <drag-lint.exe>
#>
[CmdletBinding()]
param(
  [string]$Exe = ''
)
# Defaults that need the script path are resolved HERE, not in param(): Windows PowerShell 5 run with
# -File leaves $PSScriptRoot/$MyInvocation empty inside an advanced script's param block (Repo became C:\).
if (-not $Exe) { $Exe = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe" }
if (-not (Test-Path -LiteralPath $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
. "$PSScriptRoot\lib\HermeticEngine.ps1"; $Exe = Get-HermeticEngine $Exe
$ErrorActionPreference = 'Continue'
$script:Failed = $false
function Check($n, $ok, $d = '') {
  Write-Host ("[{0}] {1} {2}" -f (@('FAIL','PASS')[[int][bool]$ok]), $n, $d) -ForegroundColor (@('Red','Green')[[int][bool]$ok])
  if (-not $ok) { $script:Failed = $true }
}

$Work = Join-Path ([IO.Path]::GetTempPath()) ('dl-rmu-' + [guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($Work) | Out-Null

$src = @(
  'unit RmuUnit;',
  '',
  'interface',
  '',
  'implementation',
  '',
  'procedure P;',
  'begin',
  '  try',
  '  except // dl:ok empty-excpet -- typo {A}',
  '  end;',
  '  try',
  '  except // drag-lint:ignore empty-excpet {B}',
  '  end;',
  '  try',
  '  except // dl:ok no-such-rule -- nothing close {C}',
  '  end;',
  '  try',
  '  except // drag-lint:ignore empty-except -- known id, then a reason {D}',
  '  end;',
  'end;',
  '',
  'end.'
)
$Unit = Join-Path $Work 'RmuUnit.pas'
[IO.File]::WriteAllText($Unit, (($src -join "`r`n") + "`r`n"), [Text.Encoding]::ASCII)
function LineOf($tag) { for ($i = 0; $i -lt $src.Count; $i++) { if ($src[$i].Contains($tag)) { return $i + 1 } }; return -1 }
$LA = LineOf '{A}'; $LB = LineOf '{B}'; $LC = LineOf '{C}'; $LD = LineOf '{D}'

function LintJson([string[]]$Extra) {
  $raw = (& $Exe lint $Unit --json @Extra 2>$null) -join "`n"
  Write-Host ('raw[0..200]: ' + $raw.Substring(0, [Math]::Min(200, $raw.Length)).Replace("`n", ' '))
  try { return @($raw | ConvertFrom-Json) } catch { Check 'lint --json parses' $false; return @() }
}
function Msg($all, $line) {
  @($all | Where-Object { $_.rule -eq 'review-marker-malformed' -and $_.start_line -eq $line } | ForEach-Object { $_.message })
}

try {
  $all = LintJson @()
  Check 'lint returned findings (non-empty answer)' ($all.Count -gt 0) "count=$($all.Count)"
  $a = Msg $all $LA; $b = Msg $all $LB; $c = Msg $all $LC; $d = Msg $all $LD
  Check "A: dl:ok typo reported (line $LA)" ($a.Count -eq 1) "n=$($a.Count)"
  Check 'A: suggests empty-except' (($a -join '') -like '*Did you mean "empty-except"?*') ($a -join '')
  Check "B: drag-lint:ignore typo reported (line $LB)" ($b.Count -eq 1) "n=$($b.Count)"
  Check 'B: suggests empty-except' (($b -join '') -like '*Did you mean "empty-except"?*') ($b -join '')
  Check "C: far-off id reported (line $LC)" ($c.Count -eq 1) "n=$($c.Count)"
  Check 'C: no guess offered' (-not (($c -join '') -like '*Did you mean*')) ($c -join '')
  Check "D: known id + reason not reported (line $LD)" ($d.Count -eq 0) "n=$($d.Count)"

  $off = LintJson @('--disable', 'review-marker-malformed')
  Check 'P: positive control -- rule disabled, A and B gone' (((Msg $off $LA).Count + (Msg $off $LB).Count) -eq 0)
} finally {
  try { [IO.Directory]::Delete($Work, $true) } catch { }
}
if ($script:Failed) { Write-Host 'RESULT: FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'RESULT: PASS' -ForegroundColor Green
exit 0
