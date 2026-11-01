<#
  run_lint_rule_cache_store_rules.ps1 -- the two whole-store project rules added
  after the rule cache (enum-ordinal-persisted, X6; dfm-event-handler-missing, G8)
  are served from the `lint <file>` rule cache, not recomputed on every run.

  THE DEFECT THIS PINS (2026-11-01)

    Both rules read every file of the project index, and `lint <file> --db` ran
    them on EVERY call, then kept only the linted file's rows. On the 164 MB
    ORM3 Micronite2027 index that was 4.9 s + 2.6 s of a 16 s single-file lint
    of COMMON\BASICS.PAS. The IDE's live runner gives a project file 8 s
    (DRagLint.Core.LintBudget), so every live lint of BASICS timed out and the
    gutter showed 0 findings while the CLI reported 15.

  C0  POSITIVE CONTROL: the fixture triggers enum-ordinal-persisted (cache off).
  C1  PARITY: identical findings with the cache off, on the filling run and on
      the hit.
  C2  the cache file HOLDS both rules (the RED check before the fix).
  C3  the second run is a HIT (DRAGLINT_PROFILE `rule-cache: hit`).
  C4  staleness: pin every value, reindex -> the finding is gone (a stale
      entry never wins).

  Run from a NEUTRAL CWD, pwsh 7.
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe",
  [string]$WorkDir = "C:\TEMP\draglint_rule_cache_store_$PID"
)
$ErrorActionPreference = 'Stop'; $script:fail = $false
function Check($n,$ok,$d){ Write-Host ("[{0}] {1}" -f (@('FAIL','PASS')[[int][bool]$ok]),$n) -ForegroundColor (@('Red','Green')[[int][bool]$ok]); if(-not $ok){ if($d){Write-Host "      $d" -ForegroundColor DarkGray}; $script:fail=$true } }
try {
  $exePath = (Resolve-Path $Exe).Path
  if (Test-Path $WorkDir) { [IO.Directory]::Delete($WorkDir, $true) }
  $src = Join-Path $WorkDir 'src'; $cache = Join-Path $WorkDir 'cache'
  New-Item -ItemType Directory -Path $src, $cache -Force | Out-Null
  $fixture = Join-Path $PSScriptRoot '..\lint-project\enum-ordinal-persisted\uEnumPersist.pas'
  Copy-Item $fixture $src
  $unit = Join-Path $src 'uEnumPersist.pas'
  $db   = Join-Path $WorkDir 'fx.sqlite'
  $env:DRAGLINT_RULE_CACHE_DIR = $cache
  Push-Location $WorkDir
  try {
    & $exePath index $src --db $db 2>&1 | Out-Null
    Check 'index exits 0' ($LASTEXITCODE -eq 0) "exit=$LASTEXITCODE"
    # the indexer may have warmed the cache: start every phase from an empty one
    Get-ChildItem $cache -File | ForEach-Object { [IO.File]::Delete($_.FullName) }

    function Lint-Rows {
      $j = & $exePath lint $unit --db $db --json 2>$null
      $a = @($j | Out-String | ConvertFrom-Json)
      return ,@($a | ForEach-Object { '{0}|{1}|{2}|{3}' -f $_.rule, $_.start_line, $_.start_col, $_.message } | Sort-Object)
    }

    $env:DRAGLINT_RULE_CACHE = '0'
    $off = Lint-Rows
    $env:DRAGLINT_RULE_CACHE = $null
    $eop = @($off | Where-Object { $_ -like 'enum-ordinal-persisted|*' })
    Check 'C0  positive control: enum-ordinal-persisted fires with the cache off' ($eop.Count -ge 1) "rows=$($off.Count)"
    Check 'C0  cache off writes nothing' (@(Get-ChildItem $cache -File).Count -eq 0)

    $fill = Lint-Rows
    $env:DRAGLINT_PROFILE = '1'
    $hitErr = & $exePath lint $unit --db $db --json 2>&1 | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] } | ForEach-Object { "$_" }
    $env:DRAGLINT_PROFILE = $null
    $hit = Lint-Rows
    Check 'C1  parity: cache off == filling run' ((($off -join "`n") -eq ($fill -join "`n"))) "off=$($off.Count) fill=$($fill.Count)"
    Check 'C1  parity: cache off == hit'         ((($off -join "`n") -eq ($hit  -join "`n"))) "off=$($off.Count) hit=$($hit.Count)"

    $cf = @(Get-ChildItem $cache -Filter 'rules-*.json' -File)
    $held = @()
    if ($cf.Count -eq 1) { $held = @((Get-Content $cf[0].FullName -Raw | ConvertFrom-Json).rules) }
    Check 'C2  one cache file written' ($cf.Count -eq 1) "files=$($cf.Count)"
    foreach ($r in 'enum-ordinal-persisted', 'dfm-event-handler-missing') {
      Check "C2  the cache holds $r" ($held -contains $r) ("holds: " + ($held -join ','))
    }
    Check 'C3  second run is a rule-cache HIT' (@($hitErr | Where-Object { $_ -match 'rule-cache: hit' }).Count -ge 1) (($hitErr | Where-Object { $_ -match 'rule-cache' }) -join ' | ')

    # C4: pin every value -> the rule must go silent after a reindex
    $txt = [IO.File]::ReadAllText($unit)
    $pinned = $txt
    foreach ($m in [regex]::Matches($txt, '\(([A-Za-z_]\w*(\s*,\s*[A-Za-z_]\w*)+)\)\s*;')) {
      $vals = $m.Groups[1].Value -split '\s*,\s*'
      $i = 0; $new = '(' + (($vals | ForEach-Object { "$_ = $($i)"; $i++ }) -join ', ') + ');'
      $pinned = $pinned.Replace($m.Value, $new)
    }
    [IO.File]::WriteAllText($unit, $pinned, [Text.Encoding]::ASCII)
    & $exePath index $src --db $db 2>&1 | Out-Null
    $after = Lint-Rows
    $env:DRAGLINT_RULE_CACHE = '0'
    $afterOff = Lint-Rows
    $env:DRAGLINT_RULE_CACHE = $null
    Check 'C4  pinned enums: enum-ordinal-persisted gone with the cache off (control)' (@($afterOff | Where-Object { $_ -like 'enum-ordinal-persisted|*' }).Count -lt $eop.Count) "before=$($eop.Count) after=$(@($afterOff | Where-Object { $_ -like 'enum-ordinal-persisted|*' }).Count)"
    Check 'C4  cached run == live run after the edit (no stale entry)' ((($after -join "`n") -eq ($afterOff -join "`n"))) "cached=$($after.Count) live=$($afterOff.Count)"
  } finally { Pop-Location }
} catch {
  Write-Host "ERROR: $_" -ForegroundColor Red; $script:fail = $true
} finally {
  $env:DRAGLINT_RULE_CACHE_DIR = $null; $env:DRAGLINT_RULE_CACHE = $null; $env:DRAGLINT_PROFILE = $null
}
if ($script:fail) { Write-Host 'RESULT: FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'RESULT: PASS' -ForegroundColor Green; exit 0
