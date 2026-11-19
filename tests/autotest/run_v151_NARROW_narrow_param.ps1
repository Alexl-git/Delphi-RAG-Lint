<#
  run_v151_NARROW_narrow_param.ps1 -- v151 lane NARROW (P15): narrow-param without --project

  L1  without --project the verb uses the DB's own project (<proj>\_D-RAG\P.sqlite -> <proj>) and plans
      nothing in a unit outside it (LibUse lives in ..\lib): refused 'outside-roots', never a fix.
  B1  --show-bound lists each binding with its reason (JSON "bound" array + text lines); absent without the flag.
  D1  an unpublished handler that only a .dfm assigns is refused 'dfm-bound'; its sibling is narrowed.
  Positive controls: OwnRoutine narrows (the verb is alive); a DB outside any _D-RAG folder has no own
  project, so the library routine is planned there (proves L1 is the anchor and not a vacuous filter).
#>
param(
  [string]$Exe = ''
)
# Defaults that need the script path are resolved HERE, not in param(): Windows PowerShell 5 run with
# -File leaves $PSScriptRoot/$MyInvocation empty inside an advanced script's param block (Repo became C:\).
if (-not $Exe) { $Exe = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe" }
$ErrorActionPreference = 'Stop'
$script:Failed = $false
function Check([string]$Name, [bool]$Ok, [string]$Detail = '') {
  if ($Ok) { Write-Host "  ok   $Name" } else { $script:Failed = $true; Write-Host "  FAIL $Name $Detail" -ForegroundColor Red }
}
if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
$Exe = (Resolve-Path $Exe).Path
$Fx = (Resolve-Path "$PSScriptRoot\fixtures\v151-NARROW").Path
$Tmp = Join-Path $env:TEMP ("v151_narrow_" + [guid]::NewGuid().ToString('N').Substring(0, 8))
[IO.Directory]::CreateDirectory($Tmp) | Out-Null
try {
  Copy-Item $Fx (Join-Path $Tmp 'fx') -Recurse
  $Proj = Join-Path $Tmp 'fx\proj\P.dproj'
  $Db = Join-Path $Tmp 'fx\proj\_D-RAG\P.sqlite'
  [IO.Directory]::CreateDirectory((Split-Path $Db)) | Out-Null
  & { $ErrorActionPreference = 'Continue'; & $Exe index --project $Proj --db $Db --library-db none *> (Join-Path $Tmp 'index.log') }
  if ($LASTEXITCODE -ne 0) { throw "index exit $LASTEXITCODE" }
  $Loose = Join-Path $Tmp 'loose.sqlite'
  Copy-Item $Db $Loose

  function Run-Json([string]$DbPath, [string[]]$More) {
    $o = & { $ErrorActionPreference = 'Continue'; $dlErrFile = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath((Join-Path $Tmp 'run.err')); [IO.File]::WriteAllText($dlErrFile, ''); & $Exe narrow-param --db $DbPath --library-db none --all --plan --format json @More 2>&1 | ForEach-Object { if ($_ -is [Management.Automation.ErrorRecord]) { [IO.File]::AppendAllText($dlErrFile, "$_" + [Environment]::NewLine) } else { $_ } } }
    $script:LastExit = $LASTEXITCODE
    return (($o -join "`n") | ConvertFrom-Json | ForEach-Object { $_ })
  }
  function Has([object[]]$Rows, [string]$Routine) { return @($Rows | Where-Object { $_.routine -like "*$Routine" }).Count -gt 0 }

  Write-Host 'L1 no library leak without --project'
  $p = Run-Json $Db @()
  Check 'L0 control: the project routine narrows' (Has $p.fixes 'OwnRoutine') "exit $script:LastExit"
  Check 'L1 the library routine is not a fix' (-not (Has $p.fixes 'LibRoutine'))
  Check 'L2 it is refused outside-roots, with a reason' (@($p.refused | Where-Object { $_.routine -like '*LibRoutine' -and $_.kind -eq 'outside-roots' -and $_.reason }).Count -eq 1)
  $q = Run-Json $Loose @()
  Check 'L3 control: with no own project the anchor is gone and LibRoutine is planned' (Has $q.fixes 'LibRoutine')

  Write-Host 'B1 --show-bound'
  $b = Run-Json $Db @('--show-bound')
  $own = @($b.bound | Where-Object { $_.routine -like '*OwnRoutine' })
  Check 'B1 a bound array with a row for OwnRoutine' ($own.Count -ge 1)
  Check 'B2 the row names member, class and a reason' (($own.Count -ge 1) -and ($own[0].member -eq 'Foo') -and ($own[0].class -eq 'TNpBase') -and $own[0].reason)
  Check 'B3 no bound key without the flag' ($null -eq $p.PSObject.Properties['bound'])
  $txt = (& { $ErrorActionPreference = 'Continue'; & $Exe narrow-param --db $Db --library-db none --all --plan --show-bound 2>&1 | ForEach-Object { "$_" } }) -join "`n"
  Check 'B4 the text form prints a bound line' ($txt -match '(?m)^bound\s+.*OwnRoutine.*Foo.*TNpBase')

  Write-Host 'D1 unpublished handler bound only in a .dfm'
  Check 'D1 Handler is refused dfm-bound' (@($p.refused | Where-Object { $_.routine -like '*TFrm.Handler' -and $_.kind -eq 'dfm-bound' -and $_.reason }).Count -eq 1)
  Check 'D2 control: its sibling Plain narrows' (Has $p.fixes 'TFrm.Plain')
}
finally {
  try { [IO.Directory]::Delete($Tmp, $true) } catch { Write-Host "note: scratch left: $Tmp" }
}
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
