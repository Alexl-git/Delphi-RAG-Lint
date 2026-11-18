<#
  run_v152_PROJ2.ps1 -- lane v152 PROJ2.

  Ruling B9e: unit-used-by-no-unit ships default ON. A unit the program file lists
  that no other unit uses and the program code never references is reported. Exempt
  ONLY a true self-registering DI unit (an initialization section or a container
  registration). A form is NOT exempt for an initialization section: only when
  something opens it (the program code names it, or another unit names its class
  in a string, e.g. FindClass('TNamedForm')).
  O05: lint-all --project hands unit-not-in-dpr the own-roots file list; an unlisted
  closure unit in a shared folder OUTSIDE the project root is reported all the same.

  Fixture: tests\lint\unit-used-by-no-unit (app\ = project root, shared\ = outside it),
  copied to a temp folder.
  CASES
    C1  rules --json: unit-used-by-no-unit, project-wide, warning, default ON
    F1  UDeadUnit (dpr-only, no init, no registration) fires
    F2  UDeadForm (form nobody opens) fires
    F3  UDeadFormInit (form, RegisterClass in initialization, nobody opens it) fires
    N1  UDiReg (initialization + container registration) silent
    N2  UNamedForm (opened by name from UMain) silent
    N3  UMain (program code creates TMainForm) silent
    N4  UUsed (UMain uses it) silent; UShared (not listed by the dpr) silent
    D1  default run (no --rule) reports F1 under unit-used-by-no-unit (default ON)
    P1  positive control: --disable unit-used-by-no-unit -> none of F1-F3
    O1  unit-not-in-dpr reports UShared (outside the project root) exactly once
    P2  positive control: --disable unit-not-in-dpr -> UShared not reported

  pwsh -File tests\autotest\run_v152_PROJ2.ps1 -Exe <drag-lint.exe>
#>
[CmdletBinding()]
param(
  [string]$Exe = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe"
)
if (-not (Test-Path -LiteralPath $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
. "$PSScriptRoot\lib\HermeticEngine.ps1"; $Exe = Get-HermeticEngine $Exe
$ErrorActionPreference = 'Continue'
$script:Failed = $false
function Check($n, $ok, $d = '') {
  Write-Host ("[{0}] {1} {2}" -f (@('FAIL','PASS')[[int][bool]$ok]), $n, $d) -ForegroundColor (@('Red','Green')[[int][bool]$ok])
  if (-not $ok) { $script:Failed = $true }
}

$RuleId  = 'unit-used-by-no-unit'
$Fixture = Join-Path $PSScriptRoot '..\lint\unit-used-by-no-unit'
$Work = Join-Path ([IO.Path]::GetTempPath()) ('dl-v152-proj2-' + [guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($Work) | Out-Null
Copy-Item -Path (Join-Path $Fixture '*') -Destination $Work -Recurse
$Dproj = Join-Path $Work 'app\App.dproj'
$Db = Join-Path $Work 'app.sqlite'

function LintAll([string[]]$extra) {
  $raw = (& $Exe lint-all --db $Db --project $Dproj --json @extra 2>$null) -join "`n"
  Write-Host ('  raw[0..160]: ' + $raw.Substring(0, [Math]::Min(160, $raw.Length)))
  $arr = @()
  try { $arr = @($raw | ConvertFrom-Json) } catch { }
  return ,$arr
}
function UnitsOf($findings, [string]$rule) {
  return ,@($findings | Where-Object { $_.rule -eq $rule } | ForEach-Object { [IO.Path]::GetFileNameWithoutExtension('' + $_.file_path) })
}

try {
  $cat = $null
  try { $cat = (& $Exe rules --json 2>$null | ConvertFrom-Json).rules | Where-Object { $_.id -eq $RuleId } } catch { }
  Check 'C1 catalog row: project-wide, warning, default ON' ($null -ne $cat -and $cat.category -eq 'project-wide' -and $cat.default_severity -eq 'warning' -and $cat.default_enabled -eq $true) ("row=" + ($cat | Select-Object id,category,default_severity,default_enabled | ConvertTo-Json -Compress))

  $idx = (& $Exe index --project $Dproj --db $Db 2>&1) -join "`n"
  if ($LASTEXITCODE -ne 0) { Write-Host $idx; Check 'index exit 0' $false; throw 'index failed' }

  $f = LintAll @('--rule', $RuleId)
  $u = UnitsOf $f $RuleId
  $f | Where-Object { $_.rule -eq $RuleId } | ForEach-Object { Write-Host ("    {0}:{1} {2}" -f $_.file_path, $_.start_line, $_.message) }
  # positive-control: unit-used-by-no-unit
  Check 'F1 UDeadUnit fires'                         (@($u | Where-Object { $_ -eq 'UDeadUnit' }).Count -eq 1)     ($u -join ',')
  Check 'F2 UDeadForm (form nobody opens) fires'      (@($u | Where-Object { $_ -eq 'UDeadForm' }).Count -eq 1)     ($u -join ',')
  Check 'F3 UDeadFormInit (form + init, unopened) fires' (@($u | Where-Object { $_ -eq 'UDeadFormInit' }).Count -eq 1) ($u -join ',')
  Check 'N1 UDiReg (self-registering DI unit) silent' (@($u | Where-Object { $_ -eq 'UDiReg' }).Count -eq 0)        ($u -join ',')
  Check 'N2 UNamedForm (opened by name) silent'       (@($u | Where-Object { $_ -eq 'UNamedForm' }).Count -eq 0)    ($u -join ',')
  Check 'N3 UMain (program code creates the form) silent' (@($u | Where-Object { $_ -eq 'UMain' }).Count -eq 0)    ($u -join ',')
  Check 'N4 UUsed / UShared silent'                   (@($u | Where-Object { $_ -in 'UUsed','UShared' }).Count -eq 0) ($u -join ',')
  Check 'N5 exactly three findings'                   ($u.Count -eq 3) ("n=$($u.Count)")

  $all = LintAll @()
  $ua = UnitsOf $all $RuleId
  Check 'D1 default run reports UDeadUnit (rule ON by default)' (@($ua | Where-Object { $_ -eq 'UDeadUnit' }).Count -eq 1) ($ua -join ',')

  $off = LintAll @('--rule', $RuleId, '--disable', $RuleId)
  $uo = UnitsOf $off $RuleId
  Check 'P1 positive control: --disable silences F1-F3' ($uo.Count -eq 0) ("n=$($uo.Count)")

  $d = LintAll @('--rule', 'unit-not-in-dpr')
  $d | Where-Object { $_.rule -eq 'unit-not-in-dpr' } | ForEach-Object { Write-Host ("    {0}:{1} {2}" -f $_.file_path, $_.start_line, $_.message) }
  Check 'O1 unit-not-in-dpr reports UShared (outside the root) once' (@($d | Where-Object { $_.rule -eq 'unit-not-in-dpr' -and ('' + $_.message) -match '"UShared"' }).Count -eq 1) ("n=$($d.Count)")
  $d2 = LintAll @('--rule', 'unit-not-in-dpr', '--disable', 'unit-not-in-dpr')
  Check 'P2 positive control: --disable unit-not-in-dpr -> UShared not reported' (@($d2 | Where-Object { ('' + $_.message) -match '"UShared"' }).Count -eq 0) ("n=$($d2.Count)")
} finally {
  try { [IO.Directory]::Delete($Work, $true) } catch { }
}
if ($script:Failed) { Write-Host 'RESULT: FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'RESULT: PASS' -ForegroundColor Green
exit 0