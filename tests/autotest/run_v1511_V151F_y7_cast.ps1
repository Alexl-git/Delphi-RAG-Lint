<#
  run_v1511_V151F_y7_cast.ps1 -- run v1511 lane V151F item Y7.

  unrelated-class-cast across a unit boundary: the class tree lives in
  uTypShapes, the casts in uTypUse, so the rule can only decide from the index
  (type_ancestors + ref_types) and never from the unit's own declarations.
  The fixture project is copied to a temp folder, indexed into a temp DB by the
  engine under test, then `lint <uY7Use.pas> --db <tmp> --rule <id> --json`.

  Positive control: the same lint with --disable unrelated-class-cast must lose
  the must-fire lines (proves the assertions can fail).

  Run from a NEUTRAL CWD, pwsh 7.
#>
[CmdletBinding()]
param(
  [string]$Exe     = '',
  [string]$WorkDir = "C:\TEMP\draglint_v1511_V151F_y7_$PID"
)
# Defaults that need the script path are resolved HERE, not in param(): Windows PowerShell 5 run with
# -File leaves $PSScriptRoot/$MyInvocation empty inside an advanced script's param block (Repo became C:\).
# H01-AUTOWRAP (v152 DDFIX5): the work dir is removed in the finally below; DL_KEEP_WORKDIR=1 keeps it.
. (Join-Path $PSScriptRoot 'lib\WorkDirCleanup.ps1')
try {
if (-not $Exe) { $Exe = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe" }
$ErrorActionPreference = 'Stop'
$script:fail = $false
function Check($n, $ok, $d) {
  Write-Host ("[{0}] {1}" -f (@('FAIL', 'PASS')[[int][bool]$ok]), $n)
  if (-not $ok) { if ($d) { Write-Host "      $d" }; $script:fail = $true }
}

$rule    = 'unrelated-class-cast'
$exePath = (Resolve-Path $Exe).Path
$src     = Join-Path $PSScriptRoot 'fixtures\v1511-V151F\y7'
New-Item -ItemType Directory -Path $WorkDir -Force | Out-Null
Copy-Item (Join-Path $src '*') $WorkDir -Force
$db  = Join-Path $WorkDir 'y7.sqlite'
$use = Join-Path $WorkDir 'uY7Use.pas'

& { $ErrorActionPreference = 'Continue'; & $exePath index $WorkDir --db $db *> (Join-Path $WorkDir 'index.log') }
Check 'fixture indexed' ($LASTEXITCODE -eq 0) "index exit $LASTEXITCODE"

# must-fire / must-not-fire lines from the {HIT} / {OK} markers
$lines = [IO.File]::ReadAllLines($use)
$hit = @(); $ok = @()
for ($i = 0; $i -lt $lines.Count; $i++) {
  if ($lines[$i] -match '\{HIT\}') { $hit += ($i + 1) }
  if ($lines[$i] -match '\{OK\}')  { $ok  += ($i + 1) }
}

$raw = & { $ErrorActionPreference = 'Continue'; & $exePath lint $use --db $db --rule $rule --json 2>$null }
$txt = ($raw -join "`n")
Write-Host ("raw: " + $txt.Substring(0, [Math]::Min(200, $txt.Length)))
$found = @()
try { $found = @(($txt | ConvertFrom-Json | ForEach-Object { $_ }) | ForEach-Object { $_ }) } catch { Check 'lint output is JSON' $false $txt }
$got = @($found | Where-Object { $_.rule_id -eq $rule -or $_.rule -eq $rule } | ForEach-Object { [int]$_.start_line })
foreach ($l in $hit) { Check "fires at $l" ($got -contains $l) "got: $($got -join ',')" }
foreach ($l in $ok)  { Check "silent at $l" (-not ($got -contains $l)) "got: $($got -join ',')" }

# positive control: the rule disabled must lose the must-fire lines
$raw2 = & { $ErrorActionPreference = 'Continue'; & $exePath lint $use --db $db --rule $rule --disable $rule --json 2>$null }
$f2 = @()
try { $f2 = @((($raw2 -join "`n") | ConvertFrom-Json | ForEach-Object { $_ }) | ForEach-Object { $_ }) } catch { $f2 = @() }
$got2 = @($f2 | Where-Object { $_.rule_id -eq $rule -or $_.rule -eq $rule } | ForEach-Object { [int]$_.start_line })
Check 'positive control: --disable removes the findings' ($got2.Count -eq 0) "got: $($got2 -join ',')"

if ($script:fail) { Write-Host 'RESULT: FAIL'; exit 1 }
Write-Host 'RESULT: PASS'
exit 0
} finally { Remove-WorkDir $WorkDir -Keep:($env:DL_KEEP_WORKDIR -eq '1') }
