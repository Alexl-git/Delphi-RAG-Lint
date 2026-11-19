<#
  run_v152_UNWITH_rows.ps1 -- 1.52 lane UNWITH: the unwith rows owed since 1.44 (INBOX 2026-11-06-144-wave2-owed-rows).
  (a) `lint --fix --fix-rule with-statement` is `unwith`: no --apply = a plan, exit 0, the same candidate count as
      `unwith --plan` on the same file (the route row was closed by E-UNWITH-LINTFIX; this pins it).
  (b) `unwith --plan --exclude-under <dir>` (repeatable): a project-wide plan leaves out every file under the folder.
      Fixture: UwRefused.pas lives in gen\ (21+ refused withs), UwCases.pas beside the project.
      POSITIVE CONTROL: without --exclude-under the plan holds the gen\ sites; with it none, and the UwCases sites stay.
  (c) an explicit --in file is never excluded, even under an excluded folder (the user named it).
  (d) a non-matching --exclude-under changes nothing (same counts as no flag): the filter is not a blanket drop.
  Needs the platform library (read-only); no compiler. Run against an engine built BEFORE the change: (b) is the RED
  (--exclude-under is unknown to unwith or ignored, so the gen\ sites stay).
#>
[CmdletBinding()]
param(
  [string]$Exe       = '',
  [string]$WorkDir   = "$env:TEMP\drag-lint-unwith-rows-$PID",
  [string]$LibraryDb = 'C:\Projects\.drag-lint\library-Win64.sqlite'
)
# Defaults that need the script path are resolved HERE, not in param(): Windows PowerShell 5 run with
# -File leaves $PSScriptRoot/$MyInvocation empty inside an advanced script's param block (Repo became C:\).
if (-not $Exe) { $Exe = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe" }
$ErrorActionPreference = 'Continue'
$script:Failed = $false
function Check([string]$Name, [bool]$Ok, [string]$Detail = '') {
  if ($Ok) { Write-Host "  ok   $Name" } else { $script:Failed = $true; Write-Host "  FAIL $Name $Detail" -ForegroundColor Red }
}
if (-not (Test-Path $LibraryDb)) { Write-Host "SKIP: no platform library ($LibraryDb)" -ForegroundColor Yellow; exit 0 }
if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
$Exe = (Resolve-Path $Exe).Path
$Repo = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$Fixture = Join-Path $Repo 'tests\fixtures\refactor\unwith'
function Last-Json($o) { return ($o | Where-Object { $_ -like '{*' } | Select-Object -Last 1) | ConvertFrom-Json | ForEach-Object { $_ } }

[IO.Directory]::CreateDirectory("$WorkDir\gen") | Out-Null
Copy-Item "$Fixture\*" $WorkDir -Recurse -Force
Move-Item "$WorkDir\UwRefused.pas" "$WorkDir\gen\UwRefused.pas" -Force
foreach ($f in 'UwDemo.dpr', 'UwDemo.dproj') {
  $t = [IO.File]::ReadAllText("$WorkDir\$f").Replace("UwRefused.pas", "gen\UwRefused.pas")
  [IO.File]::WriteAllText("$WorkDir\$f", $t)
}
$Db = "$WorkDir\uw.sqlite"
$env:UW_HIDDEN = ''
$null = & { $ErrorActionPreference = 'Continue'; & $Exe index --project "$WorkDir\UwDemo.dproj" --db $Db 2>&1 | ForEach-Object { "$_" } }
if ($LASTEXITCODE -ne 0) { Write-Host "FATAL: index failed" -ForegroundColor Red; exit 2 }

$All = Last-Json (& { $ErrorActionPreference = 'Continue'; & $Exe unwith --db $Db --plan --json --library-db $LibraryDb 2>$null })
$GenSites = @($All.sites | Where-Object { $_.file -like '*\gen\*' }).Count
$CaseSites = @($All.sites | Where-Object { $_.file -like '*UwCases.pas' }).Count
Check 'control: the plain plan holds gen\ sites' ($GenSites -ge 20) "gen sites $GenSites"
Check 'control: the plain plan holds UwCases sites' ($CaseSites -ge 11) "case sites $CaseSites"

# (b) --exclude-under
$Ex = Last-Json (& { $ErrorActionPreference = 'Continue'; & $Exe unwith --db $Db --plan --json --library-db $LibraryDb --exclude-under "$WorkDir\gen" 2>$null })
Check '(b) --exclude-under drops every gen\ site' (($null -ne $Ex) -and (@($Ex.sites | Where-Object { $_.file -like '*\gen\*' }).Count -eq 0)) "left $(@($Ex.sites | Where-Object { $_.file -like '*\gen\*' }).Count)"
Check '(b) ... and keeps the UwCases sites' (($null -ne $Ex) -and (@($Ex.sites | Where-Object { $_.file -like '*UwCases.pas' }).Count -eq $CaseSites))
# slash forms, as the index verb accepts them
$Ex2 = Last-Json (& { $ErrorActionPreference = 'Continue'; & $Exe unwith --db $Db --plan --json --library-db $LibraryDb --exclude-under ($WorkDir.Replace('\', '/') + '/GEN/') 2>$null })
Check '(b) forward slashes and case are accepted' (($null -ne $Ex2) -and (@($Ex2.sites | Where-Object { $_.file -like '*\gen\*' }).Count -eq 0))

# (c) an explicit --in is never excluded
$In = Last-Json (& { $ErrorActionPreference = 'Continue'; & $Exe unwith --db $Db --plan --json --library-db $LibraryDb --in "$WorkDir\gen\UwRefused.pas" --exclude-under "$WorkDir\gen" 2>$null })
Check '(c) --in under an excluded folder is still planned' (($null -ne $In) -and (@($In.sites).Count -ge 20)) "sites $(@($In.sites).Count)"

# (d) a folder that matches nothing changes nothing
$No = Last-Json (& { $ErrorActionPreference = 'Continue'; & $Exe unwith --db $Db --plan --json --library-db $LibraryDb --exclude-under "$WorkDir\nothing-here" 2>$null })
Check '(d) a non-matching --exclude-under is a no-op' (($null -ne $No) -and (@($No.sites).Count -eq @($All.sites).Count)) "$(@($No.sites).Count) vs $(@($All.sites).Count)"

# (a) the lint --fix route is the same verb
$L = & { $ErrorActionPreference = 'Continue'; & $Exe lint --fix --fix-rule with-statement --db $Db --in "$WorkDir\UwCases.pas" --library-db $LibraryDb 2>$null }
$LCode = $LASTEXITCODE
$U = & { $ErrorActionPreference = 'Continue'; & $Exe unwith --db $Db --plan --in "$WorkDir\UwCases.pas" --library-db $LibraryDb 2>$null }
$LSum = @($L | Where-Object { $_ -match '^unwith: \d+ with statement' })
$USum = @($U | Where-Object { $_ -match '^unwith: \d+ with statement' })
Check '(a) lint --fix --fix-rule with-statement (no --apply) exits 0' ($LCode -eq 0) "exit $LCode"
Check '(a) it prints the unwith summary, equal to `unwith --plan`' (($LSum.Count -eq 1) -and ($USum.Count -eq 1) -and ($LSum[0] -eq $USum[0])) "lint '$($LSum -join '|')' unwith '$($USum -join '|')'"

if ($script:Failed) { Write-Host 'run_v152_UNWITH_rows: FAILED' -ForegroundColor Red; exit 1 }
Write-Host 'run_v152_UNWITH_rows: all passed'
exit 0
